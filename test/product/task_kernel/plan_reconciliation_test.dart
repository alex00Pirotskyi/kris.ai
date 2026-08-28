import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/task_kernel/plan_reconciliation.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';

/// SCENARIO L / DELIVERABLE #11.
///
///     ✓ inspect project
///     ✓ define architecture
///     ○ implement Firebase storage
///     ○ build result UI
///     ○ tests
///
///     user: "don't use Firebase"
///
/// Regenerating the whole plan throws away two completed, verified,
/// still-valid tasks. These tests pin the alternative: preserve what is
/// still valid, invalidate explicitly what the new constraint
/// contradicts, and never erase completed evidence-backed work silently.
void main() {
  const reconciler = PlanReconciler();

  UniversalTask task(
    String id,
    String title, {
    String phase = 'Implementation',
    Set<String> dependencies = const <String>{},
    String? parentId,
  }) =>
      UniversalTask(
        id: id,
        title: title,
        objective: title,
        instructions: title,
        phase: phase,
        parentId: parentId,
        dependencies: dependencies,
        acceptanceCriteria: <String>['$title is complete.'],
        verificationSteps: const <String>['Run the detected checks.'],
      );

  TaskSpecification specification({
    List<SpecificationClaim> hardConstraints = const <SpecificationClaim>[],
  }) =>
      TaskSpecification(
        id: 'spec_app',
        originalRequest: 'Build the app',
        objective: 'Build the app',
        hardConstraints: hardConstraints,
      );

  UniversalTaskPlan planWith(
    List<UniversalTask> tasks, {
    TaskSpecification? spec,
    String id = 'plan_1',
  }) =>
      UniversalTaskPlan(
        id: id,
        specification: spec ?? specification(),
        family: TaskFamily.software,
        route: PlanningRoute.graph,
        title: 'App plan',
        rationale: 'Incremental delivery.',
        tasks: tasks,
      );

  UniversalTaskPlan originalPlan() => planWith(<UniversalTask>[
        task('t1', 'Inspect project', phase: 'Inspect'),
        task('t2', 'Define architecture',
            phase: 'Design', dependencies: <String>{'t1'}),
        task('t3', 'Implement Firebase storage', dependencies: <String>{'t2'}),
        task('t4', 'Build result UI', dependencies: <String>{'t2'}),
        task('t5', 'Write tests',
            phase: 'Qualification', dependencies: <String>{'t3', 't4'}),
      ]);

  /// The replan: same work, minus Firebase, plus a Firebase-free store.
  UniversalTaskPlan revisedPlan() => planWith(
        <UniversalTask>[
          task('r1', 'Inspect project', phase: 'Inspect'),
          task('r2', 'Define architecture',
              phase: 'Design', dependencies: <String>{'r1'}),
          task('r3', 'Implement local storage', dependencies: <String>{'r2'}),
          task('r4', 'Build result UI', dependencies: <String>{'r2'}),
          task('r5', 'Write tests',
              phase: 'Qualification', dependencies: <String>{'r3', 'r4'}),
        ],
        spec: specification(
          hardConstraints: <SpecificationClaim>[
            const SpecificationClaim.stated('Do not use Firebase.'),
          ],
        ),
        id: 'plan_2',
      );

  group('completed work is preserved across a replan', () {
    late PlanReconciliationResult result;

    setUp(() {
      final previous = originalPlan();
      result = reconciler.reconcile(
        previous: previous,
        revised: revisedPlan(),
        completed: <CompletedTaskRecord>[
          CompletedTaskRecord.of(
            previous.tasks.firstWhere((task) => task.id == 't1'),
            evidence: <String, dynamic>{'runId': 'run_1'},
          ),
          CompletedTaskRecord.of(
            previous.tasks.firstWhere((task) => task.id == 't2'),
            evidence: <String, dynamic>{'runId': 'run_1'},
          ),
        ],
      );
    });

    test('the two finished tasks are kept, not redone', () {
      final preservedTitles =
          result.preserved.map((item) => item.title).toSet();
      expect(
        preservedTitles,
        containsAll(<String>['Inspect project', 'Define architecture']),
      );
      // Preserved work is carried as satisfied rather than re-queued.
      for (final change in result.preserved) {
        final task =
            result.plan.tasks.firstWhere((item) => item.id == change.taskId);
        expect(task.enabled, isFalse, reason: '${task.title} must not rerun');
      }
    });

    test('semantic identity survives a change of generated task id', () {
      // The revised plan renamed t1 -> r1. Reconciliation still matched
      // it, because identity is content, not the generator's counter.
      final inspect = result.reconciliations
          .firstWhere((item) => item.title == 'Inspect project');
      expect(inspect.taskId, 'r1');
      expect(inspect.outcome, TaskReconciliationOutcome.preserved);
      expect(inspect.reason, contains('evidence'));
    });

    test('the Firebase task is replaced and the unrelated work carries on', () {
      expect(
        result.added.map((item) => item.title),
        contains('Implement local storage'),
      );
      expect(
        result.removed.map((item) => item.title),
        contains('Implement Firebase storage'),
      );
      // Build result UI and Write tests were neither completed nor
      // contradicted, so they carry forward as remaining work.
      final carried = result.reconciliations
          .where((item) => item.outcome == TaskReconciliationOutcome.carried)
          .map((item) => item.title)
          .toSet();
      expect(carried, containsAll(<String>['Build result UI', 'Write tests']));
    });

    test('the reconciled graph still validates', () {
      expect(result.plan.validate(), isEmpty);
      expect(result.plan.revision, 2);
      expect(result.plan.previousPlanId, 'plan_1');
    });

    test('the change is summarized for the user rather than silent', () {
      expect(result.summary, contains('2 completed task(s) kept'));
      expect(result.summary, contains('1 new task(s)'));
      expect(result.summary, contains('1 task(s) dropped'));
    });
  });

  group('work the new constraint contradicts is explicitly invalidated', () {
    test('a completed Firebase task cannot be trusted after "no Firebase"', () {
      final previous = originalPlan();
      final result = reconciler.reconcile(
        previous: previous,
        revised: planWith(
          <UniversalTask>[
            task('r1', 'Inspect project', phase: 'Inspect'),
            // The replan still contains the Firebase task (say the
            // planner re-emitted it); the constraint must override.
            task('r3', 'Implement Firebase storage',
                dependencies: <String>{'r1'}),
          ],
          spec: specification(
            hardConstraints: <SpecificationClaim>[
              const SpecificationClaim.stated('Do not use Firebase.'),
            ],
          ),
          id: 'plan_2',
        ),
        completed: <CompletedTaskRecord>[
          CompletedTaskRecord.of(
            previous.tasks.firstWhere((task) => task.id == 't3'),
            evidence: <String, dynamic>{'runId': 'run_1'},
          ),
        ],
      );
      final invalidated = result.invalidated.single;
      expect(invalidated.title, 'Implement Firebase storage');
      expect(invalidated.reason, contains('firebase'));
      expect(invalidated.reason, contains('no longer'));
      // Invalidated work is re-enabled: its result cannot be relied on.
      expect(
        result.plan.tasks
            .firstWhere((task) => task.id == invalidated.taskId)
            .enabled,
        isTrue,
      );
    });

    test('completed work the revision simply omits is preserved, not erased',
        () {
      final previous = originalPlan();
      final result = reconciler.reconcile(
        previous: previous,
        // The replan does not mention the completed inspection at all.
        revised: planWith(
          <UniversalTask>[task('r9', 'Ship it', phase: 'Release')],
          id: 'plan_2',
        ),
        completed: <CompletedTaskRecord>[
          CompletedTaskRecord.of(
            previous.tasks.firstWhere((task) => task.id == 't1'),
            evidence: <String, dynamic>{'runId': 'run_1'},
          ),
        ],
      );
      final preserved = result.preserved.single;
      expect(preserved.title, 'Inspect project');
      expect(preserved.reason, contains('preserved even though'));
      expect(result.plan.validate(), isEmpty);
    });

    test('an unchanged specification invalidates nothing', () {
      final previous = originalPlan();
      final result = reconciler.reconcile(
        previous: previous,
        revised: originalPlan().copyWith(id: 'plan_2'),
        completed: <CompletedTaskRecord>[
          CompletedTaskRecord.of(
            previous.tasks.firstWhere((task) => task.id == 't3'),
          ),
        ],
      );
      expect(result.invalidated, isEmpty);
      expect(result.preserved, hasLength(1));
      expect(result.removed, isEmpty);
    });

    test('constraint scaffolding words never invalidate the whole plan', () {
      // "Do not use Firebase" contains "use" and "not" -- if those became
      // invalidating terms, every task in the plan would be invalidated.
      final previous = originalPlan();
      final result = reconciler.reconcile(
        previous: previous,
        revised: revisedPlan(),
        completed: <CompletedTaskRecord>[
          CompletedTaskRecord.of(
            previous.tasks.firstWhere((task) => task.id == 't1'),
          ),
          CompletedTaskRecord.of(
            previous.tasks.firstWhere((task) => task.id == 't2'),
          ),
        ],
      );
      expect(result.invalidated, isEmpty);
      expect(result.preserved, hasLength(2));
    });
  });
}
