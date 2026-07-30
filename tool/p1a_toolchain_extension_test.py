#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

EXPECTED_HASHES = {
    "bbaed969cef3c427f4f17591feb28db4ae595e3a4bbd45cb35522cee14df6a32",
    "da9d4fd9abd571fd016ddb27da0428b10277010b23bb21e3678f8b9e96e1686e",
    "1c8b05df0602365da91ee6a3336fe57525b137706c4ab5675498f662ae1dbcec",
    "2297e9591307d9c61e557efe737bcf4d7c13a30f1f860732f684a204fee24dca",
}


def require(value: object, message: str) -> None:
    if not value:
        raise SystemExit(message)


def job_block(workflow: str, name: str) -> str:
    marker = f"  {name}:\n"
    require(marker in workflow, f"workflow job missing: {name}")
    start = workflow.index(marker)
    match = re.search(r"(?m)^  [A-Za-z0-9_-]+:\n", workflow[start + len(marker):])
    end = start + len(marker) + match.start() if match else len(workflow)
    return workflow[start:end]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()
    ext = json.loads((root / "config/p1a_toolchain_extension.v1.json").read_text(encoding="utf-8"))
    workflow = (root / ".github/workflows/p1-authority-amendment.yml").read_text(encoding="utf-8")
    requirements_path = root / "config/p1a_hosted_cmake_requirements.txt"
    bootstrap_path = root / "tool/p1a_bootstrap_hosted_cmake.py"
    toolchains_path = root / "tool/p1a_toolchains.py"
    require(ext.get("schemaVersion") == "1.0.0", "P1A toolchain extension schema invalid")
    require(
        ext.get("pythonVersion") == "3.13.5"
        and ext.get("nodeVersion") == "24.18.0"
        and ext.get("cmakeVersion") == "3.31.6",
        "P1A exact toolchain versions invalid",
    )
    hosted = ext.get("hostedSourceBuildCmake") or {}
    require(hosted.get("requirementsPath") == "config/p1a_hosted_cmake_requirements.txt", "hosted CMake requirements path invalid")
    require(hosted.get("version") == "3.31.6", "hosted CMake version invalid")
    require(hosted.get("completionEligible") is False, "hosted source build cannot be completion eligible")
    for ref in ext["actions"].values():
        require(ref in workflow, f"immutable action missing: {ref}")
    for label in ext["runnerLabels"].values():
        require(label in workflow, f"exact runner missing: {label}")
    require(not any(x in workflow for x in ("ubuntu-latest", "windows-latest", "macos-latest")), "floating runner fallback present")
    require(requirements_path.is_file() and bootstrap_path.is_file() and toolchains_path.is_file(), "hosted CMake governance files missing")
    requirements = requirements_path.read_text(encoding="utf-8")
    require(set(re.findall(r"--hash=sha256:([0-9a-f]{64})", requirements)) == EXPECTED_HASHES, "hosted CMake wheel hash set invalid")
    require(re.findall(r"(?m)^cmake==([^\s\\]+)", requirements) == ["3.31.6"], "hosted CMake requirement is not exact")
    bootstrap = bootstrap_path.read_text(encoding="utf-8")
    for marker in ("--only-binary=:all:", "--require-hashes", "--no-deps", "--force-reinstall", "completionEligible\": False"):
        require(marker in bootstrap, f"hosted bootstrap boundary missing: {marker}")
    toolchains = toolchains_path.read_text(encoding="utf-8")
    for marker in ("--hosted-source-build", "discover_windows_compiler", "vswhere.exe", "github-hosted-source-build-not-completion-evidence"):
        require(marker in toolchains, f"hosted toolchain verifier marker missing: {marker}")
    hosted_jobs = ("p1a-native-build-linux", "p1a-native-build-windows", "p1a-native-build-macos")
    controlled_jobs = ("p1a-behavioral-linux", "p1a-behavioral-windows", "p1a-behavioral-macos")
    for name in hosted_jobs:
        block = job_block(workflow, name)
        require("p1a_bootstrap_hosted_cmake.py" in block, f"{name} does not bootstrap exact hosted CMake")
        require("--hosted-source-build" in block, f"{name} does not mark hosted non-completion provenance")
        require(block.index("p1a_bootstrap_hosted_cmake.py") < block.index("--hosted-source-build"), f"{name} verifies before bootstrap")
        if name == "p1a-native-build-windows":
            for marker in ("Launch-VsDevShell.ps1", "-G Ninja", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"):
                require(marker in block, f"Windows hosted build boundary missing: {marker}")
    for name in controlled_jobs:
        block = job_block(workflow, name)
        require("p1a_bootstrap_hosted_cmake.py" not in block, f"{name} must not install hosted CMake")
        require("--hosted-source-build" not in block, f"{name} must retain controlled completion-eligible verification")
        require("--verify-native-host" in block, f"{name} controlled toolchain verification missing")

    # V63-R15 canonical-text/source-landing repair retaining the R14 native-security corrections. CMake owns Windows SDK macros
    # because the targets compile with /WX; source-level redefinitions are forbidden.
    windows_contracts = {
        "authority_service/native/windows/CMakeLists.txt": ("SECURITY_WIN32", "WIN32_LEAN_AND_MEAN", "NOMINMAX"),
        "authority_service/connector/windows/CMakeLists.txt": ("WIN32_LEAN_AND_MEAN", "NOMINMAX"),
        "authority_service/worker_launcher/windows/CMakeLists.txt": ("WIN32_LEAN_AND_MEAN", "NOMINMAX"),
    }
    for relative, macros in windows_contracts.items():
        cmake_text = (root / relative).read_text(encoding="utf-8")
        require("/W4 /WX /permissive-" in cmake_text, f"strict Windows warnings missing: {relative}")
        for macro in macros:
            require(macro in cmake_text, f"CMake macro authority missing {macro}: {relative}")
    windows_sources = (
        root / "authority_service/native/windows/authority_service_windows.cpp",
        root / "authority_service/connector/windows/p1a_connector_windows.cpp",
        root / "authority_service/worker_launcher/windows/restricted_worker_launcher_windows.cpp",
    )
    for source in windows_sources:
        source_text = source.read_text(encoding="utf-8")
        for macro in ("SECURITY_WIN32", "WIN32_LEAN_AND_MEAN", "NOMINMAX"):
            require(not re.search(rf"(?m)^\s*#\s*define\s+{macro}(?:\s|$)", source_text), f"duplicate /WX macro remains in {source}: {macro}")

    mac_native = (root / "authority_service/native/macos/authority_service_macos.mm").read_text(encoding="utf-8")
    mac_connector_cmake = (root / "authority_service/connector/macos/CMakeLists.txt").read_text(encoding="utf-8")
    mac_native_cmake = (root / "authority_service/native/macos/CMakeLists.txt").read_text(encoding="utf-8")
    mac_worker = (root / "authority_service/worker_launcher/macos/restricted_worker_launcher_macos.mm").read_text(encoding="utf-8")
    mac_manager = (root / "authority_service/install/macos/smappservice_manager.mm").read_text(encoding="utf-8")
    require("std::string ns(NSData" not in mac_native and "std::string file_sha256(" not in mac_native, "unused macOS helpers remain under -Werror")
    require("CCHmacContext" not in mac_native and "CCHmac(" in mac_native, "macOS HMAC must use the stateless API under strict SDK warnings")
    require(mac_native.index("#pragma clang diagnostic push") < mac_native.index("void store_keychain_secret") < mac_native.index("#pragma clang diagnostic pop"), "deprecated ACL bridge is not narrowly scoped")
    require(" xpc)" not in mac_native_cmake and " xpc)" not in mac_connector_cmake, "macOS XPC must resolve through libSystem without non-portable -lxpc")
    require("dlsym(RTLD_DEFAULT,\"xpc_connection_get_audit_token\")" in mac_native and "kSecGuestAttributeAudit" in mac_native, "dynamic audit-token bridge missing")
    require("checked_dword" in (root / "authority_service/native/windows/authority_service_windows.cpp").read_text(encoding="utf-8"), "Windows checked width conversion contract missing")
    require("const int expected_bytes" in mac_worker and "const int observed_bytes" in mac_worker, "proc_pidinfo size contract is not normalized")
    require("#include <cstdio>" in mac_manager and "std::fprintf" in mac_manager and "std::printf" in mac_manager and "std::puts" in mac_manager, "SMAppService manager strict stdio contract missing")
    validation_header = (root / "authority_service/native/common/validation.hpp").read_text(encoding="utf-8")
    authority_core = (root / "authority_service/native/common/authority_core_v2.hpp").read_text(encoding="utf-8")
    linux_worker = (root / "authority_service/worker_launcher/linux/restricted_worker_launcher_linux.cpp").read_text(encoding="utf-8")
    windows_worker = (root / "authority_service/worker_launcher/windows/restricted_worker_launcher_windows.cpp").read_text(encoding="utf-8")
    require(validation_header.count("inline bool valid_identifier") == 1 and validation_header.count("inline bool valid_hex64") == 1, "shared identifier validation definitions invalid")
    require('#include "validation.hpp"' in authority_core and "inline bool valid_identifier" not in authority_core, "authority core does not consume the shared validator")
    for name, worker in (("linux", linux_worker), ("windows", windows_worker), ("macos", mac_worker)):
        require('#include "../../native/common/validation.hpp"' in worker, f"{name} worker does not include shared validation")
        require("kp::valid_identifier" in worker, f"{name} worker does not use shared identifier validation")
        require("bool valid_identifier(" not in worker, f"{name} worker retains a divergent local validator")
    sandbox_push = mac_worker.index("#pragma clang diagnostic push", mac_worker.index("char* sandbox_error"))
    sandbox_init = mac_worker.index("sandbox_init", sandbox_push)
    sandbox_free = mac_worker.index("sandbox_free_error", sandbox_init)
    sandbox_pop = mac_worker.index("#pragma clang diagnostic pop", sandbox_free)
    require(sandbox_push < sandbox_init < sandbox_free < sandbox_pop, "macOS sandbox deprecation bridge is not narrowly and completely scoped")
    for name in hosted_jobs:
        block = job_block(workflow, name)
        require("--verbose" in block, f"{name} does not emit exact native build commands")
    require("integration/p1-authority-service-v63r15" in workflow and "integration/p1-authority-service-v63r12" not in workflow, "R15 workflow branch boundary invalid")

    base = root / "config/toolchains.lock.json"
    if base.is_file():
        completed = subprocess.run(
            [sys.executable, str(root / "tool/p1a_toolchains.py"), "--project", str(root), "--source-only"],
            capture_output=True,
            text=True,
            check=False,
        )
        require(completed.returncode == 0, "P1A toolchain resolver source contract failed")
        validation = subprocess.run(
            [sys.executable, str(bootstrap_path), "--project", str(root), "--validate-only"],
            capture_output=True,
            text=True,
            check=False,
        )
        require(validation.returncode == 0, "hash-locked hosted CMake requirements validation failed")
    else:
        require(ext.get("baseToolchainLockPath") == "config/toolchains.lock.json", "merged P0 lock dependency missing")
    print("P1A V63-R15 hosted-source, canonical-text, shared worker validation, and strict compile-conformance contract: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
