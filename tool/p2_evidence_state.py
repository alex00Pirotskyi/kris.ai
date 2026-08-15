#!/usr/bin/env python3
"""Validate the canonical P2 task/phase state without promoting unsupported behavior."""
from __future__ import annotations

import argparse
import json
from pathlib import Path, PurePosixPath
import re
from typing import Any

TASK_IDS = tuple(f"P2-{number:03d}" for number in range(1, 15))
CLAIM_LEVELS = (
    "IMPLEMENTED_SOURCE",
    "VERIFIED_SOURCE",
    "BEHAVIOR_VERIFIED",
    "PLATFORM_QUALIFIED",
    "RELEASE_CANDIDATE",
    "SUPPORTED",
    "GA",
)
TASK_STATE_KEYS = {
    "recordType",
    "schemaVersion",
    "taskId",
    "taskKind",
    "recordRole",
    "status",
    "claimLevel",
    "sourceCommit",
    "sourceTree",
    "effectiveAt",
    "platform",
    "packagedExecution",
    "productBehaviorObserved",
    "measurementObserved",
    "completionEligible",
    "phaseCompletionEligible",
    "platformQualified",
    "releaseSupported",
    "productionSupported",
    "selectedCandidate",
    "evidenceRefs",
    "supersedes",
    "downstreamTasks",
    "truthBoundary",
}
PHASE_STATE_KEYS = {
    "recordType",
    "schemaVersion",
    "phase",
    "recordRole",
    "status",
    "claimLevel",
    "sourceCommit",
    "sourceTree",
    "effectiveAt",
    "taskStates",
    "acceptedDecisionTasks",
    "behaviorCertifiedTasks",
    "phaseCompletionEligible",
    "platformQualified",
    "releaseSupported",
    "productionSupported",
    "activeTaskRecords",
    "knownDebts",
    "truthBoundary",
}
HEX40 = re.compile(r"^[0-9a-f]{40}$")
RFC3339 = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")

P2_004_STATE = "release/evidence/P2-004/state.json"
P2_PHASE_STATE = "release/evidence/P2/state.json"
P2_004_MANIFEST = "release/evidence/P2-004/manifest.json"
P2_004_SPIKE = "release/evidence/P2-004/technology-spike.json"
P2_004_DIAGNOSTIC = "release/evidence/P2-004/test-results.json"
P2_LEGACY_MANIFEST = "release/evidence/P2/manifest.json"


class EvidenceStateError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise EvidenceStateError(message)


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"invalid JSON {path}: {error}")
    if not isinstance(value, dict):
        fail(f"JSON object required: {path}")
    return value


def _closed(value: dict[str, Any], expected: set[str], label: str) -> None:
    actual = set(value)
    if actual != expected:
        fail(
            f"{label} must be closed: "
            f"missing={sorted(expected - actual)} extra={sorted(actual - expected)}"
        )


def _sha(value: Any, label: str) -> str:
    text = str(value)
    if HEX40.fullmatch(text) is None:
        fail(f"{label} must be an exact 40-character Git object ID")
    return text


def _timestamp(value: Any, label: str) -> str:
    text = str(value)
    if RFC3339.fullmatch(text) is None:
        fail(f"{label} must be UTC RFC3339 without fractional seconds")
    return text


def _safe_repo_path(value: Any, label: str) -> str:
    text = str(value)
    pure = PurePosixPath(text)
    if (
        not text
        or pure.is_absolute()
        or ".." in pure.parts
        or "\\" in text
        or text.startswith("./")
    ):
        fail(f"{label} is not a safe repository-relative path: {text!r}")
    return text


def _unique_strings(value: Any, label: str, *, allow_empty: bool = False) -> list[str]:
    if not isinstance(value, list) or (not allow_empty and not value):
        fail(f"{label} must be a {'possibly empty ' if allow_empty else ''}list")
    if any(not isinstance(item, str) or not item for item in value):
        fail(f"{label} must contain non-empty strings")
    if len(value) != len(set(value)):
        fail(f"{label} must not contain duplicates")
    return value


def validate_task_state(value: dict[str, Any], root: Path) -> dict[str, Any]:
    _closed(value, TASK_STATE_KEYS, "P2 task state")
    exact = {
        "recordType": "P2TaskState",
        "schemaVersion": "1.0.0",
        "taskId": "P2-004",
        "taskKind": "architecture_decision",
        "recordRole": "active",
        "status": "accepted_decision",
        "claimLevel": "VERIFIED_SOURCE",
        "platform": "cross_platform_measurement",
        "packagedExecution": False,
        "productBehaviorObserved": False,
        "measurementObserved": True,
        "completionEligible": True,
        "phaseCompletionEligible": False,
        "platformQualified": False,
        "releaseSupported": False,
        "productionSupported": False,
        "selectedCandidate": "typescript-node-node-pty-with-native-lifecycle-adapters",
    }
    for key, expected in exact.items():
        if value.get(key) != expected:
            fail(f"P2-004 task state {key} mismatch: {value.get(key)!r}")
    _sha(value["sourceCommit"], "P2-004 sourceCommit")
    _sha(value["sourceTree"], "P2-004 sourceTree")
    _timestamp(value["effectiveAt"], "P2-004 effectiveAt")

    evidence = _unique_strings(value["evidenceRefs"], "P2-004 evidenceRefs")
    expected_evidence = {
        P2_004_MANIFEST,
        P2_004_SPIKE,
        P2_004_DIAGNOSTIC,
        "docs/adr/ADR-0012-p2-automation-host.md",
    }
    if set(evidence) != expected_evidence:
        fail(f"P2-004 evidenceRefs mismatch: {sorted(evidence)}")
    for relative in evidence:
        path = root / _safe_repo_path(relative, "P2-004 evidence ref")
        if not path.is_file():
            fail(f"P2-004 evidence ref missing: {relative}")

    supersedes = _unique_strings(
        value["supersedes"], "P2-004 supersedes", allow_empty=True
    )
    if set(supersedes) != {P2_004_MANIFEST, P2_004_SPIKE}:
        fail(f"P2-004 supersedes mismatch: {supersedes}")

    downstream = value["downstreamTasks"]
    if downstream != {"P2-005": False, "P2-006": False}:
        fail(f"P2-004 downstream task boundary invalid: {downstream}")

    truth = value["truthBoundary"]
    expected_truth = {
        "p2PhaseComplete": False,
        "platformSupportPromoted": False,
        "releaseSupportPromoted": False,
        "productionReadinessPromoted": False,
        "gaPromoted": False,
    }
    if truth != expected_truth:
        fail(f"P2-004 truth boundary invalid: {truth}")
    return value


def validate_phase_state(value: dict[str, Any], root: Path) -> dict[str, Any]:
    _closed(value, PHASE_STATE_KEYS, "P2 phase state")
    exact = {
        "recordType": "P2PhaseState",
        "schemaVersion": "1.0.0",
        "phase": "P2",
        "recordRole": "active",
        "status": "incomplete",
        "claimLevel": "VERIFIED_SOURCE",
        "phaseCompletionEligible": False,
        "platformQualified": False,
        "releaseSupported": False,
        "productionSupported": False,
    }
    for key, expected in exact.items():
        if value.get(key) != expected:
            fail(f"P2 phase state {key} mismatch: {value.get(key)!r}")
    _sha(value["sourceCommit"], "P2 phase sourceCommit")
    _sha(value["sourceTree"], "P2 phase sourceTree")
    _timestamp(value["effectiveAt"], "P2 phase effectiveAt")

    expected_states = {task_id: "source_only" for task_id in TASK_IDS}
    expected_states["P2-004"] = "accepted_decision"
    if value["taskStates"] != expected_states:
        fail(f"P2 taskStates mismatch: {value['taskStates']}")
    if value["acceptedDecisionTasks"] != ["P2-004"]:
        fail("P2 acceptedDecisionTasks must contain exactly P2-004")
    if value["behaviorCertifiedTasks"] != []:
        fail("P2 behaviorCertifiedTasks must remain empty")
    if value["activeTaskRecords"] != {"P2-004": P2_004_STATE}:
        fail("P2 activeTaskRecords must bind exactly P2-004 state")
    if not (root / P2_004_STATE).is_file():
        fail("P2-004 active state record missing")
    debts = _unique_strings(value["knownDebts"], "P2 knownDebts")
    required_debts = {
        "P2-005 interactive PTY behavior is not certified.",
        "P2-006 process-tree behavior is not certified.",
        "macOS node-pty spawn-helper packaging repair is not closed.",
        "Windows automation-host startup optimization is not closed.",
    }
    if set(debts) != required_debts:
        fail(f"P2 knownDebts mismatch: {debts}")
    truth = value["truthBoundary"]
    expected_truth = {
        "sourceOnlyIsNotBehavioralProof": True,
        "acceptedDecisionDoesNotCompletePhase": True,
        "platformSupportPromoted": False,
        "releaseSupportPromoted": False,
        "productionReadinessPromoted": False,
        "gaPromoted": False,
    }
    if truth != expected_truth:
        fail(f"P2 phase truth boundary invalid: {truth}")
    return value


def _validate_legacy_annotations(root: Path) -> None:
    phase = load_json(root / P2_LEGACY_MANIFEST)
    expected_phase = {
        "recordType": "P2LegacyPhaseManifest",
        "recordRole": "historical",
        "stateAuthority": False,
        "supersededBy": P2_PHASE_STATE,
    }
    for key, expected in expected_phase.items():
        if phase.get(key) != expected:
            fail(f"legacy P2 phase manifest {key} mismatch")

    acceptance = load_json(root / P2_004_MANIFEST)
    expected_acceptance = {
        "recordType": "P2TaskAcceptanceEvidence",
        "recordRole": "historical",
        "stateAuthority": False,
        "supersededBy": P2_004_STATE,
        "claimLevel": "VERIFIED_SOURCE",
        "productBehaviorObserved": False,
        "platformQualified": False,
        "releaseSupported": False,
        "productionSupported": False,
        "gaPromoted": False,
    }
    for key, expected in expected_acceptance.items():
        if acceptance.get(key) != expected:
            fail(f"legacy P2-004 acceptance evidence {key} mismatch")

    spike = load_json(root / P2_004_SPIKE)
    expected_spike = {
        "recordType": "P2TechnologySpike",
        "recordRole": "historical",
        "stateAuthority": False,
        "supersededBy": P2_004_STATE,
        "claimLevel": "IMPLEMENTED_SOURCE",
    }
    for key, expected in expected_spike.items():
        if spike.get(key) != expected:
            fail(f"legacy P2-004 technology spike {key} mismatch")

    diagnostic = load_json(root / P2_004_DIAGNOSTIC)
    expected_diagnostic = {
        "recordType": "P2TaskDiagnostic",
        "recordRole": "diagnostic",
        "stateAuthority": False,
        "activeState": P2_004_STATE,
        "claimLevel": "IMPLEMENTED_SOURCE",
    }
    for key, expected in expected_diagnostic.items():
        if diagnostic.get(key) != expected:
            fail(f"P2-004 diagnostic {key} mismatch")


def validate_repository(root: Path) -> dict[str, Any]:
    root = root.resolve()
    task_state = validate_task_state(load_json(root / P2_004_STATE), root)
    phase_state = validate_phase_state(load_json(root / P2_PHASE_STATE), root)
    _validate_legacy_annotations(root)
    if phase_state["activeTaskRecords"]["P2-004"] != P2_004_STATE:
        fail("phase/task active-state binding mismatch")
    if task_state["status"] != phase_state["taskStates"]["P2-004"]:
        fail("phase/task status mismatch")
    return {
        "schemaVersion": "1.0.0",
        "phase": "P2",
        "status": "incomplete",
        "acceptedDecisionTasks": ["P2-004"],
        "behaviorCertifiedTasks": [],
        "platformQualified": False,
        "releaseSupported": False,
        "productionSupported": False,
        "gaPromoted": False,
        "canonicalTaskState": P2_004_STATE,
        "canonicalPhaseState": P2_PHASE_STATE,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--json-output")
    args = parser.parse_args()
    try:
        result = validate_repository(Path(args.project))
    except EvidenceStateError as error:
        raise SystemExit(f"P2_EVIDENCE_STATE_FAILED: {error}") from error
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    print(rendered, end="")
    if args.json_output:
        output = Path(args.json_output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
