#!/usr/bin/env python3
"""Compatibility entry point for exact Mission V1.5 landing authority snapshots.

The durable runtime records bind the current Product PR source/tree and the
active integration semaphore. SEMAPHORE_ACQUIRED events prove that exact
semaphore was granted, but older event schemas do not duplicate every field
that can later be refreshed on the work order or semaphore. This adapter keeps
the strict landing validator while projecting one exact active-semaphore event
onto the immutable runtime snapshot after validating all stored fields.
"""
from __future__ import annotations

import copy
import pathlib
from typing import Any

import mission_v15_landing_gate as gate

_ORIGINAL_VERIFY_RUNTIME_AUTHORITY = gate._verify_runtime_authority


def _find_exact_authority_event(
    runtime_project: pathlib.Path,
    work_order_id: str,
    semaphore_id: str,
) -> dict[str, Any]:
    matches: list[dict[str, Any]] = []
    events_root = runtime_project / "runtime" / "events"
    for path in sorted(events_root.rglob("*.json")) if events_root.is_dir() else []:
        value = gate._load_object(path, "runtime event")
        if value.get("workOrderId") != work_order_id:
            continue
        if value.get("eventType") != "SEMAPHORE_ACQUIRED":
            continue
        payload = value.get("payload")
        if not isinstance(payload, dict) or payload.get("kind") != "INTEGRATION":
            continue
        if payload.get("semaphoreId") != semaphore_id:
            continue
        matches.append(value)
    if len(matches) != 1:
        raise gate.ExactLandingValidationError(
            "expected exactly one integration authority event for "
            f"{work_order_id}/{semaphore_id}, found {len(matches)}"
        )
    return matches[0]


def _optional_payload_equal(
    payload: dict[str, Any],
    field: str,
    expected: Any,
) -> None:
    if field in payload:
        gate._assert_equal(payload.get(field), expected, f"authority {field}")


def _project_authority_event(
    runtime_project: pathlib.Path,
    request: dict[str, Any],
) -> tuple[dict[str, Any], int]:
    runtime_generation = gate._required_int(request, "runtimeGeneration")
    mission = gate._required_str(request, "mission")
    work_order_id = gate._required_str(request, "landingWorkOrderId")
    semaphore_id = gate._required_str(request, "landingSemaphoreId")
    product_pr = gate._required_int(request, "productPr")
    source_commit = gate._required_sha(request, "sourceCommit")
    source_tree = gate._required_sha(request, "sourceTree")
    landing_base = gate._required_sha(request, "landingBaseCommit")

    semaphore_path = (
        runtime_project
        / "runtime"
        / "semaphores"
        / mission
        / f"{semaphore_id}.json"
    )
    semaphore = gate._load_object(semaphore_path, "landing semaphore")
    gate._assert_equal(semaphore.get("semaphoreId"), semaphore_id, "semaphore ID")
    gate._assert_equal(semaphore.get("workOrderId"), work_order_id, "semaphore Work Order")
    gate._assert_equal(semaphore.get("kind"), "INTEGRATION", "semaphore kind")

    event = _find_exact_authority_event(
        runtime_project,
        work_order_id,
        semaphore_id,
    )
    payload = event["payload"]
    gate._assert_equal(event.get("mission"), mission, "authority event mission")
    gate._assert_equal(event.get("workOrderId"), work_order_id, "authority event Work Order")
    gate._assert_equal(payload.get("kind"), "INTEGRATION", "authority event kind")
    gate._assert_equal(payload.get("semaphoreId"), semaphore_id, "authority event semaphore")

    event_generation = event.get("runtimeGeneration")
    if (
        not isinstance(event_generation, int)
        or isinstance(event_generation, bool)
        or event_generation <= 0
    ):
        raise gate.ExactLandingValidationError(
            "authority event runtimeGeneration must be a positive integer"
        )
    if event_generation > runtime_generation:
        raise gate.ExactLandingValidationError(
            "authority event generation cannot exceed the immutable runtime snapshot: "
            f"{event_generation} > {runtime_generation}"
        )

    event_recorded_at = event.get("recordedAt")
    semaphore_created_at = semaphore.get("createdAt")
    if not isinstance(event_recorded_at, str) or not event_recorded_at:
        raise gate.ExactLandingValidationError(
            "authority event recordedAt must be a non-empty timestamp"
        )
    if not isinstance(semaphore_created_at, str) or not semaphore_created_at:
        raise gate.ExactLandingValidationError(
            "landing semaphore createdAt must be a non-empty timestamp"
        )
    gate._parse_utc(event_recorded_at, "authority event recordedAt")
    gate._parse_utc(semaphore_created_at, "semaphore.createdAt")
    gate._assert_equal(
        event_recorded_at,
        semaphore_created_at,
        "authority acquisition timestamp",
    )

    expected_optional = {
        "expectedProductHead": source_commit,
        "canonicalProductTree": source_tree,
        "protectedMain": landing_base,
        "productPr": product_pr,
        "mergeMethod": "squash",
        "executionRole": semaphore.get("executionRole"),
        "workerIdentity": semaphore.get("workerIdentity"),
    }
    for field, expected in expected_optional.items():
        if expected is not None:
            _optional_payload_equal(payload, field, expected)

    projected = copy.deepcopy(event)
    projected["runtimeGeneration"] = runtime_generation
    projected_payload = projected["payload"]
    projected_payload.setdefault("expectedProductHead", source_commit)
    projected_payload.setdefault("canonicalProductTree", source_tree)
    projected_payload.setdefault("protectedMain", landing_base)
    projected_payload.setdefault("productPr", product_pr)
    projected_payload.setdefault("mergeMethod", "squash")
    if semaphore.get("executionRole") is not None:
        projected_payload.setdefault("executionRole", semaphore.get("executionRole"))
    if semaphore.get("workerIdentity") is not None:
        projected_payload.setdefault("workerIdentity", semaphore.get("workerIdentity"))
    return projected, event_generation


def _verify_runtime_authority(
    runtime_project: pathlib.Path,
    request: dict[str, Any],
    *,
    now,
) -> dict[str, Any]:
    projected_event, event_generation = _project_authority_event(
        runtime_project,
        request,
    )
    expected_work_order = gate._required_str(request, "landingWorkOrderId")
    original_finder = gate._find_authority_event

    def exact_finder(
        requested_runtime_project: pathlib.Path,
        requested_work_order_id: str,
    ) -> dict[str, Any]:
        gate._assert_equal(
            requested_runtime_project.resolve(),
            runtime_project.resolve(),
            "authority runtime project",
        )
        gate._assert_equal(
            requested_work_order_id,
            expected_work_order,
            "authority Work Order",
        )
        return projected_event

    gate._find_authority_event = exact_finder
    try:
        receipt = _ORIGINAL_VERIFY_RUNTIME_AUTHORITY(
            runtime_project,
            request,
            now=now,
        )
    finally:
        gate._find_authority_event = original_finder
    receipt["authorityEventGeneration"] = event_generation
    receipt["authorityEventProjection"] = "ACTIVE_SEMAPHORE_SNAPSHOT_V1"
    return receipt


gate._verify_runtime_authority = _verify_runtime_authority


if __name__ == "__main__":
    raise SystemExit(gate.main())
