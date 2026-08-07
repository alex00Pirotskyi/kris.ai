#!/usr/bin/env python3
"""Generate delivery metrics without promoting legacy bookkeeping to acceptance.

Historical records are read for their declared non-terminal status only. Strict
ACCEPTED/MERGED_MAIN provenance is validated separately by
`mission_delivery_strict.py` before this generator runs. Unknown historical
status labels are preserved as rawStatus and counted only as LEGACY_OTHER.
Mission Execution 1.5 additionally reports source landing as an orthogonal
metric; LANDED_MAIN never increments accepted progress by itself.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from collections import defaultdict
from typing import Any

from mission_delivery_lib import load_model, read_json, record_files

LEGACY_OTHER = "LEGACY_OTHER"
SOURCE_LANDING_VALUES = {"NOT_LANDED", "HELPER", "PRODUCT_PR", "LANDED_MAIN"}


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


def latest_source_landing(project: pathlib.Path, model: dict[str, Any]) -> dict[str, dict[str, Any]]:
    latest: dict[str, dict[str, Any]] = {}
    for path in record_files(project, model):
        value = read_json(path)
        task = value.get("task")
        landing = value.get("sourceLanding")
        recorded = value.get("recordedAt", "")
        if landing is None:
            continue
        if landing not in SOURCE_LANDING_VALUES:
            raise ValueError(f"unsupported sourceLanding in {path.relative_to(project)}: {landing}")
        if not isinstance(task, str) or task not in model["tasks"]:
            raise ValueError(f"unknown/missing task in {path.relative_to(project)}")
        previous = latest.get(task)
        if previous is None or recorded > previous.get("recordedAt", ""):
            item = dict(value)
            item["_path"] = path.relative_to(project).as_posix()
            latest[task] = item
    return latest


def metrics(project: pathlib.Path, model: dict[str, Any]) -> dict[str, Any]:
    latest = latest_records(project, model)
    landing_latest = latest_source_landing(project, model)
    statuses = list(model["config"]["statuses"])
    totals = defaultdict(int)
    source_totals = defaultdict(int)
    rows = []
    for mission_id, mission in model["missions"].items():
        tasks = sorted(
            (task for task in model["tasks"].values() if task.get("mission") == mission_id),
            key=lambda item: item["id"],
        )
        counts = {status: 0 for status in statuses}
        counts[LEGACY_OTHER] = 0
        source_counts = {value: 0 for value in SOURCE_LANDING_VALUES}
        records = []
        for task in tasks:
            record = latest.get(task["id"])
            raw_status = record.get("status") if record else "NOT_EVALUATED"
            status = raw_status if raw_status in counts else LEGACY_OTHER
            counts[status] += 1
            totals[status] += 1

            landing_record = landing_latest.get(task["id"])
            landing = landing_record.get("sourceLanding") if landing_record else "NOT_LANDED"
            source_counts[landing] += 1
            source_totals[landing] += 1

            if record or landing_record:
                row = {
                    "task": task["id"],
                    "status": status,
                    "sourceLanding": landing,
                    "recordedAt": record.get("recordedAt") if record else None,
                    "path": record.get("_path") if record else None,
                    "nextAction": record.get("nextAction") if record else None,
                    "sourceLandingRecordPath": landing_record.get("_path") if landing_record else None,
                }
                if status == LEGACY_OTHER:
                    row["rawStatus"] = raw_status
                records.append(row)
        accepted = counts.get("ACCEPTED", 0) + counts.get("MERGED_MAIN", 0)
        active_claim = mission.get("activeClaim") or {}
        rows.append({
            "mission": mission_id,
            "title": mission["title"],
            "worker": active_claim.get("worker"),
            "claimStatus": active_claim.get("status", "UNCLAIMED"),
            "totalTasks": len(tasks),
            "acceptedTasks": accepted,
            "landedMainTasks": source_counts.get("LANDED_MAIN", 0),
            "mergedMainTasks": counts.get("MERGED_MAIN", 0),
            "implementationTasks": counts.get("IMPLEMENTATION", 0),
            "inReviewTasks": counts.get("REVIEW", 0),
            "blockedTasks": counts.get("BLOCKED", 0) + counts.get("BLOCKED_EXTERNAL", 0),
            "legacyOtherTasks": counts.get(LEGACY_OTHER, 0),
            "notEvaluatedTasks": counts.get("NOT_EVALUATED", 0),
            "statusCounts": counts,
            "sourceLandingCounts": source_counts,
            "records": records,
            "frontierState": "DERIVE_LIVE_FROM_TASK_RECORDS_RUNTIME_WORK_ORDERS_SEMAPHORES_AND_GIT",
        })
    total = len(model["tasks"])
    accepted_total = totals["ACCEPTED"] + totals["MERGED_MAIN"]
    landed_total = source_totals["LANDED_MAIN"]
    return {
        "schemaVersion": 2,
        "generatedAt": "DETERMINISTIC_FROM_RECORDS",
        "taskCount": total,
        "explicitRecordCount": len(latest),
        "acceptedTaskCount": accepted_total,
        "landedMainTaskCount": landed_total,
        "mergedMainTaskCount": totals["MERGED_MAIN"],
        "implementationTaskCount": totals["IMPLEMENTATION"],
        "inReviewTaskCount": totals["REVIEW"],
        "blockedTaskCount": totals["BLOCKED"] + totals["BLOCKED_EXTERNAL"],
        "legacyOtherTaskCount": totals[LEGACY_OTHER],
        "notEvaluatedTaskCount": totals["NOT_EVALUATED"],
        "statusCounts": dict(sorted(totals.items())),
        "sourceLandingCounts": dict(sorted(source_totals.items())),
        "progressPercentage": round(accepted_total * 100.0 / total, 2) if total else 0.0,
        "sourceLandingPercentage": round(landed_total * 100.0 / total, 2) if total else 0.0,
        "progressMeaning": "Accepted progress counts only strict-provenance ACCEPTED/MERGED_MAIN. LANDED_MAIN is an orthogonal source-delivery metric and never implies acceptance, certification, platform or release support.",
        "missions": rows,
    }


def dashboard(value: dict[str, Any]) -> str:
    lines = [
        "# Kristin mission delivery dashboard",
        "",
        "This dashboard counts the latest append-only delivery state per roadmap task and independently tracks source landing. Historical non-terminal records may retain legacy formatting/status labels; only strict-provenance `ACCEPTED` / `MERGED_MAIN` records count as accepted progress.",
        "",
        "## Portfolio",
        "",
        f"- Roadmap tasks: **{value['taskCount']}**",
        f"- Source landed on protected main: **{value['landedMainTaskCount']}**",
        f"- Accepted: **{value['acceptedTaskCount']}**",
        f"- Merged/accepted terminal state: **{value['mergedMainTaskCount']}**",
        f"- In implementation: **{value['implementationTaskCount']}**",
        f"- In review: **{value['inReviewTaskCount']}**",
        f"- Blocked: **{value['blockedTaskCount']}**",
        f"- Legacy other status: **{value['legacyOtherTaskCount']}**",
        f"- Not evaluated: **{value['notEvaluatedTaskCount']}**",
        f"- Source landing progress: **{value['sourceLandingPercentage']:.2f}%**",
        f"- Accepted progress: **{value['progressPercentage']:.2f}%**",
        "",
        "| Mission | Worker | Claim | Landed main | Accepted / total | Terminal merged | Impl | Review | Blocked | Legacy | Not evaluated |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in value["missions"]:
        lines.append(
            f"| `{row['mission']}` {row['title']} | "
            f"{('Worker ' + row['worker']) if row['worker'] else 'Unassigned'} | "
            f"`{row['claimStatus']}` | {row['landedMainTasks']} | {row['acceptedTasks']} / {row['totalTasks']} | "
            f"{row['mergedMainTasks']} | {row['implementationTasks']} | {row['inReviewTasks']} | "
            f"{row['blockedTasks']} | {row['legacyOtherTasks']} | {row['notEvaluatedTasks']} |"
        )
    lines += [
        "",
        "`LANDED_MAIN` means the validated source slice exists on protected main. It does not imply roadmap acceptance, behavioral support, platform support, certification, release support, production or GA.",
        "`LEGACY_OTHER` preserves an old raw status without interpreting it as accepted, blocked, review, or implementation state.",
        "`NOT_EVALUATED` means no normalized delivery-state record exists; it is not proof that no source work exists.",
        "The executable frontier is derived live from exact dependency levels, Work Orders, semaphores, Product PRs, blockers, Git, CI and review state.",
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
