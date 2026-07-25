#!/usr/bin/env python3
"""Build Kristin's categorized assurance dashboard.

The dashboard is a claim firewall. It refuses to convert source-marker or mixed
checks into behavioral proof, and it keeps source, behavior, SDK/toolchain,
platform, and release evidence visibly separate.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from assurance_model import (
    ASSURANCE_BEHAVIORAL,
    ASSURANCE_SOURCE_CONTRACT,
    PROOF_EXECUTED_BEHAVIOR,
    PROOF_SOURCE_INSPECTION,
    STATUS_FAILED,
    STATUS_PASSED,
    summarize_assurance_checks,
    validate_assurance_summary,
)

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_VALIDATION = ROOT / "release" / "validation_report.json"
DEFAULT_ARCHITECTURE = ROOT / "release" / "ARCHITECTURE_CONTRACT_RESULTS.json"
DEFAULT_JSON = ROOT / "release" / "ASSURANCE_REPORT.json"
DEFAULT_MD = ROOT / "release" / "ASSURANCE_REPORT.md"


def load_json(path: Path, *, required: bool) -> dict[str, Any] | None:
    if not path.is_file():
        if required:
            raise FileNotFoundError(path)
        return None
    decoded = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(decoded, dict):
        raise ValueError(f"{path} must contain an object")
    return decoded


def architecture_check(report: dict[str, Any]) -> dict[str, Any]:
    return {
        "name": "Architecture and source-contract gate",
        "status": STATUS_PASSED if report.get("passed") is True else STATUS_FAILED,
        "blocking": True,
        "detail": (
            f"{report.get('passedCount', 0)} source-contract checks passed; "
            f"{report.get('failedCount', 0)} failed"
        ),
        "assurance_level": ASSURANCE_SOURCE_CONTRACT,
        "proof_kind": PROOF_SOURCE_INSPECTION,
        "behavioral_proof": False,
        "claim_scope": "source_and_wiring_only",
        "source_function": "architecture_contract_test",
    }


def render_markdown(report: dict[str, Any]) -> str:
    summary = report["assuranceSummary"]
    lines = [
        "# Kristin Assurance Dashboard",
        "",
        f"Overall categorized validation: **{'PASS' if report['passed'] else 'FAIL'}**",
        "",
        "## Claim boundaries",
        "",
        f"- Source-contract evidence passed: **{summary['sourceContractPassed']}**",
        f"- Pure behavioral assurance passed: **{summary['behavioralAssurancePassed']}**",
        f"- Source/mixed evidence counted as behavioral: **{not summary['noSourceMarkerOverclaim']}**",
        f"- Classification complete: **{summary['classificationComplete']}**",
        "",
        "> Source-marker and mixed gates never count as pure behavioral proof. Platform and release claims require separate executable evidence.",
        "",
        "## Assurance categories",
        "",
        "| Category | Checks | Passed | Failed | Unavailable | Complete |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for name, state in summary["groups"].items():
        lines.append(
            f"| {name} | {state['count']} | {state['passedCount']} | "
            f"{state['failedCount']} | {state['unavailableCount']} | {state['complete']} |"
        )
    lines.extend(
        [
            "",
            "## Checks",
            "",
            "| Check | Status | Assurance | Proof | Behavioral proof | Detail |",
            "|---|---:|---|---|---:|---|",
        ]
    )
    for check in report.get("checks", []):
        if not isinstance(check, dict):
            continue
        detail = str(check.get("detail", "")).replace("|", "\\|").replace("\n", " ")[:800]
        lines.append(
            f"| {check.get('name', '')} | {check.get('status', '')} | "
            f"{check.get('assurance_level', '')} | {check.get('proof_kind', '')} | "
            f"{check.get('behavioral_proof', False)} | {detail} |"
        )
    lines.extend(
        [
            "",
            "## Limitations",
            "",
            "- Architecture/source-contract evidence proves source shape and wiring only.",
            "- Mixed checks remain useful migration gates but do not satisfy pure behavioral assurance.",
            "- SDK/toolchain success does not by itself prove platform packaging or runtime security.",
            "- Platform and release assurance must be supplied by native CI and installer/update evidence.",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=str(ROOT))
    parser.add_argument("--validation-report")
    parser.add_argument("--architecture-report")
    parser.add_argument("--output-json")
    parser.add_argument("--output-markdown")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    project = Path(args.project).expanduser().resolve()
    validation_path = (
        Path(args.validation_report).expanduser().resolve()
        if args.validation_report
        else project / DEFAULT_VALIDATION.relative_to(ROOT)
    )
    architecture_path = (
        Path(args.architecture_report).expanduser().resolve()
        if args.architecture_report
        else project / DEFAULT_ARCHITECTURE.relative_to(ROOT)
    )
    output_json = (
        Path(args.output_json).expanduser().resolve()
        if args.output_json
        else project / DEFAULT_JSON.relative_to(ROOT)
    )
    output_markdown = (
        Path(args.output_markdown).expanduser().resolve()
        if args.output_markdown
        else project / DEFAULT_MD.relative_to(ROOT)
    )

    validation = load_json(validation_path, required=True)
    assert validation is not None
    architecture = load_json(architecture_path, required=False)
    checks = validation.get("checks")
    if not isinstance(checks, list):
        raise ValueError("validation report checks must be an array")
    normalized_checks = [dict(item) for item in checks if isinstance(item, dict)]
    if architecture is not None:
        normalized_checks.append(architecture_check(architecture))

    summary = summarize_assurance_checks(normalized_checks)
    failures = validate_assurance_summary(summary)
    if architecture is not None:
        if architecture.get("behavioralProof") is not False:
            failures.append("architecture report attempted to claim behavioral proof")
        if architecture.get("proofKind") != PROOF_SOURCE_INSPECTION:
            failures.append("architecture report proof kind is not source_inspection")
    validation_summary = validation.get("assurance_summary")
    if isinstance(validation_summary, dict):
        if validation_summary.get("noSourceMarkerOverclaim") is not True:
            failures.append("validator assurance summary reports a source-marker overclaim")

    blocking_failures = [
        str(item.get("name", ""))
        for item in normalized_checks
        if item.get("blocking", True) is True and item.get("status") == STATUS_FAILED
    ]
    passed = not failures and not blocking_failures
    report: dict[str, Any] = {
        "schemaVersion": "1.0.0",
        "product": validation.get("product", "Kristin Local Agent"),
        "version": validation.get("version", "unknown"),
        "passed": passed,
        "strict": args.strict,
        "assuranceSummary": summary,
        "checks": normalized_checks,
        "blockingFailures": blocking_failures,
        "classificationFailures": failures,
        "claims": {
            "sourceContractEvidence": summary["sourceContractPassed"],
            "behavioralEvidence": summary["behavioralAssurancePassed"],
            "platformEvidence": bool(summary["groups"]["platform"]["complete"]),
            "releaseEvidence": bool(summary["groups"]["release"]["complete"]),
            "sourceMarkersProveBehavior": False,
        },
    }
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    output_markdown.parent.mkdir(parents=True, exist_ok=True)
    output_markdown.write_text(render_markdown(report), encoding="utf-8")
    print(
        "Assurance dashboard: "
        f"source={summary['sourceContractPassed']} "
        f"behavioral={summary['behavioralAssurancePassed']} "
        f"overclaim={not summary['noSourceMarkerOverclaim']} "
        f"status={'PASS' if passed else 'FAIL'}"
    )
    if args.strict:
        return 0 if passed else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
