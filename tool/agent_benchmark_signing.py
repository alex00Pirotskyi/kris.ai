#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Sequence

from agent_safety_v2 import AgentBenchmarkDashboard, ModelSuiteResult
from signed_manifest_v2 import sign_manifest


def sign_dashboard(
    results: Sequence[ModelSuiteResult],
    *,
    seed: bytes,
    key_id: str,
    issued_at: datetime,
    expires_at: datetime,
) -> dict[str, Any]:
    if issued_at.tzinfo is None or expires_at.tzinfo is None:
        raise ValueError("benchmark_signature_time_must_be_timezone_aware")
    if expires_at <= issued_at:
        raise ValueError("benchmark_signature_expiry_invalid")
    dashboard = AgentBenchmarkDashboard.build(results)
    body = {
        "schemaVersion": "2.0.0",
        "keyId": key_id,
        "intendedUse": "agent_benchmark_dashboard",
        "trustDomain": "kristin.evals",
        "issuedAt": issued_at.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
        "expiresAt": expires_at.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
        "payload": dashboard,
    }
    return sign_manifest(body, seed=seed)
