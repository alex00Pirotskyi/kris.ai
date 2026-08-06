#!/usr/bin/env python3
"""Fail-closed P8 assurance-report enforcement layered on canonical Test Center semantics."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
from typing import Any, Mapping

from test_center_assurance_jsonschema import SchemaValidationError, parse_rfc3339, validate_instance
from test_center_assurance_semantics import CLASS_LEVELS, HierarchyError, validate_assurance_execution_report as validate_base_report, validate_documents as validate_base_documents
from test_center_contracts import ContractError, validate_test_execution_result

REPORT_CONTRACT_SCHEMA = Path("schemas/test_center_assurance_report_contract.v1.json")
REPORT_CONTRACT = Path("config/test_center_assurance_report_contract.v1.json")
PROOF_CONTRACT_SCHEMA = Path("release/evidence/TEST_CENTER/P8-001/contracts/assurance-proof-contract.schema.json")
PROOF_CONTRACT = Path("release/evidence/TEST_CENTER/P8-001/contracts/assurance-proof-contract.v1.json")


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


def _resolve_schema(schema: Mapping[str, Any], root: Mapping[str, Any], canonical: Mapping[str, Any]) -> tuple[Mapping[str, Any], Mapping[str, Any]]:
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


def _require_schema_path(report_schema: Mapping[str, Any], canonical_schema: Mapping[str, Any], path: str) -> None:
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


def validate_report_contract(contract_schema: dict[str, Any], contract: dict[str, Any], report_schema: dict[str, Any], canonical_schema: dict[str, Any], hierarchy: dict[str, Any]) -> dict[str, Any]:
    try:
        validate_instance(contract, contract_schema, root=contract_schema)
    except SchemaValidationError as exc:
        raise HierarchyError(str(exc)) from exc
    if contract.get("schemaVersion") != "1.0.0" or contract.get("contractId") != "test-center.assurance-report-contract-v1" or contract.get("hierarchyId") != hierarchy.get("hierarchyId") or contract.get("executionReportSchema") != "schemas/test_center_assurance_execution_report.v1.json":
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
    return {"schemaVersion":"1.0.0","status":"PASS","mappingContractId":contract["contractId"],"mappedHierarchyFieldCount":len(mappings),"requiredTopLevelFieldCount":len(declared_top)}


def validate_proof_contract(contract_schema: dict[str, Any], contract: dict[str, Any], hierarchy: dict[str, Any]) -> dict[str, Any]:
    try:
        validate_instance(contract, contract_schema, root=contract_schema)
    except SchemaValidationError as exc:
        raise HierarchyError(str(exc)) from exc
    if contract.get("contractId") != "test-center.assurance-proof-contract-v1" or contract.get("hierarchyId") != hierarchy.get("hierarchyId"):
        fail("assurance proof contract identity drifted")
    evidence = contract["evidenceContracts"]
    categories = [item["category"] for item in evidence]
    if len(categories) != len(set(categories)):
        fail("assurance proof contract contains duplicate evidence categories")
    required_categories = {category for level in hierarchy["levels"] for category in level["requiredEvidence"]}
    if set(categories) != required_categories:
        fail(f"assurance proof contract evidence catalog does not exactly cover hierarchy; missing={sorted(required_categories-set(categories))}, extra={sorted(set(categories)-required_categories)}")
    lineages = contract["lineageBindings"]
    lineage_ids = [item["testId"] for item in lineages]
    if len(lineage_ids) != len(set(lineage_ids)):
        fail("assurance proof contract contains duplicate test lineage bindings")
    active_ids = {item["testId"] for item in hierarchy["testBindings"]}
    if set(lineage_ids) != active_ids:
        fail(f"assurance proof contract lineage bindings do not exactly cover active tests; missing={sorted(active_ids-set(lineage_ids))}, extra={sorted(set(lineage_ids)-active_ids)}")
    return {"schemaVersion":"1.0.0","status":"PASS","proofContractId":contract["contractId"],"evidenceContractCount":len(evidence),"lineageBindingCount":len(lineages)}


def validate_documents(hierarchy_schema: dict[str, Any], report_schema: dict[str, Any], canonical_schema: dict[str, Any], hierarchy: dict[str, Any], registry: dict[str, Any], contract_schema: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    base = validate_base_documents(hierarchy_schema, report_schema, hierarchy, registry)
    mapping = validate_report_contract(contract_schema, contract, report_schema, canonical_schema, hierarchy)
    return {**base, **mapping}


def _resolve_evidence(project: Path, evidence: Mapping[str, Any]) -> tuple[Path, bytes]:
    uri = str(evidence.get("uri", ""))
    normalized = uri.replace("\\", "/")
    relative = PurePosixPath(normalized)
    if not normalized or relative.is_absolute() or ".." in relative.parts or normalized.startswith("~/") or ":" in relative.parts[0]:
        fail(f"evidence URI must be repository-relative: {uri!r}")
    target = (project / Path(*relative.parts)).resolve()
    try:
        target.relative_to(project)
    except ValueError as exc:
        raise HierarchyError(f"evidence URI escapes project root: {uri!r}") from exc
    if not target.is_file():
        fail(f"evidence URI does not resolve to a durable file: {uri}")
    payload = target.read_bytes()
    actual = hashlib.sha256(payload).hexdigest()
    if actual != evidence.get("sha256"):
        fail(f"evidence digest mismatch for {evidence.get('evidenceId')}: {uri}")
    return target, payload


def _dot_value(value: Mapping[str, Any], path: str) -> Any:
    current: Any = value
    for segment in path.split("."):
        if not isinstance(current, Mapping) or segment not in current:
            fail(f"evidence contract context path does not exist: {path}")
        current = current[segment]
    return current


def _validate_evidence_semantics(project: Path, evidence: Mapping[str, Any], category: str, result: Mapping[str, Any], proof_contract: Mapping[str, Any]) -> None:
    contracts = {item["category"]: item for item in proof_contract["evidenceContracts"]}
    if category not in contracts:
        fail(f"unknown assurance evidence category contract: {category}")
    contract = contracts[category]
    if evidence.get("mediaType") != contract["mediaType"]:
        fail(f"evidence {evidence.get('evidenceId')} has wrong media type for {category}")
    target, payload = _resolve_evidence(project, evidence)
    try:
        document = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise HierarchyError(f"evidence for {category} is not canonical JSON: {target}") from exc
    if not isinstance(document, dict):
        fail(f"evidence for {category} must be a JSON object: {target}")
    missing = sorted(set(contract["requiredJsonFields"]) - set(document))
    if missing:
        fail(f"evidence for {category} is missing semantic fields: {missing}")
    if document.get("kind") != contract["jsonKind"]:
        fail(f"evidence kind mismatch for {category}: expected {contract['jsonKind']}, got {document.get('kind')!r}")
    context = {"candidateCommit":result["commit"],"candidateTree":result["tree"],"executionResult":result}
    for evidence_field, context_path in contract["valueBindings"].items():
        if _dot_value(document, evidence_field) != _dot_value(context, context_path):
            fail(f"evidence semantic binding mismatch for {category}.{evidence_field}")
    for evidence_field, expected in contract["requiredConstants"].items():
        if _dot_value(document, evidence_field) != expected:
            fail(f"evidence semantic constant mismatch for {category}.{evidence_field}")


def _validate_typed_evidence(*, result: Mapping[str, Any], bindings: list[Mapping[str, Any]], required_categories: set[str], project: Path, proof_contract: Mapping[str, Any], label: str) -> list[str]:
    canonical = result.get("evidenceReferences", [])
    canonical_by_id = {item["evidenceId"]: item for item in canonical}
    categories = [item["category"] for item in bindings]
    evidence_ids = [item["evidenceId"] for item in bindings]
    if len(categories) != len(set(categories)):
        fail(f"{label} contains duplicate evidence categories")
    if len(evidence_ids) != len(set(evidence_ids)):
        fail(f"{label} reuses one evidence object across categories")
    actual = set(categories)
    if actual != required_categories:
        fail(f"{label} evidence categories do not exactly satisfy level requirements; missing={sorted(required_categories-actual)}, extra={sorted(actual-required_categories)}")
    if set(evidence_ids) != set(canonical_by_id):
        fail(f"{label} evidence bindings do not exactly cover canonical evidence objects")
    for binding in bindings:
        _validate_evidence_semantics(project, canonical_by_id[binding["evidenceId"]], binding["category"], result, proof_contract)
    return sorted(required_categories)


def _validate_predecessor_chain(*, subject_test_id: str, predecessors: list[Mapping[str, Any]], required_levels: set[str], levels: Mapping[str, Mapping[str, Any]], active: Mapping[str, Mapping[str, Any]], lineages: Mapping[str, str], project: Path, proof_contract: Mapping[str, Any], candidate_commit: str, candidate_tree: str, seen_result_ids: set[str], depth: int = 0) -> list[dict[str, Any]]:
    if depth > len(levels):
        fail("assurance predecessor proof exceeds hierarchy depth")
    declared_levels = [item["assuranceLevel"] for item in predecessors]
    if len(declared_levels) != len(set(declared_levels)):
        fail(f"assurance predecessor proof for {subject_test_id} contains duplicate levels")
    actual = set(declared_levels)
    if actual != required_levels:
        fail(f"assurance predecessor results for {subject_test_id} do not exactly satisfy required levels; missing={sorted(required_levels-actual)}, extra={sorted(actual-required_levels)}")
    proofs: list[dict[str, Any]] = []
    for predecessor in predecessors:
        level_id = predecessor["assuranceLevel"]
        result = predecessor["executionResult"]
        try:
            validate_test_execution_result(result)
        except ContractError as exc:
            raise HierarchyError(f"predecessor canonical TestExecutionResult invalid: {exc}") from exc
        result_id = result["resultId"]
        if result_id in seen_result_ids:
            fail(f"assurance predecessor receipt/resultId is reused: {result_id}")
        seen_result_ids.add(result_id)
        if result["resultState"] != "PASS":
            fail(f"required predecessor {level_id} must PASS")
        if result["commit"] != candidate_commit or result["tree"] != candidate_tree:
            fail(f"required predecessor {level_id} belongs to another candidate")
        binding = active.get(result["testId"])
        if binding is None or binding["levelId"] != level_id:
            fail(f"required predecessor {level_id} does not bind an active canonical test")
        if lineages.get(result["testId"]) != lineages.get(subject_test_id):
            fail(f"required predecessor {level_id} belongs to unrelated assurance lineage: {result['testId']}")
        if level_id not in CLASS_LEVELS.get(result["assuranceClass"], set()):
            fail(f"required predecessor {level_id} has incompatible assuranceClass {result['assuranceClass']!r}")
        child_proofs = _validate_predecessor_chain(
            subject_test_id=result["testId"],
            predecessors=predecessor["predecessorResults"],
            required_levels=set(levels[level_id]["requiredPredecessorLevels"]),
            levels=levels,
            active=active,
            lineages=lineages,
            project=project,
            proof_contract=proof_contract,
            candidate_commit=candidate_commit,
            candidate_tree=candidate_tree,
            seen_result_ids=seen_result_ids,
            depth=depth+1,
        )
        verified = _validate_typed_evidence(result=result, bindings=predecessor["evidenceBindings"], required_categories=set(levels[level_id]["requiredEvidence"]), project=project, proof_contract=proof_contract, label=f"predecessor {level_id}")
        proofs.append({"assuranceLevel":level_id,"testId":result["testId"],"resultId":result_id,"lineageId":lineages[result["testId"]],"requiredEvidence":verified,"predecessorProofs":child_proofs})
    return proofs


def validate_assurance_execution_report(report: dict[str, Any], *, report_schema: dict[str, Any], canonical_schema: dict[str, Any], hierarchy: dict[str, Any], registry: dict[str, Any], project: Path, proof_contract: dict[str, Any] | None = None) -> dict[str, Any]:
    base = validate_base_report(report, report_schema=report_schema, canonical_schema=canonical_schema, hierarchy=hierarchy, registry=registry)
    project = project.resolve()
    if proof_contract is None:
        proof_contract = json.loads((project / PROOF_CONTRACT).read_text(encoding="utf-8"))
    ended = parse_rfc3339(report["executionResult"]["endedAt"], "$.executionResult.endedAt")
    generated = parse_rfc3339(report["generatedAt"], "$.generatedAt")
    if generated < ended:
        fail("assurance report generatedAt precedes executionResult.endedAt")
    levels = {item["levelId"]: item for item in hierarchy["levels"]}
    active = {item["testId"]: item for item in hierarchy["testBindings"]}
    lineages = {item["testId"]: item["lineageId"] for item in proof_contract["lineageBindings"]}
    level = levels[report["assuranceLevel"]]
    predecessors = _validate_predecessor_chain(
        subject_test_id=report["executionResult"]["testId"],
        predecessors=report["predecessorResults"],
        required_levels=set(level["requiredPredecessorLevels"]),
        levels=levels,
        active=active,
        lineages=lineages,
        project=project,
        proof_contract=proof_contract,
        candidate_commit=report["candidateCommit"],
        candidate_tree=report["candidateTree"],
        seen_result_ids={report["executionResult"]["resultId"]},
    )
    current_evidence = _validate_typed_evidence(result=report["executionResult"], bindings=report["evidenceBindings"], required_categories=set(level["requiredEvidence"]), project=project, proof_contract=proof_contract, label="assurance report")
    return {**base,"predecessorLevelsVerified":sorted(level["requiredPredecessorLevels"]),"predecessorEvidenceProofs":predecessors,"predecessorEvidenceProofCount":len(predecessors),"requiredEvidenceVerified":current_evidence,"evidenceResolution":"REPOSITORY_RELATIVE_SHA256_AND_TYPED_JSON","predecessorProofMode":"RECURSIVE_EXACT_CANDIDATE_LINEAGE"}
