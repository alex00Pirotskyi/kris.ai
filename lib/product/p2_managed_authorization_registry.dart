import 'p2_process_tree.dart';
import 'p2_runtime_composition.dart';

/// Lifecycle-owned authorization registry. Exact process/watchdog identities
/// are registered by the shipped ProductRuntime when a supervised session is
/// created and removed on completion. Unknown or stale identities fail closed.
final class P2ManagedAuthorizationRegistry {
  final Map<String, P2ProcessAuthorization> _process =
      <String, P2ProcessAuthorization>{};
  final Map<String, P2WatchdogAuthorization> _watchdogs =
      <String, P2WatchdogAuthorization>{};

  static String _processKey(P2ProcessIdentity identity) =>
      '${identity.pid}:${identity.startToken}:${identity.supervisorToken}:'
      '${identity.platformGroupId}';

  void registerProcess({
    required P2ProcessIdentity identity,
    required P2ProcessAuthorization authorization,
  }) {
    if (authorization.binding.runId.isEmpty ||
        authorization.binding.taskId.isEmpty ||
        authorization.grantDigest.isEmpty) {
      throw StateError('process_authorization_invalid');
    }
    final key = _processKey(identity);
    final previous = _process[key];
    if (previous != null &&
        (previous.binding.runId != authorization.binding.runId ||
            previous.binding.taskId != authorization.binding.taskId ||
            previous.grantDigest != authorization.grantDigest)) {
      throw StateError('process_authorization_rebind_rejected');
    }
    _process[key] = authorization;
  }

  void registerWatchdog({
    required String watchdogId,
    required P2WatchdogAuthorization authorization,
  }) {
    if (watchdogId.trim().isEmpty ||
        authorization.sessionId.isEmpty ||
        authorization.grantDigest.isEmpty) {
      throw StateError('watchdog_authorization_invalid');
    }
    final previous = _watchdogs[watchdogId];
    if (previous != null &&
        (previous.binding.runId != authorization.binding.runId ||
            previous.binding.taskId != authorization.binding.taskId ||
            previous.grantDigest != authorization.grantDigest ||
            _processKey(previous.processIdentity) !=
                _processKey(authorization.processIdentity))) {
      throw StateError('watchdog_authorization_rebind_rejected');
    }
    _watchdogs[watchdogId] = authorization;
  }

  P2ProcessAuthorization processFor(
    P2ProcessIdentity identity,
    String operation,
  ) {
    final value = _process[_processKey(identity)];
    if (value == null) throw StateError('process_authorization_missing');
    return value;
  }

  P2ProcessAuthorization processForPid(int pid, String operation) {
    final matches = _process.entries
        .where((entry) => entry.key.startsWith('$pid:'))
        .map((entry) => entry.value)
        .toList(growable: false);
    if (matches.length != 1) {
      throw StateError('process_authorization_identity_required');
    }
    return matches.single;
  }

  P2WatchdogAuthorization watchdogFor(String id, String operation) {
    final value = _watchdogs[id];
    if (value == null) throw StateError('watchdog_authorization_missing');
    return value;
  }

  void unregister({
    required String watchdogId,
    required P2ProcessIdentity processIdentity,
  }) {
    _watchdogs.remove(watchdogId);
    _process.remove(_processKey(processIdentity));
  }

  void clear() {
    _watchdogs.clear();
    _process.clear();
  }

  Map<String, Object?> get provenance => <String, Object?>{
    'implementation': 'P2ManagedAuthorizationRegistry',
    'processBindings': _process.length,
    'watchdogBindings': _watchdogs.length,
    'exactIdentityRequired': true,
    'syntheticFallback': false,
  };
}
