#!/usr/bin/env python3
"""Apply the one bounded P4 Test Center registry fixture-path migration.

This is deliberately not a generic JSON patcher. It exists only to close the
independently identified P4-001 combined-authority blocker where Test Center
registry records still refer to the historical ``evals/fixtures`` location
although the deterministic fixture corpus has been rehomed into the
MISSION-004-owned research-worker test tree.

The operation requires the live ``test-center-registry`` AUTHORITY semaphore,
an exact canonical P4 Product head, and a dedicated helper branch still equal
to that base head. The only permitted semantic transformation is replacing two
exact string values. Every collection identity, array order, non-target value,
and all non-P4 records must remain unchanged.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
import tempfile
from typing import Any

from mission_delivery_lib import run_git
from mission_runtime_model import authority_config, validate_runtime_state

COMMAND_SCHEMA_VERSION = 1
OPERATION = "REWRITE_P4_REGISTRY_FIXTURE_PATH_V1"
AUTHORITY_ID = "test-center-registry"
REQUESTING_MISSION = "MISSION-004"
PRODUCT_PR = 62
OLD_DIRECTORY = "evals/fixtures/p4_001_search_provider/**"
NEW_DIRECTORY = "services/research_worker/test/fixtures/p4_001_search_provider/**"
OLD_FILE = "evals/fixtures/p4_001_search_provider/contract_cases.json"
NEW_FILE = "services/research_worker/test/fixtures/p4_001_search_provider/contract_cases.json"


def read_json(path: pathlib.Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def _git(project: pathlib.Path, *args: str) -> str:
    return run_git(project, *args)


def _require_command_shape(command: dict[str, Any], command_path: pathlib.Path) -> None:
    required = {
        "schemaVersion",
        "commandId",
        "operation",
        "expectedRuntimeGeneration",
        "workOrderId",
        "semaphoreId",
        "workerIdentity",
        "authorityId",
        "requestingMission",
        "productPr",
        "expectedProductHead",
    }
    optional = {"createdAt", "note"}
    missing = sorted(required - set(command))
    extra = sorted(set(command) - required - optional)
    if missing:
        raise ValueError(f"P4 registry fixture-path command missing fields: {missing}")
    if extra:
        raise ValueError(f"P4 registry fixture-path command has unsupported fields: {extra}")
    if command.get("schemaVersion") != COMMAND_SCHEMA_VERSION:
        raise ValueError("unsupported P4 registry fixture-path command schemaVersion")
    if command.get("operation") != OPERATION:
        raise ValueError(f"unsupported P4 registry fixture-path operation {command.get('operation')}")
    if pathlib.PurePosixPath(command_path).stem != command.get("commandId"):
        raise ValueError("commandId must match command filename")
    if command.get("authorityId") != AUTHORITY_ID:
        raise ValueError(f"authorityId must be exactly {AUTHORITY_ID}")
    if command.get("requestingMission") != REQUESTING_MISSION:
        raise ValueError(f"requestingMission must be exactly {REQUESTING_MISSION}")
    if command.get("productPr") != PRODUCT_PR:
        raise ValueError(f"productPr must be exactly {PRODUCT_PR}")
    if not isinstance(command.get("expectedRuntimeGeneration"), int):
        raise ValueError("expectedRuntimeGeneration must be an integer")
    head = command.get("expectedProductHead")
    if not isinstance(head, str) or re.fullmatch(r"[0-9a-f]{40}", head) is None:
        raise ValueError("expectedProductHead must be a full lowercase Git SHA")
    for key in ("workOrderId", "semaphoreId", "workerIdentity"):
        if not isinstance(command.get(key), str) or not command[key]:
            raise ValueError(f"{key} must be non-empty")


def _transform(value: Any) -> Any:
    if isinstance(value, str):
        if value == OLD_DIRECTORY:
            return NEW_DIRECTORY
        if value == OLD_FILE:
            return NEW_FILE
        return value
    if isinstance(value, list):
        return [_transform(item) for item in value]
    if isinstance(value, dict):
        return {key: _transform(item) for key, item in value.items()}
    return value


def _identity_sequences(document: dict[str, Any], collections: dict[str, str]) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for collection, identity_key in collections.items():
        items = document.get(collection)
        if not isinstance(items, list):
            raise ValueError(f"registry collection {collection} must be an array")
        identities: list[str] = []
        for index, item in enumerate(items):
            if not isinstance(item, dict):
                raise ValueError(f"registry collection {collection}[{index}] must be an object")
            identity = item.get(identity_key)
            if not isinstance(identity, str) or not identity:
                raise ValueError(
                    f"registry collection {collection}[{index}].{identity_key} must be non-empty"
                )
            identities.append(identity)
        if len(identities) != len(set(identities)):
            raise ValueError(f"registry collection {collection} contains duplicate identities")
        result[collection] = identities
    return result


def _rewrite_registry(base_text: str, collections: dict[str, str]) -> tuple[str, dict[str, int]]:
    old_directory_literal = json.dumps(OLD_DIRECTORY)
    new_directory_literal = json.dumps(NEW_DIRECTORY)
    old_file_literal = json.dumps(OLD_FILE)
    new_file_literal = json.dumps(NEW_FILE)
    directory_count = base_text.count(old_directory_literal)
    file_count = base_text.count(old_file_literal)
    if directory_count <= 0 or file_count <= 0:
        raise ValueError(
            "expected both historical P4 fixture directory and file references before migration; "
            f"directory={directory_count}, file={file_count}"
        )
    updated = base_text.replace(old_directory_literal, new_directory_literal)
    updated = updated.replace(old_file_literal, new_file_literal)
    if old_directory_literal in updated or old_file_literal in updated:
        raise ValueError("historical P4 fixture references remain after bounded migration")

    before = json.loads(base_text)
    after = json.loads(updated)
    if not isinstance(before, dict) or not isinstance(after, dict):
        raise ValueError("Test Center registry must remain a JSON object")
    expected = _transform(before)
    if after != expected:
        raise ValueError("registry migration produced a semantic change beyond exact fixture-path replacement")
    if _identity_sequences(before, collections) != _identity_sequences(after, collections):
        raise ValueError("registry collection identities/order changed during fixture-path migration")
    return updated, {
        "directoryReplacements": directory_count,
        "fileReplacements": file_count,
        "totalReplacements": directory_count + file_count,
    }


def apply_command(project: pathlib.Path, command_path: pathlib.Path) -> dict[str, Any]:
    command = read_json(command_path)
    _require_command_shape(command, command_path)

    state = validate_runtime_state(project)
    generation = state["meta"]["runtimeGeneration"]
    if generation != command["expectedRuntimeGeneration"]:
        raise ValueError(
            f"runtime generation moved: expected {command['expectedRuntimeGeneration']}, actual {generation}"
        )

    work = state["workOrders"].get(command["workOrderId"])
    if work is None:
        raise ValueError(f"unknown Work Order {command['workOrderId']}")
    if work.get("type") != "AUTHORITY_UPDATE" or work.get("status") != "IN_PROGRESS":
        raise ValueError(
            f"Work Order must be IN_PROGRESS AUTHORITY_UPDATE, got {work.get('type')} / {work.get('status')}"
        )
    if work.get("mission") != REQUESTING_MISSION or work.get("parentProductPr") != PRODUCT_PR:
        raise ValueError("Work Order is not the bounded MISSION-004 / P4-001 authority repair")
    if work.get("baseCommit") != command["expectedProductHead"]:
        raise ValueError("Work Order baseCommit differs from expectedProductHead")
    if work.get("activeSemaphoreId") != command["semaphoreId"]:
        raise ValueError("Work Order activeSemaphoreId differs from command semaphoreId")

    matches = [
        sem for sem in state["activeSemaphores"] if sem.get("semaphoreId") == command["semaphoreId"]
    ]
    if len(matches) != 1:
        raise ValueError("command requires exactly one matching active semaphore")
    semaphore = matches[0]
    if semaphore.get("kind") != "AUTHORITY":
        raise ValueError("P4 registry fixture-path command requires AUTHORITY semaphore")
    if semaphore.get("workOrderId") != work["workOrderId"]:
        raise ValueError("AUTHORITY semaphore Work Order mismatch")
    if semaphore.get("workerIdentity") != command["workerIdentity"]:
        raise ValueError("AUTHORITY semaphore workerIdentity mismatch")
    if semaphore.get("authorityId") != AUTHORITY_ID:
        raise ValueError("AUTHORITY semaphore is not bound to test-center-registry")

    authority = authority_config(project)["authorities"].get(AUTHORITY_ID)
    if not isinstance(authority, dict):
        raise ValueError(f"unknown authority {AUTHORITY_ID}")
    if authority.get("path") != "config/test_center_registry.v1.json":
        raise ValueError("test-center-registry authority path changed unexpectedly")
    eligible = authority.get("eligibleRequestingMissions", [])
    if REQUESTING_MISSION not in eligible and authority.get("ownerMission") != REQUESTING_MISSION:
        raise ValueError("MISSION-004 is no longer eligible for test-center-registry authority")
    authority_path = authority["path"]
    if work.get("allowedPaths") != [authority_path]:
        raise ValueError("Work Order must authorize exactly the Test Center registry path")
    if semaphore.get("allowedPaths") != [authority_path]:
        raise ValueError("AUTHORITY semaphore must authorize exactly the Test Center registry path")

    product = state["productPrs"].get(PRODUCT_PR)
    if product is None or product.get("task") != "P4-001":
        raise ValueError("canonical P4-001 Product PR mapping is missing")
    if product.get("observedHead") != command["expectedProductHead"]:
        raise ValueError("canonical P4 Product head differs from expectedProductHead")

    helper_branch = semaphore.get("branch")
    if not isinstance(helper_branch, str) or not helper_branch:
        raise ValueError("AUTHORITY semaphore missing dedicated helper branch")
    _git(project, "fetch", "--no-tags", "origin", f"+refs/heads/{helper_branch}:refs/remotes/origin/{helper_branch}")
    helper_ref = f"refs/remotes/origin/{helper_branch}"
    helper_head = _git(project, "rev-parse", helper_ref)
    if helper_head != work["baseCommit"]:
        raise ValueError(
            "dedicated P4 registry helper must still equal the exact reserved Product base before migration"
        )

    base_text = _git(project, "show", f"{work['baseCommit']}:{authority_path}")
    updated_text, replacement_counts = _rewrite_registry(
        base_text,
        authority.get("collections", {}),
    )

    with tempfile.TemporaryDirectory(prefix="mission-v15-p4-registry-path-") as temp:
        worktree = pathlib.Path(temp) / "worktree"
        _git(project, "worktree", "add", "--detach", str(worktree), helper_head)
        try:
            target = worktree / authority_path
            target.write_text(updated_text, encoding="utf-8", newline="\n")
            subprocess.run(["git", "diff", "--check"], cwd=worktree, check=True, text=True)
            changed_paths = _git(worktree, "diff", "--name-only").splitlines()
            if changed_paths != [authority_path]:
                raise ValueError(f"P4 registry fixture-path migration changed unexpected paths: {changed_paths}")
            subprocess.run(
                [sys.executable, "tool/test_center_contracts.py", "check", "--project", "."],
                cwd=worktree,
                check=True,
                text=True,
            )
            _git(worktree, "config", "user.name", "Mission V1.5 Authority Relay")
            _git(
                worktree,
                "config",
                "user.email",
                "mission-v15-authority-relay@users.noreply.github.com",
            )
            _git(worktree, "add", "--", authority_path)
            _git(worktree, "commit", "-m", "fix(p4): bind Test Center registry to owned fixture path")
            candidate = _git(worktree, "rev-parse", "HEAD")
            candidate_tree = _git(worktree, "rev-parse", "HEAD^{tree}")
            _git(worktree, "push", "origin", f"HEAD:refs/heads/{helper_branch}")
            remote = _git(project, "ls-remote", "origin", f"refs/heads/{helper_branch}").split()
            if not remote or remote[0] != candidate:
                raise ValueError("helper push returned but remote branch does not contain candidate")
            return {
                "schemaVersion": 1,
                "commandId": command["commandId"],
                "operation": OPERATION,
                "result": "APPLIED",
                "runtimeGeneration": generation,
                "workOrderId": work["workOrderId"],
                "semaphoreId": semaphore["semaphoreId"],
                "authorityId": AUTHORITY_ID,
                "authorityPath": authority_path,
                "helperBranch": helper_branch,
                "baseCommit": work["baseCommit"],
                "candidateHead": candidate,
                "candidateTree": candidate_tree,
                **replacement_counts,
            }
        finally:
            subprocess.run(
                ["git", "worktree", "remove", "--force", str(worktree)],
                cwd=project,
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--command", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = apply_command(
            pathlib.Path(args.project).resolve(),
            pathlib.Path(args.command).resolve(),
        )
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_P4_REGISTRY_FIXTURE_PATH_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
