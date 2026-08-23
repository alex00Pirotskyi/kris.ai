#!/usr/bin/env python3
"""Create and independently verify a deterministic clean Kristin source ZIP."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import zipfile

from source_tree_policy import is_generated_path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.9.0+190"
PACKAGE_ROOT = "Kristin_Local_Agent_v1.9.0_build190_interoperability_admin_release_ops"
DEFAULT_ARCHIVE = "Kristin_Local_Agent_v1.9.0_build190_interoperability_admin_release_ops.zip"
FIXED_TIME = (2026, 7, 23, 0, 0, 0)
EXCLUDED_DIRS = {
    ".git", ".dart_tool", "build", "node_modules", ".idea", ".vscode",
    "archive", "dist", "reports", "__pycache__",
}
EXCLUDED_NAMES = {
    ".DS_Store", "Thumbs.db", "SOURCE_MANIFEST.sha256", "RELEASE.json",
    "PATCH_MANIFEST.sha256", "PATCH_RELEASE.json",
    "APPLY_AND_RUN_V070.cmd", "APPLY_V070.cmd",
    "UPGRADE_EXISTING_PROJECT.cmd", "UPGRADE_EXISTING_PROJECT.sh",
    "PATCH_README_V070.md", "package_in_place_patch.py",
}
EXCLUDED_SUFFIXES = {".log", ".tmp", ".bak", ".swp", ".pyc", ".exit", ".zip"}
SECRET_NAMES = {".env", "credentials.json", "service-account.json", "secrets.json"}
RELEASE_WHITELIST = {
    "validation_report.json",
    "VALIDATION_REPORT.md",
    "SBOM.cdx.json",
    "SECRET_SCAN.json",
    "DEEP_TEST_BASELINE_V180.md",
}

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_relative(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or "\\" in name or not path.parts:
        raise RuntimeError(f"unsafe archive path: {name}")
    return path


def allowed(path: Path) -> bool:
    relative = path.relative_to(ROOT)
    if is_generated_path(relative) or any(
        part in EXCLUDED_DIRS for part in relative.parts
    ):
        return False
    if relative.parts and relative.parts[0] == "release":
        if len(relative.parts) != 2 or path.name not in RELEASE_WHITELIST:
            return False
    if path.name in EXCLUDED_NAMES or path.name.lower() in SECRET_NAMES:
        return False
    if path.suffix.lower() in EXCLUDED_SUFFIXES:
        return False
    if path.is_symlink():
        raise RuntimeError(f"release refuses symlink: {relative}")
    return path.is_file()


def source_payloads() -> dict[str, bytes]:
    payloads: dict[str, bytes] = {}
    for path in sorted(ROOT.rglob("*"), key=lambda item: item.relative_to(ROOT).as_posix()):
        if allowed(path):
            relative = path.relative_to(ROOT).as_posix()
            safe_relative(relative)
            payloads[relative] = path.read_bytes()
    return payloads


def sdk_status(report: dict[str, object]) -> dict[str, str | None]:
    values: dict[str, str | None] = {
        "dart_format": None,
        "flutter_pub_get": None,
        "flutter_analyze": None,
        "flutter_test": None,
        "windows_build": None,
    }
    mapping = {
        "dart format": "dart_format",
        "flutter pub get": "flutter_pub_get",
        "flutter analyze": "flutter_analyze",
        "flutter test": "flutter_test",
    }
    for raw in report.get("checks", []):
        if not isinstance(raw, dict):
            continue
        key = mapping.get(str(raw.get("name")))
        if key:
            values[key] = str(raw.get("status"))
    return values


def release_metadata(report: dict[str, object]) -> dict[str, object]:
    compiled = bool(report.get("compiled_release_validated"))
    source_passed = bool(report.get("source_gate_passed"))
    return {
        "product": "Kristin Local Agent",
        "version": VERSION,
        "release_channel": "preview",
        "classification": "compiled-release" if compiled else "source-release",
        "source_gate_passed": source_passed,
        "compiled_release_validated": compiled,
        "chat_workspace_integrated": True,
        "governed_runtime_preserved": True,
        "project_doctor_and_quick_tests": True,
        "project_manager_workspace": True,
        "project_analyze_test_build_run_stop": True,
        "managed_project_processes": True,
        "project_manager_api": True,
        "project_manager_cli": True,
        "ollama_cold_load_prewarm": True,
        "bounded_ollama_load_retry": True,
        "model_load_cancellation": True,
        "model_load_progress_events": True,
        "configurable_ollama_load_policy": True,
        "separate_load_first_token_and_generation_deadlines": True,
        "human_study_task_normalization": True,
        "contradictory_capability_instruction_replacement": True,
        "non_manual_task_minimum_attempts": 2,
        "capability_aligned_task_compilation": True,
        "artifact_task_mode_promotion": True,
        "implementation_mutation_evidence": True,
        "bounded_mutation_completion_repairs": True,
        "duplicate_deployment_task_deduplication": True,
        "visual_run_graph": True,
        "prompt_studio": True,
        "ai_prompt_generation": True,
        "immutable_prompt_versions": True,
        "adaptive_task_plans": True,
        "task_plan_maximum": 100,
        "immutable_task_plan_revisions": True,
        "selected_task_dependency_compilation": True,
        "safe_in_project_absolute_path_normalization": True,
        "bounded_tool_argument_repair": True,
        "system_test_cli": True,
        "release_test_cli": True,
        "research_snapshot_archive": True,
        "content_addressed_research_archive": True,
        "hybrid_local_retrieval": True,
        "inspectable_knowledge_citations": True,
        "episodic_run_memory": True,
        "safe_automatic_memory_retrieval": True,
        "diagnostic_memory_opt_in": True,
        "agent_action_schema_recovery": True,
        "model_protocol_adapter": True,
        "nested_model_envelope_recovery": True,
        "safe_tool_alias_normalization": True,
        "consecutive_protocol_repairs": True,
        "read_only_protocol_fallback": True,
        "redacted_model_response_preview": True,
        "model_protocol_exhaustion_diagnostics": True,
        "conversational_fast_path": True,
        "auto_mode_greeting_routing": True,
        "conversation_plain_text_fallback": True,
        "knowledge_export": True,
        "knowledge_cli_and_api": True,
        "knowledge_memory_v2": True,
        "content_addressed_object_store": True,
        "memory_admission_quarantine": True,
        "research_freshness_policy": True,
        "skill_candidate_extraction": True,
        "governed_skill_publication": True,
        "file_adapter_registry_v1": True,
        "sandboxed_core_file_adapters": True,
        "generic_binary_file_tools": True,
        "interoperability_admin_release_ops": True,
        "release_operations_v19": True,
        "typed_mcp_lifecycle_manifests": True,
        "bounded_a2a_delegation": True,
        "signed_capability_manifests": True,
        "policy_profiles_and_fleet_overlays": True,
        "append_only_audit_verification": True,
        "support_compatibility_policy": True,
        "authenticated_source_update_policy": True,
        "deep_release_ops_verification": True,
        "local_logs_and_support_diagnostics": True,
        "budget_aware_agent_turns": True,
        "plan_scaled_autonomy_budgets": True,
        "fresh_linked_run_retries": True,
        "model_request_lifecycle_events": True,
        "stagnant_tool_loop_detection": True,
        "duplicate_static_tool_deduplication": True,
        "bounded_agent_loop_recovery": True,
        "deterministic_evidence_baseline_completion": True,
        "sensitive_path_exclusion_for_recovery": True,
        "loop_recovery_diagnostic_summary": True,
        "windows_compile_contract_hotfix": True,
        "project_diagnostics_product_exception_import_hotfix": True,
        "project_manager_compile_regression_gate": True,
        "workstation_analyzer_warning_hotfix": True,
        "formatter_resilient_source_contracts": True,
        "ordered_model_progress_behavioral_test": True,
        "explicit_local_deployment_claim_guard": True,
        "deterministic_flutter_test_concurrency": True,
        "cold_load_test_handshake": True,
        "test_failure_identity_reporting": True,
        "source_only_architecture_validation": True,
        "formatter_independent_source_contracts": True,
        "visible_validation_failure_details": True,
        "bounded_external_path_rebasing": True,
        "virtual_workspace_alias_recovery": True,
        "stale_project_path_recovery": True,
        "root_scoped_read_path_recovery": True,
        "arbitrary_external_writes_blocked": True,
        "path_recovery_diagnostics": True,
        "generated_workstation_state_exclusion": True,
        "shared_source_tree_policy": True,
        "windows_extended_path_prefix_normalization": True,
        "windows_reparse_point_boundary_regression": True,
        "version_control_schema": "kristin.version-control.v1",
        "parent_release_sha256": "eac7469a776c859b9d14ad6133d06093c43327f8f4579633615aa3129cca9bcc",
        "parent_release_version": "1.8.0+180",
        "parent_release_archive": "Kristin_Local_Agent_v1.8.0_build180_knowledge_memory_skills_adapters.zip",
        "workstation_validation_transcript_sha256": "f11139cff61ed1d7c0526e60454600de9831b330bbf2cdeb92e9adb7a4ce538b",
        "path_hygiene_parent_sha256": "81bc8384d545cd6586696ed3b58da315b596de042785ae9918ea4b2b427f18a2",
        "transitive_lineage_contract": True,
        "structured_lineage_validation": True,
        "merged_user_patch_sha256": "80e5044cf47e8f19ec2350a20f22e0b9fc3da464fac142bc67a5d6bc6231e3f3",
        "diagnostic_bundle_sha256": "a2c3570a9910cf99f3f5c26388b6638bf5639796c47009277cfcd64c90dd0f9b",
        "strict_failed_memory_opt_in": True,
        "application_error_terms_do_not_enable_failed_memory": True,
        "task_aware_protocol_normalization": True,
        "task_appropriate_protocol_repair_examples": True,
        "local_only_plan_capability_alignment": True,
        "self_project_mutation_guard": True,
        "memory_and_protocol_diagnostic_sections": True,
        "sdk_environment_compatibility": True,
        "windows_pub_cache_environment": True,
        "sdk_proxy_and_certificate_forwarding": True,
        "single_pass_sdk_validation": True,
        "flutter_no_pub_compile_gates": True,
        "redacted_sdk_command_output": True,
        "all_logs_diagnostic_export": True,
        "diagnostic_cli_export": True,
        "diagnostic_bundle_schema": "kristin.diagnostics.bundle.v2",
        "legacy_v070_migration_compatibility": True,
        "nested_command_vector_recovery": True,
        "project_scoped_git_command_specialization": True,
        "no_op_mutation_detection": True,
        "no_op_write_loop_convergence": True,
        "retry_evidence_carry_forward": True,
        "product_specific_artifact_validation": True,
        "artifact_inspection_before_completion": True,
        "testing_task_rewrite_guard": True,
        "artifact_scope_correction_events": True,
        "least_privilege_design_task_tools": True,
        "selected_project_workspace_setup_rewrite": True,
        "unnecessary_backend_task_rewrite": True,
        "process_argument_project_boundary": True,
        "non_repository_git_evidence": True,
        "execution_convergence_diagnostic_summary": True,
        "execution_reliability_diagnostic_summary": True,
        "lossless_nested_argument_recovery": True,
        "write_content_required": True,
        "machine_readable_tool_argument_schema": True,
        "artifact_mutation_required_state": True,
        "repeated_empty_artifact_inspection_blocked": True,
        "external_read_root_fallback": True,
        "idempotent_desired_state_completion": True,
        "golden_diagnostic_replay_corpus": True,
        "diagnostic_replay_cli": True,
        "markdown_wrapped_path_canonicalization": True,
        "bounded_artifact_mutation_recovery": True,
        "create_only_artifact_recovery": True,
        "hash_guarded_artifact_replacement": True,
        "incomplete_artifact_state_reconstruction": True,
        "automatic_artifact_post_mutation_verification": True,
        "retry_repair_reservation": True,
        "model_history_correction_projection": True,
        "current_diagnostic_bundle_sha256": "69a6b4502607e35b9262d66de9e5be612f0fcc26a867a5242453fc9854d78895",
        "roadmap_source_sha256": "6ae96908eca16a33c2e400ab31d2f8e41a9470f7fae823aa6719e45fbf233623",
        "compact_execution_prompt_context": True,
        "bounded_tool_history_payloads": True,
        "deterministic_execution_temperature": True,
        "reduced_single_action_output_budget": True,
        "typed_agent_decision_protocol": True,
        "agent_decision_schema_version": "1.0.0",
        "tool_registry_schema_version": "2.0.0",
        "canonical_tool_contract_count": 23,
        "generated_tool_contracts": True,
        "provider_adapter_boundary": True,
        "ollama_provider_compatibility": True,
        "openai_compatible_provider_compatibility": True,
        "mcp_provider_compatibility": True,
        "recorded_provider_replay_compatibility": True,
        "pre_dispatch_input_schema_validation": True,
        "post_dispatch_output_schema_validation": True,
        "representative_output_contract_cases": 23,
        "invalid_tool_output_blocked": True,
        "canonical_failure_metadata_preserved": True,
        "typed_retryability_classification": True,
        "strict_undeclared_argument_rejection": True,
        "deterministic_protocol_fuzz_cases": 2000,
        "sqlite_workflow_authority": True,
        "workflow_schema_version": 7,
        "workflow_migration_digest": "966ca51bd07ea48e2349123d4dd8a73dcd8bb4aa177f5fc70c2b62a07738aa29",
        "append_only_run_events": True,
        "transactional_run_projection": True,
        "durable_tool_idempotency": True,
        "durable_run_leases": True,
        "durable_checkpoints": True,
        "durable_task_attempts": True,
        "durable_agent_action_attempts": True,
        "compensation_records": True,
        "legacy_json_migration": True,
        "byte_exact_migration_backups": True,
        "startup_database_rollback": True,
        "workflow_projection_rebuild": True,
        "workflow_retry_taxonomy": True,
        "workflow_kernel_executable_cases": 14,
        "sqlite_package_version": "2.9.4",
        "sqlite_flutter_libraries_version": "0.5.42",
        "prompt_studio_v2": True,
        "product_specification_schema_version": "2.0.0",
        "task_plan_schema_version": "2.0.0",
        "prompt_evaluation_schema_version": "1.0.0",
        "plan_compiler_version": "1.0.0",
        "prompt_studio_contract_digest": "4f65d0e57ee86b58b26223970c8fbfda243256a47689ce83568df88be042500a",
        "deterministic_capability_compiler": True,
        "hierarchical_task_plan_maximum": 100,
        "plan_dry_run_without_side_effects": True,
        "plan_quality_grader": True,
        "prompt_revision_static_evaluation": True,
        "plan_revision_impact_measurement": True,
        "artifact_and_validator_declarations": True,
        "local_only_external_claim_guard": True,
        "sandbox_prerequisite_compilation_guard": True,
        "sandbox_dependent_tasks_fail_closed": True,
        "v1_4_sandbox_implemented": False,
        "v1_4_linux_reference_implemented": True,
        "v1_4_cross_platform_complete": False,
        "linux_namespace_sandbox_worker": True,
        "https_network_broker": True,
        "one_use_secret_broker": True,
        "sandboxed_project_commands": True,
        "sandbox_parent_death_cleanup": True,
        "pid_reuse_safe_process_tree_stop": True,
        "trusted_host_diagnostic_mode": True,
        "sandbox_worker_gate_cases": 8,
        "network_broker_gate_cases": 6,
        "prompt_studio_v2_fixture_cases": 30,
        "task_scale_fixture_counts": [1, 10, 50, 100],
        "prompt_studio_v2_api": True,
        "prompt_studio_v2_cli": True,
        "project_manager_v2": True,
        "project_profile_schema_version": "2.0.0",
        "project_manager_live_sandbox_readiness": True,
        "project_manager_retained_snapshots": True,
        "project_manager_durable_process_records": True,
        "project_manager_complete_tree_stop": True,
        "project_manager_abrupt_parent_death_gate": True,
        "project_manager_artifact_validation": True,
        "project_manager_gate_cases": 16,
        "execution_intelligence_v1": True,
        "role_based_model_router": True,
        "model_role_count": 8,
        "provider_circuit_breakers": True,
        "semantic_progress_ledger": True,
        "deterministic_convergence_controller": True,
        "independent_objective_verifier": True,
        "phase_specific_budgets": True,
        "context_compaction": True,
        "stronger_model_fallback_requires_approval": True,
        "execution_intelligence_gate_cases": 40,
        "criterion_scoped_objective_evidence": True,
        "executor_prose_rejected_as_evidence": True,
        "phase_budgets_enforced_by_coordinator": True,
        "explicit_plan_split_outcome": True,
        "explicit_awaiting_user_outcome": True,
        "approval_gated_model_fallback_outcome": True,
        "source_date": "2026-07-22T00:00:00Z",
        "sdk": sdk_status(report),
        "known_limits": [
            "This package is source-only unless compiled_release_validated is true.",
            "The v1.1 Prompt-to-Task and Project Manager workflow is a product preview; generated prompts, plans, and detected commands require review before execution.",
            "Local-model loading time depends on model size, storage, RAM, and hardware; v1.8 preserves bounded retries, durable recovery, circuit breaking, semantic convergence, Linux sandbox execution, memory admission, freshness-aware citations, and governed file adapters but cannot guarantee that an unavailable or incompatible model will load.",
            "Human recruitment, interviews, surveys, and external user studies are converted into local objective checks and a manual usability checklist; Kristin does not fabricate participant feedback.",
            "Complexity and effort values are relative planning estimates, not elapsed-time commitments.",
            "This cumulative source head backfills the Linux reference sandbox worker, HTTPS network broker, and one-use secret broker, but it does not claim the full cross-platform v1.4.0 exit gate.",
            "Project Manager 2 is implemented as a source-side governed service and CLI; complete native Flutter desktop UX qualification remains unavailable without the Flutter SDK and platform workstations.",
            "The execution-intelligence gates prove deterministic routing, circuit, progress, convergence, verification, budget, and compaction behavior; they do not yet establish a statistically significant live-model success-rate improvement across hardware and model families.",
            "The Prompt Studio 2 compiler blocks process, network, MCP, deployment, and other sandbox-dependent tasks unless sandbox availability is declared or an explicit legacy unsandboxed dry-run override is approved.",
            "The 1-, 10-, 50-, and 100-task release fixtures prove schema validation, compilation, graph ordering, policy checks, and side-effect-free simulation; they do not execute 161 real project mutations.",
            "Prompt evaluation in this release is deterministic static evaluation against user-authored cases; it is not a semantic guarantee of downstream model or artifact quality.",
            "The canonical v2 specification and task-plan documents are compiled and exposed through the runtime, API, and CLI, but full visual Prompt Studio 2 editing surfaces remain a later UI integration step.",
            "On Linux, standard CLI project commands execute inside the namespace sandbox worker when it is available; native Windows and macOS worker backends remain future work.",
            "Sandbox self-tests run in trusted host mode to avoid nested user-namespace false failures; ordinary project commands still go through the worker boundary.",
            "SQLite governs mutable product and run state, and this source head adds a Linux namespace worker plus brokers; Windows and macOS native worker backends remain future work.",
            "Cross-machine database replication and multi-device synchronization are not implemented.",
            "Binary file support provides governed inspection and writing, not universal format conversion.",
            "The research archive stores fetched snapshots and search results, not complete remote websites or databases.",
            "The local semantic score uses deterministic hashed features, not a learned embedding model.",
            "Research DNS validation is not yet pinned through connection establishment.",
            "Knowledge and run-memory exports may contain project-confidential data and require review before sharing.",
            "Model evidence can contain a redacted bounded response preview and must be reviewed before sharing diagnostic exports.",
            "Diagnostic ZIP redaction is defensive, not proof that all confidential context is absent; review every archive before sharing.",
            "Kristin can now block several proven-unproductive recovery transitions, but complex non-convergent work may still require a stronger model or a smaller work item.",
            "Paths that genuinely target another project remain blocked; register and select that directory before asking Kristin to modify it.",
            "Generated Flutter/native state is excluded from source validation and packaging, but native builds still require platform-specific verification.",
            "Native Flutter analysis, tests, and Windows execution remain authoritative on a configured Flutter workstation.",
            "v1.9 adds typed interoperability, audit, and release-governance foundations, but native signed installers and platform update application are still unavailable in this source-only environment.",
        ],
    }


def make_manifest(payloads: dict[str, bytes]) -> bytes:
    return ("\n".join(f"{digest(data)}  {name}" for name, data in sorted(payloads.items())) + "\n").encode("utf-8")


def write_zip(archive: Path, payloads: dict[str, bytes], *, prefix: str) -> None:
    safe_relative(prefix)
    with zipfile.ZipFile(
        archive,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
        strict_timestamps=True,
    ) as zf:
        for relative, data in sorted(payloads.items()):
            safe_relative(relative)
            name = f"{prefix}/{relative}"
            safe_relative(name)
            info = zipfile.ZipInfo(name, FIXED_TIME)
            executable = relative == "kristin" or relative.endswith((".sh", ".py", ".command"))
            info.external_attr = ((0o100755 if executable else 0o100644) & 0xFFFF) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            zf.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def validate_zip(archive: Path, *, prefix: str) -> tuple[int, str]:
    root_prefix = f"{prefix}/"
    with zipfile.ZipFile(archive, "r") as zf:
        bad = zf.testzip()
        if bad:
            raise RuntimeError(f"corrupt ZIP member: {bad}")
        names = zf.namelist()
        if len(names) != len(set(names)):
            raise RuntimeError("duplicate ZIP members")
        if not names or any(not name.startswith(root_prefix) for name in names):
            raise RuntimeError("clean archive must contain exactly one versioned top-level folder")
        for name in names:
            safe_relative(name)
        manifest_member = f"{prefix}/SOURCE_MANIFEST.sha256"
        release_member = f"{prefix}/RELEASE.json"
        if manifest_member not in names or release_member not in names:
            raise RuntimeError("embedded manifest or release metadata missing")

        manifest: dict[str, str] = {}
        for line in zf.read(manifest_member).decode("utf-8").splitlines():
            expected, separator, relative = line.partition("  ")
            if not separator or len(expected) != 64 or not relative:
                raise RuntimeError(f"invalid manifest line: {line!r}")
            safe_relative(relative)
            if relative in manifest:
                raise RuntimeError(f"duplicate manifest entry: {relative}")
            manifest[relative] = expected

        expected = {
            name[len(root_prefix):]
            for name in names
            if name != manifest_member
        }
        if set(manifest) != expected:
            missing = sorted(expected - set(manifest))
            extra = sorted(set(manifest) - expected)
            raise RuntimeError(f"manifest coverage mismatch; missing={missing[:5]} extra={extra[:5]}")
        for relative, expected_hash in manifest.items():
            actual = digest(zf.read(f"{prefix}/{relative}"))
            if actual != expected_hash:
                raise RuntimeError(f"manifest hash mismatch: {relative}")

        release = json.loads(zf.read(release_member))
        if release.get("version") != VERSION:
            raise RuntimeError("embedded release version mismatch")
        return len(names), str(release.get("classification"))


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--output-dir", default=str(ROOT / "dist"))
    parser.add_argument("--archive-name", default=DEFAULT_ARCHIVE)
    parser.add_argument("--output", help="explicit archive path (.zip)")
    parser.add_argument("--skip-validation", action="store_true")
    args = parser.parse_args()

    archive_name = args.archive_name
    output_dir = Path(args.output_dir)
    if args.output:
        explicit = Path(args.output)
        if explicit.suffix.lower() != ".zip":
            raise RuntimeError("--output must point to a .zip archive path")
        archive_name = explicit.name
        output_dir = explicit.parent
    if PurePosixPath(archive_name).name != archive_name or not archive_name.endswith(".zip"):
        raise RuntimeError("--archive-name must be a plain .zip filename")

    if not args.skip_validation:
        env = dict(os.environ)
        env["SOURCE_DATE_EPOCH"] = "1784678400"
        return_code = subprocess.call(
            [
                sys.executable,
                str(ROOT / "tool" / "validate_release.py"),
                "--skip-tests",
                "--skip-sdk",
            ],
            cwd=ROOT,
            env=env,
        )
        if return_code:
            return return_code

    report = json.loads((ROOT / "release" / "validation_report.json").read_text(encoding="utf-8"))
    if not report.get("source_gate_passed"):
        raise RuntimeError("source validation gate failed")

    metadata = release_metadata(report)
    payloads = source_payloads()
    payloads["RELEASE.json"] = (json.dumps(metadata, indent=2, sort_keys=True) + "\n").encode("utf-8")
    payloads["SOURCE_MANIFEST.sha256"] = make_manifest(payloads)

    output = output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    archive = output / archive_name
    write_zip(archive, payloads, prefix=PACKAGE_ROOT)

    file_count, embedded_classification = validate_zip(archive, prefix=PACKAGE_ROOT)
    archive_hash = digest(archive.read_bytes())
    sums = output / "Kristin_Local_Agent_v1.9.0_build190_SHA256SUMS.txt"
    sums.write_text(f"{archive_hash}  {archive.name}\n", encoding="utf-8")
    package_metadata = {
        **metadata,
        "archive": archive.name,
        "archive_root": PACKAGE_ROOT,
        "archive_sha256": archive_hash,
        "file_count": file_count,
        "embedded_classification": embedded_classification,
        "zip_integrity_verified": True,
        "manifest_verified": True,
    }
    (output / "Kristin_Local_Agent_v1.9.0_build190_release_metadata.json").write_text(
        json.dumps(package_metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(archive)
    print(archive_hash)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
