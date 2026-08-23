#!/usr/bin/env python3
"""One-shot A2A bridge resolved only from a signed trusted registry."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any, Mapping

from signed_manifest_v2 import ExternalKeyring, TrustKey, canonical_json, verify_manifest


def fail(code: str, detail: str) -> None:
    raise RuntimeError(f"{code}: {detail}")


def load_keyring(path: Path) -> ExternalKeyring:
    raw = json.loads(path.read_text(encoding="utf-8"))
    keys: dict[str, TrustKey] = {}
    for item in raw.get("keys") or []:
        key_id = str(item.get("keyId") or "")
        if not key_id:
            fail("a2a_keyring_invalid", "keyId is required")
        try:
            public_key = bytes.fromhex(str(item["publicKeyHex"]))
        except (KeyError, ValueError) as exc:
            raise RuntimeError("a2a_keyring_invalid: publicKeyHex is invalid") from exc
        keys[key_id] = TrustKey(
            key_id=key_id,
            public_key=public_key,
            intended_uses=frozenset(str(value) for value in item.get("intendedUses") or []),
            trust_domains=frozenset(str(value) for value in item.get("trustDomains") or []),
            revoked=item.get("revoked") is True,
        )
    if not keys:
        fail("a2a_keyring_invalid", "at least one trusted key is required")
    return ExternalKeyring(keys)


def load_registry(path: Path, keyring: ExternalKeyring) -> Mapping[str, Any]:
    envelope = json.loads(path.read_text(encoding="utf-8"))
    body = verify_manifest(
        envelope,
        keyring=keyring,
        now=datetime.now(timezone.utc),
        expected_use="a2a_agent_registry",
        expected_domain="kristin.a2a",
    )
    payload = body.get("payload")
    if not isinstance(payload, dict) or payload.get("schemaVersion") != "1.0.0":
        fail("a2a_registry_invalid", "signed registry payload must use schemaVersion 1.0.0")
    return payload


def descriptor_digest(descriptor: Mapping[str, Any]) -> str:
    import hashlib

    return hashlib.sha256(canonical_json(dict(descriptor)).encode("utf-8")).hexdigest()


def resolve_agent(registry: Mapping[str, Any], agent_id: str) -> Mapping[str, Any]:
    matches = [
        item
        for item in registry.get("agents") or []
        if isinstance(item, dict) and str(item.get("id") or "") == agent_id
    ]
    if len(matches) != 1:
        fail("a2a_agent_unregistered", f"registered agent not found exactly once: {agent_id}")
    item = matches[0]
    descriptor = item.get("descriptor")
    expected = str(item.get("descriptorSha256") or "")
    if not isinstance(descriptor, dict) or not expected:
        fail("a2a_descriptor_invalid", "descriptor and descriptorSha256 are required")
    actual = descriptor_digest(descriptor)
    if actual != expected:
        fail("a2a_descriptor_digest_mismatch", "registered descriptor changed")
    return descriptor


def validate_delegation(
    request: Mapping[str, Any],
    grant: Mapping[str, Any],
    descriptor: Mapping[str, Any],
    agent_id: str,
) -> tuple[int, int]:
    if grant.get("schemaVersion") != "1.0.0":
        fail("a2a_grant_invalid", "grant schemaVersion must be 1.0.0")
    if str(grant.get("agentId") or "") != agent_id:
        fail("a2a_grant_agent_mismatch", "grant is bound to another agent")
    request_task = str(request.get("contract", {}).get("taskId") or request.get("taskId") or "")
    if not request_task or str(grant.get("taskId") or "") != request_task:
        fail("a2a_grant_task_mismatch", "grant is bound to another task")
    requested = {
        str(value)
        for value in (
            request.get("contract", {}).get("allowedCapabilities")
            or request.get("requestedCapabilities")
            or []
        )
    }
    granted = {str(value) for value in grant.get("allowedCapabilities") or []}
    descriptor_capabilities = {
        str(value) for value in descriptor.get("capabilities") or []
    }
    if not requested.issubset(granted):
        fail("a2a_grant_capability_exceeded", "request exceeds delegation grant")
    if not requested.issubset(descriptor_capabilities):
        fail("a2a_descriptor_capability_exceeded", "request exceeds registered descriptor")
    if grant.get("allowDownstreamDelegation") is True:
        fail("a2a_downstream_delegation_denied", "bridge does not permit cascading delegation")
    deadline = datetime.fromisoformat(str(grant.get("deadline") or "").replace("Z", "+00:00"))
    if deadline.astimezone(timezone.utc) <= datetime.now(timezone.utc):
        fail("a2a_grant_expired", "delegation deadline has passed")
    timeout_seconds = min(
        max(1, int(descriptor.get("timeoutSeconds") or 20)),
        max(1, int(grant.get("timeoutSeconds") or 20)),
        120,
    )
    max_output_bytes = min(
        max(1024, int(descriptor.get("maxOutputBytes") or 1024 * 1024)),
        max(1024, int(grant.get("maxOutputBytes") or 1024 * 1024)),
        8 * 1024 * 1024,
    )
    return timeout_seconds, max_output_bytes


def execute_registered_agent(
    descriptor: Mapping[str, Any],
    request_json: str,
    grant_json: str,
    *,
    timeout_seconds: int,
    max_output_bytes: int,
) -> str:
    executable = Path(str(descriptor.get("executable") or ""))
    if not executable.is_absolute() or not executable.is_file():
        fail("a2a_executable_invalid", "registered executable must be an existing absolute file")
    arguments = [str(item) for item in descriptor.get("arguments") or []]
    cwd_raw = str(descriptor.get("workingDirectory") or executable.parent)
    cwd = Path(cwd_raw)
    if not cwd.is_absolute() or not cwd.is_dir():
        fail("a2a_working_directory_invalid", "registered working directory must exist and be absolute")
    environment = {
        "KRISTIN_A2A_REQUEST_JSON": request_json,
        "KRISTIN_A2A_GRANT_JSON": grant_json,
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "LANG": os.environ.get("LANG", "C.UTF-8"),
        "LC_ALL": os.environ.get("LC_ALL", os.environ.get("LANG", "C.UTF-8")),
    }
    with tempfile.TemporaryFile() as stdout_file, tempfile.TemporaryFile() as stderr_file:
        completed = subprocess.run(
            [str(executable), *arguments],
            cwd=str(cwd),
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=stdout_file,
            stderr=stderr_file,
            check=False,
            timeout=timeout_seconds,
        )
        stdout_file.seek(0)
        stdout = stdout_file.read(max_output_bytes + 1)
        stderr_file.seek(0)
        stderr = stderr_file.read(min(max_output_bytes, 256 * 1024) + 1)
    if len(stdout) > max_output_bytes:
        fail("a2a_output_limit_exceeded", "agent stdout exceeded delegation limit")
    if len(stderr) > min(max_output_bytes, 256 * 1024):
        stderr = stderr[: min(max_output_bytes, 256 * 1024)]
    stdout_text = stdout.decode("utf-8", errors="replace").strip()
    stderr_text = stderr.decode("utf-8", errors="replace").strip()
    if completed.returncode != 0:
        fail("a2a_agent_failed", (stderr_text or stdout_text or "agent failed")[-1200:])
    try:
        decoded = json.loads(stdout_text)
    except json.JSONDecodeError as exc:
        raise RuntimeError("a2a_response_invalid: agent stdout is not JSON") from exc
    if not isinstance(decoded, dict):
        fail("a2a_response_invalid", "agent response must be an object")
    return json.dumps(decoded, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--keyring", required=True, type=Path)
    parser.add_argument("--agent-id")
    args = parser.parse_args()
    if "KRISTIN_A2A_TARGET_JSON" in os.environ:
        fail("a2a_raw_target_forbidden", "raw executable selection is permanently disabled")
    request_json = os.environ.get("KRISTIN_A2A_REQUEST_JSON", "")
    grant_json = os.environ.get("KRISTIN_A2A_GRANT_JSON", "")
    agent_id = args.agent_id or os.environ.get("KRISTIN_A2A_AGENT_ID", "")
    if not request_json or not grant_json or not agent_id:
        fail("a2a_invocation_incomplete", "request, delegation grant, and registered agent id are required")
    request = json.loads(request_json)
    grant = json.loads(grant_json)
    if not isinstance(request, dict) or not isinstance(grant, dict):
        fail("a2a_invocation_invalid", "request and grant must be JSON objects")
    keyring = load_keyring(args.keyring.resolve())
    registry = load_registry(args.registry.resolve(), keyring)
    descriptor = resolve_agent(registry, agent_id)
    timeout_seconds, max_output_bytes = validate_delegation(
        request,
        grant,
        descriptor,
        agent_id,
    )
    sys.stdout.write(
        execute_registered_agent(
            descriptor,
            request_json,
            grant_json,
            timeout_seconds=timeout_seconds,
            max_output_bytes=max_output_bytes,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
