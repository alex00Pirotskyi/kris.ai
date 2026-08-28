import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/task_kernel/plan_compiler.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

/// DELIVERABLE #8: hierarchy must survive compilation.
///
/// Previously TaskPlanRecord carried real phase/parentId/dependencies and
/// compilePlan flattened them into WorkItem.description prose, destroying
/// the structure before the Runner or the UI could reason about stages.
/// These tests pin the structure to the compiled WorkItem itself.
void main() {
  final project = ProjectRecord(
    id: 'project-hierarchy',
    name: 'Hierarchy fixture',
    rootPath: '.',
    createdAt: DateTime.utc(2026, 8, 28),
    updatedAt: DateTime.utc(2026, 8, 28),
  );

  UniversalTask task(
    String id,
    String phase, {
    String? parentId,
    Set<String> dependencies = const <String>{},
  }) =>
      UniversalTask(
        id: id,
        title: 'Task $id',
        objective: 'Objective for $id',
        instructions: 'Instructions for $id',
        phase: phase,
        parentId: parentId,
        dependencies: dependencies,
        acceptanceCriteria: <String>['$id is complete.'],
        verificationSteps: const <String>['Run the detected checks.'],
        allowedTools: const <String>{'read_file', 'inspect_file'},
      );

  UniversalTaskPlan mp3Plan() => UniversalTaskPlan(
        id: 'plan_mp3',
        specification: TaskSpecification(
          id: 'spec_mp3',
          originalRequest: 'Build an MP3 converter',
          objective: 'Build an MP3 converter',
        ),
        family: TaskFamily.software,
        route: PlanningRoute.graph,
        title: 'MP3 to URL delivery plan',
        rationale: 'Build the flow incrementally.',
        tasks: <UniversalTask>[
          task('task_001', 'Foundation'),
          task('task_002', 'UI',
              parentId: 'task_001', dependencies: <String>{'task_001'}),
          task('task_003', 'Conversion',
              parentId: 'task_001', dependencies: <String>{'task_001'}),
          task('task_004', 'UI',
              parentId: 'task_002',
              dependencies: <String>{'task_002', 'task_003'}),
          task('task_005', 'Qualification',
              parentId: 'task_001', dependencies: <String>{'task_004'}),
        ],
      );

  CompiledTaskPlan compile(
    UniversalTaskPlan plan, {
    Set<String>? selectedTaskIds,
  }) =>
      UniversalPlanCompiler(tools: ToolRegistry.standard()).compile(
        plan: plan,
        project: project,
        mode: CommandMode.build,
        request: plan.specification.originalRequest,
        selectedTaskIds: selectedTaskIds,
      );

  group('phase and parentId reach the executable WorkItem', () {
    test('every compiled item keeps its canonical phase', () {
      final compiled = compile(mp3Plan());
      final byId = <String, WorkItem>{
        for (final item in compiled.plan.items) item.id: item,
      };
      expect(byId['task_001']!.phase, 'Foundation');
      expect(byId['task_002']!.phase, 'UI');
      expect(byId['task_003']!.phase, 'Conversion');
      expect(byId['task_005']!.phase, 'Qualification');
      expect(byId.values.every((item) => item.hasHierarchy), isTrue);
    });

    test('every compiled item keeps its canonical parent', () {
      final compiled = compile(mp3Plan());
      final byId = <String, WorkItem>{
        for (final item in compiled.plan.items) item.id: item,
      };
      expect(byId['task_001']!.parentId, isNull);
      expect(byId['task_002']!.parentId, 'task_001');
      expect(byId['task_004']!.parentId, 'task_002');
      expect(byId['task_005']!.parentId, 'task_001');
    });

    test('dependencies are preserved alongside hierarchy', () {
      final compiled = compile(mp3Plan());
      final byId = <String, WorkItem>{
        for (final item in compiled.plan.items) item.id: item,
      };
      expect(byId['task_004']!.dependencies, <String>{'task_002', 'task_003'});
      // Hierarchy is grouping metadata; dependencies still decide order.
      expect(byId['task_003']!.dependencies, <String>{'task_001'});
    });

    test('the canonical plan exposes the same stage grouping the UI shows', () {
      final plan = mp3Plan();
      expect(
        plan.phases,
        <String>['Foundation', 'UI', 'Conversion', 'Qualification'],
      );
      expect(plan.roots.map((task) => task.id), <String>['task_001']);
      expect(
        plan.childrenOf('task_001').map((task) => task.id),
        <String>['task_002', 'task_003', 'task_005'],
      );
    });
  });

  group('THE INVARIANT: one plan, shown and executed', () {
    test('every executed item traces to a canonical task of the same id', () {
      final plan = mp3Plan();
      final compiled = compile(plan);
      expect(compiled.isFaithfulProjection, isTrue);
      expect(
        compiled.plan.items.map((item) => item.id).toSet(),
        plan.enabledTasks.map((task) => task.id).toSet(),
      );
      expect(
        compiled.plan.items.map((item) => item.title).toList(),
        plan.enabledTasks.map((task) => task.title).toList(),
      );
      // The compiler is a pure function of the canonical plan, so the
      // structures cannot drift.
      expect(compiled.canonical, same(plan));
    });

    test('a partial selection never leaves a dangling parent pointer', () {
      // task_004's parent (task_002) is pulled in as a dependency, but
      // selecting only task_003 excludes its parent task_001's children.
      final compiled =
          compile(mp3Plan(), selectedTaskIds: <String>{'task_003'});
      expect(compiled.plan.validate(), isEmpty);
      final ids = compiled.plan.items.map((item) => item.id).toSet();
      for (final item in compiled.plan.items) {
        if (item.parentId != null) {
          expect(ids, contains(item.parentId));
        }
      }
    });
  });

  group('backwards compatibility', () {
    test('a WorkItem without hierarchy is unchanged and omits the fields', () {
      const item = WorkItem(
        id: 'work_1',
        title: 'Flat item',
        description: 'No hierarchy here.',
        dependencies: <String>{},
        allowedTools: <String>{'read_file'},
        acceptanceCriteria: <String>['done'],
      );
      expect(item.phase, '');
      expect(item.parentId, isNull);
      expect(item.hasHierarchy, isFalse);
      // Existing evidence/golden payloads stay byte-identical: the new
      // keys are only emitted when there is hierarchy to emit.
      expect(item.toJson().containsKey('phase'), isFalse);
      expect(item.toJson().containsKey('parentId'), isFalse);
    });

    test('hierarchy round-trips through JSON when present', () {
      const item = WorkItem(
        id: 'work_2',
        title: 'Nested item',
        description: 'Has hierarchy.',
        dependencies: <String>{'work_1'},
        allowedTools: <String>{'read_file'},
        acceptanceCriteria: <String>['done'],
        phase: 'Implementation',
        parentId: 'work_1',
      );
      final restored = WorkItem.fromJson(item.toJson());
      expect(restored.phase, 'Implementation');
      expect(restored.parentId, 'work_1');
      expect(restored.hasHierarchy, isTrue);
    });

    test('ExecutionPlan rejects a dangling or self-referential parent', () {
      final dangling = ExecutionPlan(
        id: 'plan_bad',
        contractId: 'contract_bad',
        complexity: 1,
        rationale: 'invalid',
        items: const <WorkItem>[
          WorkItem(
            id: 'a',
            title: 'A',
            description: 'A',
            dependencies: <String>{},
            allowedTools: <String>{},
            acceptanceCriteria: <String>[],
            parentId: 'missing',
          ),
        ],
        createdAt: DateTime.utc(2026, 8, 28),
      );
      expect(dangling.validate().join(' '), contains('missing parent'));

      final selfParent = ExecutionPlan(
        id: 'plan_bad2',
        contractId: 'contract_bad2',
        complexity: 1,
        rationale: 'invalid',
        items: const <WorkItem>[
          WorkItem(
            id: 'a',
            title: 'A',
            description: 'A',
            dependencies: <String>{},
            allowedTools: <String>{},
            acceptanceCriteria: <String>[],
            parentId: 'a',
          ),
        ],
        createdAt: DateTime.utc(2026, 8, 28),
      );
      expect(selfParent.validate().join(' '), contains('own parent'));
    });

    test('a flat plan with no hierarchy still validates', () {
      final flat = ExecutionPlan(
        id: 'plan_flat',
        contractId: 'contract_flat',
        complexity: 1,
        rationale: 'ContractPlanner-shaped output',
        items: const <WorkItem>[
          WorkItem(
            id: 'a',
            title: 'A',
            description: 'A',
            dependencies: <String>{},
            allowedTools: <String>{},
            acceptanceCriteria: <String>[],
          ),
          WorkItem(
            id: 'b',
            title: 'B',
            description: 'B',
            dependencies: <String>{'a'},
            allowedTools: <String>{},
            acceptanceCriteria: <String>[],
          ),
        ],
        createdAt: DateTime.utc(2026, 8, 28),
      );
      expect(flat.validate(), isEmpty);
    });
  });

  test('the canonical plan round-trips to Prompt Studio and back', () {
    // Prompt Studio edits the SAME plan rather than a forked copy: the
    // projection into PlanTaskRecord and back preserves the hierarchy.
    final plan = mp3Plan();
    for (final original in plan.tasks) {
      final restored = UniversalTask.fromPlanTask(original.toPlanTask());
      expect(restored.id, original.id);
      expect(restored.phase, original.phase);
      expect(restored.parentId, original.parentId);
      expect(restored.dependencies, original.dependencies);
      expect(restored.semanticKey, original.semanticKey);
    }
  });
}
