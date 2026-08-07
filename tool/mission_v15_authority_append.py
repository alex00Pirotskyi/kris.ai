#!/usr/bin/env python3
"""Fail-closed append-safe shared-authority verifier for Mission Execution 1.5."""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Any

from mission_delivery_lib import load_model, matches_any, run_git


def git_text(project: pathlib.Path, commit: str, path: str) -> str:
    return run_git(project, "show", f"{commit}:{path}")


def _identity_sequence(items: Any, key: str, label: str) -> list[str]:
    if not isinstance(items, list):
        raise ValueError(f"{label} must be an array")
    result: list[str] = []
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            raise ValueError(f"{label}[{index}] must be an object")
        value = item.get(key)
        if not isinstance(value, str) or not value:
            raise ValueError(f"{label}[{index}].{key} must be non-empty")
        result.append(value)
    if len(result) != len(set(result)):
        raise ValueError(f"{label} contains duplicate {key} values")
    return result


def verify_append_safe_json(
    base_text: str,
    head_text: str,
    collections: dict[str, str],
) -> dict[str, list[str]]:
    base = json.loads(base_text)
    head = json.loads(head_text)
    if not isinstance(base, dict) or not isinstance(head, dict):
        raise ValueError("append-safe JSON authority must be an object")
    if set(base) != set(head):
        raise ValueError("append-safe JSON authority cannot add/remove top-level keys")
    appended: dict[str, list[str]] = {}
    for key in sorted(base):
        if key not in collections:
            if base[key] != head[key]:
                raise ValueError(f"append-safe authority changed immutable field {key}")
            continue
        identity = collections[key]
        base_items = base[key]
        head_items = head[key]
        base_ids = _identity_sequence(base_items, identity, key)
        head_ids = _identity_sequence(head_items, identity, key)
        if head_ids[: len(base_ids)] != base_ids:
            raise ValueError(f"{key} must preserve all existing identities in original order")
        if head_items[: len(base_items)] != base_items:
            raise ValueError(f"{key} modified an existing authority object")
        appended[key] = head_ids[len(base_ids) :]
    return appended


def _dart_set(text: str, marker: str) -> tuple[str, str, list[str]]:
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
    return text[: open_brace + 1], text[end:], values


def verify_append_safe_dart_set(
    project: pathlib.Path,
    head_commit: str,
    base_text: str,
    head_text: str,
    marker: str,
    path_prefix: str,
    requesting_mission: str,
) -> dict[str, list[str]]:
    base_prefix, base_suffix, base_values = _dart_set(base_text, marker)
    head_prefix, head_suffix, head_values = _dart_set(head_text, marker)
    if base_prefix != head_prefix or base_suffix != head_suffix:
        raise ValueError("source inventory append changed code outside the governed expected set")
    if head_values[: len(base_values)] != base_values:
        raise ValueError("source inventory must preserve existing entries in original order")
    appended = head_values[len(base_values) :]
    model = load_model(project)
    owned = model["config"]["missionPathPolicies"][requesting_mission]["owned"]
    for path in appended:
        if not path.startswith(path_prefix):
            raise ValueError(f"source inventory append outside required prefix {path_prefix}: {path}")
        if not matches_any(path, owned):
            raise ValueError(
                f"source inventory append {path} is not owned by {requesting_mission}"
            )
        # The working tree is expected to be the exact candidate checkout.
        if not (project / path).is_file():
            # Fall back to exact Git object existence so detached validation works.
            try:
                run_git(project, "cat-file", "-e", f"{head_commit}:{path}")
            except Exception as exc:
                raise ValueError(f"source inventory appended missing source path {path}") from exc
    return {"expectedSourcePaths": appended}


def verify_authority(
    project: pathlib.Path,
    *,
    config_path: pathlib.Path,
    authority_id: str,
    requesting_mission: str,
    base_commit: str,
    head_commit: str,
) -> dict[str, Any]:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if config.get("schemaVersion") != 1:
        raise ValueError("invalid v1.5 authority config schemaVersion")
    authority = config.get("authorities", {}).get(authority_id)
    if not isinstance(authority, dict):
        raise ValueError(f"unknown authority {authority_id}")
    eligible = authority.get("eligibleRequestingMissions", [])
    if requesting_mission != authority.get("ownerMission") and requesting_mission not in eligible:
        raise ValueError(
            f"{requesting_mission} is not eligible for append-safe authority {authority_id}"
        )
    path = authority["path"]
    run_git(project, "cat-file", "-e", f"{base_commit}^{{commit}}")
    run_git(project, "cat-file", "-e", f"{head_commit}^{{commit}}")
    run_git(project, "merge-base", "--is-ancestor", base_commit, head_commit)
    base_text = git_text(project, base_commit, path)
    head_text = git_text(project, head_commit, path)
    mode = authority["mode"]
    if mode == "APPEND_SAFE_JSON":
        appended = verify_append_safe_json(
            base_text,
            head_text,
            authority.get("collections", {}),
        )
    elif mode == "APPEND_SAFE_DART_SET":
        appended = verify_append_safe_dart_set(
            project,
            head_commit,
            base_text,
            head_text,
            authority["setStartMarker"],
            authority["pathPrefix"],
            requesting_mission,
        )
    else:
        raise ValueError(f"unsupported append-safe authority mode {mode}")
    return {
        "schemaVersion": 1,
        "authorityId": authority_id,
        "ownerMission": authority["ownerMission"],
        "requestingMission": requesting_mission,
        "path": path,
        "mode": mode,
        "baseCommit": base_commit,
        "headCommit": head_commit,
        "appended": appended,
        "existingAuthorityModified": False,
        "pass": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--config", default="config/mission_v15_authorities.v1.json")
    parser.add_argument("--authority-id", required=True)
    parser.add_argument("--requesting-mission", required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        project = pathlib.Path(args.project).resolve()
        result = verify_authority(
            project,
            config_path=pathlib.Path(args.config).resolve(),
            authority_id=args.authority_id,
            requesting_mission=args.requesting_mission,
            base_commit=args.base,
            head_commit=args.head,
        )
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_AUTHORITY_APPEND_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
