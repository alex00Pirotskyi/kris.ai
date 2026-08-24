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
import sys
import time
from typing import Iterable

P2_SHA = "7b0d77d8956f05ff907ca7463b0d787dcebf93a60426aab105be2b610e6072b0"


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def copy_file(source: pathlib.Path, destination: pathlib.Path, executable: bool = False) -> pathlib.Path:
    if not source.is_file():
        fail(f"source file missing: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    if executable and os.name != "nt":
        destination.chmod(destination.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return destination


def copy_tree(source: pathlib.Path, destination: pathlib.Path, excludes: Iterable[str] = ()) -> None:
    excluded = set(excludes)
    if not source.is_dir():
        fail(f"source directory missing: {source}")
    for path in sorted(source.rglob("*"), key=lambda item: item.relative_to(source).as_posix()):
        relative = path.relative_to(source)
        if any(part in excluded for part in relative.parts):
            continue
        target = destination / relative
        if path.is_symlink():
            # Resolve executable/package-manager links into ordinary files so the
            # QA bundle remains portable and symlink-free.
            resolved = path.resolve()
            if resolved.is_file():
                copy_file(resolved, target, os.access(resolved, os.X_OK))
            continue
        if path.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            copy_file(path, target, os.access(path, os.X_OK))


def first_file(roots: list[pathlib.Path], patterns: tuple[str, ...]) -> pathlib.Path | None:
    candidates: list[pathlib.Path] = []
    for root in roots:
        if not root.exists():
            continue
        for pattern in patterns:
            candidates.extend(path for path in root.rglob(pattern) if path.is_file())
    candidates = [
        path
        for path in candidates
        if not any(part in {"CMakeFiles", "Testing"} for part in path.parts)
        and path.suffix.lower() not in {".obj", ".o", ".pdb", ".ilk", ".cmake", ".txt"}
    ]
    return sorted(candidates, key=lambda path: (len(path.parts), path.as_posix()))[0] if candidates else None


def run(argv: list[str], *, cwd: pathlib.Path | None = None) -> None:
    result = subprocess.run(argv, cwd=cwd, text=True, encoding="utf-8", errors="replace")
    if result.returncode:
        fail(f"command failed ({result.returncode}): {' '.join(argv)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--platform", required=True, choices=("windows", "macos", "linux"))
    parser.add_argument("--output", required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--source-tree", required=True)
    parser.add_argument("--p2-package-sha256", default=P2_SHA)
    parser.add_argument("--configurator", required=True)
    parser.add_argument("--mode", choices=("qa", "product-current-account"), default="qa")
    parser.add_argument("--github-env")
    args = parser.parse_args()

    root = pathlib.Path(args.project).resolve()
    output = pathlib.Path(args.output).resolve()
    configurator = pathlib.Path(args.configurator).resolve()
    for name, value, length in (
        ("source commit", args.source_commit, 40),
        ("source tree", args.source_tree, 40),
        ("P2 package SHA-256", args.p2_package_sha256, 64),
    ):
        if len(value) != length or any(ch not in "0123456789abcdef" for ch in value):
            fail(f"invalid {name}: {value}")
    if args.p2_package_sha256 != P2_SHA:
        fail("unexpected P2 package SHA-256")
    contract = root / "lib/product/p1_authority_service_contract_v1.dart"
    automation = root / "automation_host"
    if not contract.is_file() or not automation.is_dir() or not configurator.is_file():
        fail("required project/configurator files missing")
    node_value = shutil.which("node")
    if not node_value:
        fail("node executable missing")
    node_source = pathlib.Path(node_value).resolve()

    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    runtime = output / "runtime"
    node_name = "node.exe" if args.platform == "windows" else "node"
    copy_file(node_source, runtime / "node" / node_name, executable=True)
    copy_tree(automation, runtime / "automation_host", excludes={".git", "build", ".dart_tool"})
    copy_file(configurator, runtime / "tools" / "configure-owner-risk-runtime.mjs", executable=True)
    copy_file(contract, runtime / "contracts" / contract.name)

    # Carry reviewed P1A binaries and P2 lifecycle helpers in the QA payload.
    p1a_output = output / "p1a-native"
    p2_native = runtime / "native"
    if args.platform == "windows":
        build_roots = [root / ".p1a-build-windows", root / ".p1a-connector-windows", root / ".p1a-worker-windows"]
        for logical, patterns in (
            ("authority-service", ("*authority_service*.exe",)),
            ("connector", ("*connector*.dll", "*connector*.exe")),
            ("worker-launcher", ("*worker_launcher*.exe",)),
        ):
            found = first_file(build_roots, patterns)
            if not found:
                fail(f"P1A Windows binary missing: {logical}")
            copy_file(found, p1a_output / found.name, executable=True)
        helper = first_file([root / ".p2-native-windows"], ("*job_supervisor*.exe",))
        conpty = first_file([root / ".p2-native-windows"], ("*pty_probe*.exe",))
        if not helper or not conpty:
            fail("P2 Windows native helpers missing")
        copy_file(helper, p2_native / "windowsJobHelper" / helper.name, executable=True)
        copy_file(conpty, p2_native / "interactiveDesktopAdapter" / conpty.name, executable=True)
    elif args.platform == "macos":
        build_roots = [root / ".p1a-build-macos", root / ".p1a-connector-macos", root / ".p1a-worker-macos", root / ".p1a-manager-macos"]
        for logical, patterns in (
            ("authority-service", ("kristin_p1_authority_service*",)),
            ("connector", ("*connector*",)),
            ("worker-launcher", ("*worker_launcher*",)),
        ):
            found = first_file(build_roots, patterns)
            if not found:
                fail(f"P1A macOS binary missing: {logical}")
            copy_file(found, p1a_output / found.name, executable=True)
        watchdog = first_file([root / ".p2-native-posix"], ("*watchdog*",))
        pty = first_file([root / ".p2-native-posix"], ("*pty_probe*",))
        if not watchdog or not pty:
            fail("P2 macOS native helpers missing")
        copy_file(watchdog, p2_native / "posixWatchdog" / watchdog.name, executable=True)
        copy_file(pty, p2_native / "interactiveDesktopAdapter" / pty.name, executable=True)
    else:
        build_roots = [root / ".p1a-build-linux", root / ".p1a-connector-linux", root / ".p1a-worker-linux"]
        for logical, patterns in (
            ("authority-service", ("kristin_p1_authority_service*",)),
            ("connector", ("*connector*",)),
            ("worker-launcher", ("*worker_launcher*",)),
        ):
            found = first_file(build_roots, patterns)
            if not found:
                fail(f"P1A Linux binary missing: {logical}")
            copy_file(found, p1a_output / found.name, executable=True)
        watchdog = first_file([root / ".p2-native-posix"], ("*watchdog*",))
        pty = first_file([root / ".p2-native-posix"], ("*pty_probe*",))
        if not watchdog or not pty:
            fail("P2 Linux native helpers missing")
        copy_file(watchdog, p2_native / "posixWatchdog" / watchdog.name, executable=True)
        copy_file(pty, p2_native / "interactiveDesktopAdapter" / pty.name, executable=True)

    run([
        str(runtime / "node" / node_name),
        str(runtime / "tools" / "configure-owner-risk-runtime.mjs"),
        "--root", str(runtime),
        "--platform", args.platform,
        "--source-commit", args.source_commit,
        "--source-tree", args.source_tree,
        "--p2-package-sha256", args.p2_package_sha256,
        "--p1-contract", str(runtime / "contracts" / contract.name),
        "--mode", args.mode,
    ])
    environment = {
        "KRISTIN_V70_RUNTIME_ROOT": str(runtime),
        "KRISTIN_V70_NODE": str(runtime / "node" / node_name),
        "KRISTIN_V70_HOST": str(runtime / "automation_host/src/host.mjs"),
        "KRISTIN_V70_HOST_ROOT": str(runtime / "automation_host"),
        "KRISTIN_V70_LAUNCHER": str(runtime / "automation_host/src/owner-risk-launcher.mjs"),
        "KRISTIN_V70_POLICY": str(runtime / "provisioning/worker-policy.v2.json"),
        **({"KRISTIN_OWNER_RISK_QA": "1"} if args.mode == "qa" else {}),
        **({"KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT": "1"} if args.mode == "product-current-account" else {}),
    }
    for name, relative in (
        ("KRISTIN_V70_WINDOWS_HELPER", "native/windowsJobHelper"),
        ("KRISTIN_V70_POSIX_WATCHDOG", "native/posixWatchdog"),
        ("KRISTIN_V70_INTERACTIVE_ADAPTER", "native/interactiveDesktopAdapter"),
    ):
        directory = runtime / relative
        if directory.is_dir():
            files = sorted(path for path in directory.iterdir() if path.is_file())
            if files:
                environment[name] = str(files[0])
    (output / "runtime-environment.json").write_text(json.dumps(environment, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.github_env:
        github_env = pathlib.Path(args.github_env)
        with github_env.open("a", encoding="utf-8", newline="\n") as stream:
            for name, value in sorted(environment.items()):
                stream.write(f"{name}={value}\n")

    metadata = {
        "schemaVersion": "1.0.0",
        "mode": "product-current-account" if args.mode == "product-current-account" else "owner-risk-tri-platform-qa",
        "platform": args.platform,
        "sourceCommit": args.source_commit,
        "sourceTree": args.source_tree,
        "p2PackageSha256": args.p2_package_sha256,
        "securityEvidenceWaived": True,
        "formalSecurityCompletion": False,
        "qaShipmentEligibleOnlyAfterAllPlatforms": ["windows", "macos", "linux"],
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "runtimeManifestSha256": sha256(runtime / "runtime-manifest.v3.json"),
    }
    (output / "runtime-stage-metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(metadata, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
