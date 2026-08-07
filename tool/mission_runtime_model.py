#!/usr/bin/env python3
"""Mission Execution 1.5 mutable runtime model.

The existing ``mission_runtime_control.py`` remains the compatibility surface
for v1 helper leases while this module owns the v1.5 Work Order/semaphore/event
runtime. It reuses roadmap/delivery helpers and does not duplicate acceptance
truth.
"""
from __future__ import annotations

import datetime as dt
import json
import pathlib
from typing import Any

from mission_delivery_lib import DeliveryError, load_latest_records, load_model
from mission_runtime_control import (
    ACCEPTED,
    mission_maximum_patterns,
    pattern_within,
    prefixes_overlap,
    verify_git_base,
)

RUNTIME = pathlib.Path("runtime")
META = RUNTIME / "meta.json"
CLAIMS = RUNTIME / "claims"
WORK_ORDERS = RUNTIME / "work-orders"
SEMAPHORES = RUNTIME / "semaphores"
EVENTS = RUNTIME / "events"
PRODUCT_PRS = RUNTIME / "integration/product-prs"

WORK_ORDER_STATES = {
    "CREATED", "READY", "RESERVED", "IN_PROGRESS", "HELPER_READY",
    "INTEGRATING", "VALIDATING", "REVIEW", "LANDED", "BLOCKED",
    "SUPERSEDED", "CANCELLED",
}
WORK_ORDER_TYPES = {
    "PRODUCT_FEATURE", "PRODUCT_DEFECT_REPAIR", "PRODUCT_TEST", "CI_REPAIR",
    "INTEGRATION", "REVIEW", "SECURITY_REVIEW", "AUTHORITY_UPDATE",
    "BLOCKER_REMOVAL", "EVIDENCE_FINALIZATION", "RELEASE_FINALIZATION",
    "INCIDENT",
}
ROLES = {
    "CAPTAIN", "BUILDER", "TESTER", "DEFECT_HUNTER", "CI_REPAIR",
    "REVIEWER", "SECURITY_REVIEWER", "INTEGRATOR", "AUTHORITY_OWNER",
    "AUDITOR", "RELEASE_FINALIZER", "INCIDENT_RESPONDER",
}
SEMAPHORE_KINDS = {"WRITE", "INTEGRATION", "AUTHORITY", "RELEASE"}
SEMAPHORE_STATES = {"ACTIVE", "RELEASED", "EXPIRED"}
DEPENDENCY_LEVELS = {
    "IMPLEMENTATION", "INTEGRATION", "LANDING", "ACCEPTANCE",
    "CERTIFICATION", "RELEASE",
}
CLAIM_STATES = {"ACTIVE", "PAUSED", "YIELDED", "COMPLETE"}
CLAIM_PRIORITIES = {"CRITICAL", "HIGH", "MEDIUM", "LOW"}
BUILD_TYPES = {"PRODUCT_FEATURE", "PRODUCT_DEFECT_REPAIR", "PRODUCT_TEST"}
ACTIVE_WORK = {
    "READY", "RESERVED", "IN_PROGRESS", "HELPER_READY", "INTEGRATING",
    "VALIDATING", "REVIEW",
}
TERMINAL_WORK = {"LANDED", "SUPERSEDED", "CANCELLED"}
HELPER_READY_LIMIT = 2
ACTIVE_BUILD_LIMIT = 3

WORKER_MISSION_EXPERTISE = {
    "A": {"MISSION-001"},
    "B": {"MISSION-002"},
    "C": {"MISSION-004"},
    "D": {"MISSION-003", "MISSION-004"},
    "E": {"MISSION-010"},
    "F": {"MISSION-005"},
    "G": {"MISSION-006"},
    "H": set(),
    "I": {"MISSION-007"},
    "J": {"MISSION-015"},
}


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def iso(value: dt.datetime) -> str:
    return (
        value.astimezone(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def parse_time(value: str) -> dt.datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ValueError(f"runtime timestamp must be UTC RFC3339: {value!r}")
    return dt.datetime.fromisoformat(value[:-1] + "+00:00").astimezone(dt.timezone.utc)


def read_json(path: pathlib.Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def meta(project: pathlib.Path) -> dict[str, Any]:
    path = project / META
    if not path.is_file():
        raise ValueError(f"Mission Execution 1.5 runtime missing {META}")
    value = read_json(path)
    if value.get("schemaVersion") != 1 or not isinstance(value.get("runtimeGeneration"), int):
        raise ValueError("invalid runtime meta")
    return value


def claim_files(project: pathlib.Path) -> list[pathlib.Path]:
    root = project / CLAIMS
    return sorted(root.glob("MISSION-*.json")) if root.is_dir() else []


def work_order_files(project: pathlib.Path) -> list[pathlib.Path]:
    root = project / WORK_ORDERS
    return sorted(root.glob("**/*.json")) if root.is_dir() else []


def semaphore_files(project: pathlib.Path) -> list[pathlib.Path]:
    root = project / SEMAPHORES
    return sorted(root.glob("**/*.json")) if root.is_dir() else []


def product_pr_files(project: pathlib.Path) -> list[pathlib.Path]:
    root = project / PRODUCT_PRS
    return sorted(root.glob("*.json")) if root.is_dir() else []


def load_claims(project: pathlib.Path, model: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for path in claim_files(project):
        item = read_json(path)
        mission = item.get("mission")
        if item.get("schemaVersion") != 2:
            raise ValueError(f"Mission Claim v2 schema required: {path}")
        if mission not in model["missions"] or mission in result:
            raise ValueError(f"invalid/duplicate Mission Claim v2: {path}")
        if item.get("status") not in CLAIM_STATES:
            raise ValueError(f"invalid Mission Claim v2 status: {path}")
        captain = item.get("captainWorker")
        if not isinstance(captain, str) or not captain:
            raise ValueError(f"Mission Claim v2 captain required: {path}")
        if item.get("integrationAuthority") != captain:
            raise ValueError(
                f"Mission Claim v2 integrationAuthority must equal captain during v1.5 migration: {path}"
            )
        if item.get("priority") not in CLAIM_PRIORITIES:
            raise ValueError(f"invalid Mission Claim v2 priority: {path}")
        if not isinstance(item.get("currentProductPrs"), list):
            raise ValueError(f"Mission Claim v2 currentProductPrs must be an array: {path}")
        if not isinstance(item.get("runtimeGeneration"), int):
            raise ValueError(f"Mission Claim v2 runtimeGeneration required: {path}")
        parse_time(item["updatedAt"])
        item["_path"] = path.relative_to(project).as_posix()
        result[mission] = item
    return result


def load_work_orders(project: pathlib.Path) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for path in work_order_files(project):
        item = read_json(path)
        key = item.get("workOrderId")
        if not isinstance(key, str) or key in result:
            raise ValueError(f"invalid/duplicate Work Order: {path}")
        item["_path"] = path.relative_to(project).as_posix()
        result[key] = item
    return result


def load_product_prs(project: pathlib.Path) -> dict[int, dict[str, Any]]:
    result: dict[int, dict[str, Any]] = {}
    tasks: set[str] = set()
    for path in product_pr_files(project):
        item = read_json(path)
        pr = item.get("productPr")
        task = item.get("task")
        if item.get("schemaVersion") != 1:
            raise ValueError(f"canonical Product PR schemaVersion must be 1: {path}")
        if not isinstance(pr, int) or pr <= 0 or pr in result:
            raise ValueError(f"invalid/duplicate canonical Product PR: {path}")
        if not isinstance(task, str) or task in tasks:
            raise ValueError(f"duplicate canonical Product PR task mapping: {task}")
        if not isinstance(item.get("branch"), str) or not item.get("branch"):
            raise ValueError(f"canonical Product PR branch required: {path}")
        tasks.add(task)
        item["_path"] = path.relative_to(project).as_posix()
        result[pr] = item
    return result


def validate_claim_product_prs(
    claims: dict[str, dict[str, Any]],
    product_prs: dict[int, dict[str, Any]],
) -> None:
    for pr, product in product_prs.items():
        mission = product.get("mission")
        claim = claims.get(mission)
        if claim is None:
            raise ValueError(f"canonical Product PR #{pr} has no Mission Claim v2 for {mission}")
        if product.get("captain") != claim.get("captainWorker"):
            raise ValueError(f"canonical Product PR #{pr} captain differs from Mission Claim v2")
        if pr not in claim.get("currentProductPrs", []):
            raise ValueError(f"canonical Product PR #{pr} missing from Mission Claim v2 currentProductPrs")
    for mission, claim in claims.items():
        for pr in claim.get("currentProductPrs", []):
            product = product_prs.get(pr)
            if product is None or product.get("mission") != mission:
                raise ValueError(f"Mission Claim v2 {mission} references non-canonical Product PR #{pr}")


def _dependency_satisfied(
    requirement: dict[str, Any],
    latest: dict[str, dict[str, Any]],
) -> bool:
    task = requirement["task"]
    level = requirement["level"]
    record = latest.get(task, {})
    status = record.get("status", "NOT_EVALUATED")
    landing = record.get("sourceLanding", "NOT_LANDED")
    if level == "IMPLEMENTATION":
        return bool(record) and (
            landing in {"HELPER", "PRODUCT_PR", "LANDED_MAIN"}
            or status not in {"NOT_EVALUATED", "LEGACY_OTHER"}
        )
    if level == "INTEGRATION":
        return landing in {"PRODUCT_PR", "LANDED_MAIN"}
    if level == "LANDING":
        return landing == "LANDED_MAIN"
    if level in {"ACCEPTANCE", "CERTIFICATION"}:
        return status in ACCEPTED
    if level == "RELEASE":
        return status in ACCEPTED and record.get("releaseSupport") == "SUPPORTED"
    raise ValueError(f"unsupported dependency level {level}")


def validate_work_order(
    project: pathlib.Path,
    item: dict[str, Any],
    model: dict[str, Any],
    claims: dict[str, dict[str, Any]],
    product_prs: dict[int, dict[str, Any]],
    latest: dict[str, dict[str, Any]],
) -> None:
    required = {
        "schemaVersion", "workOrderId", "mission", "roadmapTask",
        "parentProductPr", "priority", "type", "objective", "requestedRole",
        "allowedPaths", "baseCommit", "baseTree", "dependencyRequirements",
        "requiredTests", "maxChildWorkOrders", "status", "createdBy", "createdAt",
    }
    missing = sorted(required - set(item))
    if missing:
        raise ValueError(f"Work Order missing fields: {missing}")
    if item["schemaVersion"] != 1:
        raise ValueError("Work Order schemaVersion must be 1")
    mission = item["mission"]
    task = item["roadmapTask"]
    claim = claims.get(mission)
    if claim is None or claim.get("status") != "ACTIVE":
        raise ValueError(f"Work Order requires active Mission Claim v2: {mission}")
    if mission not in model["missions"]:
        raise ValueError(f"Work Order unknown mission {mission}")
    if task not in model["tasks"] or model["tasks"][task].get("mission") != mission:
        raise ValueError(f"Work Order task {task} does not belong to {mission}")
    if item["type"] not in WORK_ORDER_TYPES or item["requestedRole"] not in ROLES:
        raise ValueError("Work Order type/role invalid")
    if item["status"] not in WORK_ORDER_STATES:
        raise ValueError(f"Work Order status invalid: {item['status']}")
    pr = item["parentProductPr"]
    product = product_prs.get(pr)
    if product is None or product.get("task") != task or product.get("mission") != mission:
        raise ValueError(f"Work Order parentProductPr {pr} is not canonical for {task}")
    allowed = item.get("allowedPaths") or []
    maxima = mission_maximum_patterns(model, mission)
    for path in allowed:
        if not any(pattern_within(path, maximum) for maximum in maxima):
            raise ValueError(f"Work Order path exceeds mission policy: {path}")
    verify_git_base(project, item["baseCommit"], item["baseTree"])
    parent_id = item.get("parentWorkOrderId")
    if parent_id is not None and not isinstance(parent_id, str):
        raise ValueError("parentWorkOrderId must be null or string")
    for requirement in item.get("dependencyRequirements") or []:
        if set(requirement) != {"task", "level"}:
            raise ValueError(f"invalid dependency requirement: {requirement}")
        if requirement["task"] not in model["tasks"]:
            raise ValueError(f"unknown Work Order dependency {requirement['task']}")
        if requirement["level"] not in DEPENDENCY_LEVELS:
            raise ValueError(f"unsupported dependency level {requirement['level']}")
        if (
            item["status"] in ACTIVE_WORK
            and not _dependency_satisfied(requirement, latest)
        ):
            raise ValueError(
                f"Work Order {item['workOrderId']} dependency not satisfied: "
                f"{requirement['task']}@{requirement['level']}"
            )
    parse_time(item["createdAt"])
    if item.get("updatedAt"):
        parse_time(item["updatedAt"])


def validate_delegation_graph(work_orders: dict[str, dict[str, Any]]) -> None:
    for work_id, item in work_orders.items():
        parent_id = item.get("parentWorkOrderId")
        if not parent_id:
            continue
        parent = work_orders.get(parent_id)
        if parent is None:
            raise ValueError(f"Work Order {work_id} references missing parent {parent_id}")
        if (
            parent["mission"] != item["mission"]
            or parent["roadmapTask"] != item["roadmapTask"]
            or parent["parentProductPr"] != item["parentProductPr"]
        ):
            raise ValueError(f"delegated Work Order {work_id} must remain in parent mission/task/Product PR")
        seen = {work_id}
        cursor = parent
        while cursor.get("parentWorkOrderId"):
            parent_cursor = cursor["parentWorkOrderId"]
            if parent_cursor in seen:
                raise ValueError(f"Work Order delegation cycle detected at {work_id}")
            seen.add(parent_cursor)
            cursor = work_orders.get(parent_cursor)
            if cursor is None:
                raise ValueError(f"Work Order delegation chain missing {parent_cursor}")
    for work_id, parent in work_orders.items():
        children = [
            child
            for child in work_orders.values()
            if child.get("parentWorkOrderId") == work_id
            and child.get("status") not in {"CANCELLED", "SUPERSEDED"}
        ]
        if len(children) > int(parent.get("maxChildWorkOrders", 0)):
            raise ValueError(
                f"Work Order {work_id} child budget exceeded: {len(children)} > {parent.get('maxChildWorkOrders')}"
            )


def _active(item: dict[str, Any], now: dt.datetime) -> bool:
    return item.get("status") == "ACTIVE" and parse_time(item["expiresAt"]) > now


def semaphore_collides(left: dict[str, Any], right: dict[str, Any]) -> bool:
    if left["kind"] == "WRITE" and right["kind"] == "WRITE":
        return any(
            prefixes_overlap(a, b)
            for a in left.get("allowedPaths", [])
            for b in right.get("allowedPaths", [])
        )
    if left["kind"] == "INTEGRATION" and right["kind"] == "INTEGRATION":
        return left.get("productPr") == right.get("productPr")
    if left["kind"] == "AUTHORITY" and right["kind"] == "AUTHORITY":
        if left.get("authorityId") != right.get("authorityId"):
            return False
        lpaths, rpaths = left.get("allowedPaths", []), right.get("allowedPaths", [])
        if not lpaths or not rpaths:
            return True
        return any(prefixes_overlap(a, b) for a in lpaths for b in rpaths)
    if left["kind"] == "RELEASE" and right["kind"] == "RELEASE":
        return left.get("resourceId") == right.get("resourceId")
    return False


def validate_semaphore(
    project: pathlib.Path,
    item: dict[str, Any],
    work_orders: dict[str, dict[str, Any]],
    product_prs: dict[int, dict[str, Any]],
) -> None:
    required = {
        "schemaVersion", "semaphoreId", "kind", "workOrderId", "mission",
        "workerIdentity", "executionRole", "baseCommit", "baseTree",
        "allowedPaths", "createdAt", "refreshedAt", "expiresAt",
        "runtimeGeneration", "status",
    }
    missing = sorted(required - set(item))
    if missing:
        raise ValueError(f"semaphore missing fields: {missing}")
    if item["schemaVersion"] != 1 or item["kind"] not in SEMAPHORE_KINDS:
        raise ValueError("invalid semaphore schema/kind")
    if item["status"] not in SEMAPHORE_STATES:
        raise ValueError("invalid semaphore status")
    work = work_orders.get(item["workOrderId"])
    if work is None:
        raise ValueError(f"semaphore references unknown Work Order {item['workOrderId']}")
    if item["mission"] != work["mission"]:
        raise ValueError("semaphore mission differs from Work Order mission")
    if item["executionRole"] not in ROLES:
        raise ValueError("invalid semaphore execution role")
    verify_git_base(project, item["baseCommit"], item["baseTree"])
    product = product_prs[work["parentProductPr"]]
    if item["kind"] == "WRITE":
        branch = item.get("branch")
        if not isinstance(branch, str) or not branch:
            raise ValueError("WRITE semaphore requires branch")
        if branch == product["branch"]:
            raise ValueError("WRITE semaphore branch must differ from canonical Product PR branch")
        if not item.get("allowedPaths"):
            raise ValueError("WRITE semaphore requires non-empty allowedPaths")
        for path in item["allowedPaths"]:
            if not any(pattern_within(path, allowed) for allowed in work["allowedPaths"]):
                raise ValueError(f"WRITE semaphore path exceeds Work Order scope: {path}")
    if item["kind"] == "INTEGRATION":
        if item.get("productPr") != work["parentProductPr"]:
            raise ValueError("INTEGRATION semaphore must bind Work Order canonical Product PR")
        if item.get("branch") not in {None, product["branch"]}:
            raise ValueError("INTEGRATION semaphore branch must be canonical Product PR branch")
    if item["kind"] == "AUTHORITY" and not item.get("authorityId"):
        raise ValueError("AUTHORITY semaphore requires authorityId")
    if item["kind"] == "RELEASE" and not item.get("resourceId"):
        raise ValueError("RELEASE semaphore requires resourceId")
    created, refreshed, expires = map(
        parse_time,
        (item["createdAt"], item["refreshedAt"], item["expiresAt"]),
    )
    if refreshed < created or expires <= refreshed:
        raise ValueError("semaphore timestamp ordering invalid")


def load_semaphores(
    project: pathlib.Path,
    work_orders: dict[str, dict[str, Any]],
    product_prs: dict[int, dict[str, Any]],
    now: dt.datetime | None = None,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    now = now or utc_now()
    all_items: list[dict[str, Any]] = []
    active: list[dict[str, Any]] = []
    branches: dict[str, str] = {}
    for path in semaphore_files(project):
        item = read_json(path)
        item["_path"] = path.relative_to(project).as_posix()
        validate_semaphore(project, item, work_orders, product_prs)
        all_items.append(item)
        if _active(item, now):
            if item["kind"] == "WRITE":
                branch = item["branch"]
                if branch in branches:
                    raise ValueError(
                        f"active WRITE branch reused: {branch} "
                        f"({branches[branch]}, {item['semaphoreId']})"
                    )
                branches[branch] = item["semaphoreId"]
            active.append(item)
    for index, left in enumerate(active):
        for right in active[index + 1 :]:
            if semaphore_collides(left, right):
                raise ValueError(
                    f"active semaphore collision: {left['semaphoreId']} vs {right['semaphoreId']}"
                )
    return all_items, active


def validate_runtime_state(project: pathlib.Path) -> dict[str, Any]:
    runtime_meta = meta(project)
    model = load_model(project)
    latest = load_latest_records(project, model)
    claims = load_claims(project, model)
    products = load_product_prs(project)
    validate_claim_product_prs(claims, products)
    work_orders = load_work_orders(project)
    for item in work_orders.values():
        validate_work_order(project, item, model, claims, products, latest)
    validate_delegation_graph(work_orders)
    all_sems, active = load_semaphores(project, work_orders, products)
    for item in active:
        if item["runtimeGeneration"] > runtime_meta["runtimeGeneration"]:
            raise ValueError("semaphore generation is ahead of runtime meta")
    for claim in claims.values():
        if claim["runtimeGeneration"] > runtime_meta["runtimeGeneration"]:
            raise ValueError("Mission Claim v2 generation is ahead of runtime meta")
    return {
        "meta": runtime_meta,
        "model": model,
        "claims": claims,
        "productPrs": products,
        "workOrders": work_orders,
        "semaphores": all_sems,
        "activeSemaphores": active,
    }


def _work_order_path(project: pathlib.Path, work: dict[str, Any]) -> pathlib.Path:
    return project / WORK_ORDERS / work["mission"] / f"{work['workOrderId']}.json"


def _semaphore_path(project: pathlib.Path, item: dict[str, Any]) -> pathlib.Path:
    return project / SEMAPHORES / item["mission"] / f"{item['semaphoreId']}.json"


def _event_path(project: pathlib.Path, event: dict[str, Any]) -> pathlib.Path:
    return project / EVENTS / event["recordedAt"][:10] / f"{event['eventId']}.json"


def _bump_generation(
    project: pathlib.Path,
    current_meta: dict[str, Any],
    *,
    event_type: str,
    work_execution_id: str,
    mission: str | None,
    work_order_id: str | None,
    payload: dict[str, Any],
) -> int:
    generation = current_meta["runtimeGeneration"] + 1
    current_meta["runtimeGeneration"] = generation
    current_meta["updatedAt"] = iso(utc_now())
    write_json(project / META, current_meta)
    event = {
        "schemaVersion": 1,
        "eventId": f"EVT-{generation:08d}-{event_type}",
        "eventType": event_type,
        "runtimeGeneration": generation,
        "recordedAt": iso(utc_now()),
        "workExecutionId": work_execution_id,
        "workOrderId": work_order_id,
        "mission": mission,
        "payload": payload,
    }
    write_json(_event_path(project, event), event)
    return generation


def _wip_counts(work_orders: dict[str, dict[str, Any]], product_pr: int) -> tuple[int, int]:
    active_build = sum(
        1
        for work in work_orders.values()
        if work["parentProductPr"] == product_pr
        and work["type"] in BUILD_TYPES
        and work["status"] in ACTIVE_WORK
    )
    helper_ready = sum(
        1
        for work in work_orders.values()
        if work["parentProductPr"] == product_pr and work["status"] == "HELPER_READY"
    )
    return active_build, helper_ready


def create_work_order(
    project: pathlib.Path,
    *,
    work_order: dict[str, Any],
    work_execution_id: str,
    expected_generation: int,
) -> dict[str, Any]:
    state = validate_runtime_state(project)
    runtime_meta = state["meta"]
    if runtime_meta["runtimeGeneration"] != expected_generation:
        raise ValueError(
            f"runtime generation moved: expected {expected_generation}, "
            f"actual {runtime_meta['runtimeGeneration']}"
        )
    work_order = dict(work_order)
    work_id = work_order.get("workOrderId")
    if work_id in state["workOrders"]:
        raise ValueError(f"Work Order already exists: {work_id}")
    work_order.setdefault("status", "READY")
    work_order.setdefault("createdAt", iso(utc_now()))
    work_order["updatedAt"] = iso(utc_now())
    validate_work_order(
        project,
        work_order,
        state["model"],
        state["claims"],
        state["productPrs"],
        load_latest_records(project, state["model"]),
    )
    parent_id = work_order.get("parentWorkOrderId")
    if parent_id:
        parent = state["workOrders"].get(parent_id)
        if parent is None:
            raise ValueError(f"delegation parent missing: {parent_id}")
        existing_children = [
            child
            for child in state["workOrders"].values()
            if child.get("parentWorkOrderId") == parent_id
            and child.get("status") not in {"CANCELLED", "SUPERSEDED"}
        ]
        if len(existing_children) >= int(parent.get("maxChildWorkOrders", 0)):
            raise ValueError(f"delegation budget exhausted for {parent_id}")
        if (
            parent["mission"] != work_order["mission"]
            or parent["roadmapTask"] != work_order["roadmapTask"]
            or parent["parentProductPr"] != work_order["parentProductPr"]
        ):
            raise ValueError("delegated Work Order must remain within parent mission/task/Product PR")
    active_build, helper_ready = _wip_counts(
        state["workOrders"], work_order["parentProductPr"]
    )
    if work_order["type"] in BUILD_TYPES:
        if helper_ready >= HELPER_READY_LIMIT:
            raise ValueError("Product PR integration backpressure: two helpers are already waiting")
        if active_build >= ACTIVE_BUILD_LIMIT:
            raise ValueError("Product PR active build WIP limit reached")
    write_json(_work_order_path(project, work_order), work_order)
    generation = _bump_generation(
        project,
        runtime_meta,
        event_type="WORK_ORDER_READY",
        work_execution_id=work_execution_id,
        mission=work_order["mission"],
        work_order_id=work_id,
        payload={
            "type": work_order["type"],
            "requestedRole": work_order["requestedRole"],
            "parentWorkOrderId": parent_id,
        },
    )
    work_order["runtimeGeneration"] = generation
    return work_order


def transition_work_order(
    project: pathlib.Path,
    *,
    work_order_id: str,
    next_status: str,
    work_execution_id: str,
    expected_generation: int,
    actor: str,
) -> dict[str, Any]:
    state = validate_runtime_state(project)
    runtime_meta = state["meta"]
    if runtime_meta["runtimeGeneration"] != expected_generation:
        raise ValueError(
            f"runtime generation moved: expected {expected_generation}, "
            f"actual {runtime_meta['runtimeGeneration']}"
        )
    if next_status not in WORK_ORDER_STATES:
        raise ValueError(f"invalid Work Order status {next_status}")
    work = state["workOrders"].get(work_order_id)
    if work is None:
        raise ValueError(f"unknown Work Order {work_order_id}")
    if any(
        sem["workOrderId"] == work_order_id
        for sem in state["activeSemaphores"]
    ):
        raise ValueError("cannot transition Work Order directly while an active semaphore exists")
    item = {k: v for k, v in work.items() if k != "_path"}
    item["status"] = next_status
    item["updatedAt"] = iso(utc_now())
    item["lastActor"] = actor
    write_json(_work_order_path(project, item), item)
    event_type = (
        "WORK_ORDER_DONE"
        if next_status == "LANDED"
        else "WORK_ORDER_READY"
        if next_status == "READY"
        else "WORK_ORDER_UPDATED"
    )
    generation = _bump_generation(
        project,
        runtime_meta,
        event_type=event_type,
        work_execution_id=work_execution_id,
        mission=item["mission"],
        work_order_id=work_order_id,
        payload={"nextStatus": next_status, "actor": actor},
    )
    item["runtimeGeneration"] = generation
    return item


def acquire_semaphore(
    project: pathlib.Path,
    *,
    work_order_id: str,
    semaphore_id: str,
    kind: str,
    worker_identity: str,
    execution_role: str,
    work_execution_id: str,
    expected_generation: int,
    branch: str | None,
    allowed_paths: list[str],
    hours: int,
    authority_id: str | None = None,
    resource_id: str | None = None,
) -> dict[str, Any]:
    state = validate_runtime_state(project)
    runtime_meta = state["meta"]
    if runtime_meta["runtimeGeneration"] != expected_generation:
        raise ValueError(
            f"runtime generation moved: expected {expected_generation}, "
            f"actual {runtime_meta['runtimeGeneration']}"
        )
    work = state["workOrders"].get(work_order_id)
    if work is None:
        raise ValueError(f"unknown Work Order {work_order_id}")
    if work["status"] not in {"READY", "IN_PROGRESS"}:
        raise ValueError(f"Work Order not reservable from status {work['status']}")
    if (
        execution_role != work["requestedRole"]
        and execution_role
        not in {"INTEGRATOR", "TESTER", "REVIEWER", "SECURITY_REVIEWER", "AUDITOR"}
    ):
        raise ValueError(
            f"execution role {execution_role} does not satisfy requested role {work['requestedRole']}"
        )
    now = utc_now()
    product = state["productPrs"][work["parentProductPr"]]
    if kind == "WRITE" and branch == product["branch"]:
        raise ValueError("WRITE semaphore cannot use canonical Product PR branch")
    item = {
        "schemaVersion": 1,
        "semaphoreId": semaphore_id,
        "kind": kind,
        "workOrderId": work_order_id,
        "mission": work["mission"],
        "workerIdentity": worker_identity,
        "executionRole": execution_role,
        "branch": product["branch"] if kind == "INTEGRATION" else branch,
        "productPr": work["parentProductPr"] if kind == "INTEGRATION" else None,
        "authorityId": authority_id,
        "resourceId": resource_id,
        "baseCommit": work["baseCommit"],
        "baseTree": work["baseTree"],
        "allowedPaths": sorted(set(allowed_paths)),
        "createdAt": iso(now),
        "refreshedAt": iso(now),
        "expiresAt": iso(now + dt.timedelta(hours=hours)),
        "runtimeGeneration": expected_generation + 1,
        "status": "ACTIVE",
    }
    validate_semaphore(project, item, state["workOrders"], state["productPrs"])
    for existing in state["activeSemaphores"]:
        if semaphore_collides(item, existing):
            raise ValueError(
                f"requested semaphore collides with {existing['semaphoreId']}"
            )
    work = {k: v for k, v in work.items() if k != "_path"}
    work["status"] = "INTEGRATING" if kind == "INTEGRATION" else "IN_PROGRESS"
    work["assignedWorker"] = worker_identity
    work["executionRole"] = execution_role
    work["activeSemaphoreId"] = semaphore_id
    work["updatedAt"] = iso(now)
    write_json(_work_order_path(project, work), work)
    write_json(_semaphore_path(project, item), item)
    generation = _bump_generation(
        project,
        runtime_meta,
        event_type="SEMAPHORE_ACQUIRED",
        work_execution_id=work_execution_id,
        mission=work["mission"],
        work_order_id=work_order_id,
        payload={
            "semaphoreId": semaphore_id,
            "kind": kind,
            "workerIdentity": worker_identity,
            "executionRole": execution_role,
        },
    )
    item["runtimeGeneration"] = generation
    write_json(_semaphore_path(project, item), item)
    return item


def heartbeat_semaphore(
    project: pathlib.Path,
    *,
    semaphore_id: str,
    worker_identity: str,
    work_execution_id: str,
    expected_generation: int,
    hours: int,
) -> dict[str, Any]:
    state = validate_runtime_state(project)
    runtime_meta = state["meta"]
    if runtime_meta["runtimeGeneration"] != expected_generation:
        raise ValueError(
            f"runtime generation moved: expected {expected_generation}, "
            f"actual {runtime_meta['runtimeGeneration']}"
        )
    matches = [
        item for item in state["activeSemaphores"] if item["semaphoreId"] == semaphore_id
    ]
    if len(matches) != 1:
        raise ValueError(f"active semaphore not found/ambiguous: {semaphore_id}")
    item = {k: v for k, v in matches[0].items() if k != "_path"}
    if item["workerIdentity"] != worker_identity:
        raise ValueError("semaphore heartbeat rejected: worker identity mismatch")
    now = utc_now()
    item["refreshedAt"] = iso(now)
    item["expiresAt"] = iso(now + dt.timedelta(hours=hours))
    generation = _bump_generation(
        project,
        runtime_meta,
        event_type="SEMAPHORE_REFRESHED",
        work_execution_id=work_execution_id,
        mission=item["mission"],
        work_order_id=item["workOrderId"],
        payload={"semaphoreId": semaphore_id},
    )
    item["runtimeGeneration"] = generation
    write_json(_semaphore_path(project, item), item)
    return item


def release_semaphore(
    project: pathlib.Path,
    *,
    semaphore_id: str,
    worker_identity: str,
    work_execution_id: str,
    expected_generation: int,
    next_status: str,
) -> dict[str, Any]:
    state = validate_runtime_state(project)
    runtime_meta = state["meta"]
    if runtime_meta["runtimeGeneration"] != expected_generation:
        raise ValueError(
            f"runtime generation moved: expected {expected_generation}, "
            f"actual {runtime_meta['runtimeGeneration']}"
        )
    matches = [
        item for item in state["activeSemaphores"] if item["semaphoreId"] == semaphore_id
    ]
    if len(matches) != 1:
        raise ValueError(f"active semaphore not found/ambiguous: {semaphore_id}")
    item = matches[0]
    if item["workerIdentity"] != worker_identity:
        raise ValueError("semaphore release rejected: worker identity mismatch")
    work = state["workOrders"][item["workOrderId"]]
    if next_status not in WORK_ORDER_STATES:
        raise ValueError(f"invalid next Work Order status {next_status}")
    now = utc_now()
    clean_sem = {k: v for k, v in item.items() if k != "_path"}
    clean_sem["status"] = "RELEASED"
    clean_sem["refreshedAt"] = iso(now)
    clean_sem["expiresAt"] = iso(now + dt.timedelta(seconds=1))
    clean_work = {k: v for k, v in work.items() if k != "_path"}
    clean_work["status"] = next_status
    clean_work["updatedAt"] = iso(now)
    clean_work.pop("activeSemaphoreId", None)
    write_json(_work_order_path(project, clean_work), clean_work)
    write_json(pathlib.Path(project) / item["_path"], clean_sem)
    generation = _bump_generation(
        project,
        runtime_meta,
        event_type="SEMAPHORE_RELEASED",
        work_execution_id=work_execution_id,
        mission=clean_work["mission"],
        work_order_id=clean_work["workOrderId"],
        payload={"semaphoreId": semaphore_id, "nextStatus": next_status},
    )
    return {
        "runtimeGeneration": generation,
        "workOrder": clean_work,
        "semaphore": clean_sem,
    }


def reap_expired_semaphores(
    project: pathlib.Path,
    *,
    work_execution_id: str,
    expected_generation: int,
) -> dict[str, Any]:
    state = validate_runtime_state(project)
    runtime_meta = state["meta"]
    if runtime_meta["runtimeGeneration"] != expected_generation:
        raise ValueError(
            f"runtime generation moved: expected {expected_generation}, "
            f"actual {runtime_meta['runtimeGeneration']}"
        )
    now = utc_now()
    expired = [
        item
        for item in state["semaphores"]
        if item.get("status") == "ACTIVE" and parse_time(item["expiresAt"]) <= now
    ]
    if not expired:
        return {"runtimeGeneration": expected_generation, "expired": []}
    expired_ids = []
    for item in expired:
        clean_sem = {k: v for k, v in item.items() if k != "_path"}
        clean_sem["status"] = "EXPIRED"
        clean_sem["refreshedAt"] = iso(now)
        clean_sem["expiresAt"] = iso(now + dt.timedelta(seconds=1))
        write_json(pathlib.Path(project) / item["_path"], clean_sem)
        work = state["workOrders"][item["workOrderId"]]
        clean_work = {k: v for k, v in work.items() if k != "_path"}
        if clean_work.get("status") in {"IN_PROGRESS", "INTEGRATING"}:
            clean_work["status"] = "READY"
            clean_work.pop("activeSemaphoreId", None)
            clean_work["updatedAt"] = iso(now)
            write_json(_work_order_path(project, clean_work), clean_work)
        expired_ids.append(item["semaphoreId"])
    generation = _bump_generation(
        project,
        runtime_meta,
        event_type="SEMAPHORE_EXPIRED",
        work_execution_id=work_execution_id,
        mission=None,
        work_order_id=None,
        payload={"semaphoreIds": sorted(expired_ids)},
    )
    return {"runtimeGeneration": generation, "expired": sorted(expired_ids)}


def dispatch_score(
    work: dict[str, Any],
    helper_ready_by_pr: dict[int, int],
    worker_identity: str | None = None,
) -> int:
    type_weight = {
        "INCIDENT": 1200,
        "INTEGRATION": 1000,
        "CI_REPAIR": 850,
        "BLOCKER_REMOVAL": 800,
        "REVIEW": 700,
        "SECURITY_REVIEW": 700,
        "PRODUCT_DEFECT_REPAIR": 600,
        "PRODUCT_TEST": 550,
        "PRODUCT_FEATURE": 500,
        "AUTHORITY_UPDATE": 450,
        "EVIDENCE_FINALIZATION": 400,
        "RELEASE_FINALIZATION": 390,
    }.get(work["type"], 0)
    score = type_weight + int(work.get("priority", 0))
    if work["type"] in BUILD_TYPES and helper_ready_by_pr.get(work["parentProductPr"], 0) >= HELPER_READY_LIMIT:
        return -10_000
    if worker_identity:
        if work["mission"] in WORKER_MISSION_EXPERTISE.get(worker_identity, set()):
            score += 30
        if worker_identity == "H" and work["type"] in {"PRODUCT_DEFECT_REPAIR", "CI_REPAIR", "BLOCKER_REMOVAL"}:
            score += 25
        if worker_identity == "I" and work["type"] in {"REVIEW", "SECURITY_REVIEW", "INTEGRATION"}:
            score += 25
        if worker_identity == "J" and work["type"] in {"REVIEW", "AUTHORITY_UPDATE", "BLOCKER_REMOVAL"}:
            score += 15
    return score


def next_work(project: pathlib.Path, worker_identity: str | None = None) -> dict[str, Any]:
    state = validate_runtime_state(project)
    helper_ready: dict[int, int] = {}
    for work in state["workOrders"].values():
        if work["status"] == "HELPER_READY":
            pr = work["parentProductPr"]
            helper_ready[pr] = helper_ready.get(pr, 0) + 1
    rows = []
    for work in state["workOrders"].values():
        if work["status"] != "READY":
            continue
        row = {k: v for k, v in work.items() if k != "_path"}
        row["dispatchScore"] = dispatch_score(work, helper_ready, worker_identity)
        row["dispatchDisposition"] = (
            "BACKPRESSURE" if row["dispatchScore"] < 0 else "GREEN"
        )
        rows.append(row)
    rows.sort(
        key=lambda item: (-item["dispatchScore"], item["mission"], item["workOrderId"])
    )
    green = [row for row in rows if row["dispatchDisposition"] == "GREEN"]
    return {
        "schemaVersion": 1,
        "runtimeGeneration": state["meta"]["runtimeGeneration"],
        "workerIdentity": worker_identity,
        "greenCount": len(green),
        "backpressureCount": len(rows) - len(green),
        "next": green[0] if green else None,
        "candidates": rows,
    }
