#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform as host_platform
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_center_contracts as canonical

REGISTRY = Path("config/test_center_registry.v1.json")
RATIONALES = Path("release/evidence/worker-a/test-center-v1/affected-mapping-rationales.json")
EVIDENCE_ROOT = Path("release/evidence/worker-a/test-center-v1")
GENERATED_ROOT = Path("release/evidence/generated/worker-a")
WORKER_MAPPING_PREFIXES = ("affected.p1.", "affected.p1a.", "affected.p2.", "affected.worker-a.")
RESULT_STATES = {
    "PASS", "FAIL", "ERROR", "SKIPPED", "BLOCKED", "UNKNOWN", "FLAKY", "NOT_IMPLEMENTED",
}
SOURCE_SUITE_DEFAULTS = (
    "tc.test-center.contracts",
    "tc.test-center.semantic-regressions",
    "tc.p1.exit-gate",
    "tc.p1a.exit-gate",
    "tc.p2.source-inventory",
    "tc.p2.application-composition",
    "tc.p2.acceptance-contract",
    "tc.p2.evidence-contract",
    "tc.p2.runner-attestation",
    "tc.p2.cleanup-contract",
    "tc.p2.strict-finalizer",
    "tc.worker-a.canonical-integration",
)


class WorkerAContractError(RuntimeError):
    pass


def _canonical_json(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


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
    if not re.fullmatch(r"[0-9a-f]{40}", commit) or not re.fullmatch(r"[0-9a-f]{40}", tree):
        raise WorkerAContractError("invalid Git candidate identity")
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
    untracked = _git(project, "ls-files", "--others", "--exclude-standard", "-z", text=False)
    assert isinstance(status, bytes) and isinstance(diff, bytes) and isinstance(untracked, bytes)
    return {
        "clean": not status and not diff and not untracked,
        "statusSha256": _sha256(status),
        "diffSha256": _sha256(diff),
        "untrackedSha256": _sha256(untracked),
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
    return "any"


def _runner_identity(platform_name: str) -> dict[str, str]:
    provider = "github-actions" if os.environ.get("GITHUB_ACTIONS") == "true" else "local"
    runner_id = os.environ.get("RUNNER_NAME") or os.environ.get("GITHUB_RUN_ID") or "local"
    image = os.environ.get("ImageOS") or os.environ.get("RUNNER_OS") or platform_name
    architecture = os.environ.get("RUNNER_ARCH") or host_platform.machine() or "unknown"
    return {
        "provider": provider,
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
    return {"digest": _sha256(_canonical_json(components)), "components": components}


def _environment_identity(profile: Mapping[str, Any]) -> dict[str, Any]:
    values = {
        key: os.environ[key]
        for key in profile["environmentAllowlist"]
        if key in os.environ
    }
    return {"digest": _sha256(_canonical_json(values)), "allowlisted": values}


def _safe_slug(value: str) -> str:
    return re.sub(r"[^a-z0-9._-]+", "-", value.lower()).strip("-") or "record"


def _validate_schema_def(project: Path, def_name: str, value: Any) -> None:
    schema = _load(project / canonical.SCHEMA_RELATIVE)
    member = schema["$defs"][def_name]
    errors = canonical._schema_errors(value, member, schema)
    if errors:
        raise WorkerAContractError(
            f"{def_name} schema validation failed: {json.dumps(errors, sort_keys=True)}"
        )


def validate_rationales(project: Path, registry: Mapping[str, Any]) -> None:
    document = _load(project / RATIONALES)
    rows = document.get("mappings")
    if document.get("schemaVersion") != "1.0.0" or not isinstance(rows, list):
        raise WorkerAContractError("invalid Worker A affected-mapping rationale document")
    by_id = {row.get("mappingId"): row for row in rows if isinstance(row, Mapping)}
    if len(by_id) != len(rows):
        raise WorkerAContractError("duplicate or invalid mapping rationale")
    canonical_ids = {
        mapping["mappingId"]
        for mapping in registry["affectedTestMappings"]
        if mapping["mappingId"].startswith(WORKER_MAPPING_PREFIXES)
    }
    if set(by_id) != canonical_ids:
        raise WorkerAContractError(
            f"mapping rationale coverage mismatch: canonical={sorted(canonical_ids)} "
            f"rationales={sorted(by_id)}"
        )
    for mapping_id, row in sorted(by_id.items()):
        reason = row.get("reason")
        if not isinstance(reason, str) or len(reason.strip()) < 20:
            raise WorkerAContractError(f"mapping rationale too weak: {mapping_id}")


def validate_order_independence(registry: Mapping[str, Any]) -> dict[str, Any]:
    sets = [
        [
            "tool/p2_platform_ci.py",
            "config/test_center_registry.v1.json",
            "config/signed_manifest_v2.json",
        ],
        [
            "release/evidence/P2/manifest.json",
            "tool/p1a_exit_gate_test.py",
            "tool/worker_a_test_center_v1.py",
        ],
    ]
    observations = []
    for changed in sets:
        forward = canonical.select_affected_tests(
            changed, registry["affectedTestMappings"]
        )
        reverse = canonical.select_affected_tests(
            list(reversed(changed)), list(reversed(registry["affectedTestMappings"]))
        )
        if forward != reverse:
            raise WorkerAContractError(
                f"order-dependent selection: {changed!r}: {forward!r} != {reverse!r}"
            )
        observations.append({"changedPaths": sorted(changed), "selectedTestIds": forward})
    return {"status": "PASS", "observations": observations}


def _validate_execution_document(project: Path, document: Mapping[str, Any]) -> None:
    _validate_schema_def(project, "DevelopmentVerificationResult", document)
    for result in document["results"]:
        canonical.validate_test_execution_result(result)
    if document["overallState"] not in RESULT_STATES:
        raise WorkerAContractError("unknown Development Verification result state")


def _validate_certification_document(project: Path, document: Mapping[str, Any]) -> None:
    records = document.get("certificationRecords")
    if document.get("schemaVersion") != "1.0.0" or not isinstance(records, list):
        raise WorkerAContractError("invalid certification document")
    for record in records:
        _validate_schema_def(project, "CertificationRecord", record)
        canonical.validate_certification(record)


def validate_evidence_documents(project: Path) -> dict[str, int]:
    counts = {"execution": 0, "certification": 0}
    if not (project / EVIDENCE_ROOT).is_dir():
        return counts
    for path in sorted((project / EVIDENCE_ROOT).glob("*.execution.json")):
        _validate_execution_document(project, _load(path))
        counts["execution"] += 1
    for path in sorted((project / EVIDENCE_ROOT).glob("*.certification.json")):
        _validate_certification_document(project, _load(path))
        counts["certification"] += 1
    return counts


def check_project(project: Path) -> dict[str, Any]:
    project = project.resolve()
    canonical_report = canonical.validate_project(project)
    registry = _load(project / REGISTRY)
    validate_rationales(project, registry)
    deterministic = validate_order_independence(registry)
    evidence_counts = validate_evidence_documents(project)
    review = _load(
        project
        / "docs/roadmap/anarchy/reviews/WORKER_B_A_REVIEW_345847c.json"
    )
    if (
        review.get("decision") != "REQUEST_CHANGES"
        or review.get("reviewedCommit")
        != "345847cb06b3123f2841bdface68a6615cd5de42"
        or review.get("reviewedTree")
        != "10345698dea33222955cce23e5c45e59459f626f"
    ):
        raise WorkerAContractError("immutable Worker B review history changed")
    result = {
        "schemaVersion": "1.0.0",
        "status": "PASS",
        "checkMode": "NON_MUTATING",
        "canonicalRegistrySha256": canonical_report["registrySha256"],
        "workerModuleCount": sum(
            module["moduleId"].startswith(("tm.p1.", "tm.p1a.", "tm.p2.", "tm.worker-a."))
            for module in registry["testModules"]
        ),
        "workerTestCount": sum(
            case["testId"].startswith(("tc.p1.", "tc.p1a.", "tc.p2.", "tc.worker-a."))
            for case in registry["testCases"]
        ),
        "workerMappingCount": sum(
            mapping["mappingId"].startswith(WORKER_MAPPING_PREFIXES)
            for mapping in registry["affectedTestMappings"]
        ),
        "deterministicSelection": deterministic["observations"],
        "validatedEvidenceDocuments": evidence_counts,
        "preservedReviewDecision": "REQUEST_CHANGES",
    }
    return result


def _profile_map(registry: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    return {profile["stableCheckId"]: profile for profile in registry["projectTestProfiles"]}


def _case_map(registry: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    return {case["testId"]: case for case in registry["testCases"]}


def run_profile(
    project: Path,
    profile: Mapping[str, Any],
    case: Mapping[str, Any],
    platform_name: str,
    generated_dir: Path,
) -> dict[str, Any]:
    commit, tree = _candidate_identity(project)
    branch = _branch_identity(project)
    started = datetime.now(timezone.utc)
    started_mono = time.monotonic()
    try:
        completed = subprocess.run(
            list(profile["argv"]),
            cwd=project / profile["workingDirectory"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=int(profile["timeoutSeconds"]),
            check=False,
            env=os.environ.copy(),
        )
        exit_code: int | None = completed.returncode
        output = completed.stdout or ""
        result_state = "PASS" if completed.returncode == 0 else "FAIL"
        failure = "NONE" if completed.returncode == 0 else "ASSERTION"
    except subprocess.TimeoutExpired as exc:
        exit_code = None
        output = (exc.stdout or "") + (exc.stderr or "")
        result_state = "ERROR"
        failure = "TIMEOUT"
    except OSError as exc:
        exit_code = None
        output = f"{type(exc).__name__}: {exc}\n"
        result_state = "ERROR"
        failure = "INFRASTRUCTURE"
    ended = datetime.now(timezone.utc)
    _ = started_mono  # retained to make execution sequencing explicit
    duration = int((ended - started).total_seconds() * 1000)
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
        "evidenceId": "evidence." + _safe_slug(result_id.removeprefix("result.")) + ".log",
        "kind": "LOG",
        "uri": (
            "artifact://worker-a-test-center-"
            + run_id
            + "/"
            + platform_name
            + "/"
            + log_path.name
        ),
        "sha256": _sha256(log_bytes),
        "immutable": True,
        "commit": commit,
        "tree": tree,
        "createdAt": ended.isoformat().replace("+00:00", "Z"),
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
        "workingTreeIdentity": _working_tree_identity(project),
        "platform": platform_name,
        "runner": _runner_identity(platform_name),
        "toolchain": _toolchain_identity(),
        "environment": _environment_identity(profile),
        "startedAt": started.isoformat().replace("+00:00", "Z"),
        "endedAt": ended.isoformat().replace("+00:00", "Z"),
        "durationMillis": duration,
        "resultState": result_state,
        "exitCode": exit_code,
        "assuranceClass": profile["assuranceClass"],
        "evidenceReferences": [evidence],
        "cleanupState": "NOT_REQUIRED",
        "failureClassification": failure,
        "certificationImpact": "NONE" if result_state == "PASS" else "BLOCKS_SCOPE",
    }
    canonical.validate_test_execution_result(result)
    _validate_schema_def(project, "TestExecutionResult", result)
    return result


def run_suite(
    project: Path,
    platform_name: str,
    output: Path,
    test_ids: Sequence[str],
) -> dict[str, Any]:
    project = project.resolve()
    registry = _load(project / REGISTRY)
    canonical.validate_registry(registry)
    profiles = _profile_map(registry)
    cases = _case_map(registry)
    selected = list(test_ids or SOURCE_SUITE_DEFAULTS)
    missing = sorted(set(selected) - set(profiles))
    if missing:
        raise WorkerAContractError(f"unknown stable test IDs: {missing}")
    results = [
        run_profile(project, profiles[test_id], cases[test_id], platform_name, project / GENERATED_ROOT)
        for test_id in selected
    ]
    commit, tree = _candidate_identity(project)
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    overall = "PASS" if all(result["resultState"] == "PASS" for result in results) else "FAIL"
    request = {
        "requestId": "verify-request.worker-a." + _safe_slug(commit[:12]),
        "candidateCommit": commit,
        "candidateTree": tree,
        "branch": _branch_identity(project),
        "workingTreeIdentity": _working_tree_identity(project),
        "changedPaths": [
            "config/test_center_registry.v1.json",
            "tool/worker_a_test_center_v1.py",
            "tool/worker_a_test_center_v1_test.py",
        ],
        "requestedSurfaces": [
            "QUICK_CHECK",
            "DEVELOPMENT_VERIFICATION",
            "AFFECTED_TESTS",
            "EVIDENCE",
        ],
        "profileIds": selected,
        "platformMatrix": {"required": ["linux", "macos", "windows"], "observed": [platform_name]},
        "exactShaRequired": True,
        "nonMutating": True,
    }
    document = {
        "verificationId": "verification.worker-a." + _safe_slug(commit[:12]) + "." + platform_name,
        "request": request,
        "selectedTestIds": selected,
        "results": results,
        "certificationRecords": [],
        "generatedAt": now,
        "overallState": overall,
    }
    _validate_execution_document(project, document)
    target = (project / output).resolve()
    target.relative_to(project)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(_canonical_json(document))
    return document


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    check = sub.add_parser("check")
    check.add_argument("--project", type=Path, default=Path("."))
    run = sub.add_parser("run-source-suite")
    run.add_argument("--project", type=Path, default=Path("."))
    run.add_argument("--platform", choices=["linux", "macos", "windows"], required=True)
    run.add_argument("--output", type=Path, required=True)
    run.add_argument("--test", dest="tests", action="append", default=[])
    validate = sub.add_parser("validate-execution")
    validate.add_argument("--project", type=Path, default=Path("."))
    validate.add_argument("path", type=Path)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    try:
        if args.command == "check":
            report = check_project(args.project)
        elif args.command == "run-source-suite":
            report = run_suite(
                args.project,
                args.platform,
                args.output,
                args.tests or SOURCE_SUITE_DEFAULTS,
            )
        else:
            project = args.project.resolve()
            document = _load((project / args.path).resolve())
            _validate_execution_document(project, document)
            report = {"schemaVersion": "1.0.0", "status": "PASS", "path": str(args.path)}
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0
    except (
        WorkerAContractError,
        canonical.ContractError,
        KeyError,
        TypeError,
        ValueError,
        subprocess.CalledProcessError,
    ) as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, sort_keys=True), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
