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
import 'package:kristin_local_agent/product/task_kernel/runtime_gateway.dart';
import 'package:kristin_local_agent/product/task_kernel/task_families.dart';
import 'package:kristin_local_agent/product/task_kernel/task_kernel.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

/// CASE G: the coordinator/executor boundary on the real /create path.
///
///     USER CAPABILITY != EXECUTION TOOL
///
/// `agent.create_project` provisions the workspace once, before any work
/// item exists. After that it is spent. The production bug was that it
/// survived into the execution model's world -- as a briefing line the
/// planner turned into "Use the agent.create_project capability", and as
/// a requiredCapability on every generated task -- while the Runner's
/// allow-list contained no such tool.
void main() {
  late Directory temporary;
  late ProductRepositories repositories;
  late EventJournal events;
  late AuditChain audit;
  late ModelIdentity model;
  late ProjectRecord project;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('kristin-boundary-');
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
      name: 'deterministic-boundary',
      digest: 'sha256:boundary',
      discoveredAt: DateTime.utc(2026, 8, 28),
    );
    project = ProjectRecord(
      id: 'project-mp3',
      name: 'MP3 converter',
      rootPath: temporary.path,
      createdAt: DateTime.utc(2026, 8, 28),
      updatedAt: DateTime.utc(2026, 8, 28),
    );
    await repositories.projects.put(project);
  });

  tearDown(() async {
    await events.close();
    if (await temporary.exists()) {
      // Windows can hold SQLite handles briefly after close; retry rather
      // than failing the test on a transient sharing violation.
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

  UniversalTaskKernel kernelWith(
    ModelGenerationDelegate generator, {
    void Function(ModelGenerationRequest request)? capture,
  }) {
    final redactor = SecretRedactor();
    final vault = SecretVault(repositories.secretReferences, redactor, audit);
    final registry = ModelRegistry(
      settings: const ProductSettings(ollamaBaseUrl: ''),
      vault: vault,
      redactor: redactor,
    );
    return buildUniversalTaskKernel(
      planning: PromptPlanningService(
        models: registry,
        repositories: repositories,
        audit: audit,
        events: events,
        redactor: redactor,
        tools: ToolRegistry.standard(),
        generator: (request) {
          capture?.call(request);
          return generator(request);
        },
      ),
      tools: ToolRegistry.standard(),
      models: registry,
    );
  }

  TaskSpecification createSpecification() => TaskSpecification(
        id: 'spec_create',
        originalRequest: '/create flutter web application to convert mp3 '
            'files to URLs, simple UI, upload/download, progress bar',
        objective: 'Build a Flutter web MP3-to-URL converter',
        // Chat routed this to agent.create_project. The hint is
        // orchestration metadata -- it records what Chat did, not what
        // the executor should do.
        capabilityHints: const <String>['agent.create_project'],
        source: TaskSpecificationSource.modelUnderstanding,
        confidence: 0.9,
      );

  const routing = RoutingDecision(
    route: PlanningRoute.graph,
    family: TaskFamily.software,
    rationale: 'test',
  );

  PlanningContext contextFor() => PlanningContext(
        project: project,
        model: model,
        availableCapabilityIds:
            kKristinCapabilities.map((item) => item.id).toSet(),
        availableToolNames: ToolRegistry.standard().names,
        consumedCoordinatorCapabilities: const <String>{
          'agent.create_project',
        },
      );

  test('the coordinator capability set is derived from routes, not a list', () {
    expect(
      kCoordinatorCapabilityIds,
      containsAll(<String>[
        'agent.create_project',
        'agent.modify_project',
        'agent.fix_project',
      ]),
    );
    // Execution-shaped capabilities must NOT be classed as coordinator.
    expect(kCoordinatorCapabilityIds, isNot(contains('research.search')));
    expect(kCoordinatorCapabilityIds, isNot(contains('project.build')));
    expect(kCoordinatorCapabilityIds, isNot(contains('system.diagnose')));
  });

  test('the planning model is never briefed on coordinator capabilities',
      () async {
    final captured = <ModelGenerationRequest>[];
    final kernel = kernelWith(
      _validPlanGenerator(model),
      capture: captured.add,
    );
    await kernel.plan(
      specification: createSpecification(),
      routing: routing,
      context: contextFor(),
    );
    final planningPrompt = captured
        .firstWhere(
          (request) => request.systemPrompt.contains('task-planning model'),
        )
        .userPrompt;
    // The briefing exists and names real execution capabilities...
    expect(planningPrompt, contains('AVAILABLE KRISTIN CAPABILITIES'));
    expect(planningPrompt, contains('research.search'));
    // ...but never the orchestration ones, which is what taught the
    // planner to emit "Use the agent.create_project capability".
    for (final coordinator in kCoordinatorCapabilityIds) {
      expect(
        planningPrompt.contains('- $coordinator:'),
        isFalse,
        reason: '$coordinator must not be offered to the planner',
      );
    }
    expect(
      planningPrompt,
      contains('never write an instruction telling the executor to create'),
    );
  });

  test('no generated task carries a coordinator capability', () async {
    final kernel = kernelWith(_validPlanGenerator(model));
    final result = await kernel.plan(
      specification: createSpecification(),
      routing: routing,
      context: contextFor(),
    );
    expect(result.plan.tasks, isNotEmpty);
    for (final task in result.plan.tasks) {
      expect(
        task.requiredCapabilities.intersection(kCoordinatorCapabilityIds),
        isEmpty,
        reason: '${task.id} must not require an orchestration capability',
      );
    }
    expect(
      result.plan.requiredCapabilities.contains('agent.create_project'),
      isFalse,
    );
  });

  test('the compiled work items are concrete, tool-shaped, and single-project',
      () async {
    final kernel = kernelWith(_validPlanGenerator(model));
    final result = await kernel.plan(
      specification: createSpecification(),
      routing: routing,
      context: contextFor(),
    );
    final compiled = kernel.compile(
      plan: result.plan,
      project: project,
      mode: CommandMode.build,
      consumedCoordinatorCapabilities: const <String>{'agent.create_project'},
    );
    expect(compiled.plan.validate(), isEmpty);
    expect(compiled.plan.items, isNotEmpty);
    for (final item in compiled.plan.items) {
      // No phantom tool.
      expect(item.allowedTools, isNot(contains('create_project')));
      expect(
        item.allowedTools.intersection(kCoordinatorCapabilityIds),
        isEmpty,
      );
      // No instruction naming an orchestration capability.
      for (final coordinator in kCoordinatorCapabilityIds) {
        expect(
          item.description.contains(coordinator),
          isFalse,
          reason: '${item.id} instructs the executor to use $coordinator',
        );
      }
      // Only governed Runner tools survive.
      expect(item.allowedTools, isNotEmpty);
      expect(
        ToolRegistry.standard().names.containsAll(item.allowedTools),
        isTrue,
      );
    }
  });

  test(
      'a leaked coordinator instruction fails compile with a precise '
      'diagnostic instead of reaching the model', () async {
    // The defect this guard exists for: a planner that still writes
    // "Use the agent.create_project capability" into a task.
    final kernel = kernelWith(_leakyPlanGenerator(model));
    final result = await kernel.plan(
      specification: createSpecification(),
      routing: routing,
      context: contextFor(),
    );
    expect(
      () => kernel.compile(
        plan: result.plan,
        project: project,
        mode: CommandMode.build,
        consumedCoordinatorCapabilities: const <String>{
          'agent.create_project',
        },
      ),
      throwsA(
        isA<ProductException>()
            .having(
              (error) => error.code,
              'code',
              'plan_executor_capability_unresolved',
            )
            .having(
              (error) => error.details['capabilityId'],
              'capabilityId',
              contains('agent.create_project'),
            )
            .having(
              (error) => error.details['taskId'],
              'taskId',
              isNotEmpty,
            ),
      ),
    );
  });

  test('a required coordinator capability also fails compile', () {
    final specification = createSpecification();
    final plan = UniversalTaskPlan(
      id: 'plan_leak',
      specification: specification,
      family: TaskFamily.software,
      route: PlanningRoute.graph,
      title: 'Leaky plan',
      rationale: 'test',
      tasks: <UniversalTask>[
        const UniversalTask(
          id: 'task_001',
          title: 'Initialize the project',
          objective: 'Set up the workspace',
          instructions: 'Set up the workspace.',
          phase: 'Project Initialization',
          acceptanceCriteria: <String>['exists'],
          verificationSteps: <String>['check'],
          allowedTools: <String>{'write_file'},
          requiredCapabilities: <String>{'agent.create_project'},
        ),
      ],
    );
    expect(
      () => UniversalPlanCompiler(tools: ToolRegistry.standard()).compile(
        plan: plan,
        project: project,
        mode: CommandMode.build,
        request: specification.originalRequest,
        consumedCoordinatorCapabilities: const <String>{
          'agent.create_project',
        },
      ),
      throwsA(
        isA<ProductException>().having(
          (error) => error.code,
          'code',
          'plan_executor_capability_unresolved',
        ),
      ),
    );
  });
}

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
  );
}

Map<String, dynamic> _draftJson() => <String, dynamic>{
      'title': 'MP3 to URL converter',
      'purpose': 'Convert an uploaded MP3 into a downloadable result.',
      'systemPrompt': 'Act as a careful Flutter web engineer.',
      'userPrompt': 'Build a simple MP3-to-URL converter.',
      'variables': <String>[],
      'assumptions': <String>[],
      'clarifyingQuestions': <String>[],
      'acceptanceCriteria': <String>['An uploaded mp3 produces a download.'],
      'outputExpectations': <String>['Application source'],
      'guardrails': <String>[],
      'stopConditions': <String>[],
      'evaluationCases': <String>['Upload produces a link.'],
      'mode': 'build',
    };

Map<String, dynamic> _task({
  required String id,
  required String title,
  required String instructions,
  List<String> dependencies = const <String>[],
}) =>
    <String, dynamic>{
      'id': id,
      'phase': 'Implementation',
      'parentId': null,
      'title': title,
      'objective': title,
      'instructions': instructions,
      'dependencies': dependencies,
      'acceptanceCriteria': <String>['$title is complete.'],
      'verificationSteps': <String>['Run the detected analyzer and tests.'],
      'expectedArtifacts': <String>['lib/main.dart'],
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

/// A well-behaved planner: concrete, tool-shaped instructions.
ModelGenerationDelegate _validPlanGenerator(ModelIdentity model) =>
    (request) async {
      if (!request.systemPrompt.contains('task-planning model')) {
        return _resultFor(model, _draftJson());
      }
      return _resultFor(model, <String, dynamic>{
        'title': 'MP3 converter delivery plan',
        'rationale': 'Build the upload/convert/download flow.',
        'tasks': <Map<String, dynamic>>[
          _task(
            id: 'task_001',
            title: 'Write the upload screen',
            instructions: 'Write lib/upload_screen.dart with the upload '
                'control and a progress indicator.',
          ),
          _task(
            id: 'task_002',
            title: 'Write the conversion service',
            instructions: 'Write lib/conversion_service.dart implementing '
                'the mp3 conversion boundary.',
            dependencies: <String>['task_001'],
          ),
        ],
      });
    };

/// The regression shape: a planner that still names the coordinator
/// capability in a task instruction.
ModelGenerationDelegate _leakyPlanGenerator(ModelIdentity model) =>
    (request) async {
      if (!request.systemPrompt.contains('task-planning model')) {
        return _resultFor(model, _draftJson());
      }
      return _resultFor(model, <String, dynamic>{
        'title': 'MP3 converter delivery plan',
        'rationale': 'Initialize then build.',
        'tasks': <Map<String, dynamic>>[
          _task(
            id: 'task_001',
            title: 'Initialize a new Flutter web application project',
            instructions: 'Use the "agent.create_project" capability to '
                'create a new Flutter web application project.',
          ),
        ],
      });
    };
