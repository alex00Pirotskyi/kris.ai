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

  test('resume waits for deferred stack release before re-entering execute',
      () {
    expect(source, contains('bool deferredSuspension = false;'));
    expect(source, contains('control.deferredSuspension = true;'));
    expect(
      source,
      contains('if (control != null && control.deferredSuspension) {'),
    );
    expect(source, contains('final active = _active[runId];'));
    expect(source, contains('await active;'));
    expect(source, contains('unawaited(execute(runId));'));
    expect(source, contains('control.deferredSuspension = false;'));
  });

  test('durably paused cancellation rolls back before terminal state', () {
    expect(
      source,
      contains('if (control == null && run.state == RunState.paused) {'),
    );
    expect(source, contains('await _cancelDurablyPausedRun(run);'));
    expect(source, contains('Future<void> _cancelDurablyPausedRun('));
    expect(source, contains('await WorkspaceTransaction.begin('));
    expect(source, contains('await transaction.rollback();'));
    expect(source, contains('state: RunState.cancelled,'));
    expect(source, contains('state: WorkItemState.cancelled,'));
    expect(source, contains("state: 'cancelled',"));
    expect(source, contains("'durablePausedCancellation': true,"));
    expect(source, contains("'rolledBackWorkspace': true,"));
  });

  test('cancel waits for a deferred stack to unwind before rollback', () {
    expect(
      source,
      contains('if (control != null && control.deferredSuspension) {'),
    );
    expect(source, contains('control.cancellation.cancel();'));
    expect(source, contains('final active = _active[runId];'));
    expect(source, contains('await active;'));
    expect(source, contains('control = _controls[runId];'));
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
