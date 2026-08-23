#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from agent_benchmark_signing import sign_dashboard
from agent_safety_v2 import ModelSuiteResult, REQUIRED_MODEL_SUITES
from ed25519_ref import public_key
from signed_manifest_v2 import ExternalKeyring, TrustKey, verify_manifest

SEED = bytes(range(32))
KEY_ID = "benchmark-test"


def main() -> int:
    results = [
        ModelSuiteResult(
            provider="ollama",
            model="qwen-test",
            suite=suite,
            passed=True,
            score_milli=900,
            latency_ms=100,
            recoveries=1 if suite == "coding" else 0,
        )
        for suite in REQUIRED_MODEL_SUITES
    ]
    issued = datetime(2026, 8, 23, 12, tzinfo=timezone.utc)
    expires = issued + timedelta(days=30)
    first = sign_dashboard(
        results,
        seed=SEED,
        key_id=KEY_ID,
        issued_at=issued,
        expires_at=expires,
    )
    second = sign_dashboard(
        results,
        seed=SEED,
        key_id=KEY_ID,
        issued_at=issued,
        expires_at=expires,
    )
    assert first == second
    keyring = ExternalKeyring(
        {
            KEY_ID: TrustKey(
                key_id=KEY_ID,
                public_key=public_key(SEED),
                intended_uses=frozenset({"agent_benchmark_dashboard"}),
                trust_domains=frozenset({"kristin.evals"}),
            )
        }
    )
    verified = verify_manifest(
        first,
        keyring=keyring,
        now=issued,
        expected_use="agent_benchmark_dashboard",
        expected_domain="kristin.evals",
    )
    payload = verified["payload"]
    assert payload["totals"]["unauthorizedEffects"] == 0
    assert len(payload["sha256"]) == 64

    print("PASS benchmark signing: deterministic dashboard and Signed Manifest v2 verification")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
