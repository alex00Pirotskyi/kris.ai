#!/usr/bin/env python3
"""Compare Mission Execution 1.5 runtime bases with live fetched Git refs."""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

from mission_delivery_lib import run_git
from mission_runtime_model import ACTIVE_WORK, validate_runtime_state


def live_branch_head(project: pathlib.Path, branch: str) -> str:
    for ref in (f"refs/remotes/origin/{branch}", f"refs/heads/{branch}"):
        try:
            return run_git(project, "rev-parse", ref)
        except Exception:
            continue
    raise ValueError(f"live branch ref not fetched: {branch}")


def audit(repository_project: pathlib.Path, runtime_project: pathlib.Path) -> dict:
    state = validate_runtime_state(runtime_project)
    products = []
    violations: list[str] = []
    for pr, product in sorted(state["productPrs"].items()):
        live_head = live_branch_head(repository_project, product["branch"])
        work = sorted(
            (
                item
                for item in state["workOrders"].values()
                if item["parentProductPr"] == pr and item["status"] in ACTIVE_WORK
            ),
            key=lambda item: item["workOrderId"],
        )
        stale_ready = []
        for item in work:
            # READY/RESERVED work must be based on the current canonical branch.
            # Once a worker owns an active semaphore, the immutable reservation
            # governs candidate ancestry and the owner branch may move separately.
            if item["status"] in {"READY", "RESERVED"} and item["baseCommit"] != live_head:
                stale_ready.append(item["workOrderId"])
                violations.append(
                    f"STALE_READY_WORK_ORDER:{item['workOrderId']}:{item['baseCommit']}!=LIVE:{live_head}"
                )
        products.append(
            {
                "productPr": pr,
                "task": product["task"],
                "mission": product["mission"],
                "branch": product["branch"],
                "observedHead": product.get("observedHead"),
                "liveHead": live_head,
                "activeWorkOrders": [item["workOrderId"] for item in work],
                "staleReadyWorkOrders": stale_ready,
            }
        )
    result = {
        "schemaVersion": 1,
        "runtimeGeneration": state["meta"]["runtimeGeneration"],
        "products": products,
        "violations": violations,
        "pass": not violations,
    }
    if violations:
        raise ValueError("; ".join(violations))
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository-project", default=".")
    parser.add_argument("--runtime-project", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = audit(
            pathlib.Path(args.repository_project).resolve(),
            pathlib.Path(args.runtime_project).resolve(),
        )
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_LIVE_RUNTIME_AUDIT_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
