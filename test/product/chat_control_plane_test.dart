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
      final decision =
          compiler.compile('1 + 1?', inferredMode: CommandMode.build);
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
        final decision =
            compiler.compile(request, inferredMode: CommandMode.build);
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
      expect(decision.capability?.id, 'agent.create_project');
      expect(decision.needsUnderstanding, isTrue);
      expect(decision.needsPlan, isTrue);
    });

    test('natural substantial action requires understanding and plan', () {
      final decision = compiler.compile(
        'Build me a small app showing the live time in Rome.',
        inferredMode: CommandMode.build,
      );
      expect(decision.kind, ChatInteractionKind.action);
      expect(decision.capability?.id, 'agent.create_project');
      expect(decision.needsUnderstanding, isTrue);
      expect(decision.needsPlan, isTrue);
    });

    test('explicit search overrides informational fast path', () {
      final decision = compiler.compile(
        '/search 1 + 1 = ?',
        inferredMode: CommandMode.ask,
      );
      expect(decision.kind, ChatInteractionKind.action);
      expect(decision.capability?.id, 'research.search');
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
      expect(decision.capability?.id, 'project.run');
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

    test('model selection is action because execution configuration changes',
        () {
      final decision = compiler.compile(
        'Use @phi4-mini for this task.',
        inferredMode: CommandMode.ask,
        knownTargets: targets,
      );
      expect(decision.kind, ChatInteractionKind.action);
      expect(decision.capability?.id, 'model.select');
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
      expect(registry.bySlash('/web_search')?.id, 'research.search');
      expect(registry.bySlash('/doctor')?.id, 'system.diagnose');
      expect(registry.byMention('@owner')?.id, 'owner.mode');
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
      expect(runSuggestions.map((item) => item.target?.id),
          contains('rome-clock'));
      expect(runSuggestions.map((item) => item.target?.id),
          isNot(contains('phi4-mini')));
      expect(runSuggestions.map((item) => item.target?.id),
          isNot(contains('openai')));

      final useSuggestions = autocomplete.suggestions(
        text: '/use @',
        cursorOffset: 6,
        targets: targets,
      );
      expect(
          useSuggestions.map((item) => item.target?.id), contains('phi4-mini'));
      expect(useSuggestions.map((item) => item.target?.id), contains('openai'));
      expect(useSuggestions.map((item) => item.target?.id),
          isNot(contains('rome-clock')));
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
      expect(
          alternate.current.originalRequest, original.current.originalRequest);
      expect(alternate.current.revision, 2);
    });
  });

  group('capability semantics: create vs build vs modify (Improvement #8)', () {
    test('/build @project resolves to the small, direct project.build', () {
      final decision = compiler.compile(
        '/build @rome-clock',
        inferredMode: CommandMode.ask,
        knownTargets: targets,
      );
      expect(decision.capability?.id, 'project.build');
      expect(decision.needsPlan, isFalse);
    });

    test('/create always provisions a new project, never project.build', () {
      final decision = compiler.compile(
        '/create a Flutter clock app',
        inferredMode: CommandMode.ask,
      );
      expect(decision.capability?.id, 'agent.create_project');
    });

    test(
      'an unscoped "build me a clock app" is agent.create_project, not '
      'project.build',
      () {
        final decision = compiler.compile(
          'Build me a small app showing the live time in Rome.',
          inferredMode: CommandMode.build,
        );
        expect(decision.capability?.id, 'agent.create_project');
      },
    );

    test(
      '"build @project" (natural language, project mentioned) is '
      'project.build, not agent.create_project',
      () {
        final decision = compiler.compile(
          'build @rome-clock',
          inferredMode: CommandMode.build,
          knownTargets: targets,
        );
        expect(decision.capability?.id, 'project.build');
      },
    );

    test(
      'a modification verb with no explicit target is agent.modify_project, '
      'never a fresh project',
      () {
        final decision = compiler.compile(
          'Add a dark mode toggle to the settings screen.',
          inferredMode: CommandMode.build,
        );
        expect(decision.capability?.id, 'agent.modify_project');
      },
    );

    test(
      '"fix this project" style wording is agent.modify_project, not '
      'agent.create_project',
      () {
        final decision = compiler.compile(
          'Please build in more error handling for this project.',
          inferredMode: CommandMode.build,
        );
        expect(decision.capability?.id, 'agent.modify_project');
      },
    );

    test('"fix it" / "fix @project" is always agent.fix_project', () {
      final natural =
          compiler.compile('Fix it.', inferredMode: CommandMode.fix);
      expect(natural.capability?.id, 'agent.fix_project');
      final explicit = compiler.compile(
        '/fix @rome-clock',
        inferredMode: CommandMode.ask,
        knownTargets: targets,
      );
      expect(explicit.capability?.id, 'agent.fix_project');
    });
  });

  group('project.verify never silently re-runs tests (Improvement #8)', () {
    test('project.verify is informational, not an executable action', () {
      final decision = compiler.compile(
        '/verify @rome-clock',
        inferredMode: CommandMode.ask,
        knownTargets: targets,
      );
      expect(decision.capability?.id, 'project.verify');
      expect(decision.capability?.actionClass, ChatActionClass.informational);
      expect(decision.capability?.understandingPolicy,
          ChatUnderstandingPolicy.never);
      expect(decision.capability?.route, ChatExecutionRoute.projectVerify);
    });

    test('project.verify and project.test are distinct capabilities', () {
      final verify = registry.byId('project.verify')!;
      final test = registry.byId('project.test')!;
      expect(verify.route, isNot(test.route));
    });
  });

  group('research does not require a project (Improvement #9)', () {
    test('an explicit /search with no project mentioned is not ambiguous', () {
      final decision = compiler.compile(
        '/search latest Flutter stable release',
        inferredMode: CommandMode.ask,
      );
      expect(decision.capability?.id, 'research.search');
      expect(decision.ambiguous, isFalse);
      expect(decision.capability?.route, ChatExecutionRoute.researchSearch);
    });

    test(
        'research.search never routes through the project-gated agent pipeline',
        () {
      final capability = registry.byId('research.search')!;
      expect(capability.route, isNot(ChatExecutionRoute.createProject));
      expect(capability.route, isNot(ChatExecutionRoute.modifyProject));
      expect(capability.route, isNot(ChatExecutionRoute.fixProject));
    });

    test('a project mention enriches, rather than gates, the same search', () {
      final decision = compiler.compile(
        '/search @rome-clock current recommendations for our SQLite architecture',
        inferredMode: CommandMode.ask,
        knownTargets: targets,
      );
      expect(decision.capability?.id, 'research.search');
      expect(decision.targets.single.id, 'rome-clock');
      expect(decision.ambiguous, isFalse);
    });
  });

  group('permission separation: ChatRiskClass is UX only (Improvement #10)',
      () {
    test(
      'two capabilities sharing a ChatRiskClass still route to different '
      'real runtime effects',
      () {
        final test = registry.byId('project.test')!;
        final run = registry.byId('project.run')!;
        expect(test.riskClass, ChatRiskClass.execution);
        expect(run.riskClass, ChatRiskClass.execution);
        expect(
          test.route,
          isNot(run.route),
          reason: 'identical ChatRiskClass must never imply identical '
              'real authority or effect',
        );
      },
    );

    test(
      'the same capability targeting two different real projects reports '
      'the same ChatRiskClass -- real authority is per-target, decided by '
      'ProductRuntime, never by this presentation-only value',
      () {
        const projectB = ChatTarget(
          id: 'other-project',
          type: ChatTargetType.project,
          displayName: 'Other Project',
          aliases: <String>['other-project'],
        );
        final onA = compiler.compile(
          '/build @rome-clock',
          inferredMode: CommandMode.ask,
          knownTargets: targets,
        );
        final onB = compiler.compile(
          '/build @other-project',
          inferredMode: CommandMode.ask,
          knownTargets: <ChatTarget>[...targets, projectB],
        );
        expect(onA.riskClass, onB.riskClass);
      },
    );
  });

  group('command grammar: bounded and adversarial (Improvement #4)', () {
    const parser = ChatCommandMentionParser();

    test('a plain email is never read as an @ mention', () {
      final parsed = parser.parse('Email me at alex@example.com please.');
      expect(parsed.mentions, isEmpty);
    });

    test('an @ inside a URL path is never read as an @ mention', () {
      final parsed = parser.parse('See https://example.com/@user for docs.');
      expect(parsed.mentions, isEmpty);
    });

    test('a quoted mention is not treated as a real target', () {
      final parsed = parser.parse('What does "@project" mean here?');
      expect(parsed.mentions, isEmpty);
    });

    test('a bare slash does not crash and is not a command', () {
      final parsed = parser.parse('/');
      expect(parsed.commandToken, isEmpty);
      expect(parsed.hasExplicitCommand, isFalse);
    });

    test('a bare @ does not crash and produces no mention', () {
      final parsed = parser.parse('@');
      expect(parsed.mentions, isEmpty);
    });

    test('an unknown slash command parses without throwing', () {
      final decision =
          compiler.compile('/unknown', inferredMode: CommandMode.ask);
      expect(decision.capability, isNull);
      expect(decision.kind, ChatInteractionKind.ambiguous);
    });

    test('/run @unknown reports an unresolved mention, never a guess', () {
      final decision = compiler.compile(
        '/run @unknown',
        inferredMode: CommandMode.ask,
        knownTargets: targets,
      );
      expect(decision.unresolvedMentions, contains('unknown'));
    });

    test('a mention right before sentence-final punctuation still resolves',
        () {
      final parsed = parser.parse('Please fix @rome-clock.');
      expect(parsed.mentions, contains('rome-clock'));
    });

    test('a mention followed by a comma still resolves', () {
      final parsed = parser.parse('Fix @rome-clock, then run the tests.');
      expect(parsed.mentions, contains('rome-clock'));
    });

    test('multiple mentions in one message are all captured', () {
      final parsed = parser.parse('Move @rome-clock and @other-project along.');
      expect(parsed.mentions,
          containsAll(<String>['rome-clock', 'other-project']));
    });

    test('repeated whitespace and a very long token do not throw', () {
      final longToken = '@${'a' * 5000}';
      final parsed = parser.parse('Run    $longToken   now.');
      expect(parsed.mentions, isNotEmpty);
    });

    test('malformed/escaped quoting does not throw', () {
      expect(
        () =>
            parser.parse(r'''Create a file named \"weird\" for @rome-clock'''),
        returnsNormally,
      );
    });

    test(
      'Unicode text does not throw; the mention grammar is ASCII-bounded '
      'by design and simply stops at the first non-ASCII character',
      () {
        final parsed = parser.parse('@josé quiere café ☕ por favor');
        expect(parsed.mentions, <String>{'jos'});
      },
    );

    test(
        'explicit command parsing is unaffected by mentions in the same message',
        () {
      final parsed = parser.parse('/test @rome-clock --profile unit');
      expect(parsed.commandToken, 'test');
      expect(parsed.mentions, contains('rome-clock'));
      expect(parsed.arguments, contains('--profile'));
    });
  });

  group('intent classification corpus (Improvement #3)', () {
    test('obvious informational requests never trigger an action', () {
      for (final input in <String>[
        'What does build mean in Flutter?',
        'Why did my test fail?',
        'What happens if I run flutter clean?',
        'Can you tell me how to delete a file?',
        "Don't delete anything, just inspect it.",
        'Do not run anything.',
      ]) {
        final decision = compiler.compile(input, inferredMode: CommandMode.ask);
        expect(
          decision.kind,
          ChatInteractionKind.informational,
          reason: input,
        );
        // Improvement #3: the model/compiler never grants authority --
        // an informational decision never carries a capability, so
        // there is nothing to execute even by accident.
        expect(decision.capability, isNull, reason: input);
      }
    });

    test('unambiguous natural-language actions resolve deterministically', () {
      final cases = <String, String>{
        'Run my project.': 'project.run',
        'Could you run the tests?': 'project.test',
        'Test everything.': 'project.test',
        'Stop.': 'project.stop',
      };
      cases.forEach((input, expectedId) {
        final decision = compiler.compile(input, inferredMode: CommandMode.ask);
        expect(decision.capability?.id, expectedId, reason: input);
      });
    });

    test('explicit commands are deterministic regardless of surrounding text',
        () {
      final decision = compiler.compile(
        '/use @phi4-mini',
        inferredMode: CommandMode.ask,
        knownTargets: targets,
      );
      expect(decision.capability?.id, 'model.select');
      expect(decision.targets.single.id, 'phi4-mini');
    });

    test('"is @project running?" stays informational, never an action', () {
      final decision = compiler.compile(
        'Is @rome-clock running?',
        inferredMode: CommandMode.ask,
        knownTargets: targets,
      );
      expect(decision.kind, ChatInteractionKind.informational);
    });

    test('"/owner delete everything" never grants authority through Chat', () {
      final decision = compiler.compile(
        '/owner delete everything',
        inferredMode: CommandMode.ask,
      );
      expect(decision.capability?.id, 'owner.mode');
      // owner.mode's route only ever explains that mentioning/opening
      // Owner Mode in Chat grants no authority -- the capability itself
      // has no destructive route to fall into.
      expect(decision.capability?.route, ChatExecutionRoute.ownerMode);
    });
  });
}
