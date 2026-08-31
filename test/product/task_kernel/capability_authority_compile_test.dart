import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/task_kernel/plan_compiler.dart';
import 'package:kristin_local_agent/product/task_kernel/task_kernel.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/task_understanding.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

void main() {
  final project = ProjectRecord(
    id: 'p1',
    name: 'Project',
    rootPath: '.',
    createdAt: DateTime.utc(2026, 8, 31),
    updatedAt: DateTime.utc(2026, 8, 31),
  );
  final kernel = UniversalTaskKernel(
    understanding: const UnderstandingService(),
    compiler: UniversalPlanCompiler(tools: ToolRegistry.standard()),
    planners: const [],
  );

  UniversalTaskPlan planWithCapability(String capabilityId) => UniversalTaskPlan(
        id: 'plan',
        specification: TaskSpecification(
          id: 'spec',
          originalRequest: 'Inspect the project.',
          objective: 'Inspect the project.',
        ),
        family: TaskFamily.software,
        route: PlanningRoute.graph,
        title: 'Plan',
        rationale: 'test',
        tasks: <UniversalTask>[
          UniversalTask(
            id: 'inspect',
            title: 'Inspect',
            objective: 'Inspect the project.',
            instructions: 'Read the project.',
            allowedTools: const <String>{'read_file'},
            requiredCapabilities: <String>{capabilityId},
            acceptanceCriteria: const <String>['Inspection is complete.'],
            verificationSteps: const <String>['Review the evidence.'],
          ),
        ],
      );

  test('compiled contract must contain scopes implied by requiredCapabilities', () {
    expect(
      () => kernel.compile(
        plan: planWithCapability('project.run'),
        project: project,
        mode: CommandMode.analyze,
      ),
      throwsA(
        isA<ProductException>().having(
          (error) => error.code,
          'code',
          'capability_authority_not_compiled',
        ),
      ),
    );
  });

  test('unknown model-authored capability fails closed after compilation', () {
    expect(
      () => kernel.compile(
        plan: planWithCapability('not.a.capability'),
        project: project,
        mode: CommandMode.analyze,
      ),
      throwsA(
        isA<ProductException>().having(
          (error) => error.code,
          'code',
          'capability_unknown',
        ),
      ),
    );
  });
}
