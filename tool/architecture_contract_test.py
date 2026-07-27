#!/usr/bin/env python3
"""Run and re-emit Kristin's legacy source-contract gate honestly.

`system_test.py` is retained for compatibility, but its checks primarily inspect
source text, files, schemas, and wiring. This wrapper makes that assurance level
machine-readable and rejects any future attempt to label the result as runtime
behavioral proof.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_JSON = ROOT / "release" / "ARCHITECTURE_CONTRACT_RESULTS.json"
DEFAULT_MD = ROOT / "release" / "ARCHITECTURE_CONTRACT_RESULTS.md"


def _redact(value: str, root: Path) -> str:
    value = value.replace(str(root), "<ROOT>")
    value = re.sub(
        r"(?i)(authorization\s*[:=]\s*bearer\s+)[^\s]+",
        r"\1<redacted>",
        value,
    )
    value = re.sub(
        r"(?i)(api[_-]?key|token|secret|password)(\s*[:=]\s*)[^\s,;]+",
        r"\1\2<redacted>",
        value,
    )
    return value[-50000:]


def _write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _write_markdown(path: Path, report: dict[str, Any]) -> None:
    lines = [
        "# Kristin Architecture and Source-Contract Report",
        "",
        f"Status: **{'PASS' if report.get('passed') else 'FAIL'}**",
        "",
        "Assurance level: **source_contract**",
        "",
        "Proof kind: **source_inspection**",
        "",
        "> This report does not establish runtime behavioral, platform, security-adversarial, or release assurance.",
        "",
        "| Check | Status | Detail |",
        "|---|---:|---|",
    ]
    for item in report.get("results", []):
        if not isinstance(item, dict):
            continue
        detail = str(item.get("detail", "")).replace("|", "\\|").replace("\n", " ")[:1000]
        lines.append(
            f"| {item.get('name', '')} | {'PASS' if item.get('passed') else 'FAIL'} | {detail} |"
        )
    lines.extend(
        [
            "",
            "## Limitation",
            "",
            "Passing source markers can show that a behavioral test or security control is present in the source tree. It cannot show that the behavior executed successfully or resisted an adversarial case.",
            "",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def run_gate(project: Path) -> tuple[int, dict[str, Any], str]:
    command = [
        sys.executable,
        str(project / "tool" / "system_test.py"),
        "--project",
        str(project),
        "--json",
    ]
    completed = subprocess.run(
        command,
        cwd=project,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        timeout=600,
        check=False,
    )
    output = _redact(completed.stdout, project)
    try:
        decoded = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        return completed.returncode or 1, {}, f"invalid JSON: {error}; output={output[-2000:]}"
    if not isinstance(decoded, dict):
        return completed.returncode or 1, {}, "system_test.py returned a non-object"
    return completed.returncode, decoded, output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=str(ROOT))
    parser.add_argument("--json-output")
    parser.add_argument("--markdown-output")
    parser.add_argument("--print", action="store_true", dest="print_report")
    args = parser.parse_args()
    project = Path(args.project).expanduser().resolve()
    json_output = Path(args.json_output).resolve() if args.json_output else project / DEFAULT_JSON.relative_to(ROOT)
    markdown_output = Path(args.markdown_output).resolve() if args.markdown_output else project / DEFAULT_MD.relative_to(ROOT)

    code, payload, bounded_output = run_gate(project)
    reported_level = payload.get("assuranceLevel")
    reported_proof = payload.get("proofKind")
    reported_behavior = payload.get("behavioralProof")
    metadata_valid = (
        reported_level == "source_contract"
        and reported_proof == "source_inspection"
        and reported_behavior is False
    )
    passed_count = payload.get("passed")
    failed_count = payload.get("failed")
    results = payload.get("results") if isinstance(payload.get("results"), list) else []
    passed = (
        code == 0
        and metadata_valid
        and isinstance(passed_count, int)
        and failed_count == 0
        and len(results) == passed_count
    )
    report: dict[str, Any] = {
        "schemaVersion": "1.0.0",
        "gateId": "architecture-source-contract",
        "assuranceLevel": "source_contract",
        "proofKind": "source_inspection",
        "behavioralProof": False,
        "passed": passed,
        "passedCount": passed_count if isinstance(passed_count, int) else 0,
        "failedCount": failed_count if isinstance(failed_count, int) else 1,
        "results": results,
        "command": command_display(project),
        "outputSha256": hashlib.sha256(bounded_output.encode("utf-8")).hexdigest(),
        "limitations": [
            "Source and wiring inspection only.",
            "Not runtime behavioral proof.",
            "Not platform containment or release evidence.",
        ],
    }
    if not metadata_valid:
        report["metadataFailure"] = {
            "assuranceLevel": reported_level,
            "proofKind": reported_proof,
            "behavioralProof": reported_behavior,
        }
    _write_json(json_output, report)
    _write_markdown(markdown_output, report)
    if args.print_report:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(
            "Architecture/source-contract gate: "
            f"{report['passedCount']} passed, {report['failedCount']} failed; "
            "behavioralProof=false"
        )
    return 0 if passed else 1


def command_display(project: Path) -> list[str]:
    return [
        "<PYTHON>",
        "tool/system_test.py",
        "--project",
        "<ROOT>",
        "--json",
    ]


if __name__ == "__main__":
    raise SystemExit(main())
