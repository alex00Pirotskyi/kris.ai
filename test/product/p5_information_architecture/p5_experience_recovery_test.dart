import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';

void main() {
  test('satisfying a workspace level requirement clears its stale warning', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.selectWorkspace(P5WorkspaceId.evidence);
    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.recoveryMessage, contains('Advanced mode'));

    controller.changeExperienceLevel(P5ExperienceLevel.advanced);

    expect(controller.state.experienceLevel, P5ExperienceLevel.advanced);
    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.recoveryMessage, isNull);
    expect(controller.sideEffects.isZero, isTrue);
  });
}
