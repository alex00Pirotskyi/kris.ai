#!/usr/bin/env python3
"""Mission Execution 1.5 branch/runtime hygiene gate."""
from __future__ import annotations

import argparse
import fnmatch
import json
import pathlib
import subprocess
import sys

from mission_runtime_model import parse_time, utc_now, validate_runtime_state


def git_lines(project: pathlib.Path, *args: str) -> list[str]:
    result = subprocess.run(
        ["git", *args],
        cwd=project,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def _matches(branch: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(branch, pattern) for pattern in patterns)


def audit(
    repository_project: pathlib.Path,
    runtime_project: pathlib.Path,
    config_path: pathlib.Path,
) -> dict:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if config.get("schemaVersion") != 1:
        raise ValueError("invalid mission_v15_hygiene schemaVersion")
    refs = git_lines(
        repository_project,
        "for-each-ref",
        "--format=%(refname:strip=3)",
        "refs/remotes/origin",
    )
    branches = sorted({branch for branch in refs if branch != "HEAD"})
    # Local default main may not appear under refs/remotes/origin when a caller
    # intentionally fetched only named branches. Count it if available.
    if "main" not in branches:
        main_exists = subprocess.run(
            ["git", "show-ref", "--verify", "--quiet", "refs/heads/main"],
            cwd=repository_project,
            check=False,
        ).returncode == 0
        if main_exists:
            branches.append("main")
            branches.sort()

    migration = config["migration"]
    debt = sorted(
        branch
        for branch in branches
        if _matches(branch, config.get("legacyDebtPatterns", []))
    )
    helpers = sorted(
        branch
        for branch in branches
        if fnmatch.fnmatchcase(branch, config.get("helperPattern", "agent/help/*"))
    )
    tx_prefix = migration.get("runtimeTransactionBranchPrefix", "runtime/tx/")
    transaction_branches = sorted(
        branch for branch in branches if branch.startswith(tx_prefix)
    )
    grandfathered_transactions = set(
        migration.get("grandfatheredRuntimeTransactionBranches", [])
    )
    new_transaction_branches = sorted(
        branch for branch in transaction_branches if branch not in grandfathered_transactions
    )

    violations: list[str] = []
    if len(branches) > migration["maxTotalBranchesDuringMigration"]:
        violations.append(
            f"TOTAL_BRANCH_BUDGET:{len(branches)}>{migration['maxTotalBranchesDuringMigration']}"
        )
    if len(debt) > migration["maxLegacyDebtBranchesDuringMigration"]:
        violations.append(
            f"LEGACY_DEBT_GROWTH:{len(debt)}>{migration['maxLegacyDebtBranchesDuringMigration']}"
        )
    if len(helpers) > migration["maxActiveHelperBranches"]:
        violations.append(
            f"HELPER_BRANCH_BUDGET:{len(helpers)}>{migration['maxActiveHelperBranches']}"
        )
    if len(transaction_branches) > migration["maxRuntimeTransactionBranchesDuringMigration"]:
        violations.append(
            "RUNTIME_TRANSACTION_BRANCH_GROWTH:"
            f"{len(transaction_branches)}>{migration['maxRuntimeTransactionBranchesDuringMigration']}"
        )
    if new_transaction_branches:
        violations.append(
            "NEW_RUNTIME_TRANSACTION_BRANCHES:" + ",".join(new_transaction_branches)
        )

    state = validate_runtime_state(runtime_project)
    now = utc_now()
    expired_active = sorted(
        item["semaphoreId"]
        for item in state["semaphores"]
        if item.get("status") == "ACTIVE" and parse_time(item["expiresAt"]) <= now
    )
    if expired_active:
        violations.append("EXPIRED_ACTIVE_SEMAPHORES:" + ",".join(expired_active))

    result = {
        "schemaVersion": 1,
        "totalBranchCount": len(branches),
        "legacyDebtBranchCount": len(debt),
        "legacyDebtBranches": debt,
        "helperBranchCount": len(helpers),
        "helperBranches": helpers,
        "runtimeTransactionBranchCount": len(transaction_branches),
        "runtimeTransactionBranches": transaction_branches,
        "grandfatheredRuntimeTransactionBranches": sorted(grandfathered_transactions),
        "newRuntimeTransactionBranches": new_transaction_branches,
        "runtimeGeneration": state["meta"]["runtimeGeneration"],
        "workOrderCount": len(state["workOrders"]),
        "activeSemaphoreCount": len(state["activeSemaphores"]),
        "expiredActiveSemaphores": expired_active,
        "target": config["target"],
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
    parser.add_argument("--config", default="config/mission_v15_hygiene.v1.json")
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = audit(
            pathlib.Path(args.repository_project).resolve(),
            pathlib.Path(args.runtime_project).resolve(),
            pathlib.Path(args.config).resolve(),
        )
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_HYGIENE_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
