import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'p2_automation_host.dart';
import 'p2_automation_host_operations.dart';
import 'p2_automation_host_process_client.dart';
import 'p2_automation_command_service.dart';
import 'p2_desktop_effect_authorizers.dart';
import 'p2_effect_boundary.dart';
import 'p2_effect_journal.dart';
import 'p2_emergency_watchdog.dart';
import 'p2_filesystem_service.dart';
import 'p2_process_tree.dart';
import 'p2_pty_service.dart';
import 'p2_snapshot_undo.dart';

P2EffectBinding _operationBinding(P2EffectBinding source, String operation) =>
    P2EffectBinding(
      runId: source.runId,
      taskId: source.taskId,
      actorId: source.actorId,
      toolId: source.toolId,
      accessProfileId: source.accessProfileId,
      capabilityId: source.capabilityId,
      operation: operation,
    );

bool _sameAuthority(P2EffectBinding left, P2EffectBinding right) =>
    left.runId == right.runId &&
    left.taskId == right.taskId &&
    left.actorId == right.actorId &&
    left.toolId == right.toolId &&
    left.accessProfileId == right.accessProfileId &&
    left.capabilityId == right.capabilityId;

P2PtyState _ptyState(Object? value) => P2PtyState.values.firstWhere(
      (P2PtyState candidate) => candidate.name == value?.toString(),
      orElse: () => P2PtyState.unknown,
    );

final class _P2PtySessionAuthority {
  const _P2PtySessionAuthority({
    required this.openRequestId,
    required this.binding,
    required this.grantDigest,
    required this.openGrantProof,
    required this.processIdentity,
  });

  final String openRequestId;
  final P2EffectBinding binding;
  final String grantDigest;
  final P2WorkerGrantProof openGrantProof;
  final P2ProcessIdentity processIdentity;
}

/// Concrete PTY adapter used by the desktop product. Every session operation
/// receives a new desktop-issued envelope, while the worker additionally checks
/// that run/task/actor/tool/profile/capability/grant remain bound to the session.
typedef P2PtySessionOpened = Future<void> Function(
  P2PtyOpenRequest request,
  P2PtySession session,
  P2EffectBinding binding,
  String grantDigest,
);

final class P2AutomationPtyBackend implements P2PtyBackend {
  P2AutomationPtyBackend({
    required this.client,
    required this.authority,
    required this.journal,
    this.onSessionOpened,
  });

  final P2AutomationHostClient client;
  final P2AutomationEnvelopeAuthority authority;
  final P2EffectJournal journal;
  final P2PtySessionOpened? onSessionOpened;
  final Map<String, P2EffectReceipt> _receipts = <String, P2EffectReceipt>{};
  final Map<String, _P2PtySessionAuthority> _sessions =
      <String, _P2PtySessionAuthority>{};

  Future<void> _recordReceipt(
    Map<String, Object?> response,
    String operation, {
    String? sessionId,
  }) async {
    final raw = response['receipt'];
    if (raw is! Map) throw StateError('pty_effect_receipt_missing');
    final receipt = P2EffectReceipt.fromJson(Map<String, Object?>.from(raw));
    if (receipt.operation != operation) {
      throw StateError('pty_effect_receipt_operation_mismatch');
    }
    await journal.append(receipt);
    final id = sessionId ?? response['sessionId']?.toString();
    if (id != null && id.isNotEmpty) _receipts[id] = receipt;
  }

  P2EffectReceipt? receiptFor(String sessionId) => _receipts[sessionId];

  Future<Map<String, Object?>> _invoke(
    P2EffectBinding binding,
    String operation,
    Map<String, Object?> payload, {
    required String expectedGrantDigest,
    Duration deadline = const Duration(seconds: 30),
  }) async {
    final envelope = await authority.issue(
      binding: _operationBinding(binding, operation),
      operation: operation,
      payload: <String, Object?>{'operation': operation, ...payload},
      expectedGrantDigest: expectedGrantDigest,
      deadline: deadline,
    );
    final response = await client.invoke(envelope);
    if (response['status'] == 'error') {
      throw StateError(response['code']?.toString() ?? 'pty_operation_failed');
    }
    await _recordReceipt(
      response,
      operation,
      sessionId: payload['sessionId']?.toString(),
    );
    return response;
  }

  _P2PtySessionAuthority _session(
    String sessionId,
    P2EffectBinding binding,
    String grantDigest,
  ) {
    final session = _sessions[sessionId];
    if (session == null) throw StateError('pty_session_unknown');
    if (!_sameAuthority(session.binding, binding) ||
        session.grantDigest != grantDigest) {
      throw StateError('pty_session_authorization_mismatch');
    }
    return session;
  }

  P2PtySession _fromResponse(
    String sessionId,
    Map<String, Object?> response,
    _P2PtySessionAuthority authorityRecord,
  ) {
    final rawIdentity = response['processIdentity'];
    final identity = rawIdentity is Map
        ? P2ProcessIdentity.fromJson(Map<String, Object?>.from(rawIdentity))
        : authorityRecord.processIdentity;
    return P2PtySession(
      sessionId: sessionId,
      runId: authorityRecord.binding.runId,
      taskId: authorityRecord.binding.taskId,
      actorId: authorityRecord.binding.actorId,
      grantDigest: authorityRecord.grantDigest,
      processIdentity: identity,
      state: _ptyState(
        response['state'] ?? response['lifecycle'] ?? 'attached',
      ),
      transcriptCursor: response['nextCursor'] is int
          ? response['nextCursor']! as int
          : response['cursor'] is int
              ? response['cursor']! as int
              : 0,
    );
  }

  @override
  Future<P2PtySession> open(
    P2PtyOpenRequest request,
    P2EffectBinding binding,
    String grantDigest,
  ) async {
    request.validate();
    final exact = _operationBinding(binding, 'pty.open');
    final envelope = await authority.issue(
      binding: exact,
      operation: 'pty.open',
      payload: <String, Object?>{
        'operation': 'pty.open',
        'shell': request.shell,
        'cwd': request.cwd,
        'arguments': request.arguments,
        'environmentDelta': request.environmentDelta,
        'columns': request.columns,
        'rows': request.rows,
        'transcriptBudgetBytes': request.transcriptBudgetBytes,
      },
      expectedGrantDigest: grantDigest,
      deadline: const Duration(seconds: 45),
    );
    if (envelope.grantProof.grantDigest != grantDigest) {
      throw StateError('pty_grant_digest_mismatch');
    }
    final response = await client.invoke(envelope);
    if (response['status'] != 'ok') {
      throw StateError('pty_open_${response['status'] ?? 'invalid'}');
    }
    final sessionId = response['sessionId'];
    await _recordReceipt(
      response,
      'pty.open',
      sessionId: sessionId?.toString(),
    );
    final rawIdentity = response['processIdentity'];
    if (sessionId is! String || sessionId.isEmpty || rawIdentity is! Map) {
      throw StateError('pty_open_response_invalid');
    }
    final identity = P2ProcessIdentity.fromJson(
      Map<String, Object?>.from(rawIdentity),
    );
    final record = _P2PtySessionAuthority(
      openRequestId: envelope.requestId,
      binding: binding,
      grantDigest: grantDigest,
      openGrantProof: envelope.grantProof,
      processIdentity: identity,
    );
    _sessions[sessionId] = record;
    final session = _fromResponse(sessionId, response, record);
    final opened = onSessionOpened;
    if (opened != null) {
      try {
        await opened(request, session, binding, grantDigest);
      } catch (_) {
        _sessions.remove(sessionId);
        try {
          await _invoke(
              binding,
              'pty.terminate',
              <String, Object?>{
                'sessionId': sessionId,
                'processIdentity': identity.toJson(),
              },
              expectedGrantDigest: grantDigest);
        } catch (_) {
          // The session is unknown until restart reconciliation; never claim open.
        }
        rethrow;
      }
    }
    return session;
  }

  @override
  Stream<List<int>> output(
    String sessionId,
    int fromCursor, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async* {
    final record = _session(sessionId, binding, grantDigest);
    final attach = await _invoke(
        binding,
        'pty.attach',
        <String, Object?>{
          'sessionId': sessionId,
          'fromCursor': fromCursor,
          'processIdentity': record.processIdentity.toJson(),
        },
        expectedGrantDigest: grantDigest);
    final backlog = attach['dataBase64'];
    if (backlog is String && backlog.isNotEmpty) {
      yield base64Decode(backlog);
    }
    await for (final event in client.stream(
      record.openRequestId,
      binding: record.binding,
      grantProof: record.openGrantProof,
    )) {
      if (event['sessionId'] != sessionId || event['type'] != 'pty.data') {
        continue;
      }
      final encoded = event['dataBase64'];
      if (encoded is String && encoded.isNotEmpty) yield base64Decode(encoded);
    }
  }

  Future<Map<String, Object?>> _sessionOperation(
    String sessionId,
    String operation,
    Map<String, Object?> payload, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) {
    final record = _session(sessionId, binding, grantDigest);
    return _invoke(
        binding,
        operation,
        <String, Object?>{
          'sessionId': sessionId,
          'processIdentity': record.processIdentity.toJson(),
          ...payload,
        },
        expectedGrantDigest: grantDigest);
  }

  @override
  Future<void> input(
    String sessionId,
    List<int> bytes, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    if (bytes.length > 1024 * 1024) throw StateError('pty_input_too_large');
    await _sessionOperation(
      sessionId,
      'pty.input',
      <String, Object?>{'dataBase64': base64Encode(bytes)},
      binding: binding,
      grantDigest: grantDigest,
    );
  }

  @override
  Future<void> resize(
    String sessionId,
    int columns,
    int rows, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    if (columns < 20 || columns > 1000 || rows < 5 || rows > 500) {
      throw StateError('invalid_terminal_size');
    }
    await _sessionOperation(
      sessionId,
      'pty.resize',
      <String, Object?>{'columns': columns, 'rows': rows},
      binding: binding,
      grantDigest: grantDigest,
    );
  }

  @override
  Future<void> detach(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    await _sessionOperation(
      sessionId,
      'pty.detach',
      const <String, Object?>{},
      binding: binding,
      grantDigest: grantDigest,
    );
  }

  @override
  Future<P2PtySession> attach(
    String sessionId,
    int fromCursor, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    final record = _session(sessionId, binding, grantDigest);
    final response = await _sessionOperation(
      sessionId,
      'pty.attach',
      <String, Object?>{'fromCursor': fromCursor},
      binding: binding,
      grantDigest: grantDigest,
    );
    return _fromResponse(sessionId, response, record);
  }

  @override
  Future<void> interrupt(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    await _sessionOperation(
      sessionId,
      'pty.interrupt',
      const <String, Object?>{},
      binding: binding,
      grantDigest: grantDigest,
    );
  }

  @override
  Future<void> terminate(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    await _sessionOperation(
      sessionId,
      'pty.terminate',
      const <String, Object?>{},
      binding: binding,
      grantDigest: grantDigest,
    );
  }
}

class P2ProcessAuthorization {
  const P2ProcessAuthorization({
    required this.binding,
    required this.grantDigest,
  });

  final P2EffectBinding binding;
  final String grantDigest;
}

typedef P2ProcessAuthorizationResolver = P2ProcessAuthorization Function(
    int pid, String operation);

final class P2AutomationProcessTreeAdapter
    implements P2NativeProcessTreeAdapter {
  P2AutomationProcessTreeAdapter({
    required this.host,
    required this.authority,
    required this.authorizationFor,
    required this.journal,
  });

  final P2AutomationHostClient host;
  final P2AutomationEnvelopeAuthority authority;
  final P2ProcessAuthorizationResolver authorizationFor;
  final P2EffectJournal journal;
  final Map<int, P2EffectReceipt> _receipts = <int, P2EffectReceipt>{};

  P2EffectReceipt? receiptForPid(int pid) => _receipts[pid];

  Future<Map<String, Object?>> _invoke(
    int pid,
    String operation,
    Map<String, Object?> payload,
  ) async {
    final authorization = authorizationFor(pid, operation);
    final envelope = await authority.issue(
      binding: _operationBinding(authorization.binding, operation),
      operation: operation,
      payload: <String, Object?>{'operation': operation, ...payload},
      expectedGrantDigest: authorization.grantDigest,
    );
    final response = await host.invoke(envelope);
    final raw = response['receipt'];
    if (raw is! Map) throw StateError('process_effect_receipt_missing');
    final receipt = P2EffectReceipt.fromJson(Map<String, Object?>.from(raw));
    if (receipt.operation != operation) {
      throw StateError('process_effect_receipt_operation_mismatch');
    }
    await journal.append(receipt);
    _receipts[pid] = receipt;
    return response;
  }

  @override
  Future<P2ProcessLifecycle> inspect(P2ProcessIdentity identity) async {
    final response = await _invoke(
      identity.pid,
      'process.inspect',
      <String, Object?>{'processIdentity': identity.toJson()},
    );
    final state = response['lifecycle']?.toString() ?? 'unknown';
    return P2ProcessLifecycle.values.firstWhere(
      (P2ProcessLifecycle value) => value.name == state,
      orElse: () => P2ProcessLifecycle.unknown,
    );
  }

  @override
  Future<void> requestStop(P2ProcessIdentity identity, Duration grace) async {
    final response = await _invoke(
      identity.pid,
      'process.stop',
      <String, Object?>{
        'processIdentity': identity.toJson(),
        'graceMs': grace.inMilliseconds,
      },
    );
    if (response['status'] != 'ok') throw StateError('process_stop_failed');
  }

  @override
  Future<void> forceKill(P2ProcessIdentity identity) async {
    final response = await _invoke(
      identity.pid,
      'process.kill',
      <String, Object?>{'processIdentity': identity.toJson()},
    );
    if (response['status'] != 'ok') throw StateError('process_kill_failed');
  }
}

class P2WatchdogAuthorization {
  const P2WatchdogAuthorization({
    required this.binding,
    required this.grantDigest,
    required this.sessionId,
    required this.processIdentity,
  });

  final P2EffectBinding binding;
  final String grantDigest;
  final String sessionId;
  final P2ProcessIdentity processIdentity;
}

typedef P2WatchdogAuthorizationResolver = P2WatchdogAuthorization Function(
    String watchdogId, String operation);

final class P2AutomationWatchdogTransport implements P2WatchdogTransport {
  P2AutomationWatchdogTransport({
    required this.client,
    required this.authority,
    required this.authorizationFor,
    required this.journal,
  });

  final P2AutomationHostClient client;
  final P2AutomationEnvelopeAuthority authority;
  final P2WatchdogAuthorizationResolver authorizationFor;
  final P2EffectJournal journal;
  final Map<String, P2EffectReceipt> _receipts = <String, P2EffectReceipt>{};

  P2EffectReceipt? receiptFor(String watchdogId) => _receipts[watchdogId];

  Future<Map<String, Object?>> _invoke(
    String id,
    String operation,
    Map<String, Object?> payload,
  ) async {
    final authorization = authorizationFor(id, operation);
    final envelope = await authority.issue(
      binding: _operationBinding(authorization.binding, operation),
      operation: operation,
      payload: <String, Object?>{
        'operation': operation,
        'watchdogId': id,
        'sessionId': authorization.sessionId,
        'processIdentity': authorization.processIdentity.toJson(),
        ...payload,
      },
      expectedGrantDigest: authorization.grantDigest,
    );
    final response = await client.invoke(envelope);
    final raw = response['receipt'];
    if (raw is! Map) throw StateError('watchdog_effect_receipt_missing');
    final receipt = P2EffectReceipt.fromJson(Map<String, Object?>.from(raw));
    if (receipt.operation != operation) {
      throw StateError('watchdog_effect_receipt_operation_mismatch');
    }
    await journal.append(receipt);
    _receipts[id] = receipt;
    return response;
  }

  @override
  Future<void> arm({
    required String watchdogId,
    required Duration heartbeatTimeout,
  }) async {
    final response = await _invoke(
      watchdogId,
      'watchdog.arm',
      <String, Object?>{'timeoutMs': heartbeatTimeout.inMilliseconds},
    );
    if (response['status'] != 'ok') throw StateError('watchdog_arm_failed');
  }

  @override
  Future<void> heartbeat(String watchdogId) async {
    final response = await _invoke(
      watchdogId,
      'watchdog.heartbeat',
      const <String, Object?>{},
    );
    if (response['status'] != 'ok') {
      throw StateError('watchdog_heartbeat_failed');
    }
  }

  @override
  Future<void> killAll(String watchdogId) async {
    final response = await _invoke(
      watchdogId,
      'watchdog.kill',
      const <String, Object?>{},
    );
    if (response['status'] != 'ok') throw StateError('watchdog_kill_failed');
  }

  @override
  Stream<Map<String, Object?>> events(String watchdogId) =>
      client.events.where((Map<String, Object?> event) {
        return event['watchdogId'] == watchdogId;
      });
}

/// Production composition root. P1 implementations provide protected bootstrap
/// material and envelope issuance; P2 supplies only supervised execution.
final class P2OwnerRuntimeComposition {
  P2OwnerRuntimeComposition._({
    required this.client,
    required this.ptyBackend,
    required this.processTreeAdapter,
    required this.watchdogTransport,
    required this.commandService,
    required this.hostOperations,
    required this.filesystemAuthorizer,
    required this.hostOperationAuthorizer,
    required this.journal,
  });

  final P2ProcessAutomationHostClient client;
  final P2AutomationPtyBackend ptyBackend;
  final P2AutomationProcessTreeAdapter processTreeAdapter;
  final P2AutomationWatchdogTransport watchdogTransport;
  final P2AutomationFiniteCommandService commandService;
  final P2AutomationHostOperations hostOperations;
  final P2DesktopFilesystemAuthorizer filesystemAuthorizer;
  final P2DesktopHostOperationAuthorizer hostOperationAuthorizer;
  final P2EffectJournal journal;

  P2FilesystemService filesystemService(Directory backupRoot) =>
      P2FilesystemService(
        authorizer: filesystemAuthorizer,
        journal: journal,
        backupRoot: backupRoot,
      );

  P2SnapshotUndoService snapshotUndoService(Directory snapshotRoot) =>
      P2SnapshotUndoService(
        snapshotRoot,
        authorizer: hostOperationAuthorizer,
        journal: journal,
      );

  static Future<P2OwnerRuntimeComposition> start({
    required P2AutomationHostLaunchConfig launchConfig,
    required P2AutomationEnvelopeAuthority authority,
    required P2EffectJournal journal,
    required P2HostBindingProvider hostBindingProvider,
    required P2ProcessAuthorizationResolver processAuthorizationFor,
    required P2WatchdogAuthorizationResolver watchdogAuthorizationFor,
    P2PtySessionOpened? onPtySessionOpened,
  }) async {
    final client = await P2ProcessAutomationHostClient.start(launchConfig);
    final supervised = P2SupervisedAutomationHost(client);
    return P2OwnerRuntimeComposition._(
      client: client,
      ptyBackend: P2AutomationPtyBackend(
        client: client,
        authority: authority,
        journal: journal,
        onSessionOpened: onPtySessionOpened,
      ),
      processTreeAdapter: P2AutomationProcessTreeAdapter(
        host: client,
        authority: authority,
        authorizationFor: processAuthorizationFor,
        journal: journal,
      ),
      watchdogTransport: P2AutomationWatchdogTransport(
        client: client,
        authority: authority,
        authorizationFor: watchdogAuthorizationFor,
        journal: journal,
      ),
      commandService: P2AutomationFiniteCommandService(
        host: client,
        authority: authority,
        journal: journal,
      ),
      hostOperations: P2AutomationHostOperations(
        host: supervised,
        authority: authority,
        journal: journal,
        bindingProvider: hostBindingProvider,
      ),
      filesystemAuthorizer: P2DesktopFilesystemAuthorizer(authority),
      hostOperationAuthorizer: P2DesktopHostOperationAuthorizer(authority),
      journal: journal,
    );
  }

  Future<void> close() => client.close();
}
