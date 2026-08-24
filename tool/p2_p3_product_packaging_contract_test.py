#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGER = ROOT / "tool/v70_package_platform.py"
SUPPORT = ROOT / "tool/v70_package_platform_support.py"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"P2_P3_PRODUCT_PACKAGING_FAIL {message}")


def load_module(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    require(spec is not None and spec.loader is not None, f"{name} import spec missing")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_file(path: pathlib.Path, payload: bytes, *, executable: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    if os.name != "nt":
        path.chmod(0o755 if executable else 0o644)


def write_json(path: pathlib.Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")


def file_row(support, root: pathlib.Path, path: pathlib.Path, *, executable: bool = False) -> dict:
    return {
        "kind": "file",
        "path": path.relative_to(root).as_posix(),
        "sha256": support.sha_file(path),
        "bytes": path.stat().st_size,
        "executable": executable,
    }


def directory_row(support, root: pathlib.Path, path: pathlib.Path) -> dict:
    return {
        "kind": "directory",
        "path": path.relative_to(root).as_posix(),
        "treeSha256": support.tree_sha256(path),
    }


def build_fixture(support, root: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path, pathlib.Path, pathlib.Path]:
    app = root / "app/Kristin.app"
    p2 = app / "Contents/Resources/runtime/p2/current"
    p3 = app / "Contents/Resources/runtime/p3/current"
    p1a = root / "p1a-native"
    p1a.mkdir(parents=True)
    write_file(p1a / "authority", b"\xcf\xfa\xed\xfeP1A", executable=True)

    node = p2 / "node/node"
    host = p2 / "automation_host/src/host.mjs"
    launcher = p2 / "automation_host/src/owner-risk-launcher.mjs"
    native = p2 / "automation_host/node_modules/node-pty/prebuilds/darwin-arm64/pty.node"
    spawn = p2 / "automation_host/node_modules/node-pty/prebuilds/darwin-arm64/spawn-helper"
    contract = p2 / "contracts/p1_authority_service_contract_v1.dart"
    policy = p2 / "provisioning/worker-policy.v2.json"
    provisioning = p2 / "provisioning/environment.v1.json"
    write_file(node, b"\xcf\xfa\xed\xfeP2NODE", executable=True)
    write_file(host, b"HOST")
    write_file(launcher, b"LAUNCHER", executable=True)
    write_file(native, b"\xcf\xfa\xed\xfePTY", executable=True)
    write_file(spawn, b"\xcf\xfa\xed\xfeSPAWN", executable=True)
    write_file(contract, b"CONTRACT")
    write_json(provisioning, {"schemaVersion": "1.0.0"})
    write_json(
        policy,
        {
            "nodeSha256": support.sha_file(node),
            "hostScriptSha256": support.sha_file(host),
            "launcherSha256": support.sha_file(launcher),
        },
    )
    p2_resources = {
        "nodeExecutable": file_row(support, p2, node, executable=True),
        "automationHost": file_row(support, p2, host),
        "automationHostRoot": directory_row(support, p2, p2 / "automation_host"),
        "restrictedWorkerLauncher": file_row(support, p2, launcher, executable=True),
        "restrictedWorkerPolicy": file_row(support, p2, policy),
        "runtimeProvisioning": file_row(support, p2, provisioning),
    }
    p2_manifest = {
        "schemaVersion": "3.0.0",
        "bundleType": "kristin-p2-application-runtime-v3",
        "identity": {
            "sourceCommit": "a" * 40,
            "sourceTree": "b" * 40,
            "runtimeBuildSha256": "",
            "p1AuthorityServiceContractSha256": support.sha_file(contract),
        },
        "resources": p2_resources,
    }
    p2_manifest["identity"]["runtimeBuildSha256"] = support._p2_build_sha(p2_manifest)
    write_json(p2 / "runtime-manifest.v3.json", p2_manifest)

    p3_node = p3 / "node/node"
    worker = p3 / "automation_host/src/browser-runtime.mjs"
    lock = p3 / "automation_host/package-lock.json"
    browser = p3 / "browser/Chromium.app/Contents/MacOS/Chromium"
    framework_bundle = (
        p3
        / "browser/Chromium.app/Contents/Frameworks/Google Chrome for Testing Framework.framework"
    )
    framework_root = framework_bundle / "Google Chrome for Testing Framework"
    framework_versioned = (
        framework_bundle
        / "Versions/140.0.7339.0/Google Chrome for Testing Framework"
    )
    framework = framework_bundle / "Versions/140.0.7339.0/Libraries/libfixture.dylib"
    write_file(p3_node, b"\xcf\xfa\xed\xfeP3NODE", executable=True)
    write_file(worker, b"WORKER")
    write_file(lock, b"LOCK")
    write_file(browser, b"\xcf\xfa\xed\xfeBROWSER", executable=True)
    write_file(framework_root, b"\xcf\xfa\xed\xfeFRAMEWORK-ROOT", executable=True)
    write_file(framework_versioned, b"\xcf\xfa\xed\xfeFRAMEWORK-VERSION", executable=True)
    write_file(framework, b"\xcf\xfa\xed\xfeFRAMEWORK-DYLIB", executable=True)
    p3_resources = {
        "nodeExecutable": file_row(support, p3, p3_node, executable=True),
        "browserWorker": file_row(support, p3, worker),
        "automationHostRoot": directory_row(support, p3, p3 / "automation_host"),
        "packageLock": file_row(support, p3, lock),
        "browserExecutable": file_row(support, p3, browser, executable=True),
        "browserRoot": directory_row(support, p3, p3 / "browser"),
    }
    p3_manifest = {
        "schemaVersion": "1.0.0",
        "bundleType": "kristin-p3-browser-runtime-v1",
        "identity": {
            "sourceCommit": "a" * 40,
            "sourceTree": "b" * 40,
            "runtimeBuildSha256": "",
            "packageLockSha256": support.sha_file(lock),
            "browserRevision": "fixture-revision",
        },
        "resources": p3_resources,
    }
    p3_manifest["identity"]["runtimeBuildSha256"] = support._p3_build_sha(p3_manifest)
    write_json(p3 / "browser-runtime-manifest.v1.json", p3_manifest)
    return app, p1a, p2, p3


def main() -> int:
    sys.path.insert(0, str(ROOT / "tool"))
    packager = load_module(PACKAGER, "kristin_product_packager")
    support = load_module(SUPPORT, "kristin_product_packager_support_test")

    with tempfile.TemporaryDirectory() as temporary:
        root = pathlib.Path(temporary)
        app_destination = root / "app"
        app_source = root / "Kristin.app"
        p2, p3 = packager.product_runtime_destinations(app_destination, app_source, "macos")
        require(p2.as_posix().endswith("Kristin.app/Contents/Resources/runtime/p2/current"), "macOS P2 destination drift")
        require(p3.as_posix().endswith("Kristin.app/Contents/Resources/runtime/p3/current"), "macOS P3 destination drift")
        p2, p3 = packager.product_runtime_destinations(app_destination, app_source, "windows")
        require(p2 == app_destination / "runtime/p2/current", "Windows/Linux P2 destination drift")
        require(p3 == app_destination / "runtime/p3/current", "Windows/Linux P3 destination drift")

        browser = root / "browser"
        browser.mkdir()
        seen: dict[str, list[str]] = {}

        def fake_acl_runner(argv, **kwargs):
            seen["argv"] = list(argv)
            return subprocess.CompletedProcess(argv, 0, "", "")

        require(packager.prepare_windows_browser_sandbox_acl(browser, platform="windows", runner=fake_acl_runner), "Windows ACL repair not invoked")
        command = " ".join(seen["argv"])
        require("*S-1-15-2-1:(OI)(CI)(RX)" in command, "AppContainer ACL missing")
        require("*S-1-15-2-2:(OI)(CI)(RX)" in command, "restricted AppContainer ACL missing")
        require(packager.prepare_windows_browser_sandbox_acl(browser, platform="linux", runner=fake_acl_runner) is False, "ACL repair must be Windows-only")

    with tempfile.TemporaryDirectory() as temporary:
        root = pathlib.Path(temporary)
        app, p1a, p2, p3 = build_fixture(support, root)
        original_p2 = json.loads((p2 / "runtime-manifest.v3.json").read_text())["identity"]["runtimeBuildSha256"]
        original_p3 = json.loads((p3 / "browser-runtime-manifest.v1.json").read_text())["identity"]["runtimeBuildSha256"]
        framework_bundle = (
            p3
            / "browser/Chromium.app/Contents/Frameworks/Google Chrome for Testing Framework.framework"
        )
        framework_root = framework_bundle / "Google Chrome for Testing Framework"
        framework_versioned = (
            framework_bundle
            / "Versions/140.0.7339.0/Google Chrome for Testing Framework"
        )
        framework_dylib = framework_bundle / "Versions/140.0.7339.0/Libraries/libfixture.dylib"
        require(
            support._macos_codesign_target(framework_root) == framework_versioned,
            "macOS framework primary executable must resolve to concrete versioned Mach-O",
        )
        require(
            support._macos_codesign_target(framework_dylib) == framework_dylib,
            "macOS framework nested dylib must remain a leaf signing target",
        )
        mutated = False
        commands: list[list[str]] = []

        def fake_sign_runner(argv, **kwargs):
            nonlocal mutated
            commands.append(list(argv))
            if argv[0] == "codesign" and "--force" in argv:
                target = pathlib.Path(argv[-1])
                if target == framework_bundle or target == framework_root:
                    return subprocess.CompletedProcess(argv, 1, "", "bundle format is ambiguous")
            if argv[0] == "codesign" and "--deep" in argv and "--force" in argv and not mutated:
                mutated = True
                for relative in (
                    "node/node",
                    "automation_host/node_modules/node-pty/prebuilds/darwin-arm64/pty.node",
                    "automation_host/node_modules/node-pty/prebuilds/darwin-arm64/spawn-helper",
                ):
                    target = p2 / relative
                    target.write_bytes(target.read_bytes() + b"SIGNED")
                for relative in (
                    "node/node",
                    "browser/Chromium.app/Contents/MacOS/Chromium",
                    "browser/Chromium.app/Contents/Frameworks/Google Chrome for Testing Framework.framework/Google Chrome for Testing Framework",
                    "browser/Chromium.app/Contents/Frameworks/Google Chrome for Testing Framework.framework/Versions/140.0.7339.0/Google Chrome for Testing Framework",
                    "browser/Chromium.app/Contents/Frameworks/Google Chrome for Testing Framework.framework/Versions/140.0.7339.0/Libraries/libfixture.dylib",
                ):
                    target = p3 / relative
                    target.write_bytes(target.read_bytes() + b"SIGNED")
            return subprocess.CompletedProcess(argv, 0, "", "")

        result = support.ad_hoc_sign_macos(app, p1a, p2, p3, runner=fake_sign_runner)
        require(result["classification"] == "ad-hoc-nested-signed-manifest-rebound-outer-sealed", "macOS signing classification invalid")
        require(result["p2"]["runtimeBuildSha256"] != original_p2, "P2 runtime identity was not rebound")
        require(result["p3"]["runtimeBuildSha256"] != original_p3, "P3 runtime identity was not rebound")
        require(support.verify_runtime_manifest_bindings(p2, "runtime-manifest.v3.json") == result["p2"], "final P2 manifest does not bind final bytes")
        require(support.verify_runtime_manifest_bindings(p3, "browser-runtime-manifest.v1.json") == result["p3"], "final P3 manifest does not bind final bytes")
        policy = json.loads((p2 / "provisioning/worker-policy.v2.json").read_text())
        require(policy["nodeSha256"] == support.sha_file(p2 / "node/node"), "P2 worker policy node binding stale")
        app_signs = [command for command in commands if command[0] == "codesign" and "--force" in command and str(app) in command]
        require(len(app_signs) == 2, "expected pre-rebind deep sign plus final outer seal")
        require("--deep" in app_signs[0], "pre-rebind app sign must be deep")
        require("--deep" not in app_signs[-1], "final outer seal must not mutate nested runtime bytes")
        framework_leaf_signs = [
            command
            for command in commands
            if command[0] == "codesign"
            and "--force" in command
            and command[-1] == str(framework_versioned)
        ]
        require(len(framework_leaf_signs) == 1, "concrete framework Mach-O must be signed exactly once")
        require(
            not any(command[0] == "codesign" and "--force" in command and command[-1] == str(framework_bundle) for command in commands),
            "ambiguous framework container must never be a direct signing target",
        )
        chrome_app = p3 / "browser/Chromium.app"
        chrome_signs = [
            command
            for command in commands
            if command[0] == "codesign" and "--force" in command and command[-1] == str(chrome_app)
        ]
        require(len(chrome_signs) == 1 and "--deep" in chrome_signs[0], "Chromium app must be signed after nested code")
        require(commands.index(framework_leaf_signs[0]) < commands.index(chrome_signs[0]), "framework leaf must be signed before Chromium app")
        require(commands.index(chrome_signs[0]) < commands.index(app_signs[0]), "Chromium app must be signed before Kristin outer app")

        payload = root / "payload"
        payload.mkdir()
        packager.write_launchers(payload, "macos", "Kristin.app/Contents/MacOS/Kristin", "a" * 40, "b" * 40)
        launcher = (payload / "launch-kristin-owner-risk-qa.command").read_text(encoding="utf-8")
        require("Contents/Resources/runtime/p2/current" in launcher, "macOS QA launcher runtime path stale")
        require("codesign --force --deep --sign" not in launcher, "macOS QA launcher performs mutating deep re-sign")
        require("codesign --force --sign -" in launcher, "macOS QA launcher outer seal missing")

    source = PACKAGER.read_text(encoding="utf-8")
    require("--browser-runtime-stage" in source, "browser stage argument missing")
    require("browserRuntimeIncluded" in source, "product metadata browser truth missing")
    require("runtimeIdentity" in source, "final runtime identity metadata missing")
    print("P2_P3_PRODUCT_PACKAGING_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
