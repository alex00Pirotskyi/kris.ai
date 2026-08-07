#!/usr/bin/env python3
"""Strict delivery, source-landing and runtime-ownership checks.

Historical non-terminal bookkeeping remains readable. Future accepted records
and Mission Execution 1.5 source-landing/review receipts are fail-closed.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import re
import sys
from typing import Any

from mission_delivery_lib import (
    DeliveryError,
    load_model,
    matches_any,
    read_json,
    record_files,
    run_git,
    validate_record,
    write_json,
)
from mission_delivery_checks import classify_changed_paths
from mission_runtime_control import (
    active_leases,
    durable_claims,
    matching_helper_leases,
    verify_candidate_ancestry,
)

RFC3339_UTC = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
GIT_SHA = re.compile(r"^[0-9a-f]{40}$")
ACCEPTED = {"ACCEPTED", "MERGED_MAIN"}
SOURCE_LANDING = {"NOT_LANDED", "HELPER", "PRODUCT_PR", "LANDED_MAIN"}
REVIEW_TIERS = {"R0", "R1", "R2"}


def strict_time(value: str) -> dt.datetime:
    if not isinstance(value, str) or not RFC3339_UTC.fullmatch(value):
        raise DeliveryError(f"recordedAt must be canonical UTC RFC3339 seconds: {value!r}")
    return dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_evidence(project: pathlib.Path, item: Any, record_path: pathlib.Path) -> None:
    if not isinstance(item, dict):
        raise DeliveryError(f"{record_path}: accepted evidence must be structured objects")
    path_value = item.get("path")
    expected = item.get("sha256")
    kind = item.get("kind")
    if (
        not isinstance(path_value, str)
        or not path_value
        or pathlib.PurePosixPath(path_value).is_absolute()
        or ".." in pathlib.PurePosixPath(path_value).parts
    ):
        raise DeliveryError(f"{record_path}: unsafe evidence path {path_value!r}")
    if not isinstance(expected, str) or not SHA256.fullmatch(expected):
        raise DeliveryError(f"{record_path}: invalid evidence sha256")
    if not isinstance(kind, str) or not kind:
        raise DeliveryError(f"{record_path}: evidence kind required")
    target = project / path_value
    if not target.is_file():
        raise DeliveryError(f"{record_path}: evidence target missing: {path_value}")
    actual = sha256_file(target)
    if actual != expected:
        raise DeliveryError(f"{record_path}: evidence digest mismatch for {path_value}")


def git_tree(project: pathlib.Path, commit: str) -> str:
    run_git(project, "cat-file", "-e", f"{commit}^{{commit}}")
    return run_git(project, "rev-parse", f"{commit}^{{tree}}")


def latest_records_compat(project: pathlib.Path, model: dict[str, Any]) -> dict[str, dict[str, Any]]:
    latest: dict[str, dict[str, Any]] = {}
    for path in record_files(project, model):
        record = read_json(path)
        task = record.get("task")
        recorded = record.get("recordedAt")
        if not isinstance(task, str) or task not in model["tasks"]:
            raise DeliveryError(f"{path.relative_to(project)}: unknown/missing task")
        strict_time(recorded)
        previous = latest.get(task)
        if previous is None or recorded > previous.get("recordedAt", ""):
            latest[task] = record
    return latest


def validate_review_receipt(
    review: dict[str, Any],
    *,
    candidate_commit: str,
    record_path: pathlib.Path,
) -> None:
    """Validate explicit v1.5 review identity namespaces and tier semantics."""
    if review.get("candidateCommit") != candidate_commit or review.get("decision") != "PASS":
        raise DeliveryError(f"{record_path}: exact-candidate PASS reviewReceipt required")

    tier = review.get("reviewTier")
    if tier is None:
        raise DeliveryError(f"{record_path}: reviewReceipt.reviewTier required (R0/R1/R2)")
    if tier not in REVIEW_TIERS:
        raise DeliveryError(f"{record_path}: invalid review tier {tier!r}")

    worker_identity = review.get("reviewerWorkerIdentity")
    github_identity = review.get("reviewerGitHubIdentity")
    context_id = review.get("reviewContextId")
    author_contexts = review.get("authoringContextIds")
    implementer_contexts = review.get("implementerAuthoringContextIds")
    if not isinstance(worker_identity, str) or not worker_identity:
        raise DeliveryError(f"{record_path}: reviewerWorkerIdentity required")
    if not isinstance(context_id, str) or not context_id:
        raise DeliveryError(f"{record_path}: reviewContextId required")
    if not isinstance(author_contexts, list) or not all(isinstance(x, str) for x in author_contexts):
        raise DeliveryError(f"{record_path}: authoringContextIds must be a string array")
    if not isinstance(implementer_contexts, list) or not all(
        isinstance(x, str) for x in implementer_contexts
    ):
        raise DeliveryError(
            f"{record_path}: implementerAuthoringContextIds must be a string array"
        )

    if tier == "R0":
        raise DeliveryError(f"{record_path}: R0 builder check cannot satisfy accepted state")

    overlap = sorted(set(author_contexts) & set(implementer_contexts))
    if tier == "R1":
        if context_id in implementer_contexts or overlap:
            raise DeliveryError(
                f"{record_path}: R1 review context is contaminated by implementer authoring context"
            )
    elif tier == "R2":
        implementer_github = review.get("implementerGitHubIdentity")
        if (
            not isinstance(github_identity, str)
            or not github_identity
            or not isinstance(implementer_github, str)
            or not implementer_github
            or github_identity == implementer_github
        ):
            raise DeliveryError(
                f"{record_path}: R2 requires distinct reviewer/implementer GitHub identities"
            )


def validate_source_landing(project: pathlib.Path, record: dict[str, Any], record_path: pathlib.Path) -> None:
    source_landing = record.get("sourceLanding")
    if source_landing is None:
        return
    if source_landing not in SOURCE_LANDING:
        raise DeliveryError(f"{record_path}: unsupported sourceLanding {source_landing!r}")
    if source_landing != "LANDED_MAIN":
        return
    commit = record.get("commit")
    merged_main = record.get("mergedMainCommit")
    if not isinstance(commit, str) or not GIT_SHA.fullmatch(commit):
        raise DeliveryError(f"{record_path}: LANDED_MAIN requires exact source commit")
    if not isinstance(merged_main, str) or not GIT_SHA.fullmatch(merged_main):
        raise DeliveryError(f"{record_path}: LANDED_MAIN requires mergedMainCommit")
    run_git(project, "cat-file", "-e", f"{merged_main}^{{commit}}")
    run_git(project, "merge-base", "--is-ancestor", commit, merged_main)


def validate_accepted_records(project: pathlib.Path) -> None:
    model = load_model(project)
    latest = latest_records_compat(project, model)
    future_limit = dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=5)
    for path in record_files(project, model):
        record = read_json(path)
        recorded = strict_time(record.get("recordedAt"))
        if recorded > future_limit:
            raise DeliveryError(f"{path.relative_to(project)}: future-dated delivery record")
        validate_source_landing(project, record, path)
        status = record.get("status")
        if status not in ACCEPTED:
            continue
        validate_record(record, model, path.relative_to(project).as_posix())
        for dependency in model["tasks"][record["task"]].get("dependencies", []):
            if latest.get(dependency, {}).get("status") not in ACCEPTED:
                raise DeliveryError(
                    f"{path.relative_to(project)}: accepted task has unaccepted dependency {dependency}"
                )
        commit = record["commit"]
        actual_tree = git_tree(project, commit)
        if actual_tree != record["tree"]:
            raise DeliveryError(f"{path.relative_to(project)}: commit/tree binding mismatch")
        evidence = record.get("evidence") or []
        if not evidence:
            raise DeliveryError(f"{path.relative_to(project)}: accepted evidence required")
        for item in evidence:
            verify_evidence(project, item, path)
        ci = record.get("ciReceipt")
        review = record.get("reviewReceipt")
        if (
            not isinstance(ci, dict)
            or ci.get("candidateCommit") != commit
            or ci.get("result") != "PASS"
        ):
            raise DeliveryError(f"{path.relative_to(project)}: exact-candidate PASS ciReceipt required")
        if not isinstance(review, dict):
            raise DeliveryError(f"{path.relative_to(project)}: structured reviewReceipt required")
        validate_review_receipt(review, candidate_commit=commit, record_path=path)
        if status == "MERGED_MAIN":
            merged = record.get("mergedMainCommit")
            if not merged:
                raise DeliveryError(f"{path.relative_to(project)}: mergedMainCommit required")
            run_git(project, "merge-base", "--is-ancestor", commit, merged)


def merge_base_paths(project: pathlib.Path, base: str, head: str) -> tuple[str, list[str]]:
    merge_base = run_git(project, "merge-base", base, head)
    output = run_git(
        project,
        "diff",
        "--name-only",
        "--diff-filter=ACDMRTUXB",
        f"{merge_base}..{head}",
        "--",
    )
    return merge_base, [
        line.strip().replace("\\", "/") for line in output.splitlines() if line.strip()
    ]


def infer_runtime_mission(project: pathlib.Path, head_branch: str, event: dict[str, Any]) -> str:
    claims = durable_claims(project)
    branch_matches = [
        mission for mission, claim in claims.items() if claim.get("branch") == head_branch
    ]
    if len(branch_matches) == 1:
        return branch_matches[0]
    body = (event.get("pull_request") or {}).get("body") or ""
    model = load_model(project)
    body_matches = [mission for mission in model["missions"] if mission in body]
    unique = sorted(set(branch_matches + body_matches))
    if len(unique) != 1:
        raise DeliveryError(f"cannot infer one runtime mission for {head_branch}: {unique}")
    return unique[0]


def strict_ownership(
    project: pathlib.Path,
    base: str,
    head: str,
    head_branch: str,
    event_path: pathlib.Path | None,
) -> dict[str, Any]:
    model = load_model(project)
    claims = durable_claims(project)
    leases = active_leases(project, model, claims)
    event = read_json(event_path) if event_path else {}
    mission = infer_runtime_mission(project, head_branch, event)
    merge_base, changed = merge_base_paths(project, base, head)
    result = classify_changed_paths(mission, changed, model)
    claim = claims.get(mission)
    owner_branch = claim is not None and claim.get("branch") == head_branch
    helpers = matching_helper_leases(leases, mission, head_branch)
    runtime_violations: list[str] = []

    if len(helpers) > 1:
        runtime_violations.append("AMBIGUOUS_MULTIPLE_HELPER_LEASES_FOR_BRANCH")
        helper = None
    else:
        helper = helpers[0] if helpers else None

    if helper is not None:
        try:
            verify_candidate_ancestry(project, helper["baseCommit"], head)
        except ValueError as exc:
            runtime_violations.append(f"HELPER_BASE_ANCESTRY_INVALID:{exc}")
        for path in changed:
            if not matches_any(path, helper["allowedPaths"]):
                runtime_violations.append(f"OUTSIDE_HELPER_LEASE:{path}")
    elif owner_branch:
        if claim.get("head") != head:
            runtime_violations.append(f"CLAIM_HEAD_STALE:{claim.get('head')}!=HEAD:{head}")
        claim_scope = claim.get("exclusivePaths") or model["config"]["missionPathPolicies"][mission]["owned"]
        generated = model["config"].get("commonGeneratedPaths", [])
        shared = [
            pattern
            for grant in model["config"].get("sharedPathGrants", [])
            if grant.get("requestingMission") == mission
            for pattern in grant.get("patterns", [])
        ]
        for path in changed:
            if not (
                matches_any(path, claim_scope)
                or matches_any(path, generated)
                or matches_any(path, shared)
            ):
                runtime_violations.append(f"OUTSIDE_CURRENT_CLAIM:{path}")
    else:
        runtime_violations.append("NO_CURRENT_MISSION_CLAIM_OR_HELPER_LEASE_FOR_BRANCH")

    result.update(
        {
            "mergeBase": merge_base,
            "head": head,
            "headBranch": head_branch,
            "runtimeLock": (
                "HELPER_LEASE"
                if helper
                else ("MISSION_CLAIM" if owner_branch else "NONE")
            ),
            "helperLeaseId": helper.get("leaseId") if helper else None,
            "runtimeViolations": runtime_violations,
        }
    )
    result["authorized"] = bool(result.get("authorized")) and not runtime_violations
    result["violations"] = sorted(
        set(result.get("violations", []) + runtime_violations)
    )
    return result


def append_only(project: pathlib.Path, base: str, head: str) -> None:
    model = load_model(project)
    root = model["config"]["recordsRoot"]
    merge_base = run_git(project, "merge-base", base, head)
    output = run_git(
        project,
        "diff",
        "--name-status",
        f"{merge_base}..{head}",
        "--",
        root,
        check=False,
    )
    violations = []
    for line in output.splitlines():
        if not line.strip():
            continue
        status = line.split("\t", 1)[0]
        if not status.startswith("A"):
            violations.append(line)
    if violations:
        raise DeliveryError(
            "delivery history is append-only; non-add changes: " + "; ".join(violations)
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("validate")
    append = sub.add_parser("append-only")
    append.add_argument("--base", required=True)
    append.add_argument("--head", required=True)
    ownership = sub.add_parser("ownership")
    ownership.add_argument("--base", required=True)
    ownership.add_argument("--head", required=True)
    ownership.add_argument("--head-branch", required=True)
    ownership.add_argument("--event-path")
    ownership.add_argument("--output")
    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    try:
        if args.command == "validate":
            validate_accepted_records(project)
            print("MISSION_DELIVERY_STRICT_VALID")
        elif args.command == "append-only":
            append_only(project, args.base, args.head)
            print("MISSION_DELIVERY_APPEND_ONLY_VALID")
        elif args.command == "ownership":
            result = strict_ownership(
                project,
                args.base,
                args.head,
                args.head_branch,
                pathlib.Path(args.event_path) if args.event_path else None,
            )
            if args.output:
                write_json(pathlib.Path(args.output), result)
            print(json.dumps(result, indent=2, sort_keys=True))
            if not result["authorized"]:
                raise DeliveryError("strict runtime ownership rejected candidate")
        return 0
    except Exception as exc:
        print(f"MISSION_DELIVERY_STRICT_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
