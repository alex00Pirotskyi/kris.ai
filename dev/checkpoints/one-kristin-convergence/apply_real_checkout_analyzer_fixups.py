#!/usr/bin/env python3
"""Close real-checkout analyzer integration gaps after the 20 feature slices.

This is a qualification compatibility slice, not a new product capability. It
owns only direct-import closure, async test adaptation, literal escaping, and
fatal-lint hygiene exposed by the locked Flutter analyzer on the exact recovered
checkout.
"""
from __future__ import annotations

import argparse
import difflib
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def transform_planning(text: str) -> str:
    if "import 'agent_decision_v3.dart';\n" not in text:
        text = replace_once(
            text,
            "import 'agent_context_v2.dart';\n",
            "import 'agent_context_v2.dart';\nimport 'agent_decision_v3.dart';\n",
            "direct protocol-v3 decision import",
        )
    return text


def transform_product_runtime(text: str) -> str:
    universal = "import 'task_kernel/universal_task_plan.dart';\n"
    count = text.count(universal)
    if count == 2:
        first = text.find(universal)
        second = text.find(universal, first + 1)
        text = text[:second] + text[second + len(universal):]
    elif count != 1:
        raise RuntimeError(f"universal task-plan import: expected one/two anchors, found {count}")
    if "repositories.projects.get(archiveProjectId!)" in text:
        text = replace_once(
            text,
            "repositories.projects.get(archiveProjectId!)",
            "repositories.projects.get(archiveProjectId)",
            "promoted archive project id",
        )
    return text


def transform_run_steering(text: str) -> str:
    if "import 'storage_security.dart';\n" not in text:
        text = replace_once(
            text,
            "import 'run_steering_record.dart';\n",
            "import 'run_steering_record.dart';\nimport 'storage_security.dart';\n",
            "ProductException owner import",
        )
    old = "          record.state != RunSteeringRecordState.pending) continue;\n"
    if old in text:
        text = replace_once(
            text,
            old,
            "          record.state != RunSteeringRecordState.pending) {\n"
            "        continue;\n"
            "      }\n",
            "fatal-lint steering guard block",
        )
    return text


def transform_chat_actions(text: str) -> str:
    unused = (
        "    final subjects = plan == null\n"
        "        ? <String>[effectiveQuery]\n"
        "        : plan.tasks\n"
        "            .where((task) => task.phase == 'Retrieval')\n"
        "            .map((task) => task.title.replaceFirst('Obtain ', ''))\n"
        "            .toList(growable: false);\n"
        "    final queries = subjects.isEmpty ? <String>[effectiveQuery] : subjects;\n\n"
    )
    if unused in text:
        text = replace_once(text, unused, "", "obsolete direct-research queries")
    return text


def transform_blocking_test(text: str) -> str:
    old = 'contains("status = \'Reply in Chat: $question\'")'
    if old in text:
        text = replace_once(
            text, old, 'contains("status = \'Reply in Chat: \\$question\'")',
            "literal clarification source contract",
        )
    return text


def transform_failure_test(text: str) -> str:
    old = 'contains("runtime.redactor.redact(\'$failure\')")'
    if old in text:
        text = replace_once(
            text, old, 'contains("runtime.redactor.redact(\'\\$failure\')")',
            "literal failure source contract",
        )
    return text


def transform_hf_convergence_test(text: str) -> str:
    if "product/repository.dart" not in text:
        text = replace_once(
            text,
            "import 'package:kristin_local_agent/product/run_live_signals.dart';\n",
            "import 'package:kristin_local_agent/product/repository.dart';\n"
            "import 'package:kristin_local_agent/product/run_live_signals.dart';\n",
            "steering repository test import",
        )
    if "product/run_steering_record.dart" not in text:
        text = replace_once(
            text,
            "import 'package:kristin_local_agent/product/run_steering.dart';\n",
            "import 'package:kristin_local_agent/product/run_steering.dart';\n"
            "import 'package:kristin_local_agent/product/run_steering_record.dart';\n",
            "steering record test import",
        )
    if "class _MemoryRunSteeringRepository" not in text:
        helper = r'''class _MemoryRunSteeringRepository implements EntityRepository<RunSteeringRecord> {
  final Map<String, RunSteeringRecord> values = <String, RunSteeringRecord>{};

  @override
  Future<List<RunSteeringRecord>> all() async => values.values.toList();

  @override
  Future<RunSteeringRecord?> get(String id) async => values[id];

  @override
  Future<void> put(RunSteeringRecord item) async {
    values[item.id] = item;
  }

  @override
  Future<void> putAll(Iterable<RunSteeringRecord> items) async {
    for (final item in items) {
      values[item.id] = item;
    }
  }

  @override
  Future<void> remove(String id) async {
    values.remove(id);
  }

  @override
  Future<void> removeWhere(
    bool Function(RunSteeringRecord item) predicate,
  ) async {
    values.removeWhere((_, value) => predicate(value));
  }

  @override
  Future<void> replaceAll(Iterable<RunSteeringRecord> items) async {
    values
      ..clear()
      ..addEntries(items.map((item) => MapEntry(item.id, item)));
  }
}

'''
        text = replace_once(text, "void main() {\n", helper + "void main() {\n", "HF test helper")
    if "RunSteeringService(liveSignals: bus)" in text:
        text = replace_once(
            text,
            "final steering = RunSteeringService(liveSignals: bus);",
            "final steering = RunSteeringService(\n"
            "      liveSignals: bus,\n"
            "      repository: _MemoryRunSteeringRepository(),\n"
            "    );",
            "durable steering test constructor",
        )
    if "final queued = steering.queue('run-a', 'keep everything local');" in text:
        text = replace_once(
            text,
            "final queued = steering.queue('run-a', 'keep everything local');",
            "final queued = await steering.queue('run-a', 'keep everything local');",
            "async steering queue test",
        )
    if "final first = steering.takePending('run-a');\n    final second = steering.takePending('run-a');" in text:
        text = replace_once(
            text,
            "final first = steering.takePending('run-a');\n    final second = steering.takePending('run-a');",
            "final first = await steering.takePending('run-a');\n"
            "    final second = await steering.takePending('run-a');",
            "async steering pending test",
        )
    return text


def transform_memory_repo_test(text: str) -> str:
    old = "async { for (final item in items) values[item.id] = item; }"
    if old in text:
        text = replace_once(
            text,
            old,
            "async {\n"
            "    for (final item in items) {\n"
            "      values[item.id] = item;\n"
            "    }\n"
            "  }",
            "fatal-lint memory repository loop",
        )
    return text


def transform_research_execution_test(text: str) -> str:
    text = transform_memory_repo_test(text)
    if "product/crypto_utils.dart" not in text:
        text = replace_once(
            text,
            "import 'package:kristin_local_agent/product/domain.dart';\n",
            "import 'package:kristin_local_agent/product/crypto_utils.dart';\n"
            "import 'package:kristin_local_agent/product/domain.dart';\n",
            "SecretRedactor owner import",
        )
    return text


def compute(root: Path):
    transforms = {
        'lib/product/planning_runtime.dart': transform_planning,
        'lib/product/product_runtime.dart': transform_product_runtime,
        'lib/product/run_steering.dart': transform_run_steering,
        'lib/product/chat_control_plane_studio_actions.dart': transform_chat_actions,
        'test/product/blocking_clarification_contract_test.dart': transform_blocking_test,
        'test/product/chat_failure_projection_contract_test.dart': transform_failure_test,
        'test/product/hf_runner_chat_convergence_test.dart': transform_hf_convergence_test,
        'test/product/semantic_durable_steering_test.dart': transform_memory_repo_test,
        'test/product/task_kernel/research_restart_reconciliation_test.dart': transform_memory_repo_test,
        'test/product/task_kernel/research_task_family_execution_test.dart': transform_research_execution_test,
    }
    changes = {}
    for rel, transform in transforms.items():
        path = root / rel
        if not path.exists():
            raise RuntimeError(f"missing {rel}")
        before = path.read_text(encoding='utf-8')
        after = transform(before)
        changes[path] = (before, after)
    return changes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('repo', type=Path)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--diff', action='store_true')
    args = parser.parse_args()
    root = args.repo.resolve()
    changes = compute(root)
    if args.diff or not args.apply:
        for path, (before, after) in changes.items():
            if before == after:
                continue
            rel = path.relative_to(root)
            print(''.join(difflib.unified_diff(
                before.splitlines(True), after.splitlines(True),
                fromfile=f'a/{rel}', tofile=f'b/{rel}',
            )), end='')
    if args.apply:
        for path, (before, after) in changes.items():
            if before != after:
                path.write_text(after, encoding='utf-8')
        print('Applied real-checkout analyzer compatibility fixups.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
