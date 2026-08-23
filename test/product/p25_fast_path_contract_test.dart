import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/execution_intelligence.dart';
import 'package:kristin_local_agent/product/prompt_planning.dart';

void main() {
  group('P25 focused fast path', () {
    test('local execution uses a bounded model budget', () {
      final budget = PhaseBudget.localExecution();
      expect(budget.phase, 'execution');
      expect(budget.maxModelRequests, 4);
      expect(budget.maxToolCalls, 12);
      expect(budget.maxRepairs, 2);
      expect(budget.maxOutputTokens, 1280);
      expect(budget.maxContextCharacters, 16000);
      expect(budget.deadlineSeconds, 600);
    });

    test(
      'provider lifetime, discovery cache, warm reuse, and deltas are wired',
      () {
        final source = File(
          'lib/product/models_research.dart',
        ).readAsStringSync();
        expect(
          source,
          contains('List<LanguageModelProvider>? _providerCache;'),
        );
        expect(
          source,
          contains('Future<List<ModelIdentity>>? _discoveryInFlight;'),
        );
        expect(source, contains("stage: 'load_reused'"));
        expect(
          source,
          contains("'warmupSkippedForActiveKeepAlive': warmup.attempts == 0"),
        );
        expect(source, contains('void Function(String delta)? onTextDelta;'));
        expect(source, contains('request.reportTextDelta(fragment);'));
      },
    );

    test('clarification contract enforces question and option bounds', () {
      final session = PromptClarificationSession.fromModelJson(
        <String, dynamic>{
          'brief': 'A local desktop utility is already clear.',
          'questions': <Map<String, dynamic>>[
            <String, dynamic>{
              'question': 'Which release target should lead?',
              'whyItMatters': 'It changes scope and verification.',
              'options': <Map<String, dynamic>>[
                <String, dynamic>{
                  'label': 'Working first version',
                  'description': 'Prioritize usable behavior.',
                  'recommended': true,
                },
                <String, dynamic>{
                  'label': 'Production-ready',
                  'description': 'Prioritize robustness.',
                  'recommended': false,
                },
              ],
            },
            <String, dynamic>{
              'question': 'Which tradeoff should lead?',
              'whyItMatters': 'It gives the prompt a tie-breaker.',
              'options': <Map<String, dynamic>>[
                <String, dynamic>{
                  'label': 'Reliability',
                  'description': 'Prefer stronger checks.',
                  'recommended': true,
                },
                <String, dynamic>{
                  'label': 'Speed',
                  'description': 'Prefer the smallest solution.',
                  'recommended': false,
                },
              ],
            },
          ],
        },
        goal: 'Build a local calculator',
        model: ModelIdentity(
          providerId: 'ollama',
          name: 'phi5-mini',
          digest: 'digest',
          discoveredAt: DateTime.utc(2026, 8, 19),
        ),
      );
      expect(session.questions, hasLength(2));
      expect(session.questions.first.options, hasLength(2));
      expect(
        session.questions.first.recommendedOption.label,
        'Working first version',
      );
      expect(
        session.missingAnswerIds(<String, String>{
          'question_1': 'Working first version',
        }),
        <String>['question_2'],
      );
    });

    test('prompt and plan generation permit only one bounded repair', () {
      final source = File(
        'lib/product/prompt_planning.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'const maxAttempts = 2;').allMatches(source).length,
        greaterThanOrEqualTo(2),
      );
      expect(source, isNot(contains('maxOutputTokens: 6144')));
      expect(source, isNot(contains('min(32000')));
      expect(source, contains('maxOutputTokens: 1024'));
      expect(source, contains('STRUCTURED INTAKE'));
      expect(source, contains('clarifyingQuestions: const <String>[]'));
      expect(source, contains("stage: 'plan_validation_started'"));
    });

    test('Prompt Studio is question-first and shows every AI operation', () {
      final source = File('lib/product/chat_studio.dart').readAsStringSync();
      expect(source, contains('int generatedMaxTasks = 7;'));
      expect(source, contains('Future<void> _startPromptStudioFlow()'));
      expect(source, contains('class _PromptClarificationDialog'));
      expect(source, contains("'Other — write my own answer'"));
      expect(source, contains("'Generate final prompt'"));
      expect(source, contains('Widget _promptGenerationStatusCard()'));
      expect(source, contains('_PromptStudioOperationKind.taskPlan'));
      expect(source, contains("label: const Text('Stop')"));
      expect(source, contains("label: const Text('Improve with AI')"));
      expect(source, contains("label: const Text('Simplify')"));
      expect(source, contains("label: const Text('Add useful detail')"));
      expect(source, contains('onTextDelta: (delta)'));
    });

    test('Ollama runs select the local execution fast path', () {
      final source = File(
        'lib/product/planning_runtime.dart',
      ).readAsStringSync();
      expect(source, contains("run.command.model.providerId == 'ollama'"));
      expect(source, contains('PhaseBudget.localExecution()'));
      expect(source, contains('executionPhaseBudget.maxContextCharacters'));
    });
  });
}
