import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_fixtures.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';

Future<void> _pump(
  WidgetTester tester,
  P5InformationArchitectureController controller,
) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: P5InformationArchitecturePrototype(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('P5-009 every saved run exposes all nine deterministic viewer kinds',
      () {
    expect(P5EvidenceViewKind.values.length, 9);
    for (final run in P5PrototypeFixtures.runs) {
      final artifacts = P5PrototypeFixtures.evidenceArtifactsForRun(run.id);
      expect(artifacts.length, P5EvidenceViewKind.values.length);
      expect(
        artifacts.map((artifact) => artifact.kind).toSet(),
        P5EvidenceViewKind.values.toSet(),
      );
      expect(artifacts.every((artifact) => artifact.runId == run.id), isTrue);
    }
    expect(
      P5PrototypeFixtures.evidenceArtifactsForRun(
        'run.p5-simulated-current',
      ),
      isEmpty,
    );
  });

  testWidgets('P5-009 all supported evidence viewers reopen from a saved run',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.runsActivity)
      ..selectRun('run.p5-complete-001');
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await _tapKey(tester, const Key('existing-run-evidence-button'));
    expect(
      find.byKey(const Key('p5-evidence-artifact-browser')),
      findsOneWidget,
    );

    for (final kind in P5EvidenceViewKind.values) {
      await _tapKey(tester, Key('p5-evidence-artifact-${kind.name}'));
      expect(
        find.byKey(Key('p5-evidence-viewer-${kind.name}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('P5-009 saved-run provenance survives workspace reopen',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.runsActivity)
      ..selectRun('run.p5-existing-001');
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await _tapKey(tester, const Key('existing-run-evidence-button'));
    expect(
      find.descendant(
        of: find.byKey(const Key('p5-evidence-artifact-browser')),
        matching: find.text('Review navigation accessibility'),
      ),
      findsOneWidget,
    );
    final initialArtifactScrollable = find.descendant(
      of: find.byKey(const Key('p5-evidence-artifact-list')),
      matching: find.byType(Scrollable),
    );
    expect(initialArtifactScrollable, findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('p5-evidence-artifact-receipt')),
      120,
      scrollable: initialArtifactScrollable,
    );
    await _tapKey(tester, const Key('p5-evidence-artifact-receipt'));
    expect(find.textContaining('run.p5-existing-001'), findsWidgets);

    controller.selectWorkspace(P5WorkspaceId.runsActivity);
    await tester.pumpAndSettle();
    await _tapKey(tester, const Key('existing-run-evidence-button'));
    expect(
      find.descendant(
        of: find.byKey(const Key('p5-evidence-artifact-browser')),
        matching: find.text('Review navigation accessibility'),
      ),
      findsOneWidget,
    );
    final reopenedArtifactScrollable = find.descendant(
      of: find.byKey(const Key('p5-evidence-artifact-list')),
      matching: find.byType(Scrollable),
    );
    expect(reopenedArtifactScrollable, findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('p5-evidence-artifact-receipt')),
      120,
      scrollable: reopenedArtifactScrollable,
    );
    await _tapKey(tester, const Key('p5-evidence-artifact-receipt'));
    expect(
      find.byKey(const Key('p5-evidence-viewer-receipt')),
      findsOneWidget,
    );
    expect(find.textContaining('run.p5-existing-001'), findsWidgets);
  });

  testWidgets('P5-009 current in-memory run never fabricates saved artifacts',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..apply(P5PrototypeAction.reviewPlan)
      ..apply(P5PrototypeAction.startRun)
      ..apply(P5PrototypeAction.completeRun)
      ..selectWorkspace(P5WorkspaceId.evidence);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(
      find.byKey(const Key('evidence-saved-run-required')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('p5-evidence-artifact-browser')),
      findsNothing,
    );
    expect(
      find.textContaining('do not fabricate saved evidence'),
      findsOneWidget,
    );
  });

  testWidgets('P5-009 binary view exposes metadata without raw payload',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.runsActivity)
      ..selectRun('run.p5-complete-001');
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await _tapKey(tester, const Key('existing-run-evidence-button'));
    await _tapKey(tester, const Key('p5-evidence-artifact-binaryMetadata'));

    expect(find.text('METADATA ONLY'), findsOneWidget);
    expect(find.textContaining('metadata only'), findsWidgets);
    expect(
      find.textContaining('Binary payload is intentionally not embedded'),
      findsOneWidget,
    );
  });
}
