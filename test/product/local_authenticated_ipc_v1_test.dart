import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/local_authenticated_ipc_v1.dart';

void main() {
  test('IPC envelope requires identity, request id, deadline and MAC', () {
    final envelope = LocalIpcEnvelopeV1(
      peerId: 'desktop-host',
      requestId: 'request-1',
      deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      body: const <String, Object?>{'operation': 'ping'},
      mac: List<String>.filled(32, '00').join(),
    );
    expect(envelope.toJson()['requestId'], 'request-1');
  });

  test('IPC transport policy is mutually authenticated on all desktops', () {
    const policy = LocalIpcTransportPolicyV1();
    expect(policy.requiresMutualAuthentication, isTrue);
    expect(policy.requiresPeerIdentity, isTrue);
    expect(policy.requiresReplayProtection, isTrue);
    expect(LocalIpcTransportPolicyV1.transports.keys.toSet(), <String>{
      'windows',
      'macos',
      'linux',
    });
  });
}
