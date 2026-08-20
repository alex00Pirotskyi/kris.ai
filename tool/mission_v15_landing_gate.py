#!/usr/bin/env python3
"""Protected-main source-landing truth gate for Mission Execution 1.5."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import subprocess
import sys
from typing import Any

from mission_delivery_lib import load_model, read_json, record_files, run_git
from mission_delivery_strict import ACCEPTED, validate_source_landing

PROMOTION_VALUES = {
    "SUPPORTED",
    "ESTABLISHED",
    "CERTIFIED",
    "PRODUCTION",
    "PRODUCTION_READY",
    "GA",
    "GA_READY",
    "READY",
    "PASS",
    "TRUE",
}
PROMOTION_FIELDS = {
    "capabilitySupport",
    "behavioralSupport",
    "platformSupport",
    "releaseSupport",
    "productionReadiness",
    "gaReadiness",
    "certification",
}
SHA_RE = __import__("re").compile(r"^[0-9a-f]{40}$")


class ExactLandingValidationError(ValueError):
    """Raised when an immutable exact-main landing request is not proven."""


def _promotes_without_acceptance(record: dict[str, Any]) -> list[str]:
    if record.get("sourceLanding") != "LANDED_MAIN" or record.get("status") in ACCEPTED:
        return []
    violations: list[str] = []
    if record.get("supportPromotion") is True:
        violations.append("supportPromotion=true")
    for field in sorted(PROMOTION_FIELDS):
        value = record.get(field)
        if value is None:
            continue
        if str(value).strip().upper().replace(" ", "_") in PROMOTION_VALUES:
            violations.append(f"{field}={value}")
    return violations


def validate_main_landing(project: pathlib.Path, main_commit: str) -> dict[str, Any]:
    run_git(project, "cat-file", "-e", f"{main_commit}^{{commit}}")
    model = load_model(project)
    landed: list[dict[str, Any]] = []
    violations: list[str] = []
    for path in record_files(project, model):
        record = read_json(path)
        if record.get("sourceLanding") != "LANDED_MAIN":
            continue
        try:
            validate_source_landing(project, record, path)
            merged = record.get("mergedMainCommit")
            run_git(project, "merge-base", "--is-ancestor", merged, main_commit)
        except Exception as exc:
            violations.append(f"{path.relative_to(project)}:{exc}")
            continue
        promotions = _promotes_without_acceptance(record)
        if promotions:
            violations.append(
                f"{path.relative_to(project)}:source-only landing contains support promotion: {promotions}"
            )
        landed.append(
            {
                "task": record.get("task"),
                "status": record.get("status"),
                "sourceCommit": record.get("commit"),
                "mergedMainCommit": merged,
                "path": path.relative_to(project).as_posix(),
            }
        )
    if violations:
        raise ValueError("; ".join(violations))
    return {
        "schemaVersion": 1,
        "mainCommit": main_commit,
        "landedMainRecordCount": len(landed),
        "landedMainRecords": landed,
        "acceptedCountNotInferred": True,
    }


def _required_str(value: dict[str, Any], field: str) -> str:
    result = value.get(field)
    if not isinstance(result, str) or not result:
        raise ExactLandingValidationError(f"{field} must be a non-empty string")
    return result


def _required_sha(value: dict[str, Any], field: str) -> str:
    result = _required_str(value, field)
    if not SHA_RE.fullmatch(result):
        raise ExactLandingValidationError(f"{field} must be a lowercase 40-hex Git object ID")
    return result


def _required_int(value: dict[str, Any], field: str) -> int:
    result = value.get(field)
    if not isinstance(result, int) or isinstance(result, bool) or result <= 0:
        raise ExactLandingValidationError(f"{field} must be a positive integer")
    return result


def _parse_utc(value: str, field: str) -> dt.datetime:
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ExactLandingValidationError(f"{field} must be an ISO-8601 timestamp") from exc
    if parsed.tzinfo is None:
        raise ExactLandingValidationError(f"{field} must include a timezone")
    return parsed.astimezone(dt.timezone.utc)


def _load_object(path: pathlib.Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ExactLandingValidationError(f"{label} missing: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ExactLandingValidationError(f"{label} is invalid JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ExactLandingValidationError(f"{label} must contain a JSON object: {path}")
    return value


def _assert_equal(actual: Any, expected: Any, label: str) -> None:
    if actual != expected:
        raise ExactLandingValidationError(
            f"{label} mismatch: expected {expected!r}, got {actual!r}"
        )


def _git_exact(project: pathlib.Path, *args: str) -> str:
    try:
        return run_git(project, *args)
    except Exception as exc:
        raise ExactLandingValidationError(str(exc)) from exc


def _find_authority_event(
    runtime_project: pathlib.Path,
    work_order_id: str,
) -> dict[str, Any]:
    matches: list[dict[str, Any]] = []
    events_root = runtime_project / "runtime" / "events"
    for path in sorted(events_root.rglob("*.json")) if events_root.is_dir() else []:
        value = _load_object(path, "runtime event")
        if value.get("workOrderId") != work_order_id:
            continue
        if value.get("eventType") != "SEMAPHORE_ACQUIRED":
            continue
        payload = value.get("payload")
        if not isinstance(payload, dict) or payload.get("kind") != "INTEGRATION":
            continue
        matches.append(value)
    if len(matches) != 1:
        raise ExactLandingValidationError(
            f"expected exactly one integration authority event for {work_order_id}, found {len(matches)}"
        )
    return matches[0]


def _verify_runtime_authority(
    runtime_project: pathlib.Path,
    request: dict[str, Any],
    *,
    now: dt.datetime,
) -> dict[str, Any]:
    runtime_commit = _required_sha(request, "runtimeCommit")
    runtime_generation = _required_int(request, "runtimeGeneration")
    mission = _required_str(request, "mission")
    task = _required_str(request, "task")
    landing_work_order_id = _required_str(request, "landingWorkOrderId")
    landing_semaphore_id = _required_str(request, "landingSemaphoreId")
    product_pr = _required_int(request, "productPr")
    source_commit = _required_sha(request, "sourceCommit")
    source_tree = _required_sha(request, "sourceTree")
    landing_base = _required_sha(request, "landingBaseCommit")

    _assert_equal(
        _git_exact(runtime_project, "rev-parse", "HEAD"),
        runtime_commit,
        "runtime checkout HEAD",
    )
    meta = _load_object(runtime_project / "runtime" / "meta.json", "runtime meta")
    _assert_equal(meta.get("runtimeGeneration"), runtime_generation, "runtime generation")

    work_order_path = (
        runtime_project
        / "runtime"
        / "work-orders"
        / mission
        / f"{landing_work_order_id}.json"
    )
    work_order = _load_object(work_order_path, "landing Work Order")
    _assert_equal(work_order.get("workOrderId"), landing_work_order_id, "Work Order ID")
    _assert_equal(work_order.get("mission"), mission, "Work Order mission")
    _assert_equal(work_order.get("roadmapTask"), task, "Work Order task")
    _assert_equal(work_order.get("status"), "INTEGRATING", "Work Order status")
    _assert_equal(work_order.get("executionRole"), "INTEGRATOR", "Work Order role")
    _assert_equal(work_order.get("baseCommit"), source_commit, "Work Order source commit")
    _assert_equal(work_order.get("baseTree"), source_tree, "Work Order source tree")
    _assert_equal(work_order.get("parentProductPr"), product_pr, "Work Order Product PR")
    _assert_equal(
        work_order.get("activeSemaphoreId"),
        landing_semaphore_id,
        "Work Order active semaphore",
    )

    semaphore_path = (
        runtime_project
        / "runtime"
        / "semaphores"
        / mission
        / f"{landing_semaphore_id}.json"
    )
    semaphore = _load_object(semaphore_path, "landing semaphore")
    _assert_equal(semaphore.get("semaphoreId"), landing_semaphore_id, "semaphore ID")
    _assert_equal(semaphore.get("workOrderId"), landing_work_order_id, "semaphore Work Order")
    _assert_equal(semaphore.get("status"), "ACTIVE", "semaphore status")
    _assert_equal(semaphore.get("productPr"), product_pr, "semaphore Product PR")
    _assert_equal(semaphore.get("baseCommit"), source_commit, "semaphore source commit")
    _assert_equal(semaphore.get("baseTree"), source_tree, "semaphore source tree")
    expires_at = _parse_utc(_required_str(semaphore, "expiresAt"), "semaphore.expiresAt")
    if now >= expires_at:
        raise ExactLandingValidationError(
            f"landing semaphore expired at {expires_at.isoformat()}"
        )

    event = _find_authority_event(runtime_project, landing_work_order_id)
    payload = event["payload"]
    _assert_equal(event.get("runtimeGeneration"), runtime_generation, "authority event generation")
    _assert_equal(payload.get("expectedProductHead"), source_commit, "authority source commit")
    _assert_equal(payload.get("canonicalProductTree"), source_tree, "authority source tree")
    _assert_equal(payload.get("protectedMain"), landing_base, "authority landing base")
    _assert_equal(payload.get("productPr"), product_pr, "authority Product PR")
    _assert_equal(payload.get("mergeMethod"), "squash", "authority merge method")
    _assert_equal(payload.get("semaphoreId"), landing_semaphore_id, "authority semaphore")
    return {
        "runtimeCommit": runtime_commit,
        "runtimeGeneration": runtime_generation,
        "landingWorkOrderId": landing_work_order_id,
        "landingSemaphoreId": landing_semaphore_id,
        "authorityEventId": event.get("eventId"),
        "semaphoreExpiresAt": expires_at.isoformat().replace("+00:00", "Z"),
    }


def _verify_git_landing(project: pathlib.Path, request: dict[str, Any]) -> dict[str, Any]:
    source_commit = _required_sha(request, "sourceCommit")
    source_tree = _required_sha(request, "sourceTree")
    source_branch = _required_str(request, "sourceBranch")
    landing_base = _required_sha(request, "landingBaseCommit")
    merged_main = _required_sha(request, "mergedMainCommit")
    merged_tree = _required_sha(request, "mergedMainTree")

    _assert_equal(_git_exact(project, "rev-parse", "HEAD"), merged_main, "target HEAD")
    _git_exact(project, "cat-file", "-e", f"{source_commit}^{{commit}}")
    _git_exact(project, "cat-file", "-e", f"{merged_main}^{{commit}}")
    _assert_equal(
        _git_exact(project, "rev-parse", f"{source_commit}^{{tree}}"),
        source_tree,
        "source tree",
    )
    _assert_equal(
        _git_exact(project, "rev-parse", f"{merged_main}^{{tree}}"),
        merged_tree,
        "merged-main tree",
    )
    _assert_equal(merged_tree, source_tree, "squash tree equivalence")

    parents = _git_exact(project, "rev-list", "--parents", "-n", "1", merged_main).split()
    if parents != [merged_main, landing_base]:
        raise ExactLandingValidationError(
            f"merged main must be a one-parent squash-equivalent commit over {landing_base}; got {parents}"
        )
    _git_exact(project, "merge-base", "--is-ancestor", landing_base, merged_main)

    remote_source = f"refs/remotes/origin/{source_branch}"
    _assert_equal(
        _git_exact(project, "rev-parse", remote_source),
        source_commit,
        "source branch head",
    )
    return {
        "sourceBranch": source_branch,
        "sourceCommit": source_commit,
        "sourceTree": source_tree,
        "landingBaseCommit": landing_base,
        "mergedMainCommit": merged_main,
        "mergedMainTree": merged_tree,
        "landingMode": "TREE_EQUIVALENT_LINEAR_V1",
    }


def _verify_pr(pr: dict[str, Any], request: dict[str, Any]) -> dict[str, Any]:
    product_pr = _required_int(request, "productPr")
    source_commit = _required_sha(request, "sourceCommit")
    landing_base = _required_sha(request, "landingBaseCommit")
    merged_main = _required_sha(request, "mergedMainCommit")

    _assert_equal(pr.get("number"), product_pr, "PR number")
    _assert_equal(pr.get("state"), "closed", "PR state")
    if pr.get("merged") is not True or not pr.get("merged_at"):
        raise ExactLandingValidationError("Product PR is not recorded as merged")
    _assert_equal(pr.get("merge_commit_sha"), merged_main, "PR merged-main commit")
    head = pr.get("head")
    base = pr.get("base")
    if not isinstance(head, dict) or not isinstance(base, dict):
        raise ExactLandingValidationError("PR head/base metadata missing")
    _assert_equal(head.get("sha"), source_commit, "PR source head")
    _assert_equal(base.get("sha"), landing_base, "PR landing base")
    return {
        "productPr": product_pr,
        "mergedAt": pr.get("merged_at"),
        "mergeCommit": merged_main,
    }


def _verify_product_gates(
    run: dict[str, Any],
    jobs_document: dict[str, Any],
    request: dict[str, Any],
) -> dict[str, Any]:
    run_id = _required_int(request, "productGatesRun")
    merged_main = _required_sha(request, "mergedMainCommit")
    expected_jobs = request.get("expectedJobs")
    if not isinstance(expected_jobs, list) or len(expected_jobs) != 3:
        raise ExactLandingValidationError("expectedJobs must contain exactly three jobs")

    _assert_equal(run.get("id"), run_id, "product-gates run ID")
    _assert_equal(run.get("name"), "product-gates", "workflow name")
    _assert_equal(run.get("head_sha"), merged_main, "product-gates head")
    _assert_equal(run.get("event"), "push", "product-gates event")
    _assert_equal(run.get("status"), "completed", "product-gates status")
    _assert_equal(run.get("conclusion"), "success", "product-gates conclusion")

    jobs = jobs_document.get("jobs")
    if not isinstance(jobs, list):
        raise ExactLandingValidationError("workflow jobs document missing jobs list")
    actual_by_name: dict[str, dict[str, Any]] = {}
    for item in jobs:
        if not isinstance(item, dict) or not isinstance(item.get("name"), str):
            raise ExactLandingValidationError("workflow job metadata is malformed")
        actual_by_name[item["name"]] = item
    expected_names = {"validate-ubuntu", "validate-windows", "validate-macos"}
    if set(actual_by_name) != expected_names:
        raise ExactLandingValidationError(
            f"product-gates jobs mismatch: expected {sorted(expected_names)}, got {sorted(actual_by_name)}"
        )

    receipt_jobs: list[dict[str, Any]] = []
    seen_names: set[str] = set()
    for expected in expected_jobs:
        if not isinstance(expected, dict):
            raise ExactLandingValidationError("expectedJobs entries must be objects")
        name = _required_str(expected, "name")
        job_id = _required_int(expected, "id")
        if name in seen_names:
            raise ExactLandingValidationError(f"duplicate expected job name: {name}")
        seen_names.add(name)
        actual = actual_by_name.get(name)
        if actual is None:
            raise ExactLandingValidationError(f"expected job missing: {name}")
        _assert_equal(actual.get("id"), job_id, f"{name} job ID")
        _assert_equal(actual.get("head_sha"), merged_main, f"{name} head")
        _assert_equal(actual.get("status"), "completed", f"{name} status")
        _assert_equal(actual.get("conclusion"), "success", f"{name} conclusion")
        receipt_jobs.append({"id": job_id, "name": name, "conclusion": "success"})
    _assert_equal(seen_names, expected_names, "expected job names")
    return {"runId": run_id, "workflow": "product-gates", "jobs": receipt_jobs}


def _verify_source_manifest(project: pathlib.Path) -> dict[str, Any]:
    manifest = project / "SOURCE_MANIFEST.sha256"
    generator = project / "tool" / "p1a_refresh_source_manifest.py"
    if not manifest.is_file() or not generator.is_file():
        raise ExactLandingValidationError(
            "target checkout lacks SOURCE_MANIFEST.sha256 or its canonical generator"
        )
    before = manifest.read_bytes()
    before_status = _git_exact(project, "status", "--porcelain=v1")
    if before_status:
        raise ExactLandingValidationError(
            f"target checkout was dirty before manifest validation: {before_status}"
        )
    for _ in range(2):
        result = subprocess.run(
            [sys.executable, generator.relative_to(project).as_posix(), "."],
            cwd=project,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0:
            raise ExactLandingValidationError(
                f"source-manifest generator failed ({result.returncode}): {result.stderr.strip()}"
            )
        if manifest.read_bytes() != before:
            raise ExactLandingValidationError(
                "canonical source-manifest regeneration changed the landed manifest"
            )
    after_status = _git_exact(project, "status", "--porcelain=v1")
    if after_status:
        raise ExactLandingValidationError(
            f"manifest validation mutated target checkout: {after_status}"
        )
    return {
        "path": "SOURCE_MANIFEST.sha256",
        "sha256": hashlib.sha256(before).hexdigest(),
        "regeneratedTwiceByteIdentical": True,
        "targetCheckoutUnmodified": True,
    }


def validate_exact_main_landing(
    project: pathlib.Path,
    runtime_project: pathlib.Path,
    request_path: pathlib.Path,
    pr_path: pathlib.Path,
    run_path: pathlib.Path,
    jobs_path: pathlib.Path,
    *,
    now: dt.datetime | None = None,
) -> dict[str, Any]:
    request = _load_object(request_path, "exact landing request")
    _assert_equal(request.get("schemaVersion"), 1, "request schemaVersion")
    request_id = _required_str(request, "requestId")
    now = now or dt.datetime.now(dt.timezone.utc)
    if now.tzinfo is None:
        now = now.replace(tzinfo=dt.timezone.utc)
    now = now.astimezone(dt.timezone.utc)

    runtime_receipt = _verify_runtime_authority(runtime_project, request, now=now)
    git_receipt = _verify_git_landing(project, request)
    pr_receipt = _verify_pr(_load_object(pr_path, "Product PR receipt"), request)
    gates_receipt = _verify_product_gates(
        _load_object(run_path, "product-gates run receipt"),
        _load_object(jobs_path, "product-gates jobs receipt"),
        request,
    )
    manifest_receipt = _verify_source_manifest(project)

    return {
        "schemaVersion": 1,
        "kind": "MISSION_V15_EXACT_MAIN_LANDING_RECEIPT",
        "requestId": request_id,
        "validatedAt": now.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "controlCommit": os.environ.get("GITHUB_SHA"),
        "mission": _required_str(request, "mission"),
        "task": _required_str(request, "task"),
        "acceptedCountNotInferred": True,
        "supportPromotionNotInferred": True,
        "runtime": runtime_receipt,
        "git": git_receipt,
        "pullRequest": pr_receipt,
        "productGates": gates_receipt,
        "sourceManifest": manifest_receipt,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--main-commit")
    parser.add_argument("--runtime-project")
    parser.add_argument("--exact-request")
    parser.add_argument("--pr-json")
    parser.add_argument("--run-json")
    parser.add_argument("--jobs-json")
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        project = pathlib.Path(args.project).resolve()
        if args.exact_request:
            required = {
                "--runtime-project": args.runtime_project,
                "--pr-json": args.pr_json,
                "--run-json": args.run_json,
                "--jobs-json": args.jobs_json,
            }
            missing = [name for name, value in required.items() if not value]
            if missing:
                raise ExactLandingValidationError(
                    f"exact mode missing required arguments: {', '.join(missing)}"
                )
            result = validate_exact_main_landing(
                project,
                pathlib.Path(args.runtime_project).resolve(),
                pathlib.Path(args.exact_request).resolve(),
                pathlib.Path(args.pr_json).resolve(),
                pathlib.Path(args.run_json).resolve(),
                pathlib.Path(args.jobs_json).resolve(),
            )
        else:
            if not args.main_commit:
                raise ValueError("--main-commit is required outside exact-request mode")
            result = validate_main_landing(project, args.main_commit)
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_LANDING_GATE_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
