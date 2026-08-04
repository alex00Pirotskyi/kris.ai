import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_effect_boundary.dart';

void main() {
  test('effect binding carries exact P1 identities', () {
    const binding = P2EffectBinding(
      runId: 'r',
      taskId: 't',
      actorId: 'owner_executor',
      toolId: 'write_file',
      accessProfileId: 'owner',
      capabilityId: 'filesystem.write',
      operation: 'write',
    );
    expect(binding.accessProfileId, 'owner');
    expect(binding.operation, 'write');
  });
}
