#!/usr/bin/env python3
"""Runtime coordination for autonomous mission workers.

Mission claims are leadership/integration authority. Helper leases are the
backward-compatible v1 bounded write locks. Mission Execution 1.5 extends the
same engine with Work Orders, scoped semaphore invariants and path-aware
frontier reporting without adding a second runtime stack.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import sys
from typing import Any

from mission_delivery_lib import (
    DeliveryError,
    load_latest_records,
    load_model,
    normalize_path,
    run_git,
)

ROOT = pathlib.Path("docs/roadmap/missions")
CLAIMS = ROOT / "claims"
LEASES = ROOT / "helper-leases"
LEASE_ID_RE = re.compile(r"^HLP-[A-Z0-9][A-Z0-9._-]{5,79}$")
ACTIVE = {"ACTIVE"}
FINAL = {"YIELDED", "COMPLETE", "EXPIRED"}
ACCEPTED = {"ACCEPTED", "MERGED_MAIN"}


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def iso(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_time(value: str) -> dt.datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ValueError(f"timestamp must be UTC RFC3339: {value!r}")
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
    cfx, pfx = static_prefix(child), static_prefix(parent)
    return bool(cfx and pfx and (cfx == pfx or cfx.startswith(pfx + "/")))


def durable_claims(project: pathlib.Path) -> dict[str, dict[str, Any]]:
    root = project / CLAIMS
    result: dict[str, dict[str, Any]] = {}
    if not root.is_dir():
        return result
    for path in sorted(root.glob("MISSION-*.claim.json")):
        claim = read_json(path)
        mission = claim.get("mission")
        if not isinstance(mission, str) or mission in result:
            raise ValueError(f"invalid or duplicate durable claim: {path}")
        if not claim.get("worker") or not claim.get("branch"):
            raise ValueError(f"durable claim missing worker/branch: {path}")
        result[mission] = claim
    return result


def lease_files(project: pathlib.Path) -> list[pathlib.Path]:
    root = project / LEASES
    return sorted(root.glob("MISSION-*/*.json")) if root.is_dir() else []


def load_leases(project: pathlib.Path) -> list[dict[str, Any]]:
    leases = []
    for path in lease_files(project):
        value = read_json(path)
        value["_path"] = path.relative_to(project).as_posix()
        leases.append(value)
    return leases


def mission_maximum_patterns(model: dict[str, Any], mission: str) -> list[str]:
    return list(model["config"]["missionPathPolicies"][mission]["owned"])


def verify_git_base(project: pathlib.Path, base_commit: str, base_tree: str) -> None:
    """Bind a reservation to a real immutable Git commit/tree."""
    if not re.fullmatch(r"[0-9a-f]{40}", str(base_commit)):
        raise ValueError("helper baseCommit must be a full lowercase Git object id")
    if not re.fullmatch(r"[0-9a-f]{40}", str(base_tree)):
        raise ValueError("helper baseTree must be a full lowercase Git object id")
    try:
        run_git(project, "cat-file", "-e", f"{base_commit}^{{commit}}")
        actual_tree = run_git(project, "rev-parse", f"{base_commit}^{{tree}}")
    except DeliveryError as exc:
        raise ValueError(f"helper baseCommit does not resolve to a commit: {base_commit}") from exc
    if actual_tree != base_tree:
        raise ValueError(
            f"helper baseCommit/baseTree mismatch: {base_commit} -> {actual_tree}, recorded {base_tree}"
        )


def verify_candidate_ancestry(project: pathlib.Path, base_commit: str, candidate_head: str) -> None:
    """Require a helper/integration candidate to descend from its reserved base."""
    try:
        run_git(project, "cat-file", "-e", f"{candidate_head}^{{commit}}")
        run_git(project, "merge-base", "--is-ancestor", base_commit, candidate_head)
    except DeliveryError as exc:
        raise ValueError(
            f"candidate {candidate_head} does not descend from reserved base {base_commit}"
        ) from exc


def validate_lease(
    lease: dict[str, Any],
    model: dict[str, Any],
    claims: dict[str, dict[str, Any]],
    project: pathlib.Path | None = None,
) -> None:
    required = {
        "schemaVersion", "leaseId", "mission", "task", "ownerWorker", "helperWorker",
        "workExecutionId", "branch", "baseCommit", "baseTree", "allowedPaths", "status",
        "createdAt", "refreshedAt", "expiresAt", "parentClaimHead", "nextAction",
    }
    missing = sorted(required - set(lease))
    if missing:
        raise ValueError(f"helper lease missing fields: {missing}")
    if lease["schemaVersion"] != 1 or not LEASE_ID_RE.fullmatch(str(lease["leaseId"])):
        raise ValueError("invalid helper lease schema/id")
    mission, task = lease["mission"], lease["task"]
    if mission not in model["missions"]:
        raise ValueError(f"unknown helper mission: {mission}")
    if task not in model["tasks"] or model["tasks"][task].get("mission") != mission:
        raise ValueError(f"helper task {task} does not belong to {mission}")
    claim = claims.get(mission)
    if claim is None:
        raise ValueError(f"helper lease requires an active durable mission claim: {mission}")
    if lease["ownerWorker"] != claim.get("worker"):
        raise ValueError(f"helper owner does not match durable claim owner for {mission}")
    if lease["parentClaimHead"] != claim.get("head"):
        raise ValueError(f"helper lease is stale relative to durable claim head for {mission}")
    if lease["status"] not in ACTIVE | FINAL:
        raise ValueError(f"unsupported helper lease status: {lease['status']}")
    if lease["status"] == "ACTIVE" and lease.get("branch") == claim.get("branch"):
        raise ValueError("active helper lease must use a branch separate from the mission owner branch")
    allowed = lease.get("allowedPaths") or []
    if not allowed:
        raise ValueError("helper lease allowedPaths must be non-empty")
    maxima = mission_maximum_patterns(model, mission)
    for path in allowed:
        if not any(pattern_within(path, maximum) for maximum in maxima):
            raise ValueError(f"helper path exceeds mission policy: {path}")
    created, refreshed, expires = map(parse_time, (lease["createdAt"], lease["refreshedAt"], lease["expiresAt"]))
    if refreshed < created or expires <= refreshed:
        raise ValueError("helper lease timestamp ordering is invalid")
    if project is not None:
        verify_git_base(project, lease["baseCommit"], lease["baseTree"])


def active_leases(
    project: pathlib.Path,
    model: dict[str, Any],
    claims: dict[str, dict[str, Any]],
    now: dt.datetime | None = None,
) -> list[dict[str, Any]]:
    now = now or utc_now()
    active: list[dict[str, Any]] = []
    branches: dict[str, str] = {}
    for lease in load_leases(project):
        validate_lease(lease, model, claims, project)
        if lease["status"] == "ACTIVE" and parse_time(lease["expiresAt"]) > now:
            branch = lease["branch"]
            prior = branches.get(branch)
            if prior is not None:
                raise ValueError(
                    f"active helper branch reused by multiple leases: {branch} ({prior}, {lease['leaseId']})"
                )
            branches[branch] = lease["leaseId"]
            active.append(lease)
    for index, left in enumerate(active):
        for right in active[index + 1:]:
            if left["mission"] != right["mission"]:
                continue
            for a in left["allowedPaths"]:
                for b in right["allowedPaths"]:
                    if prefixes_overlap(a, b):
                        raise ValueError(
                            f"active helper collision: {left['leaseId']} {a} vs {right['leaseId']} {b}"
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


def _dependency_state(
    project: pathlib.Path,
    model: dict[str, Any],
    task_id: str,
) -> tuple[list[str], dict[str, dict[str, Any]]]:
    """Backward-compatible acceptance dependency view used by frontier reporting."""
    latest = load_latest_records(project, model)
    missing = [
        dep
        for dep in model["tasks"][task_id].get("dependencies", [])
        if latest.get(dep, {}).get("status") not in ACCEPTED
    ]
    return missing, latest


def create_helper(project: pathlib.Path, args: argparse.Namespace) -> pathlib.Path:
    runtime = validate_runtime(project)
    model, claims = runtime["model"], runtime["claims"]
    claim = claims.get(args.mission)
    if claim is None:
        raise ValueError(f"mission is not durably claimed: {args.mission}")
    if args.task not in model["tasks"] or model["tasks"][args.task].get("mission") != args.mission:
        raise ValueError(f"task {args.task} does not belong to {args.mission}")
    if args.branch == claim.get("branch"):
        raise ValueError("helper branch must be separate from the durable mission owner branch")
    if any(lease["branch"] == args.branch for lease in runtime["leases"]):
        raise ValueError(f"helper branch already has an active lease: {args.branch}")
    verify_git_base(project, args.base_commit, args.base_tree)
    target = helper_path(project, args.mission, args.lease_id)
    if target.exists():
        raise ValueError(f"helper lease already exists: {target.relative_to(project)}")
    now = utc_now()
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
    validate_lease(lease, model, claims, project)
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
    if lease.get("helperWorker") != args.helper_worker or lease.get("status") != "ACTIVE":
        raise ValueError("helper lease mutation rejected")
    now = utc_now()
    lease["refreshedAt"] = iso(now)
    if status is None:
        lease["expiresAt"] = iso(now + dt.timedelta(hours=args.hours))
    else:
        lease["status"] = status
        lease["expiresAt"] = iso(now + dt.timedelta(seconds=1))
        lease["nextAction"] = args.next_action
    validate_lease(lease, runtime["model"], runtime["claims"], project)
    write_json(target, lease)
    return target


def matching_helper_leases(
    leases: list[dict[str, Any]],
    mission: str,
    branch: str,
) -> list[dict[str, Any]]:
    return [
        lease
        for lease in leases
        if lease.get("mission") == mission and lease.get("branch") == branch
    ]


def frontier(project: pathlib.Path) -> dict[str, Any]:
    runtime = validate_runtime(project)
    model, claims, leases = runtime["model"], runtime["claims"], runtime["leases"]
    latest = load_latest_records(project, model)
    priorities = model["config"].get("priorityOrder", {})
    scopes: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for lease in leases:
        scopes.setdefault((lease["mission"], lease["task"]), []).append(
            {
                "leaseId": lease["leaseId"],
                "branch": lease["branch"],
                "allowedPaths": list(lease["allowedPaths"]),
            }
        )
    rows = []
    for task in model["tasks"].values():
        mission = task["mission"]
        record = latest.get(task["id"], {})
        status = record.get("status", "NOT_EVALUATED")
        if status in ACCEPTED:
            continue
        missing = [
            dep
            for dep in task.get("dependencies", [])
            if latest.get(dep, {}).get("status") not in ACCEPTED
        ]
        if missing:
            continue
        claim = claims.get(mission)
        active_scopes = scopes.get((mission, task["id"]), [])
        priority = model["missions"][mission].get("priority")
        if not claim:
            action = "MISSION_CLAIM_CANDIDATE"
        elif active_scopes:
            action = "HELPER_CANDIDATE_ADDITIONAL_NON_OVERLAPPING_SCOPE"
        else:
            action = "HELPER_CANDIDATE"
        rows.append(
            {
                "mission": mission,
                "task": task["id"],
                "title": task.get("title"),
                "status": status,
                "claimed": bool(claim),
                "claimWorker": claim.get("worker") if claim else None,
                "activeHelperScopes": active_scopes,
                "action": action,
                "priority": priority,
                "priorityOrder": priorities.get(priority, 999),
            }
        )
    rows.sort(key=lambda row: (row["priorityOrder"], row["mission"], row["task"]))
    return {
        "schemaVersion": 2,
        "meaning": (
            "Dependency-satisfied roadmap tasks from durable records. "
            "Active helper scopes are path reservations, not whole-task occupancy. "
            "Live Git/CI/ownership must still be re-resolved before writes."
        ),
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
        item.add_argument(
            "--next-action",
            default="Re-resolve live state and continue the highest-priority safe action.",
        )
    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    try:
        if args.command == "validate":
            runtime = validate_runtime(project)
            print(
                f"MISSION_RUNTIME_VALID claims={len(runtime['claims'])} "
                f"active_helper_leases={len(runtime['leases'])}"
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
