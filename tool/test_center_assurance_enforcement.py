#!/usr/bin/env python3
"""Fail-closed P8 assurance-report enforcement layered on canonical Test Center semantics."""
from __future__ import annotations

import hashlib
from pathlib import Path, PurePosixPath
from typing import Any, Mapping

from test_center_assurance_jsonschema import (
    SchemaValidationError,
    parse_rfc3339,
    validate_instance,
)
from test_center_assurance_semantics import (
    CLASS_LEVELS,
    HierarchyError,
    validate_assurance_execution_report as validate_base_report,
    validate_documents as validate_base_documents,
)
from test_center_contracts import ContractError, validate_test_execution_result

REPORT_CONTRACT_SCHEMA = Path("schemas/test_center_assurance_report_contract.v1.json")
REPORT_CONTRACT = Path("config/test_center_assurance_report_contract.v1.json")


def fail(message: str) -> None:
    raise HierarchyError(message)


def _pointer(document: Mapping[str, Any], pointer: str) -> Any:
    value: Any = document
    for raw in pointer.lstrip("/").split("/") if pointer else ():
        if not isinstance(value, Mapping):
            fail(f"schema pointer crosses a non-object at {raw!r}")
        key = raw.replace("~1", "/").replace("~0", "~")
        if key not in value:
            fail(f"schema pointer does not exist: {pointer}")
        value = value[key]
    return value


def _resolve_schema(
    schema: Mapping[str, Any],
    root: Mapping[str, Any],
    canonical: Mapping[str, Any],
) -> tuple[Mapping[str, Any], Mapping[str, Any]]:
    current = schema
    current_root = root
    seen: set[str] = set()
    while "$ref" in current:
        ref = str(current["$ref"])
        if ref in seen:
            fail(f"recursive schema reference is unsupported for report-contract path: {ref}")
        seen.add(ref)
        if ref.startswith("#"):
            resolved = _pointer(current_root, ref[1:])
        else:
            name, marker, pointer = ref.partition("#")
            if not marker or name != "test_center.v1.json":
                fail(f"unsupported report-contract schema reference: {ref}")
            current_root = canonical
            resolved = _pointer(canonical, pointer)
        if not isinstance(resolved, Mapping):
            fail(f"schema reference does not resolve to an object: {ref}")
        current = resolved
    return current, current_root


def _require_schema_path(
    report_schema: Mapping[str, Any],
    canonical_schema: Mapping[str, Any],
    path: str,
) -> None:
    if not path or path.startswith(".") or path.endswith(".") or ".." in path:
        fail(f"invalid report-contract field path: {path!r}")
    schema: Mapping[str, Any] = report_schema
    root: Mapping[str, Any] = report_schema
    for segment in path.split("."):
        schema, root = _resolve_schema(schema, root, canonical_schema)
        if schema.get("type") != "object":
            fail(f"report-contract path crosses non-object schema: {path}")
        properties = schema.get("properties", {})
        required = schema.get("required", [])
        if not isinstance(properties, Mapping) or segment not in properties:
            fail(f"report-contract path is absent from closed schema: {path}")
        if segment not in required:
            fail(f"report-contract path is not required by schema: {path}")
        child = properties[segment]
        if not isinstance(child, Mapping):
            fail(f"report-contract path has invalid schema node: {path}")
        schema = child


def validate_report_contract(
    contract_schema: dict[str, Any],
    contract: dict[str, Any],
    report_schema: dict[str, Any],
    canonical_schema: dict[str, Any],
    hierarchy: dict[str, Any],
) -> dict[str, Any]:
    try:
        validate_instance(contract, contract_schema, root=contract_schema)
    except SchemaValidationError as exc:
        raise HierarchyError(str(exc)) from exc
    if (
        contract.get("schemaVersion") != "1.0.0"
        or contract.get("contractId") != "test-center.assurance-report-contract-v1"
        or contract.get("hierarchyId") != hierarchy.get("hierarchyId")
        or contract.get("executionReportSchema")
        != "schemas/test_center_assurance_execution_report.v1.json"
    ):
        fail("assurance report mapping contract identity drifted")
    advertised = hierarchy["reportContract"]["requiredFields"]
    mappings = contract["hierarchyRequiredFieldMappings"]
    if set(mappings) != set(advertised) or len(mappings) != len(advertised):
        fail("hierarchy required fields and report mapping contract are not exact")
    schema_required = report_schema.get("required", [])
    declared_top = contract["reportRequiredTopLevelFields"]
    if set(declared_top) != set(schema_required) or len(declared_top) != len(schema_required):
        fail("closed report schema required fields and mapping contract drifted")
    for alias, target in mappings.items():
        if not isinstance(alias, str) or not isinstance(target, str):
            fail("report mapping aliases and targets must be strings")
        _require_schema_path(report_schema, canonical_schema, target)
    for field in declared_top:
        _require_schema_path(report_schema, canonical_schema, field)
    return {
        "schemaVersion": "1.0.0",
        "status": "PASS",
        "mappingContractId": contract["contractId"],
        "mappedHierarchyFieldCount": len(mappings),
        "requiredTopLevelFieldCount": len(declared_top),
    }


def validate_documents(
    hierarchy_schema: dict[str, Any],
    report_schema: dict[str, Any],
    canonical_schema: dict[str, Any],
    hierarchy: dict[str, Any],
    registry: dict[str, Any],
    contract_schema: dict[str, Any],
    contract: dict[str, Any],
) -> dict[str, Any]:
    base = validate_base_documents(hierarchy_schema, report_schema, hierarchy, registry)
    mapping = validate_report_contract(
        contract_schema, contract, report_schema, canonical_schema, hierarchy
    )
    return {**base, **mapping}


def _resolve_evidence(project: Path, evidence: Mapping[str, Any]) -> None:
    uri = str(evidence.get("uri", ""))
    normalized = uri.replace("\\", "/")
    relative = PurePosixPath(normalized)
    if (
        not normalized
        or relative.is_absolute()
        or ".." in relative.parts
        or normalized.startswith("~/")
        or ":" in relative.parts[0]
    ):
        fail(f"evidence URI must be repository-relative: {uri!r}")
    target = (project / Path(*relative.parts)).resolve()
    try:
        target.relative_to(project)
    except ValueError as exc:
        raise HierarchyError(f"evidence URI escapes project root: {uri!r}") from exc
    if not target.is_file():
        fail(f"evidence URI does not resolve to a durable file: {uri}")
    actual = hashlib.sha256(target.read_bytes()).hexdigest()
    if actual != evidence.get("sha256"):
        fail(f"evidence digest mismatch for {evidence.get('evidenceId')}: {uri}")


def _validate_evidence_categories(
    report: Mapping[str, Any],
    level: Mapping[str, Any],
    project: Path,
) -> None:
    canonical = report["executionResult"].get("evidenceReferences", [])
    canonical_by_id = {item["evidenceId"]: item for item in canonical}
    bindings = report["evidenceBindings"]
    categories = [item["category"] for item in bindings]
    evidence_ids = [item["evidenceId"] for item in bindings]
    if len(categories) != len(set(categories)):
        fail("assurance report contains duplicate evidence categories")
    if len(evidence_ids) != len(set(evidence_ids)):
        fail("one evidence object cannot satisfy multiple assurance categories")
    required = set(level["requiredEvidence"])
    actual = set(categories)
    if actual != required:
        fail(
            "assurance evidence categories do not exactly satisfy level requirements; "
            f"missing={sorted(required - actual)}, extra={sorted(actual - required)}"
        )
    if set(evidence_ids) != set(canonical_by_id):
        fail("assurance evidence bindings do not exactly cover canonical evidence objects")
    for evidence_id in evidence_ids:
        _resolve_evidence(project, canonical_by_id[evidence_id])


def _validate_predecessors(
    report: Mapping[str, Any],
    hierarchy: Mapping[str, Any],
    project: Path,
) -> None:
    levels = {item["levelId"]: item for item in hierarchy["levels"]}
    active = {item["testId"]: item for item in hierarchy["testBindings"]}
    current = levels[report["assuranceLevel"]]
    predecessors = report["predecessorResults"]
    ids = [item["assuranceLevel"] for item in predecessors]
    if len(ids) != len(set(ids)):
        fail("assurance report contains duplicate predecessor levels")
    required = set(current["requiredPredecessorLevels"])
    actual = set(ids)
    if actual != required:
        fail(
            "assurance predecessor results do not exactly satisfy level requirements; "
            f"missing={sorted(required - actual)}, extra={sorted(actual - required)}"
        )
    for predecessor in predecessors:
        level_id = predecessor["assuranceLevel"]
        result = predecessor["executionResult"]
        try:
            validate_test_execution_result(result)
        except ContractError as exc:
            raise HierarchyError(f"predecessor canonical TestExecutionResult invalid: {exc}") from exc
        if result["resultState"] != "PASS":
            fail(f"required predecessor {level_id} must PASS")
        if result["commit"] != report["candidateCommit"] or result["tree"] != report["candidateTree"]:
            fail(f"required predecessor {level_id} belongs to another candidate")
        binding = active.get(result["testId"])
        if binding is None or binding["levelId"] != level_id:
            fail(f"required predecessor {level_id} does not bind an active canonical test")
        if level_id not in CLASS_LEVELS.get(result["assuranceClass"], set()):
            fail(
                f"required predecessor {level_id} has incompatible assuranceClass "
                f"{result['assuranceClass']!r}"
            )
        for evidence in result.get("evidenceReferences", []):
            _resolve_evidence(project, evidence)


def validate_assurance_execution_report(
    report: dict[str, Any],
    *,
    report_schema: dict[str, Any],
    canonical_schema: dict[str, Any],
    hierarchy: dict[str, Any],
    registry: dict[str, Any],
    project: Path,
) -> dict[str, Any]:
    base = validate_base_report(
        report,
        report_schema=report_schema,
        canonical_schema=canonical_schema,
        hierarchy=hierarchy,
        registry=registry,
    )
    project = project.resolve()
    ended = parse_rfc3339(report["executionResult"]["endedAt"], "$.executionResult.endedAt")
    generated = parse_rfc3339(report["generatedAt"], "$.generatedAt")
    if generated < ended:
        fail("assurance report generatedAt precedes executionResult.endedAt")
    levels = {item["levelId"]: item for item in hierarchy["levels"]}
    level = levels[report["assuranceLevel"]]
    _validate_predecessors(report, hierarchy, project)
    _validate_evidence_categories(report, level, project)
    return {
        **base,
        "predecessorLevelsVerified": sorted(level["requiredPredecessorLevels"]),
        "requiredEvidenceVerified": sorted(level["requiredEvidence"]),
        "evidenceResolution": "REPOSITORY_RELATIVE_SHA256",
    }
