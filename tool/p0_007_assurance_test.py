#!/usr/bin/env python3
"""Executable repository integration gate for P0-007."""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import py_compile
import re
import subprocess
import sys
import tempfile
from typing import Callable


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str


def run_case(name: str, action: Callable[[], str]) -> Result:
    try:
        return Result(name, True, action())
    except BaseException as error:
        return Result(name, False, f"{type(error).__name__}: {error}")


def require(path: Path) -> str:
    if not path.is_file():
        raise AssertionError(f"missing {path}")
    return path.read_text(encoding="utf-8")


def test_required_files(root: Path) -> str:
    required = (
        "tool/assurance_model.py",
        "tool/assurance_model_test.py",
        "tool/architecture_contract_test.py",
        "tool/assurance_dashboard.py",
        "tool/p0_007_assurance_test.py",
        "schemas/assurance_report.v1.json",
        "docs/roadmap/ASSURANCE_MODEL.md",
        "tasks/completed/P0-007.md",
        "release/evidence/P0-007/IMPLEMENTATION.md",
    )
    missing = [item for item in required if not (root / item).is_file()]
    if missing:
        raise AssertionError(f"missing: {missing}")
    return f"files={len(required)}"


def test_python_compilation(root: Path) -> str:
    files = (
        "tool/assurance_model.py",
        "tool/assurance_model_test.py",
        "tool/architecture_contract_test.py",
        "tool/assurance_dashboard.py",
        "tool/p0_007_assurance_test.py",
        "tool/system_test.py",
        "tool/validate_release.py",
    )
    for relative in files:
        py_compile.compile(str(root / relative), doraise=True)
    return f"compiled={len(files)}"


def test_system_gate_classification(root: Path) -> str:
    text = require(root / "tool/system_test.py")
    required = (
        'ASSURANCE_LEVEL = "source_contract"',
        'PROOF_KIND = "source_inspection"',
        "BEHAVIORAL_PROOF = False",
        '"assuranceLevel": ASSURANCE_LEVEL',
        '"proofKind": PROOF_KIND',
        '"behavioralProof": BEHAVIORAL_PROOF',
        "Source inspection only; this is not runtime behavioral proof.",
    )
    missing = [item for item in required if item not in text]
    if missing:
        raise AssertionError(f"system_test classification missing: {missing}")
    if re.search(r'"behavioralProof"\s*:\s*True', text):
        raise AssertionError("system_test.py claims behavioral proof")
    return "source_contract=true behavioralProof=false"


def test_validator_classification(root: Path) -> str:
    text = require(root / "tool/validate_release.py")
    required = (
        "from assurance_model import (",
        "classify_validator_check",
        "summarize_assurance_checks",
        "assurance_level: str",
        "proof_kind: str",
        "behavioral_proof: bool",
        "source_function: str",
        '"assurance_summary": assurance_summary',
        '"behavioral_assurance_passed"',
        "Mixed source/execution checks are not counted as pure behavioral proof.",
    )
    missing = [item for item in required if item not in text]
    if missing:
        raise AssertionError(f"validator classification missing: {missing}")
    return "categorized_check_model=true"


def test_no_legacy_overclaim_sentence(root: Path) -> str:
    text = require(root / "tool/validate_release.py")
    forbidden = (
        "A source release has passed deterministic architecture and security gates.",
        "source markers prove runtime behavior",
    )
    found = [item for item in forbidden if item in text]
    if found:
        raise AssertionError(f"legacy assurance overclaim remains: {found}")
    return "legacy_overclaim_absent=true"


def test_verify_integration(root: Path) -> str:
    text = require(root / "tool/verify.sh")
    required = (
        "python3 tool/assurance_model_test.py",
        "python3 tool/p0_007_assurance_test.py",
        "python3 tool/architecture_contract_test.py --project .",
        "python3 tool/assurance_dashboard.py --project . --strict",
    )
    missing = [item for item in required if item not in text]
    if missing:
        raise AssertionError(f"verify.sh integration missing: {missing}")
    return "verification_ladder_integrated=true"



def test_ci_integration(root: Path) -> str:
    path = root / ".github/workflows/ci.yml"
    if not path.is_file():
        return "workflow_absent=true"
    text = path.read_text(encoding="utf-8")
    required = (
        "P0-007 assurance classification",
        "python tool/p0_007_assurance_test.py --project .",
    )
    missing = [item for item in required if item not in text]
    if missing:
        raise AssertionError(f"CI assurance step missing: {missing}")
    return "ci_assurance_step=true"

def test_schema(root: Path) -> str:
    payload = json.loads(require(root / "schemas/assurance_report.v1.json"))
    if payload.get("$id") != "https://kristin.local/schemas/assurance_report.v1.json":
        raise AssertionError("schema ID mismatch")
    required = set(payload.get("required", []))
    expected = {"schemaVersion", "passed", "assuranceSummary", "checks", "claims"}
    if not expected.issubset(required):
        raise AssertionError(f"schema missing required fields: {sorted(expected - required)}")
    return "schema_required_fields=true"


def test_unit_suite(root: Path) -> str:
    completed = subprocess.run(
        [sys.executable, "tool/assurance_model_test.py"],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        timeout=120,
        check=False,
    )
    if completed.returncode != 0:
        raise AssertionError(completed.stdout[-4000:])
    match = re.search(r"Ran (\d+) tests", completed.stdout)
    if not match or int(match.group(1)) < 13:
        raise AssertionError(f"unexpected unit-test count: {completed.stdout[-1000:]}")
    return f"unitTests={match.group(1)}"


def test_dashboard_honest_fixture(root: Path) -> str:
    with tempfile.TemporaryDirectory(prefix="kristin-p0-007-") as temporary:
        work = Path(temporary)
        validation = {
            "product": "fixture",
            "version": "1",
            "checks": [
                {
                    "name": "source",
                    "status": "passed",
                    "blocking": True,
                    "detail": "source marker",
                    "assurance_level": "source_contract",
                    "proof_kind": "source_inspection",
                    "behavioral_proof": False,
                    "claim_scope": "source_and_wiring_only",
                    "source_function": "check_architecture",
                },
                {
                    "name": "behavior",
                    "status": "passed",
                    "blocking": True,
                    "detail": "executed harness",
                    "assurance_level": "behavioral",
                    "proof_kind": "executed_behavior",
                    "behavioral_proof": True,
                    "claim_scope": "runtime_behavior",
                    "source_function": "check_durable_workflow_kernel",
                },
            ],
        }
        architecture = {
            "passed": True,
            "passedCount": 1,
            "failedCount": 0,
            "proofKind": "source_inspection",
            "behavioralProof": False,
        }
        (work / "validation.json").write_text(json.dumps(validation), encoding="utf-8")
        (work / "architecture.json").write_text(json.dumps(architecture), encoding="utf-8")
        completed = subprocess.run(
            [
                sys.executable,
                "tool/assurance_dashboard.py",
                "--validation-report",
                str(work / "validation.json"),
                "--architecture-report",
                str(work / "architecture.json"),
                "--output-json",
                str(work / "report.json"),
                "--output-markdown",
                str(work / "report.md"),
                "--strict",
            ],
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=120,
            check=False,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stdout[-4000:])
        report = json.loads((work / "report.json").read_text(encoding="utf-8"))
        if report.get("passed") is not True:
            raise AssertionError("honest fixture did not pass")
        if report["claims"].get("sourceMarkersProveBehavior") is not False:
            raise AssertionError("dashboard upgraded source markers")
        if report["claims"].get("behavioralEvidence") is not True:
            raise AssertionError("pure behavioral evidence was not recognized")
    return "honest_fixture=true"


def test_dashboard_source_only_fixture(root: Path) -> str:
    with tempfile.TemporaryDirectory(prefix="kristin-p0-007-source-") as temporary:
        work = Path(temporary)
        validation = {
            "product": "fixture",
            "version": "1",
            "checks": [
                {
                    "name": "source",
                    "status": "passed",
                    "blocking": True,
                    "detail": "source marker",
                    "assurance_level": "source_contract",
                    "proof_kind": "source_inspection",
                    "behavioral_proof": False,
                    "claim_scope": "source_and_wiring_only",
                    "source_function": "check_architecture",
                }
            ],
        }
        (work / "validation.json").write_text(json.dumps(validation), encoding="utf-8")
        completed = subprocess.run(
            [
                sys.executable,
                "tool/assurance_dashboard.py",
                "--validation-report",
                str(work / "validation.json"),
                "--architecture-report",
                str(work / "missing.json"),
                "--output-json",
                str(work / "report.json"),
                "--output-markdown",
                str(work / "report.md"),
                "--strict",
            ],
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=120,
            check=False,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stdout[-4000:])
        report = json.loads((work / "report.json").read_text(encoding="utf-8"))
        if report["claims"].get("behavioralEvidence") is not False:
            raise AssertionError("source-only fixture claimed behavior")
    return "sourceOnlyBehavioralEvidence=false"


def test_docs(root: Path) -> str:
    text = require(root / "docs/roadmap/ASSURANCE_MODEL.md")
    required = (
        "architecture_lint",
        "source_contract",
        "behavioral",
        "sdk_toolchain",
        "platform",
        "release",
        "Mixed gates do not count as pure behavioral evidence",
    )
    missing = [item for item in required if item not in text]
    if missing:
        raise AssertionError(f"assurance documentation missing: {missing}")
    return "taxonomy_documented=true"


def test_task_packet(root: Path) -> str:
    text = require(root / "tasks/completed/P0-007.md")
    if re.search(r"## Status\s+DONE\b", text) is None:
        raise AssertionError("P0-007 completed packet must be DONE after formal P0 closure")
    if "Dashboard never reports source-marker checks as behavioral proof" not in text:
        raise AssertionError("P0-007 acceptance criterion missing")
    if re.search(r"release/evidence/P0/P0_EXIT_GATE_V[0-9]+[.]json", text) is None:
        raise AssertionError("P0-007 completed packet lacks P0 exit evidence")
    return "status=DONE"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--json-output")
    args = parser.parse_args()
    root = Path(args.project).expanduser().resolve()
    cases = [
        ("Required P0-007 files", lambda: test_required_files(root)),
        ("Python compilation", lambda: test_python_compilation(root)),
        ("system_test source-contract classification", lambda: test_system_gate_classification(root)),
        ("validate_release categorized checks", lambda: test_validator_classification(root)),
        ("Legacy overclaim removed", lambda: test_no_legacy_overclaim_sentence(root)),
        ("Verification ladder integration", lambda: test_verify_integration(root)),
        ("CI assurance integration", lambda: test_ci_integration(root)),
        ("Assurance report schema", lambda: test_schema(root)),
        ("Assurance unit suite", lambda: test_unit_suite(root)),
        ("Honest dashboard fixture", lambda: test_dashboard_honest_fixture(root)),
        ("Source-only dashboard fixture", lambda: test_dashboard_source_only_fixture(root)),
        ("Assurance model documentation", lambda: test_docs(root)),
        ("P0-007 task packet", lambda: test_task_packet(root)),
    ]
    results = [run_case(name, action) for name, action in cases]
    failed = [item for item in results if not item.passed]
    report = {
        "schemaVersion": "1.0.0",
        "taskId": "P0-007",
        "passed": not failed,
        "passedCount": len(results) - len(failed),
        "failedCount": len(failed),
        "caseCount": len(results),
        "results": [asdict(item) for item in results],
        "invariant": "source_and_mixed_checks_never_count_as_behavioral_proof",
    }
    if args.json_output:
        output = Path(args.json_output).expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for item in results:
        print(f"{'PASS' if item.passed else 'FAIL':<5} {item.name}: {item.detail}")
    print(f"\nP0-007 assurance gate: {report['passedCount']}/{report['caseCount']} passed")
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
