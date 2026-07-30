#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
import pathlib
import shutil
import subprocess
import sys
import sysconfig


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command_output(command: list[str], *, accepted: tuple[int, ...] = (0,)) -> str:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode not in accepted:
        raise SystemExit("toolchain version command failed: " + " ".join(command))
    combined = "\n".join(part for part in (result.stdout, result.stderr) if part)
    lines = [line.strip() for line in combined.splitlines() if line.strip()]
    if not lines:
        raise SystemExit("toolchain version command returned no output: " + " ".join(command))
    return lines[0]


def output(path: str | None, key: str, value: str) -> None:
    if path:
        with pathlib.Path(path).open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(f"{key}={value}\n")


def discover_windows_compiler() -> pathlib.Path:
    direct = shutil.which("cl")
    if direct:
        return pathlib.Path(direct).resolve()
    candidates: list[pathlib.Path] = []
    for variable in ("ProgramFiles(x86)", "ProgramFiles"):
        base = os.environ.get(variable)
        if base:
            candidates.append(pathlib.Path(base) / "Microsoft Visual Studio/Installer/vswhere.exe")
    candidates.append(pathlib.Path(r"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"))
    vswhere = next((path for path in candidates if path.is_file()), None)
    if vswhere is None:
        raise SystemExit("P1A Windows compiler unavailable: vswhere.exe not found")
    completed = subprocess.run(
        [
            str(vswhere),
            "-latest",
            "-products",
            "*",
            "-requires",
            "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
            "-property",
            "installationPath",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    installation_text = (completed.stdout or "").strip()
    if completed.returncode or not installation_text:
        raise SystemExit("P1A Windows compiler unavailable: Visual Studio C++ workload not found")
    installation = pathlib.Path(installation_text.splitlines()[-1].strip())
    roots = list((installation / "VC/Tools/MSVC").glob("*/bin/Hostx64/x64/cl.exe"))
    if not roots:
        raise SystemExit("P1A Windows compiler unavailable: cl.exe not found under latest Visual Studio")
    def version_key(path: pathlib.Path) -> tuple[int, ...]:
        parts = path.parents[3].name.split(".")
        return tuple(int(part) if part.isdigit() else 0 for part in parts)
    return max(roots, key=version_key).resolve()


def discover_compiler(platform: str | None) -> pathlib.Path:
    if platform == "windows":
        return discover_windows_compiler()
    executable = shutil.which("c++")
    if not executable:
        raise SystemExit("P1A C++ compiler unavailable")
    return pathlib.Path(executable).resolve()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--source-only", action="store_true")
    parser.add_argument("--verify-native-host", action="store_true")
    parser.add_argument("--hosted-source-build", action="store_true")
    parser.add_argument("--skip-node", action="store_true")
    parser.add_argument("--platform", choices=("windows", "macos", "linux"))
    parser.add_argument("--github-output")
    parser.add_argument("--json-output")
    args = parser.parse_args()
    if args.hosted_source_build and not args.verify_native_host:
        raise SystemExit("--hosted-source-build requires --verify-native-host")
    if args.verify_native_host and not args.platform:
        raise SystemExit("--verify-native-host requires --platform")
    root = pathlib.Path(args.project).resolve()
    base_path = root / "config/toolchains.lock.json"
    ext_path = root / "config/p1a_toolchain_extension.v1.json"
    requirements_path = root / "config/p1a_hosted_cmake_requirements.txt"
    if not ext_path.is_file():
        raise SystemExit("P1A toolchain extension missing")
    ext = json.loads(ext_path.read_text(encoding="utf-8"))
    base = json.loads(base_path.read_text(encoding="utf-8")) if base_path.is_file() else {}
    if ext.get("schemaVersion") != "1.0.0" or ext.get("baseToolchainLockPath") != "config/toolchains.lock.json":
        raise SystemExit("P1A toolchain extension identity invalid")
    flutter = str(base.get("flutter", {}).get("version") or base.get("flutterVersion") or "")
    dart = str(base.get("dart", {}).get("version") or base.get("dartVersion") or "")
    python_version = str(ext.get("pythonVersion", ""))
    node = str(ext.get("nodeVersion", ""))
    cmake = str(ext.get("cmakeVersion", ""))
    if not all((flutter, dart, python_version, node, cmake)):
        raise SystemExit("P1A exact toolchain versions missing")
    workflow = (root / ".github/workflows/p1-authority-amendment.yml").read_text(encoding="utf-8")
    for ref in ext.get("actions", {}).values():
        if ref not in workflow:
            raise SystemExit(f"P1A immutable action pin missing: {ref}")
    for label in ext.get("runnerLabels", {}).values():
        if label not in workflow:
            raise SystemExit(f"P1A exact runner label missing: {label}")
    if any(token in workflow for token in ("ubuntu-latest", "windows-latest", "macos-latest")):
        raise SystemExit("floating P1A runner label rejected")
    result: dict[str, object] = {
        "schemaVersion": "1.1.0",
        "baseToolchainLockSha256": sha(base_path) if base_path.is_file() else None,
        "extensionSha256": sha(ext_path),
        "python": python_version,
        "node": node,
        "cmake": cmake,
        "flutter": flutter,
        "dart": dart,
        "nativeToolchainProofRequired": not args.source_only,
        "provenanceClass": (
            "github-hosted-source-build-not-completion-evidence"
            if args.hosted_source_build
            else "controlled-native-toolchain" if args.verify_native_host else "source-contract-only"
        ),
        "completionEligible": bool(args.verify_native_host and not args.hosted_source_build),
        "completionClaim": False,
    }
    if args.verify_native_host:
        python_executable = pathlib.Path(sys.executable).resolve()
        actual_python = ".".join(map(str, sys.version_info[:3]))
        if actual_python != python_version:
            raise SystemExit(f"P1A Python mismatch: {actual_python} != {python_version}")
        cmake_executable_text = shutil.which("cmake")
        if not cmake_executable_text:
            raise SystemExit("P1A CMake unavailable")
        cmake_executable = pathlib.Path(cmake_executable_text).resolve()
        actual_cmake = command_output([str(cmake_executable), "--version"]).removeprefix("cmake version ").strip()
        if actual_cmake != cmake:
            raise SystemExit(f"P1A CMake mismatch: {actual_cmake} != {cmake}")
        if args.hosted_source_build:
            if not requirements_path.is_file():
                raise SystemExit("P1A hosted CMake requirements missing")
            installed = importlib.metadata.version("cmake")
            if installed != cmake:
                raise SystemExit(f"P1A hosted CMake distribution mismatch: {installed} != {cmake}")
            scripts = pathlib.Path(sysconfig.get_path("scripts")).resolve()
            if scripts != cmake_executable.parent and scripts not in cmake_executable.parents:
                # The cmake Python distribution may expose the native binary through
                # its package bin directory after that directory is added to GITHUB_PATH.
                try:
                    import cmake as cmake_distribution  # type: ignore
                except Exception as exc:
                    raise SystemExit(f"P1A hosted CMake provenance unavailable: {exc}")
                package_bin = pathlib.Path(str(cmake_distribution.CMAKE_BIN_DIR)).resolve()
                if package_bin != cmake_executable.parent and package_bin not in cmake_executable.parents:
                    raise SystemExit("P1A hosted CMake executable is not from the hash-locked Python distribution")
        compiler = discover_compiler(args.platform)
        compiler_version = (
            command_output([str(compiler), "/?"], accepted=(0, 1, 2))
            if args.platform == "windows"
            else command_output([str(compiler), "--version"])
        )
        native: dict[str, object] = {
            "python": {
                "version": actual_python,
                "path": str(python_executable),
                "executableSha256": sha(python_executable),
            },
            "cmake": {
                "version": actual_cmake,
                "path": str(cmake_executable),
                "executableSha256": sha(cmake_executable),
                "requirementsSha256": sha(requirements_path) if args.hosted_source_build else None,
            },
            "compiler": {
                "version": compiler_version,
                "path": str(compiler),
                "executableSha256": sha(compiler),
            },
            "provenanceClass": result["provenanceClass"],
            "completionEligible": result["completionEligible"],
        }
        if args.hosted_source_build and args.platform == "windows":
            ninja_text = shutil.which("ninja")
            if not ninja_text:
                raise SystemExit("P1A Windows hosted Ninja generator unavailable")
            ninja = pathlib.Path(ninja_text).resolve()
            native["generator"] = {
                "name": "Ninja",
                "version": command_output([str(ninja), "--version"]),
                "path": str(ninja),
                "executableSha256": sha(ninja),
            }
        if not args.skip_node:
            node_executable_text = shutil.which("node")
            if not node_executable_text:
                raise SystemExit("P1A exact Node unavailable")
            node_executable = pathlib.Path(node_executable_text).resolve()
            actual_node = command_output([str(node_executable), "--version"]).lstrip("v")
            if actual_node != node:
                raise SystemExit(f"P1A Node mismatch: {actual_node} != {node}")
            native["node"] = {
                "version": actual_node,
                "path": str(node_executable),
                "executableSha256": sha(node_executable),
            }
        result["native"] = native
    for key, value in (
        ("flutter", flutter),
        ("dart", dart),
        ("python", python_version),
        ("node", node),
        ("cmake", cmake),
    ):
        output(args.github_output, key, value)
    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    print(text, end="")
    if args.json_output:
        pathlib.Path(args.json_output).write_text(text, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
