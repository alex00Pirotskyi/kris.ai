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

from mission_delivery_lib import *
def namespace_diagnostics(
    project: pathlib.Path,
    mission: str,
    model: dict[str, Any],
    branch_tree_paths: Iterable[str] | None = None,
) -> list[dict[str, Any]]:
    branch_tree_paths = list(branch_tree_paths or [])
    diagnostics = []
    for item in model["config"]["missionPathPolicies"][mission].get("namespaces", []):
        pattern = item["pattern"]
        mode = item["mode"]
        local_matches = [
            path.relative_to(project).as_posix()
            for path in project.rglob("*")
            if path.is_file() and path_matches(path.relative_to(project).as_posix(), pattern)
        ]
        remote_matches = [path for path in branch_tree_paths if path_matches(path, pattern)]
        match_count = len(set(local_matches + remote_matches))
        state = "PASS"
        if mode == "EXISTING_ON_CLAIM_BRANCH" and match_count == 0:
            state = "FAIL"
        elif mode == "RESERVED_FUTURE_NAMESPACE" and match_count == 0:
            state = "RESERVED"
        diagnostics.append(
            {
                "pattern": pattern,
                "mode": mode,
                "matchCount": match_count,
                "state": state,
            }
        )
    return diagnostics


def mission_allowed_patterns(mission: str, model: dict[str, Any]) -> dict[str, list[str]]:
    config = model["config"]
    owned = list(config["missionPathPolicies"][mission]["owned"])
    shared = []
    coordination_ids = []
    for grant in config.get("sharedPathGrants", []):
        if grant.get("requestingMission") == mission:
            shared.extend(grant.get("patterns", []))
            coordination_ids.append(grant["coordinationId"])
    generated = list(config.get("commonGeneratedPaths", []))
    return {
        "owned": sorted(set(owned)),
        "shared": sorted(set(shared)),
        "generated": sorted(set(generated)),
        "coordinationIds": sorted(set(coordination_ids)),
    }


def classify_changed_paths(
    mission: str,
    changed_paths: Iterable[str],
    model: dict[str, Any],
) -> dict[str, Any]:
    if mission not in model["missions"]:
        raise DeliveryError(f"unknown mission {mission}")
    allowed = mission_allowed_patterns(mission, model)
    authorities = model["config"].get("sharedAuthorities", [])
    other_owned = []
    for other, policy in model["config"]["missionPathPolicies"].items():
        if other != mission:
            other_owned.extend((other, pattern) for pattern in policy.get("owned", []))

    rows = []
    violations = []
    owner_reviews = set()
    for raw in sorted(set(changed_paths)):
        path = normalize_path(raw)
        category = None
        reason = None
        if matches_any(path, allowed["owned"]):
            category = "MISSION_OWNED"
        elif matches_any(path, allowed["shared"]):
            category = "APPROVED_SHARED"
            for grant in model["config"].get("sharedPathGrants", []):
                if (
                    grant.get("requestingMission") == mission
                    and matches_any(path, grant.get("patterns", []))
                    and grant.get("ownerReviewRequired")
                ):
                    owner_reviews.add(grant["ownerMission"])
        elif matches_any(path, allowed["generated"]):
            category = "GENERATOR_OWNED"
        else:
            foreign = [
                {"mission": other, "pattern": pattern}
                for other, pattern in other_owned
                if path_matches(path, pattern)
            ]
            shared_authority = [
                {"ownerMission": item["ownerMission"], "authorityId": item["authorityId"]}
                for item in authorities
                if matches_any(path, item.get("patterns", []))
            ]
            if shared_authority:
                category = "UNGRANTED_SHARED_AUTHORITY"
                reason = shared_authority
            elif foreign:
                category = "OTHER_MISSION_PATH"
                reason = foreign
            else:
                category = "UNDECLARED_PATH"
                reason = "not covered by mission policy, shared grant, or generator output"
            violations.append(path)
        rows.append({"path": path, "category": category, "reason": reason})
    return {
        "mission": mission,
        "changedPathCount": len(rows),
        "authorized": not violations,
        "violations": violations,
        "requiredOwnerReviews": sorted(owner_reviews),
        "coordinationIds": allowed["coordinationIds"],
        "paths": rows,
    }


def git_changed_paths(project: pathlib.Path, base: str, head: str) -> list[str]:
    output = run_git(project, "diff", "--name-only", "--diff-filter=ACDMRTUXB", f"{base}..{head}", "--")
    return [normalize_path(line) for line in output.splitlines() if line.strip()]


def review_impact(changed_paths: Iterable[str], model: dict[str, Any]) -> dict[str, Any]:
    scopes = {}
    changed = sorted(set(normalize_path(path) for path in changed_paths))
    for scope, patterns in model["config"].get("reviewScopes", {}).items():
        matching = [path for path in changed if matches_any(path, patterns)]
        scopes[scope] = {
            "invalidated": bool(matching),
            "changedPaths": matching,
        }
    invalidated = sorted(scope for scope, value in scopes.items() if value["invalidated"])
    if not invalidated:
        classification = "NO_REVIEW_IMPACT"
    elif invalidated == ["EVIDENCE"]:
        classification = "EVIDENCE_REVIEW_INVALIDATED"
    elif invalidated == ["SOURCE"]:
        classification = "SOURCE_REVIEW_INVALIDATED"
    elif invalidated == ["SECURITY"]:
        classification = "SECURITY_REVIEW_INVALIDATED"
    elif invalidated == ["INTEGRATION"]:
        classification = "INTEGRATION_REVIEW_INVALIDATED"
    else:
        classification = "MULTI_SCOPE_REVIEW_INVALIDATED"
    return {
        "classification": classification,
        "invalidatedScopes": invalidated,
        "scopes": scopes,
        "changedPaths": changed,
        "treeOnlyReviewBindingAllowed": False,
    }


def task_dependencies_satisfied(task: dict[str, Any], latest: dict[str, dict[str, Any]]) -> bool:
    accepted = {"ACCEPTED", "MERGED_MAIN"}
    return all(latest.get(dep, {}).get("status") in accepted for dep in task.get("dependencies", []))


def delivery_metrics(project: pathlib.Path, model: dict[str, Any]) -> dict[str, Any]:
    latest = load_latest_records(project, model)
    mission_rows = []
    totals = defaultdict(int)
    status_order = model["config"]["statuses"]
    for mission_id, mission in model["missions"].items():
        tasks = [
            task for task in model["tasks"].values()
            if task.get("mission") == mission_id
        ]
        counts = {status: 0 for status in status_order}
        records = []
        for task in sorted(tasks, key=lambda item: item["id"]):
            record = latest.get(task["id"])
            status = record.get("status") if record else "NOT_EVALUATED"
            counts[status] = counts.get(status, 0) + 1
            totals[status] += 1
            if record:
                records.append(
                    {
                        "task": task["id"],
                        "status": status,
                        "recordedAt": record.get("recordedAt"),
                        "path": record.get("_path"),
                        "nextAction": record.get("nextAction"),
                    }
                )
        accepted = counts.get("ACCEPTED", 0) + counts.get("MERGED_MAIN", 0)
        mission_rows.append(
            {
                "mission": mission_id,
                "title": mission["title"],
                "worker": (mission.get("activeClaim") or {}).get("worker"),
                "claimStatus": (mission.get("activeClaim") or {}).get("status", "UNCLAIMED"),
                "totalTasks": len(tasks),
                "acceptedTasks": accepted,
                "mergedMainTasks": counts.get("MERGED_MAIN", 0),
                "inReviewTasks": counts.get("REVIEW", 0),
                "implementationTasks": counts.get("IMPLEMENTATION", 0),
                "blockedTasks": counts.get("BLOCKED", 0) + counts.get("BLOCKED_EXTERNAL", 0),
                "notEvaluatedTasks": counts.get("NOT_EVALUATED", 0),
                "statusCounts": counts,
                "records": records,
                "frontierState": "DERIVE_LIVE_FROM_ROADMAP_INTERLOCKS_AND_CURRENT_RECORDS",
            }
        )
    total_tasks = len(model["tasks"])
    accepted_total = totals["ACCEPTED"] + totals["MERGED_MAIN"]
    return {
        "schemaVersion": 1,
        "generatedAt": "DETERMINISTIC_FROM_RECORDS",
        "taskCount": total_tasks,
        "explicitRecordCount": len(latest),
        "acceptedTaskCount": accepted_total,
        "mergedMainTaskCount": totals["MERGED_MAIN"],
        "inReviewTaskCount": totals["REVIEW"],
        "implementationTaskCount": totals["IMPLEMENTATION"],
        "blockedTaskCount": totals["BLOCKED"] + totals["BLOCKED_EXTERNAL"],
        "notEvaluatedTaskCount": totals["NOT_EVALUATED"],
        "statusCounts": dict(sorted(totals.items())),
        "progressPercentage": (
            round(accepted_total * 100.0 / total_tasks, 2) if total_tasks else 0.0
        ),
        "progressMeaning": "Accepted or merged roadmap tasks only; source presence and CI alone do not count.",
        "missions": mission_rows,
    }

def dashboard_markdown(metrics: dict[str, Any]) -> str:
    lines = [
        "# Kristin mission delivery dashboard",
        "",
        "This dashboard counts only append-only delivery records. Missing records are `NOT_EVALUATED`; prose, commits, source presence, and CI do not silently become task completion.",
        "",
        "## Portfolio",
        "",
        f"- Roadmap tasks: **{metrics['taskCount']}**",
        f"- Accepted: **{metrics['acceptedTaskCount']}**",
        f"- Merged to protected main: **{metrics['mergedMainTaskCount']}**",
        f"- In implementation: **{metrics['implementationTaskCount']}**",
        f"- In review: **{metrics['inReviewTaskCount']}**",
        f"- Blocked: **{metrics['blockedTaskCount']}**",
        f"- Not evaluated: **{metrics['notEvaluatedTaskCount']}**",
        f"- Accepted progress: **{metrics['progressPercentage']:.2f}%**",
        "",
        "| Mission | Worker | Claim | Accepted / total | Merged main | Implementation | Review | Blocked | Not evaluated |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in metrics["missions"]:
        lines.append(
            f"| `{row['mission']}` {row['title']} | "
            f"{('Worker ' + row['worker']) if row['worker'] else 'Unassigned'} | "
            f"`{row['claimStatus']}` | "
            f"{row['acceptedTasks']} / {row['totalTasks']} | "
            f"{row['mergedMainTasks']} | {row['implementationTasks']} | "
            f"{row['inReviewTasks']} | {row['blockedTasks']} | {row['notEvaluatedTasks']} |"
        )
    lines += [
        "",
        "## Interpretation",
        "",
        "- `ACCEPTED` requires exact commit/tree, durable evidence, and the task's done conditions.",
        "- `MERGED_MAIN` additionally requires the protected-main merge identity.",
        "- `REVIEW` means implementation exists but is not accepted.",
        "- `NOT_EVALUATED` is intentional and must never be presented as zero-progress proof or completion.",
        "- The executable frontier must be derived live from task dependencies, interlocks, claims, and the latest records before a worker claims work.",
        "",
    ]
    return "\n".join(lines)

def generated_contents(project: pathlib.Path, model: dict[str, Any]) -> dict[pathlib.Path, str]:
    metrics = delivery_metrics(project, model)
    generated = model["config"]["generated"]
    return {
        project / generated["metrics"]: json.dumps(metrics, indent=2, sort_keys=True) + "\n",
        project / generated["dashboard"]: dashboard_markdown(metrics),
    }


def generate(project: pathlib.Path, model: dict[str, Any], check: bool) -> None:
    mismatches = []
    for path, content in generated_contents(project, model).items():
        if check:
            if not path.is_file() or path.read_text(encoding="utf-8") != content:
                mismatches.append(path.relative_to(project).as_posix())
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    if mismatches:
        raise DeliveryError("generated delivery files differ: " + ", ".join(mismatches))
    print(f"MISSION_DELIVERY_GENERATED check={str(check).lower()} files=2")


def append_record(
    project: pathlib.Path,
    model: dict[str, Any],
    mission: str,
    task: str,
    status: str,
    work_id: str,
    worker: str,
    branch: str,
    pr: int | None,
    commit: str | None,
    tree: str | None,
    evidence: list[str],
    next_action: str,
    merged_main_commit: str | None,
) -> pathlib.Path:
    timestamp = utc_now()
    record = {
        "schemaVersion": 1,
        "mission": mission,
        "task": task,
        "status": status,
        "workExecutionId": work_id,
        "worker": worker,
        "branch": branch,
        "pullRequest": pr,
        "commit": commit,
        "tree": tree,
        "evidence": evidence,
        "nextAction": next_action,
        "mergedMainCommit": merged_main_commit,
        "recordedAt": timestamp,
    }
    validate_record(record, model)
    safe_time = timestamp.replace(":", "").replace("-", "")
    target = (
        project
        / model["config"]["recordsRoot"]
        / task
        / f"{safe_time}-{work_id}.json"
    )
    if target.exists():
        raise DeliveryError(f"append-only record already exists: {target}")
    write_json(target, record)
    return target
