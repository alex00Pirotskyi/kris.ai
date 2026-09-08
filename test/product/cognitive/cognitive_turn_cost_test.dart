// Regression proof for the cost of an ordinary conversation turn.
//
// A cognitive projection is compiled into the system prompt of every chat
// answer, so its size is prompt-evaluation time on the user's machine. A
// budget that is *filled* rather than *bounded* makes a greeting cost exactly
// as much as a deep planning turn: on a local 7B model that was enough to
// exhaust the first-token deadline and fail the turn outright.
//
// These tests pin the shape of the fix: a focused turn carries what the turn
// touches, planning still carries the broad list, and nothing that was
// omitted is ever presented as absent.

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/cognitive/cognitive_model.dart';
import 'package:kristin_local_agent/product/self_awareness/capability_self_model.dart';

import 'cognitive_test_support.dart';

/// A realistically populated application: many known capabilities and live
/// state maps of the size the shipped runtime actually reports.
KristinSelfSnapshot _liveSelf() => testSelf(
      application: testApplication(
        selectedProject: <String, Object?>{
          'id': 'project-1',
          'name': 'Smart Image Archive',
          'rootPath': '/home/alex/projects/smart-image-archive',
          'profile': 'flutter',
        },
        selectedModel: <String, Object?>{
          'exactId': 'ollama/qwen2.5-coder:7b@sha256-abcdef0123456789',
          'name': 'qwen2.5-coder:7b',
          'discovered': true,
        },
        browser: <String, Object?>{'runtimeInstalled': true, 'sessions': 0},
        ownerMode: <String, Object?>{
          'runtimeAvailable': true,
          'entered': false
        },
        runState: <String, Object?>{'active': false},
        authority: <String, Object?>{'ownerMode': 'not_evaluated'},
      ),
      capabilities: <KnownCapability>[
        for (var index = 0; index < 38; index++)
          testCapability('unrelated.capability.$index'),
        testCapability('browser.session'),
        testCapability('owner.mode'),
      ],
    );

Future<CognitiveContextProjection> _compile(
  String objective, {
  CognitiveReasoningPathway pathway = CognitiveReasoningPathway.conversation,
  Set<String> capabilityHints = const <String>{},
  List<KnownCapability>? capabilities,
}) =>
    buildTestSubstrate(
      project: testProject(),
      self: capabilities == null
          ? _liveSelf()
          : testSelf(
              application: _liveSelf().application,
              capabilities: capabilities,
            ),
    ).compile(
      CognitiveContextRequest(
        objective: objective,
        pathway: pathway,
        capabilityHints: capabilityHints,
        selectedProject: testProject(),
        selectedModel: testModel(),
        maxCharacters: 6800,
      ),
    );

void main() {
  group('conversation turn cost', () {
    test('a greeting does not drag the whole catalog into the prompt',
        () async {
      final greeting = await _compile('hey');

      expect(
        greeting.includedIds.where((id) => id.startsWith('capability:')),
        isEmpty,
        reason: 'no capability relates to a greeting',
      );
      expect(greeting.omittedCounts['capabilities'], 40);
      expect(
        greeting.includedIds.where((id) => id.startsWith('product:')),
        isEmpty,
      );
      expect(greeting.coordinatorGuidance, isNot(contains('CAPABILITIES')));

      // The turn still carries everything that keeps an answer truthful.
      expect(greeting.coordinatorGuidance, startsWith('EPISTEMIC RULE'));
      expect(greeting.coordinatorGuidance, contains('IDENTITY'));
      expect(greeting.coordinatorGuidance, contains('APPLICATION STATE'));
      expect(greeting.coordinatorGuidance, contains('selectedModel='));
    });

    test('a greeting costs materially less than a planning turn', () async {
      final greeting = await _compile('hey');
      final planning = await _compile(
        'plan a refactor of the archive importer',
        pathway: CognitiveReasoningPathway.taskPlanning,
      );

      expect(
        planning.includedIds.where((id) => id.startsWith('capability:')).length,
        greaterThan(8),
        reason: 'planning still plans against the real capability set',
      );
      // The regression this pins: both turns used to render the same size.
      expect(
        greeting.coordinatorGuidance.length * 2,
        lessThan(planning.coordinatorGuidance.length),
      );
    });

    test('a turn that names a capability still receives it in full', () async {
      final asked = await _compile('why is the browser session unavailable?');

      expect(asked.includedIds, contains('capability:browser.session'));
      expect(asked.coordinatorGuidance, contains('CAPABILITIES'));
      expect(asked.coordinatorGuidance, contains('availability='));
      expect(asked.coordinatorGuidance, contains('authority='));
      expect(
        asked.includedIds,
        isNot(contains('capability:unrelated.capability.0')),
      );
    });

    test('an explicit capability hint is always carried', () async {
      final hinted = await _compile(
        'hey',
        capabilityHints: <String>{'owner.mode'},
      );
      expect(hinted.includedIds, contains('capability:owner.mode'));
    });

    test('a degraded capability is surfaced even when unasked', () async {
      final degraded = await _compile(
        'hey',
        capabilities: <KnownCapability>[
          for (var index = 0; index < 20; index++)
            testCapability('unrelated.capability.$index'),
          testCapability(
            'browser.session',
            state: CapabilityAvailabilityState.unavailable,
          ),
          testCapability(
            'runner.execute',
            health: CapabilityHealthState.failing,
            riskClass: CapabilityRiskClass.sensitive,
          ),
        ],
      );

      expect(degraded.includedIds, contains('capability:browser.session'));
      expect(degraded.includedIds, contains('capability:runner.execute'));
      expect(
        degraded.includedIds.where((id) => id.startsWith('capability:')).length,
        lessThanOrEqualTo(4),
        reason: 'the degraded sample stays bounded',
      );
    });

    test('omission is stated as unobserved, never as absent', () async {
      final greeting = await _compile('hey');
      expect(
        greeting.coordinatorGuidance,
        contains('not observed in this turn'),
      );
      expect(
        greeting.coordinatorGuidance,
        contains('never evidence that it does not exist'),
      );
    });

    test('required application state is bounded field by field', () async {
      final wide = await _compile(
        'hey',
        capabilities: const <KnownCapability>[],
      );
      final section = sectionOf(wide.coordinatorGuidance, 'APPLICATION STATE');
      for (final line in section.split('\n').skip(1)) {
        expect(
          line.length,
          lessThan(700),
          reason: 'an unbounded live-state value would be truncated mid-JSON',
        );
      }
    });
  });
}
