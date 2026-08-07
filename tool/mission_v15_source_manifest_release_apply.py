#!/usr/bin/env python3
"""Runner-backed exact RELEASE finalizer for SOURCE_MANIFEST.sha256.

This is intentionally narrow. It can only materialize the canonical source
manifest on the exact observed head of a canonical Product PR while a live
Mission Execution 1.5 RELEASE semaphore authorizes that single generated file.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
import tempfile
from typing import Any

from mission_delivery_lib import run_git
from mission_runtime_control import verify_git_base
from mission_runtime_model import validate_runtime_state

OPERATION = "MATERIALIZE_SOURCE_MANIFEST_V1"
MANIFEST_PATH = "SOURCE_MANIFEST.sha256"


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
        raise ValueError(f"source-manifest release command missing fields: {missing}")
    if extra:
        raise ValueError(f"source-manifest release command has unsupported fields: {extra}")
    if command.get("schemaVersion") != 1:
        raise ValueError("unsupported source-manifest release command schemaVersion")
    if command.get("operation") != OPERATION:
        raise ValueError(f"unsupported source-manifest release operation {command.get('operation')}")
    if pathlib.PurePosixPath(command_path).stem != command.get("commandId"):
        raise ValueError("commandId must match command filename")
    if not isinstance(command.get("expectedRuntimeGeneration"), int):
        raise ValueError("expectedRuntimeGeneration must be an integer")
    if not isinstance(command.get("productPr"), int) or command["productPr"] <= 0:
        raise ValueError("productPr must be a positive integer")
    head = command.get("expectedProductHead")
    if not isinstance(head, str) or len(head) != 40 or any(c not in "0123456789abcdef" for c in head):
        raise ValueError("expectedProductHead must be a full lowercase Git SHA")
    for key in ("workOrderId", "semaphoreId", "workerIdentity"):
        if not isinstance(command.get(key), str) or not command[key]:
            raise ValueError(f"{key} must be non-empty")


def _git(project: pathlib.Path, *args: str) -> str:
    return run_git(project, *args)


def apply_command(project: pathlib.Path, command_path: pathlib.Path) -> dict[str, Any]:
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
    if work.get("type") != "RELEASE_FINALIZATION" or work.get("status") != "IN_PROGRESS":
        raise ValueError(
            f"Work Order must be IN_PROGRESS RELEASE_FINALIZATION, got {work.get('type')} / {work.get('status')}"
        )
    if work.get("parentProductPr") != command["productPr"]:
        raise ValueError("Work Order parentProductPr differs from command productPr")
    if work.get("activeSemaphoreId") != command["semaphoreId"]:
        raise ValueError("Work Order activeSemaphoreId differs from command semaphoreId")
    if work.get("baseCommit") != command["expectedProductHead"]:
        raise ValueError("Work Order baseCommit differs from expectedProductHead")
    if work.get("allowedPaths") != [MANIFEST_PATH]:
        raise ValueError("release Work Order must authorize exactly SOURCE_MANIFEST.sha256")
    verify_git_base(project, work["baseCommit"], work["baseTree"])

    matches = [
        sem
        for sem in state["activeSemaphores"]
        if sem.get("semaphoreId") == command["semaphoreId"]
    ]
    if len(matches) != 1:
        raise ValueError("command requires exactly one matching active RELEASE semaphore")
    semaphore = matches[0]
    if semaphore.get("kind") != "RELEASE":
        raise ValueError("source-manifest finalizer requires RELEASE semaphore")
    if semaphore.get("workOrderId") != work["workOrderId"]:
        raise ValueError("RELEASE semaphore Work Order mismatch")
    if semaphore.get("workerIdentity") != command["workerIdentity"]:
        raise ValueError("RELEASE semaphore workerIdentity mismatch")
    if semaphore.get("resourceId") != MANIFEST_PATH:
        raise ValueError("RELEASE semaphore must bind SOURCE_MANIFEST.sha256")
    if semaphore.get("allowedPaths") != [MANIFEST_PATH]:
        raise ValueError("RELEASE semaphore must authorize exactly SOURCE_MANIFEST.sha256")

    product = state["productPrs"].get(command["productPr"])
    if product is None:
        raise ValueError(f"unknown canonical Product PR #{command['productPr']}")
    if product.get("observedHead") != command["expectedProductHead"]:
        raise ValueError("canonical Product PR observedHead differs from expectedProductHead")
    branch = product.get("branch")
    if not isinstance(branch, str) or not branch:
        raise ValueError("canonical Product PR branch is missing")

    _git(project, "fetch", "--no-tags", "origin", f"+refs/heads/{branch}:refs/remotes/origin/{branch}")
    remote_ref = f"refs/remotes/origin/{branch}"
    remote_head = _git(project, "rev-parse", remote_ref)
    if remote_head != command["expectedProductHead"]:
        raise ValueError(
            f"Product PR head moved: expected {command['expectedProductHead']}, actual {remote_head}"
        )

    with tempfile.TemporaryDirectory(prefix="mission-v15-source-manifest-") as temp:
        worktree = pathlib.Path(temp) / "worktree"
        _git(project, "worktree", "add", "--detach", str(worktree), remote_head)
        try:
            manifest = worktree / MANIFEST_PATH
            before = manifest.read_bytes()
            generator = [sys.executable, "tool/p1a_refresh_source_manifest.py", "."]
            subprocess.run(generator, cwd=worktree, check=True, text=True)
            first = manifest.read_bytes()
            subprocess.run(generator, cwd=worktree, check=True, text=True)
            second = manifest.read_bytes()
            if first != second:
                raise ValueError("canonical source manifest generator is not deterministic")
            if first == before:
                return {
                    "schemaVersion": 1,
                    "commandId": command["commandId"],
                    "operation": OPERATION,
                    "result": "ALREADY_PRESENT",
                    "productPr": command["productPr"],
                    "productHead": remote_head,
                }
            changed = _git(worktree, "diff", "--name-only").splitlines()
            if changed != [MANIFEST_PATH]:
                raise ValueError(f"source-manifest finalizer changed unexpected paths: {changed}")
            subprocess.run(["git", "diff", "--check"], cwd=worktree, check=True, text=True)
            _git(worktree, "config", "user.name", "Mission V1.5 Release Finalizer")
            _git(worktree, "config", "user.email", "mission-v15-release@users.noreply.github.com")
            _git(worktree, "add", "--", MANIFEST_PATH)
            _git(worktree, "commit", "-m", "mission-v15: materialize exact source manifest for landing")
            candidate = _git(worktree, "rev-parse", "HEAD")
            _git(worktree, "push", "origin", f"HEAD:refs/heads/{branch}")
            remote_after = _git(project, "ls-remote", "origin", f"refs/heads/{branch}").split()
            if not remote_after or remote_after[0] != candidate:
                raise ValueError("source-manifest push returned but remote Product PR does not contain candidate")
            return {
                "schemaVersion": 1,
                "commandId": command["commandId"],
                "operation": OPERATION,
                "result": "APPLIED",
                "runtimeGeneration": generation,
                "workOrderId": work["workOrderId"],
                "semaphoreId": semaphore["semaphoreId"],
                "productPr": command["productPr"],
                "productBranch": branch,
                "previousProductHead": remote_head,
                "productHead": candidate,
                "path": MANIFEST_PATH,
            }
        finally:
            subprocess.run(
                ["git", "worktree", "remove", "--force", str(worktree)],
                cwd=project,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--command", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        project = pathlib.Path(args.project).resolve()
        result = apply_command(project, pathlib.Path(args.command).resolve())
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_SOURCE_MANIFEST_RELEASE_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
