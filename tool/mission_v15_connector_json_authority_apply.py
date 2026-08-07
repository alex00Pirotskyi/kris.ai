#!/usr/bin/env python3
"""Runner-backed connector relay for explicit append-safe JSON authority records.

This is intentionally not a generic JSON patcher. It consumes one immutable
runtime command, requires an ACTIVE AUTHORITY semaphore, and may append only
explicitly named record identities copied from one trusted Git commit into one
configured ``APPEND_SAFE_JSON`` authority path.

Existing authority bytes/objects are preserved. A requested identity that
already exists must be semantically identical to the source object or the
operation fails closed. Unrequested source records are never copied.
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
from mission_runtime_control import verify_candidate_ancestry
from mission_runtime_model import authority_config, validate_runtime_state
from mission_v15_authority_append import verify_authority

COMMAND_SCHEMA_VERSION = 1
SUPPORTED_OPERATION = "APPEND_SAFE_JSON_IDENTITIES_V1"


def read_json(path: pathlib.Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def _git(project: pathlib.Path, *args: str) -> str:
    return run_git(project, *args)


def _require_exact_keys(command: dict[str, Any]) -> None:
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
        "sourceCommit",
        "appendIdentities",
    }
    optional = {"createdAt", "note"}
    missing = sorted(required - set(command))
    extra = sorted(set(command) - required - optional)
    if missing:
        raise ValueError(f"JSON authority command missing fields: {missing}")
    if extra:
        raise ValueError(f"JSON authority command has unsupported fields: {extra}")


def _identity_index(items: Any, identity_key: str, label: str) -> dict[str, dict[str, Any]]:
    if not isinstance(items, list):
        raise ValueError(f"{label} must be an array")
    result: dict[str, dict[str, Any]] = {}
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            raise ValueError(f"{label}[{index}] must be an object")
        identity = item.get(identity_key)
        if not isinstance(identity, str) or not identity:
            raise ValueError(f"{label}[{index}].{identity_key} must be non-empty")
        if identity in result:
            raise ValueError(f"{label} contains duplicate {identity_key} {identity}")
        result[identity] = item
    return result


def _array_bounds(text: str, key: str) -> tuple[int, int]:
    marker = re.search(rf'(?m)^\s*"{re.escape(key)}"\s*:\s*\[', text)
    if marker is None:
        raise ValueError(f"authority collection not found in source text: {key}")
    open_index = text.find("[", marker.start(), marker.end())
    if open_index < 0:
        raise ValueError(f"authority collection opening bracket missing: {key}")
    depth = 1
    cursor = open_index + 1
    in_string = False
    escaped = False
    while cursor < len(text):
        char = text[cursor]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        else:
            if char == '"':
                in_string = True
            elif char == "[":
                depth += 1
            elif char == "]":
                depth -= 1
                if depth == 0:
                    return open_index, cursor
        cursor += 1
    raise ValueError(f"authority collection closing bracket missing: {key}")


def _indent_json_object(item: dict[str, Any], indent: int = 4) -> str:
    rendered = json.dumps(item, indent=2, ensure_ascii=False)
    prefix = " " * indent
    return "\n".join(prefix + line for line in rendered.splitlines())


def append_explicit_identities(
    base_text: str,
    source_text: str,
    collections: dict[str, str],
    requested: dict[str, list[str]],
) -> tuple[str, dict[str, list[str]]]:
    base = json.loads(base_text)
    source = json.loads(source_text)
    if not isinstance(base, dict) or not isinstance(source, dict):
        raise ValueError("append-safe JSON authority must be an object")
    if not isinstance(requested, dict) or not requested:
        raise ValueError("appendIdentities must be a non-empty object")
    unknown = sorted(set(requested) - set(collections))
    if unknown:
        raise ValueError(f"appendIdentities contains unsupported collections: {unknown}")

    additions: dict[str, list[dict[str, Any]]] = {}
    appended_ids: dict[str, list[str]] = {}
    for collection, identities in requested.items():
        if not isinstance(identities, list) or not identities:
            raise ValueError(f"appendIdentities.{collection} must be a non-empty array")
        if any(not isinstance(value, str) or not value for value in identities):
            raise ValueError(f"appendIdentities.{collection} must contain non-empty strings")
        if len(identities) != len(set(identities)):
            raise ValueError(f"appendIdentities.{collection} contains duplicate identities")
        identity_key = collections[collection]
        base_index = _identity_index(base.get(collection), identity_key, collection)
        source_index = _identity_index(source.get(collection), identity_key, f"source.{collection}")
        pending: list[dict[str, Any]] = []
        appended: list[str] = []
        for identity in identities:
            source_item = source_index.get(identity)
            if source_item is None:
                raise ValueError(
                    f"requested authority identity missing from source commit: {collection}/{identity}"
                )
            existing = base_index.get(identity)
            if existing is not None:
                if existing != source_item:
                    raise ValueError(
                        f"existing authority identity conflicts with source: {collection}/{identity}"
                    )
                continue
            pending.append(source_item)
            appended.append(identity)
        if pending:
            additions[collection] = pending
            appended_ids[collection] = appended

    if not additions:
        return base_text, {}

    updated = base_text
    for collection, items in additions.items():
        open_index, close_index = _array_bounds(updated, collection)
        cursor = close_index - 1
        while cursor > open_index and updated[cursor].isspace():
            cursor -= 1
        rendered = ",\n".join(_indent_json_object(item) for item in items)
        if cursor == open_index:
            insertion = "\n" + rendered + updated[cursor + 1 : close_index]
            updated = updated[: open_index + 1] + insertion + updated[close_index:]
        else:
            trailing = updated[cursor + 1 : close_index]
            updated = (
                updated[: cursor + 1]
                + ",\n"
                + rendered
                + trailing
                + updated[close_index:]
            )
    json.loads(updated)
    return updated, appended_ids


def apply_command(project: pathlib.Path, command_path: pathlib.Path) -> dict[str, Any]:
    command = read_json(command_path)
    _require_exact_keys(command)
    if command["schemaVersion"] != COMMAND_SCHEMA_VERSION:
        raise ValueError("unsupported JSON authority command schemaVersion")
    if command["operation"] != SUPPORTED_OPERATION:
        raise ValueError(f"unsupported JSON authority operation {command['operation']}")
    if not isinstance(command["expectedRuntimeGeneration"], int):
        raise ValueError("expectedRuntimeGeneration must be an integer")
    if pathlib.PurePosixPath(command_path).stem != command["commandId"]:
        raise ValueError("commandId must match command filename")
    source_commit = command["sourceCommit"]
    if not isinstance(source_commit, str) or re.fullmatch(r"[0-9a-f]{40}", source_commit) is None:
        raise ValueError("sourceCommit must be an exact 40-hex commit")

    state = validate_runtime_state(project)
    generation = state["meta"]["runtimeGeneration"]
    if generation != command["expectedRuntimeGeneration"]:
        raise ValueError(
            f"runtime generation moved: expected {command['expectedRuntimeGeneration']}, actual {generation}"
        )
    work = state["workOrders"].get(command["workOrderId"])
    if work is None:
        raise ValueError(f"unknown Work Order {command['workOrderId']}")
    if work["type"] != "AUTHORITY_UPDATE" or work["status"] != "IN_PROGRESS":
        raise ValueError(
            f"Work Order must be IN_PROGRESS AUTHORITY_UPDATE, got {work['type']} / {work['status']}"
        )
    if work["mission"] != command["requestingMission"]:
        raise ValueError("command requestingMission differs from Work Order mission")
    if work.get("activeSemaphoreId") != command["semaphoreId"]:
        raise ValueError("Work Order activeSemaphoreId differs from command semaphoreId")

    matches = [
        sem for sem in state["activeSemaphores"] if sem["semaphoreId"] == command["semaphoreId"]
    ]
    if len(matches) != 1:
        raise ValueError("command requires exactly one matching active semaphore")
    semaphore = matches[0]
    if semaphore["kind"] != "AUTHORITY":
        raise ValueError("JSON authority command requires AUTHORITY semaphore")
    if semaphore["workOrderId"] != command["workOrderId"]:
        raise ValueError("semaphore Work Order mismatch")
    if semaphore["workerIdentity"] != command["workerIdentity"]:
        raise ValueError("semaphore workerIdentity mismatch")
    if semaphore.get("authorityId") != command["authorityId"]:
        raise ValueError("semaphore authorityId mismatch")
    if semaphore["mission"] != command["requestingMission"]:
        raise ValueError("semaphore mission mismatch")

    authority = authority_config(project)["authorities"].get(command["authorityId"])
    if not isinstance(authority, dict):
        raise ValueError(f"unknown authority {command['authorityId']}")
    if authority.get("mode") != "APPEND_SAFE_JSON":
        raise ValueError("JSON authority relay requires APPEND_SAFE_JSON mode")
    eligible = authority.get("eligibleRequestingMissions", [])
    if (
        command["requestingMission"] != authority.get("ownerMission")
        and command["requestingMission"] not in eligible
    ):
        raise ValueError("requesting mission is not eligible for JSON authority append")
    authority_path = authority["path"]
    if authority_path not in semaphore.get("allowedPaths", []):
        raise ValueError("active semaphore does not authorize exact authority path")
    if authority_path not in work.get("allowedPaths", []):
        raise ValueError("Work Order does not authorize exact authority path")

    helper_branch = semaphore.get("branch")
    if not isinstance(helper_branch, str) or not helper_branch:
        raise ValueError("AUTHORITY semaphore missing dedicated helper branch")
    _git(project, "cat-file", "-e", f"{source_commit}^{{commit}}")
    _git(project, "fetch", "--no-tags", "origin", f"+refs/heads/{helper_branch}:refs/remotes/origin/{helper_branch}")
    helper_ref = f"refs/remotes/origin/{helper_branch}"
    helper_head = _git(project, "rev-parse", helper_ref)
    verify_candidate_ancestry(project, work["baseCommit"], helper_head)
    actual_base_tree = _git(project, "rev-parse", f"{work['baseCommit']}^{{tree}}")
    if actual_base_tree != work["baseTree"]:
        raise ValueError("Work Order baseCommit/baseTree no longer matches Git")

    base_authority = _git(project, "show", f"{work['baseCommit']}:{authority_path}")
    helper_authority = _git(project, "show", f"{helper_head}:{authority_path}")
    if helper_authority != base_authority:
        raise ValueError(
            "dedicated authority helper already changes the governed authority path; refusing to stack"
        )
    source_authority = _git(project, "show", f"{source_commit}:{authority_path}")
    updated, appended = append_explicit_identities(
        base_authority,
        source_authority,
        authority.get("collections", {}),
        command["appendIdentities"],
    )
    if not appended:
        return {
            "schemaVersion": 1,
            "commandId": command["commandId"],
            "operation": command["operation"],
            "result": "ALREADY_PRESENT",
            "helperBranch": helper_branch,
            "helperHead": helper_head,
            "sourceCommit": source_commit,
        }

    with tempfile.TemporaryDirectory(prefix="mission-v15-json-authority-") as temp:
        worktree = pathlib.Path(temp) / "worktree"
        _git(project, "worktree", "add", "--detach", str(worktree), helper_head)
        try:
            target = worktree / authority_path
            target.write_text(updated, encoding="utf-8", newline="\n")
            subprocess.run(["git", "diff", "--check"], cwd=worktree, check=True, text=True)
            changed_paths = _git(worktree, "diff", "--name-only").splitlines()
            if changed_paths != [authority_path]:
                raise ValueError(f"JSON authority relay changed unexpected paths: {changed_paths}")
            _git(worktree, "config", "user.name", "Mission V1.5 Authority Relay")
            _git(worktree, "config", "user.email", "mission-v15-authority-relay@users.noreply.github.com")
            _git(worktree, "add", "--", authority_path)
            _git(
                worktree,
                "commit",
                "-m",
                f"mission-v15: append explicit records to {command['authorityId']}",
            )
            candidate = _git(worktree, "rev-parse", "HEAD")
            verify_authority(
                project,
                config_path=project / "config/mission_v15_authorities.v1.json",
                authority_id=command["authorityId"],
                requesting_mission=command["requestingMission"],
                base_commit=work["baseCommit"],
                head_commit=candidate,
            )
            _git(worktree, "push", "origin", f"HEAD:refs/heads/{helper_branch}")
            remote = _git(project, "ls-remote", "origin", f"refs/heads/{helper_branch}").split()
            if not remote or remote[0] != candidate:
                raise ValueError("helper push returned but remote branch does not contain candidate")
            return {
                "schemaVersion": 1,
                "commandId": command["commandId"],
                "operation": command["operation"],
                "result": "APPLIED",
                "runtimeGeneration": generation,
                "workOrderId": work["workOrderId"],
                "semaphoreId": semaphore["semaphoreId"],
                "helperBranch": helper_branch,
                "previousHelperHead": helper_head,
                "helperHead": candidate,
                "authorityId": command["authorityId"],
                "authorityPath": authority_path,
                "sourceCommit": source_commit,
                "appended": appended,
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
        result = apply_command(pathlib.Path(args.project).resolve(), pathlib.Path(args.command).resolve())
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_CONNECTOR_JSON_AUTHORITY_APPLY_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
