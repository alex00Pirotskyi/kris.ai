#!/usr/bin/env python3
"""Read-only P8-001 assurance hierarchy and execution-report validator."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from test_center_assurance_enforcement import (
    REPORT_CONTRACT,
    REPORT_CONTRACT_SCHEMA,
    validate_assurance_execution_report as _validate_enforced_report,
    validate_documents as _validate_enforced_documents,
)
from test_center_assurance_jsonschema import SchemaValidationError
from test_center_assurance_semantics import (
    HierarchyError,
    validate_documents as _validate_semantic_documents,
)

HIERARCHY_SCHEMA = Path("schemas/test_center_assurance_hierarchy.v1.json")
REPORT_SCHEMA = Path("schemas/test_center_assurance_execution_report.v1.json")
CANONICAL_SCHEMA = Path("schemas/test_center.v1.json")
HIERARCHY = Path("config/test_center_assurance_hierarchy.v1.json")
REGISTRY = Path("config/test_center_registry.v1.json")
REPORT = Path("release/evidence/TEST_CENTER/P8-001/formal-test-hierarchy-validation.json")
DEFAULT_PROJECT = Path(__file__).resolve().parents[1]


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise HierarchyError(f"{path} must be an object")
    return value


def validate_documents(
    hierarchy_schema: dict[str, Any],
    report_schema: dict[str, Any],
    *documents: dict[str, Any],
) -> dict[str, Any]:
    """Preserve the legacy four-document API while exposing full enforcement."""
    if len(documents) == 2:
        hierarchy, registry = documents
        return _validate_semantic_documents(
            hierarchy_schema, report_schema, hierarchy, registry
        )
    if len(documents) == 5:
        canonical, hierarchy, registry, contract_schema, contract = documents
        return _validate_enforced_documents(
            hierarchy_schema,
            report_schema,
            canonical,
            hierarchy,
            registry,
            contract_schema,
            contract,
        )
    raise TypeError(
        "validate_documents expects hierarchy/report schemas plus either "
        "(hierarchy, registry) or "
        "(canonical, hierarchy, registry, contract_schema, contract)"
    )


def _validate_predecessor_evidence_bindings(
    report: dict[str, Any], hierarchy: dict[str, Any]
) -> dict[str, Any]:
    levels = {item["levelId"]: item for item in hierarchy["levels"]}
    verified: list[dict[str, Any]] = []
    for predecessor in report["predecessorResults"]:
        level_id = predecessor["assuranceLevel"]
        level = levels[level_id]
        bindings = predecessor["evidenceBindings"]
        categories = [item["category"] for item in bindings]
        evidence_ids = [item["evidenceId"] for item in bindings]
        canonical_ids = [
            item["evidenceId"]
            for item in predecessor["executionResult"].get("evidenceReferences", [])
        ]
        if len(categories) != len(set(categories)):
            raise HierarchyError(
                f"predecessor {level_id} contains duplicate evidence categories"
            )
        if len(evidence_ids) != len(set(evidence_ids)):
            raise HierarchyError(
                f"predecessor {level_id} reuses one evidence object across categories"
            )
        if len(canonical_ids) != len(set(canonical_ids)):
            raise HierarchyError(
                f"predecessor {level_id} contains duplicate canonical evidence IDs"
            )
        required = set(level["requiredEvidence"])
        actual = set(categories)
        if actual != required:
            raise HierarchyError(
                f"predecessor {level_id} evidence categories do not exactly satisfy "
                f"level requirements; missing={sorted(required - actual)}, "
                f"extra={sorted(actual - required)}"
            )
        if set(evidence_ids) != set(canonical_ids):
            raise HierarchyError(
                f"predecessor {level_id} evidence bindings do not exactly cover "
                "canonical evidence objects"
            )
        verified.append(
            {
                "assuranceLevel": level_id,
                "requiredEvidence": sorted(required),
                "evidenceObjectCount": len(evidence_ids),
            }
        )
    return {
        "predecessorEvidenceProofs": verified,
        "predecessorEvidenceProofCount": len(verified),
    }


def validate_assurance_execution_report(
    report: dict[str, Any],
    *,
    report_schema: dict[str, Any],
    canonical_schema: dict[str, Any],
    hierarchy: dict[str, Any],
    registry: dict[str, Any],
    project: Path | None = None,
) -> dict[str, Any]:
    """Keep existing callers valid while enforcing durable proof resolution."""
    validated = _validate_enforced_report(
        report,
        report_schema=report_schema,
        canonical_schema=canonical_schema,
        hierarchy=hierarchy,
        registry=registry,
        project=(project or DEFAULT_PROJECT),
    )
    return {
        **validated,
        **_validate_predecessor_evidence_bindings(report, hierarchy),
    }


def project_documents(project: Path) -> tuple[dict[str, Any], ...]:
    paths = (
        HIERARCHY_SCHEMA,
        REPORT_SCHEMA,
        CANONICAL_SCHEMA,
        HIERARCHY,
        REGISTRY,
        REPORT_CONTRACT_SCHEMA,
        REPORT_CONTRACT,
    )
    return tuple(load(project / path) for path in paths)


def validate_project(project: Path) -> dict[str, Any]:
    project = project.resolve()
    hierarchy_schema, report_schema, canonical, hierarchy, registry, contract_schema, contract = project_documents(project)
    report = validate_documents(
        hierarchy_schema, report_schema, canonical, hierarchy, registry, contract_schema, contract
    )
    digest = lambda path: hashlib.sha256((project / path).read_bytes()).hexdigest()
    return {
        **report,
        "hierarchySchema": str(HIERARCHY_SCHEMA),
        "hierarchySchemaSha256": digest(HIERARCHY_SCHEMA),
        "executionReportSchema": str(REPORT_SCHEMA),
        "executionReportSchemaSha256": digest(REPORT_SCHEMA),
        "canonicalExecutionSchema": str(CANONICAL_SCHEMA),
        "canonicalExecutionSchemaSha256": digest(CANONICAL_SCHEMA),
        "reportContractSchema": str(REPORT_CONTRACT_SCHEMA),
        "reportContractSchemaSha256": digest(REPORT_CONTRACT_SCHEMA),
        "reportContract": str(REPORT_CONTRACT),
        "reportContractSha256": digest(REPORT_CONTRACT),
        "hierarchy": str(HIERARCHY),
        "hierarchySha256": digest(HIERARCHY),
        "registry": str(REGISTRY),
        "registrySha256": digest(REGISTRY),
    }


def validate_report_file(project: Path, report_path: Path) -> dict[str, Any]:
    project = project.resolve()
    path = (project / report_path).resolve()
    try:
        path.relative_to(project)
    except ValueError as exc:
        raise HierarchyError("assurance report path must remain inside the project") from exc
    hierarchy_schema, report_schema, canonical, hierarchy, registry, contract_schema, contract = project_documents(project)
    validate_documents(
        hierarchy_schema, report_schema, canonical, hierarchy, registry, contract_schema, contract
    )
    return validate_assurance_execution_report(
        load(path),
        report_schema=report_schema,
        canonical_schema=canonical,
        hierarchy=hierarchy,
        registry=registry,
        project=project,
    )


def write_report(project: Path, output: Path, report: dict[str, Any]) -> None:
    project = project.resolve()
    target = (project / output).resolve()
    try:
        target.relative_to(project)
    except ValueError as exc:
        raise HierarchyError("report output must remain inside the project") from exc
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ("check", "write-report", "check-report"):
        child = sub.add_parser(command)
        child.add_argument("--project", type=Path, default=Path("."))
        if command == "write-report":
            child.add_argument("--output", type=Path, default=REPORT)
        if command == "check-report":
            child.add_argument("--report", type=Path, required=True)
    args = parser.parse_args(argv or sys.argv[1:])
    try:
        report = validate_report_file(args.project, args.report) if args.command == "check-report" else validate_project(args.project)
        if args.command == "write-report":
            write_report(args.project, args.output, report)
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0
    except (HierarchyError, SchemaValidationError, KeyError, TypeError, ValueError, OSError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, sort_keys=True), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
