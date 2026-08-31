import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'scope steering before execution materializes a continuation immediately',
      () {
    final planning =
        File('lib/product/planning_runtime.dart').readAsStringSync();
    final runtime = File('lib/product/product_runtime.dart').readAsStringSync();

    expect(planning, contains('interruptAwaitingApprovalForSteeringReplan'));
    expect(planning, contains("run.state != RunState.awaitingApproval"));
    expect(planning, contains("'executionStarted': false"));
    expect(planning, contains("'authorityInherited': false"));

    expect(runtime, contains('source?.state == RunState.awaitingApproval'));
    expect(runtime, contains('interruptAwaitingApprovalForSteeringReplan'));
    expect(
        runtime, contains('_materializePendingSteeringContinuation(retired)'));
    expect(runtime, contains('RunSteeringInstruction.fromRecord(record)'));
  });
}
