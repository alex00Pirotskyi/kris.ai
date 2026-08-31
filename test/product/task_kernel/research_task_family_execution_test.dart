import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/repository.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/task_kernel/research_task_family_executor.dart';
import 'package:kristin_local_agent/product/task_kernel/task_family_execution.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';

class _MemoryRepository implements EntityRepository<TaskFamilyExecutionRecord> {
  final Map<String, TaskFamilyExecutionRecord> values =
      <String, TaskFamilyExecutionRecord>{};
  @override
  Future<List<TaskFamilyExecutionRecord>> all() async => values.values.toList();
  @override
  Future<TaskFamilyExecutionRecord?> get(String id) async => values[id];
  @override
  Future<void> put(TaskFamilyExecutionRecord item) async {
    values[item.id] = item;
  }

  @override
  Future<void> putAll(Iterable<TaskFamilyExecutionRecord> items) async {
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
          bool Function(TaskFamilyExecutionRecord item) predicate) async =>
      values.removeWhere((_, value) => predicate(value));
  @override
  Future<void> replaceAll(Iterable<TaskFamilyExecutionRecord> items) async {
    values
      ..clear()
      ..addEntries(items.map((item) => MapEntry(item.id, item)));
  }
}

void main() {
  test('project-free research graph persists one durable execution identity',
      () async {
    final directories = await AppDirectories.create(
        overrideRoot:
            '${Directory.systemTemp.path}/kristin-research-${newId("test")}');
    final redactor = SecretRedactor();
    final audit =
        AuditChain(File('${directories.logs.path}/audit.jsonl'), redactor);
    await audit.open();
    final events = EventJournal(File('${directories.logs.path}/events.jsonl'));
    await events.open();
    final repository = _MemoryRepository();
    final specification = TaskSpecification(
      id: 'spec-research',
      originalRequest: 'weather in Nha Trang and time in New York',
      objective: 'Answer two current facts',
      subObjectives: const <String>['weather in Nha Trang', 'time in New York'],
      capabilityHints: const <String>['research.search'],
    );
    final plan = UniversalTaskPlan(
      id: 'plan-research',
      specification: specification,
      family: TaskFamily.research,
      route: PlanningRoute.compact,
      title: 'Research',
      rationale: 'fixture',
      tasks: const <UniversalTask>[
        UniversalTask(
            id: 'root',
            title: 'Answer',
            objective: 'Answer',
            instructions: 'Coordinate',
            phase: 'Research',
            acceptanceCriteria: <String>['Grounded'],
            verificationSteps: <String>['Verify'],
            requiredCapabilities: <String>{'research.search'},
            hidden: true),
        UniversalTask(
            id: 'r1',
            title: 'Obtain weather in Nha Trang',
            objective: 'weather',
            instructions: 'search',
            phase: 'Retrieval',
            parentId: 'root',
            acceptanceCriteria: <String>['Grounded'],
            verificationSteps: <String>['Verify'],
            requiredCapabilities: <String>{'research.search'},
            hidden: true),
        UniversalTask(
            id: 'r2',
            title: 'Obtain time in New York',
            objective: 'time',
            instructions: 'search',
            phase: 'Retrieval',
            parentId: 'root',
            acceptanceCriteria: <String>['Grounded'],
            verificationSteps: <String>['Verify'],
            requiredCapabilities: <String>{'research.search'},
            hidden: true),
        UniversalTask(
            id: 'verify',
            title: 'Verify',
            objective: 'verify',
            instructions: 'verify',
            phase: 'Verification',
            parentId: 'root',
            dependencies: <String>{'r1', 'r2'},
            acceptanceCriteria: <String>['Grounded'],
            verificationSteps: <String>['Verify'],
            requiredCapabilities: <String>{'research.search'},
            hidden: true),
        UniversalTask(
            id: 'synth',
            title: 'Synthesize',
            objective: 'answer',
            instructions: 'answer',
            phase: 'Synthesis',
            parentId: 'root',
            dependencies: <String>{'verify'},
            acceptanceCriteria: <String>['Answer'],
            verificationSteps: <String>['Verify'],
            requiredCapabilities: <String>{'research.search'},
            hidden: true),
      ],
    );
    var searches = 0;
    final result = await ResearchTaskFamilyExecutor(
            repository: repository, events: events, audit: audit)
        .execute(
      plan: plan,
      request: specification.originalRequest,
      search: (query) async {
        searches += 1;
        return <Map<String, String>>[
          {
            'title': query,
            'url': 'https://example.com/$searches',
            'description': 'fixture'
          }
        ];
      },
      fetch: (url) async => <String, String>{
        'title': 'fixture',
        'url': url,
        'contentHash': List<String>.filled(64, 'a').join(),
        'fetchedAt': DateTime.now().toUtc().toIso8601String(),
        'excerpt': 'grounded fixture'
      },
      synthesize: (request, evidence) async =>
          'Grounded answer from ${evidence.length} sources.',
    );
    expect(searches, 2);
    expect(result.execution.projectId, isNull);
    expect(result.execution.state, TaskFamilyExecutionState.succeeded);
    expect(repository.values, hasLength(1));
    expect(
        result.execution.tasks
            .every((task) => task.state == TaskFamilyTaskState.succeeded),
        isTrue);
    expect(result.evidence, hasLength(2));
    await events.close();
  });
}
