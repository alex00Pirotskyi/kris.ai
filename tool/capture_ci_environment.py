#!/usr/bin/env python3
"""Capture redacted CI toolchain evidence for P0-003/P0-004 handoff."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import shutil
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


def prepare_command(
    argv: list[str],
    *,
    windows: bool | None = None,
    resolver: Any = None,
    command_processor: str | None = None,
) -> list[str] | None:
    """Resolve native executables and Windows .bat/.cmd launchers deterministically."""
    if not argv:
        raise ValueError("argv must not be empty")
    which = shutil.which if resolver is None else resolver
    executable = which(argv[0])
    if not executable:
        return None
    resolved = [executable, *argv[1:]]
    is_windows = os.name == "nt" if windows is None else windows
    if is_windows and Path(executable).suffix.lower() in {".bat", ".cmd"}:
        processor = command_processor or os.environ.get("COMSPEC") or which("cmd.exe") or "cmd.exe"
        return [processor, "/d", "/s", "/c", subprocess.list2cmdline(resolved)]
    return resolved


def run(argv: list[str]) -> dict[str, Any]:
    prepared = prepare_command(argv)
    if prepared is None:
        return {"available": False, "error": "FileNotFoundError"}
    try:
        completed = subprocess.run(
            prepared,
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=60,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"available": False, "error": type(error).__name__}
    text = (completed.stdout or "").replace(str(ROOT), "<PROJECT>")
    return {
        "available": completed.returncode == 0,
        "exitCode": completed.returncode,
        "output": text[-12000:],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--print", action="store_true", dest="print_result")
    args = parser.parse_args()
    payload = {
        "schemaVersion": "1.0.0",
        "milestone": "P0-003",
        "runner": {
            "os": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
            "githubRunnerOs": os.environ.get("RUNNER_OS"),
            "githubRunnerArch": os.environ.get("RUNNER_ARCH"),
            "githubRunId": os.environ.get("GITHUB_RUN_ID"),
            "githubRunAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
            "gitSha": os.environ.get("GITHUB_SHA"),
        },
        "python": {
            "version": platform.python_version(),
            "implementation": platform.python_implementation(),
            "executableName": Path(sys.executable).name,
        },
        "dart": run(["dart", "--version"]),
        "flutter": run(["flutter", "--version", "--machine"]),
        "git": run(["git", "--version"]),
    }
    rendered = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    output = Path(args.output)
    if not output.is_absolute():
        output = ROOT / output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(rendered, encoding="utf-8")
    if args.print_result:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
