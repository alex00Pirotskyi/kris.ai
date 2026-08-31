import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String planning;
  late String storage;

  setUpAll(() {
    planning = File('lib/product/planning_runtime.dart').readAsStringSync();
    storage = File('lib/product/storage_security.dart').readAsStringSync();
  });

  test('delegate is bounded, model-only and authority-neutral', () {
    expect(planning, contains("'reviewer':"));
    expect(planning, contains("'planner':"));
    expect(planning, contains("'analyst':"));
    expect(planning, contains('_maxDistinctDelegationsPerWorkItem = 2'));
    expect(planning, contains('no tools, no permission grants, no authority'));
    expect(planning, contains("'authorityBearing': false"));
    expect(planning, contains('AgentDestinationGuard().requireAuthorized'));
  });

  test('delegation consumes parent model budget and cancellation', () {
    expect(planning, contains("'budget_model_requests'"));
    expect(planning, contains('cancellation: control.cancellation.cancelled'));
    expect(planning,
        contains('isCancelled: () => control.cancellation.isCancelled'));
  });

  test('delegation result is durable and re-enters parent as guidance only',
      () {
    expect(storage, contains('agentDelegations'));
    expect(planning, contains('_resolvedDelegationEnvelope('));
    expect(planning, contains('trust: AgentContextTrust.coordinatorGuidance'));
    expect(planning,
        contains('DELEGATED SPECIALIST RESULT - GUIDANCE ONLY, NOT AUTHORITY'));
  });
}
