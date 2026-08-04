import 'dart:async';

enum P2ProcessLifecycle {
  starting,
  running,
  stopping,
  stopped,
  killing,
  killed,
  exited,
  unknown,
  unsupported,
}

class P2ProcessIdentity {
  const P2ProcessIdentity({
    required this.pid,
    required this.startToken,
    required this.supervisorToken,
    required this.platformGroupId,
  });

  final int pid;
  final String startToken;
  final String supervisorToken;
  final String platformGroupId;

  factory P2ProcessIdentity.fromJson(Map<String, Object?> value) {
    final pid = value['pid'];
    if (pid is! int || pid <= 1) {
      throw const FormatException('process_identity_pid');
    }
    final startToken = value['startToken']?.toString() ?? '';
    final supervisorToken = value['supervisorToken']?.toString() ?? '';
    final platformGroupId = value['platformGroupId']?.toString() ?? '';
    if (startToken.isEmpty ||
        supervisorToken.isEmpty ||
        platformGroupId.isEmpty) {
      throw const FormatException('process_identity_binding');
    }
    return P2ProcessIdentity(
      pid: pid,
      startToken: startToken,
      supervisorToken: supervisorToken,
      platformGroupId: platformGroupId,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'pid': pid,
        'startToken': startToken,
        'supervisorToken': supervisorToken,
        'platformGroupId': platformGroupId,
      };
}

abstract interface class P2NativeProcessTreeAdapter {
  Future<P2ProcessIdentity> register(int pid);
  Future<P2ProcessLifecycle> inspect(P2ProcessIdentity identity);
  Future<void> requestStop(P2ProcessIdentity identity, Duration grace);
  Future<void> forceKill(P2ProcessIdentity identity);
}

class P2ProcessTreeManager {
  P2ProcessTreeManager(this.adapter);

  final P2NativeProcessTreeAdapter adapter;
  final Map<String, Future<void>> _kills = <String, Future<void>>{};

  Future<P2ProcessIdentity> register(int pid) => adapter.register(pid);

  Future<void> stop(
    P2ProcessIdentity identity, {
    Duration grace = const Duration(seconds: 3),
  }) async {
    final state = await adapter.inspect(identity);
    if (<P2ProcessLifecycle>{
      P2ProcessLifecycle.exited,
      P2ProcessLifecycle.killed,
      P2ProcessLifecycle.stopped,
    }.contains(state)) {
      return;
    }
    await adapter.requestStop(identity, grace);
    final after = await adapter.inspect(identity);
    if (!<P2ProcessLifecycle>{
      P2ProcessLifecycle.exited,
      P2ProcessLifecycle.stopped,
      P2ProcessLifecycle.killed,
    }.contains(after)) {
      await kill(identity);
    }
  }

  Future<void> kill(P2ProcessIdentity identity) => _kills.putIfAbsent(
        '${identity.pid}:${identity.startToken}:${identity.supervisorToken}',
        () => adapter.forceKill(identity),
      );

  Future<P2ProcessLifecycle> reconcile(P2ProcessIdentity identity) =>
      adapter.inspect(identity);
}
