import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/task_kernel/plan_compiler.dart';
import 'package:kristin_local_agent/product/task_kernel/planning_failures.dart';
import 'package:kristin_local_agent/product/task_kernel/task_families.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

/// UNIVERSALITY.
///
/// The claim under test is not "research works" or "diagnostics works" --
/// it is that research, diagnostics and Owner work all accept the SAME
/// TaskSpecification, produce the SAME UniversalTaskPlan type, and pass
/// through the SAME UniversalPlanCompiler as software work does.
/// Different executors; one semantic architecture.
void main() {
  final project = ProjectRecord(
    id: 'project-universal',
    name: 'Universal fixture',
    rootPath: '.',
    createdAt: DateTime.utc(2026, 8, 28),
    updatedAt: DateTime.utc(2026, 8, 28),
  );

  final allCapabilities = kKristinCapabilities.map((item) => item.id).toSet();

  PlanningContext contextWith({Set<String>? capabilities}) => PlanningContext(
        project: project,
        availableCapabilityIds: capabilities ?? allCapabilities,
        availableToolNames: ToolRegistry.standard().names,
      );

  group('RESEARCH family', () {
    // SCENARIO E / DELIVERABLE #6: "what is the weather in Nha Trang and
    // the current time in New York?"
    TaskSpecification weatherAndTime() => TaskSpecification(
          id: 'spec_research',
          originalRequest: 'What is the weather in Nha Trang and the current '
              'time in New York?',
          objective: 'Answer both current factual questions',
          subObjectives: <String>[
            'current Nha Trang weather',
            'current New York local time',
          ],
          successCriteria: <SpecificationClaim>[
            const SpecificationClaim.inferred(
              'Both facts are grounded in current sources.',
            ),
          ],
          source: TaskSpecificationSource.modelUnderstanding,
          confidence: 0.9,
        );

    test('decomposes into retrieval / freshness / synthesis', () async {
      final plan = await const ResearchTaskFamilyPlanner().plan(
        specification: weatherAndTime(),
        route: PlanningRoute.compact,
        context: contextWith(),
      );
      expect(plan.validate(), isEmpty);
      expect(plan.family, TaskFamily.research);

      final retrievals = plan.tasks
          .where((task) => task.phase == 'Retrieval')
          .toList(growable: false);
      expect(retrievals, hasLength(2));
      expect(
        retrievals.map((task) => task.title),
        containsAll(<String>[
          'Obtain current Nha Trang weather',
          'Obtain current New York local time',
        ]),
      );
      // The two facts are INDEPENDENT: neither retrieval waits on the
      // other, so they can be satisfied in any order.
      for (final retrieval in retrievals) {
        expect(retrieval.dependencies, isEmpty);
      }
      expect(
        plan.tasks.any((task) => task.phase == 'Verification'),
        isTrue,
        reason: 'freshness must be verified before synthesis',
      );
      final synthesis =
          plan.tasks.firstWhere((task) => task.phase == 'Synthesis');
      expect(
        synthesis.dependencies.single,
        plan.tasks.firstWhere((task) => task.phase == 'Verification').id,
      );
    });

    test('the graph exists but stays hidden -- planning is not display',
        () async {
      final plan = await const ResearchTaskFamilyPlanner().plan(
        specification: weatherAndTime(),
        route: PlanningRoute.compact,
        context: contextWith(),
      );
      // Real tasks, really executed and verified...
      expect(plan.enabledTasks.length, greaterThanOrEqualTo(4));
      // ...and zero task cards for a two-fact question.
      expect(plan.visibleTasks, isEmpty);
    });

    test('a single-subject question still produces one grounded retrieval',
        () async {
      final plan = await const ResearchTaskFamilyPlanner().plan(
        specification: TaskSpecification(
          id: 'spec_single',
          originalRequest: 'What is the current price of gold?',
          objective: 'Find the current price of gold',
        ),
        route: PlanningRoute.compact,
        context: contextWith(),
      );
      expect(plan.validate(), isEmpty);
      expect(
        plan.tasks.where((task) => task.phase == 'Retrieval'),
        hasLength(1),
      );
    });
  });

  group('DIAGNOSTICS family', () {
    // SCENARIO H: "Why is Kristin slow today?"
    test('collects evidence before asserting a cause', () async {
      final plan = await const DiagnosticsTaskFamilyPlanner().plan(
        specification: TaskSpecification(
          id: 'spec_diag',
          originalRequest: 'Why is Kristin slow today?',
          objective: 'Explain why Kristin is slow today',
        ),
        route: PlanningRoute.compact,
        context: contextWith(),
      );
      expect(plan.validate(), isEmpty);
      expect(plan.family, TaskFamily.diagnostics);
      final collect = plan.tasks.firstWhere((task) => task.phase == 'Evidence');
      final interpret =
          plan.tasks.firstWhere((task) => task.phase == 'Analysis');
      final answer = plan.tasks.firstWhere((task) => task.phase == 'Synthesis');
      // Evidence -> analysis -> answer, enforced by the graph rather than
      // by hoping the executor does them in order.
      expect(interpret.dependencies, contains(collect.id));
      expect(answer.dependencies, contains(interpret.id));
      expect(plan.requiredCapabilities, contains('system.diagnose'));
    });
  });

  group('OWNER family', () {
    // SCENARIO G / DELIVERABLE #7:
    //   /owner create testFF.txt on Desktop containing "Hello world"
    TaskSpecification desktopFile() => TaskSpecification(
          id: 'spec_owner',
          originalRequest: '/owner create file at my desktop testFF.txt and '
              'write in it "Hello world"',
          objective: 'Create Desktop/testFF.txt containing "Hello world"',
          targetRefs: <TaskTargetRef>[
            const TaskTargetRef(
              kind: 'workspace',
              value: 'Desktop/testFF.txt',
              displayName: 'Desktop/testFF.txt',
              provenance: EvidenceProvenance.userStated,
            ),
          ],
          hardConstraints: <SpecificationClaim>[
            const SpecificationClaim.stated('Only this file may be affected.'),
            const SpecificationClaim.stated(
              'The content must be exactly "Hello world".',
            ),
          ],
        );

    test('produces resolve / effect / verify, not implementation trivia',
        () async {
      final plan = await const OwnerTaskFamilyPlanner().plan(
        specification: desktopFile(),
        route: PlanningRoute.compact,
        context: contextWith(),
      );
      expect(plan.validate(), isEmpty);
      expect(plan.family, TaskFamily.owner);
      expect(
        plan.phases,
        containsAll(<String>['Authority', 'Effect', 'Verification']),
      );
      // Authority is resolved BEFORE the effect, structurally.
      final resolve =
          plan.tasks.firstWhere((task) => task.phase == 'Authority');
      final effect = plan.tasks.firstWhere((task) => task.phase == 'Effect');
      final verify =
          plan.tasks.firstWhere((task) => task.phase == 'Verification');
      expect(effect.dependencies, contains(resolve.id));
      expect(verify.dependencies, contains(effect.id));
      // No open-handle/write-bytes/flush/close noise.
      final titles = plan.tasks.map((task) => task.title.toLowerCase());
      for (final trivia in <String>['open handle', 'flush', 'write bytes']) {
        expect(titles.any((title) => title.contains(trivia)), isFalse);
      }
    });

    test('an Owner plan REQUIRES a capability; it never grants one', () async {
      final plan = await const OwnerTaskFamilyPlanner().plan(
        specification: desktopFile(),
        route: PlanningRoute.compact,
        context: contextWith(),
      );
      expect(plan.requiredCapabilities, contains('owner.mode'));
      // Every Owner task carries the requirement, so no step can slip
      // past the authority layer by being unlabelled.
      for (final task in plan.enabledTasks) {
        expect(task.requiredCapabilities, contains('owner.mode'));
      }
    });

    test(
        'OWNER MODE IS NEVER BLANKET PERMISSION: an unavailable capability '
        'is refused at plan time', () async {
      // The architecture proved against a fixture capability that does not
      // exist in the governed registry -- exactly the case where
      // production must NOT claim OS authority it does not have.
      await expectLater(
        const OwnerTaskFamilyPlanner(
          capabilityId: 'owner.external_filesystem_write',
        ).plan(
          specification: desktopFile(),
          route: PlanningRoute.compact,
          context: contextWith(),
        ),
        throwsA(
          isA<PlanningFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                PlanningFailureKind.permissionDenied,
              )
              .having(
                (failure) => failure.allowsConservativeFallback,
                'allowsConservativeFallback',
                isFalse,
              ),
        ),
      );
    });

    test(
        'a fixture Owner capability reaches authority resolution through '
        'the same kernel architecture', () async {
      // The test adapter: a canonical capability that IS present. The
      // plan then compiles like any other family's -- which is the point.
      // Nothing here performs an external filesystem effect.
      const fixtureCapability = 'owner.fixture_effect';
      final plan = await const OwnerTaskFamilyPlanner(
        capabilityId: fixtureCapability,
      ).plan(
        specification: desktopFile(),
        route: PlanningRoute.compact,
        context: contextWith(
          capabilities: <String>{...allCapabilities, fixtureCapability},
        ),
      );
      expect(plan.validate(), isEmpty);
      final compiled =
          UniversalPlanCompiler(tools: ToolRegistry.standard()).compile(
        plan: plan,
        project: project,
        mode: CommandMode.ask,
        request: plan.specification.originalRequest,
      );
      expect(compiled.isFaithfulProjection, isTrue);
      // The user's exact constraints are inviolable in the CONTRACT the
      // executor receives, not merely in the request text.
      expect(
        compiled.contract.constraints.join(' | '),
        contains('Hard constraint (must not be violated): Only this file '
            'may be affected.'),
      );
      expect(
        compiled.contract.constraints.join(' | '),
        contains('The content must be exactly "Hello world".'),
      );
    });
  });

  group('every family passes through the same compiler', () {
    test(
        'research, diagnostics, owner and conservative software all '
        'compile', () async {
      final specification = TaskSpecification(
        id: 'spec_shared',
        originalRequest: 'Do the thing',
        objective: 'Do the thing',
        subObjectives: <String>['part one', 'part two'],
        successCriteria: <SpecificationClaim>[
          const SpecificationClaim.inferred('The thing is done.'),
        ],
      );
      final planners = <TaskFamilyPlanner>[
        const ResearchTaskFamilyPlanner(),
        const DiagnosticsTaskFamilyPlanner(),
        const OwnerTaskFamilyPlanner(),
        const ConservativeSoftwarePlanner(),
      ];
      final compiler = UniversalPlanCompiler(tools: ToolRegistry.standard());
      for (final planner in planners) {
        final plan = await planner.plan(
          specification: specification,
          route: PlanningRoute.compact,
          context: contextWith(),
        );
        expect(plan.validate(), isEmpty, reason: '${planner.family}');
        final compiled = compiler.compile(
          plan: plan,
          project: project,
          mode: CommandMode.ask,
          request: specification.originalRequest,
        );
        expect(
          compiled.plan.validate(),
          isEmpty,
          reason: '${planner.family} must compile to a valid execution plan',
        );
        expect(
          compiled.isFaithfulProjection,
          isTrue,
          reason: '${planner.family} must execute the graph it planned',
        );
      }
    });

    test(
        'the conservative planner is a safety envelope, not a '
        'decomposition', () async {
      final plan = await const ConservativeSoftwarePlanner().plan(
        specification: TaskSpecification(
          id: 'spec_conservative',
          originalRequest: 'Build an MP3 converter',
          objective: 'Build an MP3 converter',
          hardConstraints: <SpecificationClaim>[
            const SpecificationClaim.stated('No accounts.'),
          ],
        ),
        route: PlanningRoute.graph,
        context: contextWith(),
      );
      expect(plan.conservative, isTrue);
      expect(plan.phases, <String>['Inspect', 'Implement', 'Verify']);
      // Even the safety net carries the user's constraint forward rather
      // than dropping it.
      expect(
        plan.tasks.firstWhere((task) => task.phase == 'Implement').instructions,
        contains('No accounts.'),
      );
    });
  });
}
