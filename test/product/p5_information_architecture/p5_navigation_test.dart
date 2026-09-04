import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';

Future<void> pumpPrototype(
  WidgetTester tester,
  P5InformationArchitectureController controller,
) async {
  tester.view.physicalSize = const Size(1440, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(P5InformationArchitectureApp(controller: controller));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('all required workspaces are reachable', (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced);
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);
    for (final definition in controller.visibleWorkspaces) {
      await tapKey(tester, Key('workspace-nav-${definition.id.name}'));
      expect(controller.state.workspace, definition.id);
    }
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('advanced Experience exposes Web Studio honestly', (
    tester,
  ) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.webStudio);
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);

    expect(controller.state.workspace, P5WorkspaceId.webStudio);
    expect(find.byKey(const Key('web-studio-runtime-card')), findsOneWidget);
    expect(find.byKey(const Key('web-browser-start-stop')), findsOneWidget);
    expect(find.textContaining('P3 p3_runtime_not_bound'), findsOneWidget);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets(
    'simple task cannot bypass advanced evidence and can open verification',
    (tester) async {
      final controller = P5InformationArchitectureController();
      addTearDown(controller.dispose);
      await pumpPrototype(tester, controller);
      await tapKey(tester, const Key('review-plan-button'));
      await tapKey(tester, const Key('start-run-button'));
      await tapKey(tester, const Key('pause-run-button'));
      await tapKey(tester, const Key('resume-run-button'));
      await tapKey(tester, const Key('complete-run-button'));
      await tapKey(tester, const Key('open-evidence-button'));

      expect(controller.state.workspace, P5WorkspaceId.homeChat);
      expect(controller.state.recoveryMessage, contains('Advanced mode'));

      await tapKey(tester, const Key('run-verification-button'));
      expect(controller.state.workspace, P5WorkspaceId.verificationCenter);
      expect(controller.state.verificationRequested, isTrue);
      expect(controller.sideEffects.isZero, isTrue);
    },
  );

  testWidgets('advanced task can open evidence', (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced);
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);

    await tapKey(tester, const Key('review-plan-button'));
    await tapKey(tester, const Key('start-run-button'));
    await tapKey(tester, const Key('complete-run-button'));
    await tapKey(tester, const Key('open-evidence-button'));

    expect(controller.state.workspace, P5WorkspaceId.evidence);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('plan-only control is disabled after a run starts', (
    tester,
  ) async {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);

    CheckboxListTile planOnlyTile() => tester.widget<CheckboxListTile>(
      find.byKey(const Key('plan-only-toggle')),
    );

    expect(planOnlyTile().onChanged, isNotNull);
    await tapKey(tester, const Key('review-plan-button'));
    await tapKey(tester, const Key('start-run-button'));

    expect(controller.state.runState, P5RunPresentationState.running);
    expect(planOnlyTile().onChanged, isNull);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('plan and start controls cannot replace an active run', (
    tester,
  ) async {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);

    await tapKey(tester, const Key('review-plan-button'));
    await tapKey(tester, const Key('start-run-button'));

    FilledButton reviewButton() => tester.widget<FilledButton>(
      find.byKey(const Key('review-plan-button')),
    );
    OutlinedButton startButton() => tester.widget<OutlinedButton>(
      find.byKey(const Key('start-run-button')),
    );

    expect(controller.state.runState, P5RunPresentationState.running);
    expect(reviewButton().onPressed, isNull);
    expect(startButton().onPressed, isNull);

    await tapKey(tester, const Key('pause-run-button'));
    expect(controller.state.runState, P5RunPresentationState.paused);
    expect(reviewButton().onPressed, isNull);
    expect(startButton().onPressed, isNull);

    await tapKey(tester, const Key('resume-run-button'));
    await tapKey(tester, const Key('complete-run-button'));
    expect(controller.state.runState, P5RunPresentationState.completed);
    expect(reviewButton().onPressed, isNotNull);
    expect(startButton().onPressed, isNull);

    await tapKey(tester, const Key('review-plan-button'));
    expect(controller.state.selectedRunId, isNull);
    expect(controller.state.runState, P5RunPresentationState.ready);
    expect(startButton().onPressed, isNotNull);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('current simulated run does not fabricate a saved timeline', (
    tester,
  ) async {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);

    await tapKey(tester, const Key('review-plan-button'));
    await tapKey(tester, const Key('start-run-button'));
    controller.selectWorkspace(P5WorkspaceId.runsActivity);
    await tester.pumpAndSettle();

    expect(controller.state.selectedRunId, 'run.p5-simulated-current');
    expect(find.byKey(const Key('current-run-detail')), findsOneWidget);
    expect(find.byKey(const Key('selected-run-detail')), findsNothing);
    expect(find.text('Saved run timeline'), findsNothing);
    expect(find.text('Current simulated run'), findsOneWidget);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('saved run detail exposes resume only for interrupted fixture', (
    tester,
  ) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.runsActivity);
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);

    await tapKey(tester, const Key('run-run.p5-complete-001'));
    expect(controller.state.runState, P5RunPresentationState.completed);
    expect(find.byKey(const Key('selected-run-detail')), findsOneWidget);
    expect(find.byKey(const Key('resume-existing-run-button')), findsNothing);
    expect(find.text('Saved run timeline'), findsNothing);

    await tapKey(tester, const Key('run-run.p5-existing-001'));
    expect(controller.state.runState, P5RunPresentationState.interrupted);
    expect(find.byKey(const Key('resume-existing-run-button')), findsOneWidget);

    await tapKey(tester, const Key('resume-existing-run-button'));
    expect(controller.state.runState, P5RunPresentationState.running);
    expect(find.byKey(const Key('resume-existing-run-button')), findsNothing);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('existing run retains project and run context', (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.runsActivity);
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);
    await tapKey(tester, const Key('run-run.p5-existing-001'));
    final project = controller.state.selectedProjectId;
    final run = controller.state.selectedRunId;
    await tapKey(tester, const Key('existing-run-evidence-button'));
    expect(controller.state.workspace, P5WorkspaceId.evidence);
    expect(controller.state.selectedProjectId, project);
    expect(controller.state.selectedRunId, run);
    controller.back();
    expect(controller.state.workspace, P5WorkspaceId.runsActivity);
  });

  testWidgets(
    'interrupted-run recovery restores the deterministic saved fixture',
    (tester) async {
      final controller = P5InformationArchitectureController()
        ..selectWorkspace(P5WorkspaceId.settingsDiagnostics);
      addTearDown(controller.dispose);
      await pumpPrototype(tester, controller);

      expect(controller.state.runState, P5RunPresentationState.planReady);
      expect(controller.state.selectedRunId, isNull);

      final recovery = find.text('Resume the saved run');
      await tester.ensureVisible(recovery);
      await tester.tap(recovery);
      await tester.pumpAndSettle();

      expect(controller.state.selectedProjectId, 'project.kristin-local');
      expect(controller.state.selectedRunId, 'run.p5-existing-001');
      expect(controller.state.runState, P5RunPresentationState.running);
      expect(
        controller.state.recoveryMessage,
        'Interrupted run restored from the saved fixture.',
      );
      expect(controller.sideEffects.isZero, isTrue);
    },
  );

  testWidgets('advanced recovery destinations require explicit disclosure', (
    tester,
  ) async {
    final controller = P5InformationArchitectureController()
      ..selectWorkspace(P5WorkspaceId.settingsDiagnostics);
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);

    final modelsRecovery = find.text('Open Models and Providers');
    await tester.ensureVisible(modelsRecovery);
    await tester.tap(modelsRecovery);
    await tester.pumpAndSettle();

    expect(controller.state.experienceLevel, P5ExperienceLevel.simple);
    expect(controller.state.workspace, P5WorkspaceId.settingsDiagnostics);
    expect(controller.state.recoveryMessage, contains('Advanced mode'));

    controller.changeExperienceLevel(P5ExperienceLevel.advanced);
    await tester.pumpAndSettle();
    await tester.tap(modelsRecovery);
    await tester.pumpAndSettle();
    expect(controller.state.workspace, P5WorkspaceId.modelsProviders);

    controller.changeExperienceLevel(P5ExperienceLevel.simple);
    controller.selectWorkspace(P5WorkspaceId.settingsDiagnostics);
    await tester.pumpAndSettle();
    final capabilityRecovery = find.text('Open capability requirements');
    await tester.ensureVisible(capabilityRecovery);
    await tester.tap(capabilityRecovery);
    await tester.pumpAndSettle();

    expect(controller.state.experienceLevel, P5ExperienceLevel.simple);
    expect(controller.state.workspace, P5WorkspaceId.settingsDiagnostics);
    expect(controller.state.recoveryMessage, contains('Advanced mode'));

    controller.changeExperienceLevel(P5ExperienceLevel.advanced);
    await tester.pumpAndSettle();
    await tester.tap(capabilityRecovery);
    await tester.pumpAndSettle();
    expect(controller.state.workspace, P5WorkspaceId.capabilitiesIntegrations);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('permission recovery is honest about later-task ownership', (
    tester,
  ) async {
    final controller = P5InformationArchitectureController()
      ..selectWorkspace(P5WorkspaceId.settingsDiagnostics);
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);

    final permissionRecovery = find.text('Review the requested access');
    await tester.ensureVisible(permissionRecovery);
    await tester.tap(permissionRecovery);
    await tester.pumpAndSettle();

    expect(controller.state.experienceLevel, P5ExperienceLevel.simple);
    expect(controller.state.workspace, P5WorkspaceId.settingsDiagnostics);
    expect(controller.state.recoveryMessage, contains('not implemented'));
    expect(controller.state.recoveryMessage, contains('P5-007'));
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets(
    'failing evidence uses the Evidence workspace without elevation',
    (tester) async {
      final controller = P5InformationArchitectureController()
        ..selectWorkspace(P5WorkspaceId.settingsDiagnostics);
      addTearDown(controller.dispose);
      await pumpPrototype(tester, controller);

      final failureCard = find.byKey(const Key('failure.test-fail'));
      await tester.scrollUntilVisible(
        failureCard,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      final evidenceRecovery = find.descendant(
        of: failureCard,
        matching: find.text('Open failing evidence'),
      );
      await tester.tap(evidenceRecovery);
      await tester.pumpAndSettle();

      expect(controller.state.experienceLevel, P5ExperienceLevel.simple);
      expect(controller.state.workspace, P5WorkspaceId.settingsDiagnostics);
      expect(controller.state.recoveryMessage, contains('Advanced mode'));

      controller.changeExperienceLevel(P5ExperienceLevel.advanced);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        failureCard,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(evidenceRecovery);
      await tester.pumpAndSettle();
      expect(controller.state.workspace, P5WorkspaceId.evidence);
      expect(controller.sideEffects.isZero, isTrue);
    },
  );

  testWidgets('Owner Mode remains presentation-only', (tester) async {
    final controller = P5InformationArchitectureController()
      ..selectWorkspace(P5WorkspaceId.ownerMode);
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);
    expect(find.textContaining('BLOCKED_EXTERNAL'), findsOneWidget);
    await tapKey(tester, const Key('owner-preview-running'));
    expect(
      controller.state.ownerModeState,
      P5OwnerModePresentationState.running,
    );
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('Web Studio opens from capabilities and has a navigation exit', (
    tester,
  ) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.capabilitiesIntegrations);
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);

    await tapKey(tester, const Key('capability-webStudio'));
    expect(controller.state.workspace, P5WorkspaceId.webStudio);
    expect(find.byKey(const Key('web-studio-runtime-card')), findsOneWidget);

    await tapKey(tester, const Key('history-back'));
    expect(controller.state.workspace, P5WorkspaceId.capabilitiesIntegrations);
    expect(controller.sideEffects.isZero, isTrue);
  });
}
