import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';

void main() {
  test('completed run must detach old identity before a new start', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.apply(P5PrototypeAction.reviewPlan);
    controller.apply(P5PrototypeAction.startRun);
    controller.apply(P5PrototypeAction.completeRun);

    expect(controller.state.runState, P5RunPresentationState.completed);
    expect(controller.state.selectedRunId, 'run.p5-simulated-current');
    expect(controller.canReviewPlan, isTrue);
    expect(controller.canStartRun, isFalse);

    controller.apply(P5PrototypeAction.startRun);
    expect(controller.state.runState, P5RunPresentationState.completed);
    expect(controller.state.selectedRunId, 'run.p5-simulated-current');
    expect(controller.state.recoveryMessage, contains('Review a new plan'));

    controller.apply(P5PrototypeAction.reviewPlan);
    expect(controller.state.selectedRunId, isNull);
    expect(controller.state.runState, P5RunPresentationState.ready);
    expect(controller.state.planReviewed, isTrue);
    expect(controller.state.verificationRequested, isFalse);
    expect(controller.canStartRun, isTrue);

    controller.apply(P5PrototypeAction.startRun);
    expect(controller.state.selectedRunId, 'run.p5-simulated-current');
    expect(controller.state.runState, P5RunPresentationState.running);
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('saved run selection clears stale planning and verification state', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.apply(P5PrototypeAction.reviewPlan);
    controller.apply(P5PrototypeAction.runVerification);
    controller.selectWorkspace(P5WorkspaceId.homeChat);
    controller.apply(P5PrototypeAction.choosePlanOnly);

    expect(controller.state.planReviewed, isTrue);
    expect(controller.state.planOnly, isTrue);
    expect(controller.state.verificationRequested, isTrue);

    controller.selectRun('run.p5-complete-001');

    expect(controller.state.selectedProjectId, 'project.kristin-local');
    expect(controller.state.selectedRunId, 'run.p5-complete-001');
    expect(controller.state.runState, P5RunPresentationState.completed);
    expect(controller.state.planReviewed, isFalse);
    expect(controller.state.planOnly, isFalse);
    expect(controller.state.verificationRequested, isFalse);
    expect(controller.canStartRun, isFalse);
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('saved-run deep link clears stale planning and verification state', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.apply(P5PrototypeAction.reviewPlan);
    controller.apply(P5PrototypeAction.runVerification);
    controller.selectWorkspace(P5WorkspaceId.homeChat);
    controller.apply(P5PrototypeAction.choosePlanOnly);

    controller.deepLink(
      workspace: P5WorkspaceId.runsActivity,
      projectId: 'project.kristin-local',
      runId: 'run.p5-complete-001',
    );

    expect(controller.state.workspace, P5WorkspaceId.runsActivity);
    expect(controller.state.selectedRunId, 'run.p5-complete-001');
    expect(controller.state.runState, P5RunPresentationState.completed);
    expect(controller.state.planReviewed, isFalse);
    expect(controller.state.planOnly, isFalse);
    expect(controller.state.verificationRequested, isFalse);
    expect(controller.canStartRun, isFalse);
    expect(controller.sideEffects.isZero, isTrue);
  });
}
