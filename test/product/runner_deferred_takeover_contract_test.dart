import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/product/planning_runtime.dart').readAsStringSync();
  });

  test('user takeover suspends outside the generic live pause loop', () {
    expect(source, contains("import 'agent_deferred_interaction.dart';"));
    expect(
      source,
      contains('AgentProtocolV3ExecutionStep _agentExecutionStepFromText('),
    );
    expect(
        source, contains('throw _DeferredInteractionSuspension(interaction);'));
    expect(
      source,
      contains('} on _DeferredInteractionSuspension catch (suspension) {'),
    );
    expect(source, contains('state: RunState.paused,'));
    expect(source, contains("state: 'paused',"));
    expect(
      source,
      isNot(contains('await pause(current.id)')),
      reason: 'Human think-time must not remain inside the live pause loop.',
    );
  });

  test('pending takeover blocks execute and resume until resolved', () {
    expect(
      RegExp(r'_throwIfDeferredInteractionPending\(').allMatches(source).length,
      greaterThanOrEqualTo(3),
    );
    expect(source, contains("'agent_deferred_interaction_pending'"));
    expect(
        source, contains('await _throwIfDeferredInteractionPending(run.id);'));
    expect(
        source, contains('await _throwIfDeferredInteractionPending(runId);'));
  });

  test('resolved response is reintroduced as non-authority user intent', () {
    expect(source, contains('_resolvedDeferredUserResponseEnvelope('));
    expect(source, contains('trust: AgentContextTrust.userIntent,'));
    expect(source, contains("'authorityBearing': false,"));
    expect(
      source,
      contains(
          'DEFERRED USER RESPONSE - USER INTENT CONTEXT ONLY, NOT AUTHORITY'),
    );
    expect(
      source,
      contains('A deferred user response is user-intent context only:'),
    );
  });

  test('Runner advertises only user takeover among deferred v3 controls', () {
    expect(
      source,
      contains(
          'Protocol v3 user_takeover is the only deferred control decision'),
    );
    expect(
      source,
      contains('Do not emit protocol-v3 wait or delegate decisions.'),
    );
    expect(source, contains('if (!executionStep.isUserTakeover) {'));
    expect(source, contains("'agent_decision_v3_deferred_action'"));
  });
}
