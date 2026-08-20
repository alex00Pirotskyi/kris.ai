#!/usr/bin/env python3
"""Materialize scoped review carry-forward receipts from exact Git diffs."""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

from mission_delivery_checks import git_changed_paths, review_impact
from mission_delivery_lib import load_model, read_json, run_git
from mission_delivery_strict import validate_review_receipt


def carry_forward(
    project: pathlib.Path,
    receipt: dict,
    head: str,
) -> dict:
    model = load_model(project)
    base = receipt.get("candidateCommit")
    if not isinstance(base, str):
        raise ValueError("review receipt missing candidateCommit")
    validate_review_receipt(receipt, candidate_commit=base, record_path=pathlib.Path("review-receipt.json"))
    run_git(project, "cat-file", "-e", f"{base}^{{commit}}")
    run_git(project, "cat-file", "-e", f"{head}^{{commit}}")
    changed = git_changed_paths(project, base, head)
    impact = review_impact(changed, model)
    scopes = sorted(set(receipt.get("scopes") or []))
    if not scopes:
        raise ValueError("review receipt scopes required for carry-forward")
    invalidated = sorted(set(impact["invalidatedScopes"]) & set(scopes))
    if invalidated:
        raise ValueError(
            f"review carry-forward invalidated for scopes {invalidated}: {impact['changedPaths']}"
        )
    result = dict(receipt)
    result["carriedFromCommit"] = base
    result["candidateCommit"] = head
    result["candidateTree"] = run_git(project, "rev-parse", f"{head}^{{tree}}")
    result["carryForwardProof"] = {
        "base": base,
        "head": head,
        "reviewedScopes": scopes,
        "invalidatedScopes": impact["invalidatedScopes"],
        "changedPaths": impact["changedPaths"],
        "classification": impact["classification"],
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--review-receipt", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        project = pathlib.Path(args.project).resolve()
        receipt = read_json(pathlib.Path(args.review_receipt))
        result = carry_forward(project, receipt, args.head)
        pathlib.Path(args.output).write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(
            "MISSION_REVIEW_CARRY_FORWARD_VALID "
            f"base={result['carriedFromCommit']} head={result['candidateCommit']} "
            f"scopes={','.join(result.get('scopes') or [])}"
        )
        return 0
    except Exception as exc:
        print(f"MISSION_REVIEW_CARRY_FORWARD_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
