#!/usr/bin/env python3
"""Work-Order-aware governance-drift gate for Mission Execution 1.5."""
from __future__ import annotations

import argparse
import fnmatch
import json
import pathlib
import subprocess
import sys

from mission_runtime_model import BUILD_TYPES, validate_runtime_state

GOVERNANCE_PATTERNS = [
    "docs/roadmap/missions/**",
    "docs/roadmap/anarchy/**",
    "schemas/mission_*.json",
    "config/mission_*.json",
    "config/mission*.json",
    "tool/mission_*.py",
    ".github/workflows/mission-*.yml",
]
EXEMPT_TYPES = {
    "CI_REPAIR",
    "AUTHORITY_UPDATE",
    "BLOCKER_REMOVAL",
    "EVIDENCE_FINALIZATION",
    "RELEASE_FINALIZATION",
}


def _matches(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def numstat(project: pathlib.Path, base: str, head: str) -> list[tuple[int, int, str]]:
    result = subprocess.run(
        ["git", "diff", "--numstat", f"{base}..{head}", "--"],
        cwd=project,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError(f"git diff failed: {result.stderr.strip()}")
    rows = []
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        added, deleted, path = line.split("\t", 2)
        rows.append((0 if added == "-" else int(added), 0 if deleted == "-" else int(deleted), path.replace("\\", "/")))
    return rows


def audit(
    repository_project: pathlib.Path,
    runtime_project: pathlib.Path,
    base: str,
    head: str,
    head_branch: str,
    threshold: int,
) -> dict:
    state = validate_runtime_state(runtime_project)
    matches = [
        sem
        for sem in state["activeSemaphores"]
        if sem.get("kind") == "WRITE" and sem.get("branch") == head_branch
    ]
    if len(matches) > 1:
        raise ValueError(f"multiple active WRITE semaphores match branch {head_branch}")
    if not matches:
        return {
            "schemaVersion": 1,
            "headBranch": head_branch,
            "bound": False,
            "disposition": "NO_ACTIVE_WORK_ORDER_FOR_BRANCH",
            "pass": True,
        }
    sem = matches[0]
    work = state["workOrders"][sem["workOrderId"]]
    rows = numstat(repository_project, base, head)
    governance_added = sum(added for added, _, path in rows if _matches(path, GOVERNANCE_PATTERNS))
    non_governance_added = sum(added for added, _, path in rows if not _matches(path, GOVERNANCE_PATTERNS))
    governance_files = sorted(path for _, _, path in rows if _matches(path, GOVERNANCE_PATTERNS))
    substantive_files = sorted(path for _, _, path in rows if not _matches(path, GOVERNANCE_PATTERNS))
    product_work = work["type"] in BUILD_TYPES
    exempt = work["type"] in EXEMPT_TYPES
    violation = (
        product_work
        and not exempt
        and non_governance_added == 0
        and governance_added > threshold
    )
    result = {
        "schemaVersion": 1,
        "headBranch": head_branch,
        "bound": True,
        "workOrderId": work["workOrderId"],
        "workOrderType": work["type"],
        "productWork": product_work,
        "governanceAdded": governance_added,
        "nonGovernanceAdded": non_governance_added,
        "governanceFiles": governance_files,
        "substantiveFiles": substantive_files,
        "threshold": threshold,
        "pass": not violation,
        "disposition": "GOVERNANCE_DRIFT" if violation else "PASS",
    }
    if violation:
        raise ValueError(
            f"product Work Order {work['workOrderId']} added {governance_added} governance lines with no substantive product/test/integration additions"
        )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository-project", default=".")
    parser.add_argument("--runtime-project", required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--head-branch", required=True)
    parser.add_argument("--threshold", type=int, default=200)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = audit(
            pathlib.Path(args.repository_project).resolve(),
            pathlib.Path(args.runtime_project).resolve(),
            args.base,
            args.head,
            args.head_branch,
            args.threshold,
        )
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_GOVERNANCE_DRIFT_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
