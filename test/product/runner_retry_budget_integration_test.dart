import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live retry path does not use the legacy repair-reserve gate', () {
    final source = File('lib/product/planning_runtime.dart').readAsStringSync();
    final retryStart = source.indexOf('_RetryDecision _retryDecision({');
    final retryEnd = source.indexOf('Future<void> _awaitControl', retryStart);

    expect(retryStart, greaterThanOrEqualTo(0));
    expect(retryEnd, greaterThan(retryStart));

    final retrySource = source.substring(retryStart, retryEnd);
    expect(retrySource, isNot(contains('RunRetryBudgetPolicy')));
    expect(retrySource, isNot(contains('insufficient_repair_reserve')));
    expect(retrySource, contains('recovery_safety_limit'));
    expect(retrySource, contains('_recoverySafetyLimit(run)'));
  });

  test('live Runner exposes no-progress pressure and a generous outer fuse', () {
    final source = File('lib/product/planning_runtime.dart').readAsStringSync();
    final promptStart = source.indexOf('String _userPrompt(');
    final promptEnd = source.indexOf('AgentAction _agentActionFromText', promptStart);

    expect(source, contains('static const int _minimumRecoverySafetyLimit = 24;'));
    expect(source, contains("'repairBudgetSemantic': 'outer_recovery_fuse'"));
    expect(source, contains('successfulVerification = result.ok;'));
    expect(promptStart, greaterThanOrEqualTo(0));
    expect(promptEnd, greaterThan(promptStart));

    final promptSource = source.substring(promptStart, promptEnd);
    expect(promptSource, contains('consecutiveNoProgress='));
    expect(promptSource, isNot(contains('repairs=')));
  });
}
