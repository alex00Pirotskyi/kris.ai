#!/usr/bin/env python3
"""Validate a bounded Mission Execution 1.5 exact Product PR CI dispatch.

This module does not execute arbitrary commands and does not mutate product
source. It may only authorize dispatch of the repository's existing ``ci.yml``
workflow for the exact observed head of one canonical Product PR while a live
Product-PR-scoped INTEGRATION semaphore is held by a CI_REPAIR Work Order.

The active INTEGRATION semaphore is intentionally required even though this
operation performs no merge. It freezes the canonical Product PR head while
GitHub allocates the workflow_dispatch run, so the resulting run can be bound
back to ``expectedProductHead`` without a source-history trigger commit.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

from mission_delivery_lib import run_git
from mission_runtime_control import verify_git_base
from mission_runtime_model import validate_runtime_state

COMMAND_SCHEMA_VERSION = 1
OPERATION = "DISPATCH_EXACT_PRODUCT_GATES_V1"
WORKFLOW_FILE = "ci.yml"


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
        "expectedProductHead",
    }
    optional = {"createdAt", "note"}
    missing = sorted(required - set(command))
    extra = sorted(set(command) - required - optional)
    if missing:
        raise ValueError(f"exact-product-CI command missing fields: {missing}")
    if extra:
        raise ValueError(f"exact-product-CI command has unsupported fields: {extra}")
    if command.get("schemaVersion") != COMMAND_SCHEMA_VERSION:
        raise ValueError("unsupported exact-product-CI command schemaVersion")
    if command.get("operation") != OPERATION:
        raise ValueError(f"unsupported exact-product-CI operation {command.get('operation')}")
    if pathlib.PurePosixPath(command_path).stem != command.get("commandId"):
        raise ValueError("commandId must match command filename")
    if not isinstance(command.get("expectedRuntimeGeneration"), int):
        raise ValueError("expectedRuntimeGeneration must be an integer")
    if not isinstance(command.get("productPr"), int) or command["productPr"] <= 0:
        raise ValueError("productPr must be a positive integer")
    head = command.get("expectedProductHead")
    if (
        not isinstance(head, str)
        or len(head) != 40
        or any(character not in "0123456789abcdef" for character in head)
    ):
        raise ValueError("expectedProductHead must be a full lowercase Git SHA")
    for key in ("workOrderId", "semaphoreId", "workerIdentity"):
        if not isinstance(command.get(key), str) or not command[key]:
            raise ValueError(f"{key} must be non-empty")


def _git(project: pathlib.Path, *args: str) -> str:
    return run_git(project, *args)


def prepare_dispatch(project: pathlib.Path, command_path: pathlib.Path) -> dict[str, Any]:
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
    if work.get("type") != "CI_REPAIR" or work.get("status") != "INTEGRATING":
        raise ValueError(
            f"Work Order must be INTEGRATING CI_REPAIR, got {work.get('type')} / {work.get('status')}"
        )
    if work.get("parentProductPr") != command["productPr"]:
        raise ValueError("Work Order parentProductPr differs from command productPr")
    if work.get("activeSemaphoreId") != command["semaphoreId"]:
        raise ValueError("Work Order activeSemaphoreId differs from command semaphoreId")
    if work.get("baseCommit") != command["expectedProductHead"]:
        raise ValueError("Work Order baseCommit differs from expectedProductHead")
    verify_git_base(project, work["baseCommit"], work["baseTree"])

    matches = [
        semaphore
        for semaphore in state["activeSemaphores"]
        if semaphore.get("semaphoreId") == command["semaphoreId"]
    ]
    if len(matches) != 1:
        raise ValueError("command requires exactly one matching active semaphore")
    semaphore = matches[0]
    if semaphore.get("kind") != "INTEGRATION":
        raise ValueError("exact-product-CI dispatch requires INTEGRATION semaphore")
    if semaphore.get("workOrderId") != work["workOrderId"]:
        raise ValueError("INTEGRATION semaphore Work Order mismatch")
    if semaphore.get("workerIdentity") != command["workerIdentity"]:
        raise ValueError("INTEGRATION semaphore workerIdentity mismatch")
    if semaphore.get("productPr") != command["productPr"]:
        raise ValueError("INTEGRATION semaphore Product PR mismatch")
    if semaphore.get("allowedPaths") not in ([], None):
        raise ValueError("exact-product-CI INTEGRATION semaphore must not authorize writable paths")

    product = state["productPrs"].get(command["productPr"])
    if product is None:
        raise ValueError(f"unknown canonical Product PR #{command['productPr']}")
    if product.get("observedHead") != command["expectedProductHead"]:
        raise ValueError("canonical Product PR observedHead differs from expectedProductHead")
    branch = product.get("branch")
    if not isinstance(branch, str) or not branch:
        raise ValueError("canonical Product PR branch is missing")
    if semaphore.get("branch") != branch:
        raise ValueError("INTEGRATION semaphore branch differs from canonical Product PR branch")

    _git(project, "fetch", "--no-tags", "origin", f"+refs/heads/{branch}:refs/remotes/origin/{branch}")
    remote_head = _git(project, "rev-parse", f"refs/remotes/origin/{branch}")
    if remote_head != command["expectedProductHead"]:
        raise ValueError(
            f"Product PR head moved: expected {command['expectedProductHead']}, actual {remote_head}"
        )

    return {
        "schemaVersion": 1,
        "commandId": command["commandId"],
        "operation": OPERATION,
        "runtimeGeneration": generation,
        "workOrderId": work["workOrderId"],
        "semaphoreId": semaphore["semaphoreId"],
        "productPr": command["productPr"],
        "productBranch": branch,
        "productHead": remote_head,
        "workflowFile": WORKFLOW_FILE,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--command", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = prepare_dispatch(
            pathlib.Path(args.project).resolve(),
            pathlib.Path(args.command).resolve(),
        )
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_EXACT_PRODUCT_CI_DISPATCH_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
