#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import stat
import subprocess
import time
import zipfile

P2_SHA = "7b0d77d8956f05ff907ca7463b0d787dcebf93a60426aab105be2b610e6072b0"


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def copy_tree(source: pathlib.Path, destination: pathlib.Path) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination, symlinks=True)


def ensure_macos_node_pty_spawn_helpers(runtime_destination: pathlib.Path) -> list[pathlib.Path]:
    prebuilds = (
        runtime_destination
        / "automation_host"
        / "node_modules"
        / "node-pty"
        / "prebuilds"
    )
    helpers = sorted(prebuilds.glob("darwin-*/spawn-helper"), key=lambda item: item.as_posix())
    if not helpers:
        fail("macOS node-pty spawn-helper missing from staged runtime")
    repaired: list[pathlib.Path] = []
    for helper in helpers:
        if helper.is_symlink() or not helper.is_file():
            fail(f"macOS node-pty spawn-helper is not a regular file: {helper}")
        mode = stat.S_IMODE(helper.stat().st_mode)
        helper.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        if not os.access(helper, os.X_OK):
            fail(f"macOS node-pty spawn-helper is not executable after staging repair: {helper}")
        repaired.append(helper)
    return repaired


def locate_app(root: pathlib.Path, platform: str) -> tuple[pathlib.Path, str]:
    if platform == "windows":
        roots = [path for path in root.glob("build/windows/**/runner/Release") if path.is_dir()]
        for directory in sorted(roots, key=lambda value: len(value.parts), reverse=True):
            exes = [p for p in directory.glob("*.exe") if not p.name.lower().startswith(("uninstall", "vc_redist"))]
            if exes:
                chosen = sorted(exes, key=lambda p: p.name)[0]
                return directory, chosen.relative_to(directory).as_posix()
        fail("Flutter Windows release output not found")
    if platform == "linux":
        roots = [path for path in root.glob("build/linux/**/release/bundle") if path.is_dir()]
        for directory in sorted(roots, key=lambda value: len(value.parts), reverse=True):
            candidates = [
                p for p in directory.iterdir()
                if p.is_file() and os.access(p, os.X_OK) and p.name not in {"libflutter_linux_gtk.so"}
            ]
            if candidates:
                chosen = sorted(candidates, key=lambda p: p.name)[0]
                return directory, chosen.relative_to(directory).as_posix()
        fail("Flutter Linux release bundle not found")
    apps = sorted(root.glob("build/macos/Build/Products/Release/*.app"), key=lambda p: p.name)
    if not apps:
        fail("Flutter macOS release .app not found")
    app = apps[0]
    macos_dir = app / "Contents/MacOS"
    executables = [p for p in macos_dir.iterdir() if p.is_file() and os.access(p, os.X_OK)] if macos_dir.is_dir() else []
    if not executables:
        fail("macOS app executable not found")
    executable = sorted(executables, key=lambda p: p.name)[0]
    return app, f"{app.name}/Contents/MacOS/{executable.name}"


def hash_rows(root: pathlib.Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for path in sorted(root.rglob("*"), key=lambda p: p.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            target = os.readlink(path).encode("utf-8")
            rows.append({"path": relative, "kind": "symlink", "target": os.readlink(path), "sha256": sha_bytes(target), "bytes": len(target)})
        elif path.is_file():
            rows.append({"path": relative, "kind": "file", "sha256": sha_file(path), "bytes": path.stat().st_size})
    return rows


def zip_payload(source: pathlib.Path, archive: pathlib.Path) -> None:
    archive.parent.mkdir(parents=True, exist_ok=True)
    temporary = archive.with_suffix(archive.suffix + ".tmp")
    temporary.unlink(missing_ok=True)
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for path in sorted(source.rglob("*"), key=lambda p: p.relative_to(source).as_posix()):
            relative = path.relative_to(source).as_posix()
            if path.is_dir() and not path.is_symlink():
                continue
            info = zipfile.ZipInfo(relative, (2020, 1, 1, 0, 0, 0))
            info.create_system = 3
            if path.is_symlink():
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                bundle.writestr(info, os.readlink(path).encode("utf-8"))
            else:
                mode = 0o755 if os.access(path, os.X_OK) else 0o644
                info.external_attr = (stat.S_IFREG | mode) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                bundle.writestr(info, path.read_bytes())
    temporary.replace(archive)


def ad_hoc_sign_macos(
    app_bundle: pathlib.Path,
    p1a_native: pathlib.Path,
    runtime_executables: list[pathlib.Path] | tuple[pathlib.Path, ...] = (),
) -> str:
    def execute(argv: list[str]) -> None:
        result = subprocess.run(argv, text=True, encoding="utf-8", errors="replace", capture_output=True)
        if result.returncode:
            fail(f"macOS ad-hoc code signing failed ({result.returncode}): {' '.join(argv)}\n{result.stdout}\n{result.stderr}")

    subprocess.run(["xattr", "-cr", str(app_bundle)], text=True, encoding="utf-8", errors="replace", capture_output=True)
    for binary in sorted((path for path in p1a_native.rglob("*") if path.is_file() and os.access(path, os.X_OK)), key=lambda item: item.as_posix()):
        execute(["codesign", "--force", "--sign", "-", "--timestamp=none", str(binary)])
        execute(["codesign", "--verify", "--strict", "--verbose=2", str(binary)])
    for binary in sorted(runtime_executables, key=lambda item: item.as_posix()):
        if not binary.is_file() or not os.access(binary, os.X_OK):
            fail(f"macOS staged runtime executable is invalid before signing: {binary}")
        execute(["codesign", "--force", "--sign", "-", "--timestamp=none", str(binary)])
        execute(["codesign", "--verify", "--strict", "--verbose=2", str(binary)])
    execute(["codesign", "--force", "--deep", "--sign", "-", "--timestamp=none", str(app_bundle)])
    execute(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app_bundle)])
    return "ad-hoc-resigned-after-runtime-staging"


def write_launchers(payload: pathlib.Path, platform: str, app_executable: str, source_commit: str, source_tree: str) -> None:
    if platform == "windows":
        launcher = payload / "Launch-Kristin-OwnerRisk-QA.ps1"
        launcher.write_text(r'''param([switch]$AsAdministrator)
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
'''.replace('SOURCE_COMMIT', source_commit).replace('SOURCE_TREE', source_tree).replace('P2_SHA', P2_SHA).replace('APP_EXECUTABLE', app_executable.replace('/', '\\')), encoding="utf-8")
    elif platform == "linux":
        launcher = payload / "launch-kristin-owner-risk-qa.sh"
        launcher.write_text(f'''#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
APP_ROOT="$ROOT/app"
RUNTIME="$APP_ROOT/runtime/p2/current"
"$RUNTIME/node/node" "$RUNTIME/tools/configure-owner-risk-runtime.mjs" --root "$RUNTIME" --platform linux --source-commit {source_commit} --source-tree {source_tree} --p2-package-sha256 {P2_SHA} --p1-contract "$RUNTIME/contracts/p1_authority_service_contract_v1.dart"
exec "$APP_ROOT/{app_executable}" "$@"
''', encoding="utf-8")
        launcher.chmod(0o755)
    else:
        app_name = app_executable.split('/', 1)[0]
        app_binary = app_executable
        runtime_rel = f"app/{app_name}/Contents/MacOS/runtime/p2/current"
        launcher = payload / "launch-kristin-owner-risk-qa.command"
        launcher.write_text(f'''#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
APP_BUNDLE="$ROOT/app/{app_name}"
RUNTIME="$ROOT/{runtime_rel}"
"$RUNTIME/node/node" "$RUNTIME/tools/configure-owner-risk-runtime.mjs" --root "$RUNTIME" --platform macos --source-commit {source_commit} --source-tree {source_tree} --p2-package-sha256 {P2_SHA} --p1-contract "$RUNTIME/contracts/p1_authority_service_contract_v1.dart"
# Runtime configuration is relocation-specific and changes files inside the app.
# Re-seal the QA app ad hoc after that write so macOS never sees a stale signature.
/usr/bin/xattr -cr "$APP_BUNDLE" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
exec "$ROOT/app/{app_binary}" "$@"
''', encoding="utf-8")
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
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()
    runtime_stage = pathlib.Path(args.runtime_stage).resolve()
    output_dir = pathlib.Path(args.output_dir).resolve()
    for value, length, label in ((args.source_commit, 40, "source commit"), (args.source_tree, 40, "source tree")):
        if len(value) != length or any(ch not in "0123456789abcdef" for ch in value):
            fail(f"invalid {label}")
    if not (runtime_stage / "runtime/runtime-manifest.v3.json").is_file():
        fail("runtime stage invalid")
    app_source, app_executable = locate_app(root, args.platform)
    payload = output_dir / f"payload-{args.platform}"
    if payload.exists():
        shutil.rmtree(payload)
    payload.mkdir(parents=True)
    app_destination = payload / "app"
    if args.platform == "macos":
        app_destination.mkdir()
        copy_tree(app_source, app_destination / app_source.name)
        runtime_destination = app_destination / app_source.name / (
            "Contents/Resources/runtime/p2/current"
            if args.product_current_account
            else "Contents/MacOS/runtime/p2/current"
        )
    else:
        copy_tree(app_source, app_destination)
        runtime_destination = app_destination / "runtime/p2/current"
    copy_tree(runtime_stage / "runtime", runtime_destination)
    macos_spawn_helpers: list[pathlib.Path] = []
    if args.platform == "macos":
        macos_spawn_helpers = ensure_macos_node_pty_spawn_helpers(runtime_destination)
        windows_only_conpty = (
            runtime_destination
            / "automation_host"
            / "node_modules"
            / "node-pty"
            / "third_party"
            / "conpty"
        )
        if windows_only_conpty.exists():
            shutil.rmtree(windows_only_conpty)
    p1a_destination = payload / "p1a-native"
    copy_tree(runtime_stage / "p1a-native", p1a_destination)
    qa_code_signing = "unsigned-owner-risk-qa"
    if args.platform == "macos":
        qa_code_signing = ad_hoc_sign_macos(
            app_destination / app_source.name,
            p1a_destination,
            runtime_executables=macos_spawn_helpers,
        )
    if not args.product_current_account:
        write_launchers(payload, args.platform, app_executable, args.source_commit, args.source_tree)

    qa_dir = payload / "qa"
    if not args.product_current_account:
        qa_dir.mkdir(parents=True)
    if not args.product_current_account:
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
        "macosNodePtySpawnHelpers": [
            item.relative_to(runtime_destination).as_posix()
            for item in macos_spawn_helpers
        ],
        "appExecutable": app_executable,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    metadata_name = "OWNER_RUNTIME_METADATA.json" if args.product_current_account else "QA_BUILD_METADATA.json"
    (payload / metadata_name).write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    manifest = {
        **metadata,
        "files": hash_rows(payload),
    }
    manifest_name = "OWNER_RUNTIME_MANIFEST.json" if args.product_current_account else "QA_BUNDLE_MANIFEST.json"
    (payload / manifest_name).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    archive_name = (
        f"KRISTIN_OWNER_MODE_{args.platform.upper()}_{args.source_commit[:12]}.zip"
        if args.product_current_account
        else f"KRISTIN_P1_P2_OWNER_RISK_QA_{args.platform.upper()}_V71R12_{args.source_commit[:12]}.zip"
    )
    archive = output_dir / archive_name
    zip_payload(payload, archive)
    digest = sha_file(archive)
    archive.with_name(archive.name + ".sha256").write_text(f"{digest}  {archive.name}\n", encoding="utf-8")
    result = {**metadata, "archive": str(archive), "archiveSha256": digest, "bytes": archive.stat().st_size}
    (output_dir / f"result-{args.platform}.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
