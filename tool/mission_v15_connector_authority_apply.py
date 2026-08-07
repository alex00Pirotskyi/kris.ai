#!/usr/bin/env python3
"""Runner-backed connector relay for narrow append-safe authority mutations.

This is intentionally not a generic patch or command executor. It consumes one
immutable JSON request committed on ``agent/mission-runtime`` and may mutate
only the authority path named by an already ACTIVE AUTHORITY semaphore.

Currently supported operation:

``APPEND_SAFE_DART_SET`` — append one mission-owned ``lib/**`` path to the
configured governed Dart set while preserving every existing byte outside the
set and every existing set entry in order.
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

from mission_delivery_lib import load_model, matches_any, run_git
from mission_runtime_control import verify_candidate_ancestry
from mission_runtime_model import authority_config, validate_runtime_state
from mission_v15_authority_append import verify_authority

COMMAND_SCHEMA_VERSION = 1
SUPPORTED_OPERATION = "APPEND_SAFE_DART_SET"


def read_json(path: pathlib.Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def _git(project: pathlib.Path, *args: str) -> str:
    return run_git(project, *args)


def _append_dart_set_entry(
    text: str,
    *,
    marker: str,
    value: str,
) -> tuple[str, bool]:
    start = text.find(marker)
    if start < 0:
        raise ValueError(f"source inventory marker missing: {marker}")
    open_brace = text.find("{", start)
    if open_brace < 0:
        raise ValueError("source inventory opening brace missing")
    end = text.find("};", open_brace)
    if end < 0:
        raise ValueError("source inventory closing marker missing")
    body = text[open_brace + 1 : end]
    values = re.findall(r"'([^']+)'", body)
    if len(values) != len(set(values)):
        raise ValueError("source inventory contains duplicate paths")
    if value in values:
        return text, False

    closing_line_start = text.rfind("\n", open_brace, end) + 1
    if closing_line_start <= open_brace:
        raise ValueError("source inventory closing marker must begin on its own line")
    entry_lines = [
        line
        for line in body.splitlines()
        if re.match(r"^\s*'[^']+',\s*$", line)
    ]
    if not entry_lines:
        raise ValueError("source inventory contains no canonical entries")
    indent_match = re.match(r"^(\s*)'", entry_lines[-1])
    if indent_match is None:
        raise ValueError("cannot determine source inventory indentation")
    indent = indent_match.group(1)
    insertion = f"{indent}'{value}',\n"
    return text[:closing_line_start] + insertion + text[closing_line_start:], True


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
        "appendPath",
    }
    optional = {"createdAt", "note"}
    missing = sorted(required - set(command))
    extra = sorted(set(command) - required - optional)
    if missing:
        raise ValueError(f"connector authority command missing fields: {missing}")
    if extra:
        raise ValueError(f"connector authority command has unsupported fields: {extra}")


def apply_command(project: pathlib.Path, command_path: pathlib.Path) -> dict[str, Any]:
    command = read_json(command_path)
    _require_exact_keys(command)
    if command["schemaVersion"] != COMMAND_SCHEMA_VERSION:
        raise ValueError("unsupported connector authority command schemaVersion")
    if command["operation"] != SUPPORTED_OPERATION:
        raise ValueError(f"unsupported connector authority operation {command['operation']}")
    if not isinstance(command["expectedRuntimeGeneration"], int):
        raise ValueError("expectedRuntimeGeneration must be an integer")
    if pathlib.PurePosixPath(command_path).stem != command["commandId"]:
        raise ValueError("commandId must match command filename")

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

    semaphores = [
        sem
        for sem in state["activeSemaphores"]
        if sem["semaphoreId"] == command["semaphoreId"]
    ]
    if len(semaphores) != 1:
        raise ValueError("command requires exactly one matching active semaphore")
    semaphore = semaphores[0]
    if semaphore["kind"] != "AUTHORITY":
        raise ValueError("connector authority command requires AUTHORITY semaphore")
    if semaphore["workOrderId"] != command["workOrderId"]:
        raise ValueError("semaphore Work Order mismatch")
    if semaphore["workerIdentity"] != command["workerIdentity"]:
        raise ValueError("semaphore workerIdentity mismatch")
    if semaphore.get("authorityId") != command["authorityId"]:
        raise ValueError("semaphore authorityId mismatch")
    if semaphore["mission"] != command["requestingMission"]:
        raise ValueError("semaphore mission mismatch")

    authorities = authority_config(project)["authorities"]
    authority = authorities.get(command["authorityId"])
    if not isinstance(authority, dict):
        raise ValueError(f"unknown authority {command['authorityId']}")
    if authority.get("mode") != "APPEND_SAFE_DART_SET":
        raise ValueError("connector relay currently supports only APPEND_SAFE_DART_SET")
    eligible = authority.get("eligibleRequestingMissions", [])
    if (
        command["requestingMission"] != authority.get("ownerMission")
        and command["requestingMission"] not in eligible
    ):
        raise ValueError("requesting mission is not eligible for authority append")
    authority_path = authority["path"]
    if authority_path not in semaphore.get("allowedPaths", []):
        raise ValueError("active semaphore does not authorize exact authority path")
    if authority_path not in work.get("allowedPaths", []):
        raise ValueError("Work Order does not authorize exact authority path")

    append_path = command["appendPath"]
    if not isinstance(append_path, str) or not append_path.startswith(authority["pathPrefix"]):
        raise ValueError("appendPath violates authority pathPrefix")
    model = load_model(project)
    owned = model["config"]["missionPathPolicies"][command["requestingMission"]]["owned"]
    if not matches_any(append_path, owned):
        raise ValueError("appendPath is not owned by requesting mission")

    helper_branch = semaphore.get("branch")
    if not isinstance(helper_branch, str) or not helper_branch:
        raise ValueError("AUTHORITY semaphore missing helper branch")
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

    with tempfile.TemporaryDirectory(prefix="mission-v15-authority-") as temp:
        worktree = pathlib.Path(temp) / "worktree"
        _git(project, "worktree", "add", "--detach", str(worktree), helper_head)
        try:
            source_path = worktree / append_path
            if not source_path.is_file():
                raise ValueError(f"appendPath does not exist on helper candidate: {append_path}")
            target = worktree / authority_path
            original = target.read_text(encoding="utf-8")
            updated, changed = _append_dart_set_entry(
                original,
                marker=authority["setStartMarker"],
                value=append_path,
            )
            if not changed:
                return {
                    "schemaVersion": 1,
                    "commandId": command["commandId"],
                    "operation": command["operation"],
                    "result": "ALREADY_PRESENT",
                    "helperBranch": helper_branch,
                    "helperHead": helper_head,
                    "appendPath": append_path,
                }
            target.write_text(updated, encoding="utf-8", newline="\n")
            subprocess.run(
                ["git", "diff", "--check"],
                cwd=worktree,
                check=True,
                text=True,
            )
            changed_paths = _git(worktree, "diff", "--name-only").splitlines()
            if changed_paths != [authority_path]:
                raise ValueError(f"connector authority relay changed unexpected paths: {changed_paths}")

            _git(worktree, "config", "user.name", "Mission V1.5 Authority Relay")
            _git(worktree, "config", "user.email", "mission-v15-authority-relay@users.noreply.github.com")
            _git(worktree, "add", "--", authority_path)
            _git(
                worktree,
                "commit",
                "-m",
                f"mission-v15: append {append_path} to {command['authorityId']}",
            )
            candidate = _git(worktree, "rev-parse", "HEAD")
            # Product/helper history intentionally does not carry Mission 1.5
            # control-plane configuration. Validate the candidate Git objects
            # through the shared repository object database while loading the
            # authority/model policy from the runtime checkout.
            verify_authority(
                project,
                config_path=project / "config/mission_v15_authorities.v1.json",
                authority_id=command["authorityId"],
                requesting_mission=command["requestingMission"],
                base_commit=work["baseCommit"],
                head_commit=candidate,
            )

            _git(
                worktree,
                "push",
                "origin",
                f"HEAD:refs/heads/{helper_branch}",
            )
            remote_after = _git(project, "ls-remote", "origin", f"refs/heads/{helper_branch}").split()
            if not remote_after or remote_after[0] != candidate:
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
                "appendPath": append_path,
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
        print(f"MISSION_V15_CONNECTOR_AUTHORITY_APPLY_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
