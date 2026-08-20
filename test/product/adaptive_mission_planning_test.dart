import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/adaptive_mission_planning.dart';
import 'package:kristin_local_agent/product/domain.dart';

void main() {
  group('adaptive mission planning', () {
    test('preview adapts mission, task, and output-token ranges', () {
      final prompt = _prompt(
        userPrompt:
            'Build a responsive desktop UI with local storage, an HTTP API, migration support, accessibility, and regression tests.',
      );
      final compact = AdaptiveMissionPlanner.preview(
        prompt: prompt,
        model: _model(),
        depth: PlanningDepth.compact,
        maxTasks: 15,
      );
      final detailed = AdaptiveMissionPlanner.preview(
        prompt: prompt,
        model: _model(parameterSize: '14B', quantization: 'Q8_0'),
        depth: PlanningDepth.detailed,
        maxTasks: 15,
      );

      expect(compact.expectedTaskCount, greaterThanOrEqualTo(1));
      expect(detailed.expectedTaskCount, greaterThan(compact.expectedTaskCount));
      expect(detailed.expectedMissionCount, greaterThanOrEqualTo(2));
      expect(detailed.outputTokens.high, greaterThan(detailed.outputTokens.likely));
      expect(
        detailed.planGeneration.likely,
        greaterThan(detailed.outputTokens.likely),
      );
      expect(detailed.confidence, inInclusiveRange(0.48, 0.86));
    });

    test('token estimate reserves more capacity for uncertain high-risk work', () {
      final low = AdaptiveMissionPlanner.estimateTask(
        task: _task(
          id: 'low',
          title: 'Update copy',
          complexity: 2,
          effortPoints: 1,
          expectedModelTurns: 1,
          expectedToolCalls: 1,
          uncertainty: PlanUncertainty.low,
          risk: PlanRisk.low,
          confidence: 0.92,
        ),
        prompt: _prompt(),
        model: _model(),
      );
      final high = AdaptiveMissionPlanner.estimateTask(
        task: _task(
          id: 'high',
          title: 'Migrate persistent storage and rollback safely',
          complexity: 9,
          effortPoints: 8,
          expectedModelTurns: 8,
          expectedToolCalls: 28,
          uncertainty: PlanUncertainty.high,
          risk: PlanRisk.critical,
          confidence: 0.42,
          tools: const <String>{'inspect_file', 'apply_patch', 'verify_project'},
        ),
        prompt: _prompt(),
        model: _model(),
      );

      expect(high.totalTokens.likely, greaterThan(low.totalTokens.likely));
      expect(high.totalTokens.high, greaterThan(high.totalTokens.likely));
      expect(high.retryProbability, greaterThan(low.retryProbability));
      expect(high.confidence, lessThan(low.confidence));
    });

    test('optimizer merges overlapping packets and rewires dependencies', () {
      final result = AdaptiveMissionPlanner.optimizeTasks(
        tasks: <PlanTaskRecord>[
          _task(
            id: 'auth_a',
            title: 'Implement authentication session handling',
            objective: 'Add secure authentication session handling',
            phase: 'Authentication',
          ),
          _task(
            id: 'auth_b',
            title: 'Implement authentication session handling',
            objective: 'Add secure authentication session handling',
            phase: 'Authentication',
          ),
          _task(
            id: 'consumer',
            title: 'Use authenticated state in the dashboard',
            phase: 'Dashboard',
            dependencies: const <String>{'auth_b'},
          ),
        ],
        prompt: _prompt(mode: CommandMode.plan),
        maxTasks: 7,
      );

      expect(result.mergedTaskIds, contains('auth_b'));
      expect(result.tasks.map((task) => task.id), isNot(contains('auth_b')));
      final consumer = result.tasks.singleWhere((task) => task.id == 'consumer');
      expect(consumer.dependencies, contains('auth_a'));
      expect(consumer.dependencies, isNot(contains('auth_b')));
      expect(
        result.findings.any((finding) => finding.id == 'merged_auth_b'),
        isTrue,
      );
    });

    test('optimizer splits oversized implementation and gates downstream work', () {
      final result = AdaptiveMissionPlanner.optimizeTasks(
        tasks: <PlanTaskRecord>[
          _task(
            id: 'runtime',
            title: 'Redesign the execution runtime',
            objective: 'Implement and validate a new execution runtime',
            phase: 'Runtime',
            complexity: 9,
            effortPoints: 13,
            expectedModelTurns: 8,
            expectedToolCalls: 30,
            verification: const <String>[
              'Run focused runtime tests.',
              'Exercise cancellation and rollback paths.',
            ],
          ),
          _task(
            id: 'ui',
            title: 'Expose runtime state in the UI',
            phase: 'Experience',
            dependencies: const <String>{'runtime'},
          ),
        ],
        prompt: _prompt(),
        maxTasks: 5,
      );

      expect(result.splitTaskIds, contains('runtime'));
      final verification = result.tasks.singleWhere(
        (task) => task.id.startsWith('runtime_verify'),
      );
      final downstream = result.tasks.singleWhere((task) => task.id == 'ui');
      expect(verification.dependencies, contains('runtime'));
      expect(downstream.dependencies, contains(verification.id));
      expect(downstream.dependencies, isNot(contains('runtime')));
      expect(verification.allowedTools, contains('verify_project'));
    });

    test('optimizer adds a final verification gate when the plan has none', () {
      final result = AdaptiveMissionPlanner.optimizeTasks(
        tasks: <PlanTaskRecord>[
          _task(
            id: 'implementation',
            title: 'Implement the requested feature',
            phase: 'Implementation',
          ),
        ],
        prompt: _prompt(),
        maxTasks: 4,
      );

      expect(result.verificationGateAdded, isTrue);
      final gate = result.tasks.singleWhere(
        (task) => task.phase == 'Verification',
      );
      expect(gate.dependencies, contains('implementation'));
      expect(gate.allowedTools, contains('verify_project'));
      expect(gate.maxAttempts, 1);
    });

    test('analysis creates missions, a ready frontier, tests, and critical path', () {
      final tasks = <PlanTaskRecord>[
        _task(
          id: 'foundation',
          title: 'Create storage foundation',
          objective: 'Add local storage service',
          phase: 'Foundation',
          tools: const <String>{'inspect_file', 'apply_patch'},
        ),
        _task(
          id: 'experience',
          title: 'Build responsive settings UI',
          objective: 'Expose storage settings in an accessible widget',
          phase: 'Experience',
          dependencies: const <String>{'foundation'},
          risk: PlanRisk.high,
          complexity: 7,
        ),
        _task(
          id: 'verification',
          title: 'Verify integration and regression behavior',
          objective: 'Test storage, UI, failure, and recovery paths',
          phase: 'Verification',
          dependencies: const <String>{'experience'},
          tools: const <String>{'inspect_file', 'verify_project'},
        ),
      ];
      final plan = _plan(tasks);
      final analysis = AdaptiveMissionPlanner.analyzePlan(
        plan: plan,
        prompt: _prompt(),
      );

      expect(analysis.missions.length, 3);
      expect(analysis.readyFrontier, <String>{'foundation'});
      expect(analysis.criticalPath, <String>[
        'foundation',
        'experience',
        'verification',
      ]);
      expect(analysis.economics.high, greaterThan(analysis.economics.likely));
      expect(analysis.tests, isNotEmpty);
      expect(
        analysis.tests.map((test) => test.kind),
        containsAll(<AdaptiveTestKind>[
          AdaptiveTestKind.staticAnalysis,
          AdaptiveTestKind.component,
          AdaptiveTestKind.integration,
          AdaptiveTestKind.acceptance,
          AdaptiveTestKind.manual,
        ]),
      );
      expect(analysis.lazyPacketCount, 2);
      expect(analysis.verificationCoverage, inInclusiveRange(0.0, 1.0));
    });

    test('runner packet carries context, economics, proof, and replan limits', () {
      final task = _task(
        id: 'ready',
        title: 'Implement adaptive planner',
        objective: 'Create mission planning behavior',
        phase: 'Planner',
        tools: const <String>{'inspect_file', 'apply_patch', 'verify_project'},
      );
      final analysis = AdaptiveMissionPlanner.analyzePlan(
        plan: _plan(<PlanTaskRecord>[task]),
        prompt: _prompt(),
      );
      final packet = analysis.runnerPacketFor('ready');

      expect(packet, contains('READY FRONTIER'));
      expect(packet, contains('MISSION Planner'));
      expect(packet, contains('TOKEN BUDGET'));
      expect(packet, contains('RISK-BASED TESTS'));
      expect(packet, contains('STOP AND REPLAN'));
      expect(packet.length, lessThanOrEqualTo(6200));
    });

    test('plain-text token estimator is deterministic and language aware', () {
      const prose = 'Build a reliable local desktop application with tests.';
      const code = 'class Counter { int value = 0; void increment() { value++; } }';
      const multilingual = 'Xây dựng ứng dụng cục bộ đáng tin cậy với kiểm thử.';

      expect(
        AdaptiveMissionPlanner.estimateTextTokens(prose),
        AdaptiveMissionPlanner.estimateTextTokens(prose),
      );
      expect(AdaptiveMissionPlanner.estimateTextTokens(code), greaterThan(5));
      expect(
        AdaptiveMissionPlanner.estimateTextTokens(multilingual),
        greaterThan(5),
      );
      expect(AdaptiveMissionPlanner.estimateTextTokens(''), 0);
    });
  });
}

PromptStudioDraft _prompt({
  String userPrompt = 'Build a reliable local desktop feature with tests.',
  CommandMode mode = CommandMode.build,
}) {
  return PromptStudioDraft(
    title: 'Adaptive feature',
    purpose: 'Deliver a verified local product increment.',
    systemPrompt:
        'Work inside the selected project, preserve safety boundaries, and verify every material result.',
    userPrompt: userPrompt,
    variables: const <String>[],
    assumptions: const <String>['The implementation remains local-first.'],
    clarifyingQuestions: const <String>[],
    acceptanceCriteria: const <String>[
      'The requested behavior is implemented.',
      'Relevant automated checks pass.',
    ],
    outputExpectations: const <String>['Product source and test evidence'],
    guardrails: const <String>['Do not escape the selected project.'],
    stopConditions: const <String>['Stop when a required permission is missing.'],
    evaluationCases: const <String>['Normal path', 'Failure path'],
    mode: mode,
  );
}

ModelIdentity _model({
  String parameterSize = '4B',
  String quantization = 'Q4_K_M',
}) {
  return ModelIdentity(
    providerId: 'ollama',
    name: 'phi5-mini:test',
    digest: 'sha256:test',
    parameterSize: parameterSize,
    quantization: quantization,
    discoveredAt: DateTime.utc(2026, 8, 19),
  );
}

PlanTaskRecord _task({
  required String id,
  required String title,
  String objective = 'Deliver the requested bounded outcome.',
  String phase = 'Implementation',
  Set<String> dependencies = const <String>{},
  Set<String> tools = const <String>{'inspect_file', 'apply_patch'},
  int complexity = 4,
  int effortPoints = 3,
  int expectedModelTurns = 3,
  int expectedToolCalls = 6,
  PlanUncertainty uncertainty = PlanUncertainty.medium,
  PlanRisk risk = PlanRisk.medium,
  double confidence = 0.72,
  List<String> verification = const <String>[
    'Run the focused automated checks.',
  ],
}) {
  return PlanTaskRecord(
    id: id,
    phase: phase,
    parentId: null,
    title: title,
    objective: objective,
    instructions:
        'Inspect the relevant source, implement the bounded change, and preserve existing behavior outside this task.',
    dependencies: dependencies,
    acceptanceCriteria: const <String>[
      'The bounded outcome is present and inspectable.',
      'The affected behavior has objective evidence.',
    ],
    verificationSteps: verification,
    expectedArtifacts: <String>['Artifact for $title'],
    allowedTools: tools,
    complexity: complexity,
    effortPoints: effortPoints,
    uncertainty: uncertainty,
    risk: risk,
    estimateConfidence: confidence,
    expectedModelTurns: expectedModelTurns,
    expectedToolCalls: expectedToolCalls,
    maxAttempts: 2,
    enabled: true,
    manual: false,
  );
}

TaskPlanRecord _plan(List<PlanTaskRecord> tasks) {
  return TaskPlanRecord(
    id: 'plan_test',
    promptId: 'prompt_test',
    promptVersionId: 'prompt_version_test',
    projectId: 'project_test',
    revision: 1,
    previousPlanId: null,
    title: 'Adaptive plan',
    rationale: 'Test adaptive mission planning.',
    depth: PlanningDepth.auto,
    maxLeafTasks: 25,
    tasks: tasks,
    model: _model(),
    contentHash: 'sha256:test-plan',
    createdAt: DateTime.utc(2026, 8, 19),
    updatedAt: DateTime.utc(2026, 8, 19),
  );
}
