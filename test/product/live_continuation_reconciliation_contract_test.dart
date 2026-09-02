import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification_patch.dart';
import 'package:kristin_local_agent/product/run_steering.dart';

void main() {
  test('live semantic patch replan boundary is explicit and authority neutral',
      () {
    const preference = TaskSpecificationPatch(
      kind: TaskSpecificationPatchKind.preference,
      value: 'Prefer the smaller surface.',
    );
    const hardConstraint = TaskSpecificationPatch(
      kind: TaskSpecificationPatchKind.hardConstraint,
      value: 'Do not touch the database.',
    );
    expect(preference.requiresReplan, isFalse);
    expect(hardConstraint.requiresReplan, isTrue);
    expect(preference.grantsAuthority, isFalse);
    expect(hardConstraint.grantsAuthority, isFalse);
  });

  test('continuation materialization cannot grant inherited authority', () {
    final source = File('lib/product/product_runtime.dart').readAsStringSync();
    final start = source.indexOf(
      'Future<void> _materializePendingSteeringContinuation',
    );
    final end = source.indexOf(
      'Future<PromptStudioDraft> generatePromptDraft',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);
    expect(body, contains("'authorityInherited': false"));
    expect(body, contains('createContinuationRun'));
    expect(body, isNot(contains('permissions.grant(')));
  });

  test('Chat follows continuation planning context without stale plan fallback',
      () {
    final source =
        File('lib/product/chat_control_plane_studio.dart').readAsStringSync();
    expect(source, contains('steeringContinuationForSourceRun'));
    expect(source, contains('commandPlanningContexts'));
    expect(source, contains('replaceRunWithContinuation'));
    expect(
        source, contains('canonicalPlan = continuationContext.canonicalPlan'));
    expect(source, contains('canonicalPlan = null'));
  });
}
