#!/usr/bin/env python3
"""Read-only P8-001 assurance hierarchy and execution-report validator."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from test_center_assurance_jsonschema import SchemaValidationError
from test_center_assurance_semantics import (
    HierarchyError,
    validate_assurance_execution_report,
    validate_documents,
)

HIERARCHY_SCHEMA = Path("schemas/test_center_assurance_hierarchy.v1.json")
REPORT_SCHEMA = Path("schemas/test_center_assurance_execution_report.v1.json")
CANONICAL_SCHEMA = Path("schemas/test_center.v1.json")
HIERARCHY = Path("config/test_center_assurance_hierarchy.v1.json")
REGISTRY = Path("config/test_center_registry.v1.json")
REPORT = Path("release/evidence/TEST_CENTER/P8-001/formal-test-hierarchy-validation.json")

def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise HierarchyError(f"{path} must be an object")
    return value
def project_documents(project: Path) -> tuple[dict[str, Any], ...]:
    return tuple(load(project / path) for path in (HIERARCHY_SCHEMA, REPORT_SCHEMA, CANONICAL_SCHEMA, HIERARCHY, REGISTRY))

def validate_project(project: Path) -> dict[str, Any]:
    project = project.resolve()
    hierarchy_schema, report_schema, canonical, hierarchy, registry = project_documents(project)
    report = validate_documents(hierarchy_schema, report_schema, hierarchy, registry)
    digest = lambda path: hashlib.sha256((project / path).read_bytes()).hexdigest()
    return {**report, "hierarchySchema": str(HIERARCHY_SCHEMA), "hierarchySchemaSha256": digest(HIERARCHY_SCHEMA), "executionReportSchema": str(REPORT_SCHEMA), "executionReportSchemaSha256": digest(REPORT_SCHEMA), "canonicalExecutionSchema": str(CANONICAL_SCHEMA), "canonicalExecutionSchemaSha256": digest(CANONICAL_SCHEMA), "hierarchy": str(HIERARCHY), "hierarchySha256": digest(HIERARCHY), "registry": str(REGISTRY), "registrySha256": digest(REGISTRY)}

def validate_report_file(project: Path, report_path: Path) -> dict[str, Any]:
    project, path = project.resolve(), (project.resolve() / report_path).resolve()
    try: path.relative_to(project)
    except ValueError as exc: raise HierarchyError("assurance report path must remain inside the project") from exc
    hierarchy_schema, report_schema, canonical, hierarchy, registry = project_documents(project)
    validate_documents(hierarchy_schema, report_schema, hierarchy, registry)
    return validate_assurance_execution_report(load(path), report_schema=report_schema, canonical_schema=canonical, hierarchy=hierarchy, registry=registry)

def write_report(project: Path, output: Path, report: dict[str, Any]) -> None:
    project, target = project.resolve(), (project.resolve() / output).resolve()
    try: target.relative_to(project)
    except ValueError as exc: raise HierarchyError("report output must remain inside the project") from exc
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(); sub = parser.add_subparsers(dest="command", required=True)
    for command in ("check", "write-report", "check-report"):
        child = sub.add_parser(command); child.add_argument("--project", type=Path, default=Path("."))
        if command == "write-report": child.add_argument("--output", type=Path, default=REPORT)
        if command == "check-report": child.add_argument("--report", type=Path, required=True)
    args = parser.parse_args(argv or sys.argv[1:])
    try:
        report = validate_report_file(args.project, args.report) if args.command == "check-report" else validate_project(args.project)
        if args.command == "write-report": write_report(args.project, args.output, report)
        print(json.dumps(report, indent=2, sort_keys=True)); return 0
    except (HierarchyError, SchemaValidationError, KeyError, TypeError, ValueError, OSError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, sort_keys=True), file=sys.stderr); return 1

if __name__ == "__main__": raise SystemExit(main())
