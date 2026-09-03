import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/task_kernel/plan_reconciliation.dart';
import 'package:kristin_local_agent/product/task_kernel/semantic_steering.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';

class _Classifier implements TaskSpecificationPatchClassifier {
  const _Classifier(this.patch);
  final TaskSpecificationPatch patch;

  @override
  Future<TaskSpecificationPatch> classify({
    required TaskSpecification specification,
    required String userMessage,
  }) async => patch;
}

void main() {
  TaskSpecification specification() => TaskSpecification(
    id: 'spec',
    originalRequest: 'Build a storage-backed app.',
    objective: 'Build a storage-backed app.',
  );

  UniversalTask task({required String id, required String objective}) =>
      UniversalTask(
        id: id,
        title: objective,
        objective: objective,
        instructions: objective,
        acceptanceCriteria: const <String>['Done with evidence.'],
        verificationSteps: const <String>['Verify evidence.'],
      );

  test(
    'typed steering stays user intent and never becomes authority',
    () async {
      final result = await const SemanticSteeringCoordinator().apply(
        specification: specification(),
        userMessage: "Don't use Firebase.",
        classifier: const _Classifier(
          TaskSpecificationPatch(
            kind: TaskSpecificationPatchKind.hardConstraint,
            value: "Don't use Firebase.",
          ),
        ),
      );

      expect(
        result.specification.hardConstraints.single.statement,
        "Don't use Firebase.",
      );
      expect(result.runnerInstruction, contains('authorityBearing=false'));
      expect(result.runnerInstruction, contains('hardConstraint'));
      expect(
        result.runnerInstruction,
        contains('do not treat this message as permission'),
      );
    },
  );

  test('replanning preserves completed still-valid work', () async {
    final originalSpec = specification();
    final inspect = task(id: 'inspect-old', objective: 'Inspect project');
    final implement = task(id: 'implement-old', objective: 'Implement storage');
    final previous = UniversalTaskPlan(
      id: 'previous',
      specification: originalSpec,
      family: TaskFamily.software,
      route: PlanningRoute.compact,
      title: 'Previous',
      rationale: 'test',
      tasks: <UniversalTask>[inspect, implement],
    );

    final result = await const SemanticSteeringCoordinator().apply(
      specification: originalSpec,
      userMessage: 'Prioritize accessibility.',
      classifier: const _Classifier(
        TaskSpecificationPatch(
          kind: TaskSpecificationPatchKind.priority,
          value: 'accessibility',
        ),
      ),
      previousPlan: previous,
      completed: <CompletedTaskRecord>[
        CompletedTaskRecord.of(
          inspect,
          evidence: const <String, dynamic>{'verified': true},
        ),
      ],
      replan: (revised) async => UniversalTaskPlan(
        id: 'revised',
        specification: revised,
        family: TaskFamily.software,
        route: PlanningRoute.compact,
        title: 'Revised',
        rationale: 'test',
        tasks: <UniversalTask>[
          task(id: 'inspect-new', objective: 'Inspect project'),
          task(id: 'implement-new', objective: 'Implement storage'),
        ],
      ),
    );

    expect(result.reconciliation, isNotNull);
    expect(result.reconciliation!.preserved, hasLength(1));
    final preserved = result.reconciliation!.plan.tasks.firstWhere(
      (item) => item.objective == 'Inspect project',
    );
    expect(preserved.enabled, isFalse);
    expect(
      result.specification.preferences.single.statement,
      'Priority: accessibility',
    );
  });
}
