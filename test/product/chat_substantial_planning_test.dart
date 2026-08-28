import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/prompt_planning.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

/// Proves Chat's substantial-request planning path (Improvement: "restore
/// real multi-task planning") actually calls through to
/// PromptPlanningService and gets a request-specific multi-task graph --
/// not the generic ContractPlanner inspect/implement/verify template --
/// and that when the model-generated plan cannot be validated even after
/// its own one-shot bounded repair, it fails with exactly the error code
/// _planSubstantialTask (chat_control_plane_studio_actions.dart) catches
/// to fall back to ContractPlanner.
///
/// This exercises PromptPlanningService directly (the same convention as
/// v1_product_preview_test.dart) rather than the full ProductRuntime,
/// since ProductRuntime.generatePromptDraft/saveGeneratedPrompt/
/// generateTaskPlan/prepareTaskPlan are pure one-line delegations to it.
void main() {
  group('Chat substantial planning uses PromptPlanningService', () {
    late Directory temporary;
    late ProductRepositories repositories;
    late EventJournal events;
    late AuditChain audit;
    late ModelIdentity model;
    late ProjectRecord project;

    setUp(() async {
      temporary =
          await Directory.systemTemp.createTemp('kristin-chat-planning-');
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
        name: 'deterministic-chat-planning',
        digest: 'sha256:chat-planning-fixture',
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
        await temporary.delete(recursive: true);
      }
    });

    PromptPlanningService serviceWith(ModelGenerationDelegate generator) {
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

    test(
      'a substantial request compiles into a real per-request multi-task '
      'plan, not the generic inspect/implement/verify template',
      () async {
        final service = serviceWith(_validMp3PlanGenerator(model));

        final draft = await service.generatePrompt(
          goal: 'Flutter web app to convert mp3 file to urls, no account or '
              'security logic needed, progress bar and upload/download '
              'buttons, simple good UX/UI',
          model: model,
        );
        final version = await service.savePromptVersion(
          promptId: 'prompt-mp3',
          sourceGoal: 'Convert mp3 to a shareable url',
          action: PromptGenerationAction.generate,
          draft: draft,
          model: model,
        );
        final plan = await service.generateTaskPlan(
          promptVersion: version,
          projectId: project.id,
          model: model,
        );
        expect(plan.validate(), isEmpty);
        // ContractPlanner's fixed template is 3 items for a plain build
        // request (inspect / implement / verify) -- a genuine per-request
        // decomposition must exceed that, with titles that are actually
        // about this feature rather than the generic phase names.
        expect(plan.tasks.length, greaterThan(3));
        final titles = plan.tasks.map((task) => task.title).toList();
        expect(titles,
            isNot(contains('Inspect project and establish evidence baseline')));
        expect(titles, isNot(contains('Implement requested product behavior')));
        expect(
          titles.any((title) =>
              title.toLowerCase().contains('upload') ||
              title.toLowerCase().contains('progress') ||
              title.toLowerCase().contains('download')),
          isTrue,
          reason: 'plan should decompose the actual requested feature, '
              'not a generic phase list: $titles',
        );

        final prepared = await service.compilePlan(
          plan: plan,
          promptVersion: version,
          project: project,
          model: model,
        );
        expect(prepared.plan.items.length, plan.tasks.length);
        expect(prepared.plan.validate(), isEmpty);
      },
    );

    test(
      'a plan that still fails validation after the built-in repair '
      'throws task_plan_invalid -- the exact code the Chat fallback catches',
      () async {
        final service = serviceWith(_alwaysInvalidPlanGenerator(model));
        final draft = await service.generatePrompt(
          goal: 'Convert mp3 to a shareable url',
          model: model,
        );
        final version = await service.savePromptVersion(
          promptId: 'prompt-broken',
          sourceGoal: 'Convert mp3 to a shareable url',
          action: PromptGenerationAction.generate,
          draft: draft,
          model: model,
        );

        await expectLater(
          service.generateTaskPlan(
            promptVersion: version,
            projectId: project.id,
            model: model,
          ),
          throwsA(
            isA<ProductException>().having(
              (error) => error.code,
              'code',
              'task_plan_invalid',
            ),
          ),
        );
      },
    );
  });
}

Map<String, dynamic> _draftJson() => <String, dynamic>{
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
      'guardrails': <String>['Do not add account or security logic.'],
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
    ModelIdentity model, Map<String, dynamic> payload) {
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

ModelGenerationDelegate _validMp3PlanGenerator(ModelIdentity model) {
  return (request) async {
    final isPlan = request.systemPrompt.contains('task-planning model');
    if (!isPlan) return _resultFor(model, _draftJson());
    return _resultFor(model, <String, dynamic>{
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
          parentId: 'task_001',
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
    });
  };
}

ModelGenerationDelegate _alwaysInvalidPlanGenerator(ModelIdentity model) {
  return (request) async {
    final isPlan = request.systemPrompt.contains('task-planning model');
    if (!isPlan) return _resultFor(model, _draftJson());
    // A dependency on a task ID that is never defined fails
    // TaskPlanRecord.validate() on both the initial attempt and the
    // repair attempt, since this generator ignores the repair prompt.
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
}
