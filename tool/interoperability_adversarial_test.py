#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone

from a2a_bridge import validate_delegation
from a2a_protocol_v1 import A2AProtocolAdapter, TaskSnapshot
from agent_safety_v2 import EffectIntent, InjectionGuard, Provenance
from ed25519_ref import public_key
from extension_registry_v2 import ExtensionRegistryV2
from signed_manifest_v2 import ExternalKeyring, TrustKey, sign_manifest

GOOD_SEED = bytes(range(32))
ATTACKER_SEED = bytes(reversed(range(32)))
KEY_ID = "trusted-publisher"
CODE_SHA = "a" * 64
TEST_SHA = "b" * 64


def expect_error(fn, code: str) -> None:
    try:
        fn()
    except Exception as exc:
        assert code in str(exc), exc
        return
    raise AssertionError(f"expected {code}")


def extension_envelope(seed: bytes = GOOD_SEED) -> dict[str, object]:
    return sign_manifest(
        {
            "schemaVersion": "2.0.0",
            "keyId": KEY_ID,
            "intendedUse": "kristin_extension",
            "trustDomain": "kristin.extensions",
            "issuedAt": "2026-01-01T00:00:00Z",
            "expiresAt": "2099-01-01T00:00:00Z",
            "payload": {
                "schemaVersion": "2.0.0",
                "extensionType": "plugin",
                "id": "safe-reader",
                "publisher": "trusted.example",
                "version": "2.0.0",
                "codeSha256": CODE_SHA,
                "testsSha256": TEST_SHA,
                "requestedCapabilities": ["read_project"],
                "compatibility": [">=2.0.0", "<3.0.0"],
                "entryPoint": "bin/safe_reader",
            },
        },
        seed=seed,
    )


def main() -> int:
    guard = InjectionGuard()
    hijack = guard.authorize(
        EffectIntent(
            capability="change_policy",
            destination="kristin://policy",
            provenance=Provenance.A2A,
            derived_from_untrusted_content=True,
        ),
        granted_capabilities={"change_policy"},
        allowed_destinations={"kristin://policy"},
    )
    assert not hijack.allowed
    assert hijack.code == "untrusted_content_cannot_change_authority"

    lookalike = guard.authorize(
        EffectIntent(
            capability="read_project_admin",
            destination="project://current",
            provenance=Provenance.MCP,
        ),
        granted_capabilities={"read_project"},
        allowed_destinations={"project://current"},
    )
    assert not lookalike.allowed and lookalike.code == "capability_not_granted"

    keyring = ExternalKeyring(
        {
            KEY_ID: TrustKey(
                key_id=KEY_ID,
                public_key=public_key(GOOD_SEED),
                intended_uses=frozenset({"kristin_extension"}),
                trust_domains=frozenset({"kristin.extensions"}),
            )
        }
    )
    registry = ExtensionRegistryV2()
    expect_error(
        lambda: registry.install(
            extension_envelope(ATTACKER_SEED),
            keyring=keyring,
            now=datetime(2026, 8, 23, 12, tzinfo=timezone.utc),
            actual_code_sha256=CODE_SHA,
            actual_tests_sha256=TEST_SHA,
        ),
        "signature",
    )

    descriptor = {
        "capabilities": ["summarize"],
        "timeoutSeconds": 10,
        "maxOutputBytes": 65536,
    }
    request = {
        "contract": {
            "taskId": "task-1",
            "allowedCapabilities": ["summarize", "deploy"],
        }
    }
    grant = {
        "schemaVersion": "1.0.0",
        "agentId": "validator.agent",
        "taskId": "task-1",
        "allowedCapabilities": ["summarize"],
        "deadline": "2099-01-01T00:00:00Z",
        "timeoutSeconds": 10,
        "maxOutputBytes": 65536,
        "allowDownstreamDelegation": False,
    }
    expect_error(
        lambda: validate_delegation(request, grant, descriptor, "validator.agent"),
        "a2a_grant_capability_exceeded",
    )

    cascading_grant = dict(grant)
    cascading_grant["allowDownstreamDelegation"] = True
    cascading_request = {
        "contract": {"taskId": "task-1", "allowedCapabilities": ["summarize"]}
    }
    expect_error(
        lambda: validate_delegation(
            cascading_request,
            cascading_grant,
            descriptor,
            "validator.agent",
        ),
        "a2a_downstream_delegation_denied",
    )

    adapter = A2AProtocolAdapter()
    first = TaskSnapshot.from_json(
        {
            "taskId": "task-1",
            "state": "working",
            "revision": 1,
            "messages": [],
            "artifacts": [],
        }
    )
    expect_error(
        lambda: adapter.reconcile_stream(
            first,
            [
                {
                    "taskId": "task-1",
                    "state": "working",
                    "revision": 1,
                    "messages": [],
                    "artifacts": [],
                }
            ],
        ),
        "a2a_stream_revision_replayed",
    )

    forged_completion = TaskSnapshot.from_json(
        {
            "taskId": "task-2",
            "state": "completed",
            "revision": 5,
            "messages": [],
            "artifacts": [],
        }
    )
    expect_error(
        lambda: adapter.reconcile_stream(
            forged_completion,
            [
                {
                    "taskId": "task-2",
                    "state": "working",
                    "revision": 6,
                    "messages": [],
                    "artifacts": [],
                }
            ],
        ),
        "a2a_terminal_state_changed",
    )

    print(
        "PASS interoperability adversarial suite: injection, lookalike, signer substitution, confused deputy, replay, cascade"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
