import 'dart:async';

import 'p2_effect_boundary.dart';
import 'p2_process_tree.dart';

enum P2PtyState {
  opening,
  attached,
  detached,
  reconnecting,
  exited,
  killed,
  unknown,
  unsupported,
}

class P2PtyOpenRequest {
  const P2PtyOpenRequest({
    required this.shell,
    required this.cwd,
    this.arguments = const <String>[],
    this.environmentDelta = const <String, String?>{},
    this.columns = 120,
    this.rows = 40,
    this.transcriptBudgetBytes = 4 * 1024 * 1024,
  });

  final String shell;
  final String cwd;
  final List<String> arguments;
  final Map<String, String?> environmentDelta;
  final int columns;
  final int rows;
  final int transcriptBudgetBytes;

  void validate() {
    if (shell.trim().isEmpty) throw StateError('shell_required');
    if (cwd.trim().isEmpty) throw StateError('cwd_required');
    if (columns < 20 || columns > 1000 || rows < 5 || rows > 500) {
      throw StateError('invalid_terminal_size');
    }
    if (transcriptBudgetBytes < 4096 ||
        transcriptBudgetBytes > 64 * 1024 * 1024) {
      throw StateError('invalid_transcript_budget');
    }
    if (environmentDelta.length > 128) {
      throw StateError('environment_quota_exceeded');
    }
  }
}

class P2PtySession {
  const P2PtySession({
    required this.sessionId,
    required this.runId,
    required this.taskId,
    required this.actorId,
    required this.grantDigest,
    required this.processIdentity,
    required this.state,
    required this.transcriptCursor,
  });

  final String sessionId;
  final String runId;
  final String taskId;
  final String actorId;
  final String grantDigest;
  final P2ProcessIdentity processIdentity;
  final P2PtyState state;
  final int transcriptCursor;
}

abstract interface class P2PtyBackend {
  Stream<List<int>> output(
    String sessionId,
    int fromCursor, {
    required P2EffectBinding binding,
    required String grantDigest,
  });
  Future<P2PtySession> open(
    P2PtyOpenRequest request,
    P2EffectBinding binding,
    String grantDigest,
  );
  Future<void> input(
    String sessionId,
    List<int> bytes, {
    required P2EffectBinding binding,
    required String grantDigest,
  });
  Future<void> resize(
    String sessionId,
    int columns,
    int rows, {
    required P2EffectBinding binding,
    required String grantDigest,
  });
  Future<void> detach(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  });
  Future<P2PtySession> attach(
    String sessionId,
    int fromCursor, {
    required P2EffectBinding binding,
    required String grantDigest,
  });
  Future<void> interrupt(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  });
  Future<void> terminate(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  });
}

class P2InteractivePtyService {
  P2InteractivePtyService(this.backend);

  static const int maxInputBytes = 1024 * 1024;

  final P2PtyBackend backend;

  void _validateSessionId(String sessionId) {
    if (sessionId.trim().isEmpty || sessionId.length > 256) {
      throw StateError('invalid_pty_session_id');
    }
  }

  void _validateCursor(int cursor) {
    if (cursor < 0) throw StateError('invalid_pty_transcript_cursor');
  }

  void _validateTerminalSize(int columns, int rows) {
    if (columns < 20 || columns > 1000 || rows < 5 || rows > 500) {
      throw StateError('invalid_terminal_size');
    }
  }

  Future<P2PtySession> open(
    P2PtyOpenRequest request,
    P2EffectBinding binding,
    String grantDigest,
  ) {
    request.validate();
    return backend.open(request, binding, grantDigest);
  }

  Stream<List<int>> output(
    String sessionId,
    int fromCursor, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) {
    _validateSessionId(sessionId);
    _validateCursor(fromCursor);
    return backend.output(
      sessionId,
      fromCursor,
      binding: binding,
      grantDigest: grantDigest,
    );
  }

  Future<void> input(
    String sessionId,
    List<int> bytes, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) {
    _validateSessionId(sessionId);
    if (bytes.length > maxInputBytes) throw StateError('pty_input_too_large');
    if (bytes.any((int value) => value < 0 || value > 255)) {
      throw StateError('pty_input_byte_invalid');
    }
    return backend.input(
      sessionId,
      List<int>.unmodifiable(bytes),
      binding: binding,
      grantDigest: grantDigest,
    );
  }

  Future<void> resize(
    String sessionId,
    int columns,
    int rows, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) {
    _validateSessionId(sessionId);
    _validateTerminalSize(columns, rows);
    return backend.resize(
      sessionId,
      columns,
      rows,
      binding: binding,
      grantDigest: grantDigest,
    );
  }

  Future<void> detach(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) {
    _validateSessionId(sessionId);
    return backend.detach(
      sessionId,
      binding: binding,
      grantDigest: grantDigest,
    );
  }

  Future<P2PtySession> attach(
    String sessionId,
    int cursor, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) {
    _validateSessionId(sessionId);
    _validateCursor(cursor);
    return backend.attach(
      sessionId,
      cursor,
      binding: binding,
      grantDigest: grantDigest,
    );
  }

  Future<P2PtySession> reconnect(
    String sessionId,
    int cursor, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) =>
      attach(
        sessionId,
        cursor,
        binding: binding,
        grantDigest: grantDigest,
      );

  Future<void> interrupt(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) {
    _validateSessionId(sessionId);
    return backend.interrupt(
      sessionId,
      binding: binding,
      grantDigest: grantDigest,
    );
  }

  Future<void> terminate(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) {
    _validateSessionId(sessionId);
    return backend.terminate(
      sessionId,
      binding: binding,
      grantDigest: grantDigest,
    );
  }
}
