#!/usr/bin/env python3
"""Mission Execution 1.5 branch/runtime hygiene gate.

Branch count is hygiene pressure, not a global execution mutex. Generic audit
reports soft/hard capacity state but only enforces the hard ceiling when the
caller explicitly asks to create a new branch. Correctness hazards such as new
runtime transaction branches and expired ACTIVE semaphores remain fail-closed.
"""
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



def _is_immutable_pull_head_ref(branch: str) -> bool:
    parts = branch.split("/")
    return (
        len(parts) == 3
        and parts[0] == "pull"
        and parts[1].isdigit()
        and parts[2] == "head"
    )

def _positive_int(value: object, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError(f"{label} must be a positive integer")
    return value


def classify_branch_capacity(
    config: dict,
    *,
    total_branch_count: int,
    legacy_debt_count: int,
    helper_branch_count: int,
) -> dict:
    migration = config["migration"]
    capacity = config.get("branchCapacity") or {}
    soft_target = _positive_int(
        capacity.get(
            "softTotalBranchTarget",
            migration.get("maxTotalBranchesDuringMigration", 60),
        ),
        "branchCapacity.softTotalBranchTarget",
    )
    hard_ceiling = _positive_int(
        capacity.get(
            "hardNewBranchCreationCeiling",
            migration.get("maxTotalBranchesDuringMigration", 60),
        ),
        "branchCapacity.hardNewBranchCreationCeiling",
    )
    if hard_ceiling <= soft_target:
        raise ValueError(
            "branchCapacity.hardNewBranchCreationCeiling must exceed "
            "softTotalBranchTarget"
        )

    warnings: list[str] = []
    if total_branch_count > soft_target:
        warnings.append(
            f"TOTAL_BRANCH_SOFT_TARGET:{total_branch_count}>{soft_target}"
        )
    legacy_limit = _positive_int(
        migration["maxLegacyDebtBranchesDuringMigration"],
        "migration.maxLegacyDebtBranchesDuringMigration",
    )
    if legacy_debt_count > legacy_limit:
        warnings.append(
            f"LEGACY_DEBT_PRESSURE:{legacy_debt_count}>{legacy_limit}"
        )
    helper_limit = _positive_int(
        migration["maxActiveHelperBranches"],
        "migration.maxActiveHelperBranches",
    )
    if helper_branch_count > helper_limit:
        warnings.append(
            f"HELPER_BRANCH_PRESSURE:{helper_branch_count}>{helper_limit}"
        )

    return {
        "softTotalBranchTarget": soft_target,
        "hardNewBranchCreationCeiling": hard_ceiling,
        "newBranchCreationBlocked": total_branch_count >= hard_ceiling,
        "warnings": warnings,
    }


def audit(
    repository_project: pathlib.Path,
    runtime_project: pathlib.Path,
    config_path: pathlib.Path,
    *,
    check_new_branch_capacity: bool = False,
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
    immutable_pull_head_refs = sorted(
        branch for branch in refs if _is_immutable_pull_head_ref(branch)
    )
    branches = sorted(
        {
            branch
            for branch in refs
            if branch != "HEAD" and not _is_immutable_pull_head_ref(branch)
        }
    )
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

    capacity = classify_branch_capacity(
        config,
        total_branch_count=len(branches),
        legacy_debt_count=len(debt),
        helper_branch_count=len(helpers),
    )

    violations: list[str] = []
    if check_new_branch_capacity and capacity["newBranchCreationBlocked"]:
        violations.append(
            "NEW_BRANCH_CREATION_CEILING:"
            f"{len(branches)}>={capacity['hardNewBranchCreationCeiling']}"
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
        "immutablePullHeadRefCount": len(immutable_pull_head_refs),
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
        "branchCapacity": capacity,
        "capacityWarnings": capacity["warnings"],
        "newBranchCapacityEnforced": check_new_branch_capacity,
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
    parser.add_argument(
        "--check-new-branch-capacity",
        action="store_true",
        help=(
            "Enforce the hard total-branch ceiling for an operation that would "
            "create a new remote branch. Generic hygiene audits intentionally "
            "do not turn branch count into a global execution mutex."
        ),
    )
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = audit(
            pathlib.Path(args.repository_project).resolve(),
            pathlib.Path(args.runtime_project).resolve(),
            pathlib.Path(args.config).resolve(),
            check_new_branch_capacity=args.check_new_branch_capacity,
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
