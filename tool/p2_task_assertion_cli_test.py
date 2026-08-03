#!/usr/bin/env python3
"""Regression: every real task assertion CLI must emit a result, even blocked.

This test intentionally runs the production task runner for all fourteen tasks.
A missing SDK/backend is allowed to produce a blocked result, but an exception,
traceback, absent output, malformed schema, or task/platform mismatch is not.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
import tempfile

TASKS = [f"P2-{number:03d}" for number in range(1, 15)]
ALLOWED_EXIT_CODES = {0, 3}
ALLOWED_ASSERTION_STATUSES = {
    "passed",
    "failed",
    "blocked",
    "unsupported",
    "source_only",
    "skipped",
    "not_tested",
    "malformed",
    "absent",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--max-command-seconds", type=int, default=20)
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()
    runner = root / "tool/p2_task_platform_assertions.py"
    if not runner.is_file():
        raise SystemExit("task assertion runner missing")

    commit = "b" * 40
    with tempfile.TemporaryDirectory(prefix="p2-task-cli-contract-") as temp_value:
        temp = pathlib.Path(temp_value)
        summaries: dict[str, str] = {}
        for task in TASKS:
            artifact = temp / task / "artifact"
            output = artifact / "task-results" / f"{task}.json"
            command = [
                sys.executable,
                str(runner),
                "--project",
                str(root),
                "--task",
                task,
                "--commit-sha",
                commit,
                "--output",
                str(output),
                "--artifact-root",
                str(artifact),
                "--max-command-seconds",
                str(args.max_command_seconds),
            ]
            completed = subprocess.run(
                command,
                text=True,
                capture_output=True,
                timeout=max(60, args.max_command_seconds * 8),
            )
            if completed.returncode not in ALLOWED_EXIT_CODES:
                raise SystemExit(
                    f"{task}: runner crashed rc={completed.returncode}\n"
                    f"stdout={completed.stdout[-2000:]}\n"
                    f"stderr={completed.stderr[-2000:]}"
                )
            combined = completed.stdout + completed.stderr
            if "Traceback (most recent call last)" in combined or "NameError:" in combined:
                raise SystemExit(f"{task}: runner emitted exception traceback")
            if not output.is_file():
                raise SystemExit(f"{task}: result file missing")
            data = json.loads(output.read_text(encoding="utf-8"))
            if data.get("schemaVersion") != "1.0.0":
                raise SystemExit(f"{task}: wrong schema")
            if data.get("resultType") != "p2-task-observed-result-v1":
                raise SystemExit(f"{task}: wrong result type")
            if data.get("taskId") != task or data.get("commitSha") != commit:
                raise SystemExit(f"{task}: task/commit binding mismatch")
            if data.get("status") not in {"passed", "blocked"}:
                raise SystemExit(f"{task}: invalid aggregate status")
            assertions = data.get("assertions")
            if not isinstance(assertions, list) or not assertions:
                raise SystemExit(f"{task}: assertions missing")
            for row in assertions:
                if not isinstance(row, dict):
                    raise SystemExit(f"{task}: non-object assertion")
                if row.get("taskId") != task or row.get("observedStatus") not in ALLOWED_ASSERTION_STATUSES:
                    raise SystemExit(f"{task}: assertion binding/status invalid")
                evidence = artifact / pathlib.PurePosixPath(str(row.get("evidencePath", "")))
                if not evidence.is_file():
                    raise SystemExit(f"{task}: assertion evidence file missing")
            summaries[task] = str(data["status"])

    print("P2 task assertion CLI all-task execution: PASS")
    print(json.dumps(summaries, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
