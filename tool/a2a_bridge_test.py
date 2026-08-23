#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from ed25519_ref import public_key
from signed_manifest_v2 import canonical_json, sign_manifest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "tool" / "a2a_bridge.py"
AGENT = ROOT / "test" / "product" / "fixtures" / "interoperability_v19" / "mock_a2a_agent.py"
SEED = bytes(range(32))
KEY_ID = "test-a2a-registry"


def digest(value: dict[str, object]) -> str:
    import hashlib

    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def write_trust(temp: Path, *, bad_descriptor_digest: bool = False) -> tuple[Path, Path]:
    descriptor: dict[str, object] = {
        "executable": sys.executable,
        "arguments": [str(AGENT)],
        "workingDirectory": str(ROOT),
        "capabilities": ["summarize"],
        "timeoutSeconds": 10,
        "maxOutputBytes": 65536,
    }
    registry_payload = {
        "schemaVersion": "1.0.0",
        "agents": [
            {
                "id": "validator.agent",
                "descriptor": descriptor,
                "descriptorSha256": "0" * 64 if bad_descriptor_digest else digest(descriptor),
            }
        ],
    }
    envelope = sign_manifest(
        {
            "schemaVersion": "2.0.0",
            "keyId": KEY_ID,
            "intendedUse": "a2a_agent_registry",
            "trustDomain": "kristin.a2a",
            "issuedAt": "2026-01-01T00:00:00Z",
            "expiresAt": "2099-01-01T00:00:00Z",
            "payload": registry_payload,
        },
        seed=SEED,
    )
    registry = temp / "registry.signed.json"
    registry.write_text(json.dumps(envelope, sort_keys=True), encoding="utf-8")
    keyring = temp / "keyring.json"
    keyring.write_text(
        json.dumps(
            {
                "keys": [
                    {
                        "keyId": KEY_ID,
                        "publicKeyHex": public_key(SEED).hex(),
                        "intendedUses": ["a2a_agent_registry"],
                        "trustDomains": ["kristin.a2a"],
                    }
                ]
            },
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    return registry, keyring


def invocation_env(*, capabilities: list[str] | None = None) -> dict[str, str]:
    requested = capabilities or ["summarize"]
    request = {
        "contract": {
            "taskId": "task-1",
            "allowedCapabilities": requested,
            "maxSteps": 4,
        },
        "payload": {},
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
    return {
        **os.environ,
        "KRISTIN_A2A_REQUEST_JSON": json.dumps(request, sort_keys=True),
        "KRISTIN_A2A_GRANT_JSON": json.dumps(grant, sort_keys=True),
        "KRISTIN_A2A_AGENT_ID": "validator.agent",
    }


def run_bridge(registry: Path, keyring: Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(BRIDGE),
            "--registry",
            str(registry),
            "--keyring",
            str(keyring),
        ],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=20,
    )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="kristin-a2a-") as raw:
        temp = Path(raw)
        registry, keyring = write_trust(temp)
        completed = run_bridge(registry, keyring, invocation_env())
        assert completed.returncode == 0, completed.stderr
        response = json.loads(completed.stdout)
        assert response["taskId"] == "task-1"
        assert response["usedCapabilities"] == ["summarize"]

        raw_target = invocation_env()
        raw_target["KRISTIN_A2A_TARGET_JSON"] = json.dumps({"executable": "/bin/echo"})
        blocked = run_bridge(registry, keyring, raw_target)
        assert blocked.returncode != 0
        assert "a2a_raw_target_forbidden" in blocked.stderr

        exceeded = run_bridge(registry, keyring, invocation_env(capabilities=["summarize", "deploy"]))
        assert exceeded.returncode != 0
        assert "a2a_grant_capability_exceeded" in exceeded.stderr

    with tempfile.TemporaryDirectory(prefix="kristin-a2a-bad-") as raw:
        temp = Path(raw)
        registry, keyring = write_trust(temp, bad_descriptor_digest=True)
        bad = run_bridge(registry, keyring, invocation_env())
        assert bad.returncode != 0
        assert "a2a_descriptor_digest_mismatch" in bad.stderr

    print("PASS A2A bridge: signed registry, scoped grant, raw target rejection")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
