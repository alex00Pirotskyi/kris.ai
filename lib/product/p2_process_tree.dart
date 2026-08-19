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

  String get stableKey =>
      '$pid:$startToken:$supervisorToken:$platformGroupId';

  void validate() {
    if (pid <= 1) throw StateError('process_identity_pid');
    if (startToken.trim().isEmpty ||
        supervisorToken.trim().isEmpty ||
        platformGroupId.trim().isEmpty) {
      throw StateError('process_identity_binding');
    }
  }

  factory P2ProcessIdentity.fromJson(Map<String, Object?> value) {
    final pid = value['pid'];
    if (pid is! int || pid <= 1) {
      throw const FormatException('process_identity_pid');
    }
    final identity = P2ProcessIdentity(
      pid: pid,
      startToken: value['startToken']?.toString() ?? '',
      supervisorToken: value['supervisorToken']?.toString() ?? '',
      platformGroupId: value['platformGroupId']?.toString() ?? '',
    );
    try {
      identity.validate();
    } on StateError {
      throw const FormatException('process_identity_binding');
    }
    return identity;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'pid': pid,
        'startToken': startToken,
        'supervisorToken': supervisorToken,
        'platformGroupId': platformGroupId,
      };
}

abstract interface class P2NativeProcessTreeAdapter {
  Future<P2ProcessLifecycle> inspect(P2ProcessIdentity identity);
  Future<void> requestStop(P2ProcessIdentity identity, Duration grace);
  Future<void> forceKill(P2ProcessIdentity identity);
}

class P2ProcessTreeManager {
  P2ProcessTreeManager(this.adapter);

  static const Set<P2ProcessLifecycle> terminalStates = <P2ProcessLifecycle>{
    P2ProcessLifecycle.exited,
    P2ProcessLifecycle.killed,
    P2ProcessLifecycle.stopped,
  };

  final P2NativeProcessTreeAdapter adapter;
  final Map<String, Future<void>> _kills = <String, Future<void>>{};

  void _validateWait(Duration timeout, Duration pollInterval) {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 2)) {
      throw StateError('process_wait_timeout_invalid');
    }
    if (pollInterval <= Duration.zero ||
        pollInterval > const Duration(seconds: 5)) {
      throw StateError('process_wait_interval_invalid');
    }
  }

  void _requireInspectable(P2ProcessLifecycle state) {
    if (state == P2ProcessLifecycle.unknown ||
        state == P2ProcessLifecycle.unsupported) {
      throw StateError('managed_process_identity_unverified');
    }
  }

  Future<P2ProcessIdentity> adoptManaged(P2ProcessIdentity identity) async {
    identity.validate();
    final state = await adapter.inspect(identity);
    _requireInspectable(state);
    if (terminalStates.contains(state)) {
      throw StateError('managed_process_already_terminated');
    }
    return identity;
  }

  Future<P2ProcessLifecycle> waitUntilRunning(
    P2ProcessIdentity identity, {
    Duration timeout = const Duration(seconds: 10),
    Duration pollInterval = const Duration(milliseconds: 50),
  }) async {
    identity.validate();
    _validateWait(timeout, pollInterval);
    final stopwatch = Stopwatch()..start();
    while (true) {
      final state = await adapter.inspect(identity);
      _requireInspectable(state);
      if (state == P2ProcessLifecycle.running) return state;
      if (terminalStates.contains(state)) {
        throw StateError('managed_process_exited_before_ready');
      }
      if (stopwatch.elapsed >= timeout) {
        throw TimeoutException('managed_process_readiness_timeout', timeout);
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<P2ProcessLifecycle> waitUntilTerminated(
    P2ProcessIdentity identity, {
    Duration timeout = const Duration(seconds: 10),
    Duration pollInterval = const Duration(milliseconds: 50),
  }) async {
    identity.validate();
    _validateWait(timeout, pollInterval);
    final stopwatch = Stopwatch()..start();
    while (true) {
      final state = await adapter.inspect(identity);
      _requireInspectable(state);
      if (terminalStates.contains(state)) return state;
      if (stopwatch.elapsed >= timeout) {
        throw TimeoutException('managed_process_termination_timeout', timeout);
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<void> stop(
    P2ProcessIdentity identity, {
    Duration grace = const Duration(seconds: 3),
  }) async {
    identity.validate();
    if (grace <= Duration.zero || grace > const Duration(seconds: 30)) {
      throw StateError('process_stop_grace_invalid');
    }
    final state = await adapter.inspect(identity);
    _requireInspectable(state);
    if (terminalStates.contains(state)) return;

    await adapter.requestStop(identity, grace);
    final after = await adapter.inspect(identity);
    _requireInspectable(after);
    if (!terminalStates.contains(after)) await kill(identity);
  }

  Future<void> kill(P2ProcessIdentity identity) {
    identity.validate();
    final key = identity.stableKey;
    final existing = _kills[key];
    if (existing != null) return existing;

    late final Future<void> operation;
    operation = (() async {
      await adapter.forceKill(identity);
      final after = await adapter.inspect(identity);
      _requireInspectable(after);
      if (!terminalStates.contains(after)) {
        throw StateError('process_tree_termination_unverified');
      }
    })().whenComplete(() {
      if (identical(_kills[key], operation)) _kills.remove(key);
    });
    _kills[key] = operation;
    return operation;
  }

  Future<P2ProcessLifecycle> reconcile(P2ProcessIdentity identity) {
    identity.validate();
    return adapter.inspect(identity);
  }
}
