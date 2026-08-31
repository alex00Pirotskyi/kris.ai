import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String planning;
  late String runtime;
  late String storage;
  late String steering;
  late String specification;

  setUpAll(() {
    planning = File('lib/product/planning_runtime.dart').readAsStringSync();
    runtime = File('lib/product/product_runtime.dart').readAsStringSync();
    storage = File('lib/product/storage_security.dart').readAsStringSync();
    steering = File('lib/product/run_steering.dart').readAsStringSync();
    specification = File('lib/product/task_kernel/task_specification.dart')
        .readAsStringSync();
  });

  test('scope steering stops only at a verified task boundary', () {
    expect(planning, contains('_interruptAtSteeringReplanBoundary('));
    expect(planning, contains('await transaction.commit();'));
    final verification = planning.indexOf('_deterministicVerification(');
    final finalBoundary =
        planning.lastIndexOf('_interruptAtSteeringReplanBoundary(');
    expect(verification, greaterThanOrEqualTo(0));
    expect(finalBoundary, greaterThan(verification));
    expect(
      planning,
      contains(
          'steering_replan_requested: Scope changed after a verified task boundary.'),
    );
    expect(planning, contains("'run.steering_replan_boundary'"));
    expect(planning, contains('attachSteeringReplanHandler'));
  });

  test('replan uses canonical context and reconciliation', () {
    expect(storage, contains('commandPlanningContexts'));
    expect(runtime, contains('CommandPlanningContextRecord'));
    expect(runtime, contains('taskKernel.reconcile('));
    expect(runtime, contains('CompletedTaskRecord.of('));
    expect(runtime, contains('createContinuationRun('));
    expect(runtime, contains('sourceRunId: source.id'));
    expect(runtime, contains('reconciliation.plan.enabledTasks.isEmpty'));
    expect(runtime, contains("title: 'Verify reconciled project state'"));
    expect(runtime, contains('plan: executablePlan'));
  });

  test('continuation never inherits authority implicitly', () {
    expect(runtime, contains("'authorityInherited': false"));
    expect(runtime, contains('requiredPermissions'));
    final continuationStart = runtime.indexOf(
      'Future<void> _materializePendingSteeringContinuation(RunRecord source) async {',
    );
    final continuationEnd = runtime.indexOf(
      '\n  Future<PromptStudioDraft> generatePromptDraft({',
      continuationStart,
    );
    expect(continuationStart, greaterThanOrEqualTo(0));
    expect(continuationEnd, greaterThan(continuationStart));
    final continuationSource = runtime.substring(
      continuationStart,
      continuationEnd,
    );
    expect(continuationSource, isNot(contains('permissions.grant(')));
    expect(steering, contains('continuationRunId'));
  });

  test('scope directives remain user intent, not permission claims', () {
    expect(specification, contains('scopeDirectives'));
    expect(specification, contains('applyForReplan('));
    expect(steering, contains("'steering_authority_claim_rejected'"));
  });
}
