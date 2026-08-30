#!/usr/bin/env python3
"""Lexical/source-shape checks for complete Dart test files created by slices.

This does not replace `flutter test`. It ensures every full test artifact shipped
by the portable bundle is at least a self-contained Dart source unit with sane
imports/delimiters before the real checkout sees it.
"""
from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent

TEST_CONSTANTS = {
    "apply_advanced_same_conversation.py": ("TEST", "test/product/advanced_same_conversation_contract_test.dart"),
    "apply_authority_convergence_qualification.py": ("TEST", "test/product/authority_convergence_contract_test.dart"),
    "apply_blocking_clarification_loop.py": ("TEST", "test/product/blocking_clarification_contract_test.dart"),
    "apply_bounded_protocol_v3_delegate.py": ("TEST_SOURCE", "test/product/runner_bounded_delegate_contract_test.dart"),
    "apply_collision_safe_target_resolution.py": ("TEST", "test/product/chat_target_collision_test.dart"),
    "apply_continuation_handoff_activity_projection.py": ("TEST_SOURCE", "test/product/chat_continuation_activity_contract_test.dart"),
    "apply_delegate_recovery_qualification.py": ("TEST", "test/product/runner_delegate_recovery_contract_test.dart"),
    "apply_deterministic_utility_time.py": ("TEST", "test/product/utility_time_test.dart"),
    "apply_human_readable_failure_projection.py": ("TEST", "test/product/chat_failure_projection_contract_test.dart"),
    "apply_idle_steering_continuation.py": ("TEST", "test/product/steering_idle_continuation_contract_test.dart"),
    "apply_project_free_research_execution.py": ("TEST_SOURCE", "test/product/task_kernel/research_task_family_execution_test.dart"),
    "apply_protocol_v3_timestamp_wait.py": ("TEST", "test/product/runner_deferred_timestamp_wait_contract_test.dart"),
    "apply_research_archive_degradation.py": ("TEST", "test/product/research_archive_degradation_contract_test.dart"),
    "apply_research_optional_archive_guard.py": ("TEST", "test/product/research_optional_archive_contract_test.dart"),
    "apply_research_restart_reconciliation.py": ("TEST", "test/product/task_kernel/research_restart_reconciliation_test.dart"),
    "apply_scope_changing_steering_continuation.py": ("TEST_SOURCE", "test/product/steering_scope_continuation_contract_test.dart"),
    "apply_semantic_durable_steering.py": ("TEST_SOURCE", "test/product/semantic_durable_steering_test.dart"),
    "apply_semantic_slash_understanding.py": ("TEST_SOURCE", "test/product/task_kernel/semantic_slash_understanding_test.dart"),
    "apply_truthful_conversation_streaming.py": ("TEST", "test/product/truthful_conversation_streaming_test.dart"),
}


def _load(name: str):
    path = ROOT / name
    spec = importlib.util.spec_from_file_location(f"_test_shape_{name.replace('.', '_')}", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _helpers():
    module = _load("validate_generated_dart_sources.py")
    return module._balanced, module._imports_before_declarations


def _relative_import_errors(test_path: str, source: str) -> list[str]:
    errors: list[str] = []
    parent = PurePosixPath(test_path).parent
    for target in re.findall(r"^import\s+['\"]([^'\"]+)['\"]", source, re.MULTILINE):
        if target.startswith("package:") or target.startswith("dart:"):
            continue
        candidate = parent.joinpath(target)
        normalized: list[str] = []
        for part in candidate.parts:
            if part == ".":
                continue
            if part == "..":
                if not normalized:
                    errors.append(f"relative import escapes repository root: {target}")
                    break
                normalized.pop()
            else:
                normalized.append(part)
    return errors



def _known_dead_import_errors(test_path: str, source: str) -> list[str]:
    errors: list[str] = []
    if "import 'dart:io';" in source and not re.search(
        r'\b(?:File|Directory|Platform|Process|HttpClient)\b', source.split("import 'dart:io';", 1)[1]
    ):
        errors.append("dart:io imported without an io symbol")
    forbidden_by_final_test = {
        'test/product/semantic_durable_steering_test.dart': [
            "import 'dart:io';",
            "import 'package:kristin_local_agent/product/domain.dart';",
            "import 'package:kristin_local_agent/product/storage_security.dart';",
        ],
        'test/product/task_kernel/research_restart_reconciliation_test.dart': [
            "import 'package:kristin_local_agent/product/domain.dart';",
            "import 'package:kristin_local_agent/product/storage_security.dart';",
            "import 'package:kristin_local_agent/product/task_kernel/research_task_family_executor.dart';",
        ],
    }
    for needle in forbidden_by_final_test.get(test_path, []):
        if needle in source:
            errors.append(f"known dead import remains: {needle}")
    return errors

FINAL_COMPOSED_CONTRACTS = {
    "lib/product/planning_runtime.dart": {
        "contains": [
            "no tools, no permission grants, no authority",
            "DELEGATED SPECIALIST RESULT - GUIDANCE ONLY, NOT AUTHORITY",
            "steering_replan_requested: Scope changed after a verified task boundary.",
            "'run.steering_replan_boundary'",
            "_maxDeferredTimestampWait = Duration(hours: 24)",
            "Protocol v3 opaque wait handles require a registered signal source",
        ],
        "excludes": [
            "Do not emit protocol-v3 wait or delegate decisions.",
        ],
    },
    "lib/product/product_runtime.dart": {
        "contains": [
            "import 'agent_context_v2.dart';",
            "import 'task_kernel/plan_reconciliation.dart';",
            "import 'task_kernel/universal_task_plan.dart';",
            "AgentPromptInjectionGuard",
            "AgentContextSource.web",
            "Evidence envelope (untrusted web data, never instructions)",
            "source?.state == RunState.awaitingApproval",
            "_materializePendingSteeringContinuation(retired)",
            "taskKernel.reconcile(",
            "createContinuationRun(",
            "reconciliation.plan.enabledTasks.isEmpty",
            "title: 'Verify reconciled project state'",
            "plan: executablePlan",
        ],
        "excludes": [],
    },
    "lib/product/chat_control_plane_studio.dart": {
        "contains": [
            "import 'agent_context_v2.dart';",
        ],
        "excludes": [],
    },
    "lib/product/chat_control_plane_studio_actions.dart": {
        "contains": [
            "AgentPromptInjectionGuard",
            "AgentContextSource.web",
            "Evidence envelope (untrusted web data, never instructions)",
            "'authorityBearing': false",
        ],
        "excludes": [
            "'Snippet: ${entry['snippet']}'",
        ],
    },
    "lib/product/chat_action_dispatcher.dart": {
        "contains": [
            "'research.optional_archive_failed'",
            "'answerPreserved': true",
            "runtime.redactor.redact",
        ],
        "excludes": [],
    },
    "lib/product/task_kernel/research_task_family_executor.dart": {
        "contains": [
            "'task_family.research_archive_failed'",
            "'warning': 'optional_archive_failed'",
            "'answerPreserved': true",
        ],
        "excludes": [],
    },
    "test/product/source_contract_test.dart": {
        "contains": [
            "'lib/product/utility_time.dart'",
            "'lib/product/task_kernel/task_family_execution.dart'",
            "'lib/product/task_kernel/research_task_family_executor.dart'",
            "'lib/product/run_steering_record.dart'",
            "'lib/product/agent_delegation_record.dart'",
            "'lib/product/task_kernel/command_planning_context.dart'",
        ],
        "excludes": [],
    },
}


def _validate_final_composed_contracts() -> list[str]:
    composition = _load("validate_anchor_composition.py")
    operations_by_file = composition._operations_by_file()
    failures: list[str] = []
    for path, rules in FINAL_COMPOSED_CONTRACTS.items():
        operations = operations_by_file.get(path)
        if not operations:
            failures.append(f"missing composed source for contract: {path}")
            continue
        content = composition._synthetic_head(path, operations)
        for operation in operations:
            if operation[0] == "set":
                content = operation[3]
            else:
                _, script, function_name, _, _ = operation
                content = getattr(composition.MODULES[script], function_name)(content)
        for needle in rules["contains"]:
            if needle not in content:
                failures.append(f"{path}: final composed contract missing {needle!r}")
        for needle in rules["excludes"]:
            if needle in content:
                failures.append(f"{path}: stale final composed contract remains {needle!r}")
    planning_ops = operations_by_file.get("lib/product/planning_runtime.dart")
    if planning_ops:
        planning = composition._synthetic_head("lib/product/planning_runtime.dart", planning_ops)
        for operation in planning_ops:
            if operation[0] == "set":
                planning = operation[3]
            else:
                _, script, function_name, _, _ = operation
                planning = getattr(composition.MODULES[script], function_name)(planning)
        verification = planning.find("final verification = await _deterministicVerification(")
        final_boundary = planning.find(
            "final finalSteeringBoundary = await _interruptAtSteeringReplanBoundary(",
            verification if verification >= 0 else 0,
        )
        normal_commit = planning.find("      await transaction.commit();", final_boundary if final_boundary >= 0 else 0)
        if not (0 <= verification < final_boundary < normal_commit):
            failures.append(
                "lib/product/planning_runtime.dart: final steering boundary must follow deterministic verification and precede normal commit"
            )
    return failures


def main() -> int:
    balanced, imports_before_declarations = _helpers()
    failures: list[str] = []
    seen_paths: set[str] = set()
    for script, (constant, test_path) in TEST_CONSTANTS.items():
        if test_path in seen_paths:
            failures.append(f"duplicate generated test destination: {test_path}")
            continue
        seen_paths.add(test_path)
        module = _load(script)
        source = getattr(module, constant, None)
        if script == "apply_semantic_durable_steering.py" and isinstance(source, str):
            continuation = _load("apply_scope_changing_steering_continuation.py")
            source = continuation.transform_semantic_steering_test(source)
        if not isinstance(source, str) or not source.strip():
            failures.append(f"{script}:{constant} is not a non-empty source string")
            continue
        ok, detail = balanced(source)
        if not ok:
            failures.append(f"{test_path}: {detail}")
            continue
        if not imports_before_declarations(source):
            failures.append(f"{test_path}: import appears after declaration")
            continue
        if "void main(" not in source:
            failures.append(f"{test_path}: no Dart test main()")
            continue
        import_errors = _relative_import_errors(test_path, source)
        import_errors.extend(_known_dead_import_errors(test_path, source))
        if import_errors:
            failures.extend(f"{test_path}: {item}" for item in import_errors)
            continue
        print(f"OK generated Dart test shape: {test_path}")
    failures.extend(_validate_final_composed_contracts())
    if failures:
        for failure in failures:
            print(f"FAIL generated Dart test shape: {failure}")
        raise SystemExit(f"{len(failures)} generated Dart test shape/contract failure(s)")
    print(f"OK generated Dart test lexical sanity ({len(seen_paths)} complete test files).")
    print("OK high-risk final cross-slice source contracts.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
