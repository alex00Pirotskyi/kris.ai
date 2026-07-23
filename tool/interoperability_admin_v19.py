#!/usr/bin/env python3
"""Deterministic v1.9 interoperability, administration, and release helpers.

This module is intentionally standard-library only so a source checkout can be
validated before Flutter, Dart, or platform packaging tools are installed.

Implemented foundations:
- typed MCP server manifests and lifecycle negotiation
- bounded A2A task delegation contracts
- authenticated capability/plugin/skill/agent manifests
- policy profiles and fleet overlays
- append-only audit-chain verification with keyed integrity
- authenticated source-update manifests and rollback policy checks
- support lifecycle / compatibility policy evaluation

Not implemented here:
- native signed installers
- native cross-platform update application
- remote transport execution
- platform-specific MCP worker backends beyond the existing Linux sandbox
"""
from __future__ import annotations

from dataclasses import dataclass, field
import datetime as dt
import hashlib
import hmac
import json
from pathlib import Path
import re
from typing import Any, Mapping

VERSION = "1.9.0+190"
SCHEMA_VERSION = "1.0.0"
SIGNATURE_ALGORITHM = "hmac-sha256"
MANIFEST_KINDS = frozenset({"plugin", "skill", "agent"})
DATA_BOUNDARIES = frozenset({"local", "private_remote", "public_cloud"})
A2A_CAPABILITIES = frozenset({
    "inspect_artifact",
    "verify_artifact",
    "summarize_trace",
    "review_plan",
    "review_code",
    "prepare_release_notes",
})
MCP_TRANSPORTS = frozenset({"local_stdio", "remote_https"})
MCP_KINDS = frozenset({"tool", "resource", "prompt"})
APPROVAL_LEVELS = frozenset({"none", "reviewed", "explicit", "enterprise"})


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_text(text: str) -> str:
    return sha256_hex(text.encode("utf-8"))


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9._-]+", "-", value.strip().lower()).strip("-")


def _string(value: Any, label: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{label} must be a string")
    text = value.strip()
    if not text and not allow_empty:
        raise ValueError(f"{label} must not be empty")
    return text


def _string_list(value: Any, label: str, *, minimum: int = 0) -> tuple[str, ...]:
    if not isinstance(value, list):
        raise ValueError(f"{label} must be an array")
    result = tuple(_string(item, f"{label}[{index}]") for index, item in enumerate(value))
    if len(result) < minimum:
        raise ValueError(f"{label} must contain at least {minimum} items")
    return result


def _normalize_relpath(path: str) -> str:
    text = _string(path, "path")
    if text.startswith("/") or re.match(r"^[a-zA-Z]:", text):
        raise ValueError("paths must be project-relative or object references")
    parts = [part for part in text.replace("\\", "/").split("/") if part not in ("", ".")]
    if any(part == ".." for part in parts):
        raise ValueError("path traversal is not allowed")
    return "/".join(parts)


@dataclass(frozen=True)
class SignatureEnvelope:
    signer_id: str
    algorithm: str
    signed_at: str
    payload_sha256: str
    signature: str

    def to_json(self) -> dict[str, str]:
        return {
            "signerId": self.signer_id,
            "algorithm": self.algorithm,
            "signedAt": self.signed_at,
            "payloadSha256": self.payload_sha256,
            "signature": self.signature,
        }


def sign_payload(payload: Mapping[str, Any], *, signer_id: str, secret: str, signed_at: str | None = None) -> SignatureEnvelope:
    body = canonical_json(payload)
    digest = sha256_text(body)
    timestamp = signed_at or utc_now()
    material = canonical_json(
        {
            "algorithm": SIGNATURE_ALGORITHM,
            "payloadSha256": digest,
            "signedAt": timestamp,
            "signerId": signer_id,
        }
    )
    signature = hmac.new(secret.encode("utf-8"), material.encode("utf-8"), hashlib.sha256).hexdigest()
    return SignatureEnvelope(
        signer_id=_string(signer_id, "signer_id"),
        algorithm=SIGNATURE_ALGORITHM,
        signed_at=timestamp,
        payload_sha256=digest,
        signature=signature,
    )


def verify_signature(payload: Mapping[str, Any], envelope: SignatureEnvelope, *, secret_lookup: Mapping[str, str]) -> tuple[bool, str]:
    secret = secret_lookup.get(envelope.signer_id)
    if not secret:
        return False, "unknown_signer"
    if envelope.algorithm != SIGNATURE_ALGORITHM:
        return False, "unsupported_signature_algorithm"
    payload_digest = sha256_text(canonical_json(payload))
    if payload_digest != envelope.payload_sha256:
        return False, "payload_sha256_mismatch"
    expected = sign_payload(payload, signer_id=envelope.signer_id, secret=secret, signed_at=envelope.signed_at)
    if not hmac.compare_digest(expected.signature, envelope.signature):
        return False, "signature_mismatch"
    return True, "signature_verified"


@dataclass(frozen=True)
class CapabilityManifest:
    schema_version: str
    kind: str
    id: str
    title: str
    version: int
    purpose: str
    input_schema: str
    output_schema: str
    capabilities: tuple[str, ...]
    data_boundary: str
    model_requirements: tuple[str, ...]
    approval_policy: str
    evaluation_results: tuple[str, ...]
    provenance: tuple[str, ...]
    compatibility: tuple[str, ...]

    def to_payload(self) -> dict[str, Any]:
        return {
            "schemaVersion": self.schema_version,
            "kind": self.kind,
            "id": self.id,
            "title": self.title,
            "version": self.version,
            "purpose": self.purpose,
            "inputSchema": self.input_schema,
            "outputSchema": self.output_schema,
            "capabilities": list(self.capabilities),
            "dataBoundary": self.data_boundary,
            "modelRequirements": list(self.model_requirements),
            "approvalPolicy": self.approval_policy,
            "evaluationResults": list(self.evaluation_results),
            "provenance": list(self.provenance),
            "compatibility": list(self.compatibility),
        }

    @classmethod
    def create(
        cls,
        *,
        kind: str,
        identifier: str,
        title: str,
        version: int,
        purpose: str,
        input_schema: str,
        output_schema: str,
        capabilities: list[str],
        data_boundary: str,
        model_requirements: list[str],
        approval_policy: str,
        evaluation_results: list[str],
        provenance: list[str],
        compatibility: list[str],
    ) -> "CapabilityManifest":
        normalized_kind = _slug(kind)
        if normalized_kind not in MANIFEST_KINDS:
            raise ValueError("manifest kind must be plugin, skill, or agent")
        if data_boundary not in DATA_BOUNDARIES:
            raise ValueError("manifest data boundary is invalid")
        if approval_policy not in APPROVAL_LEVELS:
            raise ValueError("approval policy is invalid")
        capability_items = tuple(sorted({_string(item, "capability") for item in capabilities}))
        if not capability_items:
            raise ValueError("manifest capabilities must not be empty")
        return cls(
            schema_version=SCHEMA_VERSION,
            kind=normalized_kind,
            id=_slug(identifier),
            title=_string(title, "title"),
            version=max(1, int(version)),
            purpose=_string(purpose, "purpose"),
            input_schema=_string(input_schema, "input_schema"),
            output_schema=_string(output_schema, "output_schema"),
            capabilities=capability_items,
            data_boundary=data_boundary,
            model_requirements=tuple(sorted({_string(item, "model_requirement") for item in model_requirements})),
            approval_policy=approval_policy,
            evaluation_results=tuple(sorted({_string(item, "evaluation_result") for item in evaluation_results})),
            provenance=tuple(sorted({_string(item, "provenance") for item in provenance})),
            compatibility=tuple(sorted({_string(item, "compatibility") for item in compatibility})),
        )


@dataclass(frozen=True)
class SignedCapabilityManifest:
    manifest: CapabilityManifest
    signature: SignatureEnvelope

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "manifest": self.manifest.to_payload(),
            "signature": self.signature.to_json(),
        }


def sign_manifest(manifest: CapabilityManifest, *, signer_id: str, secret: str, signed_at: str | None = None) -> SignedCapabilityManifest:
    return SignedCapabilityManifest(
        manifest=manifest,
        signature=sign_payload(manifest.to_payload(), signer_id=signer_id, secret=secret, signed_at=signed_at),
    )


def verify_manifest(signed: SignedCapabilityManifest, *, secret_lookup: Mapping[str, str]) -> tuple[bool, str]:
    return verify_signature(signed.manifest.to_payload(), signed.signature, secret_lookup=secret_lookup)


@dataclass(frozen=True)
class PolicyProfile:
    id: str
    title: str
    allow_remote_mcp: bool
    allow_a2a: bool
    allow_public_cloud_models: bool
    allow_source_updates: bool
    require_manifest_signatures: bool
    required_approval: str
    allowed_update_channels: tuple[str, ...]
    trusted_signers: tuple[str, ...]

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "id": self.id,
            "title": self.title,
            "allowRemoteMcp": self.allow_remote_mcp,
            "allowA2A": self.allow_a2a,
            "allowPublicCloudModels": self.allow_public_cloud_models,
            "allowSourceUpdates": self.allow_source_updates,
            "requireManifestSignatures": self.require_manifest_signatures,
            "requiredApproval": self.required_approval,
            "allowedUpdateChannels": list(self.allowed_update_channels),
            "trustedSigners": list(self.trusted_signers),
        }


def built_in_policy(name: str) -> PolicyProfile:
    key = _slug(name)
    if key == "strict_local":
        return PolicyProfile(
            id="strict_local",
            title="Strict local-only",
            allow_remote_mcp=False,
            allow_a2a=False,
            allow_public_cloud_models=False,
            allow_source_updates=False,
            require_manifest_signatures=True,
            required_approval="explicit",
            allowed_update_channels=("stable",),
            trusted_signers=("openai-local-release",),
        )
    if key == "reviewed_remote":
        return PolicyProfile(
            id="reviewed_remote",
            title="Reviewed remote interoperability",
            allow_remote_mcp=True,
            allow_a2a=True,
            allow_public_cloud_models=False,
            allow_source_updates=True,
            require_manifest_signatures=True,
            required_approval="reviewed",
            allowed_update_channels=("stable", "candidate"),
            trusted_signers=("openai-local-release", "org-review-key"),
        )
    if key == "enterprise_fleet":
        return PolicyProfile(
            id="enterprise_fleet",
            title="Enterprise fleet",
            allow_remote_mcp=True,
            allow_a2a=True,
            allow_public_cloud_models=True,
            allow_source_updates=True,
            require_manifest_signatures=True,
            required_approval="enterprise",
            allowed_update_channels=("stable", "lts", "candidate"),
            trusted_signers=("openai-local-release", "org-review-key", "fleet-release-key"),
        )
    raise ValueError("unknown built-in policy profile")


@dataclass(frozen=True)
class FleetProfile:
    organization: str
    policy_profile_id: str
    managed_projects: tuple[str, ...]
    allowed_models: tuple[str, ...]
    allow_remote_support_bundle: bool
    update_channel: str

    def overlay(self, policy: PolicyProfile) -> PolicyProfile:
        if self.update_channel not in policy.allowed_update_channels:
            raise ValueError("fleet profile update channel is not allowed by base policy")
        return PolicyProfile(
            id=policy.id,
            title=policy.title,
            allow_remote_mcp=policy.allow_remote_mcp,
            allow_a2a=policy.allow_a2a,
            allow_public_cloud_models=policy.allow_public_cloud_models,
            allow_source_updates=policy.allow_source_updates,
            require_manifest_signatures=policy.require_manifest_signatures,
            required_approval=policy.required_approval,
            allowed_update_channels=policy.allowed_update_channels,
            trusted_signers=policy.trusted_signers,
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "organization": self.organization,
            "policyProfileId": self.policy_profile_id,
            "managedProjects": list(self.managed_projects),
            "allowedModels": list(self.allowed_models),
            "allowRemoteSupportBundle": self.allow_remote_support_bundle,
            "updateChannel": self.update_channel,
        }


@dataclass(frozen=True)
class McpToolDescriptor:
    kind: str
    name: str
    description: str

    def __post_init__(self) -> None:
        if self.kind not in MCP_KINDS:
            raise ValueError("MCP descriptor kind is invalid")


@dataclass(frozen=True)
class McpServerManifest:
    schema_version: str
    id: str
    label: str
    transport: str
    executable: str | None
    endpoint: str | None
    sandbox_required: bool
    allowed_roots: tuple[str, ...]
    tools: tuple[str, ...]
    resources: tuple[str, ...]
    prompts: tuple[str, ...]
    provenance: tuple[str, ...]
    package_sha256: str | None

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": self.schema_version,
            "id": self.id,
            "label": self.label,
            "transport": self.transport,
            "executable": self.executable,
            "endpoint": self.endpoint,
            "sandboxRequired": self.sandbox_required,
            "allowedRoots": list(self.allowed_roots),
            "tools": list(self.tools),
            "resources": list(self.resources),
            "prompts": list(self.prompts),
            "provenance": list(self.provenance),
            "packageSha256": self.package_sha256,
        }

    @classmethod
    def create(
        cls,
        *,
        identifier: str,
        label: str,
        transport: str,
        executable: str | None = None,
        endpoint: str | None = None,
        sandbox_required: bool = True,
        allowed_roots: list[str] | None = None,
        tools: list[str] | None = None,
        resources: list[str] | None = None,
        prompts: list[str] | None = None,
        provenance: list[str] | None = None,
        package_sha256: str | None = None,
    ) -> "McpServerManifest":
        normalized_transport = _slug(transport)
        if normalized_transport not in MCP_TRANSPORTS:
            raise ValueError("MCP transport is invalid")
        if normalized_transport == "local_stdio" and not executable:
            raise ValueError("local MCP servers require an executable")
        if normalized_transport == "remote_https":
            if not endpoint or not endpoint.startswith("https://"):
                raise ValueError("remote MCP servers require an https endpoint")
        roots = tuple(sorted({_normalize_relpath(item) for item in (allowed_roots or [])}))
        tool_items = tuple(sorted({_string(item, "tool") for item in (tools or [])}))
        resource_items = tuple(sorted({_string(item, "resource") for item in (resources or [])}))
        prompt_items = tuple(sorted({_string(item, "prompt") for item in (prompts or [])}))
        overlap = (set(tool_items) & set(resource_items)) | (set(tool_items) & set(prompt_items)) | (set(resource_items) & set(prompt_items))
        if overlap:
            raise ValueError("MCP tools, resources, and prompts must remain distinct")
        return cls(
            schema_version=SCHEMA_VERSION,
            id=_slug(identifier),
            label=_string(label, "label"),
            transport=normalized_transport,
            executable=str(Path(executable).as_posix()) if executable else None,
            endpoint=_string(endpoint, "endpoint") if endpoint else None,
            sandbox_required=bool(sandbox_required),
            allowed_roots=roots,
            tools=tool_items,
            resources=resource_items,
            prompts=prompt_items,
            provenance=tuple(sorted({_string(item, "provenance") for item in (provenance or [])})),
            package_sha256=package_sha256,
        )


@dataclass(frozen=True)
class McpSessionReport:
    server_id: str
    initialized: bool
    roots_authorized: tuple[str, ...]
    tools: tuple[str, ...]
    resources: tuple[str, ...]
    prompts: tuple[str, ...]
    progress_supported: bool
    cancellation_supported: bool
    sandbox_launch_required: bool

    def to_json(self) -> dict[str, Any]:
        return {
            "serverId": self.server_id,
            "initialized": self.initialized,
            "rootsAuthorized": list(self.roots_authorized),
            "tools": list(self.tools),
            "resources": list(self.resources),
            "prompts": list(self.prompts),
            "progressSupported": self.progress_supported,
            "cancellationSupported": self.cancellation_supported,
            "sandboxLaunchRequired": self.sandbox_launch_required,
        }


class McpLifecycleController:
    def __init__(self, *, policy: PolicyProfile) -> None:
        self.policy = policy

    def negotiate(
        self,
        manifest: McpServerManifest,
        *,
        initialize_result: Mapping[str, Any],
        requested_roots: list[str],
    ) -> McpSessionReport:
        if manifest.transport == "remote_https" and not self.policy.allow_remote_mcp:
            raise ValueError("remote MCP is blocked by policy")
        if manifest.transport == "local_stdio" and manifest.sandbox_required is False:
            raise ValueError("local MCP servers must remain sandboxed")
        version = _string(initialize_result.get("protocolVersion"), "protocolVersion")
        if not version:
            raise ValueError("MCP initialize result requires a protocol version")
        capabilities = initialize_result.get("capabilities")
        if not isinstance(capabilities, dict):
            raise ValueError("MCP initialize result requires capabilities")
        server_info = initialize_result.get("serverInfo")
        if not isinstance(server_info, dict) or not server_info.get("name"):
            raise ValueError("MCP initialize result requires server identity")
        normalized_roots = tuple(sorted({_normalize_relpath(item) for item in requested_roots}))
        if any(root not in manifest.allowed_roots for root in normalized_roots):
            raise ValueError("requested MCP root exceeds manifest allowlist")
        return McpSessionReport(
            server_id=manifest.id,
            initialized=True,
            roots_authorized=normalized_roots,
            tools=manifest.tools,
            resources=manifest.resources,
            prompts=manifest.prompts,
            progress_supported=bool(capabilities.get("progress")),
            cancellation_supported=bool(capabilities.get("cancellation")),
            sandbox_launch_required=manifest.transport == "local_stdio" and manifest.sandbox_required,
        )

    def authorize_operation(self, manifest: McpServerManifest, *, kind: str, name: str) -> str:
        category = _slug(kind)
        target = _string(name, "name")
        if category == "tool":
            if target not in manifest.tools:
                raise ValueError("MCP tool is not allowlisted")
        elif category == "resource":
            if target not in manifest.resources:
                raise ValueError("MCP resource is not allowlisted")
        elif category == "prompt":
            if target not in manifest.prompts:
                raise ValueError("MCP prompt is not allowlisted")
        else:
            raise ValueError("MCP kind is invalid")
        return f"authorized {category} {target}"


@dataclass(frozen=True)
class A2ATaskContract:
    schema_version: str
    contract_id: str
    objective: str
    remote_agent_id: str
    allowed_capabilities: tuple[str, ...]
    input_artifacts: tuple[str, ...]
    output_artifacts: tuple[str, ...]
    maximum_turns: int
    maximum_bytes: int
    data_boundary: str
    approval_policy: str

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": self.schema_version,
            "contractId": self.contract_id,
            "objective": self.objective,
            "remoteAgentId": self.remote_agent_id,
            "allowedCapabilities": list(self.allowed_capabilities),
            "inputArtifacts": list(self.input_artifacts),
            "outputArtifacts": list(self.output_artifacts),
            "maximumTurns": self.maximum_turns,
            "maximumBytes": self.maximum_bytes,
            "dataBoundary": self.data_boundary,
            "approvalPolicy": self.approval_policy,
        }


class A2ADelegationController:
    def __init__(self, *, policy: PolicyProfile) -> None:
        self.policy = policy

    def build_contract(
        self,
        *,
        objective: str,
        remote_agent_id: str,
        allowed_capabilities: list[str],
        input_artifacts: list[str],
        output_artifacts: list[str],
        maximum_turns: int,
        maximum_bytes: int,
        data_boundary: str,
        approval_policy: str,
    ) -> A2ATaskContract:
        if not self.policy.allow_a2a:
            raise ValueError("A2A is blocked by policy")
        if data_boundary not in DATA_BOUNDARIES:
            raise ValueError("A2A data boundary is invalid")
        if data_boundary == "public_cloud" and not self.policy.allow_public_cloud_models:
            raise ValueError("A2A cannot widen the data boundary")
        if approval_policy not in APPROVAL_LEVELS:
            raise ValueError("A2A approval policy is invalid")
        capabilities = tuple(sorted({_string(item, "capability") for item in allowed_capabilities}))
        if not capabilities:
            raise ValueError("A2A capabilities must not be empty")
        if any(capability not in A2A_CAPABILITIES for capability in capabilities):
            raise ValueError("A2A contract capability is unsupported")
        inputs = tuple(sorted({_string(item, "input_artifact") for item in input_artifacts}))
        outputs = tuple(sorted({_string(item, "output_artifact") for item in output_artifacts}))
        if any(value.startswith("project:") or value.startswith("path:") for value in (*inputs, *outputs)):
            raise ValueError("A2A contracts may not grant unrestricted project access")
        return A2ATaskContract(
            schema_version=SCHEMA_VERSION,
            contract_id=f"a2a-{sha256_text(canonical_json([objective, remote_agent_id, capabilities, inputs, outputs]))[:12]}",
            objective=_string(objective, "objective"),
            remote_agent_id=_slug(remote_agent_id),
            allowed_capabilities=capabilities,
            input_artifacts=inputs,
            output_artifacts=outputs,
            maximum_turns=max(1, int(maximum_turns)),
            maximum_bytes=max(1024, int(maximum_bytes)),
            data_boundary=data_boundary,
            approval_policy=approval_policy,
        )

    def validate_response(self, contract: A2ATaskContract, response: Mapping[str, Any]) -> str:
        artifacts = _string_list(response.get("artifacts", []), "response.artifacts")
        used_capabilities = _string_list(response.get("usedCapabilities", []), "response.usedCapabilities")
        if any(item not in contract.output_artifacts for item in artifacts):
            raise ValueError("A2A response produced undeclared artifacts")
        if any(item not in contract.allowed_capabilities for item in used_capabilities):
            raise ValueError("A2A response exceeded the delegated capability set")
        payload_bytes = len(canonical_json(response).encode("utf-8"))
        if payload_bytes > contract.maximum_bytes:
            raise ValueError("A2A response exceeded the maximum payload size")
        turns = int(response.get("turns", 0))
        if turns > contract.maximum_turns:
            raise ValueError("A2A response exceeded the maximum turns")
        return "A2A response remained within the bounded task contract"


@dataclass(frozen=True)
class AuditRecord:
    index: int
    event_type: str
    entity_id: str
    payload: dict[str, Any]
    created_at: str
    previous_hash: str
    record_hash: str
    signature: str

    def to_json(self) -> dict[str, Any]:
        return {
            "index": self.index,
            "eventType": self.event_type,
            "entityId": self.entity_id,
            "payload": self.payload,
            "createdAt": self.created_at,
            "previousHash": self.previous_hash,
            "recordHash": self.record_hash,
            "signature": self.signature,
        }


class AuditChain:
    def __init__(self, *, signer_id: str, secret: str) -> None:
        self.signer_id = signer_id
        self.secret = secret
        self.records: list[AuditRecord] = []

    def append(self, event_type: str, entity_id: str, payload: Mapping[str, Any]) -> AuditRecord:
        previous_hash = self.records[-1].record_hash if self.records else "0" * 64
        created_at = utc_now()
        canonical = {
            "index": len(self.records) + 1,
            "eventType": _string(event_type, "event_type"),
            "entityId": _string(entity_id, "entity_id"),
            "payload": json.loads(canonical_json(payload)),
            "createdAt": created_at,
            "previousHash": previous_hash,
        }
        record_hash = sha256_text(canonical_json(canonical))
        signature = sign_payload(canonical, signer_id=self.signer_id, secret=self.secret, signed_at=created_at).signature
        record = AuditRecord(
            index=canonical["index"],
            event_type=canonical["eventType"],
            entity_id=canonical["entityId"],
            payload=canonical["payload"],
            created_at=created_at,
            previous_hash=previous_hash,
            record_hash=record_hash,
            signature=signature,
        )
        self.records.append(record)
        return record

    def verify(self) -> tuple[bool, str]:
        previous_hash = "0" * 64
        for record in self.records:
            canonical = {
                "index": record.index,
                "eventType": record.event_type,
                "entityId": record.entity_id,
                "payload": record.payload,
                "createdAt": record.created_at,
                "previousHash": record.previous_hash,
            }
            if record.previous_hash != previous_hash:
                return False, f"audit_previous_hash_mismatch_at_{record.index}"
            if sha256_text(canonical_json(canonical)) != record.record_hash:
                return False, f"audit_record_hash_mismatch_at_{record.index}"
            expected_signature = sign_payload(canonical, signer_id=self.signer_id, secret=self.secret, signed_at=record.created_at).signature
            if not hmac.compare_digest(expected_signature, record.signature):
                return False, f"audit_signature_mismatch_at_{record.index}"
            previous_hash = record.record_hash
        return True, "audit_chain_verified"


@dataclass(frozen=True)
class SupportCompatibilityPolicy:
    schema_version: str
    supported_upgrade_from: tuple[str, ...]
    supported_rollback_to: tuple[str, ...]
    supported_channels: tuple[str, ...]
    support_phase: str

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": self.schema_version,
            "supportedUpgradeFrom": list(self.supported_upgrade_from),
            "supportedRollbackTo": list(self.supported_rollback_to),
            "supportedChannels": list(self.supported_channels),
            "supportPhase": self.support_phase,
        }


@dataclass(frozen=True)
class UpdateManifest:
    schema_version: str
    release_version: str
    channel: str
    package_root: str
    archive_name: str
    archive_sha256: str
    parent_version: str
    rollback_version: str
    support_policy: SupportCompatibilityPolicy
    signature: SignatureEnvelope

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": self.schema_version,
            "releaseVersion": self.release_version,
            "channel": self.channel,
            "packageRoot": self.package_root,
            "archiveName": self.archive_name,
            "archiveSha256": self.archive_sha256,
            "parentVersion": self.parent_version,
            "rollbackVersion": self.rollback_version,
            "supportPolicy": self.support_policy.to_json(),
            "signature": self.signature.to_json(),
        }


class UpdatePolicyVerifier:
    def __init__(self, *, policy: PolicyProfile, trusted_signers: Mapping[str, str]) -> None:
        self.policy = policy
        self.trusted_signers = trusted_signers

    def create_manifest(
        self,
        *,
        release_version: str,
        channel: str,
        package_root: str,
        archive_name: str,
        archive_sha256: str,
        parent_version: str,
        rollback_version: str,
        support_policy: SupportCompatibilityPolicy,
        signer_id: str,
        secret: str,
        signed_at: str | None = None,
    ) -> UpdateManifest:
        payload = {
            "schemaVersion": SCHEMA_VERSION,
            "releaseVersion": _string(release_version, "release_version"),
            "channel": _slug(channel),
            "packageRoot": _string(package_root, "package_root"),
            "archiveName": _string(archive_name, "archive_name"),
            "archiveSha256": _string(archive_sha256, "archive_sha256"),
            "parentVersion": _string(parent_version, "parent_version"),
            "rollbackVersion": _string(rollback_version, "rollback_version"),
            "supportPolicy": support_policy.to_json(),
        }
        signature = sign_payload(payload, signer_id=signer_id, secret=secret, signed_at=signed_at)
        return UpdateManifest(
            schema_version=SCHEMA_VERSION,
            release_version=payload["releaseVersion"],
            channel=payload["channel"],
            package_root=payload["packageRoot"],
            archive_name=payload["archiveName"],
            archive_sha256=payload["archiveSha256"],
            parent_version=payload["parentVersion"],
            rollback_version=payload["rollbackVersion"],
            support_policy=support_policy,
            signature=signature,
        )

    def verify(self, manifest: UpdateManifest, *, current_version: str, installer_present: bool) -> str:
        if not self.policy.allow_source_updates:
            raise ValueError("source updates are blocked by policy")
        if manifest.channel not in self.policy.allowed_update_channels:
            raise ValueError("update channel is not allowed by policy")
        if self.policy.require_manifest_signatures:
            payload = {
                "schemaVersion": manifest.schema_version,
                "releaseVersion": manifest.release_version,
                "channel": manifest.channel,
                "packageRoot": manifest.package_root,
                "archiveName": manifest.archive_name,
                "archiveSha256": manifest.archive_sha256,
                "parentVersion": manifest.parent_version,
                "rollbackVersion": manifest.rollback_version,
                "supportPolicy": manifest.support_policy.to_json(),
            }
            verified, reason = verify_signature(payload, manifest.signature, secret_lookup=self.trusted_signers)
            if not verified:
                raise ValueError(reason)
        if current_version not in manifest.support_policy.supported_upgrade_from:
            raise ValueError("current version is outside the supported upgrade set")
        if manifest.rollback_version not in manifest.support_policy.supported_rollback_to:
            raise ValueError("rollback target is outside the supported rollback set")
        if not installer_present:
            raise ValueError("native installer payload is unavailable in this source-only environment")
        return "authenticated update and rollback policy verified"
