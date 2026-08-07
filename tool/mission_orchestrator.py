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

from mission_runtime_model import acquire_semaphore, next_work, release_semaphore, validate_runtime_state


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("doctor")
    nxt = sub.add_parser("next-work")
    nxt.add_argument("--worker")
    reserve = sub.add_parser("reserve")
    reserve.add_argument("--work-order", required=True)
    reserve.add_argument("--semaphore-id", required=True)
    reserve.add_argument("--kind", required=True, choices=["WRITE", "INTEGRATION", "AUTHORITY", "RELEASE"])
    reserve.add_argument("--worker", required=True)
    reserve.add_argument("--role", required=True)
    reserve.add_argument("--work-id", required=True)
    reserve.add_argument("--expected-generation", type=int, required=True)
    reserve.add_argument("--branch")
    reserve.add_argument("--allowed-path", action="append", default=[])
    reserve.add_argument("--authority-id")
    reserve.add_argument("--resource-id")
    reserve.add_argument("--hours", type=int, default=4)
    release = sub.add_parser("release")
    release.add_argument("--semaphore-id", required=True)
    release.add_argument("--worker", required=True)
    release.add_argument("--work-id", required=True)
    release.add_argument("--expected-generation", type=int, required=True)
    release.add_argument("--next-status", required=True)
    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    try:
        if args.command == "doctor":
            state = validate_runtime_state(project)
            print(json.dumps({"runtimeGeneration": state["meta"]["runtimeGeneration"], "productPrCount": len(state["productPrs"]), "workOrderCount": len(state["workOrders"]), "activeSemaphoreCount": len(state["activeSemaphores"])}, indent=2, sort_keys=True))
        elif args.command == "next-work":
            print(json.dumps(next_work(project, args.worker), indent=2, sort_keys=True))
        elif args.command == "reserve":
            result = acquire_semaphore(project, work_order_id=args.work_order, semaphore_id=args.semaphore_id, kind=args.kind, worker_identity=args.worker, execution_role=args.role, work_execution_id=args.work_id, expected_generation=args.expected_generation, branch=args.branch, allowed_paths=args.allowed_path, hours=args.hours, authority_id=args.authority_id, resource_id=args.resource_id)
            print(json.dumps(result, indent=2, sort_keys=True))
        elif args.command == "release":
            result = release_semaphore(project, semaphore_id=args.semaphore_id, worker_identity=args.worker, work_execution_id=args.work_id, expected_generation=args.expected_generation, next_status=args.next_status)
            print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except Exception as exc:
        print(f"MISSION_ORCHESTRATOR_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
