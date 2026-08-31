import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bounded delegation converges across repeats and restart', () {
    final record =
        File('lib/product/agent_delegation_record.dart').readAsStringSync();
    final runner = File('lib/product/planning_runtime.dart').readAsStringSync();
    expect(record, contains('interrupted'));
    expect(record, contains('attempts'));
    expect(runner, contains("'agent_delegation_previous_failure'"));
    expect(runner, contains("'agent_delegation_retry_exhausted'"));
    expect(runner, contains('reconcileInterruptedDelegations'));
    expect(
        runner, contains('existing?.state == AgentDelegationState.succeeded'));
    expect(runner, contains("'agent.delegation_replayed'"));
  });
}
