#!/usr/bin/env python3
"""Mission delivery enforcement for collision-safe autonomous execution.

This control plane complements ``tool/mission_control.py``:

* mission_control validates deterministic roadmap/mission structure;
* mission_delivery_control validates delivered-task state, real changed-file
  ownership, shared-authority grants, scoped review invalidation, and live
  GitHub claim/PR/branch consistency.

The tool is dependency-free and fail-closed. It does not promote support,
behavior, certification, release, production, or GA status.
"""
from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.error
import urllib.request
from collections import defaultdict
from typing import Any, Iterable

CONFIG = pathlib.Path("config/mission_delivery.v1.json")
REGISTRY = pathlib.Path("docs/roadmap/missions/MISSION_REGISTRY.json")
TASKS = pathlib.Path("docs/roadmap/missions/ROADMAP_TASK_ASSIGNMENT.json")
INTERLOCKS = pathlib.Path("docs/roadmap/missions/MISSION_INTERLOCKS.json")
MISSION_CONFIG = pathlib.Path("config/mission_execution.v1.json")
WORK_ID_RE = re.compile(r"^WRK-\d{8}T\d{6}Z-[0-9a-f]{8}$")
TASK_ID_RE = re.compile(r"^P\d+-\d+$")
MISSION_ID_RE = re.compile(r"^MISSION-\d{3}$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")


class DeliveryError(RuntimeError):
    pass


def read_json(path: pathlib.Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise DeliveryError(f"required file missing: {path}") from exc
    except json.JSONDecodeError as exc:
        raise DeliveryError(f"invalid JSON {path}: {exc}") from exc


def write_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def run_git(project: pathlib.Path, *args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=project,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if check and result.returncode != 0:
        raise DeliveryError(
            f"git {' '.join(args)} failed ({result.returncode}): {result.stderr.strip()}"
        )
    return result.stdout.strip()


def normalize_path(value: str) -> str:
    text = value.replace("\\", "/")
    while text.startswith("./"):
        text = text[2:]
    if text.startswith("/") or re.match(r"^[A-Za-z]:/", text):
        raise DeliveryError(f"repository path must be relative: {value}")
    parts = [part for part in text.split("/") if part not in ("", ".")]
    if any(part == ".." for part in parts):
        raise DeliveryError(f"repository path traversal rejected: {value}")
    return "/".join(parts)


def path_matches(path: str, pattern: str) -> bool:
    path = normalize_path(path)
    pattern = normalize_path(pattern)
    # fnmatchcase handles repository paths consistently on every host.
    if fnmatch.fnmatchcase(path, pattern):
        return True
    # Treat trailing /** as matching the directory entry itself.
    if pattern.endswith("/**") and path == pattern[:-3].rstrip("/"):
        return True
    return False


def matches_any(path: str, patterns: Iterable[str]) -> bool:
    return any(path_matches(path, pattern) for pattern in patterns)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def execution_id(now: dt.datetime | None = None, entropy: bytes | None = None) -> str:
    now = now or dt.datetime.now(dt.timezone.utc)
    entropy = entropy or os.urandom(16)
    suffix = hashlib.sha256(entropy).hexdigest()[:8]
    return f"WRK-{now.strftime('%Y%m%dT%H%M%SZ')}-{suffix}"


def load_model(project: pathlib.Path) -> dict[str, Any]:
    config = read_json(project / CONFIG)
    registry = read_json(project / REGISTRY)
    tasks_doc = read_json(project / TASKS)
    interlocks = read_json(project / INTERLOCKS)
    mission_config = read_json(project / MISSION_CONFIG)

    missions = {item["id"]: item for item in registry.get("missions", [])}
    tasks_list = tasks_doc.get("tasks", [])
    tasks = {item["id"]: item for item in tasks_list}
    claims = {
        item["mission"]: item
        for item in mission_config.get("activeClaims", [])
    }
    return {
        "config": config,
        "registry": registry,
        "missions": missions,
        "tasks": tasks,
        "interlocks": interlocks,
        "missionConfig": mission_config,
        "claims": claims,
    }


def record_files(project: pathlib.Path, model: dict[str, Any]) -> list[pathlib.Path]:
    root = project / model["config"]["recordsRoot"]
    return sorted(root.glob("*/*.json")) if root.is_dir() else []


def load_latest_records(project: pathlib.Path, model: dict[str, Any]) -> dict[str, dict[str, Any]]:
    latest: dict[str, dict[str, Any]] = {}
    imported = model["config"].get("importedDeliveryAnchors", [])
    for index, item in enumerate(imported):
        value = dict(item)
        task = value.get("task")
        timestamp = value.get("recordedAt", "")
        if not isinstance(task, str):
            raise DeliveryError(f"imported delivery anchor {index} missing task")
        validate_record(value, model, f"config.importedDeliveryAnchors[{index}]")
        value["_path"] = f"config/mission_delivery.v1.json#importedDeliveryAnchors/{index}"
        latest[task] = value
    for path in record_files(project, model):
        value = read_json(path)
        task = value.get("task")
        timestamp = value.get("recordedAt", "")
        if not isinstance(task, str):
            raise DeliveryError(f"record missing task: {path}")
        previous = latest.get(task)
        if previous is None or timestamp > previous.get("recordedAt", ""):
            value = dict(value)
            value["_path"] = path.relative_to(project).as_posix()
            latest[task] = value
    return latest


def validate_record(record: dict[str, Any], model: dict[str, Any], path: str = "<record>") -> None:
    statuses = set(model["config"]["statuses"])
    mission = record.get("mission")
    task = record.get("task")
    status = record.get("status")
    if mission not in model["missions"]:
        raise DeliveryError(f"{path}: unknown mission {mission}")
    if task not in model["tasks"]:
        raise DeliveryError(f"{path}: unknown task {task}")
    expected_mission = model["tasks"][task].get("mission")
    if expected_mission != mission:
        raise DeliveryError(
            f"{path}: task {task} belongs to {expected_mission}, not {mission}"
        )
    if status not in statuses:
        raise DeliveryError(f"{path}: unsupported status {status}")
    work_id = record.get("workExecutionId")
    if not isinstance(work_id, str) or not WORK_ID_RE.fullmatch(work_id):
        raise DeliveryError(f"{path}: invalid workExecutionId {work_id}")
    if not isinstance(record.get("recordedAt"), str):
        raise DeliveryError(f"{path}: recordedAt required")
    if status in set(model["config"]["terminalAcceptedStatuses"]):
        if not record.get("commit") or not SHA_RE.fullmatch(record["commit"]):
            raise DeliveryError(f"{path}: accepted state requires exact commit")
        if not record.get("tree") or not SHA_RE.fullmatch(record["tree"]):
            raise DeliveryError(f"{path}: accepted state requires exact tree")
        if not record.get("evidence"):
            raise DeliveryError(f"{path}: accepted state requires evidence")
        if status == "MERGED_MAIN" and not record.get("mergedMainCommit"):
            raise DeliveryError(f"{path}: MERGED_MAIN requires mergedMainCommit")


def validate_config(model: dict[str, Any]) -> None:
    config = model["config"]
    missions = set(model["missions"])
    if config.get("schemaVersion") != 1:
        raise DeliveryError("config schemaVersion must be 1")
    statuses = config.get("statuses", [])
    if len(statuses) != len(set(statuses)):
        raise DeliveryError("delivery statuses must be unique")
    if set(config.get("missionPathPolicies", {})) != missions:
        missing = sorted(missions - set(config.get("missionPathPolicies", {})))
        extra = sorted(set(config.get("missionPathPolicies", {})) - missions)
        raise DeliveryError(f"mission path policies mismatch missing={missing} extra={extra}")
    modes = {"EXISTING_ON_CLAIM_BRANCH", "RESERVED_FUTURE_NAMESPACE"}
    for mission, policy in config["missionPathPolicies"].items():
        owned = policy.get("owned", [])
        if not owned:
            raise DeliveryError(f"{mission}: owned paths required")
        if len(owned) != len(set(owned)):
            raise DeliveryError(f"{mission}: duplicate owned paths")
        for namespace in policy.get("namespaces", []):
            if namespace.get("mode") not in modes:
                raise DeliveryError(f"{mission}: invalid namespace mode {namespace}")
            if namespace.get("pattern") not in owned:
                raise DeliveryError(
                    f"{mission}: namespace pattern must also be owned: {namespace}"
                )

    authorities: dict[str, dict[str, Any]] = {}
    for authority in config.get("sharedAuthorities", []):
        authority_id = authority.get("authorityId")
        if not authority_id or authority_id in authorities:
            raise DeliveryError(f"invalid or duplicate shared authority {authority_id}")
        if authority.get("ownerMission") not in missions:
            raise DeliveryError(f"{authority_id}: unknown owner mission")
        authorities[authority_id] = authority

    seen_grants: set[str] = set()
    authority_patterns = [
        (authority["ownerMission"], pattern)
        for authority in authorities.values()
        for pattern in authority.get("patterns", [])
    ]
    for grant in config.get("sharedPathGrants", []):
        cid = grant.get("coordinationId")
        if not cid or cid in seen_grants:
            raise DeliveryError(f"invalid or duplicate coordinationId {cid}")
        seen_grants.add(cid)
        if grant.get("requestingMission") not in missions:
            raise DeliveryError(f"{cid}: unknown requesting mission")
        if grant.get("ownerMission") not in missions:
            raise DeliveryError(f"{cid}: unknown owner mission")
        for pattern in grant.get("patterns", []):
            if not any(
                path_matches(pattern.replace("**", "sentinel"), ap.replace("**", "sentinel"))
                or static_prefix_overlap(pattern, ap)
                for _, ap in authority_patterns
            ):
                raise DeliveryError(f"{cid}: pattern is not governed shared authority: {pattern}")


def static_prefix(pattern: str) -> str:
    return pattern.split("*", 1)[0].rstrip("/")


def static_prefix_overlap(left: str, right: str) -> bool:
    a, b = static_prefix(left), static_prefix(right)
    return bool(a and b and (a == b or a.startswith(b + "/") or b.startswith(a + "/")))


def validate_model(project: pathlib.Path) -> dict[str, Any]:
    model = load_model(project)
    validate_config(model)
    expected_missions = model["registry"].get("missionCount")
    expected_tasks = model["registry"].get("taskCount")
    if expected_missions is not None and len(model["missions"]) != expected_missions:
        raise DeliveryError(
            f"expected {expected_missions} missions, found {len(model['missions'])}"
        )
    if expected_tasks is not None and len(model["tasks"]) != expected_tasks:
        raise DeliveryError(
            f"expected {expected_tasks} tasks, found {len(model['tasks'])}"
        )
    for path in record_files(project, model):
        validate_record(read_json(path), model, path.relative_to(project).as_posix())
    return model
