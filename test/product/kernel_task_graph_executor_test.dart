import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/task_kernel/kernel_task_graph_executor.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';

void main() {
  test('executes canonical dependencies before dependants', () async {
    final specification = TaskSpecification(
      id: 'spec',
      originalRequest: 'research x then summarize it',
      objective: 'Research x and summarize it.',
    );
    final plan = UniversalTaskPlan(
      id: 'plan',
      specification: specification,
      family: TaskFamily.research,
      route: PlanningRoute.compact,
      title: 'Research',
      rationale: 'test',
      tasks: const <UniversalTask>[
        UniversalTask(
          id: 'retrieve',
          title: 'Retrieve',
          objective: 'Retrieve evidence.',
          instructions: 'Retrieve evidence.',
          acceptanceCriteria: <String>['Evidence exists.'],
          verificationSteps: <String>['Inspect evidence.'],
        ),
        UniversalTask(
          id: 'synthesize',
          title: 'Synthesize',
          objective: 'Write the answer.',
          instructions: 'Use the evidence.',
          dependencies: <String>{'retrieve'},
          acceptanceCriteria: <String>['Answer exists.'],
          verificationSteps: <String>['Check answer.'],
        ),
      ],
    );
    final order = <String>[];
    final result = await const KernelTaskGraphExecutor().execute(
      plan: plan,
      executeNode: (task, dependencies) async {
        order.add(task.id);
        if (task.id == 'synthesize') {
          expect(dependencies.keys, contains('retrieve'));
        }
        return KernelTaskNodeResult(
          taskId: task.id,
          state: KernelTaskNodeState.succeeded,
        );
      },
    );

    expect(order, <String>['retrieve', 'synthesize']);
    expect(result.succeeded, isTrue);
  });
}
