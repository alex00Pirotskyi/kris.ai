import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';
import 'package:kristin_local_agent/product/domain.dart';

void main() {
  const compiler = ChatIntentCompiler();
  const registry = ChatCapabilityRegistry();
  const autocomplete = ChatAutocompleteEngine();

  const project = ChatTarget(
    id: 'rome-clock',
    type: ChatTargetType.project,
    displayName: 'Rome Clock',
    aliases: <String>['rome-clock'],
    description: 'Flutter project',
  );
  const model = ChatTarget(
    id: 'phi4-mini',
    type: ChatTargetType.model,
    displayName: 'Phi-4 Mini',
    aliases: <String>['phi4-mini', 'phi4'],
    status: 'Available',
  );
  const provider = ChatTarget(
    id: 'openai',
    type: ChatTargetType.provider,
    displayName: 'OpenAI',
    aliases: <String>['openai'],
    status: 'Not connected',
    available: false,
  );
  const targets = <ChatTarget>[project, model, provider];

  group('interaction policy', () {
    test('plain arithmetic question stays informational', () {
      final decision = compiler.compile('1 + 1?', inferredMode: CommandMode.build);
      expect(decision.kind, ChatInteractionKind.informational);
      expect(decision.mode, CommandMode.ask);
      expect(decision.needsUnderstanding, isFalse);
      expect(decision.needsPlan, isFalse);
    });

    test('action word inside a question does not trigger action', () {
      for (final request in <String>[
        'What does build mean in Flutter?',
        'Why did my test fail?',
        'What happens when I run flutter clean?',
        'Is Owner Mode dangerous?',
        'What is the difference between analyze and test?',
      ]) {
        final decision = compiler.compile(request, inferredMode: CommandMode.build);
        expect(
          decision.kind,
          ChatInteractionKind.informational,
          reason: request,
        );
        expect(decision.needsUnderstanding, isFalse, reason: request);
      }
    });

    test('polite natural action is still an action', () {
      final decision = compiler.compile(
        'Can you build me a clock app?',
        inferredMode: CommandMode.build,
      );
      expect(decision.kind, ChatInteractionKind.action);
      expect(decision.capability?.id, 'build');
      expect(decision.needsUnderstanding, isTrue);
      expect(decision.needsPlan, isTrue);
    });

    test('natural substantial action requires understanding and plan', () {
      final decision = compiler.compile(
        'Build me a small app showing the live time in Rome.',
        inferredMode: CommandMode.build,
      );
      expect(decision.kind, ChatInteractionKind.action);
      expect(decision.capability?.id, 'build');
      expect(decision.needsUnderstanding, isTrue);
      expect(decision.needsPlan, isTrue);
    });

    test('explicit search overrides informational fast path', () {
      final decision = compiler.compile(
        '/search 1 + 1 = ?',
        inferredMode: CommandMode.ask,
      );
      expect(decision.kind, ChatInteractionKind.action);
      expect(decision.capability?.id, 'search');
      expect(decision.explicitCommand, isTrue);
      expect(decision.needsUnderstanding, isTrue);
      expect(decision.needsPlan, isFalse);
      expect(
        decision.interpretedGoal,
        'Search current public sources for "1 + 1 = ?" and summarize what is found.',
      );
    });

    test('explicit project run resolves target and skips plan', () {
      final decision = compiler.compile(
        '/run @rome-clock',
        inferredMode: CommandMode.ask,
        knownTargets: targets,
      );
      expect(decision.kind, ChatInteractionKind.action);
      expect(decision.capability?.id, 'run');
      expect(decision.targets.single.id, 'rome-clock');
      expect(decision.interpretedGoal, 'Run Rome Clock.');
      expect(decision.needsUnderstanding, isTrue);
      expect(decision.needsPlan, isFalse);
      expect(decision.ambiguous, isFalse);
    });

    test('mention alone does not manufacture action intent', () {
      final decision = compiler.compile(
        'Is @rome-clock running?',
        inferredMode: CommandMode.run,
        knownTargets: targets,
      );
      expect(decision.kind, ChatInteractionKind.informational);
      expect(decision.targets.single.id, 'rome-clock');
      expect(decision.needsUnderstanding, isFalse);
    });

    test('model selection is action because execution configuration changes', () {
      final decision = compiler.compile(
        'Use @phi4-mini for this task.',
        inferredMode: CommandMode.ask,
        knownTargets: targets,
      );
      expect(decision.kind, ChatInteractionKind.action);
      expect(decision.capability?.id, 'use');
      expect(decision.targets.single.id, 'phi4-mini');
      expect(decision.needsUnderstanding, isTrue);
      expect(decision.needsPlan, isFalse);
    });

    test('destructive wording raises risk without granting authority', () {
      final decision = compiler.compile(
        'Delete the generated file.',
        inferredMode: CommandMode.build,
      );
      expect(decision.kind, ChatInteractionKind.action);
      expect(decision.riskClass, ChatRiskClass.destructive);
      expect(decision.needsUnderstanding, isTrue);
    });
  });

  group('capability registry', () {
    test('canonical ids and aliases are unambiguous', () {
      expect(registry.validate(), isEmpty);
      expect(registry.bySlash('/web_search')?.id, 'search');
      expect(registry.bySlash('/doctor')?.id, 'diagnose');
      expect(registry.byMention('@owner')?.id, 'owner');
    });

    test('slash autocomplete is deterministic and local', () {
      final suggestions = autocomplete.suggestions(
        text: '/ver',
        cursorOffset: 4,
        targets: targets,
      );
      expect(suggestions, isNotEmpty);
      expect(suggestions.first.kind, ChatAutocompleteKind.command);
      expect(suggestions.first.insertText, '/verify ');
    });

    test('mention autocomplete follows command target contract', () {
      final runSuggestions = autocomplete.suggestions(
        text: '/run @',
        cursorOffset: 6,
        targets: targets,
      );
      expect(runSuggestions.map((item) => item.target?.id), contains('rome-clock'));
      expect(runSuggestions.map((item) => item.target?.id), isNot(contains('phi4-mini')));
      expect(runSuggestions.map((item) => item.target?.id), isNot(contains('openai')));

      final useSuggestions = autocomplete.suggestions(
        text: '/use @',
        cursorOffset: 6,
        targets: targets,
      );
      expect(useSuggestions.map((item) => item.target?.id), contains('phi4-mini'));
      expect(useSuggestions.map((item) => item.target?.id), contains('openai'));
      expect(useSuggestions.map((item) => item.target?.id), isNot(contains('rome-clock')));
    });
  });

  group('understanding revisions', () {
    test('adjustment preserves original request and remains bounded', () {
      final decision = compiler.compile(
        'Build me a Rome clock.',
        inferredMode: CommandMode.build,
      );
      var history = UnderstandingHistory.initial(decision);
      for (var index = 0; index < 10; index += 1) {
        history = history.adjust('constraint $index');
      }
      expect(history.revisions.length, 6);
      expect(history.current.originalRequest, 'Build me a Rome clock.');
      expect(history.current.acceptedRequest, contains('constraint 9'));
    });

    test('another interpretation does not replace the agreed goal', () {
      final decision = compiler.compile(
        '/search best local database for Flutter desktop',
        inferredMode: CommandMode.ask,
      );
      final original = UnderstandingHistory.initial(decision);
      final alternate = original.alternate(decision);
      expect(alternate.current.summary, contains(decision.interpretedGoal));
      expect(alternate.current.originalRequest, original.current.originalRequest);
      expect(alternate.current.revision, 2);
    });
  });
}
