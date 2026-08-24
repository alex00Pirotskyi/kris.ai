#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import pathlib
import shutil
import time

from v70_package_platform_support import (
    P2_SHA,
    ad_hoc_sign_macos,
    copy_tree,
    ensure_macos_node_pty_spawn_helpers,
    fail,
    hash_rows,
    locate_app,
    p2_runtime_destination,
    prepare_windows_browser_sandbox_acl,
    product_runtime_destinations,
    sha_file,
    verify_runtime_manifest_bindings,
    zip_payload,
)


def write_launchers(
    payload: pathlib.Path,
    platform: str,
    app_executable: str,
    source_commit: str,
    source_tree: str,
) -> None:
    if platform == "windows":
        launcher = payload / "Launch-Kristin-OwnerRisk-QA.ps1"
        launcher.write_text(
            r'''param([switch]$AsAdministrator)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppRoot = Join-Path $Root 'app'
$Runtime = Join-Path $AppRoot 'runtime\p2\current'
$Node = Join-Path $Runtime 'node\node.exe'
$Config = Join-Path $Runtime 'tools\configure-owner-risk-runtime.mjs'
$Contract = Join-Path $Runtime 'contracts\p1_authority_service_contract_v1.dart'
& $Node $Config --root $Runtime --platform windows --source-commit SOURCE_COMMIT --source-tree SOURCE_TREE --p2-package-sha256 P2_SHA --p1-contract $Contract
if ($LASTEXITCODE -ne 0) { throw 'owner-risk runtime configuration failed' }
$Executable = Join-Path $AppRoot 'APP_EXECUTABLE'
if (-not (Test-Path -LiteralPath $Executable)) { throw "app executable missing: $Executable" }
$arguments = @{ FilePath = $Executable; WorkingDirectory = $AppRoot }
if ($AsAdministrator) { $arguments['Verb'] = 'RunAs' }
Start-Process @arguments
'''.replace("SOURCE_COMMIT", source_commit)
            .replace("SOURCE_TREE", source_tree)
            .replace("P2_SHA", P2_SHA)
            .replace("APP_EXECUTABLE", app_executable.replace("/", "\\")),
            encoding="utf-8",
        )
    elif platform == "linux":
        launcher = payload / "launch-kristin-owner-risk-qa.sh"
        launcher.write_text(
            f'''#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
APP_ROOT="$ROOT/app"
RUNTIME="$APP_ROOT/runtime/p2/current"
"$RUNTIME/node/node" "$RUNTIME/tools/configure-owner-risk-runtime.mjs" --root "$RUNTIME" --platform linux --source-commit {source_commit} --source-tree {source_tree} --p2-package-sha256 {P2_SHA} --p1-contract "$RUNTIME/contracts/p1_authority_service_contract_v1.dart"
exec "$APP_ROOT/{app_executable}" "$@"
''',
            encoding="utf-8",
        )
        launcher.chmod(0o755)
    else:
        app_name = app_executable.split("/", 1)[0]
        app_binary = app_executable
        launcher = payload / "launch-kristin-owner-risk-qa.command"
        launcher.write_text(
            f'''#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
APP_BUNDLE="$ROOT/app/{app_name}"
RUNTIME="$APP_BUNDLE/Contents/Resources/runtime/p2/current"
"$RUNTIME/node/node" "$RUNTIME/tools/configure-owner-risk-runtime.mjs" --root "$RUNTIME" --platform macos --source-commit {source_commit} --source-tree {source_tree} --p2-package-sha256 {P2_SHA} --p1-contract "$RUNTIME/contracts/p1_authority_service_contract_v1.dart"
/usr/bin/xattr -cr "$APP_BUNDLE" 2>/dev/null || true
/usr/bin/codesign --force --sign - --timestamp=none "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
exec "$ROOT/app/{app_binary}" "$@"
''',
            encoding="utf-8",
        )
        launcher.chmod(0o755)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--platform", required=True, choices=("windows", "macos", "linux"))
    parser.add_argument("--runtime-stage", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--source-tree", required=True)
    parser.add_argument("--workflow-run-id", default="local")
    parser.add_argument("--workflow-run-attempt", default="1")
    parser.add_argument("--product-current-account", action="store_true")
    parser.add_argument("--browser-runtime-stage")
    args = parser.parse_args()

    root = pathlib.Path(args.project).resolve()
    runtime_stage = pathlib.Path(args.runtime_stage).resolve()
    output_dir = pathlib.Path(args.output_dir).resolve()
    browser_runtime_stage = pathlib.Path(args.browser_runtime_stage).resolve() if args.browser_runtime_stage else None
    for value, length, label in (
        (args.source_commit, 40, "source commit"),
        (args.source_tree, 40, "source tree"),
    ):
        if len(value) != length or any(ch not in "0123456789abcdef" for ch in value):
            fail(f"invalid {label}")
    if not (runtime_stage / "runtime/runtime-manifest.v3.json").is_file():
        fail("runtime stage invalid")
    if args.product_current_account:
        if browser_runtime_stage is None:
            fail("product current-account package requires browser runtime stage")
        if not (browser_runtime_stage / "browser-runtime-manifest.v1.json").is_file():
            fail("browser runtime stage invalid")
    elif browser_runtime_stage is not None:
        fail("browser runtime stage is product-only")

    app_source, app_executable = locate_app(root, args.platform)
    payload = output_dir / f"payload-{args.platform}"
    if payload.exists():
        shutil.rmtree(payload)
    payload.mkdir(parents=True)
    app_destination = payload / "app"
    browser_runtime_destination: pathlib.Path | None = None

    if args.platform == "macos":
        app_destination.mkdir()
        copy_tree(app_source, app_destination / app_source.name)
    else:
        copy_tree(app_source, app_destination)

    if args.product_current_account:
        runtime_destination, browser_runtime_destination = product_runtime_destinations(
            app_destination, app_source, args.platform
        )
    else:
        runtime_destination = p2_runtime_destination(app_destination, app_source, args.platform)

    copy_tree(runtime_stage / "runtime", runtime_destination)
    macos_spawn_helpers: list[pathlib.Path] = []
    if args.platform == "macos":
        macos_spawn_helpers = ensure_macos_node_pty_spawn_helpers(runtime_destination)
        windows_only_conpty = runtime_destination / "automation_host/node_modules/node-pty/third_party/conpty"
        if windows_only_conpty.exists():
            shutil.rmtree(windows_only_conpty)

    if args.product_current_account:
        assert browser_runtime_stage is not None
        assert browser_runtime_destination is not None
        copy_tree(browser_runtime_stage, browser_runtime_destination)
        prepare_windows_browser_sandbox_acl(
            browser_runtime_destination / "browser", platform=args.platform
        )

    p1a_destination = payload / "p1a-native"
    copy_tree(runtime_stage / "p1a-native", p1a_destination)

    qa_code_signing = "unsigned-owner-risk-qa"
    final_runtime_identity: dict[str, object] = {}
    if args.platform == "macos":
        signing = ad_hoc_sign_macos(
            app_destination / app_source.name,
            p1a_destination,
            runtime_destination,
            browser_runtime_destination,
            runtime_executables=macos_spawn_helpers,
        )
        qa_code_signing = str(signing["classification"])
        final_runtime_identity = {
            "p2": signing["p2"],
            "p3": signing["p3"],
        }
    else:
        final_runtime_identity["p2"] = verify_runtime_manifest_bindings(
            runtime_destination, "runtime-manifest.v3.json"
        )
        if browser_runtime_destination is not None:
            final_runtime_identity["p3"] = verify_runtime_manifest_bindings(
                browser_runtime_destination, "browser-runtime-manifest.v1.json"
            )

    if not args.product_current_account:
        write_launchers(payload, args.platform, app_executable, args.source_commit, args.source_tree)

    qa_dir = payload / "qa"
    if not args.product_current_account:
        qa_dir.mkdir(parents=True)
        for relative in ("OWNER_RISK_QA_SHIPMENT.md", "config/p1_p2_owner_risk_qa.v1.json"):
            source = root / relative
            if source.is_file():
                shutil.copy2(source, qa_dir / source.name)
        governed_qa = root / "qa/v71r12"
        if not governed_qa.is_dir():
            fail("governed V71 QA handoff directory missing")
        for source in sorted(governed_qa.rglob("*"), key=lambda item: item.relative_to(governed_qa).as_posix()):
            if source.is_dir():
                continue
            relative = source.relative_to(governed_qa)
            target = qa_dir / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        required_qa = (
            qa_dir / "TRI_PLATFORM_TEST_MATRIX.md",
            qa_dir / "QA_HANDOFF.md",
            qa_dir / "KNOWN_LIMITATIONS.md",
            qa_dir / "SHIPMENT_CLASSIFICATION.md",
            qa_dir / "P1_P2_FEATURE_COVERAGE.json",
        )
        if any(not item.is_file() for item in required_qa):
            fail("complete QA matrix/coverage payload missing")

    metadata = {
        "schemaVersion": "1.0.0",
        "bundleType": "kristin-current-account-owner-product-v1" if args.product_current_account else "kristin-p1-p2-owner-risk-qa-v71r12",
        "platform": args.platform,
        "sourceCommit": args.source_commit,
        "sourceTree": args.source_tree,
        "p2PackageSha256": P2_SHA,
        "workflowRunId": str(args.workflow_run_id),
        "workflowRunAttempt": str(args.workflow_run_attempt),
        "securityEvidenceWaived": True,
        "rootOrAdministratorAuthorityAccepted": True,
        "formalSecurityCompletion": False,
        "productionReleaseEligible": False,
        "functionalOwnerModeEligible": bool(args.product_current_account),
        "secureIsolationCertified": False,
        "qaShipmentEligible": not args.product_current_account,
        "allThreePlatformArtifactsRequired": True,
        "manualQaMatrixIncluded": not args.product_current_account,
        "p1P2FeatureCoverageIncluded": not args.product_current_account,
        "qaCodeSigning": qa_code_signing,
        "macosNodePtySpawnHelpers": [item.relative_to(runtime_destination).as_posix() for item in macos_spawn_helpers],
        "runtimeIdentity": final_runtime_identity,
        "browserRuntimeIncluded": bool(args.product_current_account),
        "browserRuntimeManifestSha256": (
            sha_file(browser_runtime_destination / "browser-runtime-manifest.v1.json")
            if browser_runtime_destination is not None
            else None
        ),
        "appExecutable": app_executable,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    metadata_name = "OWNER_RUNTIME_METADATA.json" if args.product_current_account else "QA_BUILD_METADATA.json"
    (payload / metadata_name).write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
    )
    manifest = {**metadata, "files": hash_rows(payload)}
    manifest_name = "OWNER_RUNTIME_MANIFEST.json" if args.product_current_account else "QA_BUNDLE_MANIFEST.json"
    (payload / manifest_name).write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
    )

    archive_name = (
        f"KRISTIN_OWNER_MODE_{args.platform.upper()}_{args.source_commit[:12]}.zip"
        if args.product_current_account
        else f"KRISTIN_P1_P2_OWNER_RISK_QA_{args.platform.upper()}_V71R12_{args.source_commit[:12]}.zip"
    )
    archive = output_dir / archive_name
    zip_payload(payload, archive)
    digest = sha_file(archive)
    archive.with_name(archive.name + ".sha256").write_text(
        f"{digest}  {archive.name}\n", encoding="utf-8", newline="\n"
    )
    result = {**metadata, "archive": str(archive), "archiveSha256": digest, "bytes": archive.stat().st_size}
    (output_dir / f"result-{args.platform}.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
