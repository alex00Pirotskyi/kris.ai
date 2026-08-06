import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';

Future<void> _pump(
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

void main() {
  testWidgets('active run context controls are disabled in the UI',
      (tester) async {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    controller.apply(P5PrototypeAction.reviewPlan);
    controller.apply(P5PrototypeAction.startRun);

    await _pump(tester, controller);

    final taskField = tester.widget<TextField>(find.byKey(const Key('task-input')));
    expect(taskField.enabled, isFalse);

    controller.selectWorkspace(P5WorkspaceId.projects);
    await tester.pumpAndSettle();
    final otherProject = tester.widget<ListTile>(
      find.byKey(const Key('project-project.sample-notes')),
    );
    final clearProject = tester.widget<ListTile>(
      find.byKey(const Key('clear-project-button')),
    );
    expect(otherProject.onTap, isNull);
    expect(clearProject.onTap, isNull);

    controller.selectWorkspace(P5WorkspaceId.runsActivity);
    await tester.pumpAndSettle();
    final savedRun = tester.widget<ListTile>(
      find.byKey(const Key('run-run.p5-existing-001')),
    );
    expect(savedRun.onTap, isNull);
    expect(controller.state.selectedRunId, 'run.p5-simulated-current');
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('context controls unlock after simulated run completion',
      (tester) async {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    controller.apply(P5PrototypeAction.reviewPlan);
    controller.apply(P5PrototypeAction.startRun);
    controller.apply(P5PrototypeAction.completeRun);

    await _pump(tester, controller);

    final taskField = tester.widget<TextField>(find.byKey(const Key('task-input')));
    expect(taskField.enabled, isTrue);

    controller.selectWorkspace(P5WorkspaceId.projects);
    await tester.pumpAndSettle();
    final otherProject = tester.widget<ListTile>(
      find.byKey(const Key('project-project.sample-notes')),
    );
    expect(otherProject.onTap, isNotNull);

    controller.selectWorkspace(P5WorkspaceId.runsActivity);
    await tester.pumpAndSettle();
    final savedRun = tester.widget<ListTile>(
      find.byKey(const Key('run-run.p5-existing-001')),
    );
    expect(savedRun.onTap, isNotNull);
    expect(controller.sideEffects.isZero, isTrue);
  });
}
