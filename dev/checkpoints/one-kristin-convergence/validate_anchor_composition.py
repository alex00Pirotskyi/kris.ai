#!/usr/bin/env python3
"""Synthetic cross-slice source-anchor composition validator.

This is stronger than Python syntax/static-contract checks but deliberately
weaker than Dart compilation. It records every guarded source replacement,
constructs a synthetic recovered-head surface with the same anchor cardinality,
then runs the real transformer functions in the exact bundle order.

Why this exists: individually valid guarded transformers can still conflict if
slice N rewrites an anchor that slice N+1 expects. This validator catches that
class of packaging defect without claiming to replace a real checkout.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent

ORDER = [
    'apply_one_kristin_state_convergence.py',
    'apply_advanced_same_conversation.py',
    'apply_semantic_slash_understanding.py',
    'apply_blocking_clarification_loop.py',
    'apply_collision_safe_target_resolution.py',
    'apply_truthful_conversation_streaming.py',
    'apply_deterministic_utility_time.py',
    'apply_project_free_research_execution.py',
    'apply_semantic_durable_steering.py',
    'apply_protocol_v3_timestamp_wait.py',
    'apply_bounded_protocol_v3_delegate.py',
    'apply_scope_changing_steering_continuation.py',
    'apply_idle_steering_continuation.py',
    'apply_research_restart_reconciliation.py',
    'apply_research_optional_archive_guard.py',
    'apply_research_archive_degradation.py',
    'apply_delegate_recovery_qualification.py',
    'apply_continuation_handoff_activity_projection.py',
    'apply_authority_convergence_qualification.py',
    'apply_human_readable_failure_projection.py',
]

TRANSFORMS = {
    ORDER[0]: {
        'lib/product/kristin_conversation_session.dart': 'transform_session',
        'lib/product/chat_control_plane_studio.dart': 'transform_studio',
        'test/product/kristin_conversation_session_test.dart': 'transform_test',
    },
    ORDER[1]: {
        'lib/product/chat_control_plane_studio_actions.dart': 'caller',
        'lib/product/chat_studio.dart': 'studio',
    },
    ORDER[2]: {
        'lib/product/task_kernel/task_understanding.dart': 'transform_understanding',
        'lib/product/task_kernel/task_kernel.dart': 'transform_kernel',
    },
    ORDER[3]: {
        'lib/product/kristin_conversation_session.dart': 'session',
        'lib/product/task_kernel/task_understanding.dart': 'understanding',
        'lib/product/task_kernel/task_kernel.dart': 'kernel',
        'lib/product/chat_control_plane_studio.dart': 'studio',
        'lib/product/chat_control_plane_studio_actions.dart': 'actions',
        'lib/product/chat_control_plane_studio_view.dart': 'view',
    },
    ORDER[4]: {'lib/product/chat_control_plane.dart': 'compiler'},
    ORDER[5]: {
        'lib/product/kristin_conversation_session.dart': 'session',
        'lib/product/chat_control_plane_studio_actions.dart': 'actions',
        'lib/product/chat_control_plane_studio_view.dart': 'view',
    },
    ORDER[6]: {
        'pubspec.yaml': 'pubspec',
        'lib/product/chat_control_plane.dart': 'control_plane',
        'lib/product/chat_control_plane_studio.dart': 'studio',
        'lib/product/chat_control_plane_studio_actions.dart': 'actions',
        'test/product/source_contract_test.dart': 'source_contract',
    },
    ORDER[7]: {
        'lib/product/storage_security.dart': 'transform_storage',
        'lib/product/product_runtime.dart': 'transform_runtime',
        'lib/product/chat_control_plane_studio.dart': 'transform_studio',
        'lib/product/chat_control_plane_studio_actions.dart': 'transform_actions',
        'test/product/source_contract_test.dart': 'transform_source_contract',
    },
    ORDER[8]: {
        'lib/product/task_kernel/task_specification.dart': 'transform_task_spec',
        'lib/product/storage_security.dart': 'transform_storage',
        'lib/product/product_runtime.dart': 'transform_runtime',
        'lib/product/planning_runtime.dart': 'transform_planning',
        'test/product/source_contract_test.dart': 'transform_source_contract',
    },
    ORDER[9]: {
        'lib/product/agent_deferred_interaction.dart': 'deferred_store',
        'lib/product/planning_runtime.dart': 'planning',
        'lib/product/product_runtime.dart': 'runtime',
    },
    ORDER[10]: {
        'lib/product/storage_security.dart': 'storage',
        'lib/product/planning_runtime.dart': 'planning',
        'test/product/source_contract_test.dart': 'source_contract',
    },
    ORDER[11]: {
        'lib/product/task_kernel/task_specification.dart': 'transform_task_spec',
        'lib/product/run_steering_record.dart': 'transform_record',
        'lib/product/run_steering.dart': 'transform_steering',
        'lib/product/storage_security.dart': 'transform_storage',
        'lib/product/planning_runtime.dart': 'transform_planning',
        'lib/product/product_runtime.dart': 'transform_runtime',
        'test/product/semantic_durable_steering_test.dart': 'transform_semantic_steering_test',
        'test/product/source_contract_test.dart': 'transform_source_contract',
    },
    ORDER[12]: {
        'lib/product/planning_runtime.dart': 'transform_planning',
        'lib/product/product_runtime.dart': 'transform_runtime',
    },
    ORDER[13]: {
        'lib/product/task_kernel/task_family_execution.dart': 'transform_record',
        'lib/product/task_kernel/research_task_family_executor.dart': 'transform_executor',
        'lib/product/product_runtime.dart': 'transform_runtime',
    },
    ORDER[14]: {'lib/product/chat_action_dispatcher.dart': 'transform'},
    ORDER[15]: {
        'lib/product/chat_action_dispatcher.dart': 'transform_dispatcher',
        'lib/product/task_kernel/research_task_family_executor.dart': 'transform_executor',
    },
    ORDER[16]: {
        'lib/product/agent_delegation_record.dart': 'transform_record',
        'lib/product/planning_runtime.dart': 'transform_planning',
        'lib/product/product_runtime.dart': 'transform_runtime',
    },
    ORDER[17]: {
        'lib/product/kristin_conversation_session.dart': 'transform_session',
        'lib/product/product_runtime.dart': 'transform_runtime',
        'lib/product/chat_control_plane_studio.dart': 'transform_studio',
        'lib/product/chat_control_plane_studio_view.dart': 'transform_view',
    },
    ORDER[19]: {
        'lib/product/chat_control_plane_studio.dart': 'transform_studio',
        'lib/product/chat_control_plane_studio_actions.dart': 'transform_actions',
        'lib/product/chat_control_plane_studio_view.dart': 'transform_view',
    },
}

# Whole-file creations/replacements that later slices intentionally transform.
SETS = {
    ORDER[7]: {
        'lib/product/task_kernel/task_family_execution.dart': 'RECORD_SOURCE',
        'lib/product/task_kernel/research_task_family_executor.dart': 'EXECUTOR_SOURCE',
    },
    ORDER[8]: {
        # run_steering.dart exists on the recovered head and is deliberately
        # replaced wholesale; the record/test below are new files.
        'lib/product/run_steering.dart': 'STEERING_SOURCE',
        'lib/product/run_steering_record.dart': 'RECORD_SOURCE',
        'test/product/semantic_durable_steering_test.dart': 'TEST_SOURCE',
    },
    ORDER[10]: {'lib/product/agent_delegation_record.dart': 'RECORD_SOURCE'},
    ORDER[11]: {'lib/product/task_kernel/command_planning_context.dart': 'CONTEXT_SOURCE'},
}


def _load(script: str):
    path = ROOT / script
    spec = importlib.util.spec_from_file_location(
        f'_composition_{script.replace(".", "_")}', path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f'cannot import {script}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULES = {name: _load(name) for name in ORDER}


def _record_replacements(module, function_name: str):
    # Semantic steering appends TaskSpecificationPatch rather than calling a
    # replacement helper. Treat the appended source as generated text.
    if (
        function_name == 'transform_task_spec'
        and hasattr(module, 'PATCH_SOURCE')
        and 'semantic_durable_steering' in str(module.__file__)
    ):
        return [], ('append', module.PATCH_SOURCE + '\n')

    helper = next(
        (name for name in ('rep', 'replace_once', 'replace_count') if hasattr(module, name)),
        None,
    )
    if helper is None:
        return [], None

    captured = []
    original = getattr(module, helper)

    def record(source, old, new, *args, **kwargs):
        expected = kwargs.get('expected', kwargs.get('count', 1))
        # replace_count uses expected as a keyword; rep variants may use count.
        try:
            expected = int(expected)
        except Exception:
            expected = 1
        captured.append((old, new, expected))
        return source

    setattr(module, helper, record)
    dummy = 'DUMMY\n'
    if 'scope_changing_steering_continuation' in str(module.__file__) and function_name == 'transform_runtime':
        # That transform has a direct marker guard between replacement calls.
        dummy += (
            "    if (existing == null) {\n"
            "      await repositories.commands.put(prepared);\n"
            "      await audit.append('task_kernel.compiled', prepared.id, <String, dynamic>{\n"
        )
    try:
        getattr(module, function_name)(dummy)
    except Exception:
        # Some functions have direct source-shape guards after the replacements
        # already captured above. Their additional anchors are added explicitly
        # in _manual_seed below and are then exercised by the real transform.
        pass
    finally:
        setattr(module, helper, original)
    return captured, None


def _manual_seed(path: str) -> list[str]:
    if path == 'lib/product/planning_runtime.dart':
        # The scope-continuation slice inserts its final boundary into an
        # untouched recovered-head verification/commit region. Seed that
        # region explicitly so the synthetic model can prove ordering.
        return [
            "      control.cancellation.throwIfCancelled();\n"
            "      if (const <CommandMode>{\n"
            "        CommandMode.build,\n"
            "        CommandMode.fix,\n"
            "      }.contains(run.command.contract.mode)) {\n"
            "        final verification = await _deterministicVerification(\n"
            "          run: run,\n"
            "          project: project,\n"
            "          boundary: boundary,\n"
            "          transaction: transaction,\n"
            "          control: control,\n"
            "          leaseOwner: leaseOwner,\n"
            "        );\n"
            "        run = verification.run;\n"
            "        if (!verification.passed) {\n"
            "          throw ProductException(\n"
            "            'verification_failed',\n"
            "            'Deterministic project verification failed.',\n"
            "          );\n"
            "        }\n"
            "      }\n"
            "      await transaction.commit();\n"
            "      run = run.copyWith(\n"
            "        state: RunState.succeeded,\n"
        ]
    if path != 'lib/product/product_runtime.dart':
        return []
    # apply_scope_changing_steering_continuation.transform_runtime checks the
    # first marker directly and reaches the remaining rep() calls only after
    # that guard. Seed those exact recovered-head shapes into the simulation.
    return [
        "    if (existing == null) {\n"
        "      await repositories.commands.put(prepared);\n"
        "      await audit.append('task_kernel.compiled', prepared.id, <String, dynamic>{\n",
        "    return KernelPreparedPlan(\n"
        "      command: command,\n"
        "      canonical: result.plan,\n",
        "  Future<RunSteeringInstruction> steerRun(String runId, String text) =>\n"
        "      runs.queueSteering(runId, text);\n",
        "  Future<PromptStudioDraft> generatePromptDraft({\n",
    ]


def _operations_by_file():
    result = {}
    for script in ORDER:
        module = MODULES[script]
        for path, function_name in TRANSFORMS.get(script, {}).items():
            replacements, special = _record_replacements(module, function_name)
            result.setdefault(path, []).append(
                ('transform', script, function_name, replacements, special)
            )
        for path, constant_name in SETS.get(script, {}).items():
            result.setdefault(path, []).append(
                ('set', script, constant_name, getattr(module, constant_name))
            )
    return result


def _synthetic_head(path: str, operations) -> str:
    generated: list[str] = []
    candidates: list[tuple[str, int]] = []
    for operation in operations:
        if operation[0] == 'set':
            generated = [operation[3]]
            continue
        _, _, _, replacements, special = operation
        if special and special[0] == 'append':
            generated.append(special[1])
            continue
        for old, new, expected in replacements:
            if not any(old in value for value in generated):
                candidates.append((old, expected))
            if new:
                generated.append(new)

    # If the file is created/replaced before any transform touches it, there
    # is no recovered-head source to seed for later anchors.
    if operations and operations[0][0] == 'set':
        candidates = []

    for value in _manual_seed(path):
        candidates.append((value, 1))

    # Preserve only maximal anchors. If one guarded anchor is contained inside
    # a larger recovered-head anchor, seeding both would create a false second
    # match that the real file does not have.
    unique: list[tuple[str, int]] = []
    for value, expected in candidates:
        prior = next((i for i, (text, _) in enumerate(unique) if text == value), None)
        if prior is None:
            unique.append((value, expected))
        elif expected > unique[prior][1]:
            unique[prior] = (value, expected)
    maximal = [
        (value, expected)
        for value, expected in unique
        if not any(value != other and value in other for other, _ in unique)
    ]
    content = '\n/* synthetic recovered-head split */\n'.join(value for value, _ in maximal)

    # Honor exact cardinality guards (the real source intentionally has two
    # reset sites in a couple of cases).
    for value, expected in unique:
        if any(value in generated_value for generated_value in generated):
            continue
        while content.count(value) < expected:
            content += '\n/* synthetic duplicate */\n' + value

    if path == 'lib/product/task_kernel/task_specification.dart' and not content.rstrip().endswith('}'):
        content += '\n}\n'
    return content


def main() -> int:
    operations_by_file = _operations_by_file()
    failures = []
    for path, operations in operations_by_file.items():
        content = _synthetic_head(path, operations)
        try:
            for operation in operations:
                if operation[0] == 'set':
                    content = operation[3]
                    continue
                _, script, function_name, _, _ = operation
                content = getattr(MODULES[script], function_name)(content)
            print(f'OK composed anchors: {path} ({len(operations)} slice touch(es))')
        except Exception as error:
            failures.append((path, operation, error))
            print(
                f'FAIL composed anchors: {path} at {operation[1]}:{operation[2]}: {error}'
            )
    if failures:
        raise SystemExit(
            f'{len(failures)} synthetic cross-slice composition failure(s); '
            'do not package until they are resolved.'
        )
    print(
        'OK synthetic cross-slice composition. '
        'NOTE: this validates guarded source-anchor compatibility, not Dart/Flutter compilation.'
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
