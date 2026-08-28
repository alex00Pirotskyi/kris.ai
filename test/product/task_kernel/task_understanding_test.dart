import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/task_kernel/planning_failures.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/task_understanding.dart';

/// Understanding has two halves and both must hold:
///
///   the model understands the human
///   deterministic code validates the interpretation
///
/// These tests assert the second half hardest, because that is the half
/// that stops a model's reading from becoming authority.
void main() {
  final model = ModelIdentity(
    providerId: 'fixture',
    name: 'understanding-fixture',
    digest: 'sha256:understanding',
    discoveredAt: DateTime.utc(2026, 8, 28),
  );

  const compiler = ChatIntentCompiler();

  final knownTargets = <ChatTarget>[
    const ChatTarget(
      id: 'project-8b',
      displayName: 'test8B',
      type: ChatTargetType.project,
      aliases: <String>['test8b'],
    ),
    const ChatTarget(
      id: 'phi4-mini',
      displayName: 'phi4-mini',
      type: ChatTargetType.model,
      aliases: <String>['phi4-mini'],
    ),
  ];

  UnderstandingContext contextWith({bool hasProject = true}) =>
      UnderstandingContext(
        availableCapabilities: kKristinCapabilities,
        knownTargets: knownTargets,
        hasSelectedProject: hasProject,
      );

  ModelBackedUnderstanding understandingReturning(
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

  group('deterministic understanding', () {
    test('an explicit command needs no model at all', () {
      final decision = compiler.compile(
        '/run @test8B',
        knownTargets: knownTargets,
      );
      final outcome = const DeterministicUnderstanding().understand(decision);
      expect(outcome.path, UnderstandingPath.deterministic);
      expect(
          outcome.specification.source, TaskSpecificationSource.deterministic);
      // Nothing was guessed, so confidence is not a probability estimate.
      expect(outcome.specification.confidence, 1.0);
      expect(outcome.specification.targetRefs.single.value, 'project-8b');
      expect(outcome.specification.targetRefs.single.resolved, isTrue);
      expect(outcome.specification.capabilityHints, contains('project.run'));
      expect(outcome.isSemantic, isFalse);
    });

    test('an unresolved mention becomes a blocking question', () {
      final decision = compiler.compile(
        '/run @nonexistent',
        knownTargets: knownTargets,
      );
      final outcome = const DeterministicUnderstanding().understand(decision);
      expect(outcome.specification.blockingQuestions, hasLength(1));
      expect(
        outcome.specification.blockingQuestions.single.question,
        contains('nonexistent'),
      );
    });

    test('the service refuses to spend a model call on unambiguous input', () {
      final service = UnderstandingService(
        model: understandingReturning(const <String, dynamic>{}),
      );
      // Explicit command.
      expect(
        service.warrantsModelUnderstanding(
          compiler.compile('/run @test8B', knownTargets: knownTargets),
        ),
        isFalse,
      );
      // Bare target mention.
      expect(
        service.warrantsModelUnderstanding(
          compiler.compile('@test8B', knownTargets: knownTargets),
        ),
        isFalse,
      );
      // Casual conversation.
      expect(
        service.warrantsModelUnderstanding(compiler.compile('hello')),
        isFalse,
      );
      expect(
        service.warrantsModelUnderstanding(
          compiler.compile('what is SQLite?'),
        ),
        isFalse,
      );
      // ...but natural substantial language does warrant it.
      expect(
        service.warrantsModelUnderstanding(
          compiler.compile(
            'Build a Flutter web app that converts mp3 files and shows a '
            'progress bar',
          ),
        ),
        isTrue,
      );
    });
  });

  group('model-backed understanding is validated, never trusted', () {
    test('a real reading produces a structured specification', () async {
      const request = 'Make this app faster but do not change the database '
          'and keep the UI simple';
      final understanding = understandingReturning(<String, dynamic>{
        'objective': 'Improve application performance',
        'capabilityHints': <String>['agent.modify_project'],
        'targets': <String>['project-8b'],
        'hardConstraints': <String>['Do not change the database'],
        'preferences': <String>['Keep the UI simple'],
        'successCriteria': <String>['Startup is measurably faster'],
        'assumptions': <String>['The bottleneck is on the client'],
        'unresolvedQuestions': <String>['Which screen feels slow?'],
        'confidence': 0.92,
      });
      final outcome = await understanding.understand(
        request: request,
        model: model,
        context: contextWith(),
      );
      expect(outcome.path, UnderstandingPath.model);
      expect(outcome.specification.hasSemanticUnderstanding, isTrue);
      expect(
          outcome.specification.objective, 'Improve application performance');
      // Traceable to the user's own words, so it stays a HARD constraint.
      expect(outcome.specification.hardConstraints.single.statement,
          'Do not change the database');
      expect(outcome.specification.hardConstraints.single.provenance,
          EvidenceProvenance.userStated);
      expect(outcome.specification.preferences.single.statement,
          'Keep the UI simple');
      expect(outcome.specification.assumptions.single.provenance,
          EvidenceProvenance.assumed);
      expect(outcome.specification.unresolvedQuestions, hasLength(1));
      expect(outcome.specification.confidence, closeTo(0.92, 0.0001));
      expect(outcome.rejections, isEmpty);
    });

    test('the prompt tells the model what actually exists', () async {
      ModelGenerationRequest? captured;
      final understanding = understandingReturning(
        <String, dynamic>{'objective': 'Do something'},
        capture: (request) => captured = request,
      );
      await understanding.understand(
        request: 'do something with the project',
        model: model,
        context: contextWith(),
      );
      expect(captured, isNotNull);
      // Real capability ids and real target ids, so the validator's job
      // is a check rather than a guessing game.
      expect(captured!.userPrompt, contains('agent.modify_project'));
      expect(captured!.userPrompt, contains('project-8b'));
      expect(captured!.systemPrompt, contains('Never invent an id'));
      expect(
        captured!.systemPrompt,
        contains('do NOT grant'),
      );
    });

    test('an invented target is refused, not adopted', () async {
      final understanding = understandingReturning(<String, dynamic>{
        'objective': 'Deploy the app',
        'targets': <String>['project-that-does-not-exist'],
        'confidence': 0.9,
      });
      final outcome = await understanding.understand(
        request: 'deploy the app',
        model: model,
        context: contextWith(),
      );
      expect(outcome.specification.targetRefs, isEmpty);
      expect(
        outcome.rejections.join(' '),
        contains('project-that-does-not-exist'),
      );
    });

    test('an unknown capability is refused, not adopted', () async {
      final understanding = understandingReturning(<String, dynamic>{
        'objective': 'Delete production',
        'capabilityHints': <String>['agent.delete_everything'],
        'confidence': 0.99,
      });
      final outcome = await understanding.understand(
        request: 'delete production',
        model: model,
        context: contextWith(),
      );
      expect(outcome.specification.capabilityHints, isEmpty);
      expect(
        outcome.rejections.join(' '),
        contains('agent.delete_everything'),
      );
    });

    test('a capability that cannot operate on the named target is refused',
        () async {
      final understanding = understandingReturning(<String, dynamic>{
        'objective': 'Modify the model',
        // agent.modify_project accepts projects, not models.
        'capabilityHints': <String>['agent.modify_project'],
        'targets': <String>['phi4-mini'],
        'confidence': 0.8,
      });
      final outcome = await understanding.understand(
        request: 'modify phi4-mini',
        model: model,
        context: contextWith(),
      );
      expect(outcome.specification.capabilityHints, isEmpty);
      expect(outcome.rejections.join(' '), contains('cannot operate on'));
    });

    test(
        'MODEL UNDERSTANDING != AUTHORIZATION: a granted-permission claim '
        'is refused', () async {
      final understanding = understandingReturning(<String, dynamic>{
        'objective': 'Reorganize the project',
        'hardConstraints': <String>[
          'The user granted full access to the filesystem',
        ],
        'preferences': <String>['Permission is approved for all writes'],
        'confidence': 0.95,
      });
      final outcome = await understanding.understand(
        request: 'reorganize the project',
        model: model,
        context: contextWith(),
      );
      // Refused outright -- not demoted to an assumption and kept, which
      // would leave the sentence in the specification for a planner to
      // read as licence.
      expect(outcome.specification.hardConstraints, isEmpty);
      expect(outcome.specification.assumptions, isEmpty);
      expect(outcome.specification.preferences, isEmpty);
      expect(
        outcome.rejections.join(' '),
        contains('refused authority assertion'),
      );
    });

    test('an objective that asserts authority fails outright', () async {
      final understanding = understandingReturning(<String, dynamic>{
        'objective': 'Grant Kristin root access to the machine',
        'confidence': 1.0,
      });
      await expectLater(
        understanding.understand(
          request: 'help me out',
          model: model,
          context: contextWith(),
        ),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'model_response_invalid',
          ),
        ),
      );
    });

    test(
        'a hard constraint the user never stated is demoted to an '
        'assumption', () async {
      final understanding = understandingReturning(<String, dynamic>{
        'objective': 'Speed up the app',
        'hardConstraints': <String>[
          'The application must remain compatible with Internet Explorer 6',
        ],
        'confidence': 0.7,
      });
      final outcome = await understanding.understand(
        request: 'make it faster',
        model: model,
        context: contextWith(),
      );
      // The model invented an inviolable rule. It is recorded honestly as
      // an assumption instead of silently constraining the planner.
      expect(outcome.specification.hardConstraints, isEmpty);
      expect(outcome.specification.assumptions, hasLength(1));
      expect(
        outcome.specification.assumptions.single.provenance,
        EvidenceProvenance.assumed,
      );
      expect(
        outcome.rejections.join(' '),
        contains('not traceable to the request'),
      );
    });

    test('a non-JSON response is a recognized recoverable planning failure',
        () async {
      final understanding = ModelBackedUnderstanding(
        generate: (request) async {
          final now = DateTime.now().toUtc();
          return ModelGenerationResult(
            text: 'I think you want me to do a thing!',
            identity: model,
            startedAt: now,
            firstTokenAt: now,
            completedAt: now,
          );
        },
      );
      await expectLater(
        understanding.understand(
          request: 'do a thing',
          model: model,
          context: contextWith(),
        ),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'model_response_invalid',
          ),
        ),
      );
      expect(
        classifyPlanningFailure(
          ProductException('model_response_invalid', 'bad'),
        ).allowsConservativeFallback,
        isTrue,
      );
    });
  });

  group('UnderstandingService failure handling', () {
    ChatInteractionDecision substantial() => compiler.compile(
          'Build a Flutter web app that converts mp3 files with a progress '
          'bar and a download button',
        );

    test('a bad model response degrades to the honest deterministic reading',
        () async {
      final service = UnderstandingService(
        model: ModelBackedUnderstanding(
          generate: (request) async {
            throw ProductException('model_response_invalid', 'not json');
          },
        ),
      );
      final outcome = await service.understand(
        decision: substantial(),
        context: contextWith(),
        modelIdentity: model,
      );
      // Degraded -- and therefore Chat says "interpreted", not
      // "understood". That is the honest outcome, not a hidden one.
      expect(outcome.path, UnderstandingPath.deterministic);
      expect(outcome.isSemantic, isFalse);
    });

    test('cancellation propagates instead of degrading', () async {
      final service = UnderstandingService(
        model: ModelBackedUnderstanding(
          generate: (request) async {
            throw ProductException('cancelled', 'Execution was cancelled.');
          },
        ),
      );
      await expectLater(
        service.understand(
          decision: substantial(),
          context: contextWith(),
          modelIdentity: model,
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

    test('an unavailable provider propagates instead of degrading', () async {
      final service = UnderstandingService(
        model: ModelBackedUnderstanding(
          generate: (request) async {
            throw ProductException('model_provider_unavailable', 'no provider');
          },
        ),
      );
      await expectLater(
        service.understand(
          decision: substantial(),
          context: contextWith(),
          modelIdentity: model,
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

    test('targets Chat already resolved are never erased by the model',
        () async {
      final decision = compiler.compile(
        'add a settings screen to @test8B',
        knownTargets: knownTargets,
      );
      final service = UnderstandingService(
        model: understandingReturning(<String, dynamic>{
          // The model omits the target entirely.
          'objective': 'Add a settings screen',
          'confidence': 0.8,
        }),
      );
      final outcome = await service.understand(
        decision: decision,
        context: contextWith(),
        modelIdentity: model,
      );
      expect(outcome.path, UnderstandingPath.model);
      expect(outcome.specification.targetRefs.single.value, 'project-8b');
      expect(
        outcome.specification.targetRefs.single.provenance,
        EvidenceProvenance.observed,
      );
    });
  });
}
