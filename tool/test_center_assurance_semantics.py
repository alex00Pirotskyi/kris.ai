#!/usr/bin/env python3
"""P8-001 assurance hierarchy and execution-report semantics."""
from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path
from typing import Any

from test_center_assurance_jsonschema import SchemaValidationError, validate_instance

REPORT_SCHEMA = Path("schemas/test_center_assurance_execution_report.v1.json")
LEVELS = ("architecture_lint", "unit", "component", "integration", "platform", "adversarial", "benchmark", "release")
RANKS = tuple(range(10, 90, 10))
REPORT_FIELDS = {"assuranceLevel", "candidateCommit", "candidateTree", "durationMillis", "endedAt", "evidenceReferences", "moduleId", "platform", "resultState", "startedAt", "testId"}
CEILINGS = ("NONE", "SOURCE_FOUNDATION", "BEHAVIOR_SUPPORTED", "PLATFORM_SUPPORTED", "RELEASE_SUPPORTED")
UNEXECUTED = {"BLOCKED", "SKIPPED", "NOT_IMPLEMENTED"}
TEST_ID = re.compile(r"^tc\.[a-z0-9]+(?:[._-][a-z0-9]+)*\.[a-z0-9]+(?:[._-][a-z0-9]+)*$")
CLASS_LEVELS = {
    "architecture_lint": {"architecture_lint"}, "source_contract": {"architecture_lint"},
    "behavioral": {"unit", "component", "integration", "adversarial", "benchmark"},
    "sdk_toolchain": {"architecture_lint", "unit", "component", "integration"},
    "platform": {"platform", "adversarial", "benchmark"}, "release": {"release"},
    "mixed": set(), "unclassified": set(),
}
WORKER_A_SOURCE = {
    "pullRequest": 64, "commit": "89a15332019c73675a19cdacd7021fae2199d75e",
    "tree": "2ea1f8a718a69dba0120a4f98acb78053d6cebfb", "reviewCommentId": 5203350863,
    "integrationState": "FROZEN_EXTERNAL_CANDIDATE",
}
WORKER_A_BINDINGS = {
    "tc.p1.exit-gate": ("architecture_lint", True),
    "tc.p1a.exit-gate": ("architecture_lint", True),
    "tc.p2.source-inventory": ("architecture_lint", True),
    "tc.p2.application-composition": ("architecture_lint", True),
    "tc.p2.acceptance-contract": ("architecture_lint", True),
    "tc.p2.evidence-contract": ("architecture_lint", True),
    "tc.p2.runner-attestation": ("architecture_lint", True),
    "tc.p2.cleanup-contract": ("architecture_lint", True),
    "tc.p2.strict-finalizer": ("architecture_lint", True),
    "tc.worker-a.canonical-integration": ("architecture_lint", True),
    "tc.p2.behavioral-closure": ("release", False),
}

class HierarchyError(ValueError):
    pass

def fail(message: str) -> None:
    raise HierarchyError(message)

def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        fail(f"{path} must be an object")
    return value

def schema_validate(instance: Any, schema: dict[str, Any], *, canonical: dict[str, Any] | None = None) -> None:
    external = {"test_center.v1.json": canonical} if canonical is not None else {}
    try:
        validate_instance(instance, schema, root=schema, external=external)
    except SchemaValidationError as exc:
        raise HierarchyError(str(exc)) from exc

def registry_ids(registry: dict[str, Any]) -> set[str]:
    cases, profiles = registry.get("testCases", []), registry.get("projectTestProfiles", [])
    case_ids = [item.get("testId") for item in cases]
    profile_ids = [item.get("stableCheckId") for item in profiles]
    if len(case_ids) != len(set(case_ids)) or len(profile_ids) != len(set(profile_ids)):
        fail("registry contains duplicate stable IDs")
    if set(case_ids) != set(profile_ids):
        fail("registry test cases and profiles are not one-to-one")
    invalid = sorted(value for value in case_ids if not isinstance(value, str) or not TEST_ID.fullmatch(value))
    if invalid:
        fail(f"invalid stable test IDs: {invalid}")
    return set(case_ids)

def validate_documents(schema: dict[str, Any], report_schema: dict[str, Any], hierarchy: dict[str, Any], registry: dict[str, Any]) -> dict[str, Any]:
    if schema.get("$id") != "https://local.kristin/schemas/test_center_assurance_hierarchy.v1.json" or schema.get("additionalProperties") is not False:
        fail("hierarchy schema identity or closure drifted")
    if report_schema.get("$id") != "https://local.kristin/schemas/test_center_assurance_execution_report.v1.json" or report_schema.get("additionalProperties") is not False:
        fail("assurance execution report schema identity or closure drifted")
    if report_schema.get("properties", {}).get("executionResult", {}).get("$ref") != "test_center.v1.json#/$defs/TestExecutionResult":
        fail("assurance execution report must bind canonical TestExecutionResult")
    schema_validate(hierarchy, schema)
    if hierarchy.get("schemaVersion") != "1.0.0" or hierarchy.get("hierarchyId") != "test-center.assurance-hierarchy-v1" or hierarchy.get("roadmapTaskId") != "P8-001":
        fail("hierarchy identity is not canonical")
    levels = hierarchy["levels"]
    ids, ranks = [item["levelId"] for item in levels], [item["rank"] for item in levels]
    if tuple(ids) != LEVELS or tuple(ranks) != RANKS:
        fail("formal hierarchy must contain the canonical ordered eight levels")
    by_level = {item["levelId"]: item for item in levels}
    for item in levels:
        if len(item["requiredEvidence"]) < 2 or len(item["requiredEvidence"]) != len(set(item["requiredEvidence"])):
            fail(f"required evidence is incomplete for {item['levelId']}")
        for predecessor in item["requiredPredecessorLevels"]:
            if predecessor not in by_level or by_level[predecessor]["rank"] >= item["rank"]:
                fail(f"invalid predecessor {predecessor!r} for {item['levelId']}")
    if levels[0]["proofKind"] != "SOURCE_ONLY" or levels[0]["supportClaimCeiling"] != "NONE":
        fail("source-only architecture lint cannot promote support")
    if set(levels[-1]["requiredPredecessorLevels"]) != {"platform", "adversarial", "benchmark"}:
        fail("release assurance requires platform, adversarial, and benchmark evidence")
    contract = hierarchy["reportContract"]
    if not REPORT_FIELDS.issubset(contract["requiredFields"]) or len(contract["requiredFields"]) != len(set(contract["requiredFields"])):
        fail("assurance reports omit required fields or contain duplicates")
    if contract["unknownLevelPolicy"] != "FAIL" or contract["crossLevelPromotionPolicy"] != "FORBIDDEN" or contract["sourceOnlySupportPromotion"] != "FORBIDDEN":
        fail("assurance report policies must fail closed")
    if set(contract["unexecutedResultStates"]) != UNEXECUTED or contract["executionReportSchema"] != REPORT_SCHEMA.as_posix():
        fail("assurance report execution contract drifted")
    case_ids = registry_ids(registry)
    bindings = hierarchy["testBindings"]
    binding_ids = [item["testId"] for item in bindings]
    duplicates = sorted(key for key, count in Counter(binding_ids).items() if count > 1)
    missing, extra = sorted(case_ids - set(binding_ids)), sorted(set(binding_ids) - case_ids)
    if duplicates or missing or extra:
        fail(f"every canonical Test Center ID needs one hierarchy binding; duplicates={duplicates}, missing={missing}, extra={extra}")
    pending = hierarchy["pendingMigrationBindings"]
    pending_ids = [item["testId"] for item in pending]
    if set(pending_ids) & set(binding_ids):
        fail("pending migration bindings overlap active bindings")
    if set(pending_ids) & case_ids:
        fail("pending migration IDs entered the canonical registry without active bindings")
    if len(pending_ids) != len(set(pending_ids)) or set(pending_ids) != set(WORKER_A_BINDINGS):
        fail("Worker A downstream migration binding set is incomplete")
    if hierarchy["pendingMigrationSource"] != WORKER_A_SOURCE:
        fail("Worker A downstream migration source identity drifted")
    for item in pending:
        if item["sourceOnly"] and item["levelId"] != "architecture_lint":
            fail(f"source-only pending binding cannot claim {item['levelId']}: {item['testId']}")
        expected = WORKER_A_BINDINGS[item["testId"]]
        if (item["levelId"], item["sourceOnly"]) != expected or item["integrationPolicy"] != "BLOCK_UNTIL_ACTIVE_BINDING":
            fail(f"Worker A downstream migration binding drifted: {item['testId']}")
    cases = {item["testId"]: item for item in registry["testCases"]}
    for test_id in ("tc.p8.formal-test-hierarchy", "tc.p8.formal-test-hierarchy-regressions"):
        case = cases.get(test_id)
        if not case or case.get("moduleId") != "tm.reliability-security-diagnostics" or "P8-001" not in case.get("roadmapTaskIds", []):
            fail(f"{test_id} has incorrect roadmap or module ownership")
    return {
        "schemaVersion": "1.0.0", "status": "PASS", "checkMode": "NON_MUTATING", "roadmapTaskId": "P8-001",
        "hierarchyId": hierarchy["hierarchyId"], "levelCount": len(levels), "bindingCount": len(bindings),
        "pendingMigrationBindingCount": len(pending), "levels": [{"assuranceLevel": item["levelId"], "rank": item["rank"], "proofKind": item["proofKind"], "supportClaimCeiling": item["supportClaimCeiling"]} for item in levels],
        "unmappedTestIds": [], "unknownLevelPolicy": contract["unknownLevelPolicy"],
        "crossLevelPromotionPolicy": contract["crossLevelPromotionPolicy"], "sourceOnlySupportPromotion": contract["sourceOnlySupportPromotion"],
        "executionReportSchema": contract["executionReportSchema"],
    }

def validate_assurance_execution_report(report: dict[str, Any], *, report_schema: dict[str, Any], canonical_schema: dict[str, Any], hierarchy: dict[str, Any], registry: dict[str, Any]) -> dict[str, Any]:
    schema_validate(report, report_schema, canonical=canonical_schema)
    result = report["executionResult"]
    active = {item["testId"]: item for item in hierarchy["testBindings"]}
    levels = {item["levelId"]: item for item in hierarchy["levels"]}
    test_id, level = result["testId"], report["assuranceLevel"]
    if test_id not in active:
        fail(f"actual execution record has no active hierarchy binding: {test_id}")
    if level not in levels:
        fail(f"actual execution record uses unknown assurance level: {level}")
    if active[test_id]["levelId"] != level:
        fail(f"actual execution record assurance level mismatch for {test_id}")
    wrapper = report["hierarchyBinding"]
    if wrapper["testId"] != test_id or wrapper["levelId"] != level:
        fail("assurance execution report binding does not match the canonical result")
    case = next((item for item in registry["testCases"] if item["testId"] == test_id), None)
    if case is None:
        fail(f"actual execution record references unknown canonical test: {test_id}")
    if result["moduleId"] != case["moduleId"] or wrapper["moduleId"] != case["moduleId"]:
        fail("assurance execution report module binding mismatch")
    if sorted(result["roadmapTaskIds"]) != sorted(case["roadmapTaskIds"]) or sorted(wrapper["roadmapTaskIds"]) != sorted(case["roadmapTaskIds"]):
        fail("assurance execution report roadmap binding mismatch")
    if report["candidateCommit"] != result["commit"] or report["candidateTree"] != result["tree"]:
        fail("assurance execution report candidate identity differs from canonical result")
    if level not in CLASS_LEVELS.get(result["assuranceClass"], set()):
        fail(f"canonical assuranceClass {result['assuranceClass']!r} is incompatible with {level!r}")
    source_only = levels[level]["proofKind"] == "SOURCE_ONLY"
    if wrapper["sourceOnly"] is not source_only:
        fail("assurance execution report sourceOnly flag differs from hierarchy proof kind")
    requested, ceiling = report["requestedSupportImpact"], levels[level]["supportClaimCeiling"]
    if CEILINGS.index(requested) > CEILINGS.index(ceiling):
        fail(f"requested support impact {requested} exceeds {level} ceiling {ceiling}")
    if source_only and requested != "NONE":
        fail("source-only actual execution records cannot promote support")
    if result["resultState"] in UNEXECUTED and requested != "NONE":
        fail("unexecuted actual execution records cannot promote support")
    if result["resultState"] != "PASS" and requested != "NONE":
        fail("non-PASS actual execution records cannot promote support")
    return {"schemaVersion": "1.0.0", "status": "PASS", "checkMode": "NON_MUTATING", "roadmapTaskId": "P8-001", "reportId": report["reportId"], "testId": test_id, "assuranceLevel": level, "resultState": result["resultState"], "requestedSupportImpact": requested, "candidateCommit": report["candidateCommit"], "candidateTree": report["candidateTree"]}
