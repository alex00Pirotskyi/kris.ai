#!/usr/bin/env python3
"""Canonical Test Center v1 adapter for Worker C's P4-001 source lane."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform as host_platform
import random
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, Sequence

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))
from tool import test_center_contracts as canonical

REGISTRY = Path("config/test_center_registry.v1.json")
SCHEMA = Path("schemas/test_center.v1.json")
HANDOFF = Path("release/evidence/P4-001/test-center-handoff.json")
HISTORICAL_HANDOFF = Path(
    "release/evidence/P4-001/history/test-center-handoff.provisional.0.1.1.json"
)
MODULE_ID = "tm.p4-001.search-provider-interface"
TASK_ID = "P4-001"
CANONICAL_STATUS = "CANONICAL_TEST_CENTER_V1"
P4_TEST_IDS = (
    "tc.p4-001.request-schema",
    "tc.p4-001.result-schema",
    "tc.p4-001.page-schema",
    "tc.p4-001.provider-error-schema",
    "tc.p4-001.url-fail-closed",
    "tc.p4-001.credential-rejection",
    "tc.p4-001.secret-normalization",
    "tc.p4-001.provider-metadata-isolation",
    "tc.p4-001.stable-query-identity",
    "tc.p4-001.stable-result-identity",
    "tc.p4-001.cursor-provider-binding",
    "tc.p4-001.capability-negotiation",
    "tc.p4-001.rate-limit-representation",
    "tc.p4-001.partial-failure-representation",
    "tc.p4-001.fixture-provider-parity",
    "tc.p4-001.network-free-determinism",
    "tc.p4-001.unfetched-snippet-classification",
    "tc.p4-001.normalized-result-state-preservation",
)
P4_MAPPING_IDS = (
    "affected.p4-001.request",
    "affected.p4-001.result-page",
    "affected.p4-001.provider",
    "affected.p4-001.cursor",
    "affected.p4-001.security-validation",
    "affected.p4-001.schemas",
    "affected.p4-001.fixtures",
    "affected.p4-001.workflow",
    "affected.p4-001.evidence",
)
CANONICAL_STATES = (
    "PASS",
    "FAIL",
    "ERROR",
    "SKIPPED",
    "BLOCKED",
    "UNKNOWN",
    "FLAKY",
    "NOT_IMPLEMENTED",
)
DEFAULT_CHANGED_PATHS = (
    "config/test_center_registry.v1.json",
    "release/evidence/P4-001/test-center-handoff.json",
    "tool/p4_001_search_provider_test.py",
    "tool/p4_001_test_center_v1.py",
    ".github/workflows/p4-001-search-provider.yml",
)


class P4001TestCenterError(RuntimeError):
    """Raised when P4-001 canonical integration violates the shared contract."""


def _canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _git(project: Path, *args: str, text: bool = True) -> str | bytes:
    completed = subprocess.run(
        ["git", "-C", str(project), *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=text,
    )
    return completed.stdout


def _candidate_identity(project: Path) -> tuple[str, str]:
    commit = str(_git(project, "rev-parse", "HEAD")).strip()
    tree = str(_git(project, "show", "-s", "--format=%T", "HEAD")).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise P4001TestCenterError("invalid candidate commit identity")
    if not re.fullmatch(r"[0-9a-f]{40}", tree):
        raise P4001TestCenterError("invalid candidate tree identity")
    return commit, tree


def _branch_identity(project: Path) -> str:
    for key in ("GITHUB_HEAD_REF", "GITHUB_REF_NAME"):
        value = os.environ.get(key, "").strip()
        if value:
            return value
    completed = subprocess.run(
        ["git", "-C", str(project), "symbolic-ref", "--short", "-q", "HEAD"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    return completed.stdout.strip() or "detached-exact-candidate"


def _working_tree_identity(project: Path) -> dict[str, Any]:
    status = _git(project, "status", "--porcelain=v1", "-z", text=False)
    diff = _git(project, "diff", "--binary", "--no-ext-diff", text=False)
    untracked = _git(
        project, "ls-files", "--others", "--exclude-standard", "-z", text=False
    )
    assert isinstance(status, bytes)
    assert isinstance(diff, bytes)
    assert isinstance(untracked, bytes)
    return {
        "clean": not status and not diff and not untracked,
        "statusSha256": _sha256_bytes(status),
        "diffSha256": _sha256_bytes(diff),
        "untrackedSha256": _sha256_bytes(untracked),
    }


def _platform_name(explicit: str | None = None) -> str:
    if explicit:
        return explicit
    value = host_platform.system().lower()
    if value == "darwin":
        return "macos"
    if value.startswith("win"):
        return "windows"
    if value == "linux":
        return "linux"
    raise P4001TestCenterError(f"unsupported canonical platform: {value}")


def _runner_identity(platform_name: str) -> dict[str, str]:
    provider = (
        "github-actions" if os.environ.get("GITHUB_ACTIONS") == "true" else "local"
    )
    runner_id = (
        os.environ.get("RUNNER_NAME")
        or os.environ.get("GITHUB_RUN_ID")
        or "local"
    )
    image = os.environ.get("ImageOS") or os.environ.get("RUNNER_OS") or platform_name
    architecture = os.environ.get("RUNNER_ARCH") or host_platform.machine() or "unknown"
    return {
        "provider": str(provider),
        "runnerId": str(runner_id),
        "image": str(image),
        "architecture": str(architecture),
    }


def _toolchain_identity() -> dict[str, Any]:
    components = {
        "python": host_platform.python_version(),
        "pythonImplementation": host_platform.python_implementation(),
        "platform": host_platform.platform(),
    }
    return {"digest": _sha256_bytes(_canonical_json(components)), "components": components}


def _environment_identity(profile: Mapping[str, Any]) -> dict[str, Any]:
    values = {
        key: os.environ[key]
        for key in profile["environmentAllowlist"]
        if key in os.environ
    }
    return {"digest": _sha256_bytes(_canonical_json(values)), "allowlisted": values}


def _safe_slug(value: str) -> str:
    return re.sub(r"[^a-z0-9._-]+", "-", value.lower()).strip("-") or "record"


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )


def _validate_schema_def(project: Path, def_name: str, value: Any) -> None:
    schema = _load(project / SCHEMA)
    member = schema["$defs"][def_name]
    errors = canonical._schema_errors(value, member, schema)
    if errors:
        raise P4001TestCenterError(
            f"{def_name} schema validation failed: {json.dumps(errors, sort_keys=True)}"
        )


def normalize_observed_state(value: str) -> str:
    """Preserve canonical Test Center state exactly; reject every other domain."""
    return canonical.normalize_result_state(value)


def _registry_maps(
    registry: Mapping[str, Any],
) -> tuple[dict[str, Mapping[str, Any]], dict[str, Mapping[str, Any]]]:
    profiles = {
        item["stableCheckId"]: item for item in registry["projectTestProfiles"]
    }
    cases = {item["testId"]: item for item in registry["testCases"]}
    return profiles, cases


def validate_registration(project: Path) -> dict[str, Any]:
    canonical_report = canonical.validate_project(project)
    registry = _load(project / REGISTRY)
    handoff = _load(project / HANDOFF)
    historical = _load(project / HISTORICAL_HANDOFF)
    modules = {
        item["moduleId"]: item for item in registry["testModules"]
    }
    if MODULE_ID not in modules:
        raise P4001TestCenterError("canonical P4-001 module registration is missing")
    case_ids = [
        item["testId"]
        for item in registry["testCases"]
        if item["moduleId"] == MODULE_ID
    ]
    profile_ids = [
        item["stableCheckId"]
        for item in registry["projectTestProfiles"]
        if item["stableCheckId"].startswith("tc.p4-001.")
    ]
    mapping_ids = [
        item["mappingId"]
        for item in registry["affectedTestMappings"]
        if item["mappingId"].startswith("affected.p4-001.")
    ]
    if tuple(case_ids) != P4_TEST_IDS:
        raise P4001TestCenterError(
            f"canonical P4 test case order/identity mismatch: {case_ids}"
        )
    if tuple(profile_ids) != P4_TEST_IDS:
        raise P4001TestCenterError(
            f"canonical P4 profile order/identity mismatch: {profile_ids}"
        )
    if tuple(mapping_ids) != P4_MAPPING_IDS:
        raise P4001TestCenterError(
            f"canonical P4 affected mapping mismatch: {mapping_ids}"
        )
    if handoff.get("canonicalContractStatus") != CANONICAL_STATUS:
        raise P4001TestCenterError("canonical handoff status mismatch")
    if handoff.get("moduleId") != MODULE_ID:
        raise P4001TestCenterError("canonical handoff module mismatch")
    if tuple(handoff.get("canonicalTestIds", [])) != P4_TEST_IDS:
        raise P4001TestCenterError("canonical handoff test IDs mismatch")
    aliases = handoff.get("provisionalIdAliases")
    if not isinstance(aliases, Mapping) or set(aliases.values()) != set(P4_TEST_IDS):
        raise P4001TestCenterError("provisional ID alias map is incomplete")
    historical_bytes = (project / HISTORICAL_HANDOFF).read_bytes()
    supersedes = handoff.get("supersedes")
    if (
        not isinstance(supersedes, Mapping)
        or supersedes.get("status") != "SUPERSEDED"
        or supersedes.get("historicalPath") != str(HISTORICAL_HANDOFF).replace("\\", "/")
        or supersedes.get("sha256") != _sha256_bytes(historical_bytes)
    ):
        raise P4001TestCenterError("historical handoff supersession is not immutable")
    if historical.get("canonicalContractStatus") != "BLOCKED_BY_SHARED_CONTRACT":
        raise P4001TestCenterError("historical provisional handoff was rewritten")
    return {
        "canonicalRegistrySha256": canonical_report["registrySha256"],
        "canonicalSchemaSha256": canonical_report["schemaSha256"],
        "moduleId": MODULE_ID,
        "testIds": list(P4_TEST_IDS),
        "mappingIds": list(P4_MAPPING_IDS),
        "historicalHandoffSha256": _sha256_bytes(historical_bytes),
    }


def validate_order_independence(registry: Mapping[str, Any]) -> list[dict[str, Any]]:
    changed_sets = (
        (
            "services/research_worker/src/search/models.py",
            "schemas/web_search_request.v1.json",
            "services/research_worker/src/search/fixture_provider.py",
        ),
        (
            "services/research_worker/src/search/validation.py",
            "schemas/web_search_page.v1.json",
            ".github/workflows/p4-001-search-provider.yml",
        ),
        (
            "release/evidence/P4-001/manifest.json",
            "tool/p4_001_test_center_v1.py",
            "services/research_worker/test/test_fixture_provider.py",
        ),
    )
    observations: list[dict[str, Any]] = []
    mappings = registry["affectedTestMappings"]
    for ordinal, changed in enumerate(changed_sets):
        expected = canonical.select_affected_tests(changed, mappings)
        reversed_result = canonical.select_affected_tests(
            reversed(changed), reversed(mappings)
        )
        shuffled_changed = list(changed)
        shuffled_mappings = list(mappings)
        random.Random(4001 + ordinal).shuffle(shuffled_changed)
        random.Random(4101 + ordinal).shuffle(shuffled_mappings)
        shuffled_result = canonical.select_affected_tests(
            shuffled_changed, shuffled_mappings
        )
        if expected != reversed_result or expected != shuffled_result:
            raise P4001TestCenterError(
                "affected-test selection depends on changed-path or mapping order"
            )
        observations.append(
            {
                "changedPaths": sorted(changed),
                "selectedTestIds": expected,
            }
        )
    return observations


def check_project(project: Path) -> dict[str, Any]:
    project = project.resolve()
    registration = validate_registration(project)
    registry = _load(project / REGISTRY)
    deterministic = validate_order_independence(registry)
    preserved = {state: normalize_observed_state(state) for state in CANONICAL_STATES}
    if tuple(preserved) != CANONICAL_STATES or any(
        key != value for key, value in preserved.items()
    ):
        raise P4001TestCenterError("canonical result state was coerced")
    return {
        "schemaVersion": "1.0.0",
        "status": "PASS",
        "checkMode": "NON_MUTATING",
        "canonicalContractStatus": CANONICAL_STATUS,
        "registration": registration,
        "deterministicSelection": deterministic,
        "statePreservation": preserved,
        "capabilitySupport": "SOURCE_FOUNDATION",
        "certificationState": "NOT_EVALUATED",
        "behaviorSupportEstablished": False,
    }


def run_profile(
    project: Path,
    profile: Mapping[str, Any],
    case: Mapping[str, Any],
    platform_name: str,
    generated_dir: Path,
) -> dict[str, Any]:
    commit, tree = _candidate_identity(project)
    branch = _branch_identity(project)
    before = _working_tree_identity(project)
    started = datetime.now(timezone.utc)
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    try:
        completed = subprocess.run(
            list(profile["argv"]),
            cwd=project / profile["workingDirectory"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=int(profile["timeoutSeconds"]),
            check=False,
            env=env,
        )
        exit_code: int | None = completed.returncode
        output = completed.stdout or ""
        result_state = "PASS" if completed.returncode == 0 else "FAIL"
        failure = "NONE" if completed.returncode == 0 else "ASSERTION"
    except subprocess.TimeoutExpired as exc:
        exit_code = None
        stdout = exc.stdout.decode(errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode(errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        output = stdout + stderr
        result_state = "ERROR"
        failure = "TIMEOUT"
    except OSError as exc:
        exit_code = None
        output = f"{type(exc).__name__}: {exc}\n"
        result_state = "ERROR"
        failure = "INFRASTRUCTURE"
    ended = datetime.now(timezone.utc)
    duration = max(0, int((ended - started).total_seconds() * 1000))
    after = _working_tree_identity(project)
    cleanup_state = "CLEAN" if before == after and after["clean"] else "DIRTY"
    if cleanup_state == "DIRTY" and result_state == "PASS":
        result_state = "ERROR"
        failure = "CLEANUP"
        exit_code = None

    run_id = _safe_slug(os.environ.get("GITHUB_RUN_ID", "local"))
    result_id = (
        "result."
        + _safe_slug(profile["stableCheckId"].removeprefix("tc."))
        + "."
        + platform_name
        + "."
        + run_id
    )
    log_dir = generated_dir / platform_name
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / f"{result_id}.log"
    log_bytes = output.encode("utf-8", errors="replace")
    log_path.write_bytes(log_bytes)
    evidence = {
        "evidenceId": (
            "evidence."
            + _safe_slug(result_id.removeprefix("result."))
            + ".log"
        ),
        "kind": "LOG",
        "uri": (
            "artifact://p4-001-canonical-"
            + run_id
            + "/"
            + platform_name
            + "/"
            + log_path.name
        ),
        "sha256": _sha256_bytes(log_bytes),
        "immutable": True,
        "commit": commit,
        "tree": tree,
        "createdAt": ended.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "mediaType": "text/plain; charset=utf-8",
    }
    result = {
        "resultId": result_id,
        "testId": profile["stableCheckId"],
        "moduleId": case["moduleId"],
        "roadmapTaskIds": case["roadmapTaskIds"],
        "commit": commit,
        "tree": tree,
        "branch": branch,
        "workingTreeIdentity": before,
        "platform": platform_name,
        "runner": _runner_identity(platform_name),
        "toolchain": _toolchain_identity(),
        "environment": _environment_identity(profile),
        "startedAt": started.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "endedAt": ended.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "durationMillis": duration,
        "resultState": normalize_observed_state(result_state),
        "exitCode": exit_code,
        "assuranceClass": profile["assuranceClass"],
        "evidenceReferences": [evidence],
        "cleanupState": cleanup_state,
        "failureClassification": failure,
        "certificationImpact": (
            "INFORMATIONAL" if result_state == "PASS" else "BLOCKS_SCOPE"
        ),
    }
    canonical.validate_test_execution_result(result)
    _validate_schema_def(project, "TestExecutionResult", result)
    return result


def _unique_evidence(results: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    by_id: dict[str, dict[str, Any]] = {}
    for result in results:
        for evidence in result["evidenceReferences"]:
            by_id[evidence["evidenceId"]] = dict(evidence)
    return [by_id[key] for key in sorted(by_id)]


def build_bundle(
    project: Path,
    platform_name: str,
    generated_dir: Path,
    test_ids: Sequence[str],
    changed_paths: Sequence[str],
) -> dict[str, Any]:
    project = project.resolve()
    check_project(project)
    registry = _load(project / REGISTRY)
    profiles, cases = _registry_maps(registry)
    selected = list(test_ids or P4_TEST_IDS)
    unknown = sorted(set(selected) - set(P4_TEST_IDS))
    if unknown:
        raise P4001TestCenterError(f"unknown P4 canonical test IDs: {unknown}")
    results = [
        run_profile(
            project,
            profiles[test_id],
            cases[test_id],
            platform_name,
            generated_dir,
        )
        for test_id in selected
    ]
    commit, tree = _candidate_identity(project)
    branch = _branch_identity(project)
    generated_at = _utc_now()
    overall = (
        "PASS" if all(item["resultState"] == "PASS" for item in results) else "FAIL"
    )
    evidence = _unique_evidence(results)
    request = {
        "requestId": (
            "verify-request.p4-001."
            + _safe_slug(commit[:12])
            + "."
            + platform_name
        ),
        "candidateCommit": commit,
        "candidateTree": tree,
        "branch": branch,
        "workingTreeIdentity": _working_tree_identity(project),
        "changedPaths": sorted(set(changed_paths or DEFAULT_CHANGED_PATHS)),
        "requestedSurfaces": [
            "QUICK_CHECK",
            "DEVELOPMENT_VERIFICATION",
            "AFFECTED_TESTS",
            "PLATFORM_CERTIFICATION",
            "EVIDENCE",
        ],
        "profileIds": selected,
        "platformMatrix": {
            "required": ["linux", "macos", "windows"],
            "observed": [platform_name],
        },
        "exactShaRequired": True,
        "nonMutating": True,
    }
    certification = {
        "certificationId": (
            "cert.p4-001.source-contract."
            + _safe_slug(commit[:12])
            + "."
            + platform_name
        ),
        "candidateCommit": commit,
        "candidateTree": tree,
        "scope": (
            "P4-001 provider-neutral source contract only; live provider behavior, "
            "network retrieval, fetch, browser automation, citations, datasets, "
            "platform behavior, and release support are excluded."
        ),
        "requiredTestIds": selected,
        "observedResults": results,
        "platformMatrix": {
            "required": ["linux", "macos", "windows"],
            "observed": [platform_name],
        },
        "evidenceBindings": evidence,
        "status": "PARTIAL",
        "staleness": {
            "isStale": False,
            "evaluatedAt": generated_at,
            "reason": (
                "Exact candidate source result; tri-platform aggregation and "
                "independent reviews remain pending."
            ),
        },
        "findings": [
            {
                "findingId": "p4-001.source-only-boundary",
                "severity": "INFO",
                "summary": (
                    "Source-contract execution cannot establish live provider, "
                    "behavioral, platform, or release support."
                ),
                "disposition": "OPEN",
            }
        ],
        "supportImpact": "BLOCKS_BEHAVIOR_SUPPORT",
    }
    verification = {
        "verificationId": (
            "verification.p4-001."
            + _safe_slug(commit[:12])
            + "."
            + platform_name
        ),
        "request": request,
        "selectedTestIds": selected,
        "results": results,
        "certificationRecords": [certification],
        "generatedAt": generated_at,
        "overallState": overall,
    }
    capability = {
        "supportRecordId": (
            "support.p4-001.search-provider-interface."
            + _safe_slug(commit[:12])
            + "."
            + platform_name
        ),
        "capabilityId": "search-provider-interface",
        "candidateCommit": commit,
        "candidateTree": tree,
        "status": "SOURCE_FOUNDATION",
        "supportedPlatforms": [platform_name],
        "evidenceBindings": evidence,
        "lastReviewedAt": generated_at,
        "rationale": (
            "The exact candidate implements and verifies only the provider-neutral "
            "source contract. External-provider behavior and network retrieval are "
            "not implemented or certified."
        ),
    }
    presentation = {
        "presentationId": (
            "presentation.p4-001.search-provider-interface."
            + _safe_slug(commit[:12])
            + "."
            + platform_name
        ),
        "surface": "DEVELOPMENT_VERIFICATION",
        "displayName": "P4-001 Search Provider Interface",
        "purpose": (
            "Present exact-candidate source-contract results without converting "
            "source PASS into behavioral or release support."
        ),
        "phase": "P4",
        "capability": "Provider-neutral search source foundation",
        "assuranceClass": "source_contract",
        "platformMatrix": {
            "required": ["linux", "macos", "windows"],
            "observed": [platform_name],
        },
        "stateDomain": "TEST_EXECUTION",
        "currentState": overall,
        "lastExactCommitResult": {
            "commit": commit,
            "tree": tree,
            "resultState": overall,
        },
        "staleResultWarning": False,
        "requiredNextAction": (
            "Aggregate exact-head linux, macos, and windows evidence; obtain Worker B "
            "and Worker I exact-SHA decisions and Worker J no-conflict."
        ),
        "evidenceLinks": evidence,
        "certificationImpact": (
            "Certification remains PARTIAL; behavior and release support are not established."
        ),
        "supportClaimImpact": (
            "SOURCE_FOUNDATION only. Live search, fetch, browser automation, "
            "citations, datasets, platform behavior, release support, production "
            "readiness, and GA readiness remain unsupported."
        ),
    }
    bundle = {
        "schemaVersion": "1.0.0",
        "taskId": TASK_ID,
        "canonicalContractStatus": CANONICAL_STATUS,
        "developmentVerificationRequest": request,
        "developmentVerificationResult": verification,
        "capabilitySupportRecord": capability,
        "certificationRecord": certification,
        "testingStudioPresentationRecord": presentation,
    }
    validate_bundle(project, bundle)
    return bundle


def validate_bundle(project: Path, bundle: Mapping[str, Any]) -> None:
    if bundle.get("canonicalContractStatus") != CANONICAL_STATUS:
        raise P4001TestCenterError("canonical bundle status mismatch")
    request = bundle["developmentVerificationRequest"]
    verification = bundle["developmentVerificationResult"]
    capability = bundle["capabilitySupportRecord"]
    certification = bundle["certificationRecord"]
    presentation = bundle["testingStudioPresentationRecord"]
    _validate_schema_def(project, "DevelopmentVerificationRequest", request)
    _validate_schema_def(project, "DevelopmentVerificationResult", verification)
    _validate_schema_def(project, "CapabilitySupportRecord", capability)
    _validate_schema_def(project, "CertificationRecord", certification)
    _validate_schema_def(project, "TestingStudioPresentationRecord", presentation)
    canonical.validate_certification(certification)
    if verification["request"] != request:
        raise P4001TestCenterError(
            "DevelopmentVerificationResult does not preserve its request"
        )
    if verification["certificationRecords"] != [certification]:
        raise P4001TestCenterError("certification record mismatch")
    if capability["status"] != "SOURCE_FOUNDATION":
        raise P4001TestCenterError("capability support was inflated")
    if certification["status"] not in {"PARTIAL", "NOT_EVALUATED"}:
        raise P4001TestCenterError("source-only certification was inflated")
    for result in verification["results"]:
        canonical.validate_test_execution_result(result)
        if (
            result["commit"] != request["candidateCommit"]
            or result["tree"] != request["candidateTree"]
        ):
            raise P4001TestCenterError("execution result belongs to another candidate")


def run_source_suite(
    project: Path,
    platform_name: str,
    output: Path,
    generated_dir: Path,
    test_ids: Sequence[str],
    changed_paths: Sequence[str],
) -> dict[str, Any]:
    bundle = build_bundle(
        project,
        platform_name,
        generated_dir,
        test_ids,
        changed_paths,
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(_canonical_json(bundle))
    return bundle


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    check = sub.add_parser("check")
    check.add_argument("--project", type=Path, default=Path("."))

    run = sub.add_parser("run-source-suite")
    run.add_argument("--project", type=Path, default=Path("."))
    run.add_argument(
        "--platform", choices=["linux", "macos", "windows"], required=True
    )
    run.add_argument("--output", type=Path, required=True)
    run.add_argument("--generated-dir", type=Path, required=True)
    run.add_argument("--test", dest="tests", action="append", default=[])
    run.add_argument(
        "--changed-path", dest="changed_paths", action="append", default=[]
    )

    validate = sub.add_parser("validate-records")
    validate.add_argument("--project", type=Path, default=Path("."))
    validate.add_argument("path", type=Path)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    try:
        project = args.project.resolve()
        if args.command == "check":
            report = check_project(project)
        elif args.command == "run-source-suite":
            output = args.output if args.output.is_absolute() else project / args.output
            generated_dir = (
                args.generated_dir
                if args.generated_dir.is_absolute()
                else project / args.generated_dir
            )
            report = run_source_suite(
                project,
                _platform_name(args.platform),
                output,
                generated_dir,
                args.tests or P4_TEST_IDS,
                args.changed_paths or DEFAULT_CHANGED_PATHS,
            )
        else:
            path = args.path if args.path.is_absolute() else project / args.path
            report = _load(path)
            validate_bundle(project, report)
            report = {
                "schemaVersion": "1.0.0",
                "status": "PASS",
                "path": str(path),
            }
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0
    except (
        P4001TestCenterError,
        canonical.ContractError,
        KeyError,
        TypeError,
        ValueError,
        OSError,
        subprocess.CalledProcessError,
    ) as exc:
        print(
            json.dumps({"status": "FAIL", "error": str(exc)}, sort_keys=True),
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
