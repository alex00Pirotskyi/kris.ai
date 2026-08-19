import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/execution_intelligence.dart';

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
      expect(source, contains('final outputTokenBudget = switch (action)'));
      expect(source, contains('limit <= 7'));
      expect(source, contains('USER FEEDBACK OR ANSWERS'));
    });

    test(
      'Prompt Studio exposes live progress, stop, and feedback controls',
      () {
        final source = File('lib/product/chat_studio.dart').readAsStringSync();
        expect(source, contains('int generatedMaxTasks = 7;'));
        expect(source, contains('Widget _promptGenerationStatusCard()'));
        expect(source, contains("label: const Text('Stop')"));
        expect(source, contains("label: const Text('Apply my feedback')"));
        expect(source, contains('items: const <int>[1, 3, 5, 7, 10, 15, 25]'));
        expect(source, contains('onTextDelta: (delta)'));
      },
    );

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
