#!/usr/bin/env python3
"""Executable v1.7 model-router, verifier, and convergence gates."""
from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import os
from pathlib import Path
import tempfile
import time
from typing import Callable

import execution_intelligence as ei

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "test" / "product" / "fixtures" / "execution_intelligence"


@dataclasses.dataclass
class Result:
    name: str
    passed: bool
    detail: str
    durationMs: int



def duration_ms(started: float) -> int:
    if "SOURCE_DATE_EPOCH" in os.environ:
        return 0
    return int((time.monotonic() - started) * 1000)

def case(name: str, action: Callable[[], str], results: list[Result]) -> None:
    started = time.monotonic()
    try:
        detail = action()
        results.append(Result(name, True, detail, duration_ms(started)))
    except Exception as exc:  # noqa: BLE001 - gate must aggregate failures
        results.append(Result(name, False, f"{type(exc).__name__}: {exc}", duration_ms(started)))


def require(condition: bool, detail: str) -> str:
    if not condition:
        raise AssertionError(detail)
    return detail


def load(name: str) -> dict[str, object]:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def empty_delta() -> ei.ProgressDelta:
    return ei.SemanticProgressEngine().compare(
        ei.ProgressSnapshot.from_json(load("progress_noop.json")["before"]),
        ei.ProgressSnapshot.from_json(load("progress_noop.json")["after"]),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    results: list[Result] = []

    case(
        "Semantic progress detects material artifact mutation",
        lambda: require(
            ei.progress_document(load("progress_mutation.json"))["semanticProgress"] is True,
            "artifact hash, evidence, resolved error, and criterion changes count as progress",
        ),
        results,
    )
    case(
        "Repeated inspection is not semantic progress",
        lambda: require(
            ei.progress_document(load("progress_noop.json"))["semanticProgress"] is False,
            "identical artifact/evidence/error state is a deterministic no-progress turn",
        ),
        results,
    )
    case(
        "Repeated action and result fingerprints are surfaced",
        lambda: require(
            ei.progress_document(load("progress_noop.json"))["repeatedAction"]
            and ei.progress_document(load("progress_noop.json"))["repeatedResult"],
            "action and result repetition are explicit ledger facts",
        ),
        results,
    )
    case(
        "New evidence counts once",
        lambda: require(
            ei.SemanticProgressEngine().compare(
                ei.ProgressSnapshot({}, frozenset(), frozenset(), frozenset(), frozenset()),
                ei.ProgressSnapshot({}, frozenset({"ev-1"}), frozenset(), frozenset(), frozenset()),
            ).new_evidence == ("ev-1",),
            "one new evidence identifier is recorded",
        ),
        results,
    )
    case(
        "Resolving an error counts as progress",
        lambda: require(
            ei.SemanticProgressEngine().compare(
                ei.ProgressSnapshot({}, frozenset(), frozenset({"e1"}), frozenset(), frozenset()),
                ei.ProgressSnapshot({}, frozenset(), frozenset(), frozenset(), frozenset()),
            ).resolved_errors == ("e1",),
            "resolved errors are positive durable progress",
        ),
        results,
    )
    case(
        "New error alone does not masquerade as progress",
        lambda: require(
            not ei.SemanticProgressEngine().compare(
                ei.ProgressSnapshot({}, frozenset(), frozenset(), frozenset(), frozenset()),
                ei.ProgressSnapshot({}, frozenset(), frozenset({"new"}), frozenset(), frozenset()),
            ).semantic_progress,
            "regression is visible but not rewarded",
        ),
        results,
    )
    case(
        "Plan revision counts only when hash changes",
        lambda: require(
            ei.SemanticProgressEngine().compare(
                ei.ProgressSnapshot({}, frozenset(), frozenset(), frozenset(), frozenset(), "a"),
                ei.ProgressSnapshot({}, frozenset(), frozenset(), frozenset(), frozenset(), "b"),
            ).plan_revised,
            "a changed validated plan hash is semantic progress",
        ),
        results,
    )

    route = ei.route_document(load("routing_policy.json"))
    case(
        "Role router chooses the best approved local executor",
        lambda: require(
            route["selected"]["model"] == "qwen2.5-coder:14b",
            "preferred high-reliability local executor selected",
        ),
        results,
    )
    case(
        "Local-only policy rejects cloud escalation",
        lambda: require(
            any("local_only_policy" in row["reasons"] for row in route["rejected"] if row["identity"].startswith("cloud-example/")),
            "public-cloud candidate is rejected before scoring",
        ),
        results,
    )
    case(
        "Open provider circuit is ineligible",
        lambda: _open_circuit_route(),
        results,
    )
    case(
        "Half-open provider can receive one probe",
        lambda: _half_open_route(),
        results,
    )
    case(
        "Fallback approval cannot be invented",
        lambda: _fallback_approval_route(),
        results,
    )
    case(
        "Insufficient context is rejected",
        lambda: _context_route(),
        results,
    )
    case(
        "Unsupported role is rejected",
        lambda: _role_route(),
        results,
    )
    case(
        "Routing decisions are deterministic",
        lambda: require(
            ei.route_document(load("routing_policy.json"))["decisionHash"] == route["decisionHash"],
            "same policy and health produce the same decision hash",
        ),
        results,
    )

    case(
        "Circuit opens after threshold failures",
        lambda: _circuit_opens(),
        results,
    )
    case(
        "Circuit success resets failure streak",
        lambda: _circuit_resets(),
        results,
    )
    case(
        "Circuit cooldown enters half-open",
        lambda: _circuit_cooldown(),
        results,
    )

    case(
        "Independent verifier accepts objective passing evidence",
        lambda: require(
            ei.IndependentVerifier().verify(load("verifier_pass.json")).passed,
            "artifact and test criteria are supported independently",
        ),
        results,
    )
    case(
        "Executor prose cannot satisfy completion",
        lambda: require(
            not ei.IndependentVerifier().verify(load("verifier_false_success.json")).passed,
            "model narrative is not objective evidence",
        ),
        results,
    )
    case(
        "Failed validator blocks completion",
        lambda: _failed_validator(),
        results,
    )
    case(
        "Stale evidence is ignored",
        lambda: _stale_evidence(),
        results,
    )
    case(
        "Required evidence kind must be present",
        lambda: _required_kind(),
        results,
    )
    case(
        "Manual criterion remains blocked without human evidence",
        lambda: _manual_blocked(),
        results,
    )
    case(
        "Free-form completion claim is reported unsupported",
        lambda: _freeform_claim(),
        results,
    )
    case(
        "Verification report hash is deterministic",
        lambda: require(
            ei.IndependentVerifier().verify(load("verifier_pass.json")).report_hash
            == ei.IndependentVerifier().verify(load("verifier_pass.json")).report_hash,
            "same evidence produces the same report hash",
        ),
        results,
    )

    case("Progress continues without escalation", lambda: _strategy(0, True, ei.StrategyAction.CONTINUE), results)
    case("First stall compacts context", lambda: _strategy(1, False, ei.StrategyAction.COMPACT_AND_RETRY), results)
    case("Repeated stall requires a different action", lambda: _strategy(2, False, ei.StrategyAction.REQUIRE_DIFFERENT_ACTION), results)
    case("Third stall routes to independent verifier", lambda: _strategy(3, False, ei.StrategyAction.ROUTE_TO_VERIFIER), results)
    case("Fourth stall splits the task", lambda: _strategy(4, False, ei.StrategyAction.SPLIT_TASK), results)
    case("Fifth stall asks one user question", lambda: _strategy(5, False, ei.StrategyAction.ASK_USER), results)
    case("Cloud or stronger fallback requires approval", lambda: _strategy_offer(), results)
    case("Exhausted strategy fails precisely", lambda: _strategy_fail(), results)
    case("Convergence never widens permissions", lambda: _no_permission_widening(), results)

    case(
        "Context compactor removes duplicates",
        lambda: _compact_duplicates(),
        results,
    )
    case(
        "Context compactor retains high-value errors and criteria",
        lambda: _compact_high_value(),
        results,
    )
    case(
        "Context compaction is deterministic",
        lambda: _compact_deterministic(),
        results,
    )
    case(
        "Execution phase budgets are separated",
        lambda: require(
            ei.PhaseBudget.defaults("routing").max_model_requests == 1
            and ei.PhaseBudget.defaults("execution").max_tool_calls == 16
            and ei.PhaseBudget.defaults("verification").max_repairs == 2,
            "routing, execution, and verification use distinct ceilings",
        ),
        results,
    )
    case(
        "Unknown routing authority field fails closed",
        lambda: _unknown_field(),
        results,
    )

    payload = {
        "schemaVersion": "1.0.0",
        "version": ei.VERSION,
        "caseCount": len(results),
        "passedCount": sum(item.passed for item in results),
        "failedCount": sum(not item.passed for item in results),
        "passed": all(item.passed for item in results),
        "results": [dataclasses.asdict(item) for item in results],
    }
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for item in results:
            print(f"{'PASS' if item.passed else 'FAIL'} {item.name}: {item.detail}")
        print(f"\n{payload['passedCount']}/{payload['caseCount']} execution-intelligence cases passed")
    return 0 if payload["passed"] else 1


def _candidate(**overrides: object) -> ei.ModelCandidate:
    base: dict[str, object] = {
        "provider": "ollama",
        "model": "coder",
        "roles": ["executor"],
        "dataBoundary": "local",
        "contextTokens": 16000,
        "benchmarkScore": 0.8,
        "latencyMsP50": 1000,
        "costPerMillionTokens": 0,
        "toolSchemaScore": 0.9,
        "approved": True,
        "enabled": True,
    }
    base.update(overrides)
    return ei.ModelCandidate.from_json(base)


def _request(**overrides: object) -> ei.RoutingRequest:
    base: dict[str, object] = {
        "role": "executor",
        "requiredContextTokens": 8000,
        "maximumDataBoundary": "local",
        "allowedProviders": ["ollama"],
        "preferredModels": [],
        "localOnly": True,
        "requireToolSchemaReliability": True,
        "fallbackApprovalGranted": False,
    }
    base.update(overrides)
    return ei.RoutingRequest.from_json(base)


def _open_circuit_route() -> str:
    candidate = _candidate()
    health = ei.ProviderHealth("ollama", "coder", ei.CircuitState.OPEN, 3, opened_at=ei._utc_now())
    decision = ei.ModelRouter().route(_request(), [candidate], {candidate.identity: health})
    return require(decision.selected is None and decision.rejected[0]["reasons"] == ["provider_circuit_open"], "open circuit rejected")


def _half_open_route() -> str:
    candidate = _candidate()
    opened = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=10)).isoformat()
    health = ei.ProviderHealth("ollama", "coder", ei.CircuitState.OPEN, 3, opened_at=opened, cooldown_seconds=1)
    decision = ei.ModelRouter(circuit_breaker=ei.CircuitBreaker(cooldown_seconds=1)).route(_request(), [candidate], {candidate.identity: health})
    return require(decision.selected is not None and decision.eligible[0]["circuitState"] == "half_open", "half-open probe admitted")


def _fallback_approval_route() -> str:
    candidate = _candidate(
        provider="cloud",
        model="strong",
        dataBoundary="public_cloud",
        requiresExplicitFallbackApproval=True,
        costPerMillionTokens=10,
    )
    request = _request(localOnly=False, maximumDataBoundary="public_cloud", allowedProviders=["cloud"])
    decision = ei.ModelRouter().route(request, [candidate])
    return require(decision.selected is None and decision.approval_required, "explicit fallback approval required")


def _context_route() -> str:
    decision = ei.ModelRouter().route(_request(requiredContextTokens=32000), [_candidate(contextTokens=16000)])
    return require(decision.selected is None and "context_too_small" in decision.rejected[0]["reasons"], "context limit enforced")


def _role_route() -> str:
    decision = ei.ModelRouter().route(_request(role="verifier"), [_candidate(roles=["executor"])])
    return require(decision.selected is None and "role_unsupported" in decision.rejected[0]["reasons"], "role mismatch enforced")


def _circuit_opens() -> str:
    breaker = ei.CircuitBreaker(failure_threshold=3)
    health = ei.ProviderHealth("ollama", "coder")
    health = breaker.record_failure(health, failure_class="timeout", at="2026-07-22T00:00:00+00:00")
    health = breaker.record_failure(health, failure_class="timeout", at="2026-07-22T00:00:01+00:00")
    health = breaker.record_failure(health, failure_class="protocol", at="2026-07-22T00:00:02+00:00")
    return require(health.state == ei.CircuitState.OPEN and health.timeout_failures == 2 and health.malformed_failures == 1, "threshold opens circuit with typed counts")


def _circuit_resets() -> str:
    breaker = ei.CircuitBreaker()
    health = ei.ProviderHealth("ollama", "coder", ei.CircuitState.OPEN, 4, opened_at="2026-07-22T00:00:00+00:00")
    reset = breaker.record_success(health, at="2026-07-22T00:05:00+00:00")
    return require(reset.state == ei.CircuitState.CLOSED and reset.consecutive_failures == 0 and reset.opened_at is None, "success closes circuit")


def _circuit_cooldown() -> str:
    breaker = ei.CircuitBreaker(cooldown_seconds=30)
    health = ei.ProviderHealth("ollama", "coder", ei.CircuitState.OPEN, 3, opened_at="2026-07-22T00:00:00+00:00", cooldown_seconds=30)
    now = dt.datetime(2026, 7, 22, 0, 1, tzinfo=dt.timezone.utc)
    return require(breaker.effective_state(health, now=now) == ei.CircuitState.HALF_OPEN, "cooldown creates half-open probe state")


def _failed_validator() -> str:
    doc = load("verifier_pass.json")
    doc["evidence"][0]["ok"] = False
    report = ei.IndependentVerifier().verify(doc)
    return require(not report.passed and report.findings[0].status == ei.VerificationStatus.FAILED, "failing validator blocks completion")


def _stale_evidence() -> str:
    doc = load("verifier_pass.json")
    doc["evidence"][0]["stale"] = True
    report = ei.IndependentVerifier().verify(doc)
    return require(not report.passed and report.findings[0].status == ei.VerificationStatus.UNSUPPORTED, "stale evidence cannot support a criterion")


def _required_kind() -> str:
    doc = load("verifier_pass.json")
    doc["criteria"][0]["requiredEvidenceKinds"] = ["artifact_validation", "test"]
    report = ei.IndependentVerifier().verify(doc)
    return require(report.findings[0].status == ei.VerificationStatus.UNSUPPORTED, "all declared evidence kinds are required")


def _manual_blocked() -> str:
    report = ei.IndependentVerifier().verify({
        "criteria": [{"id": "manual", "statement": "Human confirms visual quality.", "manual": True, "requiredEvidenceKinds": []}],
        "evidence": [],
        "completionClaims": [],
    })
    return require(report.findings[0].status == ei.VerificationStatus.BLOCKED, "manual criterion awaits human evidence")


def _freeform_claim() -> str:
    doc = load("verifier_pass.json")
    doc["completionClaims"].append("Everything is perfect")
    report = ei.IndependentVerifier().verify(doc)
    return require(not report.passed and report.unsupported_completion_claims == ("Everything is perfect",), "free-form claim is unsupported")


def _strategy(no_progress: int, progress: bool, expected: ei.StrategyAction) -> str:
    delta = empty_delta()
    if progress:
        delta = dataclasses.replace(delta, semantic_progress=True)
    decision = ei.ConvergenceController().decide(
        delta=delta,
        consecutive_no_progress=no_progress,
        repeated_action_count=no_progress,
        repairs_remaining=4,
        verifier_available=True,
        task_can_split=True,
        ask_user_allowed=True,
        stronger_model_available=False,
        stronger_model_approved=False,
    )
    return require(decision.action == expected, f"selected {expected.value}")


def _strategy_offer() -> str:
    decision = ei.ConvergenceController().decide(
        delta=empty_delta(), consecutive_no_progress=6, repeated_action_count=6,
        repairs_remaining=2, verifier_available=False, task_can_split=False,
        ask_user_allowed=False, stronger_model_available=True, stronger_model_approved=False,
    )
    return require(decision.action == ei.StrategyAction.OFFER_STRONGER_MODEL and decision.requires_user_approval, "stronger model is offered, not silently selected")


def _strategy_fail() -> str:
    decision = ei.ConvergenceController().decide(
        delta=empty_delta(), consecutive_no_progress=7, repeated_action_count=7,
        repairs_remaining=0, verifier_available=False, task_can_split=False,
        ask_user_allowed=False, stronger_model_available=False, stronger_model_approved=False,
    )
    return require(decision.action == ei.StrategyAction.FAIL_CONVERGENCE, "bounded convergence terminates precisely")


def _no_permission_widening() -> str:
    controller = ei.ConvergenceController()
    decisions = [
        controller.decide(
            delta=empty_delta(), consecutive_no_progress=value, repeated_action_count=value,
            repairs_remaining=4, verifier_available=True, task_can_split=True,
            ask_user_allowed=True, stronger_model_available=True, stronger_model_approved=False,
        )
        for value in range(1, 8)
    ]
    return require(all(not item.permission_widening_allowed for item in decisions), "no strategy can widen permissions")


def _history() -> list[dict[str, object]]:
    return [
        {"id": "1", "kind": "command", "summary": "Listed root", "tool": "list_directory", "resultHash": "a", "turn": 1},
        {"id": "2", "kind": "command", "summary": "Listed   root", "tool": "list_directory", "resultHash": "a", "turn": 2},
        {"id": "3", "kind": "error", "summary": "Artifact is empty", "errorCode": "artifact_scope_incomplete", "turn": 3},
        {"id": "4", "kind": "criterion", "summary": "Wireframe scope remains unmet", "criterionId": "c1", "turn": 4},
        {"id": "5", "kind": "mutation", "summary": "Updated artifact", "path": "docs/design/wireframes.md", "sha256": "b" * 64, "turn": 5},
    ]


def _compact_duplicates() -> str:
    compacted = ei.ContextCompactor().compact(_history(), maximum_characters=4000, recent_count=2)
    return require(compacted["duplicatesRemoved"] == 1 and compacted["deduplicatedCount"] == 4, "one normalized duplicate removed")


def _compact_high_value() -> str:
    compacted = ei.ContextCompactor().compact(_history(), maximum_characters=2200, recent_count=1)
    kinds = {entry.get("kind") for entry in compacted["entries"]}
    return require({"error", "criterion", "mutation"}.issubset(kinds), "high-value facts retained")


def _compact_deterministic() -> str:
    a = ei.ContextCompactor().compact(_history())
    b = ei.ContextCompactor().compact(_history())
    return require(a["contextHash"] == b["contextHash"], "same history produces same context hash")


def _unknown_field() -> str:
    doc = load("routing_policy.json")
    doc["request"]["allowAnyProvider"] = True
    try:
        ei.route_document(doc)
    except ei.IntelligenceInputError:
        return "unknown authority-bearing field rejected"
    raise AssertionError("unknown field was accepted")


if __name__ == "__main__":
    raise SystemExit(main())
