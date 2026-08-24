#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Iterable, Mapping


ASSURANCE_LEVELS = {
    "architecture_lint",
    "unit",
    "component",
    "integration",
    "platform",
    "adversarial",
    "benchmark",
    "release",
}
OWASP_AGENTIC_IDS = {f"ASI{index:02d}" for index in range(1, 11)}
NIST_FUNCTIONS = {"GOVERN", "MAP", "MEASURE", "MANAGE"}
EXTERNAL_BLOCKERS = {"P1A", "P5-015", "P8-011", "P8-014"}
REPLAY_CATEGORIES = {
    "workflow",
    "terminal",
    "browser",
    "research",
    "interoperability",
    "effects",
    "authority",
    "security",
    "supply_chain",
}
REQUIRED_SOURCE_ARTIFACTS = {
    "lib/product/p5_ui_quality.dart",
    "lib/product/agent_context_v2.dart",
    "lib/product/agent_decision_v3.dart",
    "lib/product/agent_protocol_v3.dart",
    "lib/product/model/model_registry.dart",
    "lib/product/model/model_routing_v2.dart",
    "lib/product/mcp_registry_v2.dart",
    "tool/agent_safety_v2.py",
    "tool/agent_benchmark_signing.py",
    "tool/a2a_protocol_v1.py",
    "tool/a2a_bridge.py",
    "tool/extension_registry_v2.py",
    "tool/p1a_install_doctor.py",
    "lib/product/p8_effect_journal_adapter.dart",
    "lib/product/p8_external_effects.dart",
    "lib/product/p8_observability.dart",
    "tool/secret_scan.py",
    "tool/dependency_policy.py",
    "tool/p8_soak_gate.py",
    "tool/p8_terminal_fault_harness.py",
    "test/product/p8_research_adversarial_test.dart",
    "docs/INTEROPERABILITY_SECURITY.md",
}


def load_json(path: Path) -> dict[str, Any]:
    decoded = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(decoded, dict):
        raise ValueError(f"json_object_required:{path}")
    return decoded


def require_exact(actual: Iterable[str], expected: set[str], code: str, failures: list[str]) -> None:
    actual_set = set(actual)
    if actual_set != expected:
        missing = sorted(expected - actual_set)
        extra = sorted(actual_set - expected)
        failures.append(f"{code}:missing={missing}:extra={extra}")


def validate(root: Path) -> dict[str, Any]:
    failures: list[str] = []
    evidence_root = root / "release" / "evidence" / "P8"
    security_root = root / "release" / "security"

    hierarchy = load_json(evidence_root / "test-hierarchy.v1.json")
    levels = hierarchy.get("assuranceLevels")
    if not isinstance(levels, list):
        failures.append("assurance_levels_missing")
        levels = []
    require_exact(
        (str(item.get("id") or "") for item in levels if isinstance(item, dict)),
        ASSURANCE_LEVELS,
        "assurance_levels_invalid",
        failures,
    )
    for item in levels:
        if not isinstance(item, dict):
            failures.append("assurance_level_not_object")
            continue
        if not isinstance(item.get("behavioralProof"), bool):
            failures.append(f"assurance_behavioral_truth_missing:{item.get('id')}")
        for entry_point in item.get("entryPoints") or []:
            if not (root / str(entry_point)).exists():
                failures.append(f"assurance_entry_point_missing:{entry_point}")

    agentic = load_json(security_root / "agentic-risk-map.v1.json")
    risks = agentic.get("risks")
    if not isinstance(risks, list):
        failures.append("owasp_risks_missing")
        risks = []
    require_exact(
        (str(item.get("id") or "") for item in risks if isinstance(item, dict)),
        OWASP_AGENTIC_IDS,
        "owasp_risk_ids_invalid",
        failures,
    )
    for risk in risks:
        if not isinstance(risk, dict):
            failures.append("owasp_risk_not_object")
            continue
        if risk.get("status") != "source_controls_present_external_validation_pending":
            failures.append(f"owasp_risk_truth_boundary_invalid:{risk.get('id')}")
        if not str(risk.get("owner") or "").strip():
            failures.append(f"owasp_risk_owner_missing:{risk.get('id')}")

    nist = load_json(security_root / "nist-ai-rmf-map.v1.json")
    functions = nist.get("functions")
    if not isinstance(functions, list):
        failures.append("nist_functions_missing")
        functions = []
    require_exact(
        (str(item.get("function") or "") for item in functions if isinstance(item, dict)),
        NIST_FUNCTIONS,
        "nist_functions_invalid",
        failures,
    )
    register = nist.get("riskRegister")
    if not isinstance(register, list) or not register:
        failures.append("nist_risk_register_missing")

    pen = load_json(security_root / "penetration-test-requirements.v1.json")
    if pen.get("status") != "pending_external_assessment" or pen.get("completionClaim") is not False:
        failures.append("penetration_test_truth_boundary_invalid")
    if pen.get("independentReviewerRequired") is not True or pen.get("releaseBlocker") is not True:
        failures.append("penetration_test_independence_invalid")

    blockers = load_json(evidence_root / "release-blockers.v1.json")
    rows = blockers.get("blockers")
    if not isinstance(rows, list):
        failures.append("release_blockers_missing")
        rows = []
    require_exact(
        (str(item.get("id") or "") for item in rows if isinstance(item, dict)),
        EXTERNAL_BLOCKERS,
        "external_blockers_invalid",
        failures,
    )
    if blockers.get("sourceTrainMergeAllowed") is not True:
        failures.append("source_train_merge_truth_invalid")
    if blockers.get("productionReleaseAllowed") is not False:
        failures.append("production_release_truth_invalid")
    for row in rows:
        if not isinstance(row, dict):
            failures.append("release_blocker_not_object")
            continue
        if row.get("status") != "pending_external_evidence":
            failures.append(f"release_blocker_status_invalid:{row.get('id')}")
        validator = str(row.get("validator") or "")
        if not validator or not (root / validator).exists():
            failures.append(f"release_blocker_validator_missing:{row.get('id')}:{validator}")

    replay = load_json(evidence_root / "failure-replay-corpus.v1.json")
    if replay.get("productionIncidentCorpus") is not False:
        failures.append("replay_corpus_origin_truth_invalid")
    cases = replay.get("cases")
    if not isinstance(cases, list):
        failures.append("replay_cases_missing")
        cases = []
    ids: set[str] = set()
    categories: set[str] = set()
    for case in cases:
        if not isinstance(case, dict):
            failures.append("replay_case_not_object")
            continue
        case_id = str(case.get("id") or "")
        if not case_id or case_id in ids:
            failures.append(f"replay_case_id_invalid:{case_id}")
        ids.add(case_id)
        category = str(case.get("category") or "")
        categories.add(category)
        test_path = str(case.get("testPath") or "")
        if not test_path or not (root / test_path).is_file():
            failures.append(f"replay_test_missing:{case_id}:{test_path}")
        if not str(case.get("expectedBoundary") or "").strip():
            failures.append(f"replay_expected_boundary_missing:{case_id}")
    missing_categories = sorted(REPLAY_CATEGORIES - categories)
    if missing_categories:
        failures.append(f"replay_categories_missing:{missing_categories}")

    for artifact in sorted(REQUIRED_SOURCE_ARTIFACTS):
        if not (root / artifact).exists():
            failures.append(f"required_source_artifact_missing:{artifact}")

    canonical = {
        "assuranceLevels": sorted(ASSURANCE_LEVELS),
        "owaspAgenticIds": sorted(OWASP_AGENTIC_IDS),
        "nistFunctions": sorted(NIST_FUNCTIONS),
        "externalBlockers": sorted(EXTERNAL_BLOCKERS),
        "replayCaseIds": sorted(ids),
        "requiredSourceArtifacts": sorted(REQUIRED_SOURCE_ARTIFACTS),
    }
    digest = hashlib.sha256(
        json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return {
        "schemaVersion": "1.0.0",
        "passed": not failures,
        "sourceTrainMergeAllowed": not failures,
        "productionReleaseAllowed": False,
        "externalBlockers": sorted(EXTERNAL_BLOCKERS),
        "replayCaseCount": len(ids),
        "convergenceDigestSha256": digest,
        "failures": failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--report")
    args = parser.parse_args()
    root = Path(args.project).resolve()
    report = validate(root)
    if args.report:
        target = Path(args.report).resolve()
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
