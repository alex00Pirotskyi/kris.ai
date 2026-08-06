import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';

void main() {
  test('retry interrupted run is fail-closed for completed saved runs', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.selectRun('run.p5-complete-001');
    expect(controller.state.runState, P5RunPresentationState.completed);

    controller.apply(P5PrototypeAction.retryInterruptedRun);

    expect(controller.state.runState, P5RunPresentationState.completed);
    expect(controller.state.recoveryMessage, contains('not valid'));
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('retry interrupted run resumes only an interrupted saved fixture', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.selectRun('run.p5-existing-001');
    expect(controller.state.runState, P5RunPresentationState.interrupted);

    controller.apply(P5PrototypeAction.retryInterruptedRun);

    expect(controller.state.runState, P5RunPresentationState.running);
    expect(
      controller.state.recoveryMessage,
      'Interrupted run restored from the saved fixture.',
    );
    expect(controller.sideEffects.isZero, isTrue);
  });
}
