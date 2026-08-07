#!/usr/bin/env python3
"""Exact-SHA canonical Product PR gate for Mission Execution 1.5."""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

from mission_delivery_lib import run_git
from mission_runtime_model import validate_runtime_state


def validate_product_candidate(
    runtime_project: pathlib.Path,
    repository_project: pathlib.Path,
    product_pr: int,
    candidate_commit: str,
    candidate_tree: str,
) -> dict:
    state = validate_runtime_state(runtime_project)
    product = state["productPrs"].get(product_pr)
    if product is None:
        return {
            "schemaVersion": 1,
            "canonicalProductPr": False,
            "productPr": product_pr,
            "candidateCommit": candidate_commit,
            "candidateTree": candidate_tree,
            "disposition": "NOT_CANONICAL_PRODUCT_PR",
        }
    run_git(repository_project, "cat-file", "-e", f"{candidate_commit}^{{commit}}")
    actual_tree = run_git(repository_project, "rev-parse", f"{candidate_commit}^{{tree}}")
    if actual_tree != candidate_tree:
        raise ValueError(
            f"Product PR candidate commit/tree mismatch: {candidate_commit} -> {actual_tree}, supplied {candidate_tree}"
        )
    work_orders = [
        {k: v for k, v in item.items() if k != "_path"}
        for item in state["workOrders"].values()
        if item["parentProductPr"] == product_pr
    ]
    unresolved = [
        item["workOrderId"]
        for item in work_orders
        if item["status"] not in {"LANDED", "SUPERSEDED", "CANCELLED"}
    ]
    active_integration = [
        item["semaphoreId"]
        for item in state["activeSemaphores"]
        if item["kind"] == "INTEGRATION" and item.get("productPr") == product_pr
    ]
    return {
        "schemaVersion": 1,
        "canonicalProductPr": True,
        "productPr": product_pr,
        "task": product["task"],
        "mission": product["mission"],
        "candidateCommit": candidate_commit,
        "candidateTree": candidate_tree,
        "runtimeGeneration": state["meta"]["runtimeGeneration"],
        "workOrderCount": len(work_orders),
        "unresolvedWorkOrders": sorted(unresolved),
        "activeIntegrationSemaphores": sorted(active_integration),
        "disposition": "CANONICAL_PRODUCT_PR_VALID",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-project", required=True)
    parser.add_argument("--repository-project", default=".")
    parser.add_argument("--product-pr", type=int, required=True)
    parser.add_argument("--candidate-commit", required=True)
    parser.add_argument("--candidate-tree", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = validate_product_candidate(
            pathlib.Path(args.runtime_project).resolve(),
            pathlib.Path(args.repository_project).resolve(),
            args.product_pr,
            args.candidate_commit,
            args.candidate_tree,
        )
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_PRODUCT_GATE_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
