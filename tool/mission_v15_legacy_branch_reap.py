#!/usr/bin/env python3
"""Validate one exact Mission Execution 1.5 legacy-debt branch reap.

This module never deletes a ref itself. It proves that one immutable runtime
command is eligible to be handed to the repository's existing fail-closed
``tool/branch_hygiene.py`` executor.

Eligibility is deliberately narrow:

* exact current runtime generation;
* INTEGRATING ``BLOCKER_REMOVAL`` Work Order;
* matching zero-write Product-PR INTEGRATION semaphore;
* target matches the configured Mission v1.5 legacy-debt patterns;
* target is not main, the runtime/control branch, a canonical Product PR
  branch, or a branch held by any active semaphore;
* exact target ref exists at the command's reviewed SHA.

The downstream branch-hygiene executor additionally rejects protected/default
branches, open-PR heads, SHA movement and post-delete residual refs.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import pathlib
import sys
from typing import Any

from mission_delivery_lib import run_git
from mission_runtime_model import validate_runtime_state

COMMAND_SCHEMA_VERSION = 1
OPERATION = "DELETE_EXACT_LEGACY_BRANCH_V1"
HYGIENE_CONFIG = pathlib.Path("config/mission_v15_hygiene.v1.json")


def read_json(path: pathlib.Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def validate_command_shape(command: dict[str, Any], command_path: pathlib.Path) -> None:
    required = {
        "schemaVersion",
        "commandId",
        "operation",
        "expectedRuntimeGeneration",
        "workOrderId",
        "semaphoreId",
        "workerIdentity",
        "productPr",
        "targetBranch",
        "expectedTargetHead",
    }
    optional = {"createdAt", "note"}
    missing = sorted(required - set(command))
    extra = sorted(set(command) - required - optional)
    if missing:
        raise ValueError(f"legacy-branch command missing fields: {missing}")
    if extra:
        raise ValueError(f"legacy-branch command has unsupported fields: {extra}")
    if command.get("schemaVersion") != COMMAND_SCHEMA_VERSION:
        raise ValueError("unsupported legacy-branch command schemaVersion")
    if command.get("operation") != OPERATION:
        raise ValueError(f"unsupported legacy-branch operation {command.get('operation')}")
    if pathlib.PurePosixPath(command_path).stem != command.get("commandId"):
        raise ValueError("commandId must match command filename")
    if not isinstance(command.get("expectedRuntimeGeneration"), int):
        raise ValueError("expectedRuntimeGeneration must be an integer")
    if not isinstance(command.get("productPr"), int) or command["productPr"] <= 0:
        raise ValueError("productPr must be a positive integer")
    branch = command.get("targetBranch")
    if not isinstance(branch, str) or not branch or branch.startswith("/") or branch.endswith("/"):
        raise ValueError("targetBranch must be a non-empty branch name")
    head = command.get("expectedTargetHead")
    if (
        not isinstance(head, str)
        or len(head) != 40
        or any(character not in "0123456789abcdef" for character in head)
    ):
        raise ValueError("expectedTargetHead must be a full lowercase Git SHA")
    for key in ("workOrderId", "semaphoreId", "workerIdentity"):
        if not isinstance(command.get(key), str) or not command[key]:
            raise ValueError(f"{key} must be non-empty")


def cleanup_class_for(branch: str, patterns: list[str]) -> str:
    if not any(fnmatch.fnmatchcase(branch, pattern) for pattern in patterns):
        raise ValueError(f"target branch is not configured Mission v1.5 legacy debt: {branch}")
    if branch.startswith(("validation/", "validated/")):
        return "failure-snapshot"
    return "superseded-repair"


def _git(project: pathlib.Path, *args: str) -> str:
    return run_git(project, *args)


def prepare_reap(project: pathlib.Path, command_path: pathlib.Path) -> dict[str, Any]:
    command = read_json(command_path)
    validate_command_shape(command, command_path)

    state = validate_runtime_state(project)
    generation = state["meta"]["runtimeGeneration"]
    if generation != command["expectedRuntimeGeneration"]:
        raise ValueError(
            f"runtime generation moved: expected {command['expectedRuntimeGeneration']}, actual {generation}"
        )

    work = state["workOrders"].get(command["workOrderId"])
    if work is None:
        raise ValueError(f"unknown Work Order {command['workOrderId']}")
    if work.get("type") != "BLOCKER_REMOVAL" or work.get("status") != "INTEGRATING":
        raise ValueError(
            f"Work Order must be INTEGRATING BLOCKER_REMOVAL, got {work.get('type')} / {work.get('status')}"
        )
    if work.get("parentProductPr") != command["productPr"]:
        raise ValueError("Work Order parentProductPr differs from command productPr")
    if work.get("activeSemaphoreId") != command["semaphoreId"]:
        raise ValueError("Work Order activeSemaphoreId differs from command semaphoreId")

    matches = [
        semaphore
        for semaphore in state["activeSemaphores"]
        if semaphore.get("semaphoreId") == command["semaphoreId"]
    ]
    if len(matches) != 1:
        raise ValueError("command requires exactly one matching active semaphore")
    semaphore = matches[0]
    if semaphore.get("kind") != "INTEGRATION":
        raise ValueError("legacy-branch reap requires INTEGRATION semaphore")
    if semaphore.get("workOrderId") != work["workOrderId"]:
        raise ValueError("INTEGRATION semaphore Work Order mismatch")
    if semaphore.get("workerIdentity") != command["workerIdentity"]:
        raise ValueError("INTEGRATION semaphore workerIdentity mismatch")
    if semaphore.get("productPr") != command["productPr"]:
        raise ValueError("INTEGRATION semaphore Product PR mismatch")
    if semaphore.get("allowedPaths") not in ([], None):
        raise ValueError("legacy-branch reap semaphore must authorize zero writable paths")

    target = command["targetBranch"]
    product_branches = {
        item.get("branch")
        for item in state["productPrs"].values()
        if isinstance(item.get("branch"), str)
    }
    active_semaphore_branches = {
        item.get("branch")
        for item in state["activeSemaphores"]
        if isinstance(item.get("branch"), str)
    }
    control_branch = state["meta"].get("controlPlaneBranch")
    forbidden = {"main", "agent/mission-runtime", control_branch}
    if target in forbidden:
        raise ValueError(f"target branch is a protected Mission v1.5 authority ref: {target}")
    if target in product_branches:
        raise ValueError(f"target branch is canonical for a Product PR: {target}")
    if target in active_semaphore_branches:
        raise ValueError(f"target branch is held by an active semaphore: {target}")

    hygiene = read_json(project / HYGIENE_CONFIG)
    patterns = hygiene.get("legacyDebtPatterns")
    if not isinstance(patterns, list) or not all(isinstance(item, str) for item in patterns):
        raise ValueError("Mission v1.5 hygiene legacyDebtPatterns are invalid")
    cleanup_class = cleanup_class_for(target, patterns)

    remote = _git(project, "ls-remote", "origin", f"refs/heads/{target}").split()
    if len(remote) < 2:
        raise ValueError(f"target branch is missing: {target}")
    observed = remote[0]
    if observed != command["expectedTargetHead"]:
        raise ValueError(
            f"target branch moved: expected {command['expectedTargetHead']}, actual {observed}"
        )

    return {
        "schemaVersion": 1,
        "commandId": command["commandId"],
        "operation": OPERATION,
        "runtimeGeneration": generation,
        "workOrderId": work["workOrderId"],
        "semaphoreId": semaphore["semaphoreId"],
        "productPr": command["productPr"],
        "targetBranch": target,
        "expectedTargetHead": observed,
        "cleanupClass": cleanup_class,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--command", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = prepare_reap(
            pathlib.Path(args.project).resolve(),
            pathlib.Path(args.command).resolve(),
        )
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_LEGACY_BRANCH_REAP_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
