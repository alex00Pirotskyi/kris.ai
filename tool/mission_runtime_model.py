#!/usr/bin/env python3
"""Mission Execution 1.5 mutable runtime model.

This is a library used by ``mission_orchestrator.py``. The existing
``mission_runtime_control.py`` remains the compatibility/runtime authority
surface for v1 helper leases; this module adds Work Orders and scoped
semaphores without duplicating roadmap/delivery validation.
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
WORK_ORDERS = RUNTIME / "work-orders"
SEMAPHORES = RUNTIME / "semaphores"
EVENTS = RUNTIME / "events"
PRODUCT_PRS = RUNTIME / "integration/product-prs"

WORK_ORDER_STATES = {"CREATED", "READY", "RESERVED", "IN_PROGRESS", "HELPER_READY", "INTEGRATING", "VALIDATING", "REVIEW", "LANDED", "BLOCKED", "SUPERSEDED", "CANCELLED"}
WORK_ORDER_TYPES = {"PRODUCT_FEATURE", "PRODUCT_DEFECT_REPAIR", "PRODUCT_TEST", "CI_REPAIR", "INTEGRATION", "REVIEW", "SECURITY_REVIEW", "AUTHORITY_UPDATE", "BLOCKER_REMOVAL", "EVIDENCE_FINALIZATION", "RELEASE_FINALIZATION", "INCIDENT"}
ROLES = {"CAPTAIN", "BUILDER", "TESTER", "DEFECT_HUNTER", "CI_REPAIR", "REVIEWER", "SECURITY_REVIEWER", "INTEGRATOR", "AUTHORITY_OWNER", "AUDITOR", "RELEASE_FINALIZER", "INCIDENT_RESPONDER"}
SEMAPHORE_KINDS = {"WRITE", "INTEGRATION", "AUTHORITY", "RELEASE"}
SEMAPHORE_STATES = {"ACTIVE", "RELEASED", "EXPIRED"}
DEPENDENCY_LEVELS = {"IMPLEMENTATION", "INTEGRATION", "LANDING", "ACCEPTANCE", "CERTIFICATION", "RELEASE"}
BUILD_TYPES = {"PRODUCT_FEATURE", "PRODUCT_DEFECT_REPAIR", "PRODUCT_TEST"}
HELPER_READY_LIMIT = 2


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def iso(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_time(value: str) -> dt.datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ValueError(f"runtime timestamp must be UTC RFC3339: {value!r}")
    return dt.datetime.fromisoformat(value[:-1] + "+00:00").astimezone(dt.timezone.utc)


def read_json(path: pathlib.Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")


def meta(project: pathlib.Path) -> dict[str, Any]:
    path = project / META
    if not path.is_file():
        raise ValueError(f"Mission Execution 1.5 runtime missing {META}")
    value = read_json(path)
    if value.get("schemaVersion") != 1 or not isinstance(value.get("runtimeGeneration"), int):
        raise ValueError("invalid runtime meta")
    return value


def work_order_files(project: pathlib.Path) -> list[pathlib.Path]:
    root = project / WORK_ORDERS
    return sorted(root.glob("**/*.json")) if root.is_dir() else []


def semaphore_files(project: pathlib.Path) -> list[pathlib.Path]:
    root = project / SEMAPHORES
    return sorted(root.glob("**/*.json")) if root.is_dir() else []


def product_pr_files(project: pathlib.Path) -> list[pathlib.Path]:
    root = project / PRODUCT_PRS
    return sorted(root.glob("*.json")) if root.is_dir() else []


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
        if not isinstance(pr, int) or pr <= 0 or pr in result:
            raise ValueError(f"invalid/duplicate canonical Product PR: {path}")
        if not isinstance(task, str) or task in tasks:
            raise ValueError(f"duplicate canonical Product PR task mapping: {task}")
        tasks.add(task)
        item["_path"] = path.relative_to(project).as_posix()
        result[pr] = item
    return result


def _dependency_satisfied(requirement: dict[str, Any], latest: dict[str, dict[str, Any]]) -> bool:
    task = requirement["task"]
    level = requirement["level"]
    record = latest.get(task, {})
    status = record.get("status", "NOT_EVALUATED")
    landing = record.get("sourceLanding", "NOT_LANDED")
    if level == "IMPLEMENTATION":
        return bool(record) and (landing in {"HELPER", "PRODUCT_PR", "LANDED_MAIN"} or status not in {"NOT_EVALUATED", "LEGACY_OTHER"})
    if level == "INTEGRATION":
        return landing in {"PRODUCT_PR", "LANDED_MAIN"}
    if level == "LANDING":
        return landing == "LANDED_MAIN"
    if level in {"ACCEPTANCE", "CERTIFICATION"}:
        return status in ACCEPTED
    if level == "RELEASE":
        return status in ACCEPTED and record.get("releaseSupport") == "SUPPORTED"
    raise ValueError(f"unsupported dependency level {level}")


def validate_work_order(project: pathlib.Path, item: dict[str, Any], model: dict[str, Any], product_prs: dict[int, dict[str, Any]], latest: dict[str, dict[str, Any]]) -> None:
    required = {"schemaVersion", "workOrderId", "mission", "roadmapTask", "parentProductPr", "priority", "type", "objective", "requestedRole", "allowedPaths", "baseCommit", "baseTree", "dependencyRequirements", "requiredTests", "maxChildWorkOrders", "status", "createdBy", "createdAt"}
    missing = sorted(required - set(item))
    if missing:
        raise ValueError(f"Work Order missing fields: {missing}")
    if item["schemaVersion"] != 1:
        raise ValueError("Work Order schemaVersion must be 1")
    mission = item["mission"]
    task = item["roadmapTask"]
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
    for requirement in item.get("dependencyRequirements") or []:
        if set(requirement) != {"task", "level"}:
            raise ValueError(f"invalid dependency requirement: {requirement}")
        if requirement["task"] not in model["tasks"]:
            raise ValueError(f"unknown Work Order dependency {requirement['task']}")
        if requirement["level"] not in DEPENDENCY_LEVELS:
            raise ValueError(f"unsupported dependency level {requirement['level']}")
        if item["status"] in {"READY", "RESERVED", "IN_PROGRESS", "HELPER_READY", "INTEGRATING", "VALIDATING", "REVIEW"} and not _dependency_satisfied(requirement, latest):
            raise ValueError(f"Work Order {item['workOrderId']} dependency not satisfied: {requirement['task']}@{requirement['level']}")
    parse_time(item["createdAt"])


def _active(item: dict[str, Any], now: dt.datetime) -> bool:
    return item.get("status") == "ACTIVE" and parse_time(item["expiresAt"]) > now


def semaphore_collides(left: dict[str, Any], right: dict[str, Any]) -> bool:
    if left["kind"] == "WRITE" and right["kind"] == "WRITE":
        return any(prefixes_overlap(a, b) for a in left.get("allowedPaths", []) for b in right.get("allowedPaths", []))
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


def validate_semaphore(project: pathlib.Path, item: dict[str, Any], work_orders: dict[str, dict[str, Any]]) -> None:
    required = {"schemaVersion", "semaphoreId", "kind", "workOrderId", "mission", "workerIdentity", "executionRole", "baseCommit", "baseTree", "allowedPaths", "createdAt", "refreshedAt", "expiresAt", "runtimeGeneration", "status"}
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
    if item["kind"] == "WRITE":
        branch = item.get("branch")
        if not isinstance(branch, str) or not branch:
            raise ValueError("WRITE semaphore requires branch")
        for path in item.get("allowedPaths") or []:
            if not any(pattern_within(path, allowed) for allowed in work["allowedPaths"]):
                raise ValueError(f"WRITE semaphore path exceeds Work Order scope: {path}")
    if item["kind"] == "INTEGRATION" and item.get("productPr") != work["parentProductPr"]:
        raise ValueError("INTEGRATION semaphore must bind Work Order canonical Product PR")
    if item["kind"] == "AUTHORITY" and not item.get("authorityId"):
        raise ValueError("AUTHORITY semaphore requires authorityId")
    if item["kind"] == "RELEASE" and not item.get("resourceId"):
        raise ValueError("RELEASE semaphore requires resourceId")
    created, refreshed, expires = map(parse_time, (item["createdAt"], item["refreshedAt"], item["expiresAt"]))
    if refreshed < created or expires <= refreshed:
        raise ValueError("semaphore timestamp ordering invalid")


def load_semaphores(project: pathlib.Path, work_orders: dict[str, dict[str, Any]], now: dt.datetime | None = None) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    now = now or utc_now()
    all_items: list[dict[str, Any]] = []
    active: list[dict[str, Any]] = []
    branches: dict[str, str] = {}
    for path in semaphore_files(project):
        item = read_json(path)
        item["_path"] = path.relative_to(project).as_posix()
        validate_semaphore(project, item, work_orders)
        all_items.append(item)
        if _active(item, now):
            if item["kind"] == "WRITE":
                branch = item["branch"]
                if branch in branches:
                    raise ValueError(f"active WRITE branch reused: {branch} ({branches[branch]}, {item['semaphoreId']})")
                branches[branch] = item["semaphoreId"]
            active.append(item)
    for index, left in enumerate(active):
        for right in active[index + 1:]:
            if semaphore_collides(left, right):
                raise ValueError(f"active semaphore collision: {left['semaphoreId']} vs {right['semaphoreId']}")
    return all_items, active


def validate_runtime_state(project: pathlib.Path) -> dict[str, Any]:
    runtime_meta = meta(project)
    model = load_model(project)
    latest = load_latest_records(project, model)
    products = load_product_prs(project)
    work_orders = load_work_orders(project)
    for item in work_orders.values():
        validate_work_order(project, item, model, products, latest)
    all_sems, active = load_semaphores(project, work_orders)
    for item in active:
        if item["runtimeGeneration"] > runtime_meta["runtimeGeneration"]:
            raise ValueError("semaphore generation is ahead of runtime meta")
    return {"meta": runtime_meta, "model": model, "productPrs": products, "workOrders": work_orders, "semaphores": all_sems, "activeSemaphores": active}


def _work_order_path(project: pathlib.Path, work: dict[str, Any]) -> pathlib.Path:
    return project / WORK_ORDERS / work["mission"] / f"{work['workOrderId']}.json"


def _semaphore_path(project: pathlib.Path, item: dict[str, Any]) -> pathlib.Path:
    return project / SEMAPHORES / item["mission"] / f"{item['semaphoreId']}.json"


def _event_path(project: pathlib.Path, event: dict[str, Any]) -> pathlib.Path:
    return project / EVENTS / event["recordedAt"][:10] / f"{event['eventId']}.json"


def _bump_generation(project: pathlib.Path, current_meta: dict[str, Any], *, event_type: str, work_execution_id: str, mission: str | None, work_order_id: str | None, payload: dict[str, Any]) -> int:
    generation = current_meta["runtimeGeneration"] + 1
    current_meta["runtimeGeneration"] = generation
    current_meta["updatedAt"] = iso(utc_now())
    write_json(project / META, current_meta)
    event = {"schemaVersion": 1, "eventId": f"EVT-{generation:08d}-{event_type}", "eventType": event_type, "runtimeGeneration": generation, "recordedAt": iso(utc_now()), "workExecutionId": work_execution_id, "workOrderId": work_order_id, "mission": mission, "payload": payload}
    write_json(_event_path(project, event), event)
    return generation


def acquire_semaphore(project: pathlib.Path, *, work_order_id: str, semaphore_id: str, kind: str, worker_identity: str, execution_role: str, work_execution_id: str, expected_generation: int, branch: str | None, allowed_paths: list[str], hours: int, authority_id: str | None = None, resource_id: str | None = None) -> dict[str, Any]:
    state = validate_runtime_state(project)
    runtime_meta = state["meta"]
    if runtime_meta["runtimeGeneration"] != expected_generation:
        raise ValueError(f"runtime generation moved: expected {expected_generation}, actual {runtime_meta['runtimeGeneration']}")
    work = state["workOrders"].get(work_order_id)
    if work is None:
        raise ValueError(f"unknown Work Order {work_order_id}")
    if work["status"] not in {"READY", "IN_PROGRESS"}:
        raise ValueError(f"Work Order not reservable from status {work['status']}")
    if execution_role != work["requestedRole"] and execution_role not in {"INTEGRATOR", "TESTER", "REVIEWER", "SECURITY_REVIEWER", "AUDITOR"}:
        raise ValueError(f"execution role {execution_role} does not satisfy requested role {work['requestedRole']}")
    now = utc_now()
    item = {"schemaVersion": 1, "semaphoreId": semaphore_id, "kind": kind, "workOrderId": work_order_id, "mission": work["mission"], "workerIdentity": worker_identity, "executionRole": execution_role, "branch": branch, "productPr": work["parentProductPr"] if kind == "INTEGRATION" else None, "authorityId": authority_id, "resourceId": resource_id, "baseCommit": work["baseCommit"], "baseTree": work["baseTree"], "allowedPaths": sorted(set(allowed_paths)), "createdAt": iso(now), "refreshedAt": iso(now), "expiresAt": iso(now + dt.timedelta(hours=hours)), "runtimeGeneration": expected_generation + 1, "status": "ACTIVE"}
    validate_semaphore(project, item, state["workOrders"])
    for existing in state["activeSemaphores"]:
        if semaphore_collides(item, existing):
            raise ValueError(f"requested semaphore collides with {existing['semaphoreId']}")
    work["status"] = "IN_PROGRESS"
    work["assignedWorker"] = worker_identity
    work["executionRole"] = execution_role
    work["activeSemaphoreId"] = semaphore_id
    write_json(_work_order_path(project, work), {k: v for k, v in work.items() if k != "_path"})
    write_json(_semaphore_path(project, item), item)
    generation = _bump_generation(project, runtime_meta, event_type="SEMAPHORE_ACQUIRED", work_execution_id=work_execution_id, mission=work["mission"], work_order_id=work_order_id, payload={"semaphoreId": semaphore_id, "kind": kind, "workerIdentity": worker_identity})
    item["runtimeGeneration"] = generation
    write_json(_semaphore_path(project, item), item)
    return item


def release_semaphore(project: pathlib.Path, *, semaphore_id: str, worker_identity: str, work_execution_id: str, expected_generation: int, next_status: str) -> dict[str, Any]:
    state = validate_runtime_state(project)
    runtime_meta = state["meta"]
    if runtime_meta["runtimeGeneration"] != expected_generation:
        raise ValueError(f"runtime generation moved: expected {expected_generation}, actual {runtime_meta['runtimeGeneration']}")
    matches = [item for item in state["activeSemaphores"] if item["semaphoreId"] == semaphore_id]
    if len(matches) != 1:
        raise ValueError(f"active semaphore not found/ambiguous: {semaphore_id}")
    item = matches[0]
    if item["workerIdentity"] != worker_identity:
        raise ValueError("semaphore release rejected: worker identity mismatch")
    work = state["workOrders"][item["workOrderId"]]
    if next_status not in WORK_ORDER_STATES:
        raise ValueError(f"invalid next Work Order status {next_status}")
    now = utc_now()
    item["status"] = "RELEASED"
    item["refreshedAt"] = iso(now)
    item["expiresAt"] = iso(now + dt.timedelta(seconds=1))
    work["status"] = next_status
    work.pop("activeSemaphoreId", None)
    write_json(_work_order_path(project, work), {k: v for k, v in work.items() if k != "_path"})
    write_json(pathlib.Path(project) / item["_path"], {k: v for k, v in item.items() if k != "_path"})
    generation = _bump_generation(project, runtime_meta, event_type="SEMAPHORE_RELEASED", work_execution_id=work_execution_id, mission=work["mission"], work_order_id=work["workOrderId"], payload={"semaphoreId": semaphore_id, "nextStatus": next_status})
    return {"runtimeGeneration": generation, "workOrder": work, "semaphore": item}


def dispatch_score(work: dict[str, Any], helper_ready_by_pr: dict[int, int]) -> int:
    type_weight = {"INTEGRATION": 1000, "CI_REPAIR": 850, "BLOCKER_REMOVAL": 800, "REVIEW": 700, "SECURITY_REVIEW": 700, "PRODUCT_DEFECT_REPAIR": 600, "PRODUCT_TEST": 550, "PRODUCT_FEATURE": 500, "AUTHORITY_UPDATE": 450, "EVIDENCE_FINALIZATION": 400, "RELEASE_FINALIZATION": 390, "INCIDENT": 1200}.get(work["type"], 0)
    score = type_weight + int(work.get("priority", 0))
    if work["type"] in BUILD_TYPES and helper_ready_by_pr.get(work["parentProductPr"], 0) >= HELPER_READY_LIMIT:
        return -10_000
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
        row["dispatchScore"] = dispatch_score(work, helper_ready)
        row["dispatchDisposition"] = "BACKPRESSURE" if row["dispatchScore"] < 0 else "GREEN"
        rows.append(row)
    rows.sort(key=lambda item: (-item["dispatchScore"], item["mission"], item["workOrderId"]))
    green = [row for row in rows if row["dispatchDisposition"] == "GREEN"]
    return {"schemaVersion": 1, "runtimeGeneration": state["meta"]["runtimeGeneration"], "workerIdentity": worker_identity, "greenCount": len(green), "backpressureCount": len(rows) - len(green), "next": green[0] if green else None, "candidates": rows}
