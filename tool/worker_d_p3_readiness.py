#!/usr/bin/env python3
"""Validate Worker D P3 readiness records without mutating the repository."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path, PurePosixPath

STAGE1_COMMIT = "e7dee26404a11f076206251f619bfc3f9078753c"
STAGE1_TREE = "27a2d09ed4ed1d61775a74bccd6eac5aa4b739c6"
STAGE1_BASE_COMMIT = "d3452aa224c3228a9a3e3155a896e828af8d9ded"
STAGE1_BASE_TREE = "d6717a2954c15a76d4e71739fe448caac68a4333"
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")
DIGEST64 = re.compile(r"^sha256:[0-9a-f]{64}$")
TEST_ID = re.compile(r"^tc\.[a-z0-9]+(?:[._-][a-z0-9]+)*\.[a-z0-9]+(?:[._-][a-z0-9]+)*$")
ALLOWED_BLOCKERS = {
    "MISSING_IMPLEMENTATION", "MISSING_ADR", "MISSING_MEASUREMENT",
    "MISSING_EXACT_SHA_EVIDENCE", "STALE_EVIDENCE",
    "MISSING_INDEPENDENT_REVIEW", "CONFLICTING_ARCHITECTURE_DECISION",
    "BLOCKED_EXTERNAL", "READY",
}
ALLOWED_EVIDENCE = {"MEASURED", "SOURCE_DERIVED", "NOT_RUN", "BLOCKED", "NOT_APPLICABLE"}
IDENTITY_PLACEHOLDERS = {
    "STAGE_1_COMMIT_PENDING", "STAGE_1_TREE_PENDING", "PENDING_EXACT_HEAD_CI",
    "PENDING_CANDIDATE", "UNKNOWN_SHA", "TODO_SHA", "TBD_SHA",
}
FORBIDDEN_URL = re.compile(r"https?://", re.I)
SECRET_KEYS = re.compile(r"(password|secret|token|api[_-]?key|credential)", re.I)

def load(root: Path, rel: str):
    return json.loads((root / rel).read_text(encoding="utf-8"))

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()

def relative(value):
    path = PurePosixPath(str(value).replace("\\", "/"))
    return bool(value) and not path.is_absolute() and ".." not in path.parts

def walk(value, path=""):
    if isinstance(value, dict):
        for key, child in value.items():
            yield from walk(child, f"{path}/{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from walk(child, f"{path}/{index}")
    else:
        yield path, value

def is_sha40(value) -> bool:
    return isinstance(value, str) and bool(SHA40.fullmatch(value))

def is_sha64(value) -> bool:
    return isinstance(value, str) and bool(SHA64.fullmatch(value))

def identity_placeholder(value) -> bool:
    return isinstance(value, str) and value in IDENTITY_PLACEHOLDERS

def require_sha40(errors, label, value, expected=None):
    if identity_placeholder(value):
        errors.append(f"{label} unresolved identity placeholder")
    elif not is_sha40(value):
        errors.append(f"{label} invalid 40-character SHA")
    elif expected is not None and value != expected:
        errors.append(f"{label} does not match frozen Stage 1 identity")

def require_sha64(errors, label, value):
    if identity_placeholder(value):
        errors.append(f"{label} unresolved identity placeholder")
    elif not is_sha64(value):
        errors.append(f"{label} invalid SHA-256")

def stage_identities_distinct(stage1_commit, stage1_tree, stage2_commit, stage2_tree) -> bool:
    if stage2_commit is None and stage2_tree is None:
        return True
    return (
        is_sha40(stage1_commit) and is_sha40(stage1_tree)
        and is_sha40(stage2_commit) and is_sha40(stage2_tree)
        and (stage1_commit, stage1_tree) != (stage2_commit, stage2_tree)
    )

def validate(root: Path) -> list[str]:
    errors = []
    dep = load(root, "release/evidence/P3-001/dependency-status.json")
    for item in dep["dependencies"]:
        for key in ("commit", "tree"):
            value = item["implementation"][key]
            if not is_sha40(value):
                errors.append(f"{item['taskId']} invalid {key}")
        if item["decision"] not in ALLOWED_BLOCKERS:
            errors.append(f"{item['taskId']} invalid decision")
    for blocker in dep["activation"]["blockers"]:
        if blocker not in ALLOWED_BLOCKERS:
            errors.append(f"invalid blocker {blocker}")
    if dep["activation"]["p3_001ImplementationAuthorized"] is not False:
        errors.append("P3-001 must remain unauthorized")

    matrix = load(root, "release/evidence/P3-001/runtime-candidate-matrix.json")
    candidate_ids = [candidate["candidateId"] for candidate in matrix["candidates"]]
    if len(candidate_ids) != len(set(candidate_ids)):
        errors.append("duplicate candidate IDs")
    for candidate in matrix["candidates"]:
        for field, measurement in candidate["measurements"].items():
            if measurement["classification"] not in ALLOWED_EVIDENCE:
                errors.append(f"invalid evidence class {candidate['candidateId']} {field}")

    fixture_spec = load(root, "release/evidence/P3-001/fixture-specification.json")
    fixture_ids, routes, checksums = [], [], []
    for fixture in fixture_spec["fixtures"]:
        fixture_ids.append(fixture["fixtureId"])
        routes.append(fixture["localRoute"])
        checksums.append(fixture["deterministicChecksum"])
        copied = dict(fixture)
        supplied = copied.pop("deterministicChecksum")
        actual = hashlib.sha256(canonical(copied)).hexdigest()
        if supplied != actual:
            errors.append(f"fixture checksum mismatch {fixture['fixtureId']}")
        if fixture["networkPolicy"]["external"] != "DENY":
            errors.append(f"external network not denied {fixture['fixtureId']}")
        if not relative(fixture["localRoute"].lstrip("/")):
            errors.append(f"invalid route {fixture['fixtureId']}")
        for path, value in walk(fixture):
            if isinstance(value, str) and FORBIDDEN_URL.search(value):
                errors.append(f"external URL {fixture['fixtureId']} {path}")
            if SECRET_KEYS.search(path) and value not in (False, None, ""):
                errors.append(f"credential-like field {fixture['fixtureId']} {path}")
        if fixture["limits"]["maxRequestBytes"] > 1048576 or fixture["limits"]["maxResponseBytes"] > 1048576:
            errors.append(f"unbounded fixture {fixture['fixtureId']}")
    if len(fixture_ids) != len(set(fixture_ids)):
        errors.append("duplicate fixture IDs")
    if len(routes) != len(set(routes)):
        errors.append("duplicate fixture routes")
    if len(checksums) != len(set(checksums)):
        errors.append("duplicate fixture checksums")
    if fixture_spec["p3_016Claimed"] is not False:
        errors.append("P3-016 claim must be false")

    test_center = load(root, "release/evidence/P3-001/test-center-registration.json")
    if len(test_center["stableTestIds"]) != len(set(test_center["stableTestIds"])):
        errors.append("duplicate test IDs")
    for test_id in test_center["stableTestIds"]:
        if not TEST_ID.fullmatch(test_id):
            errors.append(f"invalid test ID {test_id}")
    request = test_center["developmentVerificationRequest"]
    require_sha40(errors, "candidate commit", request.get("candidateCommit"), STAGE1_COMMIT)
    require_sha40(errors, "candidate tree", request.get("candidateTree"), STAGE1_TREE)
    require_sha40(errors, "tested base commit", request.get("testedBaseCommit"), STAGE1_BASE_COMMIT)
    require_sha40(errors, "tested base tree", request.get("testedBaseTree"), STAGE1_BASE_TREE)

    evidence_manifest = load(root, "release/evidence/P3-001/manifest.json")
    tested = evidence_manifest.get("testedSourceCandidate", {})
    tested_base = evidence_manifest.get("testedBase", {})
    require_sha40(errors, "manifest tested source commit", tested.get("commit"), STAGE1_COMMIT)
    require_sha40(errors, "manifest tested source tree", tested.get("tree"), STAGE1_TREE)
    require_sha40(errors, "manifest tested base commit", tested_base.get("commit"), STAGE1_BASE_COMMIT)
    require_sha40(errors, "manifest tested base tree", tested_base.get("tree"), STAGE1_BASE_TREE)

    source_manifest = evidence_manifest.get("sourceManifestEvidence", {}).get("stage1", {})
    require_sha64(errors, "Stage 1 source-manifest SHA-256", source_manifest.get("sha256"))
    if not isinstance(source_manifest.get("entryCount"), int) or source_manifest["entryCount"] <= 0:
        errors.append("Stage 1 source-manifest entry count invalid")

    workflows = evidence_manifest.get("workflowEvidence", {})
    expected_runs = {
        "workerDReadiness": 31027132933,
        "productGates": 31027132935,
        "p2IntegrationAlignment": 31027132856,
    }
    for key, expected_run in expected_runs.items():
        record = workflows.get(key, {})
        if record.get("runId") != expected_run:
            errors.append(f"{key} workflow identity invalid")
        if record.get("event") != "pull_request" or record.get("runAttempt") != 1:
            errors.append(f"{key} workflow invocation invalid")
        if record.get("conclusion") != "success":
            errors.append(f"{key} workflow conclusion invalid")
        require_sha40(errors, f"{key} head SHA", record.get("headSha"), STAGE1_COMMIT)
        require_sha40(errors, f"{key} head tree", record.get("headTree"), STAGE1_TREE)
        artifacts = record.get("artifacts")
        if not isinstance(artifacts, list):
            errors.append(f"{key} artifacts must be a list")
            continue
        for artifact in artifacts:
            if not isinstance(artifact.get("artifactId"), int) or artifact["artifactId"] <= 0:
                errors.append(f"{key} artifact identity invalid")
            digest = artifact.get("digest")
            if identity_placeholder(digest) or not isinstance(digest, str) or not DIGEST64.fullmatch(digest):
                errors.append(f"{key} artifact digest invalid")
    worker_jobs = workflows.get("workerDReadiness", {}).get("jobs", [])
    expected_jobs = {
        92378362265: ("linux", "ubuntu-24.04"),
        92378362148: ("windows", "windows-2025"),
        92378362287: ("macos", "macos-15"),
    }
    observed_jobs = {}
    for job in worker_jobs:
        observed_jobs[job.get("jobId")] = (job.get("platform"), job.get("runnerImage"))
        if job.get("conclusion") != "success":
            errors.append(f"Worker D job {job.get('jobId')} conclusion invalid")
    if observed_jobs != expected_jobs:
        errors.append("Worker D platform job identities invalid")

    packaging = evidence_manifest.get("evidencePackagingCandidate", {})
    if packaging.get("classification") != "STAGE_2_EVIDENCE_PACKAGING":
        errors.append("Stage 2 evidence classification invalid")
    if packaging.get("binding") != "EXTERNAL_AFTER_PUBLICATION":
        errors.append("Stage 2 evidence binding must remain external")
    stage2_commit, stage2_tree = packaging.get("commit"), packaging.get("tree")
    for label, value in (("Stage 2 commit", stage2_commit), ("Stage 2 tree", stage2_tree)):
        if identity_placeholder(value):
            errors.append(f"{label} unresolved identity placeholder")
        elif value is not None and not is_sha40(value):
            errors.append(f"{label} invalid 40-character SHA")
    if not stage_identities_distinct(STAGE1_COMMIT, STAGE1_TREE, stage2_commit, stage2_tree):
        errors.append("Stage 1 identity rewritten as Stage 2")

    claim = load(root, "release/evidence/P3-001/claim-boundary.json")
    if claim["supportState"] != "SOURCE_FOUNDATION":
        errors.append("support state inflation")
    forbidden_states = {"BEHAVIOR_SUPPORTED", "PLATFORM_SUPPORTED", "RELEASE_SUPPORTED"}
    if any(value in forbidden_states for _, value in walk(claim)):
        errors.append("claim boundary inflated")
    certifications = [
        test_center["certificationRecord"].get("status"),
        test_center["developmentVerificationResult"].get("status"),
        evidence_manifest.get("certification", {}).get("status"),
        claim.get("certification"),
    ]
    if certifications != ["PARTIAL"] * 4:
        errors.append("certification classification inconsistent")
    support_promotions = [
        test_center["certificationRecord"].get("supportPromotion"),
        test_center["developmentVerificationResult"].get("supportPromotion"),
        test_center["capabilitySupportRecord"].get("supportPromotion"),
        evidence_manifest.get("certification", {}).get("supportPromotion"),
        claim.get("supportPromotion"),
    ]
    if any(value is not False for value in support_promotions):
        errors.append("support promotion must remain false")
    if test_center["developmentVerificationResult"].get("behavioralChecks") != "NOT_IMPLEMENTED":
        errors.append("behavioral checks must remain NOT_IMPLEMENTED")
    if claim["statements"].get("browserRuntime") != "NOT_IMPLEMENTED":
        errors.append("browser runtime must remain NOT_IMPLEMENTED")

    exact_identity_values = [
        request.get("candidateCommit"), request.get("candidateTree"),
        request.get("testedBaseCommit"), request.get("testedBaseTree"),
        tested.get("commit"), tested.get("tree"),
        tested_base.get("commit"), tested_base.get("tree"),
        source_manifest.get("sha256"),
    ]
    for record in workflows.values():
        exact_identity_values.extend([record.get("headSha"), record.get("headTree")])
    if any(identity_placeholder(value) for value in exact_identity_values):
        errors.append("unresolved exact-identity placeholder remains")

    owned_files = [
        "docs/roadmap/progress/2026-08-05-p3-001-readiness.md",
        "release/evidence/P3-001/READINESS.md",
        "release/evidence/P3-001/dependency-status.json",
        "release/evidence/P3-001/runtime-candidate-matrix.json",
        "release/evidence/P3-001/packaging-readiness-contract.json",
        "release/evidence/P3-001/fixture-specification.json",
        "release/evidence/P3-001/test-center-registration.json",
        "release/evidence/P3-001/claim-boundary.json",
        "release/evidence/P3-001/manifest.json",
    ]
    for rel in owned_files:
        if not (root / rel).is_file():
            errors.append(f"missing {rel}")
    forbidden_roots = ("lib/product/browser", "tool/browser_session", "tool/browser_actions", "automation_host/browser")
    for rel in forbidden_roots:
        if (root / rel).exists():
            errors.append(f"P3-002+ or runtime implementation present: {rel}")
    return errors

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--project", default=".")
    args = parser.parse_args()
    if not args.check:
        raise SystemExit("--check is required; this validator is non-mutating")
    errors = validate(Path(args.project).resolve())
    if errors:
        print("\n".join(f"FAIL {error}" for error in errors))
        raise SystemExit(1)
    print("Worker D P3 readiness: PASS")

if __name__ == "__main__":
    main()
