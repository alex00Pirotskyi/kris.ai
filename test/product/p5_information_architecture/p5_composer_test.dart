import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';

void main() {
  test('P5-006 composer state is bounded and side-effect free', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.updateComposerProfile(P5ComposerProfile.owner);
    controller.updateComposerModel(P5ComposerModel.localDeep);
    controller.updateComposerAccess(P5ComposerAccess.requestAdditional);
    controller.updateComposerBudget(P5ComposerBudget.thorough);
    controller.updateComposerLaunchTiming(P5ComposerLaunchTiming.runNow);
    controller.updateComposerAttachments(
      List<String>.generate(12, (index) => 'attachment-$index.md'),
    );
    controller.updateAcceptanceCriteria(
      <String>[
        'Build succeeds without warnings.',
        'Tests verify the requested behavior.',
        'Tests verify the requested behavior.',
      ],
    );

    expect(controller.state.composerProfile, P5ComposerProfile.owner);
    expect(controller.state.composerModel, P5ComposerModel.localDeep);
    expect(
      controller.state.composerAccess,
      P5ComposerAccess.requestAdditional,
    );
    expect(controller.state.composerBudget, P5ComposerBudget.thorough);
    expect(controller.state.attachments, hasLength(8));
    expect(controller.state.acceptanceCriteria, hasLength(2));
    expect(controller.state.planReviewed, isFalse);
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('P5-006 active run locks every composer context mutation', () {
    final controller = P5InformationArchitectureController()
      ..updateComposerAttachments(const <String>['spec.md'])
      ..updateAcceptanceCriteria(const <String>['Initial criterion'])
      ..launchComposer();
    addTearDown(controller.dispose);

    expect(controller.state.runState, P5RunPresentationState.running);
    final before = controller.state;

    controller.updateComposerProfile(P5ComposerProfile.owner);
    controller.updateComposerModel(P5ComposerModel.localFast);
    controller.updateComposerAccess(P5ComposerAccess.readOnly);
    controller.updateComposerBudget(P5ComposerBudget.focused);
    controller.updateComposerLaunchTiming(P5ComposerLaunchTiming.laterToday);
    controller.updateComposerAttachments(const <String>['other.md']);
    controller.updateAcceptanceCriteria(const <String>['Changed criterion']);

    expect(controller.state.composerProfile, before.composerProfile);
    expect(controller.state.composerModel, before.composerModel);
    expect(controller.state.composerAccess, before.composerAccess);
    expect(controller.state.composerBudget, before.composerBudget);
    expect(
      controller.state.composerLaunchTiming,
      before.composerLaunchTiming,
    );
    expect(controller.state.attachments, before.attachments);
    expect(controller.state.acceptanceCriteria, before.acceptanceCriteria);
    expect(controller.state.recoveryMessage, contains('cannot change'));
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('P5-006 scheduling fails closed without a scheduler runtime', () {
    final controller = P5InformationArchitectureController()
      ..updateComposerLaunchTiming(P5ComposerLaunchTiming.laterToday);
    addTearDown(controller.dispose);

    controller.launchComposer();

    expect(controller.state.selectedRunId, isNull);
    expect(controller.state.planReviewed, isFalse);
    expect(
        controller.state.recoveryMessage, contains('Scheduling is not bound'));
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('P5-006 plan-only launch reviews without starting a run', () {
    final controller = P5InformationArchitectureController()
      ..apply(P5PrototypeAction.choosePlanOnly);
    addTearDown(controller.dispose);

    controller.launchComposer();

    expect(controller.state.planReviewed, isTrue);
    expect(controller.state.planOnly, isTrue);
    expect(controller.state.selectedRunId, isNull);
    expect(controller.state.runState, P5RunPresentationState.planOnly);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('P5-006 composer exposes every roadmap control', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: P5InformationArchitecturePrototype(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('p5-task-composer')), findsOneWidget);
    expect(find.byKey(const Key('composer-project')), findsOneWidget);
    expect(find.byKey(const Key('composer-profile')), findsOneWidget);
    expect(find.byKey(const Key('composer-model')), findsOneWidget);
    expect(find.byKey(const Key('composer-access')), findsOneWidget);
    expect(find.byKey(const Key('composer-budget')), findsOneWidget);
    expect(find.byKey(const Key('composer-timing')), findsOneWidget);
    expect(find.byKey(const Key('composer-attachments')), findsOneWidget);
    expect(find.byKey(const Key('composer-criteria')), findsOneWidget);
    expect(find.byKey(const Key('plan-only-toggle')), findsOneWidget);
    expect(find.byKey(const Key('start-run-button')), findsOneWidget);
  });

  testWidgets('P5-006 Ctrl+Enter uses the same launch path as Run now',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: P5InformationArchitecturePrototype(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(controller.state.planReviewed, isTrue);
    expect(controller.state.selectedRunId, 'run.p5-simulated-current');
    expect(controller.state.runState, P5RunPresentationState.running);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('P5-006 Cmd+Enter is keyboard-complete on macOS layout',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: P5InformationArchitecturePrototype(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.state.selectedRunId, 'run.p5-simulated-current');
    expect(controller.state.runState, P5RunPresentationState.running);
    expect(controller.sideEffects.isZero, isTrue);
  });
}
