#!/usr/bin/env python3
"""Deterministic execution-intelligence primitives for Kristin v1.7.

The module is intentionally standard-library only.  It is the executable
reference implementation for:

* role-aware model routing without implicit privacy escalation;
* provider circuit breakers;
* semantic progress accounting;
* bounded convergence strategy escalation;
* phase-specific budgets;
* independent evidence-based verification; and
* deterministic prompt/history compaction.

Models may propose actions.  This module never grants authority and never runs
project commands.  Its outputs are decisions for the durable workflow kernel to
validate and persist.
"""
from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import enum
import hashlib
import json
import math
from pathlib import Path
import re
import sys
from typing import Any, Iterable, Mapping, Sequence

VERSION = "1.9.0+190"
SCHEMA_VERSION = "1.0.0"


class IntelligenceInputError(ValueError):
    """Raised when a caller supplies an invalid deterministic contract."""


class ModelRole(str, enum.Enum):
    ROUTER = "router"
    SPEC = "spec"
    PLANNER = "planner"
    EXECUTOR = "executor"
    VERIFIER = "verifier"
    SUMMARIZER = "summarizer"
    RESEARCH = "research"
    SAFETY_REVIEWER = "safety_reviewer"


class DataBoundary(str, enum.Enum):
    LOCAL = "local"
    PRIVATE_REMOTE = "private_remote"
    PUBLIC_CLOUD = "public_cloud"

    @property
    def rank(self) -> int:
        return {
            DataBoundary.LOCAL: 0,
            DataBoundary.PRIVATE_REMOTE: 1,
            DataBoundary.PUBLIC_CLOUD: 2,
        }[self]


class CircuitState(str, enum.Enum):
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"


class VerificationStatus(str, enum.Enum):
    SUPPORTED = "supported"
    FAILED = "failed"
    UNSUPPORTED = "unsupported"
    BLOCKED = "blocked"


class StrategyAction(str, enum.Enum):
    CONTINUE = "continue"
    COMPACT_AND_RETRY = "compact_and_retry"
    REQUIRE_DIFFERENT_ACTION = "require_different_action"
    ROUTE_TO_VERIFIER = "route_to_verifier"
    SPLIT_TASK = "split_task"
    ASK_USER = "ask_user"
    OFFER_STRONGER_MODEL = "offer_stronger_model"
    FAIL_CONVERGENCE = "fail_convergence"


def _utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def _as_dict(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise IntelligenceInputError(f"{label} must be a JSON object")
    return {str(key): item for key, item in value.items()}


def _as_list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise IntelligenceInputError(f"{label} must be a JSON array")
    return list(value)


def _string(value: Any, label: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise IntelligenceInputError(f"{label} must be a string")
    result = value.strip()
    if not result and not allow_empty:
        raise IntelligenceInputError(f"{label} must not be empty")
    return result


def _integer(value: Any, label: str, *, minimum: int = 0, maximum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise IntelligenceInputError(f"{label} must be an integer")
    if value < minimum or (maximum is not None and value > maximum):
        suffix = f"..{maximum}" if maximum is not None else " or greater"
        raise IntelligenceInputError(f"{label} must be {minimum}{suffix}")
    return value


def _number(value: Any, label: str, *, minimum: float = 0.0, maximum: float | None = None) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise IntelligenceInputError(f"{label} must be a number")
    number = float(value)
    if not math.isfinite(number):
        raise IntelligenceInputError(f"{label} must be finite")
    if number < minimum or (maximum is not None and number > maximum):
        suffix = f"..{maximum}" if maximum is not None else " or greater"
        raise IntelligenceInputError(f"{label} must be {minimum}{suffix}")
    return number


def _string_set(value: Any, label: str) -> frozenset[str]:
    values = _as_list(value, label)
    result: set[str] = set()
    for index, item in enumerate(values):
        result.add(_string(item, f"{label}[{index}]"))
    return frozenset(result)


@dataclasses.dataclass(frozen=True)
class ProviderHealth:
    provider: str
    model: str
    state: CircuitState = CircuitState.CLOSED
    consecutive_failures: int = 0
    timeout_failures: int = 0
    malformed_failures: int = 0
    opened_at: str | None = None
    cooldown_seconds: int = 120
    last_success_at: str | None = None
    last_failure_at: str | None = None

    @property
    def key(self) -> str:
        return f"{self.provider}/{self.model}"

    @classmethod
    def from_json(cls, raw: Mapping[str, Any]) -> "ProviderHealth":
        data = _as_dict(dict(raw), "providerHealth")
        allowed = {
            "provider", "model", "state", "consecutiveFailures", "timeoutFailures",
            "malformedFailures", "openedAt", "cooldownSeconds", "lastSuccessAt",
            "lastFailureAt",
        }
        unknown = sorted(set(data) - allowed)
        if unknown:
            raise IntelligenceInputError(f"providerHealth has unknown fields: {unknown}")
        try:
            state = CircuitState(str(data.get("state", CircuitState.CLOSED.value)))
        except ValueError as exc:
            raise IntelligenceInputError("providerHealth.state is invalid") from exc
        return cls(
            provider=_string(data.get("provider"), "providerHealth.provider"),
            model=_string(data.get("model"), "providerHealth.model"),
            state=state,
            consecutive_failures=_integer(data.get("consecutiveFailures", 0), "providerHealth.consecutiveFailures"),
            timeout_failures=_integer(data.get("timeoutFailures", 0), "providerHealth.timeoutFailures"),
            malformed_failures=_integer(data.get("malformedFailures", 0), "providerHealth.malformedFailures"),
            opened_at=str(data["openedAt"]) if data.get("openedAt") is not None else None,
            cooldown_seconds=_integer(data.get("cooldownSeconds", 120), "providerHealth.cooldownSeconds", minimum=1, maximum=86400),
            last_success_at=str(data["lastSuccessAt"]) if data.get("lastSuccessAt") is not None else None,
            last_failure_at=str(data["lastFailureAt"]) if data.get("lastFailureAt") is not None else None,
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "provider": self.provider,
            "model": self.model,
            "state": self.state.value,
            "consecutiveFailures": self.consecutive_failures,
            "timeoutFailures": self.timeout_failures,
            "malformedFailures": self.malformed_failures,
            "openedAt": self.opened_at,
            "cooldownSeconds": self.cooldown_seconds,
            "lastSuccessAt": self.last_success_at,
            "lastFailureAt": self.last_failure_at,
        }


class CircuitBreaker:
    """Pure transition logic for provider health.

    The durable workflow store owns persistence.  This class simply calculates
    the next state from a prior state and a recorded outcome.
    """

    def __init__(self, *, failure_threshold: int = 3, cooldown_seconds: int = 120) -> None:
        self.failure_threshold = max(1, int(failure_threshold))
        self.cooldown_seconds = max(1, int(cooldown_seconds))

    @staticmethod
    def _parse_time(value: str | None) -> dt.datetime | None:
        if not value:
            return None
        try:
            parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed if parsed.tzinfo is not None else parsed.replace(tzinfo=dt.timezone.utc)
        except ValueError:
            return None

    def effective_state(self, health: ProviderHealth, *, now: dt.datetime | None = None) -> CircuitState:
        now = now or dt.datetime.now(dt.timezone.utc)
        if health.state != CircuitState.OPEN:
            return health.state
        opened = self._parse_time(health.opened_at)
        if opened is None:
            return CircuitState.OPEN
        if now - opened >= dt.timedelta(seconds=health.cooldown_seconds):
            return CircuitState.HALF_OPEN
        return CircuitState.OPEN

    def permits_request(self, health: ProviderHealth, *, now: dt.datetime | None = None) -> bool:
        return self.effective_state(health, now=now) != CircuitState.OPEN

    def record_success(self, health: ProviderHealth, *, at: str | None = None) -> ProviderHealth:
        stamp = at or _utc_now()
        return dataclasses.replace(
            health,
            state=CircuitState.CLOSED,
            consecutive_failures=0,
            opened_at=None,
            cooldown_seconds=self.cooldown_seconds,
            last_success_at=stamp,
        )

    def record_failure(
        self,
        health: ProviderHealth,
        *,
        failure_class: str,
        at: str | None = None,
    ) -> ProviderHealth:
        stamp = at or _utc_now()
        failure_class = failure_class.strip().lower()
        consecutive = health.consecutive_failures + 1
        should_open = consecutive >= self.failure_threshold or health.state == CircuitState.HALF_OPEN
        return dataclasses.replace(
            health,
            state=CircuitState.OPEN if should_open else CircuitState.CLOSED,
            consecutive_failures=consecutive,
            timeout_failures=health.timeout_failures + (1 if failure_class == "timeout" else 0),
            malformed_failures=health.malformed_failures + (1 if failure_class in {"malformed", "protocol"} else 0),
            opened_at=stamp if should_open else health.opened_at,
            cooldown_seconds=self.cooldown_seconds,
            last_failure_at=stamp,
        )


@dataclasses.dataclass(frozen=True)
class ModelCandidate:
    provider: str
    model: str
    roles: frozenset[ModelRole]
    data_boundary: DataBoundary
    context_tokens: int
    benchmark_score: float
    latency_ms_p50: int
    cost_per_million_tokens: float
    tool_schema_score: float
    approved: bool = True
    requires_explicit_fallback_approval: bool = False
    enabled: bool = True

    @property
    def identity(self) -> str:
        return f"{self.provider}/{self.model}"

    @classmethod
    def from_json(cls, raw: Mapping[str, Any]) -> "ModelCandidate":
        data = _as_dict(dict(raw), "candidate")
        allowed = {
            "provider", "model", "roles", "dataBoundary", "contextTokens",
            "benchmarkScore", "latencyMsP50", "costPerMillionTokens",
            "toolSchemaScore", "approved", "requiresExplicitFallbackApproval",
            "enabled",
        }
        unknown = sorted(set(data) - allowed)
        if unknown:
            raise IntelligenceInputError(f"candidate has unknown fields: {unknown}")
        try:
            roles = frozenset(ModelRole(value) for value in _string_set(data.get("roles", []), "candidate.roles"))
            boundary = DataBoundary(_string(data.get("dataBoundary"), "candidate.dataBoundary"))
        except ValueError as exc:
            raise IntelligenceInputError("candidate role or dataBoundary is invalid") from exc
        if not roles:
            raise IntelligenceInputError("candidate.roles must not be empty")
        return cls(
            provider=_string(data.get("provider"), "candidate.provider"),
            model=_string(data.get("model"), "candidate.model"),
            roles=roles,
            data_boundary=boundary,
            context_tokens=_integer(data.get("contextTokens"), "candidate.contextTokens", minimum=512),
            benchmark_score=_number(data.get("benchmarkScore", 0), "candidate.benchmarkScore", maximum=1),
            latency_ms_p50=_integer(data.get("latencyMsP50", 0), "candidate.latencyMsP50"),
            cost_per_million_tokens=_number(data.get("costPerMillionTokens", 0), "candidate.costPerMillionTokens"),
            tool_schema_score=_number(data.get("toolSchemaScore", 0), "candidate.toolSchemaScore", maximum=1),
            approved=bool(data.get("approved", True)),
            requires_explicit_fallback_approval=bool(data.get("requiresExplicitFallbackApproval", False)),
            enabled=bool(data.get("enabled", True)),
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "provider": self.provider,
            "model": self.model,
            "roles": sorted(role.value for role in self.roles),
            "dataBoundary": self.data_boundary.value,
            "contextTokens": self.context_tokens,
            "benchmarkScore": self.benchmark_score,
            "latencyMsP50": self.latency_ms_p50,
            "costPerMillionTokens": self.cost_per_million_tokens,
            "toolSchemaScore": self.tool_schema_score,
            "approved": self.approved,
            "requiresExplicitFallbackApproval": self.requires_explicit_fallback_approval,
            "enabled": self.enabled,
        }


@dataclasses.dataclass(frozen=True)
class RoutingRequest:
    role: ModelRole
    required_context_tokens: int
    maximum_data_boundary: DataBoundary
    allowed_providers: frozenset[str]
    preferred_models: tuple[str, ...] = ()
    local_only: bool = True
    maximum_cost_per_million_tokens: float | None = None
    require_tool_schema_reliability: bool = False
    fallback_approval_granted: bool = False

    @classmethod
    def from_json(cls, raw: Mapping[str, Any]) -> "RoutingRequest":
        data = _as_dict(dict(raw), "request")
        allowed = {
            "role", "requiredContextTokens", "maximumDataBoundary", "allowedProviders",
            "preferredModels", "localOnly", "maximumCostPerMillionTokens",
            "requireToolSchemaReliability", "fallbackApprovalGranted",
        }
        unknown = sorted(set(data) - allowed)
        if unknown:
            raise IntelligenceInputError(f"request has unknown fields: {unknown}")
        try:
            role = ModelRole(_string(data.get("role"), "request.role"))
            boundary = DataBoundary(_string(data.get("maximumDataBoundary", "local"), "request.maximumDataBoundary"))
        except ValueError as exc:
            raise IntelligenceInputError("request role or maximumDataBoundary is invalid") from exc
        preferred_raw = data.get("preferredModels", [])
        preferred = tuple(_string(item, f"request.preferredModels[{index}]") for index, item in enumerate(_as_list(preferred_raw, "request.preferredModels")))
        maximum_cost = data.get("maximumCostPerMillionTokens")
        return cls(
            role=role,
            required_context_tokens=_integer(data.get("requiredContextTokens", 0), "request.requiredContextTokens"),
            maximum_data_boundary=boundary,
            allowed_providers=_string_set(data.get("allowedProviders", []), "request.allowedProviders"),
            preferred_models=preferred,
            local_only=bool(data.get("localOnly", True)),
            maximum_cost_per_million_tokens=None if maximum_cost is None else _number(maximum_cost, "request.maximumCostPerMillionTokens"),
            require_tool_schema_reliability=bool(data.get("requireToolSchemaReliability", False)),
            fallback_approval_granted=bool(data.get("fallbackApprovalGranted", False)),
        )


@dataclasses.dataclass(frozen=True)
class RouteDecision:
    selected: ModelCandidate | None
    eligible: tuple[dict[str, Any], ...]
    rejected: tuple[dict[str, Any], ...]
    approval_required: bool
    reason: str
    decision_hash: str

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "selected": self.selected.to_json() if self.selected is not None else None,
            "eligible": list(self.eligible),
            "rejected": list(self.rejected),
            "approvalRequired": self.approval_required,
            "reason": self.reason,
            "decisionHash": self.decision_hash,
        }


class ModelRouter:
    """Deterministic, policy-clamped model selection."""

    def __init__(self, *, circuit_breaker: CircuitBreaker | None = None) -> None:
        self.circuit_breaker = circuit_breaker or CircuitBreaker()

    def route(
        self,
        request: RoutingRequest,
        candidates: Sequence[ModelCandidate],
        health_by_identity: Mapping[str, ProviderHealth] | None = None,
    ) -> RouteDecision:
        health_by_identity = health_by_identity or {}
        eligible: list[tuple[float, ModelCandidate, dict[str, Any]]] = []
        rejected: list[dict[str, Any]] = []
        preferred_rank = {identity: index for index, identity in enumerate(request.preferred_models)}

        for candidate in candidates:
            reasons: list[str] = []
            health = health_by_identity.get(
                candidate.identity,
                ProviderHealth(candidate.provider, candidate.model),
            )
            effective_circuit = self.circuit_breaker.effective_state(health)
            if not candidate.enabled:
                reasons.append("disabled")
            if not candidate.approved:
                reasons.append("not_user_approved")
            if request.role not in candidate.roles:
                reasons.append("role_unsupported")
            if request.allowed_providers and candidate.provider not in request.allowed_providers:
                reasons.append("provider_not_allowed")
            if request.local_only and candidate.data_boundary != DataBoundary.LOCAL:
                reasons.append("local_only_policy")
            if candidate.data_boundary.rank > request.maximum_data_boundary.rank:
                reasons.append("data_boundary_exceeds_policy")
            if candidate.context_tokens < request.required_context_tokens:
                reasons.append("context_too_small")
            if (
                request.maximum_cost_per_million_tokens is not None
                and candidate.cost_per_million_tokens > request.maximum_cost_per_million_tokens
            ):
                reasons.append("cost_exceeds_policy")
            if request.require_tool_schema_reliability and candidate.tool_schema_score < 0.75:
                reasons.append("tool_schema_reliability_below_threshold")
            if effective_circuit == CircuitState.OPEN:
                reasons.append("provider_circuit_open")
            if candidate.requires_explicit_fallback_approval and not request.fallback_approval_granted:
                reasons.append("fallback_approval_required")

            if reasons:
                rejected.append(
                    {
                        "identity": candidate.identity,
                        "reasons": sorted(reasons),
                        "circuitState": effective_circuit.value,
                    }
                )
                continue

            preference_bonus = 0.0
            if candidate.identity in preferred_rank:
                preference_bonus = max(0.0, 20.0 - preferred_rank[candidate.identity])
            local_bonus = 8.0 if candidate.data_boundary == DataBoundary.LOCAL else 0.0
            reliability = candidate.tool_schema_score * (45.0 if request.role == ModelRole.EXECUTOR else 20.0)
            benchmark = candidate.benchmark_score * 100.0
            latency_penalty = min(25.0, candidate.latency_ms_p50 / 1000.0)
            cost_penalty = min(25.0, candidate.cost_per_million_tokens / 2.0)
            failure_penalty = min(30.0, health.consecutive_failures * 8.0)
            half_open_penalty = 15.0 if effective_circuit == CircuitState.HALF_OPEN else 0.0
            score = benchmark + reliability + preference_bonus + local_bonus - latency_penalty - cost_penalty - failure_penalty - half_open_penalty
            eligible.append(
                (
                    score,
                    candidate,
                    {
                        "identity": candidate.identity,
                        "score": round(score, 6),
                        "circuitState": effective_circuit.value,
                        "dataBoundary": candidate.data_boundary.value,
                    },
                )
            )

        eligible.sort(key=lambda item: (-item[0], item[1].identity))
        rejected.sort(key=lambda item: item["identity"])
        selected = eligible[0][1] if eligible else None
        eligible_rows = tuple(item[2] for item in eligible)
        approval_required = any("fallback_approval_required" in row["reasons"] for row in rejected)
        if selected is None:
            reason = "No model satisfies the role, privacy, health, context, approval, and cost policy."
        else:
            reason = f"Selected {selected.identity} for role {request.role.value} using deterministic policy scoring."
        digest_payload = {
            "request": dataclasses.asdict(request) | {
                "role": request.role.value,
                "maximum_data_boundary": request.maximum_data_boundary.value,
                "allowed_providers": sorted(request.allowed_providers),
            },
            "selected": selected.identity if selected else None,
            "eligible": eligible_rows,
            "rejected": rejected,
        }
        return RouteDecision(
            selected=selected,
            eligible=eligible_rows,
            rejected=tuple(rejected),
            approval_required=approval_required,
            reason=reason,
            decision_hash=sha256_json(digest_payload),
        )


@dataclasses.dataclass(frozen=True)
class ProgressSnapshot:
    artifacts: Mapping[str, str]
    evidence: frozenset[str]
    active_errors: frozenset[str]
    satisfied_criteria: frozenset[str]
    external_state: frozenset[str]
    plan_revision_hash: str = ""
    action_fingerprint: str = ""
    result_fingerprint: str = ""

    @classmethod
    def from_json(cls, raw: Mapping[str, Any]) -> "ProgressSnapshot":
        data = _as_dict(dict(raw), "progressSnapshot")
        allowed = {
            "artifacts", "evidence", "activeErrors", "satisfiedCriteria",
            "externalState", "planRevisionHash", "actionFingerprint",
            "resultFingerprint",
        }
        unknown = sorted(set(data) - allowed)
        if unknown:
            raise IntelligenceInputError(f"progressSnapshot has unknown fields: {unknown}")
        artifacts_raw = _as_dict(data.get("artifacts", {}), "progressSnapshot.artifacts")
        artifacts: dict[str, str] = {}
        for path, digest in artifacts_raw.items():
            path_value = _string(path, "artifact path")
            digest_value = _string(digest, f"artifact digest for {path_value}")
            if not re.fullmatch(r"[a-f0-9]{64}", digest_value):
                raise IntelligenceInputError(f"artifact digest for {path_value} must be lowercase SHA-256")
            artifacts[path_value.replace("\\", "/")] = digest_value
        return cls(
            artifacts=dict(sorted(artifacts.items())),
            evidence=_string_set(data.get("evidence", []), "progressSnapshot.evidence"),
            active_errors=_string_set(data.get("activeErrors", []), "progressSnapshot.activeErrors"),
            satisfied_criteria=_string_set(data.get("satisfiedCriteria", []), "progressSnapshot.satisfiedCriteria"),
            external_state=_string_set(data.get("externalState", []), "progressSnapshot.externalState"),
            plan_revision_hash=_string(data.get("planRevisionHash", ""), "progressSnapshot.planRevisionHash", allow_empty=True),
            action_fingerprint=_string(data.get("actionFingerprint", ""), "progressSnapshot.actionFingerprint", allow_empty=True),
            result_fingerprint=_string(data.get("resultFingerprint", ""), "progressSnapshot.resultFingerprint", allow_empty=True),
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "artifacts": dict(sorted(self.artifacts.items())),
            "evidence": sorted(self.evidence),
            "activeErrors": sorted(self.active_errors),
            "satisfiedCriteria": sorted(self.satisfied_criteria),
            "externalState": sorted(self.external_state),
            "planRevisionHash": self.plan_revision_hash,
            "actionFingerprint": self.action_fingerprint,
            "resultFingerprint": self.result_fingerprint,
        }


@dataclasses.dataclass(frozen=True)
class ProgressDelta:
    new_artifacts: tuple[str, ...]
    changed_artifact_hashes: tuple[dict[str, str], ...]
    removed_artifacts: tuple[str, ...]
    new_evidence: tuple[str, ...]
    resolved_errors: tuple[str, ...]
    new_errors: tuple[str, ...]
    criteria_satisfied: tuple[str, ...]
    criteria_regressed: tuple[str, ...]
    new_external_state: tuple[str, ...]
    plan_revised: bool
    repeated_action: bool
    repeated_result: bool
    semantic_progress: bool
    reasons: tuple[str, ...]
    delta_hash: str

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "newArtifacts": list(self.new_artifacts),
            "changedArtifactHashes": list(self.changed_artifact_hashes),
            "removedArtifacts": list(self.removed_artifacts),
            "newEvidence": list(self.new_evidence),
            "resolvedErrors": list(self.resolved_errors),
            "newErrors": list(self.new_errors),
            "criteriaSatisfied": list(self.criteria_satisfied),
            "criteriaRegressed": list(self.criteria_regressed),
            "newExternalState": list(self.new_external_state),
            "planRevised": self.plan_revised,
            "repeatedAction": self.repeated_action,
            "repeatedResult": self.repeated_result,
            "semanticProgress": self.semantic_progress,
            "reasons": list(self.reasons),
            "deltaHash": self.delta_hash,
        }


class SemanticProgressEngine:
    """Compare two durable fact snapshots; model prose is intentionally absent."""

    def compare(self, before: ProgressSnapshot, after: ProgressSnapshot) -> ProgressDelta:
        before_paths = set(before.artifacts)
        after_paths = set(after.artifacts)
        new_artifacts = tuple(sorted(after_paths - before_paths))
        removed_artifacts = tuple(sorted(before_paths - after_paths))
        changed = tuple(
            {
                "path": path,
                "beforeSha256": before.artifacts[path],
                "afterSha256": after.artifacts[path],
            }
            for path in sorted(before_paths & after_paths)
            if before.artifacts[path] != after.artifacts[path]
        )
        new_evidence = tuple(sorted(after.evidence - before.evidence))
        resolved_errors = tuple(sorted(before.active_errors - after.active_errors))
        new_errors = tuple(sorted(after.active_errors - before.active_errors))
        criteria_satisfied = tuple(sorted(after.satisfied_criteria - before.satisfied_criteria))
        criteria_regressed = tuple(sorted(before.satisfied_criteria - after.satisfied_criteria))
        new_external_state = tuple(sorted(after.external_state - before.external_state))
        plan_revised = bool(after.plan_revision_hash and after.plan_revision_hash != before.plan_revision_hash)
        repeated_action = bool(before.action_fingerprint and before.action_fingerprint == after.action_fingerprint)
        repeated_result = bool(before.result_fingerprint and before.result_fingerprint == after.result_fingerprint)

        positive = bool(
            new_artifacts
            or changed
            or new_evidence
            or resolved_errors
            or criteria_satisfied
            or new_external_state
            or plan_revised
        )
        reasons: list[str] = []
        if new_artifacts:
            reasons.append("required_or_observed_artifact_created")
        if changed:
            reasons.append("artifact_hash_changed")
        if new_evidence:
            reasons.append("new_independent_evidence")
        if resolved_errors:
            reasons.append("error_resolved")
        if criteria_satisfied:
            reasons.append("acceptance_criterion_verified")
        if new_external_state:
            reasons.append("external_state_changed")
        if plan_revised:
            reasons.append("plan_validly_revised")
        if not positive:
            reasons.append("no_durable_fact_changed")
        if repeated_action:
            reasons.append("action_repeated")
        if repeated_result:
            reasons.append("result_repeated")
        if removed_artifacts or criteria_regressed or new_errors:
            reasons.append("state_regressed")

        payload = {
            "newArtifacts": new_artifacts,
            "changedArtifactHashes": changed,
            "removedArtifacts": removed_artifacts,
            "newEvidence": new_evidence,
            "resolvedErrors": resolved_errors,
            "newErrors": new_errors,
            "criteriaSatisfied": criteria_satisfied,
            "criteriaRegressed": criteria_regressed,
            "newExternalState": new_external_state,
            "planRevised": plan_revised,
            "repeatedAction": repeated_action,
            "repeatedResult": repeated_result,
            "semanticProgress": positive,
            "reasons": reasons,
        }
        return ProgressDelta(
            new_artifacts=new_artifacts,
            changed_artifact_hashes=changed,
            removed_artifacts=removed_artifacts,
            new_evidence=new_evidence,
            resolved_errors=resolved_errors,
            new_errors=new_errors,
            criteria_satisfied=criteria_satisfied,
            criteria_regressed=criteria_regressed,
            new_external_state=new_external_state,
            plan_revised=plan_revised,
            repeated_action=repeated_action,
            repeated_result=repeated_result,
            semantic_progress=positive,
            reasons=tuple(reasons),
            delta_hash=sha256_json(payload),
        )


@dataclasses.dataclass(frozen=True)
class ConvergenceDecision:
    action: StrategyAction
    stage: int
    reason: str
    requires_user_approval: bool
    permission_widening_allowed: bool
    directives: tuple[str, ...]
    decision_hash: str

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "action": self.action.value,
            "stage": self.stage,
            "reason": self.reason,
            "requiresUserApproval": self.requires_user_approval,
            "permissionWideningAllowed": self.permission_widening_allowed,
            "directives": list(self.directives),
            "decisionHash": self.decision_hash,
        }


class ConvergenceController:
    """Bounded strategy escalation based on semantic, not call-count, progress."""

    def decide(
        self,
        *,
        delta: ProgressDelta,
        consecutive_no_progress: int,
        repeated_action_count: int,
        repairs_remaining: int,
        verifier_available: bool,
        task_can_split: bool,
        ask_user_allowed: bool,
        stronger_model_available: bool,
        stronger_model_approved: bool,
    ) -> ConvergenceDecision:
        no_progress = max(0, int(consecutive_no_progress))
        repeats = max(0, int(repeated_action_count))
        repairs = max(0, int(repairs_remaining))

        if delta.semantic_progress:
            action = StrategyAction.CONTINUE
            stage = 0
            reason = "A durable fact changed; continue under the existing permissions and phase budget."
            directives = ("preserve_new_evidence", "continue_current_strategy")
            approval = False
        elif no_progress <= 1 and repeats <= 1 and repairs > 0:
            action = StrategyAction.COMPACT_AND_RETRY
            stage = 1
            reason = "No durable progress was observed once; compact duplicate context and request a materially different action."
            directives = (
                "remove_duplicate_history",
                "state_unresolved_criteria",
                "forbid_identical_action_fingerprint",
            )
            approval = False
        elif no_progress <= 2 and repairs > 0:
            action = StrategyAction.REQUIRE_DIFFERENT_ACTION
            stage = 2
            reason = "The same strategy failed to change state; require a different authorized action class."
            directives = (
                "summarize_current_state_deterministically",
                "exclude_prior_failed_action",
                "do_not_widen_permissions",
            )
            approval = False
        elif verifier_available and no_progress <= 3:
            action = StrategyAction.ROUTE_TO_VERIFIER
            stage = 3
            reason = "Execution is stalled; use an independent verifier to identify the exact unsupported criterion or stale assumption."
            directives = (
                "send_artifacts_and_evidence_only",
                "exclude_executor_narrative",
                "return_criterion_level_findings",
            )
            approval = False
        elif task_can_split and no_progress <= 4:
            action = StrategyAction.SPLIT_TASK
            stage = 4
            reason = "The bounded work item is too broad for the observed state; split it into independently verifiable sub-items."
            directives = (
                "preserve_existing_capabilities",
                "create_independent_acceptance_criteria",
                "retain_parent_budget_ceiling",
            )
            approval = False
        elif ask_user_allowed and no_progress <= 5:
            action = StrategyAction.ASK_USER
            stage = 5
            reason = "Deterministic recovery cannot resolve the remaining ambiguity safely; request one precise user decision."
            directives = (
                "ask_one_material_question",
                "include_safe_default_and_consequences",
                "do_not_execute_while_waiting",
            )
            approval = True
        elif stronger_model_available and not stronger_model_approved:
            action = StrategyAction.OFFER_STRONGER_MODEL
            stage = 6
            reason = "A stronger model is available, but privacy, provider, and cost policy require explicit approval before fallback."
            directives = (
                "show_provider_and_data_boundary",
                "show_cost_and_reason",
                "retain_current_permissions",
            )
            approval = True
        elif stronger_model_available and stronger_model_approved and repairs > 0:
            action = StrategyAction.REQUIRE_DIFFERENT_ACTION
            stage = 6
            reason = "Approved stronger-model fallback may be used once with compacted evidence and the same capability envelope."
            directives = (
                "route_to_approved_stronger_model",
                "reuse_compacted_evidence",
                "forbid_permission_expansion",
            )
            approval = False
        else:
            action = StrategyAction.FAIL_CONVERGENCE
            stage = 7
            reason = "Bounded strategies are exhausted or no safe repair capacity remains; stop with a precise convergence failure."
            directives = (
                "persist_final_progress_ledger",
                "identify_last_material_change",
                "report_safe_retry_preconditions",
            )
            approval = False

        payload = {
            "action": action.value,
            "stage": stage,
            "reason": reason,
            "approval": approval,
            "directives": directives,
            "deltaHash": delta.delta_hash,
            "noProgress": no_progress,
            "repeats": repeats,
            "repairs": repairs,
        }
        return ConvergenceDecision(
            action=action,
            stage=stage,
            reason=reason,
            requires_user_approval=approval,
            permission_widening_allowed=False,
            directives=directives,
            decision_hash=sha256_json(payload),
        )


@dataclasses.dataclass(frozen=True)
class PhaseBudget:
    phase: str
    max_model_requests: int
    max_tool_calls: int
    max_repairs: int
    max_output_tokens: int
    max_context_characters: int
    deadline_seconds: int

    @classmethod
    def defaults(cls, phase: str) -> "PhaseBudget":
        phase = phase.strip().lower()
        values = {
            "routing": (1, 0, 0, 256, 8_000, 30),
            "planning": (3, 2, 2, 4096, 48_000, 300),
            "execution": (8, 16, 4, 2048, 36_000, 900),
            "verification": (3, 8, 2, 2048, 32_000, 600),
            "summarization": (1, 0, 0, 1024, 48_000, 90),
            "research": (4, 8, 2, 3072, 40_000, 600),
            "safety_review": (2, 0, 1, 1536, 24_000, 180),
        }
        if phase not in values:
            raise IntelligenceInputError(f"unknown phase: {phase}")
        model, tools, repairs, output, context, deadline = values[phase]
        return cls(phase, model, tools, repairs, output, context, deadline)

    def to_json(self) -> dict[str, Any]:
        return {
            "phase": self.phase,
            "maxModelRequests": self.max_model_requests,
            "maxToolCalls": self.max_tool_calls,
            "maxRepairs": self.max_repairs,
            "maxOutputTokens": self.max_output_tokens,
            "maxContextCharacters": self.max_context_characters,
            "deadlineSeconds": self.deadline_seconds,
        }


@dataclasses.dataclass(frozen=True)
class CriterionFinding:
    criterion_id: str
    status: VerificationStatus
    evidence_ids: tuple[str, ...]
    reason: str

    def to_json(self) -> dict[str, Any]:
        return {
            "criterionId": self.criterion_id,
            "status": self.status.value,
            "evidenceIds": list(self.evidence_ids),
            "reason": self.reason,
        }


@dataclasses.dataclass(frozen=True)
class VerificationReport:
    passed: bool
    findings: tuple[CriterionFinding, ...]
    unsupported_completion_claims: tuple[str, ...]
    evidence_hash: str
    report_hash: str

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "passed": self.passed,
            "findings": [finding.to_json() for finding in self.findings],
            "unsupportedCompletionClaims": list(self.unsupported_completion_claims),
            "evidenceHash": self.evidence_hash,
            "reportHash": self.report_hash,
        }


class IndependentVerifier:
    """Verify acceptance criteria from objective evidence, never executor prose."""

    OBJECTIVE_KINDS = frozenset(
        {
            "artifact",
            "artifact_validation",
            "test",
            "verification",
            "command",
            "mutation",
            "research",
            "external_operation",
            "preexisting_valid",
        }
    )

    def verify(self, document: Mapping[str, Any]) -> VerificationReport:
        data = _as_dict(dict(document), "verificationDocument")
        allowed = {"criteria", "evidence", "completionClaims"}
        unknown = sorted(set(data) - allowed)
        if unknown:
            raise IntelligenceInputError(f"verificationDocument has unknown fields: {unknown}")

        evidence_raw = _as_list(data.get("evidence", []), "verificationDocument.evidence")
        evidence: dict[str, dict[str, Any]] = {}
        for index, raw in enumerate(evidence_raw):
            item = _as_dict(raw, f"evidence[{index}]")
            allowed_evidence = {
                "id", "kind", "ok", "criterionIds", "sha256", "validator",
                "independent", "stale", "summary", "sourceTaskId",
            }
            unknown_evidence = sorted(set(item) - allowed_evidence)
            if unknown_evidence:
                raise IntelligenceInputError(f"evidence[{index}] has unknown fields: {unknown_evidence}")
            evidence_id = _string(item.get("id"), f"evidence[{index}].id")
            if evidence_id in evidence:
                raise IntelligenceInputError(f"duplicate evidence id: {evidence_id}")
            kind = _string(item.get("kind"), f"evidence[{index}].kind")
            criterion_ids = _string_set(item.get("criterionIds", []), f"evidence[{index}].criterionIds")
            digest = _string(item.get("sha256", ""), f"evidence[{index}].sha256", allow_empty=True)
            if digest and not re.fullmatch(r"[a-f0-9]{64}", digest):
                raise IntelligenceInputError(f"evidence[{index}].sha256 must be lowercase SHA-256")
            evidence[evidence_id] = {
                "id": evidence_id,
                "kind": kind,
                "ok": bool(item.get("ok", False)),
                "criterionIds": criterion_ids,
                "sha256": digest,
                "validator": str(item.get("validator", "")).strip(),
                "independent": bool(item.get("independent", False)),
                "stale": bool(item.get("stale", False)),
                "summary": str(item.get("summary", "")).strip(),
                "sourceTaskId": str(item.get("sourceTaskId", "")).strip(),
            }

        criteria_raw = _as_list(data.get("criteria", []), "verificationDocument.criteria")
        findings: list[CriterionFinding] = []
        criterion_ids: set[str] = set()
        for index, raw in enumerate(criteria_raw):
            criterion = _as_dict(raw, f"criteria[{index}]")
            allowed_criterion = {"id", "statement", "requiredEvidenceKinds", "manual", "blockedReason"}
            unknown_criterion = sorted(set(criterion) - allowed_criterion)
            if unknown_criterion:
                raise IntelligenceInputError(f"criteria[{index}] has unknown fields: {unknown_criterion}")
            criterion_id = _string(criterion.get("id"), f"criteria[{index}].id")
            if criterion_id in criterion_ids:
                raise IntelligenceInputError(f"duplicate criterion id: {criterion_id}")
            criterion_ids.add(criterion_id)
            _string(criterion.get("statement"), f"criteria[{index}].statement")
            manual = bool(criterion.get("manual", False))
            blocked_reason = str(criterion.get("blockedReason", "")).strip()
            required_kinds = _string_set(criterion.get("requiredEvidenceKinds", []), f"criteria[{index}].requiredEvidenceKinds")
            related = [item for item in evidence.values() if criterion_id in item["criterionIds"]]
            valid = [
                item
                for item in related
                if item["kind"] in self.OBJECTIVE_KINDS
                and item["ok"]
                and not item["stale"]
                and (item["sha256"] or item["validator"])
            ]
            represented = {item["kind"] for item in valid}
            missing_kinds = sorted(required_kinds - represented)
            if blocked_reason:
                status = VerificationStatus.BLOCKED
                reason = blocked_reason
            elif manual and not valid:
                status = VerificationStatus.BLOCKED
                reason = "Manual criterion awaits explicit human evidence."
            elif any(not item["ok"] and not item["stale"] for item in related):
                status = VerificationStatus.FAILED
                reason = "At least one current objective validator failed."
            elif not valid or missing_kinds:
                status = VerificationStatus.UNSUPPORTED
                reason = (
                    f"Missing required evidence kinds: {', '.join(missing_kinds)}."
                    if missing_kinds
                    else "No current objective evidence supports this criterion."
                )
            else:
                status = VerificationStatus.SUPPORTED
                reason = "Current objective evidence satisfies the criterion."
            findings.append(
                CriterionFinding(
                    criterion_id=criterion_id,
                    status=status,
                    evidence_ids=tuple(sorted(item["id"] for item in valid)),
                    reason=reason,
                )
            )

        claims = [str(item).strip() for item in _as_list(data.get("completionClaims", []), "verificationDocument.completionClaims") if str(item).strip()]
        supported_ids = {finding.criterion_id for finding in findings if finding.status == VerificationStatus.SUPPORTED}
        unsupported_claims: list[str] = []
        for claim in claims:
            # A claim may reference a criterion ID exactly.  Free-form executor
            # prose is deliberately never treated as evidence.
            if claim not in supported_ids:
                unsupported_claims.append(claim)

        passed = bool(findings) and all(finding.status == VerificationStatus.SUPPORTED for finding in findings) and not unsupported_claims
        evidence_payload = [
            {
                **item,
                "criterionIds": sorted(item["criterionIds"]),
            }
            for item in sorted(evidence.values(), key=lambda value: value["id"])
        ]
        evidence_hash = sha256_json(evidence_payload)
        report_payload = {
            "passed": passed,
            "findings": [finding.to_json() for finding in findings],
            "unsupportedCompletionClaims": unsupported_claims,
            "evidenceHash": evidence_hash,
        }
        return VerificationReport(
            passed=passed,
            findings=tuple(findings),
            unsupported_completion_claims=tuple(unsupported_claims),
            evidence_hash=evidence_hash,
            report_hash=sha256_json(report_payload),
        )


class ContextCompactor:
    """Bound history by relevance while preserving deterministic evidence facts."""

    HIGH_VALUE_KINDS = frozenset(
        {
            "error",
            "criterion",
            "artifact",
            "artifact_validation",
            "verification",
            "mutation",
            "approval",
            "strategy",
            "user",
        }
    )

    @staticmethod
    def _normalized_entry(entry: Mapping[str, Any]) -> dict[str, Any]:
        allowed = {
            "id", "kind", "summary", "tool", "argumentsHash", "resultHash",
            "path", "sha256", "errorCode", "criterionId", "timestamp", "turn",
            "status", "source",
        }
        result = {key: entry[key] for key in sorted(entry) if key in allowed}
        if "summary" in result:
            summary = re.sub(r"\s+", " ", str(result["summary"])).strip()
            result["summary"] = summary[:2000]
        return result

    def compact(
        self,
        entries: Sequence[Mapping[str, Any]],
        *,
        maximum_characters: int = 24000,
        recent_count: int = 8,
    ) -> dict[str, Any]:
        maximum_characters = max(2000, int(maximum_characters))
        recent_count = max(1, int(recent_count))
        normalized = [self._normalized_entry(_as_dict(dict(entry), f"history[{index}]")) for index, entry in enumerate(entries)]
        deduplicated: list[dict[str, Any]] = []
        seen: set[str] = set()
        duplicate_count = 0
        for entry in normalized:
            fingerprint_source = {key: value for key, value in entry.items() if key not in {"id", "timestamp", "turn"}}
            fingerprint = sha256_json(fingerprint_source)
            if fingerprint in seen:
                duplicate_count += 1
                continue
            seen.add(fingerprint)
            entry = dict(entry)
            entry["fingerprint"] = fingerprint
            deduplicated.append(entry)

        selected: list[dict[str, Any]] = []
        selected_ids: set[int] = set()
        for index, entry in enumerate(deduplicated):
            if str(entry.get("kind", "")) in self.HIGH_VALUE_KINDS:
                selected.append(entry)
                selected_ids.add(index)
        start_recent = max(0, len(deduplicated) - recent_count)
        for index in range(start_recent, len(deduplicated)):
            if index not in selected_ids:
                selected.append(deduplicated[index])
                selected_ids.add(index)
        selected.sort(key=lambda entry: (str(entry.get("timestamp", "")), int(entry.get("turn", 0) or 0), str(entry.get("id", ""))))

        while selected and len(canonical_json(selected)) > maximum_characters:
            removable = next(
                (
                    index
                    for index, entry in enumerate(selected)
                    if str(entry.get("kind", "")) not in self.HIGH_VALUE_KINDS
                ),
                None,
            )
            if removable is None:
                # Keep high-value facts but bound long summaries.
                longest = max(range(len(selected)), key=lambda index: len(str(selected[index].get("summary", ""))))
                summary = str(selected[longest].get("summary", ""))
                if len(summary) <= 160:
                    selected.pop(0)
                else:
                    selected[longest] = dict(selected[longest])
                    selected[longest]["summary"] = summary[: max(160, len(summary) // 2)] + "…"
            else:
                selected.pop(removable)

        payload = {
            "schemaVersion": SCHEMA_VERSION,
            "entries": selected,
            "inputCount": len(entries),
            "deduplicatedCount": len(deduplicated),
            "outputCount": len(selected),
            "duplicatesRemoved": duplicate_count,
            "characters": len(canonical_json(selected)),
        }
        payload["contextHash"] = sha256_json(payload)
        return payload


def route_document(document: Mapping[str, Any]) -> dict[str, Any]:
    data = _as_dict(dict(document), "routingDocument")
    allowed = {"request", "candidates", "health", "circuitPolicy"}
    unknown = sorted(set(data) - allowed)
    if unknown:
        raise IntelligenceInputError(f"routingDocument has unknown fields: {unknown}")
    request = RoutingRequest.from_json(_as_dict(data.get("request"), "routingDocument.request"))
    candidates = [ModelCandidate.from_json(_as_dict(item, f"candidates[{index}]")) for index, item in enumerate(_as_list(data.get("candidates", []), "routingDocument.candidates"))]
    health_items = [ProviderHealth.from_json(_as_dict(item, f"health[{index}]")) for index, item in enumerate(_as_list(data.get("health", []), "routingDocument.health"))]
    health = {item.key: item for item in health_items}
    circuit_policy = _as_dict(data.get("circuitPolicy", {}), "routingDocument.circuitPolicy")
    breaker = CircuitBreaker(
        failure_threshold=_integer(circuit_policy.get("failureThreshold", 3), "circuitPolicy.failureThreshold", minimum=1, maximum=20),
        cooldown_seconds=_integer(circuit_policy.get("cooldownSeconds", 120), "circuitPolicy.cooldownSeconds", minimum=1, maximum=86400),
    )
    return ModelRouter(circuit_breaker=breaker).route(request, candidates, health).to_json()


def progress_document(document: Mapping[str, Any]) -> dict[str, Any]:
    data = _as_dict(dict(document), "progressDocument")
    if set(data) != {"before", "after"}:
        raise IntelligenceInputError("progressDocument must contain exactly before and after")
    before = ProgressSnapshot.from_json(_as_dict(data["before"], "progressDocument.before"))
    after = ProgressSnapshot.from_json(_as_dict(data["after"], "progressDocument.after"))
    return SemanticProgressEngine().compare(before, after).to_json()


def converge_document(document: Mapping[str, Any]) -> dict[str, Any]:
    data = _as_dict(dict(document), "convergenceDocument")
    allowed = {
        "delta", "consecutiveNoProgress", "repeatedActionCount", "repairsRemaining",
        "verifierAvailable", "taskCanSplit", "askUserAllowed",
        "strongerModelAvailable", "strongerModelApproved",
    }
    unknown = sorted(set(data) - allowed)
    if unknown:
        raise IntelligenceInputError(f"convergenceDocument has unknown fields: {unknown}")
    delta_raw = _as_dict(data.get("delta"), "convergenceDocument.delta")
    # Reconstruct only the fields the controller needs while retaining a stable
    # hash over the supplied deterministic delta.
    delta = ProgressDelta(
        new_artifacts=tuple(str(item) for item in delta_raw.get("newArtifacts", [])),
        changed_artifact_hashes=tuple(dict(item) for item in delta_raw.get("changedArtifactHashes", [])),
        removed_artifacts=tuple(str(item) for item in delta_raw.get("removedArtifacts", [])),
        new_evidence=tuple(str(item) for item in delta_raw.get("newEvidence", [])),
        resolved_errors=tuple(str(item) for item in delta_raw.get("resolvedErrors", [])),
        new_errors=tuple(str(item) for item in delta_raw.get("newErrors", [])),
        criteria_satisfied=tuple(str(item) for item in delta_raw.get("criteriaSatisfied", [])),
        criteria_regressed=tuple(str(item) for item in delta_raw.get("criteriaRegressed", [])),
        new_external_state=tuple(str(item) for item in delta_raw.get("newExternalState", [])),
        plan_revised=bool(delta_raw.get("planRevised", False)),
        repeated_action=bool(delta_raw.get("repeatedAction", False)),
        repeated_result=bool(delta_raw.get("repeatedResult", False)),
        semantic_progress=bool(delta_raw.get("semanticProgress", False)),
        reasons=tuple(str(item) for item in delta_raw.get("reasons", [])),
        delta_hash=str(delta_raw.get("deltaHash") or sha256_json(delta_raw)),
    )
    return ConvergenceController().decide(
        delta=delta,
        consecutive_no_progress=_integer(data.get("consecutiveNoProgress", 0), "consecutiveNoProgress"),
        repeated_action_count=_integer(data.get("repeatedActionCount", 0), "repeatedActionCount"),
        repairs_remaining=_integer(data.get("repairsRemaining", 0), "repairsRemaining"),
        verifier_available=bool(data.get("verifierAvailable", True)),
        task_can_split=bool(data.get("taskCanSplit", True)),
        ask_user_allowed=bool(data.get("askUserAllowed", True)),
        stronger_model_available=bool(data.get("strongerModelAvailable", False)),
        stronger_model_approved=bool(data.get("strongerModelApproved", False)),
    ).to_json()


def _load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise IntelligenceInputError(f"could not read {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise IntelligenceInputError(f"invalid JSON in {path}: {exc}") from exc
    return _as_dict(value, str(path))


def _write_json(value: Mapping[str, Any], output: Path | None) -> None:
    text = json.dumps(value, indent=2, sort_keys=True) + "\n"
    if output is None:
        sys.stdout.write(text)
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8", newline="\n")
        print(output)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Kristin v1.7 deterministic execution intelligence")
    parser.add_argument("--version", action="version", version=VERSION)
    sub = parser.add_subparsers(dest="command", required=True)
    for name, help_text in (
        ("route", "select an approved role-specific model"),
        ("progress", "compare two durable fact snapshots"),
        ("converge", "select the next bounded convergence strategy"),
        ("verify", "verify criteria from objective evidence"),
        ("compact", "compact and deduplicate model-visible history"),
    ):
        command = sub.add_parser(name, help=help_text)
        command.add_argument("--input", type=Path, required=True)
        command.add_argument("--output", type=Path)
    budget = sub.add_parser("budget", help="show the default budget for one execution phase")
    budget.add_argument("phase", choices=("routing", "planning", "execution", "verification", "summarization", "research", "safety_review"))
    budget.add_argument("--output", type=Path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "route":
            result = route_document(_load_json(args.input.expanduser().resolve()))
        elif args.command == "progress":
            result = progress_document(_load_json(args.input.expanduser().resolve()))
        elif args.command == "converge":
            result = converge_document(_load_json(args.input.expanduser().resolve()))
        elif args.command == "verify":
            result = IndependentVerifier().verify(_load_json(args.input.expanduser().resolve())).to_json()
        elif args.command == "compact":
            document = _load_json(args.input.expanduser().resolve())
            allowed = {"entries", "maximumCharacters", "recentCount"}
            unknown = sorted(set(document) - allowed)
            if unknown:
                raise IntelligenceInputError(f"compact document has unknown fields: {unknown}")
            entries = [_as_dict(item, f"entries[{index}]") for index, item in enumerate(_as_list(document.get("entries", []), "entries"))]
            result = ContextCompactor().compact(
                entries,
                maximum_characters=_integer(document.get("maximumCharacters", 24000), "maximumCharacters", minimum=2000, maximum=200000),
                recent_count=_integer(document.get("recentCount", 8), "recentCount", minimum=1, maximum=200),
            )
        elif args.command == "budget":
            result = {"schemaVersion": SCHEMA_VERSION, "version": VERSION, "budget": PhaseBudget.defaults(args.phase).to_json()}
        else:  # pragma: no cover - argparse guarantees the branch set
            raise IntelligenceInputError(f"unsupported command: {args.command}")
        _write_json(result, args.output.expanduser().resolve() if args.output else None)
        return 0
    except IntelligenceInputError as exc:
        print(f"execution-intelligence input error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
