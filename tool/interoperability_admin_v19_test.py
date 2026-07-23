#!/usr/bin/env python3
"""Executable v1.9 interoperability, administration, and release gates."""
from __future__ import annotations

import argparse
import dataclasses
import json
import os
from pathlib import Path
import tempfile
import time

import interoperability_admin_v19 as v19


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

def require(condition: bool, detail: str) -> str:
    if not condition:
        raise AssertionError(detail)
    return detail


def case(name: str, fn, results: list[Result]) -> None:
    started = time.monotonic()
    try:
        detail = fn()
        results.append(Result(name, True, detail, duration_ms(started)))
    except Exception as exc:  # noqa: BLE001
        results.append(Result(name, False, f"{type(exc).__name__}: {exc}", duration_ms(started)))


def expect_error(fn, code: str) -> str:
    try:
        fn()
    except Exception as exc:  # noqa: BLE001
        return require(code in str(exc), f"blocked with {code}")
    raise AssertionError(f"expected error containing {code}")


def signed_skill(secret: str = "signing-secret") -> v19.SignedCapabilityManifest:
    manifest = v19.CapabilityManifest.create(
        kind="skill",
        identifier="release.package",
        title="Package release artifacts",
        version=1,
        purpose="Create release notes and assemble verified archive metadata.",
        input_schema="schemas/product_specification.v2.json",
        output_schema="schemas/published_skill.v1.json",
        capabilities=["archive_manifest", "verify_project"],
        data_boundary="local",
        model_requirements=["executor"],
        approval_policy="explicit",
        evaluation_results=["replay:pass", "validator:pass"],
        provenance=["episode:run-123"],
        compatibility=[">=1.8.0", "<2.0.0"],
    )
    return v19.sign_manifest(manifest, signer_id="openai-local-release", secret=secret, signed_at="2026-07-22T00:00:00+00:00")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    results: list[Result] = []

    strict = v19.built_in_policy("strict_local")
    reviewed = v19.built_in_policy("reviewed_remote")
    enterprise = v19.built_in_policy("enterprise_fleet")

    case("Signed capability manifest verifies deterministically", lambda: _manifest_case(), results)
    case("Tampered signed manifest is rejected", lambda: _manifest_tamper_case(), results)
    case("Unsupported signer is rejected", lambda: _manifest_signer_case(), results)
    case("Policy profiles remain deterministic", lambda: _policy_case(strict, reviewed, enterprise), results)
    case("Fleet profile channel must fit policy", lambda: _fleet_case(enterprise), results)
    case("Local MCP manifest requires sandboxed stdio server", lambda: _mcp_local_case(strict), results)
    case("Remote MCP is blocked by strict local policy", lambda: _mcp_remote_block_case(strict), results)
    case("Reviewed policy allows remote MCP manifest negotiation", lambda: _mcp_remote_case(reviewed), results)
    case("MCP namespaces must remain distinct", _mcp_namespace_case, results)
    case("MCP roots are bounded to allowlist", lambda: _mcp_roots_case(reviewed), results)
    case("MCP unauthorized tool is rejected", lambda: _mcp_tool_case(reviewed), results)
    case("A2A contract remains bounded", lambda: _a2a_case(reviewed), results)
    case("A2A cannot grant unrestricted project access", lambda: _a2a_project_access_case(reviewed), results)
    case("A2A cannot exceed task contract", lambda: _a2a_exceed_case(reviewed), results)
    case("Strict local policy blocks A2A", lambda: _a2a_policy_case(strict), results)
    case("Audit chain verifies append-only integrity", _audit_case, results)
    case("Audit chain break is detected", _audit_break_case, results)
    case("Update manifest signatures verify", lambda: _update_manifest_case(reviewed), results)
    case("Unsupported upgrade path is blocked", lambda: _update_upgrade_block_case(reviewed), results)
    case("Unsupported rollback target is blocked", lambda: _update_rollback_block_case(reviewed), results)
    case("Installer absence fails closed", lambda: _update_installer_case(reviewed), results)
    case("Support policy encodes supported channels", _support_policy_case, results)

    payload = {
        "version": v19.VERSION,
        "caseCount": len(results),
        "passedCount": sum(item.passed for item in results),
        "failedCount": sum(not item.passed for item in results),
        "passed": all(item.passed for item in results),
        "results": [dataclasses.asdict(item) for item in results],
    }
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["passed"] else 1


def _manifest_case() -> str:
    signed = signed_skill()
    ok, reason = v19.verify_manifest(signed, secret_lookup={"openai-local-release": "signing-secret"})
    return require(ok and reason == "signature_verified", "signed plugin/skill manifest identity is verifiable")


def _manifest_tamper_case() -> str:
    signed = signed_skill()
    tampered = v19.CapabilityManifest.create(
        kind=signed.manifest.kind,
        identifier=signed.manifest.id,
        title=signed.manifest.title,
        version=signed.manifest.version,
        purpose="Tampered purpose",
        input_schema=signed.manifest.input_schema,
        output_schema=signed.manifest.output_schema,
        capabilities=list(signed.manifest.capabilities),
        data_boundary=signed.manifest.data_boundary,
        model_requirements=list(signed.manifest.model_requirements),
        approval_policy=signed.manifest.approval_policy,
        evaluation_results=list(signed.manifest.evaluation_results),
        provenance=list(signed.manifest.provenance),
        compatibility=list(signed.manifest.compatibility),
    )
    ok, reason = v19.verify_manifest(v19.SignedCapabilityManifest(tampered, signed.signature), secret_lookup={"openai-local-release": "signing-secret"})
    return require(not ok and reason == "payload_sha256_mismatch", "tampered manifest is detected")


def _manifest_signer_case() -> str:
    signed = signed_skill()
    ok, reason = v19.verify_manifest(signed, secret_lookup={})
    return require(not ok and reason == "unknown_signer", "unknown signer is rejected")


def _policy_case(strict: v19.PolicyProfile, reviewed: v19.PolicyProfile, enterprise: v19.PolicyProfile) -> str:
    return require(
        strict.require_manifest_signatures and not strict.allow_a2a and reviewed.allow_a2a and enterprise.allow_public_cloud_models,
        "policy profiles encode strict, reviewed, and enterprise authority levels",
    )


def _fleet_case(policy: v19.PolicyProfile) -> str:
    fleet = v19.FleetProfile(
        organization="Example Org",
        policy_profile_id=policy.id,
        managed_projects=("project-a", "project-b"),
        allowed_models=("ollama/phi4-mini:latest",),
        allow_remote_support_bundle=False,
        update_channel="lts",
    )
    overlay = fleet.overlay(policy)
    return require(overlay.id == policy.id and fleet.update_channel == "lts", "fleet profile remains inside the base policy")


def _mcp_local_case(policy: v19.PolicyProfile) -> str:
    manifest = v19.McpServerManifest.create(
        identifier="local.code-audit",
        label="Local audit server",
        transport="local_stdio",
        executable="/usr/bin/python3",
        sandbox_required=True,
        allowed_roots=["workspace", "docs"],
        tools=["list_files"],
        resources=["workspace-index"],
        prompts=["explain-report"],
        provenance=["sha256:abc"],
    )
    report = v19.McpLifecycleController(policy=policy).negotiate(
        manifest,
        initialize_result={"protocolVersion": "2024-11-05", "capabilities": {"progress": True, "cancellation": True}, "serverInfo": {"name": "local-audit", "version": "1.0.0"}},
        requested_roots=["workspace"],
    )
    return require(report.initialized and report.sandbox_launch_required, "local MCP lifecycle is negotiated and sandbox-required")


def _mcp_remote_block_case(policy: v19.PolicyProfile) -> str:
    manifest = v19.McpServerManifest.create(
        identifier="remote.docs",
        label="Remote docs",
        transport="remote_https",
        endpoint="https://example.invalid/mcp",
        sandbox_required=True,
        allowed_roots=["docs"],
        tools=["fetch_docs"],
        resources=[],
        prompts=[],
        provenance=["registry:remote"],
    )
    return expect_error(
        lambda: v19.McpLifecycleController(policy=policy).negotiate(
            manifest,
            initialize_result={"protocolVersion": "2024-11-05", "capabilities": {}, "serverInfo": {"name": "remote", "version": "1"}},
            requested_roots=["docs"],
        ),
        "remote MCP is blocked by policy",
    )


def _mcp_remote_case(policy: v19.PolicyProfile) -> str:
    manifest = v19.McpServerManifest.create(
        identifier="remote.docs",
        label="Remote docs",
        transport="remote_https",
        endpoint="https://example.invalid/mcp",
        sandbox_required=True,
        allowed_roots=["docs"],
        tools=["fetch_docs"],
        resources=["doc-index"],
        prompts=["summarize-docs"],
        provenance=["registry:remote"],
    )
    report = v19.McpLifecycleController(policy=policy).negotiate(
        manifest,
        initialize_result={"protocolVersion": "2024-11-05", "capabilities": {"progress": True}, "serverInfo": {"name": "remote", "version": "1"}},
        requested_roots=["docs"],
    )
    return require(report.initialized and report.roots_authorized == ("docs",), "reviewed policy allows bounded remote MCP negotiation")


def _mcp_namespace_case() -> str:
    return expect_error(
        lambda: v19.McpServerManifest.create(
            identifier="bad",
            label="Bad",
            transport="local_stdio",
            executable="/usr/bin/python3",
            allowed_roots=["workspace"],
            tools=["duplicate"],
            resources=["duplicate"],
            prompts=[],
            provenance=["sha256:abc"],
        ),
        "must remain distinct",
    )


def _mcp_roots_case(policy: v19.PolicyProfile) -> str:
    manifest = v19.McpServerManifest.create(
        identifier="local.rooted",
        label="Rooted",
        transport="local_stdio",
        executable="/usr/bin/python3",
        sandbox_required=True,
        allowed_roots=["workspace"],
        tools=["list_files"],
        resources=[],
        prompts=[],
        provenance=["sha256:abc"],
    )
    return expect_error(
        lambda: v19.McpLifecycleController(policy=policy).negotiate(
            manifest,
            initialize_result={"protocolVersion": "2024-11-05", "capabilities": {}, "serverInfo": {"name": "rooted", "version": "1"}},
            requested_roots=["workspace", "docs"],
        ),
        "exceeds manifest allowlist",
    )


def _mcp_tool_case(policy: v19.PolicyProfile) -> str:
    manifest = v19.McpServerManifest.create(
        identifier="local.authz",
        label="AuthZ",
        transport="local_stdio",
        executable="/usr/bin/python3",
        sandbox_required=True,
        allowed_roots=["workspace"],
        tools=["safe_tool"],
        resources=[],
        prompts=[],
        provenance=["sha256:abc"],
    )
    return expect_error(lambda: v19.McpLifecycleController(policy=policy).authorize_operation(manifest, kind="tool", name="unsafe_tool"), "not allowlisted")


def _a2a_case(policy: v19.PolicyProfile) -> str:
    controller = v19.A2ADelegationController(policy=policy)
    contract = controller.build_contract(
        objective="Review the artifact validation report",
        remote_agent_id="validator.agent",
        allowed_capabilities=["verify_artifact", "summarize_trace"],
        input_artifacts=["object:sha256:abcd", "report:validation"],
        output_artifacts=["report:reviewed"],
        maximum_turns=6,
        maximum_bytes=16384,
        data_boundary="private_remote",
        approval_policy="reviewed",
    )
    detail = controller.validate_response(contract, {"artifacts": ["report:reviewed"], "usedCapabilities": ["verify_artifact"], "turns": 3})
    return require("bounded task contract" in detail, "A2A response remains inside the delegated contract")


def _a2a_project_access_case(policy: v19.PolicyProfile) -> str:
    controller = v19.A2ADelegationController(policy=policy)
    return expect_error(
        lambda: controller.build_contract(
            objective="Review code",
            remote_agent_id="validator.agent",
            allowed_capabilities=["review_code"],
            input_artifacts=["project:/entire-workspace"],
            output_artifacts=["report:reviewed"],
            maximum_turns=3,
            maximum_bytes=8192,
            data_boundary="private_remote",
            approval_policy="reviewed",
        ),
        "unrestricted project access",
    )


def _a2a_exceed_case(policy: v19.PolicyProfile) -> str:
    controller = v19.A2ADelegationController(policy=policy)
    contract = controller.build_contract(
        objective="Summarize the release trace",
        remote_agent_id="validator.agent",
        allowed_capabilities=["summarize_trace"],
        input_artifacts=["report:trace"],
        output_artifacts=["report:summary"],
        maximum_turns=2,
        maximum_bytes=1024,
        data_boundary="private_remote",
        approval_policy="reviewed",
    )
    return expect_error(
        lambda: controller.validate_response(contract, {"artifacts": ["report:other"], "usedCapabilities": ["summarize_trace"], "turns": 1}),
        "undeclared artifacts",
    )


def _a2a_policy_case(policy: v19.PolicyProfile) -> str:
    controller = v19.A2ADelegationController(policy=policy)
    return expect_error(
        lambda: controller.build_contract(
            objective="Review artifact",
            remote_agent_id="validator.agent",
            allowed_capabilities=["verify_artifact"],
            input_artifacts=["report:validation"],
            output_artifacts=["report:reviewed"],
            maximum_turns=3,
            maximum_bytes=8192,
            data_boundary="local",
            approval_policy="explicit",
        ),
        "A2A is blocked by policy",
    )


def _audit_case() -> str:
    chain = v19.AuditChain(signer_id="org-review-key", secret="audit-secret")
    chain.append("skill.published", "skill-1", {"manifest": "abc"})
    chain.append("update.verified", "release-190", {"archive": "archive.zip"})
    ok, reason = chain.verify()
    return require(ok and reason == "audit_chain_verified", "audit chain verifies append-only integrity")


def _audit_break_case() -> str:
    chain = v19.AuditChain(signer_id="org-review-key", secret="audit-secret")
    first = chain.append("skill.published", "skill-1", {"manifest": "abc"})
    second = chain.append("update.verified", "release-190", {"archive": "archive.zip"})
    chain.records[1] = dataclasses.replace(second, previous_hash=first.previous_hash)
    ok, reason = chain.verify()
    return require(not ok and reason.startswith("audit_previous_hash_mismatch"), "audit-chain break is detected")


def _support_policy_case() -> str:
    support = v19.SupportCompatibilityPolicy(
        schema_version=v19.SCHEMA_VERSION,
        supported_upgrade_from=("1.8.0+180", "1.8.1+181"),
        supported_rollback_to=("1.8.0+180",),
        supported_channels=("stable", "candidate"),
        support_phase="active",
    )
    payload = support.to_json()
    return require(payload["supportedChannels"] == ["stable", "candidate"], "support policy encodes supported channels and compatibility")


def _update_manifest_case(policy: v19.PolicyProfile) -> str:
    support = v19.SupportCompatibilityPolicy(
        schema_version=v19.SCHEMA_VERSION,
        supported_upgrade_from=("1.8.0+180",),
        supported_rollback_to=("1.8.0+180",),
        supported_channels=("stable",),
        support_phase="active",
    )
    verifier = v19.UpdatePolicyVerifier(policy=policy, trusted_signers={"org-review-key": "release-secret"})
    manifest = verifier.create_manifest(
        release_version="1.9.0+190",
        channel="stable",
        package_root="Kristin_Local_Agent_v1.9.0_build190_interoperability_admin_release_ops",
        archive_name="kristin-v190.zip",
        archive_sha256="a" * 64,
        parent_version="1.8.0+180",
        rollback_version="1.8.0+180",
        support_policy=support,
        signer_id="org-review-key",
        secret="release-secret",
        signed_at="2026-07-22T00:00:00+00:00",
    )
    return require(
        verifier.verify(manifest, current_version="1.8.0+180", installer_present=True) == "authenticated update and rollback policy verified",
        "authenticated update manifest signature and rollback policy verify",
    )


def _update_upgrade_block_case(policy: v19.PolicyProfile) -> str:
    support = v19.SupportCompatibilityPolicy(
        schema_version=v19.SCHEMA_VERSION,
        supported_upgrade_from=("1.7.0+170",),
        supported_rollback_to=("1.8.0+180",),
        supported_channels=("stable",),
        support_phase="active",
    )
    verifier = v19.UpdatePolicyVerifier(policy=policy, trusted_signers={"org-review-key": "release-secret"})
    manifest = verifier.create_manifest(
        release_version="1.9.0+190",
        channel="stable",
        package_root="pkg",
        archive_name="archive.zip",
        archive_sha256="a" * 64,
        parent_version="1.8.0+180",
        rollback_version="1.8.0+180",
        support_policy=support,
        signer_id="org-review-key",
        secret="release-secret",
        signed_at="2026-07-22T00:00:00+00:00",
    )
    return expect_error(lambda: verifier.verify(manifest, current_version="1.8.0+180", installer_present=True), "supported upgrade set")


def _update_rollback_block_case(policy: v19.PolicyProfile) -> str:
    support = v19.SupportCompatibilityPolicy(
        schema_version=v19.SCHEMA_VERSION,
        supported_upgrade_from=("1.8.0+180",),
        supported_rollback_to=("1.7.0+170",),
        supported_channels=("stable",),
        support_phase="active",
    )
    verifier = v19.UpdatePolicyVerifier(policy=policy, trusted_signers={"org-review-key": "release-secret"})
    manifest = verifier.create_manifest(
        release_version="1.9.0+190",
        channel="stable",
        package_root="pkg",
        archive_name="archive.zip",
        archive_sha256="a" * 64,
        parent_version="1.8.0+180",
        rollback_version="1.8.0+180",
        support_policy=support,
        signer_id="org-review-key",
        secret="release-secret",
        signed_at="2026-07-22T00:00:00+00:00",
    )
    return expect_error(lambda: verifier.verify(manifest, current_version="1.8.0+180", installer_present=True), "supported rollback set")


def _update_installer_case(policy: v19.PolicyProfile) -> str:
    support = v19.SupportCompatibilityPolicy(
        schema_version=v19.SCHEMA_VERSION,
        supported_upgrade_from=("1.8.0+180",),
        supported_rollback_to=("1.8.0+180",),
        supported_channels=("stable",),
        support_phase="active",
    )
    verifier = v19.UpdatePolicyVerifier(policy=policy, trusted_signers={"org-review-key": "release-secret"})
    manifest = verifier.create_manifest(
        release_version="1.9.0+190",
        channel="stable",
        package_root="pkg",
        archive_name="archive.zip",
        archive_sha256="a" * 64,
        parent_version="1.8.0+180",
        rollback_version="1.8.0+180",
        support_policy=support,
        signer_id="org-review-key",
        secret="release-secret",
        signed_at="2026-07-22T00:00:00+00:00",
    )
    return expect_error(lambda: verifier.verify(manifest, current_version="1.8.0+180", installer_present=False), "source-only environment")


if __name__ == "__main__":
    raise SystemExit(main())
