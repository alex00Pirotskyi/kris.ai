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

Finder _timelineRows() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('p5-timeline-row-');
    });

void main() {
  test('P5-008 deterministic source covers 10k events and all categories', () {
    expect(P5PrototypeFixtures.timelineEventCount, 10000);
    final firstCycle = List<P5TimelineEvent>.generate(
      P5TimelineCategory.values.length,
      (index) => P5PrototypeFixtures.timelineEventAt(
        runId: 'run.p5-complete-001',
        visibleIndex: index,
      ),
    );
    expect(
      firstCycle.map((event) => event.category).toList(),
      P5TimelineCategory.values,
    );
    expect(firstCycle.first.sequence, 1);
    expect(firstCycle.last.sequence, 10);
    final repeated = P5PrototypeFixtures.timelineEventAt(
      runId: 'run.p5-complete-001',
      visibleIndex: 4,
    );
    expect(repeated.category, P5TimelineCategory.browser);
    expect(repeated.sequence, 5);
    expect(repeated.title, firstCycle[4].title);
    expect(repeated.detail, firstCycle[4].detail);
    expect(
      () => P5PrototypeFixtures.timelineEventAt(
        runId: 'run.p5-simulated-current',
        visibleIndex: 0,
      ),
      throwsArgumentError,
    );
  });

  test('P5-008 category filters map in O(1) to exactly 1000 events', () {
    for (final category in P5TimelineCategory.values) {
      expect(P5PrototypeFixtures.timelineVisibleCount(category), 1000);
      final first = P5PrototypeFixtures.timelineEventAt(
        runId: 'run.p5-existing-001',
        visibleIndex: 0,
        filter: category,
      );
      final last = P5PrototypeFixtures.timelineEventAt(
        runId: 'run.p5-existing-001',
        visibleIndex: 999,
        filter: category,
      );
      expect(first.category, category);
      expect(last.category, category);
      expect(last.sequence, lessThanOrEqualTo(10000));
    }
  });

  testWidgets('P5-008 saved-run timeline virtualizes 10k events',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..selectWorkspace(P5WorkspaceId.runsActivity)
      ..selectRun('run.p5-complete-001');
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.byKey(const Key('p5-run-timeline')), findsOneWidget);
    expect(find.byKey(const Key('p5-run-timeline-list')), findsOneWidget);
    expect(find.text('Showing 10000 of 10000'), findsOneWidget);
    final builtRows = _timelineRows().evaluate().length;
    expect(builtRows, greaterThan(0));
    expect(builtRows, lessThan(100));
    expect(find.byKey(const Key('p5-timeline-row-10000')), findsNothing);
  });

  testWidgets('P5-008 filtering keeps virtualization and category truth',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..selectWorkspace(P5WorkspaceId.runsActivity)
      ..selectRun('run.p5-complete-001');
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.tap(find.byKey(const Key('p5-timeline-filter-browser')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1000 of 10000'), findsOneWidget);
    expect(find.byKey(const Key('p5-timeline-row-5')), findsOneWidget);
    expect(
        find.textContaining('Browser • Browser action recorded'), findsWidgets);
    expect(_timelineRows().evaluate().length, lessThan(100));
  });

  testWidgets('P5-008 current simulated run never fabricates saved timeline',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..apply(P5PrototypeAction.reviewPlan)
      ..apply(P5PrototypeAction.startRun)
      ..selectWorkspace(P5WorkspaceId.runsActivity);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.byKey(const Key('current-run-detail')), findsOneWidget);
    expect(find.byKey(const Key('p5-run-timeline')), findsNothing);
    expect(
        find.textContaining('No saved timeline is fabricated'), findsOneWidget);
  });
}
