#!/usr/bin/env python3
"""Deterministic offline system-contract checks for Kristin v1.9.0.

These checks complement Flutter behavioral tests. They are intentionally bounded,
network-free, and available before a Flutter SDK is installed.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
import os
from pathlib import Path
import sys
import tempfile


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str


def read(root: Path, relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")


def contains_all(text: str, markers: tuple[str, ...]) -> bool:
    return all(marker in text for marker in markers)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    root = Path(args.project).expanduser().resolve()

    required = (
        "lib/product/workspace_tools.dart",
        "lib/product/planning_runtime.dart",
        "lib/product/agent_decision.dart",
        "lib/product/agent_protocol.dart",
        "lib/product/protocol_types.dart",
        "lib/product/tool_schema.dart",
        "lib/product/generated/protocol_contracts.g.dart",
        "lib/product/durable_workflow.dart",
        "lib/product/repository.dart",
        "lib/product/retry_policy.dart",
        "lib/product/generated/workflow_migrations.g.dart",
        "migrations/workflow/001_core.sql",
        "migrations/workflow/002_idempotency_checkpoints.sql",
        "migrations/workflow/003_compensation_migration.sql",
        "migrations/workflow/004_append_only_guards.sql",
        "migrations/workflow/005_project_manager_execution_intelligence.sql",
        "schemas/agent_decision.v1.json",
        "schemas/tool_registry.v2.json",
        "lib/product/prompt_planning.dart",
        "lib/product/domain.dart",
        "lib/product/product_runtime.dart",
        "lib/product/storage_security.dart",
        "lib/product/chat_studio.dart",
        "lib/product/api_server.dart",
        "test/product/v1_product_preview_test.dart",
        "test/product/execution_reliability_test.dart",
        "test/product/diagnostic_replay_test.dart",
        "test/product/fixtures/diagnostic_replay/v115_nested_write_content_loss.json",
        "test/product/fixtures/diagnostic_replay/v116_markdown_path_repair_loop.json",
        "test/product/budget_diagnostics_test.dart",
        "docs/V1.0.1_MODEL_PROTOCOL_HOTFIX.md",
        "docs/V1.0.2_BUDGET_DIAGNOSTICS_HOTFIX.md",
        "docs/V1.0.3_AGENT_LOOP_RECOVERY_HOTFIX.md",
        "docs/V1.0.4_WINDOWS_VALIDATION_HOTFIX.md",
        "docs/V1.0.5_PATH_HYGIENE_HOTFIX.md",
        "docs/V1.0.6_WORKSPACE_BOUNDARY_CANONICALIZATION.md",
        "docs/V1.0.7_FAILED_RUN_RECOVERY_HOTFIX.md",
        "docs/V1.0.8_SDK_ENVIRONMENT_HOTFIX.md",
        "docs/V1.0.9_LINEAGE_CONTRACT_HOTFIX.md",
        "docs/V1.1.0_PROJECT_MANAGER_PREVIEW.md",
        "docs/V1.1.1_PROJECT_MANAGER_COMPILE_HOTFIX.md",
        "docs/V1.1.2_MODEL_RESILIENCE_HOTFIX.md",
        "docs/V1.1.3_WORKSTATION_VALIDATION_HOTFIX.md",
        "docs/V1.1.4_DETERMINISTIC_RELEASE_TESTS_HOTFIX.md",
        "docs/V1.1.6_EXECUTION_RELIABILITY_REDESIGN.md",
        "docs/V1.1.7_STABILITY_REPLAY_BASELINE.md",
        "docs/FAILURE_TAXONOMY.md",
        "docs/DIAGNOSTIC_REPLAY.md",
        "docs/CURRENT_RUN_RECOVERY.md",
        "docs/ROADMAP_IMPLEMENTATION_MATRIX.md",
        "VERSION_CONTROL.json",
        "test/product/source_contract_test.dart",
        "scripts/validate_architecture.py",
        "tool/validate_release.py",
        "tool/kristin_cli.py",
        "tool/release.py",
        "tool/source_tree_policy.py",
        "tool/generate_protocol_contracts.py",
        "tool/protocol_contract_test.py",
        "test/product/typed_protocol_schema_test.dart",
        "test/product/durable_workflow_kernel_test.dart",
        "tool/generate_workflow_migrations.py",
        "tool/workflow_kernel_test.py",
        "docs/V1.2.0_TYPED_PROTOCOL_FOUNDATION.md",
        "docs/V1.3.0_DURABLE_WORKFLOW_KERNEL.md",
        "docs/V1.5.0_PROMPT_STUDIO_2_PLAN_COMPILER.md",
        "lib/product/prompt_studio_v2.dart",
        "lib/product/execution_intelligence.dart",
        "lib/product/project_manager_v2.dart",
        "lib/product/generated/prompt_studio_contracts.g.dart",
        "lib/product/generated/v180_contracts.g.dart",
        "schemas/product_specification.v2.json",
        "schemas/task_plan.v2.json",
        "schemas/prompt_evaluation_dataset.v1.json",
        "schemas/plan_capability_catalog.v1.json",
        "schemas/plan_compilation_report.v1.json",
        "schemas/project_profile.v2.json",
        "schemas/project_manager_snapshot.v1.json",
        "schemas/model_routing_policy.v1.json",
        "schemas/execution_progress.v1.json",
        "schemas/verification_report.v1.json",
        "schemas/convergence_decision.v1.json",
        "tool/plan_compiler.py",
        "tool/generate_prompt_studio_contracts.py",
        "tool/generate_prompt_studio_fixtures.py",
        "tool/prompt_studio_v2_test.py",
        "tool/sandbox_worker.py",
        "tool/network_broker.py",
        "tool/secret_broker.py",
        "tool/sandbox_worker_test.py",
        "tool/network_broker_test.py",
        "tool/execution_intelligence.py",
        "tool/execution_intelligence_test.py",
        "tool/project_manager_v2.py",
        "tool/project_manager_v2_test.py",
        "tool/generate_v180_contracts.py",
        "tool/generate_v190_contracts.py",
        "tool/interoperability_admin_v19.py",
        "tool/interoperability_admin_v19_test.py",
        "lib/product/interoperability_v19.dart",
        "lib/product/release_operations_v19.dart",
        "lib/product/generated/v190_contracts.g.dart",
        "test/product/interoperability_v19_test.dart",
        "test/product/release_operations_v19_test.dart",
        "schemas/capability_manifest.v1.json",
        "schemas/signed_capability_manifest.v1.json",
        "schemas/mcp_server_manifest.v1.json",
        "schemas/a2a_task_contract.v1.json",
        "schemas/policy_profile.v1.json",
        "schemas/audit_chain_report.v1.json",
        "schemas/update_channel_manifest.v1.json",
        "schemas/fleet_profile.v1.json",
        "schemas/support_compatibility_policy.v1.json",
        "migrations/workflow/006_interoperability_admin.sql",
        "docs/V1.9.0_INTEROPERABILITY_ADMIN_RELEASE_OPS.md",
        "docs/V1.5.1_SANDBOX_BACKFILL.md",
        "docs/V1.6.0_PROJECT_MANAGER_2.md",
        "docs/V1.8.0_KNOWLEDGE_MEMORY_SKILLS_FILE_ADAPTERS.md",
        "lib/product/knowledge_memory_v2.dart",
        "lib/product/file_adapters.dart",
        "lib/product/generated/v180_contracts.g.dart",
        "tool/knowledge_memory_v2.py",
        "tool/knowledge_memory_v2_test.py",
        "tool/file_adapters.py",
        "tool/file_adapter_test.py",
        "test/product/knowledge_memory_v2_test.dart",
        "test/product/file_adapters_test.dart",
        "schemas/knowledge_object_manifest.v1.json",
        "schemas/memory_admission_policy.v1.json",
        "schemas/skill_candidate.v1.json",
        "schemas/published_skill.v1.json",
        "schemas/file_adapter_registry.v1.json",
        "schemas/research_freshness_policy.v1.json",
        "docs/CANONICAL_LINEAGE.md",
        "test/product/prompt_studio_v2_test.dart",
        "test/product/fixtures/prompt_studio_v2/specification.json",
        "test/product/fixtures/prompt_studio_v2/plan_001.json",
        "test/product/fixtures/prompt_studio_v2/plan_010.json",
        "test/product/fixtures/prompt_studio_v2/plan_050.json",
        "test/product/fixtures/prompt_studio_v2/plan_100.json",
    )
    results: list[Result] = []
    missing = [relative for relative in required if not (root / relative).is_file()]
    results.append(
        Result(
            "Required v1.9 cumulative files",
            not missing,
            "All retained typed-protocol, durable-kernel, Linux sandbox, Prompt Studio 2, Project Manager 2, and execution-intelligence files are present."
            if not missing
            else f"Missing: {', '.join(missing)}",
        )
    )
    if missing:
        return _finish(results, args.json)

    workspace = read(root, "lib/product/workspace_tools.dart")
    coordinator = read(root, "lib/product/planning_runtime.dart")
    agent_protocol = read(root, "lib/product/agent_protocol.dart")
    agent_decision = read(root, "lib/product/agent_decision.dart")
    tool_schema = read(root, "lib/product/tool_schema.dart")
    durable = read(root, "lib/product/durable_workflow.dart")
    retry_policy = read(root, "lib/product/retry_policy.dart")
    workflow_migrations = read(root, "lib/product/generated/workflow_migrations.g.dart")
    workflow_kernel_gate = read(root, "tool/workflow_kernel_test.py")
    durable_behavioral = read(root, "test/product/durable_workflow_kernel_test.dart")
    typed_protocol_behavioral = read(root, "test/product/typed_protocol_schema_test.dart")
    planning = read(root, "lib/product/prompt_planning.dart")
    domain = read(root, "lib/product/domain.dart")
    runtime = read(root, "lib/product/product_runtime.dart")
    storage = read(root, "lib/product/storage_security.dart")
    studio = read(root, "lib/product/chat_studio.dart")
    api = read(root, "lib/product/api_server.dart")
    diagnostics_source = read(root, "lib/product/project_diagnostics.dart")
    knowledge_source = read(root, "lib/product/models_research.dart")
    behavioral = read(root, "test/product/v1_product_preview_test.dart")
    memory_behavioral = read(root, "test/product/knowledge_memory_test.dart")
    protocol_behavioral = read(root, "test/product/execution_reliability_test.dart")
    replay_behavioral = read(root, "test/product/diagnostic_replay_test.dart")
    replay_harness = read(root, "tool/replay_diagnostics.py")
    replay_v115 = json.loads(read(root, "test/product/fixtures/diagnostic_replay/v115_nested_write_content_loss.json"))
    replay_v116 = json.loads(read(root, "test/product/fixtures/diagnostic_replay/v116_markdown_path_repair_loop.json"))
    budget_behavioral = read(root, "test/product/budget_diagnostics_test.dart")
    deployment = read(root, "lib/product/deployment_support.dart")
    cli_source = read(root, "tool/kristin_cli.py")
    prompt_studio = read(root, "lib/product/prompt_studio_v2.dart")
    prompt_contracts = read(root, "lib/product/generated/prompt_studio_contracts.g.dart")
    plan_compiler = read(root, "tool/plan_compiler.py")
    prompt_gate = read(root, "tool/prompt_studio_v2_test.py")
    prompt_behavioral = read(root, "test/product/prompt_studio_v2_test.dart")
    sandbox_worker_source = read(root, "tool/sandbox_worker.py")
    sandbox_worker_gate = read(root, "tool/sandbox_worker_test.py")
    network_broker_source = read(root, "tool/network_broker.py")
    execution_intelligence = read(root, "lib/product/execution_intelligence.dart")
    execution_intelligence_tool = read(root, "tool/execution_intelligence.py")
    execution_intelligence_gate = read(root, "tool/execution_intelligence_test.py")
    project_manager_v2 = read(root, "lib/product/project_manager_v2.dart")
    project_manager_tool = read(root, "tool/project_manager_v2.py")
    project_manager_gate = read(root, "tool/project_manager_v2_test.py")
    v170_contracts = read(root, "lib/product/generated/v180_contracts.g.dart")
    interoperability_v19 = read(root, "tool/interoperability_admin_v19.py")
    interoperability_v19_gate = read(root, "tool/interoperability_admin_v19_test.py")
    interoperability_v19_helper = read(root, "tool/interoperability_v19.py")
    release_ops_v19 = read(root, "tool/release_ops_v19.py")
    release_ops_v19_gate = read(root, "tool/release_ops_v19_test.py")
    interoperability_v19_dart = read(root, "lib/product/interoperability_v19.dart")
    release_ops_v19_dart = read(root, "lib/product/release_operations_v19.dart")
    v190_contracts = read(root, "lib/product/generated/v190_contracts.g.dart")
    network_broker_gate = read(root, "tool/network_broker_test.py")
    secret_broker_source = read(root, "tool/secret_broker.py")
    knowledge_v2 = read(root, "tool/knowledge_memory_v2.py")
    knowledge_v2_gate = read(root, "tool/knowledge_memory_v2_test.py")
    file_adapters_source = read(root, "tool/file_adapters.py")
    file_adapters_behavioral = read(root, "test/product/file_adapters_test.dart")
    knowledge_v2_behavioral = read(root, "test/product/knowledge_memory_v2_test.dart")

    results.append(
        Result(
            "Active-project absolute path compatibility",
            contains_all(
                workspace,
                (
                    "String normalizeToolPath(String input)",
                    "path_outside_project",
                    "return relative(normalized);",
                    "tool.path_normalized",
                    "originalPathHash",
                ),
            ),
            "In-project absolute paths are normalized and outside paths remain blocked with hashed audit provenance.",
        )
    )
    results.append(
        Result(
            "Bounded external path rebasing",
            contains_all(
                workspace + coordinator + behavioral + deployment,
                (
                    "class WorkspacePathRecovery",
                    "recoverExternalToolPath",
                    "virtual_workspace_alias",
                    "project_name_anchor",
                    "_looksSensitiveRecoveryPath",
                    "tool.path_rebased_to_active_project",
                    "securityBoundaryPreserved",
                    "Project scope cannot improve through a fresh work-item attempt.",
                    "rebases recognized virtual workspace paths",
                    "blocks arbitrary external writes",
                    "### Project path recovery",
                ),
            ),
            "Recognized workspace aliases and stale same-project paths are safely rebased, arbitrary external writes remain blocked, and diagnostics retain hashed recovery provenance.",
        )
    )

    results.append(
        Result(
            "Recoverable tool argument repair",
            contains_all(
                coordinator,
                (
                    "toolRepairAttempts",
                    "tool.repair_requested",
                    "_isRecoverableToolInputError",
                    "path_outside_project",
                    "project-relative path",
                ),
            ),
            "Bounded model correction is wired for path and tool-argument mistakes.",
        )
    )
    results.append(
        Result(
            "Model protocol compatibility and safe fallback",
            contains_all(
                domain + coordinator + agent_protocol + protocol_behavioral,
                (
                    "class AgentProtocolAdapter",
                    "json['function_call']",
                    "'tool_input'",
                    "'action_input'",
                    "protocolRepairAttempts < 2",
                    "protocolRepairAttempts = 0",
                    "model.protocol_fallback_applied",
                    "model.protocol_exhausted",
                    "model_protocol_exhausted",
                    "responsePreview",
                    "accepts snake-case function_call envelopes",
                    "does not normalize a tool outside the work-item allowlist",
                ),
            ),
            "Nested model envelopes, safe aliases, consecutive repair streaks, redacted previews, bounded read-only fallback, and allowlist rejection are wired.",
        )
    )
    results.append(
        Result(
            "AI Prompt Studio model",
            contains_all(
                domain + planning + runtime,
                (
                    "class PromptStudioDraft",
                    "class PromptVersionRecord",
                    "PromptGenerationAction",
                    "Future<PromptStudioDraft> generatePrompt",
                    "savePromptVersion",
                    "generatePromptDraft",
                ),
            ),
            "Structured prompt generation, validation, persistence, and runtime access are present.",
        )
    )
    results.append(
        Result(
            "Adaptive 1-100 task planning",
            contains_all(
                domain + planning,
                (
                    "class PlanTaskRecord",
                    "class TaskPlanRecord",
                    "maxLeafTasks.clamp(1, 100)",
                    "rawTasks.length > 100",
                    "expectedModelTurns",
                    "estimateConfidence",
                    "PlanRisk",
                ),
            ),
            "Task plans are bounded to 100 tasks and carry complexity, risk, confidence, and execution estimates.",
        )
    )
    results.append(
        Result(
            "Immutable plan revisions and dependency compilation",
            contains_all(
                planning,
                (
                    "revision: plan.revision + 1",
                    "previousPlanId: plan.id",
                    "_withDependencies(selectedTaskIds, all)",
                    "task_plan.compiled",
                ),
            )
            and planning.count("if (task == null || !result.add(id))") == 1,
            "Plan edits create new revisions and selected execution expands prerequisite dependencies exactly once.",
        )
    )
    results.append(
        Result(
            "Persistent prompt and plan repositories",
            contains_all(
                storage,
                (
                    "promptVersions",
                    "taskPlans",
                    "prompt_versions",
                    "task_plans",
                ),
            ),
            "Prompt versions and task-plan revisions have dedicated local repositories.",
        )
    )
    results.append(
        Result(
            "Prompt-to-Task user controls",
            contains_all(
                studio,
                (
                    "Generate prompt",
                    "Generate task list",
                    "Run all tasks",
                    "Run selected task + dependencies",
                    "Stop all running tasks",
                    "Save new plan revision",
                ),
            ),
            "Prompt generation, plan generation, selective execution, stop, and immutable-edit controls are visible in Prompt Studio.",
        )
    )
    results.append(
        Result(
            "Prompt and task-plan API",
            contains_all(
                api,
                (
                    "'/v1/prompts/generate'",
                    "'/v1/prompts/versions'",
                    "'/v1/task-plans/generate'",
                    "request.uri.path == '/v1/task-plans'",
                    "segments[1] == 'task-plans'",
                    "segments[3] == 'compile'",
                ),
            ),
            "Authenticated loopback routes cover generation, versioning, editing, listing, and deterministic compilation.",
        )
    )
    results.append(
        Result(
            "Behavioral regression coverage",
            contains_all(
                behavioral,
                (
                    "normalizes in-project absolute paths",
                    "reject absolute paths outside",
                    "generates, versions, plans, revises, and compiles",
                    "valid 100-task plan",
                    "selected execution must include transitive dependencies",
                ),
            ),
            "Flutter tests cover the reported path failure and core Prompt-to-Task behavior.",
        )
    )

    results.append(
        Result(
            "Budget-aware retries and diagnostic export",
            contains_all(
                domain + coordinator + runtime + deployment + studio + api + cli_source + budget_behavioral,
                (
                    "factory AutonomyBudget.forPlan",
                    "maxAgentTurnsPerAttempt",
                    "minModelRequestsForRetry",
                    "Future<RunRecord> retryRun(String runId)",
                    "run_retry_required",
                    "work_item.turn_budget_assigned",
                    "work_item.retry_skipped",
                    "model.request_started",
                    "model.request_completed",
                    "agent.stalled_repeated_tool_outcome",
                    "_enforceToolBudget(current, action.tool!)",
                    "tools.isMutatingTool(toolName)",
                    "The model may still complete using evidence already collected",
                    "kristin.diagnostics.bundle.v2",
                    "run-diagnostic-summary.md",
                    "Save all logs",
                    "includeAllLogs: true",
                    "action == 'retry'",
                    'logs_parser.add_argument("--export"',
                    "tool budgets are checked only when another governed tool is dispatched",
                    "retry creates a linked run",
                    "all-logs bundle retains diagnostics",
                ),
            ),
            "Retries use fresh linked runs and plan-scaled budgets; loops are bounded and a redacted all-logs ZIP is available from UI, API, and CLI.",
        )
    )

    results.append(
        Result(
            "Repeated-tool loop recovery",
            contains_all(
                coordinator + deployment + budget_behavioral,
                (
                    "class AgentLoopRecoveryPolicy",
                    "class ToolLoopObservation",
                    "agent.repeated_tool_call_blocked",
                    "agent.loop_recovery_redirected",
                    "agent.loop_recovery_completed",
                    "work_item.evidence_baseline_completed",
                    "_staticToolActionFingerprint",
                    "cachedResultSummary",
                    "### Agent loop recovery",
                    "redirects a duplicate listing to safe new evidence",
                    "completes only after diverse objective baseline evidence",
                    "never auto-completes a general grounded answer task",
                    "isNot('.env')",
                ),
            )
            and "label.contains('grounded context') ||" not in coordinator,
            "Duplicate static reads are cached, redirected to safe new evidence, and only the dedicated baseline item can complete deterministically.",
        )
    )

    sys.path.insert(0, str(root / "tool"))
    try:
        from source_tree_policy import is_generated_path  # type: ignore

        generated_policy_ok = (
            is_generated_path(
                "windows/flutter/ephemeral/flutter_windows.dll"
            )
            and is_generated_path(
                "windows/flutter/ephemeral/flutter_windows.dll.pdb"
            )
            and is_generated_path(".dart_tool/package_config.json")
            and not is_generated_path("lib/product/domain.dart")
        )
    except Exception as error:  # pragma: no cover - surfaced in CLI output
        generated_policy_ok = False
        results.append(
            Result(
                "Generated source-tree policy import",
                False,
                f"Generated-path policy failed: {error}",
            )
        )
    else:
        validator_source = read(root, "tool/validate_release.py")
        release_source = read(root, "tool/release.py")
        scan_source = read(root, "tool/secret_scan.py")
        results.append(
            Result(
                "Generated Flutter/native state exclusion",
                generated_policy_ok
                and "if is_generated_path(rel):" in validator_source
                and "if is_generated_path(relative)" in release_source
                and "is_generated_path(p.relative_to(ROOT))" in scan_source,
                "Flutter ephemeral binaries and caches are ignored consistently by source validation, secret scanning, and release packaging.",
            )
        )

    try:
        import kristin_cli  # type: ignore

        cli = kristin_cli.build_parser()
        parsed_system = cli.parse_args(["test", "--system", "--project", "."])
        parsed_release = cli.parse_args(["test", "--release", "--project", "."])
        parser_ok = parsed_system.system and parsed_release.release
    except Exception as error:  # pragma: no cover - surfaced in CLI output
        parser_ok = False
        results.append(Result("CLI parser import", False, f"CLI parser failed: {error}"))
    else:
        results.append(
            Result(
                "CLI system and release modes",
                parser_ok,
                "`test --system` and `test --release` parse as mutually exclusive test levels.",
            )
        )

        with tempfile.TemporaryDirectory(prefix="kristin-project-manager-") as temporary:
            fixture_root = Path(temporary)
            fixture_command = {
                "executable": sys.executable,
                "arguments": ["-c", "print('PROJECT_MANAGER_OK')"],
            }
            (fixture_root / "kristin.project.json").write_text(
                json.dumps(
                    {
                        "type": "Project Manager fixture",
                        "analyze": fixture_command,
                        "test": fixture_command,
                        "build": fixture_command,
                        "run": fixture_command,
                    }
                ),
                encoding="utf-8",
            )
            profile = kristin_cli.detect_profile(fixture_root)
            analysis_check = kristin_cli.run_bounded(
                profile.analysis[0], fixture_root
            ) if profile.analysis else None
            build_check = kristin_cli.run_bounded(
                profile.build, fixture_root
            ) if profile.build is not None else None
            run_check = kristin_cli.run_bounded(
                profile.run, fixture_root
            ) if profile.run is not None else None
            profile_ok = (
                profile.kind == "Project Manager fixture"
                and profile.source == "kristin.project.json"
                and len(profile.analysis) == 1
                and len(profile.tests) == 1
                and analysis_check is not None
                and analysis_check.status == "PASS"
                and build_check is not None
                and build_check.status == "PASS"
                and run_check is not None
                and run_check.status == "PASS"
                and "PROJECT_MANAGER_OK" in run_check.output
            )
        results.append(
            Result(
                "Project Manager CLI profile execution",
                profile_ok,
                "A custom Analyze/Test/Build/Run profile is detected and its bounded analysis, build, and run commands execute successfully.",
            )
        )

        sentinel_values = {
            "APPDATA": "C:/Users/test/AppData/Roaming",
            "LOCALAPPDATA": "C:/Users/test/AppData/Local",
            "PUB_CACHE": "C:/Users/test/AppData/Local/Pub/Cache",
            "HTTPS_PROXY": "http://user:password@proxy.invalid:8080",
            "SSL_CERT_FILE": "C:/certificates/company-ca.pem",
        }
        previous = {key: os.environ.get(key) for key in sentinel_values}
        try:
            os.environ.update(sentinel_values)
            default_environment = kristin_cli._safe_environment(profile="default")
            sdk_environment = kristin_cli._safe_environment(profile="sdk")
            inferred_flutter = kristin_cli._command_environment_profile(
                kristin_cli.CommandSpec("Flutter", ("flutter", "pub", "get"))
            )
            inferred_python = kristin_cli._command_environment_profile(
                kristin_cli.CommandSpec("Python", (sys.executable, "-V"))
            )
            dependency_hint = kristin_cli._failure_hint(
                "Because the package cache was unavailable.\nFailed to update packages."
            )
            probe = kristin_cli.run_bounded(
                kristin_cli.CommandSpec(
                    "SDK environment probe",
                    (
                        sys.executable,
                        "-c",
                        (
                            "import os,sys; "
                            "required=('APPDATA','LOCALAPPDATA','PUB_CACHE',"
                            "'HTTPS_PROXY','SSL_CERT_FILE'); "
                            "ok=all(os.environ.get(k) for k in required); "
                            "print(os.environ.get('HTTPS_PROXY','')); "
                            "print('SDK_ENV_OK' if ok else 'SDK_ENV_MISSING'); "
                            "sys.exit(0 if ok else 1)"
                        ),
                    ),
                    environment_profile="sdk",
                ),
                root,
            )
        finally:
            for key, value in previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value

        sdk_environment_ok = (
            default_environment.get("APPDATA") == sentinel_values["APPDATA"]
            and default_environment.get("LOCALAPPDATA")
            == sentinel_values["LOCALAPPDATA"]
            and "PUB_CACHE" not in default_environment
            and "HTTPS_PROXY" not in default_environment
            and all(
                sdk_environment.get(key) == value
                for key, value in sentinel_values.items()
            )
            and inferred_flutter == "sdk"
            and inferred_python == "default"
            and dependency_hint == "Because the package cache was unavailable."
            and probe.status == "PASS"
            and "SDK_ENV_OK" in probe.output
            and "user:password" not in probe.output
            and "[REDACTED]@proxy.invalid:8080" in probe.output
            and '"--skip-sdk"' in cli_source
            and '"--no-pub"' in cli_source
        )
        results.append(
            Result(
                "SDK subprocess environment compatibility",
                sdk_environment_ok,
                "Flutter and Dart commands receive Windows Pub-cache, proxy, and certificate variables while ordinary project commands keep the narrower environment.",
            )
        )

    results.append(
        Result(
            "Project Manager and capability-aligned execution",
            contains_all(
                domain
                + diagnostics_source
                + runtime
                + studio
                + api
                + cli_source
                + planning
                + coordinator
                + behavioral,
                (
                    "class ProjectProcessStatus",
                    "class ProjectExecutionProfile",
                    "analysisCommands",
                    "analyzeProject(",
                    "buildProject(",
                    "startProject(",
                    "stopProject(",
                    "label: 'Project Manager'",
                    "Save logs",
                    "action == 'manager'",
                    "projects:execute",
                    "execute_profile_commands",
                    "if args.command in {\"analyze\", \"build\"}",
                    "_effectivePlanMode",
                    "_taskRequiresMutation",
                    "docs/design/wireframes.md",
                    "_deduplicateCapabilityTasks",
                    "implementation_stalled_read_only",
                    "work_item.mutation_required",
                    "var mutationRepairAttempts = 0;",
                    "mutationRepairAttempts < 2",
                    "promotes artifact-producing plan tasks to governed build work",
                    "keeps an explicitly planning-only task read-only",
                    "detects custom Analyze, Test, Build, and Run commands",
                ),
            ),
            "The desktop, API, and CLI share one project profile, while artifact-producing tasks receive governed mutation capability and planning-only tasks remain read-only.",
        )
    )

    results.append(
        Result(
            "Diagnostic-derived memory, protocol, and capability recovery",
            "final failureIntent = includeUnsuccessfulEpisodes;" in knowledge_source
            and "includeUnsuccessfulEpisodes || chunk.pinned" in knowledge_source
            and "_failureIntentTerms" not in knowledge_source
            and "calculator history view, input validation, and error handling" in memory_behavioral
            and "What went wrong with calculator error handling" in protocol_behavioral
            and "inspect_project_and_establish_evidence_baseline" in protocol_behavioral
            and "_resolveTaskIntent" in agent_protocol
            and "knowledge.context_policy_applied" in coordinator
            and "antiCopyRule" in coordinator
            and "protocolRepairAttempt" in coordinator
            and "Create project-local wireframes and user flows" in planning
            and "Prepare local preview and deployment package" in planning
            and "isKristinSourceCheckout" in workspace
            and "self_project_target_rejected" in coordinator + planning
            and "### Automatic memory policy" in deployment
            and "### Model protocol recovery" in deployment,
            "Failed memory is explicit-only, the observed composite action recovers through an allowlisted task tool, generated plans align with local capabilities, and accidental self-target mutation is blocked.",
        )
    )

    source_contract = read(root, "test/product/source_contract_test.dart")
    validator = read(root, "tool/validate_release.py")
    architecture_wrapper = read(root, "scripts/validate_architecture.py")
    deployment = read(root, "lib/product/deployment_support.dart")
    results.append(
        Result(
            "Windows compile and validator hotfix",
            "contains(r\"'inspect_file:$candidate'\")" in source_contract
            and "contains(\"'inspect_file:$candidate'\")" not in source_contract
            and "sourceRunId: this.sourceRunId," not in domain
            and "output\n          ..writeln(\n            '- `${item.item.id}`" not in deployment
            and "--skip-sdk" in architecture_wrapper
            and "Kristin governed source validation failed:" in validator
            and "source_contains(content, token)" in validator,
            "Literal source markers compile, analyzer infos are removed, source-only validation avoids duplicate SDK gates, and failures are visible.",
        )
    )

    results.append(
        Result(
            "Project Manager ProductException linkage",
            "import 'storage_security.dart';" in diagnostics_source
            and "class ProductException implements Exception" in storage
            and "throw ProductException(" in diagnostics_source,
            "ProjectDiagnosticsService imports the module that defines ProductException, preventing the reported Windows analyzer failure.",
        )
    )

    results.append(
        Result(
            "Ollama cold-load resilience and capability-safe planning",
            contains_all(
                knowledge_source
                + storage
                + runtime
                + coordinator
                + planning
                + deployment
                + protocol_behavioral
                + behavioral,
                (
                    "class ModelGenerationProgress",
                    "defaultLoadTimeout = const Duration(minutes: 8)",
                    "defaultLoadRetries = 1",
                    "'prompt': ''",
                    "'stream': false",
                    "load_retry_scheduled",
                    "_closeOnCancellation",
                    "_remainingUntil",
                    "_shorterDuration",
                    "ollamaLoadTimeoutSeconds",
                    "ollamaLoadRetries",
                    "ollamaKeepAliveMinutes",
                    "cancellation: control.cancellation.cancelled",
                    "provider already performs its configured bounded cold-load retry",
                    "### Model availability and cold-load recovery",
                    "Run local usability and interaction verification",
                    "Capability alignment replaces the unsupported human-study instruction",
                    "Do not recruit participants",
                    ".clamp(2, 3)",
                    "manual: alignedManual",
                    "Ollama retries a transient cold-load timeout inside one model turn",
                    "cancelling a run closes an in-flight Ollama cold load",
                ),
            ),
            "Cold Ollama loads are prewarmed, retried inside one model request, cancellable from Stop, observable in diagnostics, and unsupported human-study tasks are rewritten into local objective verification.",
        )
    )

    results.append(
        Result(
            "Workstation analyzer and formatter-resilient contracts",
            "_HttpCancellationBinding({this.subscription})" not in knowledge_source
            and "StreamSubscription<void>? subscription;" in knowledge_source
            and "contains(\"stage: 'load_started'\")" not in source_contract
            and "contains(\"'load_started'\")" in source_contract
            and "contains(\"'load_retry_started'\")" in source_contract
            and "containsAllInOrder(<String>[" in protocol_behavioral
            and all(
                f"'{stage}'" in protocol_behavioral
                for stage in (
                    "load_started",
                    "load_retry_scheduled",
                    "load_retry_started",
                    "load_completed",
                    "generation_started",
                )
            )
            and "Do not deploy to an external service. Do not claim a public URL."
            in planning
            and "do not claim a public url" in behavioral.lower(),
            "The reported analyzer info is removed, progress-stage verification survives dart format, and local-only deployment instructions are tested semantically.",
        )
    )

    results.append(
        Result(
            "Deterministic repeated Flutter release validation",
            "final secondWarmupStarted = Completer<void>();" in protocol_behavioral
            and "await secondWarmupStarted.future.timeout(" in protocol_behavioral
            and "defaultLoadTimeout: const Duration(seconds: 2)" in protocol_behavioral
            and "defaultLoadTimeout: const Duration(milliseconds: 40)" not in protocol_behavioral
            and "Duration(milliseconds: 90)" not in protocol_behavioral
            and "final warmupRequestStarted = Completer<void>();" in protocol_behavioral
            and "final releaseWarmupResponse = Completer<void>();" in protocol_behavioral
            and "final warmupRequestFinished = Completer<void>();" in protocol_behavioral
            and "await warmupRequestStarted.future.timeout" in protocol_behavioral
            and "await releaseWarmupResponse.future" in protocol_behavioral
            and "Future<void>.delayed(const Duration(seconds: 1))" not in protocol_behavioral
            and '"--concurrency=1"' in cli_source
            and '"--concurrency=1"' in validator
            and 'if "[E]" in line' in cli_source
            and "test_failures" in cli_source,
            "Cold-load and cancellation fixtures synchronize on explicit server events, while Kristin-owned Flutter suites run serially and preserve the failing test identity.",
        )
    )


    results.append(
        Result(
            "V1.1.7 golden replay and convergence controls",
            "canonicalModelPathToken" in workspace
            and "BoundedArtifactRecoveryPolicy" in coordinator
            and "AutomaticArtifactVerificationPolicy" in coordinator
            and "RunRetryBudgetPolicy" in coordinator
            and "work_item.artifact_auto_inspection_started" in coordinator
            and "work_item.artifact_auto_inspection_completed" in coordinator
            and "governed_correction" not in coordinator
            and "expectedExists" in workspace
            and "stale_existence" in workspace
            and "create-only recovery cannot replace an uninspected artifact" in budget_behavioral
            and "Never copy a history entry as the action" in coordinator
            and "--replay-all" in read(root, "tool/kristin_cli.py")
            and "all compact production diagnostics" in replay_behavioral
            and "canonical_path_token" in replay_harness
            and replay_v115.get("source", {}).get("sha256")
            == "a2c3570a9910cf99f3f5c26388b6638bf5639796c47009277cfcd64c90dd0f9b"
            and replay_v116.get("source", {}).get("sha256")
            == "69a6b4502607e35b9262d66de9e5be612f0fcc26a867a5242453fc9854d78895"
            and replay_v116.get("expected", {}).get("minimumRemainingRepairs") == 4,
            "Both supplied failures are compact replay fixtures; wrapped paths, read-only loops, post-write verification, copied coordinator metadata, and doomed retries have deterministic controls.",
        )
    )

    results.append(
        Result(
            "Typed AgentDecision and generated tool-schema foundation",
            "sealed class AgentDecision" in agent_decision
            and "class ToolDecision" in agent_decision
            and "class CompleteDecision" in agent_decision
            and "class FailDecision" in agent_decision
            and "class AskUserDecision" in agent_decision
            and "class DelegateDecision" in agent_decision
            and "class OllamaAgentProviderAdapter" in agent_protocol
            and "class OpenAiCompatibleAgentProviderAdapter" in agent_protocol
            and "class McpAgentProviderAdapter" in agent_protocol
            and "class RecordedAgentProviderAdapter" in agent_protocol
            and "generatedToolRegistry" in tool_schema
            and "normalizeAndValidate" in tool_schema
            and "validateOutput" in tool_schema
            and "tool.contract.validateOutput" in workspace
            and "write_file fails closed when canonical content is absent" in typed_protocol_behavioral
            and "supports all canonical decision variants" in typed_protocol_behavioral
            and "deterministic envelope fuzzing never loses write content" in typed_protocol_behavioral,
            "Five typed decisions, four provider adapters, and all 23 governed tool contracts are generated and validated before dispatch and after result creation.",
        )
    )

    lineage = read(root, "VERSION_CONTROL.json")
    try:
        lineage_data = json.loads(lineage)
    except (json.JSONDecodeError, TypeError):
        lineage_data = {}
    raw_release_lineage = lineage_data.get("transitiveReleaseLineage", [])
    release_lineage = {
        str(entry.get("version")): entry
        for entry in raw_release_lineage
        if isinstance(entry, dict)
    } if isinstance(raw_release_lineage, list) else {}
    prior_lineage = lineage_data.get("priorLineage", {})
    if not isinstance(prior_lineage, dict):
        prior_lineage = {}
    merged_patch = prior_lineage.get("mergedUserPatch", {})
    if not isinstance(merged_patch, dict):
        merged_patch = {}
    lineage_contract = lineage_data.get("lineageContract", {})
    if not isinstance(lineage_contract, dict):
        lineage_contract = {}
    execution_diagnostic = prior_lineage.get("executionConvergenceDiagnostic", {})
    if not isinstance(execution_diagnostic, dict):
        execution_diagnostic = {}
    reliability_diagnostic = prior_lineage.get("executionReliabilityDiagnostic", {})
    if not isinstance(reliability_diagnostic, dict):
        reliability_diagnostic = {}
    parent_release = lineage_data.get("parentRelease", {})
    if not isinstance(parent_release, dict):
        parent_release = {}

    results.append(
        Result(
            "Execution convergence and product-specific artifact recovery",
            "actionObject['command']" in domain
            and "_specializeCommandTool" in agent_protocol
            and "project-scoped git_status" in agent_protocol
            and "'argument_required'" in coordinator
            and "ArtifactEvidencePolicy" in coordinator
            and "artifact_scope_mismatch" in coordinator
            and "artifact_evidence_missing" in coordinator
            and "work_item.artifact_evidence_required" in coordinator
            and "work_item.artifact_evidence_completed" in coordinator
            and "requiresValidatedArtifact" in coordinator
            and "_priorEvidenceHistory" in coordinator
            and "toolRepairAttempt" in coordinator
            and "operation: 'noop'" in workspace
            and "workspace.mutation_noop" in workspace
            and "process_scope_argument_rejected" in workspace
            and "process_path_outside_project" in workspace
            and "The selected project is not a Git repository" in workspace
            and "Approved product context" in planning
            and "Initialize the selected project workspace" in planning
            and "Implement the client-side calculation engine and session history" in planning
            and "unnecessary Express/REST backend" in planning
            and "backendImplementationAction" in planning
            and "### Artifact scope and convergence" in deployment
            and "normalizes the observed nested command vector" in protocol_behavioral
            and "rejects an unrelated commerce wireframe" in protocol_behavioral
            and "identical writes do not create" in budget_behavioral
            and "Do not install Node.js" in behavioral
            and "Session calculation history" in behavioral
            and "Conduct Comprehensive Testing of Calculator" in behavioral
            and execution_diagnostic.get("sha256")
            == "af691d08567a1cad8b9593b4e502aae2415f3ded486a4567178490ee4c7c1c75"
            and execution_diagnostic.get("runId")
            == "run_hklfhuqkrwdoQ11swy34hvARke"
            and "preserves direct nested write content from the observed failure envelope" in protocol_behavioral
            and "artifact_mutation_required" in coordinator
            and "Argument \"content\" is required" in workspace
            and "argumentSchema" in tool_schema
            and reliability_diagnostic.get("sha256")
            == "a2c3570a9910cf99f3f5c26388b6638bf5639796c47009277cfcd64c90dd0f9b"
            and reliability_diagnostic.get("runId")
            == "run_hklsywuyo4NMJgt9ijIxWPhBDr"
            and parent_release.get("version") == "1.8.0+180"
            and parent_release.get("sha256")
            == "eac7469a776c859b9d14ad6133d06093c43327f8f4579633615aa3129cca9bcc",
            "Nested argument preservation, fail-closed writes, mutation-required artifact recovery, compact prompts, no-op convergence, product-specific validation, and process boundaries are covered by deterministic contracts.",
        )
    )

    results.append(
        Result(
            "Linux sandbox backfill source integration",
            contains_all(
                sandbox_worker_source
                + sandbox_worker_gate
                + network_broker_source
                + network_broker_gate
                + secret_broker_source
                + cli_source,
                (
                    "def probe_backend()",
                    "linux_userns_namespace_worker",
                    "workspace_mode='snapshot_writable'",
                    "Trusted host diagnostic completed successfully.",
                    "def fetch_https(",
                    "https URLs",
                    "def issue_secret(",
                    "def consume_secret(",
                    "def sandbox_capabilities()",
                    "def run_bounded(spec: CommandSpec",
                    "execution_mode: str = \"sandbox\"",
                ),
            )
            and isinstance(lineage_data.get("sandboxBackfill"), dict)
            and lineage_data.get("sandboxBackfill", {}).get("linuxNamespaceWorker") is True
            and lineage_data.get("sandboxBackfill", {}).get("fullCrossPlatformV14Claimed") is False,
            "The cumulative source line now contains a real Linux namespace worker, HTTPS broker, one-use secret broker, sandbox-aware CLI routing, and honest metadata that the full cross-platform v1.4 milestone is still open.",
        )
    )

    prompt_meta = lineage_data.get("promptStudioV2", {})
    results.append(
        Result(
            "Prompt Studio 2 deterministic plan compiler",
            contains_all(
                prompt_studio
                + prompt_contracts
                + runtime
                + api
                + cli_source
                + plan_compiler
                + prompt_gate
                + prompt_behavioral,
                (
                    "class ProductSpecificationV2",
                    "class TaskPlanV2",
                    "class PromptStudioV2Compiler",
                    "class PromptStudioV2Evaluator",
                    "promptStudioV2",
                    "/v1/prompt-studio/v2/compile",
                    "/v1/prompt-studio/v2/evaluate",
                    "plan-compile",
                    "sideEffectsPerformed",
                    "sandbox_required",
                    "task_id_duplicate",
                    "criterion_validator_missing",
                    "Prompt Studio 2 gate:",
                    "payload['passedCount']",
                    "payload['total']",
                    "<int>[1, 10, 50, 100]",
                    "4f65d0e57ee86b58b26223970c8fbfda243256a47689ce83568df88be042500a",
                ),
            )
            and "from jsonschema" not in plan_compiler
            and isinstance(prompt_meta, dict)
            and prompt_meta.get("behavioralGateCases") == 30
            and prompt_meta.get("v14SandboxImplemented") is False
            and prompt_meta.get("sandboxDependentTasksFailClosed") is True,
            "Canonical specifications, plans, evaluation datasets, stable-ID/reference checks, capability checks, side-effect-free simulation, 1/10/50/100 scale fixtures, and sandbox fail-closed behavior are integrated without replacing the v1.3 durable kernel.",
        )
    )

    results.append(
        Result(
            "Structured transitive release lineage",
            "normalized.startsWith('//?/')" in workspace
            and "startsWith('UNC/')" in workspace
            and "accepts an in-project absolute path when the project root sits" in behavioral
            and lineage_data.get("canonicalHead") == "1.9.0+190"
            and lineage_contract.get("preserveAcrossHeads") is True
            and lineage_contract.get("requiredAncestorVersions")
            == ["1.0.5+105", "1.0.6+106", "1.0.7+107", "1.0.8+108", "1.0.9+109", "1.1.0+110", "1.1.1+111", "1.1.2+112", "1.1.3+113", "1.1.4+114", "1.1.5+115", "1.1.6+116", "1.1.7+117", "1.2.0+120", "1.3.0+130"]
            and merged_patch.get("sha256")
            == "80e5044cf47e8f19ec2350a20f22e0b9fc3da464fac142bc67a5d6bc6231e3f3"
            and release_lineage.get("1.0.5+105", {}).get("sha256")
            == "81bc8384d545cd6586696ed3b58da315b596de042785ae9918ea4b2b427f18a2"
            and release_lineage.get("1.0.6+106", {}).get("sha256")
            == "9829aa2e658893279d66e96699e225aef739a791f4b1870cf749ac8349a4662d"
            and release_lineage.get("1.0.7+107", {}).get("sha256")
            == "1b10796ceef9132f8d39f74dab69b5c81bcbf91d9a351c45d5d806b8bcb45620"
            and release_lineage.get("1.0.8+108", {}).get("sha256")
            == "76bff50ca1fe0eb82b54c09cf7ecf8f35e6d2c2062490bd73d141785b4d21448"
            and release_lineage.get("1.0.9+109", {}).get("sha256")
            == "4090bbb6fd680bde8e3862039fd503fce3cda93d982076dd3b6bf3d1524eca1c"
            and release_lineage.get("1.1.0+110", {}).get("sha256")
            == "a96d1544e3a2ef41bd01c489b2733e74fcd7c242aedcbb47b14b745a6e11a70d"
            and release_lineage.get("1.1.1+111", {}).get("sha256")
            == "830f59d1401eab6a97b99f2f96f27dace7902f4541dfbd108ea67f20266604ee"
            and release_lineage.get("1.1.2+112", {}).get("sha256")
            == "4300bb3c228e3d4b3502819df1cf84549a5bb2d66672362cdfd9e6d730fe34a2"
            and release_lineage.get("1.1.3+113", {}).get("sha256")
            == "fa648c05fcae9e3e89fca0ab5dfb41356c85d97b436aa05dd5974388e7148895"
            and release_lineage.get("1.1.4+114", {}).get("sha256")
            == "989ccfc9abdda31537b10b4a6a15e958d12b8209ba923457d45759c3bb5d29b3"
            and release_lineage.get("1.1.5+115", {}).get("sha256")
            == "28be6ac8b5de2c7612a4c5e9456dfe09895cd0964681875861e2074b1760f2a8"
            and release_lineage.get("1.1.6+116", {}).get("sha256")
            == "d4c23f7b005d7067bda06c8761f10d1cc489337300f4358b561415ebe2a6c583"
            and release_lineage.get("1.1.7+117", {}).get("sha256")
            == "6b32cb8105dcdf6aee0aff9599eefd8552e469f0c813eb992720e84287d7e835"
            and release_lineage.get("1.2.0+120", {}).get("sha256")
            == "a4904b78523da79b8abd87866c7e4497231a3f0c924cfff4d20aec12194d59d3"
            and release_lineage.get("1.3.0+130", {}).get("sha256")
            == "8da6f20dc3ccd9ee71406092df0a4e1fadd77a93916a553f0efc71b47153ff19"
            and prior_lineage.get("workstationValidationTranscript", {}).get("sha256")
            == "f11139cff61ed1d7c0526e60454600de9831b330bbf2cdeb92e9adb7a4ce538b"
            and "47bb8141259ce002" in lineage
            and "0f20bd38314290bf" in lineage
            and "run_hkk9czt4wzMPTp3bsaqLnpNOx2" in lineage
            and "2e1215e5d3bee81e" in lineage
            and "run_hkkkbh7q3rNkIqtjzJuPYvsiiy" in lineage,
            "The v1.9 head preserves the verified lineage and adds interoperability, administration, audit verification, and authenticated source-update foundations to the canonical source line.",
        )
    )

    kernel_metadata = lineage_data.get("durableWorkflowKernel", {})
    if not isinstance(kernel_metadata, dict):
        kernel_metadata = {}
    results.append(
        Result(
            "Retained v1.3.0 durable workflow kernel",
            contains_all(
                durable + storage + workspace + coordinator + retry_policy,
                (
                    "class DurableWorkflowStore",
                    "PRAGMA journal_mode = WAL",
                    "PRAGMA synchronous = FULL",
                    "BEGIN IMMEDIATE",
                    "claimOperation",
                    "recoverInFlightRuns",
                    "rebuildRunProjectionFromHistory",
                    "workflow_startup_rollback_failed",
                    "workflow.sqlite3",
                    "status: 'prepared'",
                    "await _setStatus(record, 'applied')",
                    "transaction_recovery_required",
                    "acquireRunLease",
                    "recordTaskAttempt",
                    "class WorkflowRetryTaxonomy",
                ),
            )
            and "generatedWorkflowSchemaVersion = 6" in workflow_migrations
            and "df7e693bff693d0bf649de4f26ea907ce969456adfbf342d17f40f06b22b6261" in workflow_migrations
            and "Crash after idempotent result replays once" in workflow_kernel_gate
            and "restores an existing database when a legacy import fails" in durable_behavioral
            and kernel_metadata.get("schemaVersion") == 6
            and kernel_metadata.get("appendOnlyRunEvents") is True
            and kernel_metadata.get("durableIdempotency") is True
            and kernel_metadata.get("startupRollback") is True
            and kernel_metadata.get("executableKernelCases") == 14,
            "SQLite authority, append-only events, transactional projections, idempotency, leases, checkpoints, compensation, migration rollback, and executable crash contracts are wired.",
        )
    )

    results.append(
        Result(
            "V1.6 Project Manager 2 operational layer",
            contains_all(
                project_manager_tool + project_manager_v2 + v170_contracts,
                (
                    "ProjectProfileV2",
                    "snapshot_writable",
                    "managed_project_processes",
                    "artifact_records",
                    "probe_backend",
                    "ProjectManagerV2Service",
                    "project_manager_snapshot",
                ),
            )
            and "Managed Run can be stopped with its process group" in project_manager_gate
            and "Append-only intelligence records reject mutation" in project_manager_gate
            and "--project-manager" in cli_source,
            "Strict profiles, live sandbox readiness, retained snapshots, durable process records, bounded artifacts, and CLI integration are wired.",
        )
    )

    results.append(
        Result(
            "V1.7 model router, verifier, and convergence engine",
            contains_all(
                execution_intelligence + execution_intelligence_tool + coordinator + durable,
                (
                    "RoleBasedModelRouter",
                    "ModelCircuitState",
                    "SemanticProgressEngine",
                    "ConvergenceController",
                    "IndependentVerifier",
                    "ContextCompactor",
                    "appendModelRouteDecision",
                    "appendSemanticProgress",
                    "appendVerificationReport",
                    "work_item.semantic_progress_evaluated",
                    "work_item.independent_verification_completed",
                    "_objectiveEvidenceForCriterion",
                    "mutation_followed_by_current_artifact_inspection",
                    "task_split_required",
                    "agent_user_input_required",
                    "model_fallback_approval_required",
                    "PhaseBudget.defaults('execution')",
                ),
            )
            and "objectiveEvidenceAvailable" not in coordinator
            and "entry.objective" in execution_intelligence
            and "--execution-intelligence" in cli_source,
            "Role routing, durable circuit state, semantic progress, strategy escalation, objective verification, phase budgets, and context compaction are integrated.",
        )
    )

    results.append(
        Result(
            "V1.9 interoperability, administration, and release operations",
            contains_all(
                interoperability_v19 + interoperability_v19_gate + interoperability_v19_helper + release_ops_v19 + release_ops_v19_gate + interoperability_v19_dart + release_ops_v19_dart + v190_contracts + workflow_migrations,
                (
                    "class CapabilityManifest",
                    "class McpLifecycleController",
                    "class A2ADelegationController",
                    "class AuditChain",
                    "class UpdatePolicyVerifier",
                    "class SignedManifestEnvelope",
                    "class SupportLifecyclePolicy",
                    "class UpdateManifest",
                    "const String interoperabilityV19Version = '1.9.0+190'",
                    "const String releaseOperationsV19Version = '1.9.0+190'",
                    "const String v190ContractsSha256",
                    "generatedWorkflowSchemaVersion = 6",
                ),
            )
            and "CREATE TABLE IF NOT EXISTS audit_records" in read(root, "migrations/workflow/006_interoperability_admin.sql"),
            "Typed MCP lifecycle manifests, bounded A2A delegation, signed manifests, audit verification, support lifecycle policy, and authenticated source-update policy are wired.",
        )
    )

    results.append(
        Result(
            "Cumulative v1.2-v1.9 runtime composition",
            "ExecutionIntelligenceService" in runtime
            and "ProjectManagerV2Service" in runtime
            and "executionIntelligence: executionIntelligence" in runtime
            and "projectManagerV2: projectManagerV2" in runtime
            and "generatedWorkflowSchemaVersion = 6" in workflow_migrations,
            "One ProductRuntime composes the typed protocol, SQLite kernel, Linux sandbox, Prompt Studio 2, Project Manager 2, and execution-intelligence services.",
        )
    )

    results.append(
        Result(
            "V1.7 version identity",
            "const String kristinVersion = '1.9.0+190'" in domain
            and "VERSION = \"1.9.0+190\"" in read(root, "tool/kristin_cli.py")
            and "version: 1.9.0+190" in read(root, "pubspec.yaml")
            and "def _decode_output(value: bytes)" in read(root, "tool/kristin_cli.py")
            and '_decode_output(completed.stdout or b"")' in read(root, "tool/kristin_cli.py")
            and 'environment.update(dict(spec.environment))' in read(root, "tool/kristin_cli.py")
            and "_SDK_ENVIRONMENT_KEYS" in read(root, "tool/kristin_cli.py")
            and '"--skip-sdk"' in read(root, "tool/kristin_cli.py")
            and '"--no-pub"' in read(root, "tool/kristin_cli.py")
            and '"--concurrency=1"' in read(root, "tool/kristin_cli.py")
            and '(("SOURCE_DATE_EPOCH", "1784678400"),)' in read(root, "tool/kristin_cli.py")
            and 'env["SOURCE_DATE_EPOCH"] = "1784678400"' in read(root, "tool/release.py"),
            "Runtime, package, CLI, schema-v6 persistence, Project Manager 2, execution intelligence, and v1.8 knowledge/file-adapter versions agree on the cumulative contract.",
        )
    )
    return _finish(results, args.json)


def _finish(results: list[Result], json_output: bool) -> int:
    failed = [result for result in results if not result.passed]
    if json_output:
        print(
            json.dumps(
                {
                    "passed": len(results) - len(failed),
                    "failed": len(failed),
                    "results": [asdict(result) for result in results],
                },
                indent=2,
                sort_keys=True,
            )
        )
    else:
        for result in results:
            print(f"{'PASS' if result.passed else 'FAIL':<5} {result.name}: {result.detail}")
        print(f"\nResult: {len(results) - len(failed)} passed, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
