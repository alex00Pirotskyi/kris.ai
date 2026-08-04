import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/prompt_planning.dart';
import 'package:kristin_local_agent/product/project_diagnostics.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

void main() {
  group('v1 workspace path compatibility', () {
    late Directory project;
    late Directory outside;
    late WorkspaceBoundary boundary;

    setUp(() async {
      project = await Directory.systemTemp.createTemp('kristin-v1-project-');
      outside = await Directory.systemTemp.createTemp('kristin-v1-outside-');
      await Directory('${project.path}${Platform.pathSeparator}lib')
          .create(recursive: true);
      await File(
        '${project.path}${Platform.pathSeparator}lib'
        '${Platform.pathSeparator}main.dart',
      ).writeAsString('void main() {}\n');
      boundary = await WorkspaceBoundary.open(project.path);
    });

    tearDown(() async {
      if (await project.exists()) {
        await project.delete(recursive: true);
      }
      if (await outside.exists()) {
        await outside.delete(recursive: true);
      }
    });

    test('normalizes in-project absolute paths to project-relative paths', () {
      final absolute = File(
        '${project.path}${Platform.pathSeparator}lib'
        '${Platform.pathSeparator}main.dart',
      ).absolute.path;

      expect(boundary.normalizeToolPath(project.absolute.path), '.');
      expect(boundary.normalizeToolPath(absolute), 'lib/main.dart');
      expect(boundary.normalizeToolPath('"$absolute"'), 'lib/main.dart');
      expect(boundary.normalizeToolPath('./lib//main.dart'), 'lib/main.dart');
      expect(
        boundary.normalizeToolPath(File(absolute).uri.toString()),
        'lib/main.dart',
      );
    });

    test(
      'accepts an in-project absolute path when the project root sits '
      'behind a reparse point',
      () async {
        if (!Platform.isWindows) {
          return;
        }
        final real = await Directory.systemTemp.createTemp('kristin-v1-real-');
        final linked = Link(
          '${outside.path}${Platform.pathSeparator}linked-project',
        );
        try {
          await Directory(
            '${real.path}${Platform.pathSeparator}lib',
          ).create(recursive: true);
          await File(
            '${real.path}${Platform.pathSeparator}lib'
            '${Platform.pathSeparator}main.dart',
          ).writeAsString('void main() {}\n');
          await linked.create(real.path);

          final linkedBoundary = await WorkspaceBoundary.open(linked.path);
          final realAbsolute = File(
            '${real.path}${Platform.pathSeparator}lib'
            '${Platform.pathSeparator}main.dart',
          ).absolute.path;

          expect(
            linkedBoundary.normalizeToolPath(realAbsolute),
            'lib/main.dart',
          );
        } finally {
          if (await linked.exists()) {
            await linked.delete();
          }
          if (await real.exists()) {
            await real.delete(recursive: true);
          }
        }
      },
    );

    test('detects Kristin source checkouts before mutating runs', () async {
      await File(
        '${project.path}${Platform.pathSeparator}pubspec.yaml',
      ).writeAsString('name: kristin_local_agent\n');
      await Directory(
        '${project.path}${Platform.pathSeparator}lib'
        '${Platform.pathSeparator}product',
      ).create(recursive: true);
      await File(
        '${project.path}${Platform.pathSeparator}lib'
        '${Platform.pathSeparator}product'
        '${Platform.pathSeparator}product_runtime.dart',
      ).writeAsString('// fixture\n');
      await File(
        '${project.path}${Platform.pathSeparator}lib'
        '${Platform.pathSeparator}product'
        '${Platform.pathSeparator}planning_runtime.dart',
      ).writeAsString('// fixture\n');

      expect(await boundary.isKristinSourceCheckout(), isTrue);
      expect(
          await WorkspaceBoundary.open(outside.path)
              .then((value) => value.isKristinSourceCheckout()),
          isFalse);
    });

    test('continues to reject absolute paths outside the active project', () {
      final outsidePath = File(
        '${outside.path}${Platform.pathSeparator}secret.txt',
      ).absolute.path;

      expect(
        () => boundary.normalizeToolPath(outsidePath),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'path_outside_project',
          ),
        ),
      );
      expect(
        () => boundary.normalizeToolPath('../outside.txt'),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'path_traversal_rejected',
          ),
        ),
      );
    });

    test('rebases recognized virtual workspace paths into the selected project',
        () async {
      String virtualPath(String relative) {
        if (Platform.isWindows) {
          return 'C:\\workspace\\project\\${relative.replaceAll('/', '\\')}';
        }
        return '/workspace/project/$relative';
      }

      final readRecovery = await boundary.recoverExternalToolPath(
        virtualPath('lib/main.dart'),
        allowMissing: false,
        allowRootFallback: false,
        allowUnanchoredExistingSuffix: true,
      );
      expect(readRecovery?.path, 'lib/main.dart');
      expect(readRecovery?.strategy, 'virtual_workspace_alias');

      final writeRecovery = await boundary.recoverExternalToolPath(
        virtualPath('generated/result.txt'),
        allowMissing: true,
        allowRootFallback: false,
        allowUnanchoredExistingSuffix: false,
      );
      expect(writeRecovery?.path, 'generated/result.txt');
      expect(writeRecovery?.strategy, 'virtual_workspace_alias');

      final sensitiveRecovery = await boundary.recoverExternalToolPath(
        virtualPath('.env'),
        allowMissing: true,
        allowRootFallback: false,
        allowUnanchoredExistingSuffix: false,
      );
      expect(sensitiveRecovery, isNull);
    });

    test(
        'rebases stale same-project paths but blocks arbitrary external writes',
        () async {
      final rootName =
          project.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
      final stalePath = File(
        '${outside.path}${Platform.pathSeparator}$rootName'
        '${Platform.pathSeparator}lib${Platform.pathSeparator}main.dart',
      ).absolute.path;
      final staleRecovery = await boundary.recoverExternalToolPath(
        stalePath,
        allowMissing: false,
        allowRootFallback: false,
        allowUnanchoredExistingSuffix: true,
      );
      expect(staleRecovery?.path, 'lib/main.dart');
      expect(staleRecovery?.strategy, 'project_name_anchor');

      final arbitraryWrite = File(
        '${outside.path}${Platform.pathSeparator}new-project'
        '${Platform.pathSeparator}lib${Platform.pathSeparator}main.dart',
      ).absolute.path;
      final blocked = await boundary.recoverExternalToolPath(
        arbitraryWrite,
        allowMissing: true,
        allowRootFallback: false,
        allowUnanchoredExistingSuffix: false,
      );
      expect(blocked, isNull);
    });

    test('root-scoped read recovery falls back to the active project root',
        () async {
      final arbitraryOutside = File(
        '${outside.path}${Platform.pathSeparator}unrelated'
        '${Platform.pathSeparator}missing',
      ).absolute.path;
      final recovery = await boundary.recoverExternalToolPath(
        arbitraryOutside,
        allowMissing: false,
        allowRootFallback: true,
        allowUnanchoredExistingSuffix: true,
      );
      expect(recovery?.path, '.');
      expect(recovery?.strategy, 'active_project_root');
    });
  });

  group('v1 Prompt Studio and adaptive task plans', () {
    late Directory temporary;
    late AppDirectories directories;
    late ProductRepositories repositories;
    late EventJournal events;
    late AuditChain audit;
    late PromptPlanningService service;
    late ModelIdentity model;
    late ProjectRecord project;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('kristin-v1-planning-');
      directories = await AppDirectories.create(
        overrideRoot: '${temporary.path}${Platform.pathSeparator}app-data',
      );
      repositories = await ProductRepositories.open(directories);
      final redactor = SecretRedactor();
      events = EventJournal(repositories.eventFile);
      await events.open();
      audit = AuditChain(repositories.auditFile, redactor);
      await audit.open();
      final vault = SecretVault(
        repositories.secretReferences,
        redactor,
        audit,
      );
      model = ModelIdentity(
        providerId: 'fixture',
        name: 'deterministic-v1',
        digest: 'sha256:v1-fixture',
        discoveredAt: DateTime.utc(2026, 7, 16),
      );
      project = ProjectRecord(
        id: 'project-v1',
        name: 'V1 fixture',
        rootPath: temporary.path,
        createdAt: DateTime.utc(2026, 7, 16),
        updatedAt: DateTime.utc(2026, 7, 16),
      );
      await repositories.projects.put(project);
      service = PromptPlanningService(
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
        generator: _fixtureGenerator(model),
      );
    });

    tearDown(() async {
      await events.close();
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });

    test('generates, versions, plans, revises, and compiles deterministically',
        () async {
      final draft = await service.generatePrompt(
        goal: 'Build a calculator application with standard math functions.',
        model: model,
      );
      expect(draft.title, 'Modern calculator');
      expect(draft.validate(), isEmpty);

      final version1 = await service.savePromptVersion(
        promptId: 'prompt-v1',
        sourceGoal:
            'Build a calculator application with standard math functions.',
        action: PromptGenerationAction.generate,
        draft: draft,
        model: model,
      );
      final version2 = await service.savePromptVersion(
        promptId: 'prompt-v1',
        sourceGoal:
            'Build a calculator application with standard math functions.',
        action: PromptGenerationAction.improve,
        draft: draft.copyWith(
          guardrails: <String>[
            ...draft.guardrails,
            'Never silently discard invalid input.',
          ],
        ),
        model: model,
      );
      expect(version1.versionNumber, 1);
      expect(version2.versionNumber, 2);
      expect(await service.listPromptVersions('prompt-v1'), hasLength(2));

      final plan = await service.generateTaskPlan(
        promptVersion: version2,
        projectId: project.id,
        model: model,
        depth: PlanningDepth.auto,
        maxLeafTasks: 100,
      );
      expect(plan.revision, 1);
      expect(plan.tasks, hasLength(8));
      expect(plan.validate(), isEmpty);
      expect(plan.tasks.first.allowedTools, contains('knowledge_search'));
      expect(plan.tasks.first.allowedTools, isNot(contains('research_search')));
      expect(plan.tasks.first.allowedTools, isNot(contains('research_fetch')));
      expect(plan.tasks.first.instructions, contains('Local-only constraint'));
      expect(plan.tasks[1].dependencies, contains('task_001'));
      expect(plan.tasks[1].parentId, 'task_001');
      expect(plan.tasks[1].allowedTools, contains('verify_project'));
      expect(plan.tasks[2].title,
          'Create project-local wireframes and user flows');
      expect(plan.tasks[2].allowedTools, contains('write_file'));
      expect(
        plan.tasks[2].expectedArtifacts,
        contains('Project-local responsive design prototype'),
      );
      expect(plan.tasks[2].instructions, contains('Do not claim use of Figma'));
      expect(plan.tasks[2].instructions, contains('Approved product context'));
      expect(plan.tasks[2].instructions.toLowerCase(), contains('calculator'));
      expect(plan.tasks[2].instructions, isNot(contains('Use Figma to')));
      expect(plan.tasks[2].allowedTools, isNot(contains('run_command')));
      expect(plan.tasks[2].allowedTools, isNot(contains('write_binary_file')));
      expect(plan.tasks[2].allowedTools, isNot(contains('git_status')));
      expect(plan.tasks[2].allowedTools, isNot(contains('mcp_call')));
      expect(
        plan.tasks[3].title,
        'Run local usability and interaction verification',
      );
      expect(
        plan.tasks[3].expectedArtifacts,
        contains('docs/testing/usability-checklist.md'),
      );
      expect(plan.tasks[3].allowedTools, contains('verify_project'));
      expect(
          plan.tasks[3].instructions, contains('Do not recruit participants'));
      expect(
          plan.tasks[3].instructions, isNot(contains('Recruit participants')));
      expect(plan.tasks[3].maxAttempts, 2);
      expect(plan.tasks[3].manual, isFalse);
      final deploymentTask = plan.tasks.firstWhere(
        (task) => task.title == 'Prepare local preview and deployment package',
      );
      expect(deploymentTask.allowedTools, contains('package_deployment'));
      expect(deploymentTask.allowedTools, contains('start_process'));
      final deploymentInstructions = deploymentTask.instructions.toLowerCase();
      expect(
        deploymentInstructions,
        contains('do not deploy to an external service'),
      );
      expect(deploymentInstructions, isNot(contains('deploy the calculator')));
      expect(deploymentInstructions, contains('do not claim a public url'));

      final setupTask = plan.tasks.firstWhere(
        (task) => task.title == 'Initialize the selected project workspace',
      );
      expect(setupTask.instructions, contains('selected project root'));
      expect(setupTask.instructions, contains('Do not install Node.js'));
      expect(setupTask.instructions,
          isNot(contains('Create a new project directory')));
      expect(setupTask.allowedTools, isNot(contains('run_command')));
      expect(setupTask.allowedTools, isNot(contains('mcp_call')));

      final calculationTask = plan.tasks.firstWhere(
        (task) =>
            task.title ==
            'Implement the client-side calculation engine and session history',
      );
      expect(calculationTask.instructions,
          contains('unnecessary Express/REST backend'));
      expect(calculationTask.instructions, contains('division-by-zero'));
      expect(calculationTask.instructions, isNot(contains('Install Express')));
      expect(calculationTask.allowedTools, isNot(contains('mcp_call')));
      expect(calculationTask.expectedArtifacts,
          contains('Session calculation history'));

      final testingTask = plan.tasks.firstWhere(
        (task) => task.id == 'task_008',
      );
      expect(testingTask.title, 'Conduct Comprehensive Testing of Calculator');
      expect(
        testingTask.title,
        isNot(
            'Implement the client-side calculation engine and session history'),
      );
      expect(testingTask.allowedTools, contains('verify_project'));
      expect(testingTask.expectedArtifacts, contains('Test results'));

      final editedTasks = plan.tasks
          .map(
            (task) => task.id == 'task_002'
                ? task.copyWith(title: 'Implement and verify calculator UI')
                : task,
          )
          .toList(growable: false);
      final revision = await service.updateTaskPlan(
        plan,
        tasks: editedTasks,
      );
      expect(revision.id, isNot(plan.id));
      expect(revision.revision, 2);
      expect(revision.previousPlanId, plan.id);
      expect(await service.listTaskPlans(projectId: project.id), hasLength(2));

      final prepared = await service.compilePlan(
        plan: revision,
        promptVersion: version2,
        project: project,
        model: model,
        selectedTaskIds: const <String>{'task_002'},
      );
      expect(
        prepared.plan.items.map((item) => item.id),
        <String>['task_001', 'task_002'],
        reason: 'selected execution must include transitive dependencies',
      );
      expect(prepared.contract.revision, 3);
      expect(
        prepared.contract.requiredPermissions,
        containsAll(<PermissionScope>{
          PermissionScope.projectRead,
          PermissionScope.projectWrite,
          PermissionScope.executeFinite,
        }),
      );
    });

    test('promotes artifact-producing plan tasks to governed build work',
        () async {
      const draft = PromptStudioDraft(
        title: 'Calculator delivery plan',
        purpose: 'Create a calculator application and its design artifacts.',
        systemPrompt:
            'Act as a careful product engineer and create project-local artifacts with objective evidence.',
        userPrompt:
            'Create wireframes and user flows, then implement the calculator application.',
        variables: <String>[],
        assumptions: <String>[],
        clarifyingQuestions: <String>[],
        acceptanceCriteria: <String>[
          'Project-local wireframes and user flows are created.',
        ],
        outputExpectations: <String>['docs/design/wireframes.md'],
        guardrails: <String>['Stay inside the active project.'],
        stopConditions: <String>[],
        evaluationCases: <String>[],
        mode: CommandMode.plan,
      );
      final version = PromptVersionRecord(
        id: 'prompt-version-plan-artifact',
        promptId: 'prompt-plan-artifact',
        versionNumber: 1,
        sourceGoal:
            'Build a calculator app and create wireframes and user flows.',
        action: PromptGenerationAction.generate,
        draft: draft,
        model: model,
        contentHash: Sha256.text('prompt-version-plan-artifact'),
        createdBy: 'test',
        createdAt: DateTime.utc(2026, 7, 20),
      );
      final task = PlanTaskRecord(
        id: 'task_001',
        phase: 'Design',
        parentId: null,
        title: 'Create Wireframes and User Flows',
        objective: 'Produce an inspectable calculator design artifact.',
        instructions:
            'Create project-local wireframes and user-flow documentation.',
        dependencies: const <String>{},
        acceptanceCriteria: const <String>[
          'The wireframe artifact exists and describes the main calculator states.',
        ],
        verificationSteps: const <String>[
          'Inspect the created wireframe artifact.',
        ],
        expectedArtifacts: const <String>['docs/design/wireframes.md'],
        allowedTools: const <String>{'list_directory', 'read_file'},
        complexity: 3,
        effortPoints: 3,
        uncertainty: PlanUncertainty.low,
        risk: PlanRisk.low,
        estimateConfidence: 0.9,
        expectedModelTurns: 4,
        expectedToolCalls: 5,
        maxAttempts: 2,
        enabled: true,
        manual: false,
      );
      final plan = TaskPlanRecord(
        id: 'plan-artifact',
        promptId: version.promptId,
        promptVersionId: version.id,
        projectId: project.id,
        revision: 1,
        previousPlanId: null,
        title: 'Calculator artifact plan',
        rationale: 'Exercise capability-aligned compilation.',
        depth: PlanningDepth.compact,
        maxLeafTasks: 1,
        tasks: <PlanTaskRecord>[task],
        model: model,
        contentHash: Sha256.text('plan-artifact'),
        createdAt: DateTime.utc(2026, 7, 20),
        updatedAt: DateTime.utc(2026, 7, 20),
      );

      final prepared = await service.compilePlan(
        plan: plan,
        promptVersion: version,
        project: project,
        model: model,
      );

      expect(prepared.contract.mode, CommandMode.build);
      expect(
        prepared.contract.requiredPermissions,
        contains(PermissionScope.projectWrite),
      );
      expect(
        prepared.plan.items.single.allowedTools,
        containsAll(<String>[
          'inspect_file',
          'write_file',
          'replace_text',
          'apply_patch',
        ]),
      );
    });

    test('keeps an explicitly planning-only task read-only', () async {
      const draft = PromptStudioDraft(
        title: 'Calculator architecture proposal',
        purpose: 'Prepare an architecture proposal without implementation.',
        systemPrompt:
            'Analyze the project and return a read-only architecture proposal.',
        userPrompt: 'Plan only. Do not implement or change project files.',
        variables: <String>[],
        assumptions: <String>[],
        clarifyingQuestions: <String>[],
        acceptanceCriteria: <String>[
          'The proposal identifies components and risks.',
        ],
        outputExpectations: <String>['Architecture proposal in the response'],
        guardrails: <String>['No code changes.'],
        stopConditions: <String>[],
        evaluationCases: <String>[],
        mode: CommandMode.plan,
      );
      final version = PromptVersionRecord(
        id: 'prompt-version-plan-only',
        promptId: 'prompt-plan-only',
        versionNumber: 1,
        sourceGoal: 'Plan only; do not implement the calculator.',
        action: PromptGenerationAction.generate,
        draft: draft,
        model: model,
        contentHash: Sha256.text('prompt-version-plan-only'),
        createdBy: 'test',
        createdAt: DateTime.utc(2026, 7, 20),
      );
      final task = _task('task_plan_only').copyWith(
        title: 'Plan calculator architecture',
        objective: 'Describe the architecture without implementation.',
        instructions: 'Read-only analysis. Do not implement or change files.',
        expectedArtifacts: <String>['Architecture proposal in final response'],
        allowedTools: const <String>{'list_directory', 'read_file'},
      );
      final plan = TaskPlanRecord(
        id: 'plan-only',
        promptId: version.promptId,
        promptVersionId: version.id,
        projectId: project.id,
        revision: 1,
        previousPlanId: null,
        title: 'Read-only plan',
        rationale: 'Exercise explicit planning-only behavior.',
        depth: PlanningDepth.compact,
        maxLeafTasks: 1,
        tasks: <PlanTaskRecord>[task],
        model: model,
        contentHash: Sha256.text('plan-only'),
        createdAt: DateTime.utc(2026, 7, 20),
        updatedAt: DateTime.utc(2026, 7, 20),
      );

      final prepared = await service.compilePlan(
        plan: plan,
        promptVersion: version,
        project: project,
        model: model,
      );

      expect(prepared.contract.mode, CommandMode.plan);
      expect(
        prepared.contract.requiredPermissions,
        isNot(contains(PermissionScope.projectWrite)),
      );
      expect(
        prepared.plan.items.single.allowedTools,
        isNot(contains('write_file')),
      );
    });

    test('accepts a valid 100-task plan and rejects dependency cycles', () {
      final tasks = List<PlanTaskRecord>.generate(100, (index) {
        final id = 'task_${(index + 1).toString().padLeft(3, '0')}';
        return _task(
          id,
          dependencies: index == 0
              ? const <String>{}
              : <String>{
                  'task_${index.toString().padLeft(3, '0')}',
                },
        );
      });
      final plan = TaskPlanRecord(
        id: 'plan-100',
        promptId: 'prompt-v1',
        promptVersionId: 'version-v1',
        projectId: project.id,
        revision: 1,
        previousPlanId: null,
        title: 'One hundred bounded tasks',
        rationale: 'Exercise the documented maximum.',
        depth: PlanningDepth.exhaustive,
        maxLeafTasks: 100,
        tasks: tasks,
        model: model,
        contentHash: Sha256.text('plan-100'),
        createdAt: DateTime.utc(2026, 7, 16),
        updatedAt: DateTime.utc(2026, 7, 16),
      );
      expect(plan.validate(), isEmpty);

      final cyclic = plan.copyWith(
        tasks: <PlanTaskRecord>[
          _task('a', dependencies: const <String>{'b'}),
          _task('b', dependencies: const <String>{'a'}),
        ],
        maxLeafTasks: 2,
      );
      expect(
        cyclic.validate(),
        contains('The task plan contains a dependency cycle.'),
      );

      final missingParent = plan.copyWith(
        tasks: <PlanTaskRecord>[
          _task('child').copyWith(parentId: 'missing'),
        ],
        maxLeafTasks: 1,
      );
      expect(
        missingParent.validate(),
        contains('child references missing parent missing.'),
      );

      final parentCycle = plan.copyWith(
        tasks: <PlanTaskRecord>[
          _task('parent-a').copyWith(parentId: 'parent-b'),
          _task('parent-b').copyWith(parentId: 'parent-a'),
        ],
        maxLeafTasks: 2,
      );
      expect(
        parentCycle.validate(),
        contains('The task plan contains a parent hierarchy cycle.'),
      );
    });
  });

  group('v1.1 Project Manager profiles', () {
    late Directory temporary;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp(
        'kristin-project-manager-',
      );
    });

    tearDown(() async {
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });

    test('detects custom Analyze, Test, Build, and Run commands', () async {
      await File(
        '${temporary.path}${Platform.pathSeparator}kristin.project.json',
      ).writeAsString(
        jsonEncode(<String, dynamic>{
          'type': 'Fixture application',
          'analyze': <String, dynamic>{
            'executable': 'fixture-tool',
            'arguments': <String>['analyze'],
          },
          'test': <String, dynamic>{
            'executable': 'fixture-tool',
            'arguments': <String>['test'],
          },
          'build': <String, dynamic>{
            'executable': 'fixture-tool',
            'arguments': <String>['build'],
          },
          'run': <String, dynamic>{
            'executable': 'fixture-tool',
            'arguments': <String>['run'],
          },
        }),
      );
      final project = ProjectRecord(
        id: 'project-manager-fixture',
        name: 'Project Manager fixture',
        rootPath: temporary.path,
        createdAt: DateTime.utc(2026, 7, 20),
        updatedAt: DateTime.utc(2026, 7, 20),
      );
      final service = ProjectDiagnosticsService(
        redactor: SecretRedactor(),
      );

      final report = await service.inspect(project, modelReady: true);

      expect(report.projectType, 'Fixture application');
      expect(report.analyzeCommand, 'fixture-tool analyze');
      expect(report.testCommand, 'fixture-tool test');
      expect(report.buildCommand, 'fixture-tool build');
      expect(report.runCommand, 'fixture-tool run');
    });
  });
}

ModelGenerationDelegate _fixtureGenerator(ModelIdentity model) {
  return (request) async {
    final now = DateTime.now().toUtc();
    final isPlan = request.systemPrompt.contains('task-planning model');
    final payload = isPlan
        ? <String, dynamic>{
            'title': 'Calculator delivery plan',
            'rationale': 'Separate the evidence baseline from implementation.',
            'tasks': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'task_001',
                'phase': 'Foundation',
                'parentId': null,
                'title': 'Gather calculator framework information',
                'objective':
                    'Identify suitable development tools and libraries.',
                'instructions':
                    'Search online documentation for suitable calculator frameworks and libraries.',
                'dependencies': <String>[],
                'acceptanceCriteria': <String>[
                  'Suitable local development tools and libraries are identified.',
                ],
                'verificationSteps': <String>[
                  'List the project root and inspect the selected source files.',
                ],
                'expectedArtifacts': <String>['Evidence baseline'],
                'allowedTools': <String>['list_directory', 'read_file'],
                'complexity': 2,
                'effortPoints': 2,
                'uncertainty': 'low',
                'risk': 'low',
                'estimateConfidence': 0.9,
                'expectedModelTurns': 2,
                'expectedToolCalls': 3,
                'maxAttempts': 2,
                'enabled': true,
                'manual': false,
              },
              <String, dynamic>{
                'id': 'task_002',
                'phase': 'Implementation',
                'parentId': 'task_001',
                'title': 'Implement calculator',
                'objective': 'Create and verify the calculator experience.',
                'instructions':
                    'Implement the calculator and run objective checks.',
                'dependencies': <String>['task_001'],
                'acceptanceCriteria': <String>[
                  'The calculator returns correct results for supported operations.',
                ],
                'verificationSteps': <String>[
                  'Run the detected analyzer and tests.',
                ],
                'expectedArtifacts': <String>['Calculator source and tests'],
                'allowedTools': <String>[
                  'read_file',
                  'write_file',
                  'verify_project',
                  'not_a_real_tool',
                ],
                'complexity': 6,
                'effortPoints': 8,
                'uncertainty': 'medium',
                'risk': 'medium',
                'estimateConfidence': 0.75,
                'expectedModelTurns': 6,
                'expectedToolCalls': 12,
                'maxAttempts': 2,
                'enabled': true,
                'manual': false,
              },
              <String, dynamic>{
                'id': 'task_004',
                'phase': 'Design',
                'parentId': 'task_001',
                'title': 'Create interface design in Figma',
                'objective': 'Produce a responsive calculator design in Figma.',
                'instructions':
                    'Use Figma to create wireframes, interaction states, and a responsive visual prototype.',
                'dependencies': <String>['task_001'],
                'acceptanceCriteria': <String>[
                  'A Figma design file is delivered.',
                ],
                'verificationSteps': <String>[
                  'Open the Figma design and inspect every state.',
                ],
                'expectedArtifacts': <String>['Figma design link'],
                'allowedTools': <String>['read_file'],
                'complexity': 4,
                'effortPoints': 5,
                'uncertainty': 'medium',
                'risk': 'medium',
                'estimateConfidence': 0.7,
                'expectedModelTurns': 3,
                'expectedToolCalls': 6,
                'maxAttempts': 2,
                'enabled': true,
                'manual': false,
              },
              <String, dynamic>{
                'id': 'task_005',
                'phase': 'Testing',
                'parentId': 'task_001',
                'title': 'Conduct User Testing for Calculator Interface',
                'objective':
                    'Recruit users and collect feedback about calculator usability.',
                'instructions':
                    'Recruit participants with different experience levels, observe their interactions, and collect feedback in a real-world scenario.',
                'dependencies': <String>['task_002', 'task_004'],
                'acceptanceCriteria': <String>[
                  'Users successfully complete the calculator tasks.',
                ],
                'verificationSteps': <String>[
                  'Collect feedback from recruited users.',
                ],
                'expectedArtifacts': <String>['User feedback report'],
                'allowedTools': <String>['read_file'],
                'complexity': 3,
                'effortPoints': 3,
                'uncertainty': 'medium',
                'risk': 'low',
                'estimateConfidence': 0.7,
                'expectedModelTurns': 3,
                'expectedToolCalls': 4,
                'maxAttempts': 1,
                'enabled': true,
                'manual': true,
              },
              <String, dynamic>{
                'id': 'task_003',
                'phase': 'Deployment',
                'parentId': 'task_001',
                'title': 'Deploy calculator to production environment',
                'objective': 'Publish a live-accessible calculator web app.',
                'instructions':
                    'Deploy the calculator to a cloud platform and provide a public URL.',
                'dependencies': <String>['task_002'],
                'acceptanceCriteria': <String>[
                  'The calculator is available through a public URL.',
                ],
                'verificationSteps': <String>[
                  'Open the public URL and verify the application.',
                ],
                'expectedArtifacts': <String>['Live calculator URL'],
                'allowedTools': <String>['read_file'],
                'complexity': 5,
                'effortPoints': 5,
                'uncertainty': 'medium',
                'risk': 'medium',
                'estimateConfidence': 0.7,
                'expectedModelTurns': 3,
                'expectedToolCalls': 6,
                'maxAttempts': 2,
                'enabled': true,
                'manual': false,
              },
              <String, dynamic>{
                'id': 'task_006',
                'phase': 'Setup',
                'parentId': 'task_001',
                'title': 'Set Up Development Environment',
                'objective': 'Install Node.js, npm, and Git for the project.',
                'instructions':
                    'Install Node.js, npm, and Git, then create a new project directory next to the selected workspace.',
                'dependencies': <String>['task_001'],
                'acceptanceCriteria': <String>[
                  'The external development environment is installed.',
                ],
                'verificationSteps': <String>[
                  'Run system installers and inspect the sibling directory.',
                ],
                'expectedArtifacts': <String>['New sibling project directory'],
                'allowedTools': <String>[
                  'run_command',
                  'write_file',
                  'mcp_call'
                ],
                'complexity': 4,
                'effortPoints': 5,
                'uncertainty': 'medium',
                'risk': 'high',
                'estimateConfidence': 0.6,
                'expectedModelTurns': 4,
                'expectedToolCalls': 8,
                'maxAttempts': 1,
                'enabled': true,
                'manual': false,
              },
              <String, dynamic>{
                'id': 'task_007',
                'phase': 'Backend',
                'parentId': 'task_001',
                'title': 'Develop Backend Calculation Logic',
                'objective':
                    'Create an Express REST API for calculator operations.',
                'instructions':
                    'Install Express and implement REST endpoints for arithmetic operations and calculation history.',
                'dependencies': <String>['task_006'],
                'acceptanceCriteria': <String>[
                  'The Express API responds to calculator requests.',
                ],
                'verificationSteps': <String>[
                  'Start the server and call every REST endpoint.',
                ],
                'expectedArtifacts': <String>['Express backend'],
                'allowedTools': <String>[
                  'run_command',
                  'start_process',
                  'write_file',
                  'mcp_call',
                ],
                'complexity': 6,
                'effortPoints': 8,
                'uncertainty': 'medium',
                'risk': 'medium',
                'estimateConfidence': 0.7,
                'expectedModelTurns': 6,
                'expectedToolCalls': 12,
                'maxAttempts': 1,
                'enabled': true,
                'manual': false,
              },
              <String, dynamic>{
                'id': 'task_008',
                'phase': 'Testing',
                'parentId': 'task_001',
                'title': 'Conduct Comprehensive Testing of Calculator',
                'objective':
                    'Test that the UI and backend references in the generated plan behave consistently.',
                'instructions':
                    'Verify responsive UI behavior, arithmetic tests, and any remaining backend references without implementing a new server.',
                'dependencies': <String>['task_002', 'task_007'],
                'acceptanceCriteria': <String>[
                  'The calculator checks pass or exact failures are recorded.',
                ],
                'verificationSteps': <String>[
                  'Run the detected project analyzer and tests.',
                ],
                'expectedArtifacts': <String>['Test results'],
                'allowedTools': <String>['run_command', 'verify_project'],
                'complexity': 3,
                'effortPoints': 3,
                'uncertainty': 'low',
                'risk': 'low',
                'estimateConfidence': 0.8,
                'expectedModelTurns': 2,
                'expectedToolCalls': 4,
                'maxAttempts': 2,
                'enabled': true,
                'manual': false,
              },
            ],
          }
        : <String, dynamic>{
            'title': 'Modern calculator',
            'purpose': 'Build and verify an accessible calculator application.',
            'systemPrompt':
                'Act as a careful calculator product engineer. Produce maintainable code and objective evidence.',
            'userPrompt':
                'Build a calculator with standard arithmetic and scientific functions for {{platform}}.',
            'variables': <String>['platform'],
            'assumptions': <String>[
              'The active project is the target workspace.'
            ],
            'clarifyingQuestions': <String>[
              'Which deployment platform is required?'
            ],
            'acceptanceCriteria': <String>[
              'The calculator returns correct results for supported operations.',
              'Automated tests pass without errors.',
            ],
            'outputExpectations': <String>[
              'Application source',
              'Automated tests'
            ],
            'guardrails': <String>[
              'Do not modify files outside the active project.'
            ],
            'stopConditions': <String>[
              'Stop when a required platform decision is unresolved.'
            ],
            'evaluationCases': <String>['2 + 2 returns 4.'],
            'mode': 'build',
          };
    return ModelGenerationResult(
      text: jsonEncode(payload),
      identity: model,
      startedAt: now,
      firstTokenAt: now,
      completedAt: now,
      inputTokens: 20,
      outputTokens: 40,
    );
  };
}

PlanTaskRecord _task(
  String id, {
  Set<String> dependencies = const <String>{},
}) {
  return PlanTaskRecord(
    id: id,
    phase: 'Implementation',
    parentId: null,
    title: 'Task $id',
    objective: 'Complete $id.',
    instructions: 'Implement and verify $id.',
    dependencies: dependencies,
    acceptanceCriteria: <String>['Task $id produces its expected result.'],
    verificationSteps: <String>['Verify the result for $id.'],
    expectedArtifacts: <String>['Artifact $id'],
    allowedTools: const <String>{'read_file'},
    complexity: 1,
    effortPoints: 1,
    uncertainty: PlanUncertainty.low,
    risk: PlanRisk.low,
    estimateConfidence: 0.9,
    expectedModelTurns: 1,
    expectedToolCalls: 1,
    maxAttempts: 1,
    enabled: true,
    manual: false,
  );
}
