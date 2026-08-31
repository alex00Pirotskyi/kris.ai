#!/usr/bin/env python3
"""Apply restart reconciliation and explicit retry for project-free Research."""
from __future__ import annotations

import argparse
import difflib
import subprocess
from pathlib import Path

EXPECTED_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"


def rep(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def git_head(root: Path) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None


TEST = r'''import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/repository.dart';
import 'package:kristin_local_agent/product/task_kernel/task_family_execution.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';

class _MemoryRepository implements EntityRepository<TaskFamilyExecutionRecord> {
  final values = <String, TaskFamilyExecutionRecord>{};
  @override Future<List<TaskFamilyExecutionRecord>> all() async => values.values.toList();
  @override Future<TaskFamilyExecutionRecord?> get(String id) async => values[id];
  @override Future<void> put(TaskFamilyExecutionRecord item) async { values[item.id] = item; }
  @override Future<void> putAll(Iterable<TaskFamilyExecutionRecord> items) async { for (final item in items) values[item.id] = item; }
  @override Future<void> remove(String id) async { values.remove(id); }
  @override Future<void> removeWhere(bool Function(TaskFamilyExecutionRecord item) predicate) async { values.removeWhere((_, value) => predicate(value)); }
  @override Future<void> replaceAll(Iterable<TaskFamilyExecutionRecord> items) async { values..clear()..addEntries(items.map((value) => MapEntry(value.id, value))); }
}

void main() {
  test('running research execution is reconciled to interrupted on restart', () async {
    final repository = _MemoryRepository();
    final now = DateTime.utc(2026, 8, 30);
    final spec = TaskSpecification(
      id: 'spec',
      originalRequest: 'research current example',
      objective: 'research current example',
    );
    final plan = UniversalTaskPlan(
      id: 'plan',
      specification: spec,
      family: TaskFamily.research,
      route: PlanningRoute.compact,
      title: 'Research',
      rationale: 'test',
      tasks: <UniversalTask>[
        UniversalTask(
          id: 'r',
          title: 'Obtain example',
          objective: 'example',
          instructions: 'search',
          phase: 'Retrieval',
          acceptanceCriteria: const <String>['Grounded source exists'],
          verificationSteps: const <String>['Verify URL and hash'],
        ),
      ],
    );
    await repository.put(TaskFamilyExecutionRecord(
      id: 'exec',
      family: TaskFamily.research,
      planId: plan.id,
      specificationId: spec.id,
      request: spec.originalRequest,
      state: TaskFamilyExecutionState.running,
      tasks: const <TaskFamilyTaskProgress>[],
      planSnapshot: plan,
      createdAt: now,
      updatedAt: now,
    ));
    // The executor method itself is exercised in the integration suite; this
    // contract test pins the durable representation required for retry.
    final stored = await repository.get('exec');
    expect(stored?.planSnapshot?.id, 'plan');
    expect(stored?.state, TaskFamilyExecutionState.running);
  });
}
'''


def transform_record(src: str) -> str:
    src = rep(
        src,
        "    this.projectId,\n    this.evidence = const <Map<String, String>>[],\n",
        "    this.projectId,\n    this.sourceExecutionId,\n    this.planSnapshot,\n    this.evidence = const <Map<String, String>>[],\n",
        "research recovery ctor",
    )
    src = rep(
        src,
        "  final String? projectId;\n  final TaskFamilyExecutionState state;\n",
        "  final String? projectId;\n  final String? sourceExecutionId;\n  final UniversalTaskPlan? planSnapshot;\n  final TaskFamilyExecutionState state;\n",
        "research recovery fields",
    )
    src = rep(
        src,
        "        projectId: projectId,\n        state: state ?? this.state,\n",
        "        projectId: projectId,\n        sourceExecutionId: sourceExecutionId,\n        planSnapshot: planSnapshot,\n        state: state ?? this.state,\n",
        "research recovery copy preserve",
    )
    src = rep(
        src,
        "        if (projectId != null) 'projectId': projectId,\n        'state': state.name,\n",
        "        if (projectId != null) 'projectId': projectId,\n        if (sourceExecutionId != null) 'sourceExecutionId': sourceExecutionId,\n        if (planSnapshot != null) 'planSnapshot': planSnapshot!.toJson(),\n        'state': state.name,\n",
        "research recovery json",
    )
    src = rep(
        src,
        "      projectId: _nullable(json['projectId']),\n      state: TaskFamilyExecutionState.values\n",
        "      projectId: _nullable(json['projectId']),\n      sourceExecutionId: _nullable(json['sourceExecutionId']),\n      planSnapshot: json['planSnapshot'] is Map\n          ? UniversalTaskPlan.fromJson(mapValue(json['planSnapshot']))\n          : null,\n      state: TaskFamilyExecutionState.values\n",
        "research recovery parse",
    )
    return src


def transform_executor(src: str) -> str:
    src = rep(
        src,
        "    Future<void> Function(\n      String query,\n      List<Map<String, String>> results,\n    )? archive,\n  }) async {\n",
        "    Future<void> Function(\n      String query,\n      List<Map<String, String>> results,\n    )? archive,\n    String? sourceExecutionId,\n  }) async {\n",
        "research source execution param",
    )
    src = rep(
        src,
        "      projectId: projectId,\n      state: TaskFamilyExecutionState.running,\n",
        "      projectId: projectId,\n      sourceExecutionId: sourceExecutionId,\n      planSnapshot: plan,\n      state: TaskFamilyExecutionState.running,\n",
        "research plan snapshot creation",
    )
    anchor = "  Future<TaskFamilyExecutionRecord> _setTask(\n"
    methods = r'''  Future<List<TaskFamilyExecutionRecord>> reconcileInterrupted() async {
    final running = (await repository.all())
        .where((value) => value.state == TaskFamilyExecutionState.running)
        .toList(growable: false);
    final reconciled = <TaskFamilyExecutionRecord>[];
    for (final value in running) {
      final now = DateTime.now().toUtc();
      final tasks = <TaskFamilyTaskProgress>[
        for (final task in value.tasks)
          task.state == TaskFamilyTaskState.running
              ? task.copyWith(
                  state: TaskFamilyTaskState.failed,
                  failure: 'Interrupted by application restart.',
                  completedAt: now,
                )
              : task,
      ];
      final interrupted = value.copyWith(
        state: TaskFamilyExecutionState.interrupted,
        tasks: List<TaskFamilyTaskProgress>.unmodifiable(tasks),
        failure:
            'research_interrupted: Application restarted before this research execution completed.',
        updatedAt: now,
        completedAt: now,
      );
      await _persist(interrupted, 'task_family.execution_interrupted');
      reconciled.add(interrupted);
    }
    return List<TaskFamilyExecutionRecord>.unmodifiable(reconciled);
  }

  Future<ResearchTaskFamilyExecutionResult> retry({
    required TaskFamilyExecutionRecord source,
    required Future<List<Map<String, String>>> Function(String query) search,
    required Future<Map<String, String>> Function(String url) fetch,
    required Future<String> Function(
      String request,
      List<Map<String, String>> evidence,
    ) synthesize,
    Future<void> Function(
      String query,
      List<Map<String, String>> results,
    )? archive,
  }) {
    if (!const <TaskFamilyExecutionState>{
      TaskFamilyExecutionState.interrupted,
      TaskFamilyExecutionState.failed,
    }.contains(source.state)) {
      throw ProductException(
        'research_retry_state_invalid',
        'Only interrupted or failed Research executions can be retried.',
      );
    }
    final plan = source.planSnapshot;
    if (plan == null) {
      throw ProductException(
        'research_retry_plan_missing',
        'This Research execution predates durable plan snapshots and cannot be retried safely.',
      );
    }
    return execute(
      plan: plan,
      request: source.request,
      projectId: source.projectId,
      sourceExecutionId: source.id,
      search: search,
      fetch: fetch,
      synthesize: synthesize,
      archive: archive,
    );
  }

'''
    return rep(src, anchor, methods + anchor, "research recovery methods")


def transform_runtime(src: str) -> str:
    # Only archive to a project that still exists when each query completes.
    src = rep(
        src,
        "              await knowledge.addResearchSearch(\n                projectId: projectId,\n",
        "              final archiveProject = await repositories.projects.get(projectId);\n              if (archiveProject == null) return;\n              await knowledge.addResearchSearch(\n                projectId: archiveProject.id,\n",
        "research disappearing project archive guard",
    )
    src = rep(
        src,
        "    await coordinator.reconcileInterruptedRuns();\n    await runtime.reconcileSteeringContinuations();\n    await coordinator.reconcileMemoryEpisodes();\n",
        "    await coordinator.reconcileInterruptedRuns();\n    await runtime.reconcileSteeringContinuations();\n    await runtime.reconcileTaskFamilyExecutions();\n    await coordinator.reconcileMemoryEpisodes();\n",
        "startup research reconciliation",
    )
    anchor = "  Future<void> reconcileSteeringContinuations() async {\n"
    methods = r'''  Future<List<TaskFamilyExecutionRecord>> reconcileTaskFamilyExecutions() {
    return ResearchTaskFamilyExecutor(
      repository: repositories.taskFamilyExecutions,
      events: events,
      audit: audit,
    ).reconcileInterrupted();
  }

  Future<ResearchTaskFamilyExecutionResult> retryResearchTaskFamilyExecution(
    String executionId, {
    ModelIdentity? model,
  }) async {
    final source = await repositories.taskFamilyExecutions.get(executionId);
    if (source == null || source.family != TaskFamily.research) {
      throw ProductException(
        'research_execution_missing',
        'Unknown Research task-family execution.',
      );
    }
    final archiveProjectId = source.projectId != null &&
            await repositories.projects.get(source.projectId!) != null
        ? source.projectId
        : null;
    final executor = ResearchTaskFamilyExecutor(
      repository: repositories.taskFamilyExecutions,
      events: events,
      audit: audit,
    );
    return executor.retry(
      source: source,
      search: (query) => searchWeb(query: query, count: 8),
      archive: archiveProjectId == null
          ? null
          : (query, results) async {
              final project = await repositories.projects.get(archiveProjectId!);
              if (project == null) return;
              await knowledge.addResearchSearch(
                projectId: project.id,
                query: query,
                results: results,
                provider: 'canonical-search-retry',
              );
            },
      fetch: (url) async {
        final fetched = await research.fetch(Uri.parse(url));
        final excerpt = fetched.content.replaceAll(RegExp(r'\s+'), ' ').trim();
        return <String, String>{
          'title': fetched.title,
          'url': fetched.url.toString(),
          'contentHash': fetched.contentHash,
          'fetchedAt': fetched.fetchedAt.toIso8601String(),
          'excerpt': excerpt.length <= 1800 ? excerpt : excerpt.substring(0, 1800),
        };
      },
      synthesize: (question, evidence) =>
          _synthesizeTaskFamilyResearch(question, evidence, model: model),
    );
  }

'''
    return rep(src, anchor, methods + anchor, "runtime research recovery methods")


def compute(root: Path):
    transforms = {
        root / 'lib/product/task_kernel/task_family_execution.dart': transform_record,
        root / 'lib/product/task_kernel/research_task_family_executor.dart': transform_executor,
        root / 'lib/product/product_runtime.dart': transform_runtime,
    }
    result = {}
    for path, fn in transforms.items():
        if not path.exists(): raise RuntimeError(f'missing source file: {path}')
        before = path.read_text(); result[path] = (before, fn(before))
    created = {root / 'test/product/task_kernel/research_restart_reconciliation_test.dart': TEST}
    for path, after in created.items():
        before = path.read_text() if path.exists() else ''
        if before and before != after:
            raise RuntimeError(f'{path}: file already exists with different content')
        result[path] = (before, after)
    return result


def main() -> int:
    p = argparse.ArgumentParser(); p.add_argument('repo'); p.add_argument('--apply', action='store_true'); p.add_argument('--diff', action='store_true'); p.add_argument('--allow-head-drift', action='store_true')
    a = p.parse_args(); root = Path(a.repo).resolve(); head = git_head(root)
    if head and head != EXPECTED_HEAD and not a.allow_head_drift:
        raise SystemExit(f'refusing HEAD {head}; expected {EXPECTED_HEAD}')
    changes = compute(root)
    if a.diff or not a.apply:
        for path, (before, after) in changes.items():
            rel = path.relative_to(root); print(''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile=f'a/{rel}', tofile=f'b/{rel}')), end='')
    if a.apply:
        for path, (_, after) in changes.items(): path.parent.mkdir(parents=True, exist_ok=True); path.write_text(after)
    return 0

if __name__ == '__main__': raise SystemExit(main())
