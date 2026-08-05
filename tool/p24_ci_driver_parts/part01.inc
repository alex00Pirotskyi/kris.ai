#!/usr/bin/env python3
"""Bounded exact-head CI driver for the P24-001 adoption-review workflow."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import traceback
from typing import Any, Sequence

INDEX_REL = Path("docs/roadmap/anarchy/generated/P24-001_CONTROL_PLANE_INDEX.json")
MANIFEST_REL = Path("SOURCE_MANIFEST.sha256")


def _canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, indent=2) + "\n"


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_canonical_json(value), encoding="utf-8", newline="\n")


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"JSON root must be an object: {path}")
    return value


def _run(command: Sequence[str], *, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(command), cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def _interesting(output: str, fallback: str) -> str:
    for line in output.splitlines():
        text = line.strip()
        if text.startswith(("Traceback", "ERROR:", "FAILED", "ValueError:", "ControlPlaneError:", "P24-001 control-plane error:")):
            return text
    stripped = output.strip().splitlines()
    return stripped[0] if stripped else fallback


def _parse_write_result(output: str) -> dict[str, Any] | None:
    for line in output.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and {"path", "changed", "sha256"} <= set(value):
            return value
    return None


def _paths(root: Path, temporary: Path) -> dict[str, Path]:
    return {
        "root": root,
        "temporary": temporary,
        "diagnostic": temporary / "p24-diagnostic.json",
        "tests_log": temporary / "p24-tests.log",
        "generation_log": temporary / "p24-generation.log",
        "exact_log": temporary / "p24-exact-check.log",
        "proof": temporary / "p24-isolated-generation-proof.json",
        "report": temporary / "p24-validation-report.json",
        "expected_index": temporary / "expected-P24-001_CONTROL_PLANE_INDEX.json",
        "expected_manifest": temporary / "expected-SOURCE_MANIFEST.sha256",
    }


def _update_failure(diagnostic: dict[str, Any], phase: str, detail: str) -> None:
    diagnostic.setdefault("phases", {}).setdefault(phase, {})["status"] = "FAIL"
    if diagnostic.get("firstFailure") is None:
        diagnostic["firstFailure"] = {"phase": phase, "detail": detail}


def command_init(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    temporary = Path(args.temporary).resolve()
    paths = _paths(root, temporary)
    temporary.mkdir(parents=True, exist_ok=True)
    diagnostic = {
        "schemaVersion": "1.0.0",
        "recordType": "P24ExactHeadDiagnostic",
        "candidate": {"commit": args.candidate, "tree": args.tree},
        "platform": {
            "runnerOs": os.environ.get("RUNNER_OS", "unknown"),
            "runnerArch": os.environ.get("RUNNER_ARCH", "unknown"),
            "imageOs": os.environ.get("ImageOS", "unknown"),
            "imageVersion": os.environ.get("ImageVersion", "unknown"),
        },
        "phases": {
            "tests": {"status": "NOT_RUN"},
            "generation": {"status": "NOT_RUN"},
            "exactCheck": {"status": "NOT_RUN"},
        },
        "firstFailure": None,
        "generatedIndex": {"status": "NOT_CHECKED"},
        "sourceManifest": {"status": "NOT_CHECKED"},
        "nonMutation": {"status": "NOT_CHECKED"},
        "idempotence": {"status": "NOT_CHECKED"},
        "exactCheckConclusion": "NOT_RUN",
    }
    _write_json(paths["diagnostic"], diagnostic)
    for key in ("tests_log", "generation_log", "exact_log"):
        paths[key].write_text("", encoding="utf-8", newline="\n")
    _write_json(paths["proof"], {"schemaVersion": "1.0.0", "status": "NOT_RUN"})
    _write_json(paths["report"], {"schemaVersion": "1.0.0", "status": "NOT_RUN"})
    return 0


def command_tests(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    paths = _paths(root, Path(args.temporary).resolve())
    diagnostic = _read_json(paths["diagnostic"])
    commands = [
        ("compile", [sys.executable, "-m", "py_compile", "tool/anarchy_control_plane.py", "tool/anarchy_control_plane_test.py", "tool/p24_ci_driver.py"]),
        ("unit-tests", [sys.executable, "-m", "unittest", "-v", "tool/anarchy_control_plane_test.py"]),
        ("clean-room-resume", [sys.executable, "tool/anarchy_control_plane.py", "--resume-worker", "J", "--project", "."]),
    ]
    records: list[dict[str, Any]] = []
    failure: str | None = None
    with paths["tests_log"].open("w", encoding="utf-8", newline="\n") as log:
        for name, command in commands:
            completed = _run(command, cwd=root)
            output = completed.stdout or ""
            log.write(f"## {name} rc={completed.returncode}\n{output}\n")
            records.append({"name": name, "returnCode": completed.returncode})
            if completed.returncode:
                failure = _interesting(output, f"{name} exited {completed.returncode}")
                break
    diagnostic["phases"]["tests"] = {
        "status": "PASS" if failure is None else "FAIL",
        "commands": records,
        "log": paths["tests_log"].name,
    }
    if failure is not None:
        _update_failure(diagnostic, "tests", failure)
    _write_json(paths["diagnostic"], diagnostic)
    return 0 if failure is None else 1


