#!/usr/bin/env python3
"""Validate and replay Kristin's compact, redacted production-failure corpus.

The corpus stores causal inputs and golden expectations rather than complete
private diagnostic archives. Dart behavioral tests consume the same fixtures;
this Python entry point provides a fast deterministic preflight and baseline
metrics on workstations where the Flutter SDK is not installed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CORPUS = ROOT / "test" / "product" / "fixtures" / "diagnostic_replay"
EMPTY_SHA256 = hashlib.sha256(b"").hexdigest()
SCHEMA = "kristin.diagnostic-replay.v1"


def canonical_path_token(value: object) -> str:
    """Mirror the contract for exact whole-scalar quote/Markdown wrappers."""
    token = str(value).strip()
    for _ in range(4):
        before = token
        if len(token) >= 2 and token[0] == token[-1] and token[0] in {'"', "'"}:
            token = token[1:-1].strip()
        else:
            leading = len(token) - len(token.lstrip("`"))
            trailing = len(token) - len(token.rstrip("`"))
            if leading == trailing and 1 <= leading <= 3 and len(token) >= leading * 2:
                inner = token[leading:-trailing]
                if "\n" not in inner and "\r" not in inner:
                    token = inner.strip()
        if token == before:
            break
    token = token.replace("\\", "/")
    token = re.sub(r"^\./+", "", token)
    token = re.sub(r"/+", "/", token)
    return token


def _map(value: object) -> dict[str, Any]:
    return dict(value) if isinstance(value, dict) else {}


def normalize_action(envelope: dict[str, Any]) -> dict[str, Any]:
    action = _map(envelope.get("action"))
    source = action or envelope
    arguments = _map(source.get("arguments")) or _map(envelope.get("arguments"))
    merged = dict(arguments)
    for key in ("path", "filePath", "file_path", "content"):
        if key not in merged and key in source:
            merged[key] = source[key]
        if key not in merged and key in envelope:
            merged[key] = envelope[key]
    tool = str(
        source.get("type")
        or source.get("tool")
        or envelope.get("tool")
        or envelope.get("action")
        or ""
    ).strip()
    if "path" not in merged:
        for alias in ("filePath", "file_path"):
            if alias in merged:
                merged["path"] = merged[alias]
                break
    if "path" in merged:
        merged["path"] = canonical_path_token(merged["path"])
    return {"tool": tool, "arguments": merged}


def classify(case: dict[str, Any]) -> list[str]:
    observed = _map(case.get("observed"))
    replay = _map(case.get("replayInput"))
    envelope = _map(replay.get("modelEnvelope"))
    normalized = normalize_action(envelope)
    classifications: list[str] = []
    if (
        observed.get("mutationAfterSha256") == EMPTY_SHA256
        and _map(_map(envelope.get("action"))).get("content")
    ):
        classifications.extend(
            ["nested_canonical_field_loss", "empty_artifact_mutation"]
        )
    if observed.get("terminalFailure") == "artifact_scope_mismatch":
        classifications.append("artifact_repair_non_convergence")
    raw_path = str(observed.get("mutationPath", ""))
    expected_path = str(replay.get("expectedArtifactPath", ""))
    if raw_path != canonical_path_token(raw_path):
        classifications.append("markdown_path_wrapper_not_canonicalized")
    if raw_path and raw_path != expected_path and canonical_path_token(raw_path) == expected_path:
        classifications.append("artifact_scope_match_bypassed")
    if int(observed.get("repeatedToolCallsBlocked", 0)) > 0 and observed.get("terminalFailure") == "budget_repairs":
        classifications.append("read_only_recovery_loop")
    if _map(replay.get("copiedCoordinatorEnvelope")).get("action"):
        classifications.append("coordinator_metadata_copied_as_action")
    remaining = int(observed.get("maxRepairs", 0)) - int(observed.get("repairsBeforeRetry", 0))
    minimum = int(_map(case.get("expected")).get("minimumRemainingRepairs", 0))
    if minimum and remaining < minimum:
        classifications.append("insufficient_retry_reserve")
    # Keep deterministic order while removing duplicates.
    return list(dict.fromkeys(classifications))


def _display_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def validate_case(path: Path) -> dict[str, Any]:
    case = json.loads(path.read_text(encoding="utf-8"))
    errors: list[str] = []
    if case.get("schema") != SCHEMA:
        errors.append(f"schema must be {SCHEMA}")
    for section in ("source", "observed", "replayInput", "expected"):
        if not isinstance(case.get(section), dict):
            errors.append(f"{section} must be an object")
    source = _map(case.get("source"))
    if not re.fullmatch(r"[a-f0-9]{64}", str(source.get("sha256", ""))):
        errors.append("source.sha256 must be a lowercase SHA-256")
    replay = _map(case.get("replayInput"))
    expected = _map(case.get("expected"))
    normalized = normalize_action(_map(replay.get("modelEnvelope")))
    if normalized["tool"] != expected.get("normalizedTool"):
        errors.append(
            f"normalized tool {normalized['tool']!r} != {expected.get('normalizedTool')!r}"
        )
    if normalized["arguments"].get("path") != expected.get("normalizedPath"):
        errors.append(
            "normalized path "
            f"{normalized['arguments'].get('path')!r} != {expected.get('normalizedPath')!r}"
        )
    if expected.get("contentMustBePreserved"):
        source_content = _map(_map(replay.get("modelEnvelope")).get("action")).get("content")
        if normalized["arguments"].get("content") != source_content:
            errors.append("canonical nested content was not preserved")
    actual_classifications = classify(case)
    expected_classifications = list(expected.get("classifications", []))
    if actual_classifications != expected_classifications:
        errors.append(
            "classification mismatch: "
            f"actual={actual_classifications!r} expected={expected_classifications!r}"
        )
    return {
        "id": case.get("id", path.stem),
        "path": _display_path(path),
        "passed": not errors,
        "errors": errors,
        "classifications": actual_classifications,
        "observed": case.get("observed", {}),
        "source": source,
    }


def run(corpus: Path) -> dict[str, Any]:
    paths = sorted(corpus.glob("*.json"))
    results = [validate_case(path) for path in paths]
    latency = sum(int(_map(result.get("observed")).get("modelLatencyMs", 0)) for result in results)
    return {
        "schema": "kristin.diagnostic-replay-report.v1",
        "corpus": _display_path(corpus),
        "caseCount": len(results),
        "passed": bool(results) and all(result["passed"] for result in results),
        "passedCount": sum(1 for result in results if result["passed"]),
        "failedCount": sum(1 for result in results if not result["passed"]),
        "historicalModelLatencyMs": latency,
        "historicalModelLatencyMinutes": round(latency / 60000, 3),
        "results": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--json", action="store_true", dest="as_json")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = run(args.corpus.resolve())
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    if args.as_json:
        sys.stdout.write(encoded)
    else:
        status = "PASS" if report["passed"] else "FAIL"
        print(
            f"{status}: {report['passedCount']}/{report['caseCount']} diagnostic replays; "
            f"historical model latency represented={report['historicalModelLatencyMinutes']} minutes"
        )
        for result in report["results"]:
            marker = "PASS" if result["passed"] else "FAIL"
            print(f"  {marker} {result['id']}: {', '.join(result['classifications'])}")
            for error in result["errors"]:
                print(f"    - {error}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
