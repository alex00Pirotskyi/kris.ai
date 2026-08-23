#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from enum import Enum
import hashlib
import json
from typing import Any, Iterable, Mapping, Sequence


class Provenance(str, Enum):
    SYSTEM = "system"
    USER = "user"
    PROJECT = "project"
    WEB = "web"
    MEMORY = "memory"
    TERMINAL = "terminal"
    MCP = "mcp"
    A2A = "a2a"
    TOOL = "tool"

    @property
    def untrusted(self) -> bool:
        return self in {
            Provenance.WEB,
            Provenance.MEMORY,
            Provenance.TERMINAL,
            Provenance.MCP,
            Provenance.A2A,
            Provenance.TOOL,
        }


@dataclass(frozen=True)
class ContextSegment:
    provenance: Provenance
    source_id: str
    content: str

    @property
    def content_sha256(self) -> str:
        return hashlib.sha256(self.content.encode("utf-8")).hexdigest()

    def envelope(self) -> dict[str, Any]:
        return {
            "provenance": self.provenance.value,
            "sourceId": self.source_id,
            "contentSha256": self.content_sha256,
            "untrusted": self.provenance.untrusted,
            "content": self.content,
        }


class ContextAssembler:
    @staticmethod
    def assemble(segments: Sequence[ContextSegment]) -> dict[str, Any]:
        return {
            "schemaVersion": "2.0.0",
            "controlPlane": {
                "authoritySource": "policy_engine_only",
                "contentCannotGrantAuthority": True,
            },
            "segments": [segment.envelope() for segment in segments],
        }


@dataclass(frozen=True)
class EffectIntent:
    capability: str
    destination: str
    provenance: Provenance
    derived_from_untrusted_content: bool = False
    contains_secret: bool = False


@dataclass(frozen=True)
class EffectDecision:
    allowed: bool
    code: str


class InjectionGuard:
    def authorize(
        self,
        intent: EffectIntent,
        *,
        granted_capabilities: Iterable[str],
        allowed_destinations: Iterable[str],
        secret_destinations: Iterable[str] = (),
    ) -> EffectDecision:
        grants = frozenset(granted_capabilities)
        destinations = frozenset(allowed_destinations)
        secret_targets = frozenset(secret_destinations)
        if intent.capability not in grants:
            return EffectDecision(False, "capability_not_granted")
        if intent.destination not in destinations:
            return EffectDecision(False, "destination_not_granted")
        if intent.contains_secret and intent.destination not in secret_targets:
            return EffectDecision(False, "secret_destination_not_granted")
        if intent.provenance.untrusted and intent.derived_from_untrusted_content:
            if intent.capability in {"grant_authority", "change_policy", "reveal_secret"}:
                return EffectDecision(False, "untrusted_content_cannot_change_authority")
        return EffectDecision(True, "explicit_policy_grant")


@dataclass(frozen=True)
class BrowserPlanStep:
    kind: str
    target: str = ""
    observation_age_ms: int = 0
    retry: int = 0
    destructive: bool = False
    requires_takeover: bool = False


class BrowserPlanningPolicy:
    def __init__(self, *, max_observation_age_ms: int = 15000, max_retries: int = 2) -> None:
        self.max_observation_age_ms = max_observation_age_ms
        self.max_retries = max_retries

    def validate(self, steps: Sequence[BrowserPlanStep]) -> tuple[bool, str]:
        observed = False
        awaiting_verification = False
        takeover_ready = False
        for step in steps:
            if step.retry > self.max_retries:
                return False, "browser_retry_budget_exceeded"
            if step.kind == "observe":
                observed = True
                awaiting_verification = False
                takeover_ready = False
                continue
            if step.kind == "takeover":
                if not observed:
                    return False, "browser_takeover_without_observation"
                takeover_ready = True
                continue
            if step.kind == "verify":
                if not awaiting_verification:
                    return False, "browser_verify_without_action"
                awaiting_verification = False
                observed = True
                continue
            if step.kind != "action":
                return False, "browser_step_kind_invalid"
            if not observed or awaiting_verification:
                return False, "browser_action_requires_fresh_observation"
            if step.observation_age_ms > self.max_observation_age_ms:
                return False, "browser_target_stale"
            if (step.destructive or step.requires_takeover) and not takeover_ready:
                return False, "browser_takeover_required"
            awaiting_verification = True
            observed = False
            takeover_ready = False
        if awaiting_verification:
            return False, "browser_postcondition_missing"
        return True, "observe_action_verify_satisfied"


@dataclass(frozen=True)
class TerminalPlan:
    mode: str
    command: str
    destructive: bool = False
    approval_granted: bool = False
    readiness_probe: str = ""
    kill_strategy: str = ""
    verification: str = ""


class TerminalPlanningPolicy:
    MODES = frozenset({"finite", "interactive", "background"})

    def validate(self, plan: TerminalPlan) -> tuple[bool, str]:
        if plan.mode not in self.MODES:
            return False, "terminal_mode_invalid"
        if not plan.command.strip():
            return False, "terminal_command_missing"
        if plan.destructive and not plan.approval_granted:
            return False, "terminal_destructive_scope_requires_approval"
        if plan.mode in {"interactive", "background"} and not plan.readiness_probe.strip():
            return False, "terminal_readiness_probe_required"
        if plan.mode == "background" and not plan.kill_strategy.strip():
            return False, "terminal_kill_strategy_required"
        if not plan.verification.strip():
            return False, "terminal_verification_required"
        return True, "terminal_plan_bounded"


@dataclass(frozen=True)
class ResearchClaim:
    claim_id: str
    fetched: bool
    citation_locator: str
    source_type: str
    fetched_at: str
    freshness_seconds: int
    snippet_only: bool = False
    conflict_group: str = ""


class ResearchAnswerPolicy:
    def verify(
        self,
        claims: Sequence[ResearchClaim],
        *,
        now: datetime,
        disagreement_groups: Iterable[str] = (),
    ) -> tuple[bool, tuple[str, ...]]:
        declared_disagreement = frozenset(disagreement_groups)
        failures: list[str] = []
        conflicts: dict[str, int] = {}
        instant = now.astimezone(timezone.utc)
        for claim in claims:
            if not claim.fetched or claim.snippet_only:
                failures.append(f"{claim.claim_id}:source_not_fetched")
            if not claim.citation_locator.strip():
                failures.append(f"{claim.claim_id}:citation_missing")
            try:
                fetched_at = datetime.fromisoformat(claim.fetched_at.replace("Z", "+00:00"))
            except ValueError:
                failures.append(f"{claim.claim_id}:fetched_at_invalid")
                continue
            if (instant - fetched_at.astimezone(timezone.utc)).total_seconds() > claim.freshness_seconds:
                failures.append(f"{claim.claim_id}:source_stale")
            if claim.source_type not in {"primary", "official", "independent", "repository"}:
                failures.append(f"{claim.claim_id}:source_type_invalid")
            if claim.conflict_group:
                conflicts[claim.conflict_group] = conflicts.get(claim.conflict_group, 0) + 1
        for group, count in conflicts.items():
            if count > 1 and group not in declared_disagreement:
                failures.append(f"{group}:disagreement_not_surfaced")
        return not failures, tuple(sorted(set(failures)))


REQUIRED_MODEL_SUITES = ("protocol", "coding", "browser", "research", "safety")


@dataclass(frozen=True)
class ModelSuiteResult:
    provider: str
    model: str
    suite: str
    passed: bool
    score_milli: int
    latency_ms: int
    cost_microunits: int = 0
    false_completions: int = 0
    unauthorized_attempts: int = 0
    unauthorized_effects: int = 0
    recoveries: int = 0


class ModelCompatibilityMatrix:
    @staticmethod
    def build(results: Sequence[ModelSuiteResult]) -> dict[str, Any]:
        rows: dict[str, dict[str, ModelSuiteResult]] = {}
        for result in results:
            if result.suite not in REQUIRED_MODEL_SUITES:
                raise ValueError(f"unsupported_model_suite:{result.suite}")
            identity = f"{result.provider}/{result.model}"
            suites = rows.setdefault(identity, {})
            if result.suite in suites:
                raise ValueError(f"duplicate_model_suite_result:{identity}:{result.suite}")
            suites[result.suite] = result
        models: list[dict[str, Any]] = []
        for identity in sorted(rows):
            suites = rows[identity]
            missing = [suite for suite in REQUIRED_MODEL_SUITES if suite not in suites]
            supported = not missing and all(suites[suite].passed for suite in REQUIRED_MODEL_SUITES)
            ordered = [asdict(suites[suite]) for suite in REQUIRED_MODEL_SUITES if suite in suites]
            models.append(
                {
                    "identity": identity,
                    "support": "supported" if supported else "evaluation_only",
                    "missingSuites": missing,
                    "results": ordered,
                }
            )
        payload = {"schemaVersion": "1.0.0", "models": models}
        payload["sha256"] = _sha256(payload)
        return payload


class AgentBenchmarkDashboard:
    @staticmethod
    def build(results: Sequence[ModelSuiteResult]) -> dict[str, Any]:
        matrix = ModelCompatibilityMatrix.build(results)
        totals = {
            "cases": len(results),
            "passed": sum(1 for item in results if item.passed),
            "falseCompletions": sum(item.false_completions for item in results),
            "unauthorizedAttempts": sum(item.unauthorized_attempts for item in results),
            "unauthorizedEffects": sum(item.unauthorized_effects for item in results),
            "recoveries": sum(item.recoveries for item in results),
            "latencyMs": sum(item.latency_ms for item in results),
            "costMicrounits": sum(item.cost_microunits for item in results),
        }
        payload = {
            "schemaVersion": "1.0.0",
            "matrixSha256": matrix["sha256"],
            "totals": totals,
        }
        payload["sha256"] = _sha256(payload)
        return payload


def _sha256(value: Mapping[str, Any]) -> str:
    body = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(body.encode("utf-8")).hexdigest()
