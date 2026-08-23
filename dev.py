#!/usr/bin/env python3
"""Fast, predictable development commands for Kristin."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import platform as host_platform
import shutil
import subprocess
import sys
from typing import Sequence

ROOT = Path(__file__).resolve().parent
PLATFORM_DEVICES = {"windows": "windows", "macos": "macos", "linux": "linux"}
RUNNER_MARKERS = {
    "windows": Path("windows/CMakeLists.txt"),
    "macos": Path("macos/Runner.xcodeproj/project.pbxproj"),
    "linux": Path("linux/CMakeLists.txt"),
}


def _host_platform() -> str | None:
    system = host_platform.system().lower()
    if system == "windows":
        return "windows"
    if system == "darwin":
        return "macos"
    if system == "linux":
        return "linux"
    return None


def _run(command: Sequence[str], *, check: bool = True) -> int:
    printable = (
        subprocess.list2cmdline(list(command))
        if os.name == "nt"
        else " ".join(command)
    )
    print(f"+ {printable}", flush=True)
    completed = subprocess.run(list(command), cwd=ROOT, check=False)
    if check and completed.returncode != 0:
        raise SystemExit(completed.returncode)
    return completed.returncode


def _require(name: str) -> str:
    resolved = shutil.which(name)
    if resolved is None:
        raise SystemExit(
            f"ERROR: {name} was not found on PATH. "
            "Run `python dev.py doctor` for setup diagnostics."
        )
    return resolved


def _resolve_platform(raw: str | None) -> str:
    selected = raw or _host_platform()
    if selected not in PLATFORM_DEVICES:
        supported = ", ".join(PLATFORM_DEVICES)
        raise SystemExit(
            f"ERROR: unsupported desktop platform. Choose one of: {supported}."
        )
    host = _host_platform()
    if host != selected:
        raise SystemExit(
            f"ERROR: {selected} desktop commands must run on a {selected} host; "
            f"current host is {host or 'unknown'}."
        )
    return selected


def _runner_ready(target: str) -> bool:
    return (ROOT / RUNNER_MARKERS[target]).is_file()


def doctor(target: str | None) -> int:
    selected = _resolve_platform(target)
    failed = False

    print(f"Kristin development doctor ({selected})")
    print(f"[OK] python: {sys.executable}")
    for command in ("flutter", "dart"):
        resolved = shutil.which(command)
        if resolved:
            print(f"[OK] {command}: {resolved}")
        else:
            print(f"[MISSING] {command}: add it to PATH")
            failed = True

    for command in ("node", "npm"):
        resolved = shutil.which(command)
        if resolved:
            print(f"[OK] {command}: {resolved}")
        else:
            print(
                f"[WARN] {command}: unavailable; Owner Mode/browser automation "
                "host setup will be incomplete"
            )

    marker = RUNNER_MARKERS[selected]
    if _runner_ready(selected):
        print(f"[OK] desktop runner: {marker.as_posix()}")
    else:
        print(
            f"[SETUP] desktop runner missing: {marker.as_posix()} "
            f"(run `python dev.py bootstrap {selected}`)"
        )

    return 1 if failed else 0


def bootstrap(target: str | None) -> int:
    selected = _resolve_platform(target)
    flutter = _require("flutter")
    _require("dart")

    _run([flutter, "config", f"--enable-{selected}-desktop"])
    if not _runner_ready(selected):
        _run(
            [
                flutter,
                "create",
                "--project-name",
                "kristin_local_agent",
                "--org",
                "local.kristin",
                "--platforms",
                selected,
                ".",
            ]
        )

    _run([flutter, "pub", "get"])

    npm = shutil.which("npm")
    package_lock = ROOT / "automation_host/package-lock.json"
    if npm and package_lock.is_file():
        _run(
            [
                npm,
                "ci",
                "--prefix",
                "automation_host",
                "--ignore-scripts=false",
                "--no-audit",
                "--no-fund",
            ]
        )
    elif package_lock.is_file():
        print(
            "[WARN] npm is unavailable; Flutter is bootstrapped, but the "
            "automation host was not installed."
        )

    print(f"Bootstrap complete for {selected}.")
    return 0


def run_app(target: str | None) -> int:
    selected = _resolve_platform(target)
    flutter = _require("flutter")
    if not _runner_ready(selected):
        raise SystemExit(
            f"ERROR: {selected} runner is missing. "
            f"Run `python dev.py bootstrap {selected}` once."
        )
    return _run(
        [flutter, "run", "-d", PLATFORM_DEVICES[selected]],
        check=False,
    )


def check_fast() -> int:
    flutter = _require("flutter")
    _require("dart")
    commands = [
        [sys.executable, "tool/protocol_contract_test.py"],
        [sys.executable, "tool/p2_source_inventory_test.py", "--project", "."],
        [flutter, "pub", "get"],
        [sys.executable, "tool/dart_format_scope.py", "--check"],
        [flutter, "analyze", "--no-pub", "--fatal-warnings", "--fatal-infos"],
        [
            flutter,
            "test",
            "--no-pub",
            "--concurrency=1",
            "--reporter",
            "compact",
            "test/product/source_contract_test.dart",
            "test/product/p25_fast_path_contract_test.dart",
        ],
    ]
    for command in commands:
        _run(command)
    print("Fast development checks passed.")
    return 0


def ci() -> int:
    if os.name == "nt":
        return _run(["cmd", "/d", "/c", r"tool\verify.cmd"], check=False)
    return _run(["bash", "tool/verify.sh"], check=False)


def package() -> int:
    return _run([sys.executable, "tool/release.py"], check=False)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Kristin development commands. Normal `run` never cleans the "
            "tree or executes release validation."
        )
    )
    sub = parser.add_subparsers(dest="command", required=True)

    doctor_parser = sub.add_parser(
        "doctor", help="check the local desktop development toolchain"
    )
    doctor_parser.add_argument(
        "platform", nargs="?", choices=tuple(PLATFORM_DEVICES)
    )

    bootstrap_parser = sub.add_parser(
        "bootstrap", help="one-time desktop runner and dependency setup"
    )
    bootstrap_parser.add_argument(
        "platform", nargs="?", choices=tuple(PLATFORM_DEVICES)
    )

    run_parser = sub.add_parser(
        "run", help="start the desktop app without full verification"
    )
    run_parser.add_argument(
        "platform", nargs="?", choices=tuple(PLATFORM_DEVICES)
    )

    sub.add_parser("check", help="run fast non-mutating development checks")
    sub.add_parser("ci", help="run the repository's full validation suite")
    sub.add_parser(
        "package", help="build the deterministic source release package"
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.command == "doctor":
        return doctor(args.platform)
    if args.command == "bootstrap":
        return bootstrap(args.platform)
    if args.command == "run":
        return run_app(args.platform)
    if args.command == "check":
        return check_fast()
    if args.command == "ci":
        return ci()
    if args.command == "package":
        return package()
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
