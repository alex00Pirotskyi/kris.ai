#!/usr/bin/env python3
"""Thin Mission Execution 1.5 orchestration CLI.

All state validation lives in the existing delivery/runtime libraries plus
``mission_runtime_model``. This command is deliberately a facade, not another
control stack.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

from mission_runtime_model import (
    acquire_semaphore,
    create_work_order,
    heartbeat_semaphore,
    next_work,
    reap_expired_semaphores,
    release_semaphore,
    transition_work_order,
    validate_runtime_state,
)


def read_spec(path: str) -> dict:
    value = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("Work Order spec must be a JSON object")
    return value


def dump(value: object) -> None:
    print(json.dumps(value, indent=2, sort_keys=True))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("doctor")

    nxt = sub.add_parser("next-work")
    nxt.add_argument("--worker")

    create = sub.add_parser("work-create")
    create.add_argument("--spec", required=True)
    create.add_argument("--work-id", required=True)
    create.add_argument("--expected-generation", type=int, required=True)

    delegate = sub.add_parser("delegate")
    delegate.add_argument("--parent-work-order", required=True)
    delegate.add_argument("--spec", required=True)
    delegate.add_argument("--work-id", required=True)
    delegate.add_argument("--expected-generation", type=int, required=True)

    transition = sub.add_parser("transition")
    transition.add_argument("--work-order", required=True)
    transition.add_argument("--next-status", required=True)
    transition.add_argument("--actor", required=True)
    transition.add_argument("--work-id", required=True)
    transition.add_argument("--expected-generation", type=int, required=True)

    reserve = sub.add_parser("reserve")
    reserve.add_argument("--work-order", required=True)
    reserve.add_argument("--semaphore-id", required=True)
    reserve.add_argument(
        "--kind",
        required=True,
        choices=["WRITE", "INTEGRATION", "AUTHORITY", "RELEASE"],
    )
    reserve.add_argument("--worker", required=True)
    reserve.add_argument("--role", required=True)
    reserve.add_argument("--work-id", required=True)
    reserve.add_argument("--expected-generation", type=int, required=True)
    reserve.add_argument("--branch")
    reserve.add_argument("--allowed-path", action="append", default=[])
    reserve.add_argument("--authority-id")
    reserve.add_argument("--resource-id")
    reserve.add_argument("--hours", type=int, default=4)

    heartbeat = sub.add_parser("heartbeat")
    heartbeat.add_argument("--semaphore-id", required=True)
    heartbeat.add_argument("--worker", required=True)
    heartbeat.add_argument("--work-id", required=True)
    heartbeat.add_argument("--expected-generation", type=int, required=True)
    heartbeat.add_argument("--hours", type=int, default=4)

    release = sub.add_parser("release")
    release.add_argument("--semaphore-id", required=True)
    release.add_argument("--worker", required=True)
    release.add_argument("--work-id", required=True)
    release.add_argument("--expected-generation", type=int, required=True)
    release.add_argument("--next-status", required=True)

    reap = sub.add_parser("reap")
    reap.add_argument("--work-id", required=True)
    reap.add_argument("--expected-generation", type=int, required=True)

    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    try:
        if args.command == "doctor":
            state = validate_runtime_state(project)
            dump(
                {
                    "runtimeGeneration": state["meta"]["runtimeGeneration"],
                    "claimCount": len(state["claims"]),
                    "productPrCount": len(state["productPrs"]),
                    "workOrderCount": len(state["workOrders"]),
                    "activeSemaphoreCount": len(state["activeSemaphores"]),
                }
            )
        elif args.command == "next-work":
            dump(next_work(project, args.worker))
        elif args.command == "work-create":
            dump(
                create_work_order(
                    project,
                    work_order=read_spec(args.spec),
                    work_execution_id=args.work_id,
                    expected_generation=args.expected_generation,
                )
            )
        elif args.command == "delegate":
            spec = read_spec(args.spec)
            spec["parentWorkOrderId"] = args.parent_work_order
            dump(
                create_work_order(
                    project,
                    work_order=spec,
                    work_execution_id=args.work_id,
                    expected_generation=args.expected_generation,
                )
            )
        elif args.command == "transition":
            dump(
                transition_work_order(
                    project,
                    work_order_id=args.work_order,
                    next_status=args.next_status,
                    work_execution_id=args.work_id,
                    expected_generation=args.expected_generation,
                    actor=args.actor,
                )
            )
        elif args.command == "reserve":
            dump(
                acquire_semaphore(
                    project,
                    work_order_id=args.work_order,
                    semaphore_id=args.semaphore_id,
                    kind=args.kind,
                    worker_identity=args.worker,
                    execution_role=args.role,
                    work_execution_id=args.work_id,
                    expected_generation=args.expected_generation,
                    branch=args.branch,
                    allowed_paths=args.allowed_path,
                    hours=args.hours,
                    authority_id=args.authority_id,
                    resource_id=args.resource_id,
                )
            )
        elif args.command == "heartbeat":
            dump(
                heartbeat_semaphore(
                    project,
                    semaphore_id=args.semaphore_id,
                    worker_identity=args.worker,
                    work_execution_id=args.work_id,
                    expected_generation=args.expected_generation,
                    hours=args.hours,
                )
            )
        elif args.command == "release":
            dump(
                release_semaphore(
                    project,
                    semaphore_id=args.semaphore_id,
                    worker_identity=args.worker,
                    work_execution_id=args.work_id,
                    expected_generation=args.expected_generation,
                    next_status=args.next_status,
                )
            )
        elif args.command == "reap":
            dump(
                reap_expired_semaphores(
                    project,
                    work_execution_id=args.work_id,
                    expected_generation=args.expected_generation,
                )
            )
        return 0
    except Exception as exc:
        print(f"MISSION_ORCHESTRATOR_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
