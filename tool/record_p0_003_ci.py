#!/usr/bin/env python3
"""Validate and record the same-commit three-OS P0-003 GitHub CI matrix."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any

FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
LANES = {
    "ubuntu": ("validate-ubuntu", "Linux"),
    "windows": ("validate-windows", "Windows"),
    "macos": ("validate-macos", "Darwin"),
}


class EvidenceError(RuntimeError):
    pass


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise EvidenceError(f"missing evidence file: {path}") from error
    except json.JSONDecodeError as error:
        raise EvidenceError(f"invalid JSON in {path}: {error}") from error
    if not isinstance(value, dict):
        raise EvidenceError(f"{path} root must be an object")
    return value


def current_head(project: Path) -> str | None:
    if not (project / ".git").exists():
        return None
    completed = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=project, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, check=False,
    )
    if completed.returncode != 0:
        raise EvidenceError("git rev-parse HEAD failed: " + completed.stderr.strip())
    value = completed.stdout.strip()
    if FULL_SHA.fullmatch(value) is None:
        raise EvidenceError(f"invalid Git HEAD: {value!r}")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_https_url(value: str, option: str) -> str:
    """Strip host newline translation while preserving an HTTPS evidence URL."""
    normalized = value.strip()
    if not normalized.startswith("https://"):
        raise EvidenceError(f"{option} must be HTTPS")
    return normalized


def validate_environment(path: Path, lane: str, commit: str) -> dict[str, Any]:
    payload = load_object(path)
    runner = payload.get("runner")
    if not isinstance(runner, dict):
        raise EvidenceError(f"{path}: runner must be an object")
    expected_check, expected_platform = LANES[lane]
    failures: list[str] = []
    if payload.get("milestone") != "P0-003":
        failures.append("milestone is not P0-003")
    if runner.get("gitSha") != commit:
        failures.append(f"gitSha {runner.get('gitSha')!r} does not equal {commit}")
    if runner.get("os") != expected_platform:
        failures.append(f"runner.os {runner.get('os')!r} is not {expected_platform!r}")
    python = payload.get("python")
    if not isinstance(python, dict) or not python.get("version"):
        failures.append("Python version is missing")
    for key in ("dart", "flutter", "git"):
        item = payload.get(key)
        if not isinstance(item, dict) or item.get("available") is not True:
            failures.append(f"{key} evidence is unavailable")
    if failures:
        raise EvidenceError(f"{path} failed validation:\n- " + "\n- ".join(failures))
    return {
        "path": path.as_posix(),
        "sha256": sha256(path),
        "checkName": expected_check,
        "runner": runner,
        "python": python,
        "dart": payload["dart"],
        "flutter": payload["flutter"],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--commit", required=True)
    parser.add_argument("--workflow-run-url", required=True)
    for lane in LANES:
        parser.add_argument(f"--{lane}-job-url", required=True)
        parser.add_argument(f"--{lane}-environment", required=True)
    parser.add_argument("--output", default="release/evidence/P0-003/ci_matrix.json")
    parser.add_argument("--allow-non-head", action="store_true")
    args = parser.parse_args()

    project = Path(args.project).expanduser().resolve()
    commit = args.commit.lower()
    if FULL_SHA.fullmatch(commit) is None:
        raise EvidenceError("--commit must be a full 40-character lowercase Git SHA")
    workflow_run_url = normalize_https_url(args.workflow_run_url, "--workflow-run-url")
    head = current_head(project)
    if head and head != commit and not args.allow_non_head:
        raise EvidenceError(f"recorded commit {commit} does not equal current HEAD {head}")

    lanes: dict[str, Any] = {}
    for lane, (check_name, _platform) in LANES.items():
        job_url = normalize_https_url(
            getattr(args, f"{lane}_job_url"), f"--{lane}-job-url"
        )
        env_path = Path(getattr(args, f"{lane}_environment"))
        if not env_path.is_absolute():
            env_path = project / env_path
        evidence = validate_environment(env_path, lane, commit)
        try:
            relative = env_path.relative_to(project).as_posix()
        except ValueError:
            relative = env_path.as_posix()
        lanes[lane] = {
            "checkName": check_name,
            "jobUrl": job_url,
            "status": "passed",
            "nativeBuild": "passed",
            "environmentEvidence": relative,
            "environmentSha256": evidence["sha256"],
        }

    payload = {
        "schemaVersion": "1.0.0",
        "milestone": "P0-003",
        "status": "passed",
        "commit": commit,
        "workflowRunUrl": workflow_run_url,
        "lanes": lanes,
        "closureRule": "All three stable checks and native builds passed for this exact commit.",
    }
    output = Path(args.output)
    if not output.is_absolute():
        output = project / output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({**payload, "output": str(output)}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvidenceError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
