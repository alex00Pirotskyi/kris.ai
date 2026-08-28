import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/prompt_planning.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/task_kernel/complexity_router.dart';
import 'package:kristin_local_agent/product/task_kernel/plan_compiler.dart';
import 'package:kristin_local_agent/product/task_kernel/planning_failures.dart';
import 'package:kristin_local_agent/product/task_kernel/runtime_gateway.dart';
import 'package:kristin_local_agent/product/task_kernel/software_family.dart';
import 'package:kristin_local_agent/product/task_kernel/task_families.dart';
import 'package:kristin_local_agent/product/task_kernel/task_kernel.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/task_understanding.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

/// DELIVERABLE #10: proof through the ACTUAL product boundary.
///
/// The predecessor test instantiated PromptPlanningService directly, which
/// only proved the planning service can compile a supplied graph. These
/// tests drive the whole product path a Chat message actually takes:
///
///   Chat request
///     -> ChatIntentCompiler decision
///     -> kernel Understanding / TaskSpecification
///     -> complexity routing
///     -> universal planning (reusing the real PromptPlanningService)
///     -> compile
///     -> the plan Chat would display
///     -> the SAME graph reaching the Runner's ExecutionPlan
///
/// The model is a deterministic fixture, and the assertions are about the
/// ARCHITECTURE -- what was supplied to the model, what survived
/// validation, what reached execution -- not about a fixture proving
/// general intelligence.
void main() {
  late Directory temporary;
  late ProductRepositories repositories;
  late EventJournal events;
  late AuditChain audit;
  late ModelIdentity model;
  late ProjectRecord project;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('kristin-kernel-');
    final directories = await AppDirectories.create(
      overrideRoot: '${temporary.path}${Platform.pathSeparator}app-data',
    );
    repositories = await ProductRepositories.open(directories);
    final redactor = SecretRedactor();
    events = EventJournal(repositories.eventFile);
    await events.open();
    audit = AuditChain(repositories.auditFile, redactor);
    await audit.open();
    model = ModelIdentity(
      providerId: 'fixture',
      name: 'deterministic-kernel',
      digest: 'sha256:kernel-fixture',
      discoveredAt: DateTime.utc(2026, 8, 28),
    );
    project = ProjectRecord(
      id: 'project-mp3',
      name: 'MP3 to URL fixture',
      rootPath: temporary.path,
      createdAt: DateTime.utc(2026, 8, 28),
      updatedAt: DateTime.utc(2026, 8, 28),
    );
    await repositories.projects.put(project);
  });

  tearDown(() async {
    await events.close();
    if (await temporary.exists()) {
      // On Windows, SQLite-backed repository handles are not always
      // released the instant events/audit close, so an immediate
      // recursive delete can hit a transient sharing violation. Retry
      // with backoff (the pattern v1_product_preview_test.dart uses).
      FileSystemException? lastError;
      var deleted = false;
      for (var attempt = 0; attempt < 20; attempt++) {
        try {
          await temporary.delete(recursive: true);
          deleted = true;
          break;
        } on FileSystemException catch (error) {
          lastError = error;
          await Future<void>.delayed(
            Duration(milliseconds: 25 * (attempt + 1)),
          );
        }
      }
      if (!deleted && !Platform.isWindows && lastError != null) {
        throw lastError;
      }
    }
  });

  PromptPlanningService planningWith(ModelGenerationDelegate generator) {
    final redactor = SecretRedactor();
    final vault = SecretVault(repositories.secretReferences, redactor, audit);
    return PromptPlanningService(
      models: ModelRegistry(
        settings: const ProductSettings(ollamaBaseUrl: ''),
        vault: vault,
        redactor: redactor,
      ),
      repositories: repositories,
      audit: audit,
      events: events,
      redactor: redactor,
      tools: ToolRegistry.standard(),
      generator: generator,
    );
  }

  UniversalTaskKernel kernelWith(
    ModelGenerationDelegate planningGenerator, {
    ModelGenerationDelegate? understandingGenerator,
  }) =>
      buildUniversalTaskKernel(
        planning: planningWith(planningGenerator),
        tools: ToolRegistry.standard(),
        models: ModelRegistry(
          settings: const ProductSettings(ollamaBaseUrl: ''),
          vault: SecretVault(
            repositories.secretReferences,
            SecretRedactor(),
            audit,
          ),
          redactor: SecretRedactor(),
        ),
        understandingGenerator: understandingGenerator,
      );

  PlanningContext contextFor() => PlanningContext(
        project: project,
        model: model,
        availableCapabilityIds:
            kKristinCapabilities.map((item) => item.id).toSet(),
        availableToolNames: ToolRegistry.standard().names,
      );

  const mp3Request = 'Create a Flutter web app that converts MP3 files. '
      'No accounts. Upload an MP3, show progress and provide a '
      'downloadable result with simple UX.';

  group('SCENARIO C: Chat -> kernel -> the same executable graph', () {
    test(
        'a substantial request decomposes into request-specific tasks that '
        'reach the Runner unchanged', () async {
      final captured = <ModelGenerationRequest>[];
      final kernel = kernelWith(
        _mp3PlanGenerator(model, capture: captured.add),
        understandingGenerator: _mp3UnderstandingGenerator(model),
      );

      // 1. Chat compiles the message exactly as the composer does.
      const compiler = ChatIntentCompiler();
      final decision = compiler.compile(mp3Request);
      expect(decision.kind, ChatInteractionKind.action);
      expect(decision.capability?.id, 'agent.create_project');

      // 2. Understanding: the model reads it, deterministic code validates.
      final understanding = await kernel.understand(
        KernelRequestContext(
          decision: decision,
          project: project,
          model: model,
        ),
      );
      expect(understanding.path, UnderstandingPath.model);
      final specification = understanding.specification;
      expect(specification.hasSemanticUnderstanding, isTrue);
      expect(specification.objective.toLowerCase(), contains('mp3'));
      expect(
        specification.hardConstraints.map((claim) => claim.statement),
        contains('No accounts or authentication'),
      );

      // 3. Routing decides this is worth a reviewed graph.
      final routing = kernel.route(
        specification: specification,
        decision: decision,
      );
      expect(routing.route, PlanningRoute.graph);
      expect(routing.family, TaskFamily.software);

      // 4. Planning, through the reused real PromptPlanningService.
      final result = await kernel.plan(
        specification: specification,
        routing: routing,
        context: contextFor(),
      );
      expect(result.origin, KernelPlanOrigin.planned);
      expect(result.plan.conservative, isFalse);

      // The plan is about THIS request, not the generic three-step
      // envelope.
      final titles = result.plan.tasks.map((task) => task.title).toList();
      expect(titles.length, greaterThan(3));
      expect(
        titles,
        isNot(contains('Inspect project and establish evidence baseline')),
      );
      expect(
        titles.any((title) =>
            title.toLowerCase().contains('upload') ||
            title.toLowerCase().contains('progress') ||
            title.toLowerCase().contains('download')),
        isTrue,
        reason: 'the plan must decompose the requested feature: $titles',
      );

      // 5. What was actually SUPPLIED TO THE MODEL: the accepted
      // objective, the constraints, and real capability information.
      final planningPrompt = captured
          .firstWhere(
            (request) => request.systemPrompt.contains('task-planning model'),
          )
          .userPrompt;
      expect(planningPrompt, contains('AVAILABLE KRISTIN CAPABILITIES'));
      expect(planningPrompt, contains('agent.create_project'));
      expect(planningPrompt, contains('research.search'));
      expect(planningPrompt, contains('No accounts or authentication'));
      expect(
        planningPrompt,
        contains('Proposing one is not the same as'),
        reason: 'the planning model must be told it cannot grant authority',
      );

      // 6. Compile, and assert the invariant: shown == executed.
      final compiled = kernel.compile(
        plan: result.plan,
        project: project,
        mode: CommandMode.build,
      );
      expect(compiled.plan.validate(), isEmpty);
      expect(compiled.isFaithfulProjection, isTrue);
      expect(
        compiled.plan.items.map((item) => item.id).toList(),
        result.plan.enabledTasks.map((task) => task.id).toList(),
      );
      expect(
        compiled.plan.items.map((item) => item.title).toList(),
        result.plan.enabledTasks.map((task) => task.title).toList(),
      );

      // 7. Hierarchy survived all the way to the executable work item.
      final byId = <String, WorkItem>{
        for (final item in compiled.plan.items) item.id: item,
      };
      expect(byId['task_002']!.phase, 'UI');
      expect(byId['task_002']!.parentId, 'task_001');
      expect(byId['task_005']!.dependencies, contains('task_004'));

      // 8. The user's hard constraint is inviolable in the executed
      //    contract, not merely present in the request text.
      expect(
        compiled.contract.constraints.join(' | '),
        contains('Hard constraint (must not be violated): No accounts or '
            'authentication'),
      );
    });

    test(
        'NO Prompt Studio artifact is created just because the user asked '
        'Kristin to do something', () async {
      final kernel = kernelWith(
        _mp3PlanGenerator(model),
        understandingGenerator: _mp3UnderstandingGenerator(model),
      );
      const compiler = ChatIntentCompiler();
      final decision = compiler.compile(mp3Request);
      final understanding = await kernel.understand(
        KernelRequestContext(
          decision: decision,
          project: project,
          model: model,
        ),
      );
      final routing = kernel.route(
        specification: understanding.specification,
        decision: decision,
      );

      expect(await repositories.prompts.all(), isEmpty);
      expect(await repositories.promptVersions.all(), isEmpty);

      await kernel.plan(
        specification: understanding.specification,
        routing: routing,
        context: contextFor(),
      );

      // The ephemeral planning path: the plan exists, the Prompt Studio
      // library does not gain a row the user never asked for.
      expect(
        await repositories.prompts.all(),
        isEmpty,
        reason: 'ordinary Chat planning must not save a Prompt Studio prompt',
      );
      expect(
        await repositories.promptVersions.all(),
        isEmpty,
        reason: 'ordinary Chat planning must not save a prompt version',
      );
      // ...while the task plan itself IS persisted, so Prompt Studio can
      // later open the same plan rather than forking a copy.
      expect(await repositories.taskPlans.all(), isNotEmpty);
    });

    test('the ephemeral prompt version is identifiable as ephemeral', () {
      final specification = TaskSpecification(
        id: 'spec',
        originalRequest: mp3Request,
        objective: 'Build an MP3 converter',
      );
      final version = ephemeralPromptVersion(
        specification: specification,
        draft: PromptStudioDraft.fromJson(_draftJson()),
        model: model,
      );
      expect(isEphemeralPromptVersion(version), isTrue);
      final saved = PromptVersionRecord(
        id: 'prompt_version_real',
        promptId: 'prompt_real',
        versionNumber: 1,
        sourceGoal: 'x',
        action: PromptGenerationAction.generate,
        draft: PromptStudioDraft.fromJson(_draftJson()),
        model: model,
        contentHash: 'hash',
        createdBy: 'user',
        createdAt: DateTime.utc(2026, 8, 28),
      );
      expect(isEphemeralPromptVersion(saved), isFalse);
    });
  });

  group('SCENARIO D: a stated constraint cannot be silently lost', () {
    test(
        'the hard constraint reaches the draft, the planner and the '
        'contract', () async {
      final captured = <ModelGenerationRequest>[];
      final kernel = kernelWith(
        // This draft generator deliberately DROPS the constraint, to
        // prove deterministic code puts it back.
        _constraintDroppingGenerator(model, capture: captured.add),
      );
      final specification = TaskSpecification(
        id: 'spec_faster',
        originalRequest: 'Make this app faster but do not change the '
            'database and keep the UI simple.',
        objective: 'Improve application performance',
        hardConstraints: <SpecificationClaim>[
          const SpecificationClaim.stated(
            'The database must not be modified.',
          ),
        ],
        preferences: <SpecificationClaim>[
          const SpecificationClaim.stated('Keep UI changes minimal.'),
        ],
        successCriteria: <SpecificationClaim>[
          const SpecificationClaim.inferred('Startup is measurably faster.'),
          const SpecificationClaim.inferred('Existing behavior still works.'),
        ],
        source: TaskSpecificationSource.modelUnderstanding,
        confidence: 0.9,
      );
      final result = await kernel.plan(
        specification: specification,
        routing: const RoutingDecision(
          route: PlanningRoute.graph,
          family: TaskFamily.software,
          rationale: 'test',
        ),
        context: contextFor(),
      );

      // The constraint reached the DRAFT generator as a labelled
      // constraint...
      final draftPrompt = captured.first.userPrompt;
      expect(draftPrompt, contains('HARD CONSTRAINTS (never violate these)'));
      expect(draftPrompt, contains('The database must not be modified.'));

      // ...and reached the PLANNING model even though the draft dropped
      // it, because deterministic code re-asserted it as a guardrail.
      final planningPrompt = captured
          .firstWhere(
            (request) => request.systemPrompt.contains('task-planning model'),
          )
          .userPrompt;
      expect(planningPrompt, contains('The database must not be modified.'));

      // ...and is inviolable in the compiled contract the Runner honors.
      final compiled = kernel.compile(
        plan: result.plan,
        project: project,
        mode: CommandMode.build,
      );
      expect(
        compiled.contract.constraints.join(' | '),
        contains('Hard constraint (must not be violated): The database must '
            'not be modified.'),
      );
      // The preference is carried too, but labelled as tradeable.
      expect(
        compiled.contract.constraints.join(' | '),
        contains('Preference (trade off only when it conflicts with the '
            'objective): Keep UI changes minimal.'),
      );
    });
  });

  group('the failure taxonomy at the real planning boundary', () {
    TaskSpecification softwareSpecification() => TaskSpecification(
          id: 'spec_fail',
          originalRequest: mp3Request,
          objective: 'Build an MP3 converter',
        );

    const softwareRouting = RoutingDecision(
      route: PlanningRoute.graph,
      family: TaskFamily.software,
      rationale: 'test',
    );

    test(
        'SCENARIO I: an invalid plan after repair degrades to the '
        'conservative plan, truthfully labelled', () async {
      final kernel = kernelWith(_alwaysInvalidPlanGenerator(model));
      final result = await kernel.plan(
        specification: softwareSpecification(),
        routing: softwareRouting,
        context: contextFor(),
      );
      expect(result.origin, KernelPlanOrigin.conservativeFallback);
      expect(result.isConservative, isTrue);
      expect(result.plan.conservative, isTrue);
      expect(result.failure?.kind, PlanningFailureKind.recoverablePlanning);
      expect(result.failure?.code, 'task_plan_invalid');
      // The conservative plan is honest about what it is.
      expect(result.plan.phases, <String>['Inspect', 'Implement', 'Verify']);
      expect(result.plan.rationale, contains('safety net'));
    });

    test('SCENARIO K: cancellation is NOT answered with a plan', () async {
      final kernel = kernelWith(
        (request) async =>
            throw ProductException('cancelled', 'Execution was cancelled.'),
      );
      await expectLater(
        kernel.plan(
          specification: softwareSpecification(),
          routing: softwareRouting,
          context: contextFor(),
        ),
        throwsA(
          isA<PlanningFailure>().having(
            (failure) => failure.kind,
            'kind',
            PlanningFailureKind.cancelled,
          ),
        ),
      );
    });

    test('SCENARIO J: a persistence failure is NOT answered with a plan',
        () async {
      final kernel = kernelWith(
        (request) async => throw ProductException(
          'storage_corrupt',
          'The task plan store is corrupted.',
        ),
      );
      await expectLater(
        kernel.plan(
          specification: softwareSpecification(),
          routing: softwareRouting,
          context: contextFor(),
        ),
        throwsA(
          isA<PlanningFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                PlanningFailureKind.persistenceFailure,
              )
              .having(
                (failure) => failure.allowsConservativeFallback,
                'allowsConservativeFallback',
                isFalse,
              ),
        ),
      );
    });

    test('an unavailable provider is NOT answered with a plan', () async {
      final kernel = kernelWith(
        (request) async => throw ProductException(
          'model_provider_unavailable',
          'No provider is reachable.',
        ),
      );
      await expectLater(
        kernel.plan(
          specification: softwareSpecification(),
          routing: softwareRouting,
          context: contextFor(),
        ),
        throwsA(
          isA<PlanningFailure>().having(
            (failure) => failure.kind,
            'kind',
            PlanningFailureKind.providerUnavailable,
          ),
        ),
      );
    });

    test('an unexpected programming defect is NOT answered with a plan',
        () async {
      final kernel = kernelWith(
        (request) async => throw StateError('Bad state: no element'),
      );
      await expectLater(
        kernel.plan(
          specification: softwareSpecification(),
          routing: softwareRouting,
          context: contextFor(),
        ),
        throwsA(
          isA<PlanningFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                PlanningFailureKind.unexpected,
              )
              .having(
                (failure) => failure.allowsConservativeFallback,
                'allowsConservativeFallback',
                isFalse,
              ),
        ),
      );
    });

    test('a non-software family never degrades into inspect/implement/verify',
        () async {
      // Degrading a research request into a software lifecycle envelope
      // would be nonsense, so the recoverable failure still surfaces.
      final kernel = UniversalTaskKernel(
        understanding: const UnderstandingService(),
        compiler: UniversalPlanCompiler(tools: ToolRegistry.standard()),
        planners: <TaskFamilyPlanner>[_AlwaysFailingResearchPlanner()],
      );
      await expectLater(
        kernel.plan(
          specification: softwareSpecification(),
          routing: const RoutingDecision(
            route: PlanningRoute.compact,
            family: TaskFamily.research,
            rationale: 'test',
          ),
          context: contextFor(),
        ),
        throwsA(
          isA<PlanningFailure>().having(
            (failure) => failure.kind,
            'kind',
            PlanningFailureKind.recoverablePlanning,
          ),
        ),
      );
    });
  });

  test('every family the product ships is registered in the kernel', () {
    final kernel = kernelWith(_mp3PlanGenerator(model));
    expect(
      kernel.supportedFamilies,
      containsAll(<TaskFamily>[
        TaskFamily.software,
        TaskFamily.research,
        TaskFamily.diagnostics,
        TaskFamily.owner,
      ]),
    );
  });
}

/// A research planner that always fails recoverably, to prove the kernel
/// does not paper over a non-software family with a software envelope.
class _AlwaysFailingResearchPlanner implements TaskFamilyPlanner {
  @override
  TaskFamily get family => TaskFamily.research;

  @override
  bool supports(TaskSpecification specification, PlanningRoute route) => true;

  @override
  Future<UniversalTaskPlan> plan({
    required TaskSpecification specification,
    required PlanningRoute route,
    required PlanningContext context,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  }) async =>
      throw ProductException('task_plan_invalid', 'nope');
}

Map<String, dynamic> _draftJson({List<String> guardrails = const <String>[]}) =>
    <String, dynamic>{
      'title': 'MP3 to URL converter',
      'purpose': 'Convert an uploaded MP3 file into a downloadable result.',
      'systemPrompt':
          'Act as a careful Flutter web engineer. Keep the UX minimal.',
      'userPrompt': 'Build a simple MP3-to-URL converter for {{platform}}.',
      'variables': <String>['platform'],
      'assumptions': <String>['No accounts or authentication are required.'],
      'clarifyingQuestions': <String>[],
      'acceptanceCriteria': <String>[
        'A user can upload an mp3 and download the converted result.',
      ],
      'outputExpectations': <String>['Application source', 'Automated tests'],
      'guardrails': guardrails,
      'stopConditions': <String>[],
      'evaluationCases': <String>['An uploaded mp3 produces a download link.'],
      'mode': 'build',
    };

Map<String, dynamic> _taskJson({
  required String id,
  required String phase,
  String? parentId,
  required String title,
  required String objective,
  List<String> dependencies = const <String>[],
}) =>
    <String, dynamic>{
      'id': id,
      'phase': phase,
      'parentId': parentId,
      'title': title,
      'objective': objective,
      'instructions': objective,
      'dependencies': dependencies,
      'acceptanceCriteria': <String>['$title is observably complete.'],
      'verificationSteps': <String>['Run the detected analyzer and tests.'],
      'expectedArtifacts': <String>['Updated project source'],
      'allowedTools': <String>['read_file', 'write_file', 'verify_project'],
      'complexity': 3,
      'effortPoints': 3,
      'uncertainty': 'low',
      'risk': 'low',
      'estimateConfidence': 0.8,
      'expectedModelTurns': 3,
      'expectedToolCalls': 4,
      'maxAttempts': 2,
      'enabled': true,
      'manual': false,
    };

ModelGenerationResult _resultFor(
  ModelIdentity model,
  Map<String, dynamic> payload,
) {
  final now = DateTime.now().toUtc();
  return ModelGenerationResult(
    text: jsonEncode(payload),
    identity: model,
    startedAt: now,
    firstTokenAt: now,
    completedAt: now,
    inputTokens: 20,
    outputTokens: 40,
  );
}

Map<String, dynamic> _mp3PlanJson() => <String, dynamic>{
      'title': 'MP3 to URL delivery plan',
      'rationale': 'Build the upload/convert/download flow incrementally.',
      'tasks': <Map<String, dynamic>>[
        _taskJson(
          id: 'task_001',
          phase: 'Foundation',
          title: 'Define upload and conversion flow',
          objective: 'Decide the upload -> convert -> download data flow.',
        ),
        _taskJson(
          id: 'task_002',
          phase: 'UI',
          parentId: 'task_001',
          dependencies: <String>['task_001'],
          title: 'Build upload and progress bar UI',
          objective: 'Implement the upload control and progress indicator.',
        ),
        _taskJson(
          id: 'task_003',
          phase: 'Conversion',
          parentId: 'task_001',
          dependencies: <String>['task_001'],
          title: 'Implement mp3 conversion service boundary',
          objective: 'Implement the conversion service and its interface.',
        ),
        _taskJson(
          id: 'task_004',
          phase: 'UI',
          parentId: 'task_002',
          dependencies: <String>['task_002', 'task_003'],
          title: 'Build download result UI',
          objective: 'Implement the download button and result state.',
        ),
        _taskJson(
          id: 'task_005',
          phase: 'Qualification',
          parentId: 'task_001',
          dependencies: <String>['task_004'],
          title: 'Verify end-to-end conversion',
          objective: 'Verify an uploaded mp3 produces a downloadable result.',
        ),
      ],
    };

/// Understanding fixture: a deterministic structured reading of the MP3
/// request. Deterministic on purpose -- the assertions are about what the
/// validator did with it, not about the fixture being intelligent.
ModelGenerationDelegate _mp3UnderstandingGenerator(ModelIdentity model) =>
    (request) async => _resultFor(model, <String, dynamic>{
          'objective': 'Build a Flutter web MP3 converter',
          'subObjectives': <String>[
            'upload an MP3 file',
            'show conversion progress',
            'download the converted result',
          ],
          'capabilityHints': <String>['agent.create_project'],
          'targets': <String>[],
          'hardConstraints': <String>['No accounts or authentication'],
          'preferences': <String>['Simple UX'],
          'successCriteria': <String>[
            'An uploaded MP3 produces a downloadable result',
            'Progress is visible during conversion',
          ],
          'assumptions': <String>[],
          'unresolvedQuestions': <String>[],
          'confidence': 0.9,
        });

ModelGenerationDelegate _mp3PlanGenerator(
  ModelIdentity model, {
  void Function(ModelGenerationRequest request)? capture,
}) =>
    (request) async {
      capture?.call(request);
      final isPlan = request.systemPrompt.contains('task-planning model');
      if (!isPlan) {
        return _resultFor(
          model,
          _draftJson(guardrails: <String>['Do not add account logic.']),
        );
      }
      return _resultFor(model, _mp3PlanJson());
    };

/// A draft generator that returns NO guardrails, so the test can prove
/// deterministic code re-asserts the specification's hard constraint.
ModelGenerationDelegate _constraintDroppingGenerator(
  ModelIdentity model, {
  void Function(ModelGenerationRequest request)? capture,
}) =>
    (request) async {
      capture?.call(request);
      final isPlan = request.systemPrompt.contains('task-planning model');
      if (!isPlan) return _resultFor(model, _draftJson());
      return _resultFor(model, _mp3PlanJson());
    };

ModelGenerationDelegate _alwaysInvalidPlanGenerator(ModelIdentity model) =>
    (request) async {
      final isPlan = request.systemPrompt.contains('task-planning model');
      if (!isPlan) return _resultFor(model, _draftJson());
      // A dependency on a task ID that is never defined fails validation
      // on both the initial attempt and the bounded repair attempt.
      return _resultFor(model, <String, dynamic>{
        'title': 'Broken plan',
        'rationale': 'Intentionally invalid for the fallback regression test.',
        'tasks': <Map<String, dynamic>>[
          _taskJson(
            id: 'task_001',
            phase: 'Foundation',
            dependencies: <String>['task_999'],
            title: 'Depends on a task that does not exist',
            objective: 'This can never validate.',
          ),
        ],
      });
    };
