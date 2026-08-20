import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_effect_boundary.dart';
import 'package:kristin_local_agent/product/p2_process_tree.dart';
import 'package:kristin_local_agent/product/p2_pty_service.dart';
import 'package:kristin_local_agent/product/p2_terminal_model.dart';

void main() {
  test('process identity resists pid-only reuse', () {
    const first = P2ProcessIdentity(
      pid: 4,
      startToken: 'one',
      supervisorToken: 'supervisor',
      platformGroupId: '4',
    );
    const second = P2ProcessIdentity(
      pid: 4,
      startToken: 'two',
      supervisorToken: 'supervisor',
      platformGroupId: '4',
    );
    expect(first.startToken, isNot(second.startToken));
  });

  test('terminal model exposes keyboard and emergency workflows', () {
    final model = P2TerminalModel();
    expect(model.shortcuts[P2TerminalAction.sendInterrupt], 'Ctrl+C');
    expect(model.shortcuts.containsKey(P2TerminalAction.attach), isTrue);
    expect(model.shortcuts.containsKey(P2TerminalAction.emergencyKill), isTrue);
  });

  test('interactive PTY service exposes the complete managed lifecycle',
      () async {
    final backend = _RecordingPtyBackend();
    final service = P2InteractivePtyService(backend);
    final binding = _binding('pty.open');
    final grantDigest = 'a' * 64;

    final opened = await service.open(
      const P2PtyOpenRequest(shell: 'bash', cwd: '/workspace'),
      binding,
      grantDigest,
    );
    expect(opened.sessionId, 'session-1');

    await service.input(
      'session-1',
      <int>[65, 10],
      binding: binding,
      grantDigest: grantDigest,
    );
    final output = await service
        .output(
          'session-1',
          0,
          binding: binding,
          grantDigest: grantDigest,
        )
        .single;
    expect(output, <int>[79, 75]);
    await service.resize(
      'session-1',
      132,
      44,
      binding: binding,
      grantDigest: grantDigest,
    );
    await service.detach(
      'session-1',
      binding: binding,
      grantDigest: grantDigest,
    );
    final attached = await service.attach(
      'session-1',
      2,
      binding: binding,
      grantDigest: grantDigest,
    );
    expect(attached.transcriptCursor, 2);
    await service.interrupt(
      'session-1',
      binding: binding,
      grantDigest: grantDigest,
    );
    await service.terminate(
      'session-1',
      binding: binding,
      grantDigest: grantDigest,
    );

    expect(backend.calls, <String>[
      'open',
      'input:2',
      'output:0',
      'resize:132x44',
      'detach',
      'attach:2',
      'interrupt',
      'terminate',
    ]);
    expect(
      () => service.output(
        'session-1',
        -1,
        binding: binding,
        grantDigest: grantDigest,
      ),
      throwsStateError,
    );
    expect(
      () => service.resize(
        'session-1',
        10,
        1,
        binding: binding,
        grantDigest: grantDigest,
      ),
      throwsStateError,
    );
    expect(
      () => service.input(
        'session-1',
        <int>[256],
        binding: binding,
        grantDigest: grantDigest,
      ),
      throwsStateError,
    );
  });
}

P2EffectBinding _binding(String operation) => P2EffectBinding(
      runId: 'run',
      taskId: 'P2-005',
      actorId: 'owner_executor',
      toolId: 'terminal',
      accessProfileId: 'owner',
      capabilityId: 'pty',
      operation: operation,
    );

final class _RecordingPtyBackend implements P2PtyBackend {
  final List<String> calls = <String>[];

  P2PtySession session({int cursor = 0}) => P2PtySession(
        sessionId: 'session-1',
        runId: 'run',
        taskId: 'P2-005',
        actorId: 'owner_executor',
        grantDigest: 'a' * 64,
        processIdentity: const P2ProcessIdentity(
          pid: 1234,
          startToken: 'start',
          supervisorToken: 'supervisor',
          platformGroupId: '1234',
        ),
        state: P2PtyState.attached,
        transcriptCursor: cursor,
      );

  @override
  Future<P2PtySession> open(
    P2PtyOpenRequest request,
    P2EffectBinding binding,
    String grantDigest,
  ) async {
    calls.add('open');
    return session();
  }

  @override
  Stream<List<int>> output(
    String sessionId,
    int fromCursor, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) {
    calls.add('output:$fromCursor');
    return Stream<List<int>>.value(<int>[79, 75]);
  }

  @override
  Future<void> input(
    String sessionId,
    List<int> bytes, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    calls.add('input:${bytes.length}');
  }

  @override
  Future<void> resize(
    String sessionId,
    int columns,
    int rows, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    calls.add('resize:${columns}x$rows');
  }

  @override
  Future<void> detach(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    calls.add('detach');
  }

  @override
  Future<P2PtySession> attach(
    String sessionId,
    int fromCursor, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    calls.add('attach:$fromCursor');
    return session(cursor: fromCursor);
  }

  @override
  Future<void> interrupt(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    calls.add('interrupt');
  }

  @override
  Future<void> terminate(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    calls.add('terminate');
  }
}
