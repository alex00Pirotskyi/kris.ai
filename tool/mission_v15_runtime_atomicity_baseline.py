#!/usr/bin/env python3
"""Validate the exact historical-debt boundary for runtime atomicity.

The strict runtime atomicity auditor intentionally begins at one immutable,
known-good runtime generation. This companion gate prevents that cutover from
silently hiding earlier defects:

* it binds the strict cutover to one exact first-parent commit and generation;
* it re-audits the configured historical range with the same transition rules;
* every historical violation must match an explicit commit-bound debt record;
* unrecorded, moved, removed, or relabelled historical violations fail closed;
* debt records cannot excuse the baseline generation or any descendant.

The ordinary ``mission_v15_runtime_atomicity.py`` gate remains authoritative
for the baseline transition and all descendants.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

from mission_v15_runtime_atomicity import (
    DEFAULT_COMMAND_PREFIX,
    changed_entries,
    run_git,
    show_json,
    validate_command_document,
)


def require_full_sha(value: Any, label: str) -> str:
    if (
        not isinstance(value, str)
        or len(value) != 40
        or value.lower() != value
        or any(character not in "0123456789abcdef" for character in value)
    ):
        raise ValueError(f"{label}_INVALID")
    return value


def collect_transition(
    *,
    runtime_project: pathlib.Path,
    commit: str,
    runtime_prefix: str,
    event_prefix: str,
    command_prefix: str,
    audit_from_generation: int,
) -> dict[str, Any] | None:
    parent_record = run_git(
        runtime_project, "rev-list", "--parents", "-n", "1", commit
    ).split()
    if len(parent_record) < 2:
        return None
    parent = parent_record[1]
    meta = show_json(runtime_project, commit, "runtime/meta.json")
    if meta is None:
        return None
    parent_meta = show_json(runtime_project, parent, "runtime/meta.json")
    generation = int(meta.get("runtimeGeneration", -1))

    entries = changed_entries(runtime_project, parent, commit)
    runtime_entries = [
        (status, path)
        for status, path in entries
        if path.startswith(runtime_prefix)
    ]
    if not runtime_entries or generation < audit_from_generation:
        return None

    parent_generation = (
        int(parent_meta.get("runtimeGeneration", -1))
        if parent_meta is not None
        else None
    )
    runtime_paths = {path for _, path in runtime_entries}
    violations: list[str] = []

    if parent_generation is None:
        violations.append("MISSING_PARENT_RUNTIME_META")
    elif generation != parent_generation + 1:
        violations.append(
            f"GENERATION_NOT_SINGLE_STEP:{parent_generation}->{generation}"
        )

    if "runtime/meta.json" not in runtime_paths:
        violations.append("RUNTIME_CHANGE_WITHOUT_META")

    non_runtime_entries = [
        (status, path)
        for status, path in entries
        if not path.startswith(runtime_prefix)
    ]
    command_entries = [
        (status, path)
        for status, path in non_runtime_entries
        if path.startswith(command_prefix) and path.endswith(".json")
    ]
    unrelated_non_runtime = sorted(
        path
        for _, path in non_runtime_entries
        if not (path.startswith(command_prefix) and path.endswith(".json"))
    )
    if unrelated_non_runtime:
        violations.append(
            "GENERATION_COMMIT_HAS_NON_RUNTIME_PATHS:"
            + ",".join(unrelated_non_runtime)
        )
    if len(command_entries) > 1:
        violations.append(
            f"GENERATION_COMMAND_ENVELOPE_ATOMICITY:count={len(command_entries)}"
        )
    elif len(command_entries) == 1:
        status, command_path = command_entries[0]
        command = show_json(runtime_project, commit, command_path)
        violations.extend(
            validate_command_document(
                status=status,
                path=command_path,
                command=command,
                generation=generation,
            )
        )

    event_entries = [
        (status, path)
        for status, path in runtime_entries
        if path.startswith(event_prefix)
    ]
    added_events = [
        (status, path) for status, path in event_entries if status == "A"
    ]
    if len(event_entries) != 1 or len(added_events) != 1:
        violations.append(
            "GENERATION_EVENT_ATOMICITY:"
            f"eventChanges={len(event_entries)},added={len(added_events)}"
        )
    else:
        event_path = added_events[0][1]
        event = show_json(runtime_project, commit, event_path)
        if event is None:
            violations.append("ADDED_EVENT_NOT_READABLE")
        else:
            if int(event.get("runtimeGeneration", -1)) != generation:
                violations.append(
                    "EVENT_GENERATION_MISMATCH:"
                    f"{event.get('runtimeGeneration')}!={generation}"
                )
            if event.get("schemaVersion") != 1:
                violations.append("EVENT_SCHEMA_VERSION_INVALID")
            event_id = event.get("eventId")
            if not isinstance(event_id, str) or not event_id:
                violations.append("EVENT_ID_MISSING")
            elif pathlib.PurePosixPath(event_path).stem != event_id:
                violations.append(
                    "EVENT_FILENAME_ID_MISMATCH:"
                    f"{pathlib.PurePosixPath(event_path).stem}!={event_id}"
                )

    return {
        "commit": commit,
        "parent": parent,
        "runtimeGeneration": generation,
        "parentRuntimeGeneration": parent_generation,
        "changedRuntimePaths": sorted(runtime_paths),
        "commandEnvelopePaths": sorted(path for _, path in command_entries),
        "violations": violations,
    }


def normalize_debt_records(
    configured: Any,
    *,
    enforce_from_generation: int,
) -> dict[str, dict[str, Any]]:
    if not isinstance(configured, list):
        raise ValueError("HISTORICAL_VIOLATION_DEBT_NOT_ARRAY")
    normalized: dict[str, dict[str, Any]] = {}
    required_keys = {"commit", "runtimeGeneration", "violations"}
    for index, raw in enumerate(configured):
        if not isinstance(raw, dict):
            raise ValueError(f"HISTORICAL_VIOLATION_DEBT_NOT_OBJECT:{index}")
        if set(raw) != required_keys:
            raise ValueError(
                "HISTORICAL_VIOLATION_DEBT_KEYS_INVALID:"
                f"{index}:{','.join(sorted(set(raw) ^ required_keys))}"
            )
        commit = require_full_sha(
            raw.get("commit"), f"HISTORICAL_VIOLATION_DEBT_COMMIT_{index}"
        )
        if commit in normalized:
            raise ValueError(
                f"HISTORICAL_VIOLATION_DEBT_DUPLICATE_COMMIT:{commit}"
            )
        generation = raw.get("runtimeGeneration")
        if (
            isinstance(generation, bool)
            or not isinstance(generation, int)
            or generation < 0
            or generation >= enforce_from_generation
        ):
            raise ValueError(
                "HISTORICAL_VIOLATION_DEBT_GENERATION_INVALID:"
                f"{commit}:{generation}"
            )
        violations = raw.get("violations")
        if (
            not isinstance(violations, list)
            or not violations
            or any(
                not isinstance(item, str) or not item
                for item in violations
            )
        ):
            raise ValueError(
                f"HISTORICAL_VIOLATION_DEBT_VIOLATIONS_INVALID:{commit}"
            )
        if violations != sorted(set(violations)):
            raise ValueError(
                f"HISTORICAL_VIOLATION_DEBT_VIOLATIONS_NOT_CANONICAL:{commit}"
            )
        normalized[commit] = {
            "commit": commit,
            "runtimeGeneration": generation,
            "violations": list(violations),
        }
    return normalized


def compare_historical_debt(
    *,
    configured: dict[str, dict[str, Any]],
    actual: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    configured_commits = set(configured)
    actual_commits = set(actual)
    if configured_commits != actual_commits:
        missing = sorted(actual_commits - configured_commits)
        stale = sorted(configured_commits - actual_commits)
        raise ValueError(
            "HISTORICAL_VIOLATION_DEBT_COMMIT_SET_MISMATCH:"
            f"unrecorded={','.join(missing) or 'NONE'}:"
            f"stale={','.join(stale) or 'NONE'}"
        )

    normalized: list[dict[str, Any]] = []
    for commit in sorted(configured):
        expected = configured[commit]
        observed = actual[commit]
        if expected["runtimeGeneration"] != observed["runtimeGeneration"]:
            raise ValueError(
                "HISTORICAL_VIOLATION_DEBT_GENERATION_MISMATCH:"
                f"{commit}:{expected['runtimeGeneration']}!="
                f"{observed['runtimeGeneration']}"
            )
        observed_violations = sorted(set(observed["violations"]))
        if expected["violations"] != observed_violations:
            raise ValueError(
                "HISTORICAL_VIOLATION_DEBT_VIOLATIONS_MISMATCH:"
                f"{commit}:expected={json.dumps(expected['violations'])}:"
                f"actual={json.dumps(observed_violations)}"
            )
        normalized.append(
            {
                "commit": commit,
                "runtimeGeneration": expected["runtimeGeneration"],
                "violations": expected["violations"],
            }
        )
    return normalized


def audit(
    runtime_project: pathlib.Path,
    config_path: pathlib.Path,
) -> dict[str, Any]:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    atomicity = config.get("runtimeAtomicity")
    if not isinstance(atomicity, dict):
        raise ValueError("RUNTIME_ATOMICITY_CONFIG_MISSING")

    legacy_audit_from = int(atomicity.get("legacyAuditFromGeneration", -1))
    enforce_from = int(atomicity.get("enforceFromGeneration", -1))
    if legacy_audit_from < 0 or enforce_from < 0:
        raise ValueError("RUNTIME_ATOMICITY_GENERATION_BOUNDARY_MISSING")
    if legacy_audit_from >= enforce_from:
        raise ValueError(
            "RUNTIME_ATOMICITY_GENERATION_BOUNDARY_INVALID:"
            f"{legacy_audit_from}>={enforce_from}"
        )

    baseline_commit = require_full_sha(
        atomicity.get("enforcementBaselineCommit"),
        "RUNTIME_ATOMICITY_BASELINE_COMMIT",
    )
    runtime_prefix = str(
        atomicity.get("runtimePathPrefix", "runtime/")
    )
    event_prefix = str(
        atomicity.get("eventPathPrefix", "runtime/events/")
    )
    command_prefix = str(
        atomicity.get("commandPathPrefix", DEFAULT_COMMAND_PREFIX)
    )
    configured_debt = normalize_debt_records(
        atomicity.get("historicalViolationDebt"),
        enforce_from_generation=enforce_from,
    )

    commits = run_git(
        runtime_project, "rev-list", "--first-parent", "--reverse", "HEAD"
    ).splitlines()
    try:
        baseline_index = commits.index(baseline_commit)
    except ValueError as error:
        raise ValueError(
            "RUNTIME_ATOMICITY_BASELINE_NOT_IN_FIRST_PARENT_HISTORY"
        ) from error

    baseline = collect_transition(
        runtime_project=runtime_project,
        commit=baseline_commit,
        runtime_prefix=runtime_prefix,
        event_prefix=event_prefix,
        command_prefix=command_prefix,
        audit_from_generation=enforce_from,
    )
    if baseline is None:
        raise ValueError("RUNTIME_ATOMICITY_BASELINE_NOT_A_TRANSITION")
    if baseline["runtimeGeneration"] != enforce_from:
        raise ValueError(
            "RUNTIME_ATOMICITY_BASELINE_GENERATION_MISMATCH:"
            f"{baseline['runtimeGeneration']}!={enforce_from}"
        )
    if baseline["violations"]:
        raise ValueError(
            "RUNTIME_ATOMICITY_BASELINE_NOT_CLEAN:"
            + ";".join(baseline["violations"])
        )

    actual_debt: dict[str, dict[str, Any]] = {}
    prior_enforced_transitions: list[str] = []
    for commit in commits[:baseline_index]:
        record = collect_transition(
            runtime_project=runtime_project,
            commit=commit,
            runtime_prefix=runtime_prefix,
            event_prefix=event_prefix,
            command_prefix=command_prefix,
            audit_from_generation=legacy_audit_from,
        )
        if record is None:
            continue
        if record["runtimeGeneration"] >= enforce_from:
            prior_enforced_transitions.append(commit)
        if record["violations"]:
            actual_debt[commit] = record

    if prior_enforced_transitions:
        raise ValueError(
            "RUNTIME_ATOMICITY_BASELINE_NOT_FIRST_ENFORCED_TRANSITION:"
            + ",".join(prior_enforced_transitions)
        )

    normalized_debt = compare_historical_debt(
        configured=configured_debt,
        actual=actual_debt,
    )

    return {
        "schemaVersion": 1,
        "legacyAuditFromGeneration": legacy_audit_from,
        "enforceFromGeneration": enforce_from,
        "enforcementBaseline": {
            "commit": baseline_commit,
            "runtimeGeneration": baseline["runtimeGeneration"],
            "parent": baseline["parent"],
            "changedRuntimePaths": baseline["changedRuntimePaths"],
        },
        "historicalViolationDebt": normalized_debt,
        "historicalViolationDebtCount": len(normalized_debt),
        "strictDescendantGate": "tool/mission_v15_runtime_atomicity.py",
        "pass": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-project", required=True)
    parser.add_argument(
        "--config", default="config/mission_v15_hygiene.v1.json"
    )
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = audit(
            pathlib.Path(args.runtime_project).resolve(),
            pathlib.Path(args.config).resolve(),
        )
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as error:
        print(
            f"MISSION_V15_RUNTIME_ATOMICITY_BASELINE_ERROR: {error}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
