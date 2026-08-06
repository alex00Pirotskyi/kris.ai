import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';

void main() {
  test('verification request fails closed before completion', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.apply(P5PrototypeAction.runVerification);
    expect(controller.state.runState, P5RunPresentationState.planReady);
    expect(controller.state.verificationRequested, isFalse);
    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.recoveryMessage, contains('only be requested'));

    controller.apply(P5PrototypeAction.reviewPlan);
    controller.apply(P5PrototypeAction.startRun);
    expect(controller.state.runState, P5RunPresentationState.running);

    controller.apply(P5PrototypeAction.runVerification);
    expect(controller.state.runState, P5RunPresentationState.running);
    expect(controller.state.verificationRequested, isFalse);
    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.recoveryMessage, contains('only be requested'));
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('verification request fails closed from blocked presentation state', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.selectProject(null);
    expect(controller.state.runState, P5RunPresentationState.blocked);

    controller.apply(P5PrototypeAction.runVerification);

    expect(controller.state.runState, P5RunPresentationState.blocked);
    expect(controller.state.verificationRequested, isFalse);
    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.recoveryMessage, contains('only be requested'));
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('verification request succeeds only after completion', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.apply(P5PrototypeAction.reviewPlan);
    controller.apply(P5PrototypeAction.startRun);
    controller.apply(P5PrototypeAction.completeRun);
    expect(controller.state.runState, P5RunPresentationState.completed);

    controller.apply(P5PrototypeAction.runVerification);

    expect(controller.state.verificationRequested, isTrue);
    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);
    expect(controller.state.recoveryMessage, contains('Affected tests selected'));
    expect(controller.sideEffects.isZero, isTrue);
  });
}
