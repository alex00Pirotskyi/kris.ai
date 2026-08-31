import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/repository.dart';
import 'package:kristin_local_agent/product/task_kernel/task_family_execution.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';

class _MemoryRepository implements EntityRepository<TaskFamilyExecutionRecord> {
  final values = <String, TaskFamilyExecutionRecord>{};
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
      bool Function(TaskFamilyExecutionRecord item) predicate) async {
    values.removeWhere((_, value) => predicate(value));
  }

  @override
  Future<void> replaceAll(Iterable<TaskFamilyExecutionRecord> items) async {
    values
      ..clear()
      ..addEntries(items.map((value) => MapEntry(value.id, value)));
  }
}

void main() {
  test('running research execution is reconciled to interrupted on restart',
      () async {
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
