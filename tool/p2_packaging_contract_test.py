#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import pathlib
import stat
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "automation_host/package.json"
LOCK = ROOT / "automation_host/package-lock.json"
PACKAGER = ROOT / "tool/v70_package_platform.py"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"P2_PACKAGING_CONTRACT_FAIL {message}")


def load_packager():
    spec = importlib.util.spec_from_file_location("kristin_v70_package_platform", PACKAGER)
    require(spec is not None and spec.loader is not None, "packager import spec missing")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    package = json.loads(PACKAGE.read_text(encoding="utf-8"))
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    require(package.get("dependencies", {}).get("node-pty") == "1.1.0", "node-pty dependency must stay exactly pinned")
    require(package.get("allowScripts") == {"node-pty@1.1.0": True}, "install-script approval must be exact node-pty@1.1.0 only")
    locked = lock.get("packages", {}).get("node_modules/node-pty", {})
    require(locked.get("version") == "1.1.0", "package lock node-pty version drift")
    require(locked.get("hasInstallScript") is True, "node-pty install-script fact missing from lock")

    source = PACKAGER.read_text(encoding="utf-8")
    require("ensure_macos_node_pty_spawn_helpers(runtime_destination)" in source, "staging repair is not invoked")
    require("runtime_executables=macos_spawn_helpers" in source, "repaired helpers are not explicitly signed")
    require('"macosNodePtySpawnHelpers"' in source, "QA metadata does not record repaired helpers")

    module = load_packager()
    with tempfile.TemporaryDirectory() as temporary:
        runtime = pathlib.Path(temporary) / "runtime"
        helpers = []
        for arch in ("darwin-arm64", "darwin-x64"):
            helper = runtime / "automation_host/node_modules/node-pty/prebuilds" / arch / "spawn-helper"
            helper.parent.mkdir(parents=True, exist_ok=True)
            helper.write_bytes(b"fixture")
            if os.name != "nt":
                helper.chmod(0o644)
            helpers.append(helper)
        repaired = module.ensure_macos_node_pty_spawn_helpers(runtime)
        require(repaired == helpers, "spawn-helper repair order/path set drift")
        if os.name != "nt":
            for helper in repaired:
                mode = stat.S_IMODE(helper.stat().st_mode)
                require(mode & stat.S_IXUSR != 0, f"user executable bit missing: {helper}")
                require(mode & stat.S_IXGRP != 0, f"group executable bit missing: {helper}")
                require(mode & stat.S_IXOTH != 0, f"other executable bit missing: {helper}")

    with tempfile.TemporaryDirectory() as temporary:
        missing = pathlib.Path(temporary) / "runtime"
        try:
            module.ensure_macos_node_pty_spawn_helpers(missing)
        except SystemExit as exc:
            require("spawn-helper missing" in str(exc), "missing helper must fail closed with specific reason")
        else:
            raise SystemExit("P2_PACKAGING_CONTRACT_FAIL missing spawn-helper did not fail closed")

    print("P2_PACKAGING_CONTRACT_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
