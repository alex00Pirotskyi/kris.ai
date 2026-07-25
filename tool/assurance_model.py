#!/usr/bin/env python3
"""Assurance taxonomy and report helpers for Kristin.

The central invariant is deliberately strict: source inspection may establish
that code, wiring, schemas, or tests exist, but it never proves runtime
behavior. Mixed gates are useful migration checks, yet they are not counted as
pure behavioral evidence until their executable result is reported separately.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Iterable, Mapping

SCHEMA_VERSION = "1.0.0"

ASSURANCE_ARCHITECTURE_LINT = "architecture_lint"
ASSURANCE_SOURCE_CONTRACT = "source_contract"
ASSURANCE_BEHAVIORAL = "behavioral"
ASSURANCE_SDK_TOOLCHAIN = "sdk_toolchain"
ASSURANCE_PLATFORM = "platform"
ASSURANCE_RELEASE = "release"
ASSURANCE_MIXED = "mixed"
ASSURANCE_UNCLASSIFIED = "unclassified"

PROOF_SOURCE_INSPECTION = "source_inspection"
PROOF_EXECUTED_BEHAVIOR = "executed_behavior"
PROOF_TOOLCHAIN_EXECUTION = "toolchain_execution"
PROOF_PLATFORM_EXECUTION = "platform_execution"
PROOF_RELEASE_EXECUTION = "release_execution"
PROOF_MIXED = "mixed"
PROOF_UNCLASSIFIED = "unclassified"

STATUS_PASSED = "passed"
STATUS_FAILED = "failed"
STATUS_UNAVAILABLE = "unavailable"
STATUS_NOT_RUN = "not_run"
VALID_STATUSES = {
    STATUS_PASSED,
    STATUS_FAILED,
    STATUS_UNAVAILABLE,
    STATUS_NOT_RUN,
}

SOURCE_ONLY_FUNCTIONS = {
    "check_required_files",
    "check_active_tree_layout",
    "check_imports_and_syntax",
    "check_architecture",
    "check_security",
    "check_flutter_dart_compatibility",
    "check_chat_workspace_ux",
    "check_knowledge_memory",
    "check_execution_reliability",
    "check_linux_sandbox_backfill",
    "check_v1_product_preview",
    "check_release_hygiene",
    "check_supply_chain",
}

MIXED_FUNCTIONS = {
    "check_typed_protocol_contracts",
    "check_prompt_studio_v2",
    "check_project_manager_v2",
    "check_execution_intelligence",
    "check_diagnostic_replay",
    "check_knowledge_memory_v18",
    "check_interoperability_v19",
    "check_release_ops_v19",
    "check_file_adapters_v18",
    "check_v1_trust_disablement",
    "check_policy_support",
}

PURE_BEHAVIORAL_FUNCTIONS = {
    "check_durable_workflow_kernel",
}

SDK_CHECK_NAMES = {
    "dart format",
    "flutter pub get",
    "flutter analyze",
    "flutter test",
}


@dataclass(frozen=True)
class AssuranceClassification:
    assurance_level: str
    proof_kind: str
    behavioral_proof: bool
    claim_scope: str
    rationale: str

    def as_dict(self) -> dict[str, object]:
        return asdict(self)


def _classification(
    assurance_level: str,
    proof_kind: str,
    behavioral_proof: bool,
    claim_scope: str,
    rationale: str,
) -> AssuranceClassification:
    if behavioral_proof and proof_kind not in {
        PROOF_EXECUTED_BEHAVIOR,
        PROOF_PLATFORM_EXECUTION,
        PROOF_RELEASE_EXECUTION,
    }:
        raise ValueError(
            "behavioral proof requires executable, platform, or release evidence"
        )
    if proof_kind in {PROOF_SOURCE_INSPECTION, PROOF_MIXED} and behavioral_proof:
        raise ValueError("source or mixed proof cannot be behavioral proof")
    return AssuranceClassification(
        assurance_level=assurance_level,
        proof_kind=proof_kind,
        behavioral_proof=behavioral_proof,
        claim_scope=claim_scope,
        rationale=rationale,
    )


def classify_validator_check(
    source_function: str,
    check_name: str,
) -> AssuranceClassification:
    """Classify a legacy validator check by its implementation source.

    Classification is intentionally based on the function that constructs the
    check rather than on persuasive wording in the check name or detail.
    Unknown functions remain unclassified and block a strict assurance report.
    """
    if source_function in SOURCE_ONLY_FUNCTIONS:
        level = (
            ASSURANCE_ARCHITECTURE_LINT
            if source_function
            in {
                "check_required_files",
                "check_active_tree_layout",
                "check_imports_and_syntax",
                "check_architecture",
                "check_flutter_dart_compatibility",
                "check_release_hygiene",
                "check_supply_chain",
            }
            else ASSURANCE_SOURCE_CONTRACT
        )
        return _classification(
            level,
            PROOF_SOURCE_INSPECTION,
            False,
            "source_and_wiring_only",
            "The check inspects source, files, syntax, or marker contracts and does not execute the claimed product behavior.",
        )
    if source_function in MIXED_FUNCTIONS:
        return _classification(
            ASSURANCE_MIXED,
            PROOF_MIXED,
            False,
            "mixed_source_and_execution_not_behavioral_proof",
            "The legacy check combines an executable command with source-marker assertions; it is excluded from pure behavioral totals until split evidence is reported.",
        )
    if source_function in PURE_BEHAVIORAL_FUNCTIONS:
        return _classification(
            ASSURANCE_BEHAVIORAL,
            PROOF_EXECUTED_BEHAVIOR,
            True,
            "runtime_behavior",
            "The check executes a behaviorally observable integration harness and validates its result independently of source markers.",
        )
    if source_function == "check_sdk" and check_name in SDK_CHECK_NAMES:
        return _classification(
            ASSURANCE_SDK_TOOLCHAIN,
            PROOF_TOOLCHAIN_EXECUTION,
            False,
            "sdk_and_toolchain",
            "The check proves formatter, dependency, analyzer, or test-runner execution; it is not by itself a product-behavior claim.",
        )
    return _classification(
        ASSURANCE_UNCLASSIFIED,
        PROOF_UNCLASSIFIED,
        False,
        "unclassified",
        f"No explicit assurance classification exists for {source_function}:{check_name}.",
    )


def _bool(value: object) -> bool:
    return value is True


def _check_dict(item: Mapping[str, Any] | object) -> dict[str, Any]:
    if isinstance(item, Mapping):
        return dict(item)
    if hasattr(item, "as_dict"):
        value = item.as_dict()
        if isinstance(value, Mapping):
            return dict(value)
    if hasattr(item, "__dict__"):
        return dict(vars(item))
    raise TypeError(f"unsupported check record: {type(item)!r}")


def _group_state(records: list[dict[str, Any]]) -> dict[str, object]:
    blocking = [item for item in records if item.get("blocking", True) is True]
    failed = [item for item in blocking if item.get("status") == STATUS_FAILED]
    unavailable = [
        item
        for item in blocking
        if item.get("status") in {STATUS_UNAVAILABLE, STATUS_NOT_RUN}
    ]
    passed = [item for item in records if item.get("status") == STATUS_PASSED]
    complete = bool(blocking) and not failed and not unavailable
    return {
        "count": len(records),
        "blockingCount": len(blocking),
        "passedCount": len(passed),
        "failedCount": len(failed),
        "unavailableCount": len(unavailable),
        "complete": complete,
        "passed": bool(blocking) and not failed,
        "failedChecks": [str(item.get("name", "")) for item in failed],
        "unavailableChecks": [
            str(item.get("name", "")) for item in unavailable
        ],
    }


def summarize_assurance_checks(
    checks: Iterable[Mapping[str, Any] | object],
) -> dict[str, object]:
    """Build a machine-readable summary without upgrading source evidence.

    A pure behavioral pass exists only when at least one blocking check is
    explicitly classified as behavioral proof and every blocking behavioral
    check passed. Source and mixed checks never contribute to that result.
    """
    records = [_check_dict(item) for item in checks]
    invalid_status = [
        str(item.get("name", ""))
        for item in records
        if item.get("status") not in VALID_STATUSES
    ]
    overclaims = [
        str(item.get("name", ""))
        for item in records
        if _bool(item.get("behavioral_proof"))
        and item.get("proof_kind")
        in {PROOF_SOURCE_INSPECTION, PROOF_MIXED, PROOF_UNCLASSIFIED}
    ]
    unclassified = [
        str(item.get("name", ""))
        for item in records
        if item.get("assurance_level") == ASSURANCE_UNCLASSIFIED
        or item.get("proof_kind") == PROOF_UNCLASSIFIED
    ]

    groups: dict[str, list[dict[str, Any]]] = {
        "source": [],
        "mixed": [],
        "behavioral": [],
        "sdkToolchain": [],
        "platform": [],
        "release": [],
        "unclassified": [],
    }
    for item in records:
        level = item.get("assurance_level")
        proof = item.get("proof_kind")
        if level in {ASSURANCE_ARCHITECTURE_LINT, ASSURANCE_SOURCE_CONTRACT}:
            groups["source"].append(item)
        elif level == ASSURANCE_MIXED or proof == PROOF_MIXED:
            groups["mixed"].append(item)
        elif _bool(item.get("behavioral_proof")) and proof == PROOF_EXECUTED_BEHAVIOR:
            groups["behavioral"].append(item)
        elif level == ASSURANCE_SDK_TOOLCHAIN or proof == PROOF_TOOLCHAIN_EXECUTION:
            groups["sdkToolchain"].append(item)
        elif level == ASSURANCE_PLATFORM or proof == PROOF_PLATFORM_EXECUTION:
            groups["platform"].append(item)
        elif level == ASSURANCE_RELEASE or proof == PROOF_RELEASE_EXECUTION:
            groups["release"].append(item)
        else:
            groups["unclassified"].append(item)

    group_states = {name: _group_state(value) for name, value in groups.items()}
    behavioral_records = groups["behavioral"]
    behavioral_blocking = [
        item for item in behavioral_records if item.get("blocking", True) is True
    ]
    behavioral_assurance_passed = bool(behavioral_blocking) and all(
        item.get("status") == STATUS_PASSED for item in behavioral_blocking
    )
    classification_complete = not unclassified and not invalid_status
    no_overclaim = not overclaims
    blocking_unavailable = [
        str(item.get("name", ""))
        for item in records
        if item.get("blocking", True) is True
        and item.get("status") in {STATUS_UNAVAILABLE, STATUS_NOT_RUN}
    ]
    strict_valid = (
        classification_complete and no_overclaim and not blocking_unavailable
    )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "classificationComplete": classification_complete,
        "noSourceMarkerOverclaim": no_overclaim,
        "strictValid": strict_valid,
        "behavioralAssurancePassed": behavioral_assurance_passed,
        "sourceContractPassed": bool(group_states["source"]["complete"]),
        "mixedChecksCountAsBehavioral": False,
        "unclassifiedChecks": unclassified,
        "invalidStatusChecks": invalid_status,
        "blockingUnavailableChecks": blocking_unavailable,
        "overclaimChecks": overclaims,
        "groups": group_states,
        "limitations": [
            "Source-contract and architecture-lint results establish source shape and wiring only.",
            "Mixed checks are not counted as pure behavioral evidence.",
            "Platform and release claims require their own executable lane evidence.",
        ],
    }


def validate_assurance_summary(summary: Mapping[str, Any]) -> list[str]:
    failures: list[str] = []
    if summary.get("schemaVersion") != SCHEMA_VERSION:
        failures.append("assurance summary schema version is invalid")
    if summary.get("classificationComplete") is not True:
        failures.append("one or more checks are unclassified")
    if summary.get("noSourceMarkerOverclaim") is not True:
        failures.append("source or mixed checks were counted as behavioral proof")
    if summary.get("mixedChecksCountAsBehavioral") is not False:
        failures.append("mixed checks must never count as behavioral proof")
    if summary.get("blockingUnavailableChecks"):
        failures.append("one or more blocking checks are unavailable or not run")
    return failures
