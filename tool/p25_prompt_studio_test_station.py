#!/usr/bin/env python3
"""Run P25 Prompt Studio Test Station profiles without shell execution."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def load_manifest(project: Path) -> dict[str, Any]:
    return json.loads(
        (project / "docs/roadmap/p25/prompt_studio_test_station.v1.json").read_text(
            encoding="utf-8"
        )
    )


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8", errors="replace")).hexdigest()


def source_identity(project: Path) -> dict[str, Any]:
    def git(*args: str) -> str | None:
        result = subprocess.run(
            ["git", *args],
            cwd=project,
            capture_output=True,
            text=True,
            check=False,
        )
        return result.stdout.strip() if result.returncode == 0 else None

    return {
        "commit": git("rev-parse", "HEAD"),
        "tree": git("rev-parse", "HEAD^{tree}"),
        "branch": git("branch", "--show-current"),
        "statusSha256": digest(git("status", "--porcelain") or ""),
    }


def blocker(project: Path, profile: str) -> tuple[str, str] | None:
    if profile == "latency-unit":
        if not (project / "test/product/p25_prompt_studio_latency_test.dart").is_file():
            return ("BLOCKED_NOT_IMPLEMENTED", "P25-001 latency test source is not present")
        if shutil.which("flutter") is None:
            return ("BLOCKED_ENVIRONMENT", "flutter is unavailable")
    if profile == "local-phi-cpu":
        if not (project / "tool/p25_prompt_studio_benchmark.dart").is_file():
            return ("BLOCKED_NOT_IMPLEMENTED", "P25-001 benchmark harness is not present")
        if shutil.which("dart") is None:
            return ("BLOCKED_ENVIRONMENT", "dart is unavailable")
        if not os.environ.get("P25_MODEL_NAME", "").strip():
            return ("BLOCKED_ENVIRONMENT", "P25_MODEL_NAME is missing")
        hardware = os.environ.get("P25_HARDWARE_REPORT", "").strip()
        if not hardware or not Path(hardware).is_file():
            return ("BLOCKED_ENVIRONMENT", "P25_HARDWARE_REPORT is missing or invalid")
    if profile == "packaged-windows":
        if not (project / "tool/p25_prompt_studio_packaged_windows.py").is_file():
            return ("BLOCKED_NOT_IMPLEMENTED", "packaged Windows campaign is not implemented")
    return None


def commands(project: Path, profile: str, evidence_dir: Path) -> list[list[str]]:
    python = sys.executable
    if profile == "contract":
        return [
            [python, "tool/p25_prompt_studio_roadmap_test.py", "--project", "."],
            [python, "tool/test_center_contracts.py", "check", "--project", "."],
            [python, "tool/test_center_assurance_hierarchy.py", "check", "--project", "."],
        ]
    if profile == "latency-unit":
        return [["flutter", "test", "test/product/p25_prompt_studio_latency_test.dart"]]
    if profile == "local-phi-cpu":
        return [
            [
                "dart",
                "run",
                "tool/p25_prompt_studio_benchmark.dart",
                "--model",
                os.environ["P25_MODEL_NAME"],
                "--hardware-report",
                os.environ["P25_HARDWARE_REPORT"],
                "--base-url",
                os.environ.get("P25_OLLAMA_BASE_URL", "http://127.0.0.1:11434"),
                "--output",
                str(evidence_dir / "benchmark-report.json"),
            ]
        ]
    if profile == "packaged-windows":
        return [[python, "tool/p25_prompt_studio_packaged_windows.py", "--check"]]
    raise ValueError(f"unknown profile: {profile}")


def run_profile(project: Path, profile: str, evidence_dir: Path) -> dict[str, Any]:
    manifest = load_manifest(project)
    profile_ids = {item["profileId"] for item in manifest["profiles"]}
    if profile not in profile_ids:
        raise ValueError(f"unknown profile: {profile}")
    blocked = blocker(project, profile)
    if blocked:
        state, reason = blocked
        return {
            "schemaVersion": "1.0.0",
            "suiteId": manifest["suiteId"],
            "profile": profile,
            "resultState": state,
            "blocker": reason,
            "source": source_identity(project),
            "attempts": [],
        }

    before = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=project,
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    attempts: list[dict[str, Any]] = []
    state = "PASS"
    for argv in commands(project, profile, evidence_dir):
        started = datetime.now(timezone.utc)
        watch = time.monotonic()
        result = subprocess.run(
            argv,
            cwd=project,
            capture_output=True,
            text=True,
            check=False,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
        )
        ended = datetime.now(timezone.utc)
        attempt_state = "PASS" if result.returncode == 0 else "FAIL"
        if attempt_state != "PASS":
            state = "FAIL"
        attempts.append(
            {
                "argv": argv,
                "startedAt": started.isoformat(),
                "endedAt": ended.isoformat(),
                "durationMillis": int((time.monotonic() - watch) * 1000),
                "exitCode": result.returncode,
                "resultState": attempt_state,
                "stdoutSha256": digest(result.stdout),
                "stderrSha256": digest(result.stderr),
                "stdoutTail": result.stdout[-4000:],
                "stderrTail": result.stderr[-4000:],
            }
        )
        if result.returncode != 0:
            break

    after = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=project,
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    if before != after:
        state = "FAIL"
        attempts.append(
            {
                "argv": ["git", "status", "--porcelain"],
                "durationMillis": 0,
                "exitCode": 1,
                "resultState": "FAIL",
                "stdoutSha256": digest(after),
                "stderrSha256": digest("P25 Test Station changed tracked source"),
                "stdoutTail": after[-4000:],
                "stderrTail": "P25 Test Station changed tracked source.",
            }
        )
    return {
        "schemaVersion": "1.0.0",
        "suiteId": manifest["suiteId"],
        "profile": profile,
        "resultState": state,
        "source": source_identity(project),
        "environment": {
            "platform": sys.platform,
            "python": sys.version,
            "machine": platform.machine(),
            "processor": platform.processor(),
        },
        "attempts": attempts,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--profile")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--evidence-dir", default="")
    args = parser.parse_args()
    project = Path(args.project).resolve()
    manifest = load_manifest(project)
    if args.list:
        print(json.dumps(manifest, indent=2, sort_keys=True))
        return 0
    if not args.profile:
        parser.error("--profile is required unless --list is used")

    if args.check:
        temporary = tempfile.TemporaryDirectory(prefix="p25-test-station-")
        evidence_dir = Path(temporary.name)
    else:
        temporary = None
        evidence_dir = (
            Path(args.evidence_dir).resolve()
            if args.evidence_dir
            else project / "build/p25-test-station" / args.profile
        )
        evidence_dir.mkdir(parents=True, exist_ok=True)

    try:
        report = run_profile(project, args.profile, evidence_dir)
        if args.check:
            print(json.dumps(report, indent=2, sort_keys=True))
        else:
            path = evidence_dir / "test-station-report.json"
            path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            print(path)
        return 0 if report["resultState"] == "PASS" else 1
    finally:
        if temporary is not None:
            temporary.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
