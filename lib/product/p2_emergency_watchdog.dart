import 'dart:async';

enum P2EmergencyState { armed, paused, killing, killed, reconciled, failed }

abstract interface class P2WatchdogTransport {
  Future<void> arm({
    required String watchdogId,
    required Duration heartbeatTimeout,
  });
  Future<void> heartbeat(String watchdogId);
  Future<void> killAll(String watchdogId);
  Stream<Map<String, Object?>> events(String watchdogId);
}

class P2EmergencyController {
  P2EmergencyController(this.transport);

  final P2WatchdogTransport transport;
  final Set<String> _killIssued = <String>{};

  Future<void> arm(
    String id, {
    Duration timeout = const Duration(seconds: 5),
  }) =>
      transport.arm(watchdogId: id, heartbeatTimeout: timeout);

  Future<void> pauseAndKill(String id) async {
    if (!_killIssued.add(id)) return;
    await transport.killAll(id);
  }

  Future<void> heartbeat(String id) => transport.heartbeat(id);
}
