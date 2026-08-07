#!/usr/bin/env python3
"""Runtime coordination primitives for autonomous mission workers.

Mission claims remain integration/leadership locks. Helper leases are bounded
write locks inside a claimed mission and are intentionally narrower than the
mission's maximum path policy. This module is local/deterministic; a worker must
publish a newly created lease to the canonical mission branch with a normal
fast-forward update, re-fetch that branch, and validate again before editing.
That publish/re-fetch step is the repository compare-and-swap boundary.
"""
from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import json
import pathlib
import re
import sys
from typing import Any, Iterable

from mission_delivery_lib import load_latest_records, load_model, normalize_path

ROOT = pathlib.Path("docs/roadmap/missions")
CLAIMS = ROOT / "claims"
LEASES = ROOT / "helper-leases"
LEASE_ID_RE = re.compile(r"^HLP-[A-Z0-9][A-Z0-9._-]{5,79}$")
ACTIVE_LEASE_STATES = {"ACTIVE"}
FINAL_LEASE_STATES = {"YIELDED", "COMPLETE", "EXPIRED"}
ACCEPTED_TASK_STATES = {"ACCEPTED", "MERGED_MAIN"}


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def iso(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_time(value: str) -> dt.datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ValueError(f"timestamp must be timezone-qualified UTC RFC3339: {value!r}")
    parsed = dt.datetime.fromisoformat(value[:-1] + "+00:00")
    if parsed.tzinfo is None:
        raise ValueError(f"timestamp missing timezone: {value!r}")
    return parsed.astimezone(dt.timezone.utc)


def read_json(path: pathlib.Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")


def static_prefix(pattern: str) -> str:
    return normalize_path(pattern).split("*", 1)[0].rstrip("/")


def prefixes_overlap(left: str, right: str) -> bool:
    a, b = static_prefix(left), static_prefix(right)
    return bool(a and b and (a == b or a.startswith(b + "/") or b.startswith(a + "/")))


def pattern_within(child: str, parent: str) -> bool:
    child = normalize_path(child)
    parent = normalize_path(parent)
    pfx = static_prefix(parent)
    cfx = static_prefix(child)
    if not pfx or not cfx:
        return False
    if not (cfx == pfx or cfx.startswith(pfx + "/")):
        return False
    # Exact child paths and narrower glob patterns are acceptable when they
    # live under the parent's static namespace. A helper lease can only narrow
    # authority, never widen it.
    return True


def durable_claims(project: pathlib.Path) -> dict[str, dict[str, Any]]:
    root = project / CLAIMS
    claims: dict[str, dict[str, Any]] = {}
    if not root.is_dir():
        return claims
    for path in sorted(root.glob("MISSION-*.claim.json")):
        value = read_json(path)
        mission = value.get("mission")
        if not isinstance(mission, str) or mission in claims:
            raise ValueError(f"invalid or duplicate durable claim: {path}")
        if not value.get("worker") or not value.get("branch"):
            raise ValueError(f"durable claim missing worker/branch: {path}")
        claims[mission] = value
    return claims


def lease_files(project: pathlib.Path) -> list[pathlib.Path]:
    root = project / LEASES
    return sorted(root.glob("MISSION-*/*.json")) if root.is_dir() else []


def load_leases(project: pathlib.Path) -> list[dict[str, Any]]:
    values: list[dict[str, Any]] = []
    for path in lease_files(project):
        value = read_json(path)
        value["_path"] = path.relative_to(project).as_posix()
        values.append(value)
    return values


def mission_owned_patterns(model: dict[str, Any], mission: str) -> list[str]:
    return list(model["config"]["missionPathPolicies"][mission]["owned"])


def claim_patterns(claim: dict[str, Any], model: dict[str, Any]) -> list[str]:
    explicit = claim.get("exclusivePaths") or []
    if explicit:
        return list(explicit)
    return mission_owned_patterns(model, claim["mission"])


def validate_lease(lease: dict[str, Any], model: dict[str, Any], claims: dict[str, dict[str, Any]]) -> None:
    required = [
        "schemaVersion", "leaseId", "mission", "task", "ownerWorker", "helperWorker",
        "workExecutionId", "branch", "baseCommit", "baseTree", "allowedPaths", "status",
        "createdAt", "refreshedAt", "expiresAt", "parentClaimHead", "nextAction",
    ]
    missing = [key for key in required if key not in lease]
    if missing:
        raise ValueError(f"helper lease missing fields: {missing}")
    if lease["schemaVersion"] != 1:
        raise ValueError("helper lease schemaVersion must be 1")
    if not LEASE_ID_RE.fullmatch(str(lease["leaseId"])):
        raise ValueError(f"invalid helper lease id: {lease['leaseId']}")
    mission = lease["mission"]
    if mission not in model["missions"]:
        raise ValueError(f"unknown helper mission: {mission}")
    task = lease["task"]
    if task not in model["tasks"] or model["tasks"][task].get("mission") != mission:
        raise ValueError(f"helper task {task} does not belong to {mission}")
    claim = claims.get(mission)
    if claim is None:
        raise ValueError(f"helper lease requires an active durable mission claim: {mission}")
    if lease["ownerWorker"] != claim.get("worker"):
        raise ValueError(f"helper ownerWorker does not match durable claim owner for {mission}")
    if lease["parentClaimHead"] != claim.get("head"):
        raise ValueError(f"helper lease is stale relative to durable claim head for {mission}")
    status = lease["status"]
    if status not in ACTIVE_LEASE_STATES | FINAL_LEASE_STATES:
        raise ValueError(f"unsupported helper lease status: {status}")
    allowed = lease.get("allowedPaths") or []
    if not allowed:
        raise ValueError("helper lease allowedPaths must be non-empty")
    maxima = claim_patterns(claim, model)
    for path in allowed:
        if not any(pattern_within(path, maximum) for maximum in maxima):
            raise ValueError(f"helper path widens mission claim: {path}")
    created = parse_time(lease["createdAt"])
    refreshed = parse_time(lease["refreshedAt"])
    expires = parse_time(lease["expiresAt"])
    if refreshed < created or expires <= refreshed:
        raise ValueError("helper lease timestamp ordering is invalid")


def active_leases(project: pathlib.Path, model: dict[str, Any], claims: dict[str, dict[str, Any]], now: dt.datetime | None = None) -> list[dict[str, Any]]:
    now = now or utc_now()
    active: list[dict[str, Any]] = []
    for lease in load_leases(project):
        validate_lease(lease, model, claims)
        if lease["status"] == "ACTIVE" and parse_time(lease["expiresAt"]) > now:
            active.append(lease)
    for index, left in enumerate(active):
        for right in active[index + 1 :]:
            if left["mission"] != right["mission"]:
                continue
            for a in left["allowedPaths"]:
                for b in right["allowedPaths"]:
                    if prefixes_overlap(a, b):
                        raise ValueError(
                            f"active helper lease collision: {left['leaseId']} {a} vs {right['leaseId']} {b}"
                        )
    return active


def validate_runtime(project: pathlib.Path) -> dict[str, Any]:
    model = load_model(project)
    claims = durable_claims(project)
    unknown = sorted(set(claims) - set(model["missions"]))
    if unknown:
        raise ValueError(f"durable claims reference unknown missions: {unknown}")
    leases = active_leases(project, model, claims)
    return {"model": model, "claims": claims, "leases": leases}


def helper_path(project: pathlib.Path, mission: str, lease_id: str) -> pathlib.Path:
    return project / LEASES / mission / f"{lease_id}.json"


def create_helper(project: pathlib.Path, args: argparse.Namespace) -> pathlib.Path:
    runtime = validate_runtime(project)
    model, claims = runtime["model"], runtime["claims"]
    if args.mission not in claims:
        raise ValueError(f"mission is not durably claimed: {args.mission}")
    if args.task not in model["tasks"] or model["tasks"][args.task].get("mission") != args.mission:
        raise ValueError(f"task {args.task} does not belong to {args.mission}")
    target = helper_path(project, args.mission, args.lease_id)
    if target.exists():
        raise ValueError(f"helper lease already exists: {target.relative_to(project)}")
    now = utc_now()
    claim = claims[args.mission]
    lease = {
        "schemaVersion": 1,
        "leaseId": args.lease_id,
        "mission": args.mission,
        "task": args.task,
        "ownerWorker": claim["worker"],
        "helperWorker": args.helper_worker,
        "workExecutionId": args.work_id,
        "branch": args.branch,
        "baseCommit": args.base_commit,
        "baseTree": args.base_tree,
        "allowedPaths": sorted(set(args.allowed_path)),
        "status": "ACTIVE",
        "createdAt": iso(now),
        "refreshedAt": iso(now),
        "expiresAt": iso(now + dt.timedelta(hours=args.hours)),
        "parentClaimHead": claim.get("head"),
        "nextAction": args.next_action,
    }
    validate_lease(lease, model, claims)
    for existing in runtime["leases"]:
        if existing["mission"] != args.mission:
            continue
        for left in lease["allowedPaths"]:
            for right in existing["allowedPaths"]:
                if prefixes_overlap(left, right):
                    raise ValueError(
                        f"requested helper path collides with {existing['leaseId']}: {left} vs {right}"
                    )
    write_json(target, lease)
    return target


def mutate_helper(project: pathlib.Path, args: argparse.Namespace, status: str | None) -> pathlib.Path:
    runtime = validate_runtime(project)
    target = helper_path(project, args.mission, args.lease_id)
    if not target.is_file():
        raise ValueError(f"helper lease not found: {target.relative_to(project)}")
    lease = read_json(target)
    if lease.get("helperWorker") != args.helper_worker:
        raise ValueError("only the recorded helperWorker may mutate its lease")
    if lease.get("status") != "ACTIVE":
        raise ValueError(f"helper lease is not active: {lease.get('status')}")
    now = utc_now()
    lease["refreshedAt"] = iso(now)
    if status is None:
        lease["expiresAt"] = iso(now + dt.timedelta(hours=args.hours))
    else:
        lease["status"] = status
        lease["expiresAt"] = iso(now + dt.timedelta(seconds=1))
        lease["nextAction"] = args.next_action
    validate_lease(lease, runtime["model"], runtime["claims"])
    write_json(target, lease)
    return target


def frontier(project: pathlib.Path) -> dict[str, Any]:
    runtime = validate_runtime(project)
    model, claims, leases = runtime["model"], runtime["claims"], runtime["leases"]
    latest = load_latest_records(project, model)
    priorities = model["config"].get("priorityOrder", {})
    rows: list[dict[str, Any]] = []
    leased_tasks = {(lease["mission"], lease["task"]) for lease in leases}
    for task in model["tasks"].values():
        mission = task["mission"]
        record = latest.get(task["id"], {})
        state = record.get("status", "NOT_EVALUATED")
        if state in ACCEPTED_TASK_STATES:
            continue
        deps = task.get("dependencies", [])
        missing = [dep for dep in deps if latest.get(dep, {}).get("status") not in ACCEPTED_TASK_STATES]
        if missing:
            continue
        mission_meta = model["missions"][mission]
        claimed = mission in claims
        helper_busy = (mission, task["id"]) in leased_tasks
        rows.append(
            {
                "mission": mission,
                "task": task["id"],
                "title": task.get("title"),
                "status": state,
                "claimed": claimed,
                "claimWorker": claims.get(mission, {}).get("worker"),
                "helperLeaseActive": helper_busy,
                "action": "HELPER_CANDIDATE" if claimed and not helper_busy else ("MISSION_CLAIM_CANDIDATE" if not claimed else "OWNER_CONTINUE"),
                "priority": mission_meta.get("priority"),
                "priorityOrder": priorities.get(mission_meta.get("priority"), 999),
            }
        )
    rows.sort(key=lambda row: (row["priorityOrder"], row["mission"], row["task"]))
    return {
        "schemaVersion": 1,
        "meaning": "Dependency-satisfied roadmap tasks from durable records. Live Git/CI/ownership must still be re-resolved before writing.",
        "activeClaimCount": len(claims),
        "activeHelperLeaseCount": len(leases),
        "candidateCount": len(rows),
        "candidates": rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("validate")
    sub.add_parser("next-work")

    create = sub.add_parser("helper-create")
    create.add_argument("--lease-id", required=True)
    create.add_argument("--mission", required=True)
    create.add_argument("--task", required=True)
    create.add_argument("--helper-worker", required=True)
    create.add_argument("--work-id", required=True)
    create.add_argument("--branch", required=True)
    create.add_argument("--base-commit", required=True)
    create.add_argument("--base-tree", required=True)
    create.add_argument("--allowed-path", action="append", required=True)
    create.add_argument("--hours", type=int, default=4)
    create.add_argument("--next-action", required=True)

    for name in ("helper-heartbeat", "helper-yield", "helper-complete"):
        item = sub.add_parser(name)
        item.add_argument("--lease-id", required=True)
        item.add_argument("--mission", required=True)
        item.add_argument("--helper-worker", required=True)
        item.add_argument("--hours", type=int, default=4)
        item.add_argument("--next-action", default="Re-resolve live state and continue the highest-priority safe action.")

    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    try:
        if args.command == "validate":
            runtime = validate_runtime(project)
            print(
                "MISSION_RUNTIME_VALID "
                f"claims={len(runtime['claims'])} active_helper_leases={len(runtime['leases'])}"
            )
        elif args.command == "next-work":
            print(json.dumps(frontier(project), indent=2, sort_keys=True))
        elif args.command == "helper-create":
            target = create_helper(project, args)
            print(f"MISSION_HELPER_CREATED path={target.relative_to(project)}")
        elif args.command == "helper-heartbeat":
            target = mutate_helper(project, args, None)
            print(f"MISSION_HELPER_REFRESHED path={target.relative_to(project)}")
        elif args.command == "helper-yield":
            target = mutate_helper(project, args, "YIELDED")
            print(f"MISSION_HELPER_YIELDED path={target.relative_to(project)}")
        elif args.command == "helper-complete":
            target = mutate_helper(project, args, "COMPLETE")
            print(f"MISSION_HELPER_COMPLETE path={target.relative_to(project)}")
        return 0
    except Exception as exc:
        print(f"MISSION_RUNTIME_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
