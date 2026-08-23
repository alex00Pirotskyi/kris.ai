#!/usr/bin/env python3
"""One-shot A2A bridge resolved from signed registry and delegation authority."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any, Mapping, Sequence

from signed_manifest_v2 import ExternalKeyring, TrustKey, canonical_json, verify_manifest


ALLOWED_RESPONSE_STATES = frozenset(
    {"submitted", "working", "input_required", "completed", "failed", "canceled", "unknown"}
)


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


def _verified_payload(
    envelope: Mapping[str, Any],
    *,
    keyring: ExternalKeyring,
    intended_use: str,
) -> Mapping[str, Any]:
    body = verify_manifest(
        envelope,
        keyring=keyring,
        now=datetime.now(timezone.utc),
        expected_use=intended_use,
        expected_domain="kristin.a2a",
    )
    payload = body.get("payload")
    if not isinstance(payload, dict) or payload.get("schemaVersion") != "1.0.0":
        fail("a2a_signed_payload_invalid", "signed payload must use schemaVersion 1.0.0")
    return payload


def load_registry(path: Path, keyring: ExternalKeyring) -> Mapping[str, Any]:
    envelope = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(envelope, dict):
        fail("a2a_registry_invalid", "signed registry envelope must be an object")
    return _verified_payload(
        envelope,
        keyring=keyring,
        intended_use="a2a_agent_registry",
    )


def load_delegation(raw: str, keyring: ExternalKeyring) -> Mapping[str, Any]:
    try:
        envelope = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError("a2a_grant_invalid: delegation envelope is not JSON") from exc
    if not isinstance(envelope, dict):
        fail("a2a_grant_invalid", "delegation envelope must be an object")
    return _verified_payload(
        envelope,
        keyring=keyring,
        intended_use="a2a_delegation_grant",
    )


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


def _strings(value: Any) -> frozenset[str]:
    if value is None:
        return frozenset()
    if not isinstance(value, list):
        fail("a2a_contract_invalid", "bounded capability/artifact fields must be arrays")
    result = frozenset(str(item).strip() for item in value if str(item).strip())
    if len(result) != len([item for item in value if str(item).strip()]):
        fail("a2a_contract_invalid", "bounded arrays must not contain duplicate entries")
    return result


def _contract(request: Mapping[str, Any]) -> Mapping[str, Any]:
    value = request.get("contract")
    if not isinstance(value, dict):
        fail("a2a_contract_invalid", "request.contract must be an object")
    return value


def validate_delegation(
    request: Mapping[str, Any],
    grant: Mapping[str, Any],
    descriptor: Mapping[str, Any],
    agent_id: str,
) -> dict[str, Any]:
    contract = _contract(request)
    if str(grant.get("agentId") or "") != agent_id:
        fail("a2a_grant_agent_mismatch", "grant is bound to another agent")
    request_task = str(contract.get("taskId") or request.get("taskId") or "")
    if not request_task or str(grant.get("taskId") or "") != request_task:
        fail("a2a_grant_task_mismatch", "grant is bound to another task")

    requested = _strings(contract.get("allowedCapabilities"))
    granted = _strings(grant.get("allowedCapabilities"))
    descriptor_capabilities = _strings(descriptor.get("capabilities"))
    if not requested.issubset(granted):
        fail("a2a_grant_capability_exceeded", "request exceeds delegation grant")
    if not requested.issubset(descriptor_capabilities):
        fail("a2a_descriptor_capability_exceeded", "request exceeds registered descriptor")

    requested_inputs = _strings(contract.get("inputArtifacts"))
    requested_outputs = _strings(
        contract.get("outputArtifacts")
        if contract.get("outputArtifacts") is not None
        else contract.get("expectedArtifacts")
    )
    granted_inputs = _strings(grant.get("inputArtifacts"))
    granted_outputs = _strings(grant.get("outputArtifacts"))
    if not requested_inputs.issubset(granted_inputs):
        fail("a2a_grant_input_exceeded", "request input artifacts exceed delegation grant")
    if not requested_outputs.issubset(granted_outputs):
        fail("a2a_grant_output_exceeded", "request output artifacts exceed delegation grant")

    requested_network = _strings(contract.get("networkDestinations"))
    granted_network = _strings(grant.get("networkDestinations"))
    descriptor_network = _strings(descriptor.get("allowedNetworkDestinations"))
    if not requested_network.issubset(granted_network):
        fail("a2a_grant_network_exceeded", "request network destinations exceed delegation grant")
    if not requested_network.issubset(descriptor_network):
        fail("a2a_descriptor_network_exceeded", "request network destinations exceed registered descriptor")

    requested_secrets = _strings(contract.get("secretIds"))
    granted_secrets = _strings(grant.get("secretIds"))
    if not requested_secrets.issubset(granted_secrets):
        fail("a2a_grant_secret_exceeded", "request secret identities exceed delegation grant")
    if requested_secrets:
        fail("a2a_secret_broker_required", "this bridge has no secret broker; delegated secrets fail closed")

    if grant.get("allowDownstreamDelegation") is True:
        fail("a2a_downstream_delegation_denied", "bridge does not permit cascading delegation")
    deadline_raw = str(grant.get("deadline") or "")
    try:
        deadline = datetime.fromisoformat(deadline_raw.replace("Z", "+00:00"))
    except ValueError as exc:
        raise RuntimeError("a2a_grant_invalid: delegation deadline is invalid") from exc
    if deadline.astimezone(timezone.utc) <= datetime.now(timezone.utc):
        fail("a2a_grant_expired", "delegation deadline has passed")

    grant_steps = max(1, min(int(grant.get("maxSteps") or 1), 1024))
    request_steps = max(1, int(contract.get("maxSteps") or grant_steps))
    if request_steps > grant_steps:
        fail("a2a_grant_step_budget_exceeded", "request maxSteps exceeds delegation grant")
    idempotency_key = str(grant.get("idempotencyKey") or "").strip()
    if not idempotency_key:
        fail("a2a_grant_invalid", "idempotencyKey is required")
    requested_idempotency = str(contract.get("idempotencyKey") or idempotency_key).strip()
    if requested_idempotency != idempotency_key:
        fail("a2a_grant_idempotency_mismatch", "request idempotency key differs from delegation grant")

    execution_mode = str(descriptor.get("executionMode") or "").strip()
    if execution_mode not in {"isolated", "owner_host"}:
        fail("a2a_execution_mode_invalid", "descriptor must explicitly select isolated or owner_host execution")
    if execution_mode == "owner_host" and grant.get("allowHostExecution") is not True:
        fail("a2a_host_execution_not_granted", "host execution requires explicit owner delegation")
    if execution_mode == "isolated" and requested_network:
        fail("a2a_isolated_network_denied", "isolated A2A execution is network-denied in this bridge")

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
    return {
        "taskId": request_task,
        "allowedCapabilities": requested,
        "allowedOutputs": requested_outputs,
        "maxSteps": min(request_steps, grant_steps),
        "timeoutSeconds": timeout_seconds,
        "maxOutputBytes": max_output_bytes,
        "idempotencyKey": idempotency_key,
        "executionMode": execution_mode,
    }


def _host_execute(
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
        try:
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
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(
                "a2a_outcome_unknown: host agent timed out after execution began; reconcile before retry"
            ) from exc
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
    return stdout_text


def _isolated_execute(
    descriptor: Mapping[str, Any],
    request_json: str,
    grant_json: str,
    *,
    timeout_seconds: int,
    max_output_bytes: int,
) -> str:
    if not sys.platform.startswith("linux"):
        fail("a2a_isolated_backend_unavailable", "current isolated bridge backend is Linux-only")
    import sandbox_worker

    workspace = Path(str(descriptor.get("workspaceRoot") or "")).expanduser().resolve()
    if not workspace.is_dir():
        fail("a2a_workspace_invalid", "isolated descriptor workspaceRoot must exist")
    executable = str(descriptor.get("executable") or "")
    arguments: list[str] = []
    for raw in descriptor.get("arguments") or []:
        value = str(raw)
        candidate = Path(value)
        if candidate.is_absolute() and candidate.is_relative_to(workspace):
            value = f"/workspace/{candidate.relative_to(workspace).as_posix()}"
        arguments.append(value)
    working_directory = str(descriptor.get("workingDirectoryRelative") or ".")
    try:
        result = sandbox_worker.run_finite(
            executable=executable,
            arguments=arguments,
            project_root=workspace,
            working_directory=working_directory,
            workspace_mode="read_only",
            timeout_seconds=timeout_seconds,
            environment={
                "KRISTIN_A2A_REQUEST_JSON": request_json,
                "KRISTIN_A2A_GRANT_JSON": grant_json,
            },
            memory_limit_mb=min(max(128, int(descriptor.get("memoryLimitMb") or 512)), 4096),
            process_limit=min(max(8, int(descriptor.get("processLimit") or 32)), 256),
            file_size_limit_mb=16,
            max_output_bytes=max_output_bytes,
        )
    except sandbox_worker.SandboxUnavailableError as exc:
        raise RuntimeError("a2a_isolated_backend_unavailable: Linux sandbox is unavailable") from exc
    except sandbox_worker.SandboxError as exc:
        detail = str(exc)
        if "timed out" in detail.lower():
            raise RuntimeError(
                "a2a_outcome_unknown: isolated agent timed out; reconcile before retry"
            ) from exc
        raise RuntimeError(f"a2a_agent_failed: {detail[-1200:]}") from exc
    if result.get("truncated") is True:
        fail("a2a_output_limit_exceeded", "isolated agent output was truncated")
    if int(result.get("exitCode") or 0) != 0:
        fail("a2a_agent_failed", str(result.get("stderr") or result.get("stdout") or "agent failed")[-1200:])
    return str(result.get("stdout") or "").strip()


def execute_registered_agent(
    descriptor: Mapping[str, Any],
    request_json: str,
    grant_json: str,
    *,
    execution_mode: str,
    timeout_seconds: int,
    max_output_bytes: int,
) -> Mapping[str, Any]:
    if execution_mode == "isolated":
        stdout_text = _isolated_execute(
            descriptor,
            request_json,
            grant_json,
            timeout_seconds=timeout_seconds,
            max_output_bytes=max_output_bytes,
        )
    else:
        stdout_text = _host_execute(
            descriptor,
            request_json,
            grant_json,
            timeout_seconds=timeout_seconds,
            max_output_bytes=max_output_bytes,
        )
    try:
        decoded = json.loads(stdout_text)
    except json.JSONDecodeError as exc:
        raise RuntimeError("a2a_response_invalid: agent stdout is not JSON") from exc
    if not isinstance(decoded, dict):
        fail("a2a_response_invalid", "agent response must be an object")
    return decoded


def _artifact_ids(value: Any) -> frozenset[str]:
    if value is None:
        return frozenset()
    if not isinstance(value, list):
        fail("a2a_response_invalid", "outputArtifacts must be an array")
    ids: list[str] = []
    for item in value:
        if isinstance(item, dict):
            identifier = str(item.get("artifactId") or item.get("path") or "").strip()
        else:
            identifier = str(item).strip()
        if not identifier:
            fail("a2a_response_invalid", "output artifact identity is required")
        ids.append(identifier)
    if len(set(ids)) != len(ids):
        fail("a2a_response_invalid", "output artifact identities must be unique")
    return frozenset(ids)


def reconcile_response(response: Mapping[str, Any], authority: Mapping[str, Any]) -> Mapping[str, Any]:
    if str(response.get("taskId") or "") != authority["taskId"]:
        fail("a2a_response_task_mismatch", "agent response belongs to another task")
    state = str(response.get("status") or response.get("state") or "").lower()
    if state not in ALLOWED_RESPONSE_STATES:
        fail("a2a_response_state_invalid", "agent response state is invalid")
    used = _strings(response.get("usedCapabilities"))
    allowed = frozenset(authority["allowedCapabilities"])
    if not used.issubset(allowed):
        fail("a2a_response_capability_exceeded", "agent reported a capability outside the delegation")
    outputs = _artifact_ids(response.get("outputArtifacts") or response.get("artifacts"))
    allowed_outputs = frozenset(authority["allowedOutputs"])
    if not outputs.issubset(allowed_outputs):
        fail("a2a_response_artifact_exceeded", "agent returned an undeclared output artifact")
    steps = int(response.get("steps") or 0)
    if steps < 0 or steps > int(authority["maxSteps"]):
        fail("a2a_response_step_budget_exceeded", "agent exceeded delegated step budget")
    if state == "completed" and allowed_outputs and not allowed_outputs.issubset(outputs):
        fail("a2a_response_completion_incomplete", "completed response omitted required output artifacts")
    return {
        **dict(response),
        "trust": "untrusted_a2a_output",
        "reconciled": True,
        "idempotencyKey": authority["idempotencyKey"],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--keyring", required=True, type=Path)
    parser.add_argument("--agent-id")
    args = parser.parse_args()
    if "KRISTIN_A2A_TARGET_JSON" in os.environ:
        fail("a2a_raw_target_forbidden", "raw executable selection is permanently disabled")
    request_json = os.environ.get("KRISTIN_A2A_REQUEST_JSON", "")
    grant_envelope_json = os.environ.get("KRISTIN_A2A_GRANT_JSON", "")
    agent_id = args.agent_id or os.environ.get("KRISTIN_A2A_AGENT_ID", "")
    if not request_json or not grant_envelope_json or not agent_id:
        fail("a2a_invocation_incomplete", "request, signed delegation grant, and registered agent id are required")
    try:
        request = json.loads(request_json)
    except json.JSONDecodeError as exc:
        raise RuntimeError("a2a_invocation_invalid: request must be JSON") from exc
    if not isinstance(request, dict):
        fail("a2a_invocation_invalid", "request must be a JSON object")
    keyring = load_keyring(args.keyring.resolve())
    registry = load_registry(args.registry.resolve(), keyring)
    grant = load_delegation(grant_envelope_json, keyring)
    descriptor = resolve_agent(registry, agent_id)
    authority = validate_delegation(request, grant, descriptor, agent_id)
    verified_grant_json = canonical_json(dict(grant))
    response = execute_registered_agent(
        descriptor,
        request_json,
        verified_grant_json,
        execution_mode=str(authority["executionMode"]),
        timeout_seconds=int(authority["timeoutSeconds"]),
        max_output_bytes=int(authority["maxOutputBytes"]),
    )
    reconciled = reconcile_response(response, authority)
    sys.stdout.write(canonical_json(dict(reconciled)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
