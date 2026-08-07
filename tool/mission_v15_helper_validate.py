#!/usr/bin/env python3
"""Validate a Mission Execution 1.5 helper candidate against runtime authority."""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

from mission_delivery_lib import matches_any, run_git
from mission_runtime_control import verify_candidate_ancestry
from mission_runtime_model import validate_runtime_state


def changed_paths(project: pathlib.Path, base: str, head: str) -> tuple[str, list[str]]:
    merge_base = run_git(project, "merge-base", base, head)
    output = run_git(
        project,
        "diff",
        "--name-only",
        "--diff-filter=ACDMRTUXB",
        f"{merge_base}..{head}",
        "--",
    )
    return merge_base, [line.strip().replace("\\", "/") for line in output.splitlines() if line.strip()]


def validate_helper(
    runtime_project: pathlib.Path,
    repository_project: pathlib.Path,
    *,
    base_branch: str,
    head_branch: str,
    candidate_commit: str,
    candidate_tree: str,
) -> dict:
    state = validate_runtime_state(runtime_project)
    run_git(repository_project, "cat-file", "-e", f"{candidate_commit}^{{commit}}")
    actual_tree = run_git(repository_project, "rev-parse", f"{candidate_commit}^{{tree}}")
    if actual_tree != candidate_tree:
        raise ValueError(
            f"helper candidate commit/tree mismatch: {candidate_commit} -> {actual_tree}, supplied {candidate_tree}"
        )

    matches = [
        sem
        for sem in state["activeSemaphores"]
        if sem.get("kind") == "WRITE" and sem.get("branch") == head_branch
    ]
    if len(matches) != 1:
        raise ValueError(
            f"helper branch must match exactly one active WRITE semaphore: {head_branch}, matches={len(matches)}"
        )
    sem = matches[0]
    work = state["workOrders"][sem["workOrderId"]]
    product = state["productPrs"][work["parentProductPr"]]
    if product["branch"] != base_branch:
        raise ValueError(
            f"helper PR base {base_branch} is not canonical Product PR branch {product['branch']}"
        )
    if sem["mission"] != work["mission"] or product["mission"] != work["mission"]:
        raise ValueError("helper mission/Work Order/Product PR binding mismatch")
    if sem["baseCommit"] != work["baseCommit"] or sem["baseTree"] != work["baseTree"]:
        raise ValueError("WRITE semaphore must preserve exact Work Order base commit/tree")
    verify_candidate_ancestry(repository_project, sem["baseCommit"], candidate_commit)
    merge_base, paths = changed_paths(repository_project, sem["baseCommit"], candidate_commit)
    violations = [path for path in paths if not matches_any(path, sem["allowedPaths"])]
    if violations:
        raise ValueError(
            "helper changed paths outside WRITE semaphore: " + ", ".join(sorted(violations))
        )
    return {
        "schemaVersion": 1,
        "runtimeGeneration": state["meta"]["runtimeGeneration"],
        "workOrderId": work["workOrderId"],
        "mission": work["mission"],
        "roadmapTask": work["roadmapTask"],
        "productPr": work["parentProductPr"],
        "semaphoreId": sem["semaphoreId"],
        "helperBranch": head_branch,
        "canonicalProductBranch": base_branch,
        "reservedBaseCommit": sem["baseCommit"],
        "mergeBase": merge_base,
        "candidateCommit": candidate_commit,
        "candidateTree": candidate_tree,
        "changedPaths": paths,
        "allowedPaths": sem["allowedPaths"],
        "authorized": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-project", required=True)
    parser.add_argument("--repository-project", default=".")
    parser.add_argument("--base-branch", required=True)
    parser.add_argument("--head-branch", required=True)
    parser.add_argument("--candidate-commit", required=True)
    parser.add_argument("--candidate-tree", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = validate_helper(
            pathlib.Path(args.runtime_project).resolve(),
            pathlib.Path(args.repository_project).resolve(),
            base_branch=args.base_branch,
            head_branch=args.head_branch,
            candidate_commit=args.candidate_commit,
            candidate_tree=args.candidate_tree,
        )
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_HELPER_VALIDATE_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
