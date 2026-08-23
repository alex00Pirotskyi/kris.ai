import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_fixtures.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('P5-009 exposes all nine evidence kinds for every saved run', () {
    expect(P5EvidenceKind.values, hasLength(9));
    for (final run in P5PrototypeFixtures.runs) {
      final evidence = P5PrototypeFixtures.evidenceForRun(run.id);
      expect(evidence, hasLength(P5EvidenceKind.values.length));
      final kinds = evidence.map((item) => item.kind).toSet();
      expect(kinds, hasLength(P5EvidenceKind.values.length));
      expect(kinds, containsAll(P5EvidenceKind.values));
      expect(evidence.every((item) => item.runId == run.id), isTrue);
      expect(evidence.every((item) => item.byteLength > 0), isTrue);
    }
    expect(P5PrototypeFixtures.evidenceForRun('run.unknown'), isEmpty);
  });

  test('P5-009 evidence selection fails closed outside the saved run', () {
    final controller = P5InformationArchitectureController();
    controller.selectEvidence('evidence.run.unknown.json');
    expect(controller.state.selectedEvidenceId, isNull);
    expect(
      controller.state.recoveryMessage,
      'Typed evidence can only reopen from a deterministic saved run.',
    );

    controller.selectRun('run.p5-complete-001');
    controller.selectEvidence('evidence.run.other.json');
    expect(controller.state.selectedEvidenceId, isNull);
    expect(
        controller.state.recoveryMessage, contains('is not part of saved run'));
  });

  testWidgets(
      'P5-009 reopens every viewer from a saved run and retains selection',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = P5InformationArchitectureController();
    controller.changeExperienceLevel(P5ExperienceLevel.advanced);
    controller.selectRun('run.p5-complete-001');
    controller.selectWorkspace(P5WorkspaceId.evidence);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: P5InformationArchitecturePrototype(controller: controller),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('saved-run-evidence-index')), findsOneWidget);
    for (final kind in P5EvidenceKind.values) {
      final item = find.byKey(Key('evidence-item-${kind.name}'));
      expect(item, findsOneWidget);
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pump();
      final viewer = find.byKey(Key('evidence-viewer-${kind.name}'));
      expect(viewer, findsOneWidget);
      expect(controller.state.selectedEvidenceId, contains(kind.name));
    }

    final selectedId = controller.state.selectedEvidenceId;
    expect(selectedId, contains(P5EvidenceKind.receipt.name));
    controller.selectWorkspace(P5WorkspaceId.projects);
    await tester.pump();
    controller.selectWorkspace(P5WorkspaceId.evidence);
    await tester.pump();
    expect(controller.state.selectedEvidenceId, selectedId);
    expect(
      find.byKey(Key('evidence-viewer-${P5EvidenceKind.receipt.name}')),
      findsOneWidget,
    );
  });

  testWidgets('P5-009 current in-memory run does not fabricate saved evidence',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final initial = P5PrototypeFixtures.initialState().copyWith(
      experienceLevel: P5ExperienceLevel.advanced,
      workspace: P5WorkspaceId.evidence,
      reopenWorkspace: P5WorkspaceId.evidence,
      selectedRunId: 'run.p5-simulated-current',
      runState: P5RunPresentationState.running,
    );
    final controller =
        P5InformationArchitectureController(initialState: initial);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: P5InformationArchitecturePrototype(controller: controller),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('evidence-no-saved-run')), findsOneWidget);
    expect(find.byKey(const Key('saved-run-evidence-index')), findsNothing);
  });
}
