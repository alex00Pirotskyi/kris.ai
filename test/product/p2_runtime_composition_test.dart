import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_process_tree.dart';
import 'package:kristin_local_agent/product/p2_pty_service.dart';
import 'package:kristin_local_agent/product/p2_runtime_composition.dart';

import 'p2_test_support.dart';

void main() {
  test(
    'production PTY adapter binds every session action to exact grant',
    () async {
      final authority = TestEnvelopeAuthority();
      final journal = TestJournal();
      final client = TestAutomationHostClient((envelope) {
        if (envelope.operation == 'pty.open') {
          return <String, Object?>{
            'status': 'ok',
            'sessionId': 'session-1',
            'state': 'attached',
            'processIdentity': <String, Object?>{
              'pid': 101,
              'startToken': 'start-101',
              'supervisorToken': 'supervisor-101',
              'platformGroupId': 'group-101',
            },
            'receipt': testReceipt(envelope.binding, envelope.operation),
          };
        }
        if (envelope.operation == 'pty.attach') {
          return <String, Object?>{
            'status': 'ok',
            'sessionId': 'session-1',
            'state': 'attached',
            'nextCursor': 3,
            'dataBase64': base64Encode(<int>[1, 2, 3]),
            'receipt': testReceipt(envelope.binding, envelope.operation),
          };
        }
        return <String, Object?>{
          'status': 'ok',
          'sessionId': 'session-1',
          'receipt': testReceipt(envelope.binding, envelope.operation),
        };
      });
      final backend = P2AutomationPtyBackend(
        client: client,
        authority: authority,
        journal: journal,
      );
      const grantDigest =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final binding = testBinding('pty.open', taskId: 'P2-005');
      final session = await backend.open(
        const P2PtyOpenRequest(shell: '/bin/sh', cwd: '/tmp'),
        binding,
        grantDigest,
      );
      expect(session.sessionId, 'session-1');
      await backend.resize(
        session.sessionId,
        132,
        44,
        binding: binding,
        grantDigest: grantDigest,
      );
      final attached = await backend.attach(
        session.sessionId,
        0,
        binding: binding,
        grantDigest: grantDigest,
      );
      expect(attached.transcriptCursor, 3);
      expect(client.calls.map((item) => item.operation), <String>[
        'pty.open',
        'pty.resize',
        'pty.attach',
      ]);
      await expectLater(
        backend.resize(
          session.sessionId,
          100,
          30,
          binding: binding,
          grantDigest:
              'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        ),
        throwsStateError,
      );
      await client.close();
    },
  );

  test('process adapter accepts only host-issued managed identities', () async {
    final authority = TestEnvelopeAuthority();
    final journal = TestJournal();
    final client = TestAutomationHostClient(
      (envelope) => <String, Object?>{
        'status': 'ok',
        'lifecycle': envelope.operation == 'process.inspect'
            ? 'running'
            : envelope.operation == 'process.kill'
            ? 'killed'
            : 'stopping',
        'receipt': testReceipt(envelope.binding, envelope.operation),
      },
    );
    const identity = P2ProcessIdentity(
      pid: 303,
      startToken: 'start-303',
      supervisorToken: 'supervisor-303',
      platformGroupId: 'group-303',
    );
    final adapter = P2AutomationProcessTreeAdapter(
      host: client,
      authority: authority,
      journal: journal,
      authorizationFor: (pid, operation) => P2ProcessAuthorization(
        binding: testBinding(operation, taskId: 'P2-006'),
        grantDigest:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
    );

    expect(await adapter.inspect(identity), P2ProcessLifecycle.running);
    await adapter.requestStop(identity, const Duration(milliseconds: 250));
    await adapter.forceKill(identity);

    expect(client.calls.map((item) => item.operation), <String>[
      'process.inspect',
      'process.stop',
      'process.kill',
    ]);
    expect(
      client.calls.every(
        (item) => item.payload['processIdentity'].toString().isNotEmpty,
      ),
      isTrue,
    );
    expect(
      client.calls.any((item) => item.operation == 'process.register'),
      isFalse,
    );
    expect(journal.receipts, hasLength(3));
    await client.close();
  });

  test('watchdog transport uses authenticated composition boundary', () async {
    final authority = TestEnvelopeAuthority();
    final journal = TestJournal();
    final client = TestAutomationHostClient(
      (envelope) => <String, Object?>{
        'status': 'ok',
        'watchdogId': envelope.payload['watchdogId'],
        'receipt': testReceipt(
          envelope.binding,
          envelope.operation,
          reversibility: 'irreversible',
        ),
      },
    );
    final identity = const P2ProcessIdentity(
      pid: 202,
      startToken: 'start-202',
      supervisorToken: 'supervisor-202',
      platformGroupId: 'group-202',
    );
    final transport = P2AutomationWatchdogTransport(
      client: client,
      authority: authority,
      journal: journal,
      authorizationFor: (id, operation) => P2WatchdogAuthorization(
        binding: testBinding(operation, taskId: 'P2-011'),
        grantDigest:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        sessionId: 'session-202',
        processIdentity: identity,
      ),
    );
    await transport.arm(
      watchdogId: 'watchdog-202',
      heartbeatTimeout: const Duration(milliseconds: 500),
    );
    await transport.killAll('watchdog-202');
    expect(client.calls.map((item) => item.operation), <String>[
      'watchdog.arm',
      'watchdog.kill',
    ]);
    expect(client.calls.last.payload['processIdentity'], identity.toJson());
    expect(journal.receipts.length, 2);
    await client.close();
  });
}
