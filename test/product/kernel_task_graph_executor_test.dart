import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/task_kernel/kernel_task_graph_executor.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';

void main() {
  TaskSpecification specification() => TaskSpecification(
        id: 'spec',
        originalRequest: 'research x then summarize it',
        objective: 'Research x and summarize it.',
      );

  UniversalTaskPlan planWith(List<UniversalTask> tasks) => UniversalTaskPlan(
        id: 'plan',
        specification: specification(),
        family: TaskFamily.research,
        route: PlanningRoute.compact,
        title: 'Research',
        rationale: 'test',
        tasks: tasks,
      );

  test('executes canonical dependencies before dependants', () async {
    final plan = planWith(
      const <UniversalTask>[
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

  test('resolves model-authored capabilities before the family executor', () async {
    final plan = planWith(
      const <UniversalTask>[
        UniversalTask(
          id: 'retrieve',
          title: 'Retrieve',
          objective: 'Retrieve evidence.',
          instructions: 'Search current public sources.',
          requiredCapabilities: <String>{'research.search'},
          acceptanceCriteria: <String>['Evidence exists.'],
          verificationSteps: <String>['Inspect evidence.'],
        ),
      ],
    );

    final result = await const KernelTaskGraphExecutor().execute(
      plan: plan,
      executeAuthorizedNode: (task, dependencies, authority) async {
        expect(authority.keys.toSet(), <String>{'research.search'});
        expect(
          authority['research.search']!.requiredScopes,
          contains(PermissionScope.networkResearch),
        );
        expect(
          authority['research.search']!.requiredScopes,
          isNot(contains(PermissionScope.projectRead)),
        );
        return KernelTaskNodeResult(
          taskId: task.id,
          state: KernelTaskNodeState.succeeded,
          evidence: const <String, dynamic>{'sourceCount': 2},
        );
      },
    );

    expect(result.succeeded, isTrue);
    expect(result.results['retrieve']!.evidence['sourceCount'], 2);
  });

  test('coordinator capability never reaches a graph family executor', () async {
    final plan = planWith(
      const <UniversalTask>[
        UniversalTask(
          id: 'bad',
          title: 'Provision again',
          objective: 'Provision a project from inside execution.',
          instructions: 'Create a second project.',
          requiredCapabilities: <String>{'agent.create_project'},
          acceptanceCriteria: <String>['Project exists.'],
          verificationSteps: <String>['Inspect project.'],
        ),
      ],
    );
    var called = false;

    final result = await const KernelTaskGraphExecutor().execute(
      plan: plan,
      executeAuthorizedNode: (task, dependencies, authority) async {
        called = true;
        return KernelTaskNodeResult(
          taskId: task.id,
          state: KernelTaskNodeState.succeeded,
        );
      },
    );

    expect(called, isFalse);
    expect(result.succeeded, isFalse);
    expect(result.results['bad']!.state, KernelTaskNodeState.failed);
    expect(
      result.results['bad']!.failureCode,
      'capability_coordinator_not_executable',
    );
  });

  test('reports queued running and terminal node states', () async {
    final plan = planWith(
      const <UniversalTask>[
        UniversalTask(
          id: 'retrieve',
          title: 'Retrieve',
          objective: 'Retrieve evidence.',
          instructions: 'Retrieve evidence.',
          acceptanceCriteria: <String>['Evidence exists.'],
          verificationSteps: <String>['Inspect evidence.'],
        ),
      ],
    );
    final states = <KernelTaskNodeState>[];

    await const KernelTaskGraphExecutor().execute(
      plan: plan,
      onStateChanged: (result) => states.add(result.state),
      executeNode: (task, dependencies) async => KernelTaskNodeResult(
        taskId: task.id,
        state: KernelTaskNodeState.succeeded,
      ),
    );

    expect(
      states,
      <KernelTaskNodeState>[
        KernelTaskNodeState.queued,
        KernelTaskNodeState.running,
        KernelTaskNodeState.succeeded,
      ],
    );
  });
}
