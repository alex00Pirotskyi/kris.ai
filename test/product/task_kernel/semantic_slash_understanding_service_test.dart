import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/task_kernel/semantic_slash_understanding.dart';
import 'package:kristin_local_agent/product/task_kernel/task_understanding.dart';

void main() {
  final model = ModelIdentity(
    providerId: 'fixture',
    name: 'semantic-slash',
    digest: 'sha256:semantic-slash',
    discoveredAt: DateTime.utc(2026, 8, 31),
  );
  const compiler = ChatIntentCompiler();
  const targets = <ChatTarget>[
    ChatTarget(
      id: 'project-a',
      displayName: 'project-a',
      type: ChatTargetType.project,
      aliases: <String>['project-a'],
    ),
  ];

  SemanticSlashUnderstandingService fixture(Map<String, dynamic> payload) =>
      SemanticSlashUnderstandingService(
        model: ModelBackedUnderstanding(
          generate: (request) async {
            final now = DateTime.now().toUtc();
            return ModelGenerationResult(
              text: jsonEncode(payload),
              identity: model,
              startedAt: now,
              firstTokenAt: now,
              completedAt: now,
            );
          },
        ),
      );

  test('/fix free text is semantic while /run target-only stays deterministic', () {
    final service = fixture(<String, dynamic>{});
    final fix = compiler.compile(
      '/fix @project-a login crashes when the access token expires',
      knownTargets: targets,
    );
    final run = compiler.compile('/run @project-a', knownTargets: targets);

    expect(fix.capability?.id, 'agent.fix_project');
    expect(service.warrantsModelUnderstanding(fix), isTrue);
    expect(service.warrantsModelUnderstanding(run), isFalse);
  });

  test('slash capability and deterministic target survive model interpretation', () async {
    final decision = compiler.compile(
      '/fix @project-a login crashes when the access token expires; do not change the database',
      knownTargets: targets,
    );
    final service = fixture(<String, dynamic>{
      'objective': 'Repair login after token expiry',
      'capabilityHints': <String>['research.search'],
      'targets': <String>[],
      'hardConstraints': <String>['do not change the database'],
      'successCriteria': <String>['Login recovers after token expiry'],
      'unresolvedQuestions': <String>[
        'Should an expired token sign out or refresh automatically?'
      ],
      'confidence': 0.86,
    });

    final outcome = await service.understand(
      decision: decision,
      context: const UnderstandingContext(
        availableCapabilities: kKristinCapabilities,
        knownTargets: targets,
        hasSelectedProject: true,
      ),
      modelIdentity: model,
    );

    expect(outcome.path, UnderstandingPath.model);
    expect(outcome.specification.originalRequest, decision.parsed.originalText);
    expect(outcome.specification.capabilityHints, <String>['agent.fix_project']);
    expect(
      outcome.specification.targetRefs.map((target) => target.value),
      contains('project-a'),
    );
    expect(outcome.specification.blockingQuestions, hasLength(1));
    expect(
      outcome.specification.hardConstraints.map((claim) => claim.statement),
      contains('do not change the database'),
    );
  });

  test('/create and /search with semantic payloads warrant model understanding', () {
    final service = fixture(<String, dynamic>{});
    expect(
      service.warrantsModelUnderstanding(
        compiler.compile('/create a small Flutter habit tracker with offline sync'),
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
