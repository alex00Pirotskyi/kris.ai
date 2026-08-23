import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/p5_global_autonomy.dart';

class _FakeRunPort implements P5GlobalAutonomyRunPort {
  _FakeRunPort(this.sessions);

  final List<P5GlobalAutonomyRunSession> sessions;
  final List<String> paused = <String>[];
  final List<String> cancelled = <String>[];

  @override
  Future<void> cancel(String runId) async {
    cancelled.add(runId);
    _replaceState(runId, RunState.cancelling);
  }

  @override
  Future<List<P5GlobalAutonomyRunSession>> listSessions() async =>
      List<P5GlobalAutonomyRunSession>.of(sessions);

  @override
  Future<void> pause(String runId) async {
    paused.add(runId);
    _replaceState(runId, RunState.paused);
  }

  void _replaceState(String id, RunState state) {
    final index = sessions.indexWhere((session) => session.id == id);
    final current = sessions[index];
    sessions[index] = P5GlobalAutonomyRunSession(
      id: current.id,
      state: state,
      modelLabel: current.modelLabel,
      networkRequested: current.networkRequested,
    );
  }
}

class _FakeOwnerPort implements P5GlobalAutonomyOwnerPort {
  _FakeOwnerPort(this.value);

  P5GlobalAutonomyOwnerSnapshot value;
  int emergencyCalls = 0;

  @override
  Future<void> emergencyKillAll() async {
    emergencyCalls++;
    value = P5GlobalAutonomyOwnerSnapshot(
      profileId: value.profileId,
      ownerAvailable: value.ownerAvailable,
      ownerEnabled: value.ownerEnabled,
      terminalCount: value.terminalCount,
      supervisedProcessTreeCount: 0,
    );
  }

  @override
  P5GlobalAutonomyOwnerSnapshot snapshot() => value;
}

P5GlobalAutonomyRunSession session(
  String id,
  RunState state, {
  bool network = false,
}) =>
    P5GlobalAutonomyRunSession(
      id: id,
      state: state,
      modelLabel: 'ollama/test-model@digest',
      networkRequested: network,
    );

void main() {
  test('P5-005 controller reports real port state and delegates controls',
      () async {
    final runs = _FakeRunPort(<P5GlobalAutonomyRunSession>[
      session('run-a', RunState.running, network: true),
      session('run-b', RunState.paused),
      session('run-c', RunState.queued),
      session('run-d', RunState.succeeded),
    ]);
    final owner = _FakeOwnerPort(
      const P5GlobalAutonomyOwnerSnapshot(
        profileId: 'owner',
        ownerAvailable: true,
        ownerEnabled: true,
        terminalCount: 1,
        supervisedProcessTreeCount: 1,
      ),
    );
    final controller = P5GlobalAutonomyController(
      runPort: runs,
      ownerPort: owner,
      refreshInterval: null,
    );
    addTearDown(controller.dispose);
    var browserStops = 0;
    controller.registerBrowserEmergencyStop(() async => browserStops++);
    controller.updateBrowserSessionCount(2);
    await controller.refresh();

    expect(controller.snapshot.profileLabel, 'owner');
    expect(controller.snapshot.modelLabel, 'ollama/test-model@digest');
    expect(controller.snapshot.activeRunCount, 3);
    expect(controller.snapshot.activeSessionCount, 6);
    expect(controller.snapshot.networkLabel, 'Owner policy');
    expect(controller.snapshot.takeoverLabel, 'Not globally bound');
    expect(controller.snapshot.canPause, isTrue);
    expect(controller.snapshot.canStop, isTrue);
    expect(controller.snapshot.canEmergencyKill, isTrue);

    await controller.pauseActiveRuns();
    expect(runs.paused, <String>['run-a']);

    await controller.stopActiveRuns();
    expect(runs.cancelled.toSet(), <String>{'run-a', 'run-b', 'run-c'});

    await controller.emergencyKill();
    expect(browserStops, 1);
    expect(owner.emergencyCalls, 1);
  });

  testWidgets('P5-005 bar exposes status and real action bindings',
      (tester) async {
    final runs = _FakeRunPort(<P5GlobalAutonomyRunSession>[
      session('run-a', RunState.running),
    ]);
    final owner = _FakeOwnerPort(
      const P5GlobalAutonomyOwnerSnapshot(
        profileId: 'chat',
        ownerAvailable: true,
        ownerEnabled: false,
        terminalCount: 0,
        supervisedProcessTreeCount: 0,
      ),
    );
    final controller = P5GlobalAutonomyController(
      runPort: runs,
      ownerPort: owner,
      refreshInterval: null,
    );
    addTearDown(controller.dispose);
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: P5GlobalAutonomyBar(binding: controller),
        ),
      ),
    );

    expect(find.byKey(const Key('p5-global-profile')), findsOneWidget);
    expect(find.byKey(const Key('p5-global-model')), findsOneWidget);
    expect(
      find.text('Running model: ollama/test-model@digest'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('p5-global-sessions')), findsOneWidget);
    expect(find.byKey(const Key('p5-global-takeover')), findsOneWidget);
    expect(find.byKey(const Key('p5-global-network')), findsOneWidget);

    await tester.tap(find.byKey(const Key('p5-global-pause')));
    await tester.pumpAndSettle();
    expect(runs.paused, <String>['run-a']);

    await tester.tap(find.byKey(const Key('p5-global-stop')));
    await tester.pumpAndSettle();
    expect(runs.cancelled, <String>['run-a']);
  });
}
