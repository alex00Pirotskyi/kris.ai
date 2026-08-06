import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';

void main() {
  test('downgrade warning clears after explicit disclosure requirement is met',
      () {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.evidence);
    addTearDown(controller.dispose);

    controller.changeExperienceLevel(P5ExperienceLevel.simple);

    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.experienceLevel, P5ExperienceLevel.simple);
    expect(controller.state.recoveryMessage, contains('Returned to Home / Chat'));

    controller.changeExperienceLevel(P5ExperienceLevel.advanced);

    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.experienceLevel, P5ExperienceLevel.advanced);
    expect(controller.state.recoveryMessage, isNull);
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('unrelated recovery errors survive disclosure changes', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.selectRun('run.missing');
    final message = controller.state.recoveryMessage;
    expect(message, contains('was not found'));

    controller.changeExperienceLevel(P5ExperienceLevel.advanced);
    expect(controller.state.recoveryMessage, message);
    controller.changeExperienceLevel(P5ExperienceLevel.developer);
    expect(controller.state.recoveryMessage, message);
    expect(controller.sideEffects.isZero, isTrue);
  });
}
