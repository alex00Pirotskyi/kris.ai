import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_bootstrap.dart';
import 'package:kristin_local_agent/product/p5_global_autonomy.dart';
import 'package:kristin_local_agent/product/ui.dart';

class _ShellAutonomyBinding extends P5GlobalAutonomyBinding {
  @override
  P5GlobalAutonomySnapshot snapshot = const P5GlobalAutonomySnapshot(
    profileLabel: 'project',
    modelLabel: 'local/test-model@sha256',
    activeRunCount: 1,
    ownerTerminalCount: 0,
    browserSessionCount: 0,
    supervisedProcessTreeCount: 0,
    takeoverLabel: 'Not globally bound',
    networkLabel: 'Not requested',
    canPause: true,
    canStop: true,
    canEmergencyKill: true,
  );

  @override
  Future<void> emergencyKill() async {}

  @override
  Future<void> pauseActiveRuns() async {}

  @override
  Future<void> refresh() async {}

  @override
  void registerBrowserEmergencyStop(Future<void> Function()? stop) {}

  @override
  Future<void> stopActiveRuns() async {}

  @override
  void updateBrowserSessionCount(int count) {}
}

void main() {
  testWidgets(
      'main shell exposes persistent autonomy, chat, experience, and Owner Mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ownerMode = P2ProductRuntimeOwnerModeHandle.blocked(
      'Bad state: merged_p1a_service_unavailable',
    );
    final autonomy = _ShellAutonomyBinding();
    addTearDown(autonomy.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: KristinMainShell(
          ownerMode: ownerMode,
          autonomyBinding: autonomy,
          chat: const Center(child: Text('Chat surface')),
        ),
      ),
    );

    expect(find.byKey(const Key('p5-global-autonomy-bar')), findsOneWidget);
    expect(find.byKey(const Key('p5-global-profile')), findsOneWidget);
    expect(find.text('Chat surface'), findsOneWidget);

    await tester.tap(find.text('Experience'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workspace-title')), findsOneWidget);
    expect(find.byKey(const Key('p5-global-autonomy-bar')), findsOneWidget);

    await tester.tap(find.text('Owner Mode'));
    await tester.pumpAndSettle();
    expect(find.text('Owner Mode is unavailable'), findsOneWidget);
    expect(find.byKey(const Key('p5-global-autonomy-bar')), findsOneWidget);
    expect(
      find.textContaining('Diagnostic: merged_p1a_service_unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state'), findsNothing);
  });
}
