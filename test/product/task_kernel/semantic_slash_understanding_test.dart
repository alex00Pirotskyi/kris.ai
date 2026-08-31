import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/task_kernel/task_kernel.dart';
import 'package:kristin_local_agent/product/task_kernel/task_understanding.dart';

void main() {
  final model = ModelIdentity(
    providerId: 'fixture',
    name: 'semantic-slash',
    digest: 'sha256:semantic-slash',
    discoveredAt: DateTime.utc(2026, 8, 30),
  );
  const compiler = ChatIntentCompiler();
  final targets = <ChatTarget>[
    const ChatTarget(
      id: 'project-a',
      displayName: 'project-a',
      type: ChatTargetType.project,
      aliases: <String>['project-a'],
    ),
  ];

  ModelBackedUnderstanding fixture(
    Map<String, dynamic> payload, {
    void Function(ModelGenerationRequest request)? capture,
  }) =>
      ModelBackedUnderstanding(
        generate: (request) async {
          capture?.call(request);
          final now = DateTime.now().toUtc();
          return ModelGenerationResult(
            text: jsonEncode(payload),
            identity: model,
            startedAt: now,
            firstTokenAt: now,
            completedAt: now,
          );
        },
      );

  test(
      'free-text /fix payload gets semantic understanding while /run stays deterministic',
      () {
    final service = UnderstandingService(model: fixture(<String, dynamic>{}));
    final fix = compiler.compile(
      '/fix @project-a login crashes when the access token expires',
      knownTargets: targets,
    );
    final run = compiler.compile('/run @project-a', knownTargets: targets);

    expect(fix.capability?.id, 'agent.fix_project');
    expect(service.warrantsModelUnderstanding(fix), isTrue);
    expect(service.warrantsModelUnderstanding(run), isFalse);
  });

  test('explicit slash capability is locked against model replacement',
      () async {
    final decision = compiler.compile(
      '/fix @project-a login crashes when the access token expires',
      knownTargets: targets,
    );
    ModelGenerationRequest? captured;
    final service = UnderstandingService(
      model: fixture(
        <String, dynamic>{
          'objective': 'Repair login after token expiry',
          'capabilityHints': <String>['research.search'],
          'targets': <String>['project-a'],
          'successCriteria': <String>['Login recovers after token expiry'],
          'unresolvedQuestions': <String>[
            'Should an expired token sign out or refresh automatically?'
          ],
          'confidence': 0.86,
        },
        capture: (request) => captured = request,
      ),
    );
    final kernelContext = KernelRequestContext(
      decision: decision,
      project: ProjectRecord(
        id: 'project-a',
        name: 'project-a',
        rootPath: '/tmp/project-a',
        createdAt: DateTime.utc(2026, 8, 30),
        updatedAt: DateTime.utc(2026, 8, 30),
      ),
      model: model,
      knownTargets: targets,
    );

    final outcome = await service.understand(
      decision: decision,
      context: kernelContext.understandingContext,
      modelIdentity: model,
    );

    expect(outcome.path, UnderstandingPath.model);
    expect(outcome.specification.originalRequest, decision.parsed.originalText);
    expect(
        outcome.specification.capabilityHints, contains('agent.fix_project'));
    expect(outcome.specification.capabilityHints,
        isNot(contains('research.search')));
    expect(outcome.rejections.join(' '),
        contains('explicit command locks capability'));
    expect(outcome.specification.blockingQuestions, hasLength(1));
    expect(captured?.userPrompt, contains('LOCKED COMMAND CAPABILITY'));
    expect(captured?.userPrompt, contains('agent.fix_project'));
    expect(captured?.userPrompt,
        contains('login crashes when the access token expires'));
  });

  test('/create and /search with payloads warrant semantic understanding', () {
    final service = UnderstandingService(model: fixture(<String, dynamic>{}));
    expect(
      service.warrantsModelUnderstanding(
        compiler
            .compile('/create a small Flutter habit tracker with offline sync'),
      ),
      isTrue,
    );
    expect(
      service.warrantsModelUnderstanding(
        compiler.compile('/search current Flutter desktop packaging changes'),
      ),
      isTrue,
    );
  });
}
