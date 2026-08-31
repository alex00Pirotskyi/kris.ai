import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String deferred;
  late String runner;
  late String runtime;

  setUpAll(() {
    deferred =
        File('lib/product/agent_deferred_interaction.dart').readAsStringSync();
    runner = File('lib/product/planning_runtime.dart').readAsStringSync();
    runtime = File('lib/product/product_runtime.dart').readAsStringSync();
  });

  test('timestamp wait has a durable, authority-free resolution path', () {
    expect(deferred, contains('resolveReadyTimestampWait({'));
    expect(deferred, contains("'agent.deferred.wait_elapsed'"));
    expect(deferred, contains("'agent_deferred_wait_not_ready'"));
    expect(deferred, contains("'agent_deferred_wait_not_timestamp'"));
    expect(deferred, contains("'grantsAuthority': false"));
  });

  test('runner accepts bounded timestamp waits but not opaque handles', () {
    expect(runner,
        contains('final executableTimestampWait = executionStep.isWait'));
    expect(runner, contains('_maxDeferredTimestampWait = Duration(hours: 24)'));
    expect(runner, contains("'agent_decision_v3_wait_too_long'"));
    expect(
        runner,
        contains(
            'Protocol v3 opaque wait handles require a registered signal source'));
  });

  test('wait releases execution stack and resumes through a timer', () {
    expect(runner,
        contains('_scheduleDeferredTimestampWait(suspension.interaction);'));
    expect(runner, contains('await active;'));
    expect(runner,
        contains('await store.resolveReadyTimestampWait(runId: runId);'));
    expect(runner, contains('unawaited(execute(runId));'));
  });

  test('resolved wait is reintroduced only as coordinator guidance', () {
    expect(runner, contains('_resolvedDeferredWaitEnvelope('));
    expect(runner, contains('source: AgentContextSource.coordinator'));
    expect(runner, contains('trust: AgentContextTrust.coordinatorGuidance'));
    expect(runner, contains("'authorityBearing': false"));
    expect(
        runner,
        contains(
            'DEFERRED WAIT CONTINUATION - COORDINATOR GUIDANCE, NOT AUTHORITY'));
  });

  test('runtime restores and tears down timestamp wait schedules', () {
    expect(
        runtime, contains('await coordinator.restoreDeferredWaitSchedules();'));
    expect(runtime, contains('runs.cancelDeferredWaitSchedules();'));
  });
}
