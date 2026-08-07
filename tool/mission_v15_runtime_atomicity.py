#!/usr/bin/env python3
"""Audit Mission Execution 1.5 runtime generations for commit atomicity.

Generations before the configured cutover are historical migration state.
From the cutover generation onward, every commit that changes ``runtime/**``
must represent exactly one coherent generation transition:

* runtimeGeneration increments by exactly one versus the commit parent;
* runtime/meta.json changes in the same commit;
* exactly one immutable runtime event is added in the same commit;
* the event generation matches runtime/meta.json;
* no unrelated non-runtime files are present;
* at most one newly-added connector command may travel in the same commit, and
  only when its immutable command envelope is bound to that exact generation.

The connector command exception is intentional: an AUTHORITY semaphore and the
command that exercises it must become durable atomically, so there is never an
unlocked-command window. Arbitrary docs/control/product paths remain forbidden.

Commits that do not touch ``runtime/**`` are control/documentation sync and are
not runtime-generation transitions.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
from typing import Any

DEFAULT_COMMAND_PREFIX = "docs/roadmap/missions/runtime-commands/"


def run_git(project: pathlib.Path, *args: str, check: bool = True) -> str:
    proc = subprocess.run(
        ["git", *args],
        cwd=project,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if check and proc.returncode != 0:
        raise ValueError(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout.strip()


def show_json(project: pathlib.Path, commit: str, path: str) -> dict[str, Any] | None:
    proc = subprocess.run(
        ["git", "show", f"{commit}:{path}"],
        cwd=project,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != 0:
        return None
    value = json.loads(proc.stdout)
    if not isinstance(value, dict):
        raise ValueError(f"{commit}:{path} must be a JSON object")
    return value


def changed_entries(project: pathlib.Path, parent: str, commit: str) -> list[tuple[str, str]]:
    text = run_git(
        project,
        "diff-tree",
        "--no-commit-id",
        "--name-status",
        "-r",
        parent,
        commit,
    )
    result: list[tuple[str, str]] = []
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        status = parts[0]
        # Renames/copies contain old and new path. Treat the destination as the
        # changed path and preserve the full status so envelope mutation fails.
        path = parts[-1]
        result.append((status, path))
    return result


def validate_command_document(
    *,
    status: str,
    path: str,
    command: dict[str, Any] | None,
    generation: int,
) -> list[str]:
    violations: list[str] = []
    if status != "A":
        violations.append(f"COMMAND_ENVELOPE_NOT_IMMUTABLE_ADD:{status}:{path}")
        return violations
    if command is None:
        violations.append(f"COMMAND_ENVELOPE_NOT_READABLE:{path}")
        return violations
    if command.get("schemaVersion") != 1:
        violations.append(f"COMMAND_ENVELOPE_SCHEMA_VERSION_INVALID:{path}")
    expected_generation = command.get("expectedRuntimeGeneration")
    if expected_generation != generation:
        violations.append(
            f"COMMAND_ENVELOPE_GENERATION_MISMATCH:{path}:{expected_generation}!={generation}"
        )
    command_id = command.get("commandId")
    if not isinstance(command_id, str) or not command_id:
        violations.append(f"COMMAND_ENVELOPE_ID_MISSING:{path}")
    elif pathlib.PurePosixPath(path).stem != command_id:
        violations.append(
            f"COMMAND_ENVELOPE_FILENAME_ID_MISMATCH:{pathlib.PurePosixPath(path).stem}!={command_id}"
        )
    operation = command.get("operation")
    if not isinstance(operation, str) or not operation:
        violations.append(f"COMMAND_ENVELOPE_OPERATION_MISSING:{path}")
    for key in ("workOrderId", "semaphoreId", "workerIdentity"):
        value = command.get(key)
        if not isinstance(value, str) or not value:
            violations.append(f"COMMAND_ENVELOPE_{key.upper()}_MISSING:{path}")
    return violations


def audit(runtime_project: pathlib.Path, config_path: pathlib.Path) -> dict[str, Any]:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    atomicity = config.get("runtimeAtomicity") or {}
    enforce_from = int(atomicity.get("enforceFromGeneration", 12))
    runtime_prefix = str(atomicity.get("runtimePathPrefix", "runtime/"))
    event_prefix = str(atomicity.get("eventPathPrefix", "runtime/events/"))
    command_prefix = str(atomicity.get("commandPathPrefix", DEFAULT_COMMAND_PREFIX))

    commits = run_git(runtime_project, "rev-list", "--first-parent", "--reverse", "HEAD").splitlines()
    violations: list[str] = []
    audited: list[dict[str, Any]] = []

    for commit in commits:
        parents = run_git(runtime_project, "rev-list", "--parents", "-n", "1", commit).split()
        if len(parents) < 2:
            continue
        parent = parents[1]
        meta = show_json(runtime_project, commit, "runtime/meta.json")
        if meta is None:
            continue
        parent_meta = show_json(runtime_project, parent, "runtime/meta.json")
        generation = int(meta.get("runtimeGeneration", -1))

        entries = changed_entries(runtime_project, parent, commit)
        runtime_entries = [(status, path) for status, path in entries if path.startswith(runtime_prefix)]
        if not runtime_entries:
            continue
        if generation < enforce_from:
            continue

        parent_generation = (
            int(parent_meta.get("runtimeGeneration", -1)) if parent_meta is not None else None
        )
        commit_violations: list[str] = []

        if parent_generation is None:
            commit_violations.append("MISSING_PARENT_RUNTIME_META")
        elif generation != parent_generation + 1:
            commit_violations.append(
                f"GENERATION_NOT_SINGLE_STEP:{parent_generation}->{generation}"
            )

        runtime_paths = {path for _, path in runtime_entries}
        if "runtime/meta.json" not in runtime_paths:
            commit_violations.append("RUNTIME_CHANGE_WITHOUT_META")

        non_runtime_entries = [
            (status, path) for status, path in entries if not path.startswith(runtime_prefix)
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
            commit_violations.append(
                "GENERATION_COMMIT_HAS_NON_RUNTIME_PATHS:" + ",".join(unrelated_non_runtime)
            )
        if len(command_entries) > 1:
            commit_violations.append(
                f"GENERATION_COMMAND_ENVELOPE_ATOMICITY:count={len(command_entries)}"
            )
        elif len(command_entries) == 1:
            status, command_path = command_entries[0]
            command = show_json(runtime_project, commit, command_path)
            commit_violations.extend(
                validate_command_document(
                    status=status,
                    path=command_path,
                    command=command,
                    generation=generation,
                )
            )

        event_entries = [(status, path) for status, path in runtime_entries if path.startswith(event_prefix)]
        added_events = [(status, path) for status, path in event_entries if status == "A"]
        if len(event_entries) != 1 or len(added_events) != 1:
            commit_violations.append(
                f"GENERATION_EVENT_ATOMICITY:eventChanges={len(event_entries)},added={len(added_events)}"
            )
        else:
            event_path = added_events[0][1]
            event = show_json(runtime_project, commit, event_path)
            if event is None:
                commit_violations.append("ADDED_EVENT_NOT_READABLE")
            else:
                if int(event.get("runtimeGeneration", -1)) != generation:
                    commit_violations.append(
                        f"EVENT_GENERATION_MISMATCH:{event.get('runtimeGeneration')}!={generation}"
                    )
                if event.get("schemaVersion") != 1:
                    commit_violations.append("EVENT_SCHEMA_VERSION_INVALID")
                event_id = event.get("eventId")
                if not isinstance(event_id, str) or not event_id:
                    commit_violations.append("EVENT_ID_MISSING")
                elif pathlib.PurePosixPath(event_path).stem != event_id:
                    commit_violations.append(
                        f"EVENT_FILENAME_ID_MISMATCH:{pathlib.PurePosixPath(event_path).stem}!={event_id}"
                    )

        audited.append(
            {
                "commit": commit,
                "parent": parent,
                "runtimeGeneration": generation,
                "parentRuntimeGeneration": parent_generation,
                "changedRuntimePaths": sorted(runtime_paths),
                "commandEnvelopePaths": sorted(path for _, path in command_entries),
                "violations": commit_violations,
            }
        )
        violations.extend(f"{commit}:{item}" for item in commit_violations)

    result = {
        "schemaVersion": 1,
        "enforceFromGeneration": enforce_from,
        "commandPathPrefix": command_prefix,
        "auditedTransitions": audited,
        "violations": violations,
        "pass": not violations,
    }
    if violations:
        raise ValueError("; ".join(violations))
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-project", required=True)
    parser.add_argument("--config", default="config/mission_v15_hygiene.v1.json")
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
    except Exception as exc:
        print(f"MISSION_V15_RUNTIME_ATOMICITY_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
