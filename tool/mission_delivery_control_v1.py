#!/usr/bin/env python3
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

HERE = pathlib.Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from mission_delivery_lib import *
from mission_delivery_checks import *
from mission_delivery_live import *

V15_CONTROL_BRANCH = "agent/mission-execution-v15-gold"
V15_CONTROL_PATTERNS = (
    ".github/workflows/mission-*.yml",
    "SOURCE_MANIFEST.sha256",
    "config/mission_v15_*.json",
    "docs/roadmap/missions/DELIVERY_DASHBOARD.md",
    "docs/roadmap/missions/DELIVERY_METRICS.json",
    "docs/roadmap/missions/delivery/records/**",
    "docs/roadmap/missions/MISSION_RUNTIME_CONNECTOR_CAS.md",
    "docs/roadmap/missions/REVIEW_INDEPENDENCE_POLICY.md",
    "docs/roadmap/missions/UNIVERSAL_AUTONOMOUS_WORKER_V15.md",
    "schemas/mission_*.json",
    "tool/mission_delivery_*.py",
    "tool/mission_orchestrator.py",
    "tool/mission_review_carry_forward.py",
    "tool/mission_runtime_*.py",
    "tool/mission_v15_*.py",
)


def validate_control_model(project: pathlib.Path) -> dict[str, Any]:
    """Load delivery policy while grandfathering known non-terminal v1 records.

    PR #78 introduced append-only historical delivery records before every
    producer emitted the normalized top-level ``status`` field. Those records
    are bookkeeping only and cannot satisfy acceptance. Re-validating them as
    normalized terminal records in the ownership/review path contradicted that
    policy and blocked unrelated v1.5 control-plane changes.
    """
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
    statuses = set(model["config"]["statuses"])
    for path in record_files(project, model):
        record = read_json(path)
        status = record.get("status")
        if status in statuses:
            validate_record(record, model, path.relative_to(project).as_posix())
            continue
        # Fail closed unless this is an explicitly non-terminal historical
        # record with its own deliveryState proving no acceptance/main merge.
        delivery = record.get("deliveryState")
        legacy_non_terminal = (
            status is None
            and record.get("recordType") == "MissionDeliveryRecord"
            and isinstance(delivery, dict)
            and delivery.get("accepted") is False
            and delivery.get("mergedToMain") is False
        )
        if not legacy_non_terminal:
            raise DeliveryError(
                f"{path.relative_to(project)}: unsupported non-normalized delivery record"
            )
    return model


def infer_mission(head_branch: str, pr_body: str, model: dict[str, Any]) -> str:
    matches = []
    for mission_id, mission in model["missions"].items():
        claim = mission.get("activeClaim")
        if claim and claim.get("branch") == head_branch:
            matches.append(mission_id)
        if f"`{mission_id}`" in pr_body or mission_id in pr_body:
            matches.append(mission_id)
    unique = sorted(set(matches))
    if len(unique) != 1:
        raise DeliveryError(
            f"cannot infer exactly one mission from branch/PR body: candidates={unique}"
        )
    return unique[0]


def classify_v15_control_plane_paths(changed_paths: Iterable[str]) -> dict[str, Any]:
    """Fail closed for the temporary Mission Execution 1.5 control candidate.

    The v1 delivery ownership checker is mission-centric. PR #100 is the
    explicitly designated control-plane candidate, not a Product PR or a
    Mission Captain branch, so forcing it through product-mission inference
    either fails spuriously or would require broadening a product mission's
    authority. Keep this migration exception branch-bound and path-closed.
    """
    rows = []
    violations = []
    for raw in sorted(set(changed_paths)):
        path = normalize_path(raw)
        authorized = matches_any(path, V15_CONTROL_PATTERNS)
        rows.append(
            {
                "path": path,
                "category": "V15_CONTROL_PLANE" if authorized else "UNDECLARED_PATH",
                "reason": None if authorized else "outside closed Mission Execution 1.5 control-plane scope",
            }
        )
        if not authorized:
            violations.append(path)
    return {
        "mission": None,
        "controlPlane": "MISSION_EXECUTION_V15",
        "changedPathCount": len(rows),
        "authorized": not violations,
        "violations": violations,
        "requiredOwnerReviews": [],
        "coordinationIds": [],
        "paths": rows,
    }


def load_event(path: pathlib.Path | None) -> dict[str, Any]:
    if path is None:
        return {}
    return read_json(path)


def command_validate(project: pathlib.Path) -> None:
    model = validate_control_model(project)
    print(
        f"MISSION_DELIVERY_VALID missions={len(model['missions'])} "
        f"tasks={len(model['tasks'])} records={len(record_files(project, model))}"
    )


def command_ownership(project: pathlib.Path, args: argparse.Namespace) -> None:
    model = validate_control_model(project)
    event = load_event(pathlib.Path(args.event_path) if args.event_path else None)
    mission = args.mission
    head_branch = args.head_branch
    pr_body = ""
    if event:
        pr = event.get("pull_request", {})
        head_branch = head_branch or pr.get("head", {}).get("ref")
        pr_body = pr.get("body") or ""
    changed = git_changed_paths(project, args.base, args.head)
    if head_branch == V15_CONTROL_BRANCH and not mission:
        result = classify_v15_control_plane_paths(changed)
        namespace = []
    else:
        if not mission:
            if not head_branch:
                raise DeliveryError("mission or head branch is required")
            mission = infer_mission(head_branch, pr_body, model)
        result = classify_changed_paths(mission, changed, model)
        namespace = namespace_diagnostics(project, mission, model)
    result.update(
        {
            "base": args.base,
            "head": args.head,
            "headBranch": head_branch,
            "namespaceDiagnostics": namespace,
        }
    )
    if args.output:
        write_json(pathlib.Path(args.output), result)
    print(json.dumps(result, indent=2, sort_keys=True))
    if not result["authorized"]:
        raise DeliveryError(
            "changed-file ownership violations: " + ", ".join(result["violations"])
        )


def command_review_impact(project: pathlib.Path, args: argparse.Namespace) -> None:
    model = validate_control_model(project)
    changed = git_changed_paths(project, args.base, args.head)
    result = review_impact(changed, model)
    result.update({"base": args.base, "head": args.head})
    if args.output:
        write_json(pathlib.Path(args.output), result)
    print(json.dumps(result, indent=2, sort_keys=True))


def command_live_audit(project: pathlib.Path, args: argparse.Namespace) -> None:
    model = validate_control_model(project)
    result = live_audit(args.repo, model, os.environ.get("GITHUB_TOKEN"))
    if args.output:
        write_json(pathlib.Path(args.output), result)
    print(json.dumps(result, indent=2, sort_keys=True))
    if not result["pass"]:
        raise DeliveryError("live audit contains high-severity findings")


def command_record(project: pathlib.Path, args: argparse.Namespace) -> None:
    model = validate_control_model(project)
    target = append_record(
        project=project,
        model=model,
        mission=args.mission,
        task=args.task,
        status=args.status,
        work_id=args.work_id,
        worker=args.worker,
        branch=args.branch,
        pr=args.pr,
        commit=args.commit,
        tree=args.tree,
        evidence=args.evidence or [],
        next_action=args.next_action,
        merged_main_commit=args.merged_main_commit,
    )
    print(f"MISSION_DELIVERY_RECORD_APPENDED path={target.relative_to(project)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("validate")
    work_id_parser = sub.add_parser("work-id")

    ownership_parser = sub.add_parser("ownership")
    ownership_parser.add_argument("--mission")
    ownership_parser.add_argument("--event-path")
    ownership_parser.add_argument("--head-branch")
    ownership_parser.add_argument("--base", required=True)
    ownership_parser.add_argument("--head", required=True)
    ownership_parser.add_argument("--output")

    impact_parser = sub.add_parser("review-impact")
    impact_parser.add_argument("--base", required=True)
    impact_parser.add_argument("--head", required=True)
    impact_parser.add_argument("--output")

    audit_parser = sub.add_parser("live-audit")
    audit_parser.add_argument("--repo", required=True)
    audit_parser.add_argument("--output")

    record_parser = sub.add_parser("record")
    record_parser.add_argument("--mission", required=True)
    record_parser.add_argument("--task", required=True)
    record_parser.add_argument("--status", required=True)
    record_parser.add_argument("--work-id", required=True)
    record_parser.add_argument("--worker", required=True)
    record_parser.add_argument("--branch", required=True)
    record_parser.add_argument("--pr", type=int)
    record_parser.add_argument("--commit")
    record_parser.add_argument("--tree")
    record_parser.add_argument("--evidence", action="append")
    record_parser.add_argument("--next-action", required=True)
    record_parser.add_argument("--merged-main-commit")

    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    try:
        if args.command == "validate":
            command_validate(project)
        elif args.command == "work-id":
            print(execution_id())
        elif args.command == "ownership":
            command_ownership(project, args)
        elif args.command == "review-impact":
            command_review_impact(project, args)
        elif args.command == "live-audit":
            command_live_audit(project, args)
        elif args.command == "record":
            command_record(project, args)
        return 0
    except Exception as exc:
        print(f"MISSION_DELIVERY_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
