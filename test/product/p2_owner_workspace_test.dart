import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_effect_boundary.dart';
import 'package:kristin_local_agent/product/p2_emergency_watchdog.dart';
import 'package:kristin_local_agent/product/p2_owner_mode.dart';
import 'package:kristin_local_agent/product/p2_pty_service.dart';
import 'package:kristin_local_agent/product/p2_owner_workspace.dart';
import 'package:kristin_local_agent/product/p2_terminal_model.dart';

void main() {
  testWidgets('Owner onboarding never calls full access a sandbox', (
    tester,
  ) async {
    final controller = P2OwnerModeController((_) async {}, () async {});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: P2OwnerWorkspace(
            controller: controller,
            terminalModel: P2TerminalModel(),
            actions: _Actions(),
          ),
        ),
      ),
    );
    expect(find.textContaining('not containment or isolation'), findsOneWidget);
    expect(find.textContaining('full-current-account'), findsOneWidget);
  });

  testWidgets('terminal actions are wired to typed callbacks', (tester) async {
    final controller = P2OwnerModeController((_) async {}, () async {});
    await controller.enable(
      unattended: false,
      approvalPolicy: P2OwnerApprovalPolicy.everyHighRiskEffect,
      acknowledged: true,
    );
    final model = P2TerminalModel()
      ..add(
        const P2TerminalTab(
          id: 'session',
          title: 'Terminal',
          shell: 'shell',
          cwd: '/',
          runId: 'run',
          taskId: 'task',
          grantId: 'grant',
          attached: true,
          accessibilityLabel: 'terminal session',
        ),
      );
    final actions = _Actions();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: P2OwnerWorkspace(
            controller: controller,
            terminalModel: model,
            actions: actions,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Interrupt'));
    await tester.pump();
    expect(actions.interruptCount, 1);
    await tester.tap(find.text('Terminate tree'));
    await tester.pump();
    expect(actions.terminateCount, 1);
  });

  testWidgets('runtime terminal additions become visible and interactive', (
    tester,
  ) async {
    final controller = P2OwnerModeController((_) async {}, () async {});
    await controller.enable(
      unattended: false,
      approvalPolicy: P2OwnerApprovalPolicy.everyHighRiskEffect,
      acknowledged: true,
    );
    final model = P2TerminalModel();
    final actions = _Actions();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: P2OwnerWorkspace(
            controller: controller,
            terminalModel: model,
            actions: actions,
          ),
        ),
      ),
    );
    expect(find.text('No managed terminal session is active.'), findsOneWidget);

    model.add(
      const P2TerminalTab(
        id: 'live-session',
        title: 'Live terminal',
        shell: 'bash',
        cwd: '/workspace',
        runId: 'run-live',
        taskId: 'P2-012',
        grantId: 'grant-live',
        attached: true,
        accessibilityLabel: 'live owner terminal',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Live terminal'), findsWidgets);
    expect(actions.outputCursors['live-session'], 0);

    actions.emit('live-session', utf8.encode('hello λ\n'));
    await tester.pump();
    expect(find.textContaining('hello λ'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('owner-terminal-input')),
      'echo hello',
    );
    await tester.tap(find.byTooltip('Send terminal input'));
    await tester.pump();
    expect(actions.inputs, hasLength(1));
    expect(utf8.decode(actions.inputs.single.sublist(0, 10)), 'echo hello');
    expect(actions.inputs.single.last, 13);

    await tester.tap(find.text('Detach'));
    await tester.pump();
    expect(actions.detachCount, 1);
    expect(model.selected?.attached, false);

    await tester.tap(find.text('Attach'));
    await tester.pump();
    await tester.pump();
    expect(model.selected?.attached, true);
    expect(
      actions.outputCursors['live-session'],
      utf8.encode('hello λ\n').length,
    );
  });

  test('terminal model emits changes for runtime tab lifecycle', () {
    final model = P2TerminalModel();
    var notifications = 0;
    model.addListener(() => notifications++);
    model.add(
      const P2TerminalTab(
        id: 'one',
        title: 'One',
        shell: 'bash',
        cwd: '/',
        runId: 'run',
        taskId: 'task',
        grantId: 'grant',
        attached: true,
        accessibilityLabel: 'terminal one',
      ),
    );
    model.add(
      const P2TerminalTab(
        id: 'two',
        title: 'Two',
        shell: 'bash',
        cwd: '/',
        runId: 'run',
        taskId: 'task',
        grantId: 'grant',
        attached: false,
        accessibilityLabel: 'terminal two',
      ),
    );
    model.select('one');
    model.setAttached('one', false);
    model.remove('two');
    expect(notifications, 5);
    expect(model.selected?.id, 'one');
    expect(model.selected?.attached, false);
  });

  test(
    'service actions invoke PTY stream input detach clipboard transcript and watchdog',
    () async {
      final pty = _PtyBackend();
      final transport = _WatchdogTransport();
      final clipboard = <String>[];
      final saved = <List<int>>[];
      const tab = P2TerminalTab(
        id: 'session',
        title: 'Terminal',
        shell: 'shell',
        cwd: '/',
        runId: 'run',
        taskId: 'task',
        grantId: 'grant',
        attached: true,
        accessibilityLabel: 'terminal session',
      );
      final actions = P2OwnerWorkspaceServiceActions(
        ptyBackend: pty,
        emergencyController: P2EmergencyController(transport),
        watchdogId: 'watchdog',
        authorizationFor: (_, operation) => P2TerminalAuthorization(
          binding: P2EffectBinding(
            runId: 'run',
            taskId: 'task',
            actorId: 'actor',
            toolId: 'pty',
            accessProfileId: 'owner',
            capabilityId: 'terminal',
            operation: operation,
          ),
          grantDigest: 'grant',
        ),
        selectionBytes: (_) async => <int>[104, 105],
        transcriptBytes: (_) async => <int>[1, 2, 3],
        writeClipboardText: (text) async => clipboard.add(text),
        writeTranscriptFile: (_, bytes) async => saved.add(bytes),
      );
      expect(await actions.output(tab, 7).single, <int>[79, 75]);
      await actions.input(tab, <int>[65, 13]);
      await actions.detach(tab);
      await actions.copySelection(tab);
      await actions.saveTranscript(tab);
      await actions.interrupt(tab);
      await actions.terminateTree(tab);
      await actions.emergencyPauseAndKill();
      expect(pty.outputCursor, 7);
      expect(pty.inputBytes, <int>[65, 13]);
      expect(pty.detachCount, 1);
      expect(clipboard, <String>['hi']);
      expect(saved, <List<int>>[
        <int>[1, 2, 3],
      ]);
      expect(pty.interruptCount, 1);
      expect(pty.terminateCount, 1);
      expect(transport.killCount, 1);
    },
  );
}

class _Actions implements P2OwnerWorkspaceActions {
  int interruptCount = 0;
  int terminateCount = 0;
  int detachCount = 0;
  final List<List<int>> inputs = <List<int>>[];
  final Map<String, int> outputCursors = <String, int>{};
  final Map<String, StreamController<List<int>>> _streams =
      <String, StreamController<List<int>>>{};

  @override
  Stream<List<int>> output(P2TerminalTab tab, int fromCursor) {
    outputCursors[tab.id] = fromCursor;
    return _streams
        .putIfAbsent(tab.id, () => StreamController<List<int>>.broadcast())
        .stream;
  }

  void emit(String tabId, List<int> bytes) {
    _streams
        .putIfAbsent(tabId, () => StreamController<List<int>>.broadcast())
        .add(bytes);
  }

  @override
  Future<void> input(P2TerminalTab tab, List<int> bytes) async {
    inputs.add(List<int>.of(bytes));
  }

  @override
  Future<void> detach(P2TerminalTab tab) async {
    detachCount++;
  }

  @override
  Future<void> copySelection(P2TerminalTab tab) async {}

  @override
  Future<void> emergencyPauseAndKill() async {}

  @override
  Future<void> interrupt(P2TerminalTab tab) async => interruptCount++;

  @override
  Future<void> saveTranscript(P2TerminalTab tab) async {}

  @override
  Future<void> terminateTree(P2TerminalTab tab) async => terminateCount++;
}

class _PtyBackend implements P2PtyBackend {
  int interruptCount = 0;
  int terminateCount = 0;
  int detachCount = 0;
  int? outputCursor;
  List<int>? inputBytes;

  @override
  Future<P2PtySession> attach(
    String sessionId,
    int fromCursor, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> detach(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    detachCount++;
  }

  @override
  Future<void> input(
    String sessionId,
    List<int> bytes, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    inputBytes = List<int>.of(bytes);
  }

  @override
  Future<void> interrupt(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    interruptCount++;
  }

  @override
  Future<P2PtySession> open(
    P2PtyOpenRequest request,
    P2EffectBinding binding,
    String grantDigest,
  ) =>
      throw UnimplementedError();

  @override
  Stream<List<int>> output(
    String sessionId,
    int fromCursor, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) {
    outputCursor = fromCursor;
    return Stream<List<int>>.value(<int>[79, 75]);
  }

  @override
  Future<void> resize(
    String sessionId,
    int columns,
    int rows, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> terminate(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {
    terminateCount++;
  }
}

class _WatchdogTransport implements P2WatchdogTransport {
  int killCount = 0;

  @override
  Future<void> arm({
    required String watchdogId,
    required Duration heartbeatTimeout,
  }) async {}

  @override
  Stream<Map<String, Object?>> events(String watchdogId) =>
      const Stream<Map<String, Object?>>.empty();

  @override
  Future<void> heartbeat(String watchdogId) async {}

  @override
  Future<void> killAll(String watchdogId) async {
    killCount++;
  }
}
