import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';

Future<void> pumpPrototype(
    WidgetTester tester, P5InformationArchitectureController controller) async {
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
  });

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

  testWidgets('plan-only control is disabled after a run starts', (tester) async {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);

    CheckboxListTile planOnlyTile() =>
        tester.widget<CheckboxListTile>(find.byKey(const Key('plan-only-toggle')));

    expect(planOnlyTile().onChanged, isNotNull);
    await tapKey(tester, const Key('review-plan-button'));
    await tapKey(tester, const Key('start-run-button'));

    expect(controller.state.runState, P5RunPresentationState.running);
    expect(planOnlyTile().onChanged, isNull);
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

  testWidgets('Owner Mode remains presentation-only', (tester) async {
    final controller = P5InformationArchitectureController()
      ..selectWorkspace(P5WorkspaceId.ownerMode);
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);
    expect(find.textContaining('BLOCKED_EXTERNAL'), findsOneWidget);
    await tapKey(tester, const Key('owner-preview-running'));
    expect(
        controller.state.ownerModeState, P5OwnerModePresentationState.running);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('Web Studio unavailable state has an exit', (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.capabilitiesIntegrations);
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);
    await tapKey(tester, const Key('capability-webStudio'));
    expect(find.text('BLOCKED_BY_DEPENDENCY'), findsOneWidget);
    await tester.tap(find.text('Back to Capabilities'));
    await tester.pumpAndSettle();
    expect(controller.state.workspace, P5WorkspaceId.capabilitiesIntegrations);
    expect(controller.sideEffects.isZero, isTrue);
  });
}
