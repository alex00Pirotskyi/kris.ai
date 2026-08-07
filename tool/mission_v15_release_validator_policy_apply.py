#!/usr/bin/env python3
"""Runner-backed bounded repair for the legacy release-validator Dart source policy.

This is not a generic patch executor. It may only transform the exact shared
authority path named by an ACTIVE AUTHORITY semaphore from the legacy duplicate
Dart allowlist model to the Mission Execution 1.5 governed-library model.
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
from mission_runtime_control import verify_candidate_ancestry
from mission_runtime_model import authority_config, validate_runtime_state

COMMAND_SCHEMA_VERSION = 1
SUPPORTED_OPERATION = "UPDATE_RELEASE_VALIDATOR_SOURCE_POLICY_V1"
EXPECTED_AUTHORITY_MODE = "BOUNDED_RELEASE_VALIDATOR_SOURCE_POLICY_V1"


def read_json(path: pathlib.Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def _git(project: pathlib.Path, *args: str) -> str:
    return run_git(project, *args)


def transform_release_validator(text: str) -> tuple[str, bool]:
    marker = "def _load_governed_product_library_files() -> set[str]:"
    filtered_marker = "if not path.startswith(\"test/\")"
    if marker in text or filtered_marker in text:
        if marker in text and filtered_marker in text:
            return text, False
        raise ValueError("release validator contains a partial governed-source policy migration")

    p2_anchor = "EXPECTED_DART_FILES.update(_load_governed_p2_dart_files())\n"
    if text.count(p2_anchor) != 1:
        raise ValueError("release validator P2 inventory anchor is missing or ambiguous")

    governed_loader = '''def _load_governed_product_library_files() -> set[str]:
    source_contract = ROOT / "test" / "product" / "source_contract_test.dart"
    try:
        content = source_contract.read_text(encoding="utf-8")
    except OSError as error:
        raise RuntimeError(
            f"cannot load governed product source inventory: {error}"
        ) from error
    marker = "const expected = <String>{"
    start = content.find(marker)
    if start < 0:
        raise RuntimeError("governed product source inventory marker is missing")
    open_brace = content.find("{", start)
    end = content.find("};", open_brace)
    if open_brace < 0 or end < 0:
        raise RuntimeError("governed product source inventory bounds are invalid")
    values = re.findall(r"'([^']+)'", content[open_brace + 1 : end])
    if not values:
        raise RuntimeError("governed product source inventory is empty")
    governed: set[str] = set()
    for raw in values:
        relative = raw.replace("\\\\", "/")
        if (
            not relative.startswith("lib/")
            or not relative.endswith(".dart")
            or relative.startswith("/")
            or relative.startswith("../")
            or "/../" in relative
        ):
            raise RuntimeError(
                f"governed product source inventory contains an unsafe/non-library path: {relative}"
            )
        if relative in governed:
            raise RuntimeError(
                f"duplicate governed product Dart path: {relative}"
            )
        governed.add(relative)
    return governed

'''
    text = text.replace(
        p2_anchor,
        governed_loader
        + p2_anchor
        + "EXPECTED_DART_FILES.update(_load_governed_product_library_files())\n",
        1,
    )

    legacy_unexpected = "    unexpected = sorted(actual - EXPECTED_DART_FILES)\n"
    if text.count(legacy_unexpected) != 1:
        raise ValueError("release validator unexpected-Dart calculation is missing or ambiguous")
    governed_unexpected = '''    unexpected = sorted(
        path
        for path in actual - EXPECTED_DART_FILES
        if not path.startswith("test/")
    )
'''
    text = text.replace(legacy_unexpected, governed_unexpected, 1)
    return text, True


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
    }
    optional = {"createdAt", "note"}
    missing = sorted(required - set(command))
    extra = sorted(set(command) - required - optional)
    if missing:
        raise ValueError(f"release-validator command missing fields: {missing}")
    if extra:
        raise ValueError(f"release-validator command has unsupported fields: {extra}")


def apply_command(project: pathlib.Path, command_path: pathlib.Path) -> dict[str, Any]:
    command = read_json(command_path)
    _require_exact_keys(command)
    if command["schemaVersion"] != COMMAND_SCHEMA_VERSION:
        raise ValueError("unsupported release-validator command schemaVersion")
    if command["operation"] != SUPPORTED_OPERATION:
        raise ValueError(f"unsupported release-validator operation {command['operation']}")
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

    matches = [
        sem
        for sem in state["activeSemaphores"]
        if sem["semaphoreId"] == command["semaphoreId"]
    ]
    if len(matches) != 1:
        raise ValueError("command requires exactly one matching active semaphore")
    semaphore = matches[0]
    if semaphore["kind"] != "AUTHORITY":
        raise ValueError("release-validator command requires AUTHORITY semaphore")
    if semaphore["workOrderId"] != work["workOrderId"]:
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
    if authority.get("mode") != EXPECTED_AUTHORITY_MODE:
        raise ValueError("release-validator authority mode mismatch")
    eligible = authority.get("eligibleRequestingMissions", [])
    if (
        command["requestingMission"] != authority.get("ownerMission")
        and command["requestingMission"] not in eligible
    ):
        raise ValueError("requesting mission is not eligible for release-validator repair")
    authority_path = authority.get("path")
    if authority_path != "tool/validate_release.py":
        raise ValueError("release-validator authority must bind tool/validate_release.py")
    if authority_path not in semaphore.get("allowedPaths", []):
        raise ValueError("active semaphore does not authorize exact release-validator path")
    if authority_path not in work.get("allowedPaths", []):
        raise ValueError("Work Order does not authorize exact release-validator path")

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

    base_text = _git(project, "show", f"{work['baseCommit']}:{authority_path}")
    helper_text = _git(project, "show", f"{helper_head}:{authority_path}")
    if helper_text != base_text:
        raise ValueError("release-validator helper already changes authority path; refusing to stack")

    with tempfile.TemporaryDirectory(prefix="mission-v15-release-validator-") as temp:
        worktree = pathlib.Path(temp) / "worktree"
        _git(project, "worktree", "add", "--detach", str(worktree), helper_head)
        try:
            target = worktree / authority_path
            original = target.read_text(encoding="utf-8")
            updated, changed = transform_release_validator(original)
            if not changed:
                return {
                    "schemaVersion": 1,
                    "commandId": command["commandId"],
                    "operation": command["operation"],
                    "result": "ALREADY_PRESENT",
                    "helperBranch": helper_branch,
                    "helperHead": helper_head,
                }
            target.write_text(updated, encoding="utf-8", newline="\n")
            subprocess.run(["git", "diff", "--check"], cwd=worktree, check=True, text=True)
            changed_paths = _git(worktree, "diff", "--name-only").splitlines()
            if changed_paths != [authority_path]:
                raise ValueError(f"release-validator relay changed unexpected paths: {changed_paths}")

            result = subprocess.run(
                [sys.executable, "tool/validate_release.py", "--skip-tests"],
                cwd=worktree,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=900,
            )
            if result.returncode != 0:
                raise ValueError(
                    "updated release validator did not pass --skip-tests: "
                    + result.stdout[-12000:]
                )

            _git(worktree, "config", "user.name", "Mission V1.5 Release Validator Relay")
            _git(worktree, "config", "user.email", "mission-v15-release-validator@users.noreply.github.com")
            _git(worktree, "add", "--", authority_path)
            _git(worktree, "commit", "-m", "mission-v15: consume governed Dart source inventory in release validation")
            candidate = _git(worktree, "rev-parse", "HEAD")
            _git(worktree, "push", "origin", f"HEAD:refs/heads/{helper_branch}")
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
        print(f"MISSION_V15_RELEASE_VALIDATOR_POLICY_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
