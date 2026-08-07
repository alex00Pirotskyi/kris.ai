#!/usr/bin/env python3
"""Generate delivery metrics without promoting legacy bookkeeping to acceptance.

Historical records are read for their declared non-terminal status only. Strict
ACCEPTED/MERGED_MAIN provenance is validated separately by
`mission_delivery_strict.py` before this generator runs.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from collections import defaultdict
from typing import Any

from mission_delivery_lib import load_model, read_json, record_files


def latest_records(project: pathlib.Path, model: dict[str, Any]) -> dict[str, dict[str, Any]]:
    latest: dict[str, dict[str, Any]] = {}
    for path in record_files(project, model):
        value = read_json(path)
        task = value.get("task")
        recorded = value.get("recordedAt", "")
        if not isinstance(task, str) or task not in model["tasks"]:
            raise ValueError(f"unknown/missing task in {path.relative_to(project)}")
        if not isinstance(recorded, str):
            raise ValueError(f"missing recordedAt in {path.relative_to(project)}")
        previous = latest.get(task)
        if previous is None or recorded > previous.get("recordedAt", ""):
            value = dict(value)
            value["_path"] = path.relative_to(project).as_posix()
            latest[task] = value
    return latest


def metrics(project: pathlib.Path, model: dict[str, Any]) -> dict[str, Any]:
    latest = latest_records(project, model)
    statuses = model["config"]["statuses"]
    totals = defaultdict(int)
    rows = []
    for mission_id, mission in model["missions"].items():
        tasks = sorted(
            (task for task in model["tasks"].values() if task.get("mission") == mission_id),
            key=lambda item: item["id"],
        )
        counts = {status: 0 for status in statuses}
        records = []
        for task in tasks:
            record = latest.get(task["id"])
            status = record.get("status") if record else "NOT_EVALUATED"
            if status not in counts:
                raise ValueError(f"unsupported delivery status {status} for {task['id']}")
            counts[status] += 1
            totals[status] += 1
            if record:
                records.append({
                    "task": task["id"],
                    "status": status,
                    "recordedAt": record.get("recordedAt"),
                    "path": record.get("_path"),
                    "nextAction": record.get("nextAction"),
                })
        accepted = counts.get("ACCEPTED", 0) + counts.get("MERGED_MAIN", 0)
        active_claim = mission.get("activeClaim") or {}
        rows.append({
            "mission": mission_id,
            "title": mission["title"],
            "worker": active_claim.get("worker"),
            "claimStatus": active_claim.get("status", "UNCLAIMED"),
            "totalTasks": len(tasks),
            "acceptedTasks": accepted,
            "mergedMainTasks": counts.get("MERGED_MAIN", 0),
            "implementationTasks": counts.get("IMPLEMENTATION", 0),
            "inReviewTasks": counts.get("REVIEW", 0),
            "blockedTasks": counts.get("BLOCKED", 0) + counts.get("BLOCKED_EXTERNAL", 0),
            "notEvaluatedTasks": counts.get("NOT_EVALUATED", 0),
            "statusCounts": counts,
            "records": records,
            "frontierState": "DERIVE_LIVE_FROM_TASK_RECORDS_CLAIMS_HELPER_LEASES_AND_GIT",
        })
    total = len(model["tasks"])
    accepted_total = totals["ACCEPTED"] + totals["MERGED_MAIN"]
    return {
        "schemaVersion": 1,
        "generatedAt": "DETERMINISTIC_FROM_RECORDS",
        "taskCount": total,
        "explicitRecordCount": len(latest),
        "acceptedTaskCount": accepted_total,
        "mergedMainTaskCount": totals["MERGED_MAIN"],
        "implementationTaskCount": totals["IMPLEMENTATION"],
        "inReviewTaskCount": totals["REVIEW"],
        "blockedTaskCount": totals["BLOCKED"] + totals["BLOCKED_EXTERNAL"],
        "notEvaluatedTaskCount": totals["NOT_EVALUATED"],
        "statusCounts": dict(sorted(totals.items())),
        "progressPercentage": round(accepted_total * 100.0 / total, 2) if total else 0.0,
        "progressMeaning": "Accepted or merged roadmap tasks only; legacy non-terminal records remain bookkeeping and do not become acceptance proof.",
        "missions": rows,
    }


def dashboard(value: dict[str, Any]) -> str:
    lines = [
        "# Kristin mission delivery dashboard",
        "",
        "This dashboard counts the latest append-only record per roadmap task. Historical non-terminal records may retain legacy formatting; only strict-provenance `ACCEPTED` / `MERGED_MAIN` records count as accepted progress.",
        "",
        "## Portfolio",
        "",
        f"- Roadmap tasks: **{value['taskCount']}**",
        f"- Accepted: **{value['acceptedTaskCount']}**",
        f"- Merged to protected main: **{value['mergedMainTaskCount']}**",
        f"- In implementation: **{value['implementationTaskCount']}**",
        f"- In review: **{value['inReviewTaskCount']}**",
        f"- Blocked: **{value['blockedTaskCount']}**",
        f"- Not evaluated: **{value['notEvaluatedTaskCount']}**",
        f"- Accepted progress: **{value['progressPercentage']:.2f}%**",
        "",
        "| Mission | Worker | Claim | Accepted / total | Merged | Impl | Review | Blocked | Not evaluated |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in value["missions"]:
        lines.append(
            f"| `{row['mission']}` {row['title']} | "
            f"{('Worker ' + row['worker']) if row['worker'] else 'Unassigned'} | "
            f"`{row['claimStatus']}` | {row['acceptedTasks']} / {row['totalTasks']} | "
            f"{row['mergedMainTasks']} | {row['implementationTasks']} | {row['inReviewTasks']} | "
            f"{row['blockedTasks']} | {row['notEvaluatedTasks']} |"
        )
    lines += [
        "",
        "`NOT_EVALUATED` means no accepted delivery-state record exists; it is not proof that no source work exists.",
        "The executable frontier must be derived live from exact task dependencies, durable claims, active helper leases, current blockers, and Git/CI/review state.",
        "",
    ]
    return "\n".join(lines)


def generate(project: pathlib.Path, check: bool) -> None:
    model = load_model(project)
    value = metrics(project, model)
    generated = model["config"]["generated"]
    targets = {
        project / generated["metrics"]: json.dumps(value, indent=2, sort_keys=True) + "\n",
        project / generated["dashboard"]: dashboard(value),
    }
    mismatches = []
    for path, content in targets.items():
        if check:
            if not path.is_file() or path.read_text(encoding="utf-8") != content:
                mismatches.append(path.relative_to(project).as_posix())
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    if mismatches:
        raise ValueError("safe delivery metrics differ: " + ", ".join(mismatches))
    print(f"MISSION_DELIVERY_METRICS_SAFE check={str(check).lower()} files=2")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        generate(pathlib.Path(args.project).resolve(), args.check)
        return 0
    except Exception as exc:
        print(f"MISSION_DELIVERY_METRICS_SAFE_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
