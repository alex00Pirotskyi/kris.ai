import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';

void main() {
  test('invalid state transition is rejected', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    expect(
      () => controller.transitionWorkspaceState(
        P5WorkspaceId.webStudio,
        P5WorkspaceState.running,
      ),
      throwsA(isA<P5InvalidTransition>()),
    );

    controller.transitionWorkspaceState(
      P5WorkspaceId.homeChat,
      P5WorkspaceState.running,
    );
    controller.transitionWorkspaceState(
      P5WorkspaceId.homeChat,
      P5WorkspaceState.completed,
    );
    expect(
      () => controller.transitionWorkspaceState(
        P5WorkspaceId.homeChat,
        P5WorkspaceState.running,
      ),
      throwsA(isA<P5InvalidTransition>()),
    );
  });

  test(
    'experience levels use progressive disclosure without authority changes',
    () {
      final controller = P5InformationArchitectureController();
      addTearDown(controller.dispose);

      final project = controller.state.selectedProjectId;
      final run = controller.state.selectedRunId;
      final owner = controller.state.ownerModeState;
      final sideEffects = controller.sideEffects;
      final simpleIds =
          controller.visibleWorkspaces.map((item) => item.id).toSet();

      controller.changeExperienceLevel(P5ExperienceLevel.advanced);
      final advancedIds =
          controller.visibleWorkspaces.map((item) => item.id).toSet();
      controller.changeExperienceLevel(P5ExperienceLevel.developer);

      expect(advancedIds.length, greaterThan(simpleIds.length));
      expect(advancedIds, contains(P5WorkspaceId.evidence));
      expect(advancedIds, contains(P5WorkspaceId.modelsProviders));
      expect(controller.state.selectedProjectId, project);
      expect(controller.state.selectedRunId, run);
      expect(controller.state.ownerModeState, owner);
      expect(controller.sideEffects, sideEffects);
      expect(controller.sideEffects.isZero, isTrue);
    },
  );

  test('plan-only changes are fail-closed once a run exists', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    expect(controller.canChangePlanOnly, isTrue);
    expect(controller.state.runState, P5RunPresentationState.planReady);

    controller.apply(P5PrototypeAction.choosePlanOnly);
    expect(controller.state.planOnly, isTrue);
    expect(controller.state.runState, P5RunPresentationState.planOnly);

    controller.apply(P5PrototypeAction.choosePlanOnly);
    expect(controller.state.planOnly, isFalse);
    expect(controller.state.runState, P5RunPresentationState.planReady);

    controller.apply(P5PrototypeAction.reviewPlan);
    expect(controller.state.runState, P5RunPresentationState.ready);
    controller.apply(P5PrototypeAction.startRun);

    expect(controller.state.selectedRunId, 'run.p5-simulated-current');
    expect(controller.state.runState, P5RunPresentationState.running);
    expect(controller.canChangePlanOnly, isFalse);

    controller.apply(P5PrototypeAction.choosePlanOnly);

    expect(controller.state.planOnly, isFalse);
    expect(controller.state.runState, P5RunPresentationState.running);
    expect(
      controller.state.recoveryMessage,
      contains('before a simulated run starts'),
    );
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('selected project and run persist across navigation and reopen', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.selectRun('run.p5-existing-001');
    controller.selectWorkspace(P5WorkspaceId.verificationCenter);
    controller.selectWorkspace(P5WorkspaceId.evidence);

    expect(controller.state.selectedProjectId, 'project.kristin-local');
    expect(controller.state.selectedRunId, 'run.p5-existing-001');
    expect(controller.state.workspace, P5WorkspaceId.evidence);

    controller.back();
    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);
    expect(controller.state.selectedRunId, 'run.p5-existing-001');

    controller.forward();
    expect(controller.state.workspace, P5WorkspaceId.evidence);
    expect(controller.state.selectedProjectId, 'project.kristin-local');
  });

  test('prototype controller has no runtime side effects', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.apply(P5PrototypeAction.reviewPlan);
    controller.apply(P5PrototypeAction.startRun);
    controller.apply(P5PrototypeAction.pauseRun);
    controller.apply(P5PrototypeAction.resumeRun);
    controller.apply(P5PrototypeAction.stopRun);
    controller.apply(P5PrototypeAction.completeRun);
    controller.setOwnerModePresentation(
      P5OwnerModePresentationState.running,
    );
    controller.selectWorkspace(P5WorkspaceId.webStudio);

    expect(controller.sideEffects, P5SideEffectLedger.zero);
    expect(controller.sideEffects.isZero, isTrue);
  });
}
