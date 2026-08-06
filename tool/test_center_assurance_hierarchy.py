#!/usr/bin/env python3
"""Read-only validator for the P8-001 Test Center assurance hierarchy."""
from __future__ import annotations

import argparse, hashlib, json, re, sys
from collections import Counter
from pathlib import Path

SCHEMA = Path("schemas/test_center_assurance_hierarchy.v1.json")
HIERARCHY = Path("config/test_center_assurance_hierarchy.v1.json")
REGISTRY = Path("config/test_center_registry.v1.json")
REPORT = Path("release/evidence/TEST_CENTER/P8-001/formal-test-hierarchy-validation.json")
LEVELS = ("architecture_lint", "unit", "component", "integration", "platform", "adversarial", "benchmark", "release")
RANKS = tuple(range(10, 90, 10))
REPORT_FIELDS = {"assuranceLevel", "candidateCommit", "candidateTree", "durationMillis", "endedAt", "evidenceReferences", "moduleId", "platform", "resultState", "startedAt", "testId"}
PROOFS = {"SOURCE_ONLY", "BEHAVIORAL", "PLATFORM", "BENCHMARK", "RELEASE"}
SCOPES = {"STATIC", "PROCESS_LOCAL", "COMPONENT_BOUNDARY", "MULTI_COMPONENT", "NATIVE_PLATFORM", "HOSTILE_INPUT", "MEASURED_WORKLOAD", "RELEASE_CANDIDATE"}
CEILINGS = {"NONE", "SOURCE_FOUNDATION", "BEHAVIOR_SUPPORTED", "PLATFORM_SUPPORTED", "RELEASE_SUPPORTED"}
TEST_ID = re.compile(r"^tc\.[a-z0-9]+(?:[._-][a-z0-9]+)*\.[a-z0-9]+(?:[._-][a-z0-9]+)*$")


class HierarchyError(ValueError):
    pass


def fail(message):
    raise HierarchyError(message)


def load(path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def mapping(value, name):
    if not isinstance(value, dict): fail(f"{name} must be an object")
    return value


def array(value, name):
    if not isinstance(value, list): fail(f"{name} must be an array")
    return value


def text(value, name):
    if not isinstance(value, str) or not value.strip(): fail(f"{name} must be a non-empty string")
    return value


def validate_schema(schema):
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema": fail("hierarchy schema must use JSON Schema Draft 2020-12")
    if schema.get("$id") != "https://local.kristin/schemas/test_center_assurance_hierarchy.v1.json": fail("unexpected hierarchy schema $id")
    if schema.get("type") != "object" or schema.get("additionalProperties") is not False: fail("hierarchy schema root must be a closed object")
    expected = {"schemaVersion", "hierarchyId", "roadmapTaskId", "levels", "testBindings", "reportContract"}
    if set(array(schema.get("required"), "schema.required")) != expected: fail("hierarchy schema required fields drifted")
    enum = schema["properties"]["levels"]["items"]["properties"]["levelId"].get("enum")
    if tuple(enum or ()) != LEVELS: fail("hierarchy schema level enum is not canonical")


def registry_ids(registry):
    cases = array(registry.get("testCases"), "registry.testCases")
    profiles = array(registry.get("projectTestProfiles"), "registry.projectTestProfiles")
    case_ids = [str(case.get("testId")) for case in cases]
    profile_ids = [str(profile.get("stableCheckId")) for profile in profiles]
    if len(case_ids) != len(set(case_ids)) or len(profile_ids) != len(set(profile_ids)): fail("registry contains duplicate stable IDs")
    if set(case_ids) != set(profile_ids): fail("registry test cases and profiles are not one-to-one")
    invalid = sorted(value for value in case_ids if not TEST_ID.fullmatch(value))
    if invalid: fail(f"invalid stable test IDs: {invalid}")
    return set(case_ids)


def validate_documents(schema, hierarchy, registry):
    validate_schema(schema)
    if hierarchy.get("schemaVersion") != "1.0.0" or hierarchy.get("hierarchyId") != "test-center.assurance-hierarchy-v1": fail("hierarchy identity is not canonical")
    if hierarchy.get("roadmapTaskId") != "P8-001": fail("hierarchy must bind to P8-001")
    levels = array(hierarchy.get("levels"), "levels")
    ids = [level.get("levelId") for level in levels if isinstance(level, dict)]
    ranks = [level.get("rank") for level in levels if isinstance(level, dict)]
    if len(levels) != 8 or tuple(ids) != LEVELS or tuple(ranks) != RANKS: fail("formal hierarchy must contain the canonical ordered eight levels")
    rank_by_id = dict(zip(ids, ranks))
    for level in levels:
        level = mapping(level, "level"); level_id = str(level["levelId"])
        if level.get("proofKind") not in PROOFS or level.get("executionScope") not in SCOPES: fail(f"invalid proof contract for {level_id}")
        if level.get("supportClaimCeiling") not in CEILINGS: fail(f"invalid support ceiling for {level_id}")
        evidence = array(level.get("requiredEvidence"), f"{level_id}.requiredEvidence")
        if len(evidence) < 2 or len(evidence) != len(set(evidence)): fail(f"required evidence is incomplete for {level_id}")
        for predecessor in array(level.get("requiredPredecessorLevels"), f"{level_id}.requiredPredecessorLevels"):
            if predecessor not in rank_by_id or rank_by_id[predecessor] >= rank_by_id[level_id]: fail(f"invalid predecessor {predecessor!r} for {level_id}")
        text(level.get("displayName"), f"{level_id}.displayName"); text(level.get("description"), f"{level_id}.description")
    if levels[0]["proofKind"] != "SOURCE_ONLY" or levels[0]["supportClaimCeiling"] != "NONE": fail("source-only architecture lint cannot promote support")
    if set(levels[-1]["requiredPredecessorLevels"]) != {"platform", "adversarial", "benchmark"}: fail("release assurance requires platform, adversarial, and benchmark evidence")

    report = mapping(hierarchy.get("reportContract"), "reportContract")
    fields = array(report.get("requiredFields"), "reportContract.requiredFields")
    if not REPORT_FIELDS.issubset(fields) or len(fields) != len(set(fields)): fail("assurance reports omit required fields or contain duplicates")
    if report.get("unknownLevelPolicy") != "FAIL" or report.get("crossLevelPromotionPolicy") != "FORBIDDEN": fail("assurance report policies must fail closed")
    if report.get("sourceOnlySupportPromotion") != "FORBIDDEN": fail("source-only checks must not promote support")
    if set(array(report.get("unexecutedResultStates"), "unexecutedResultStates")) != {"BLOCKED", "SKIPPED", "NOT_IMPLEMENTED"}: fail("unexecuted result states are incomplete")

    case_ids = registry_ids(registry)
    bindings = array(hierarchy.get("testBindings"), "testBindings")
    binding_ids = [binding.get("testId") for binding in bindings if isinstance(binding, dict)]
    duplicates = sorted(test_id for test_id, count in Counter(binding_ids).items() if count > 1)
    missing, extra = sorted(case_ids - set(binding_ids)), sorted(set(binding_ids) - case_ids)
    if duplicates or missing or extra: fail(f"every canonical Test Center ID needs one hierarchy binding; duplicates={duplicates}, missing={missing}, extra={extra}")
    for binding in bindings:
        binding = mapping(binding, "binding")
        if binding.get("levelId") not in rank_by_id: fail(f"unknown assurance level for {binding.get('testId')}")
        text(binding.get("rationale"), f"{binding.get('testId')}.rationale")

    required_p8 = {"tc.p8.formal-test-hierarchy", "tc.p8.formal-test-hierarchy-regressions"}
    if not required_p8.issubset(case_ids): fail("P8-001 stable Test Center IDs are not registered")
    cases = {case["testId"]: case for case in registry["testCases"]}
    for test_id in required_p8:
        case = cases[test_id]
        if "P8-001" not in case.get("roadmapTaskIds", []) or case.get("moduleId") != "tm.reliability-security-diagnostics": fail(f"{test_id} has incorrect roadmap or module ownership")
    return {"schemaVersion": "1.0.0", "status": "PASS", "checkMode": "NON_MUTATING", "roadmapTaskId": "P8-001", "hierarchyId": hierarchy["hierarchyId"], "levelCount": len(levels), "bindingCount": len(bindings), "levels": [{"assuranceLevel": level["levelId"], "rank": level["rank"], "proofKind": level["proofKind"], "supportClaimCeiling": level["supportClaimCeiling"]} for level in levels], "unmappedTestIds": [], "unknownLevelPolicy": report["unknownLevelPolicy"], "crossLevelPromotionPolicy": report["crossLevelPromotionPolicy"], "sourceOnlySupportPromotion": report["sourceOnlySupportPromotion"]}


def validate_project(project):
    project = project.resolve()
    report = validate_documents(mapping(load(project / SCHEMA), str(SCHEMA)), mapping(load(project / HIERARCHY), str(HIERARCHY)), mapping(load(project / REGISTRY), str(REGISTRY)))
    digest = lambda path: hashlib.sha256((project / path).read_bytes()).hexdigest()
    return {**report, "schema": str(SCHEMA), "schemaSha256": digest(SCHEMA), "hierarchy": str(HIERARCHY), "hierarchySha256": digest(HIERARCHY), "registry": str(REGISTRY), "registrySha256": digest(REGISTRY)}


def write_report(project, output, report):
    project = project.resolve(); target = (project / output).resolve()
    try: target.relative_to(project)
    except ValueError as exc: raise HierarchyError("report output must remain inside the project") from exc
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(); sub = parser.add_subparsers(dest="command", required=True)
    for command in ("check", "write-report"):
        child = sub.add_parser(command); child.add_argument("--project", type=Path, default=Path("."))
        if command == "write-report": child.add_argument("--output", type=Path, default=REPORT)
    args = parser.parse_args(argv or sys.argv[1:])
    try:
        report = validate_project(args.project)
        if args.command == "write-report": write_report(args.project, args.output, report)
        print(json.dumps(report, indent=2, sort_keys=True)); return 0
    except (HierarchyError, KeyError, TypeError, ValueError) as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, sort_keys=True), file=sys.stderr); return 1


if __name__ == "__main__":
    raise SystemExit(main())
