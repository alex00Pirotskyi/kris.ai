import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_ui_quality.dart';

void main() {
  group('P5-013 UI performance budgets', () {
    test('all measured lanes pass within the initial desktop targets', () {
      final monitor = P5UiPerformanceMonitor(
        residentMemoryReader: () => 192 * 1024 * 1024,
      );

      monitor.recordStartup(const Duration(milliseconds: 850));
      for (final milliseconds in <int>[10, 12, 14, 16, 18, 20, 21, 22]) {
        monitor.recordFrame(Duration(milliseconds: milliseconds));
      }
      for (final milliseconds in <int>[45, 55, 65, 72]) {
        monitor.recordStreamFlush(
          Duration(milliseconds: milliseconds),
          batchSize: 8,
        );
      }
      monitor.recordVirtualizedCollection(
        id: 'timeline-10k',
        totalItems: 10000,
        mountedItems: 54,
      );
      monitor.sampleResidentMemory();

      final snapshot = monitor.snapshot();
      expect(snapshot.allMeasured, isTrue);
      expect(snapshot.meetsInitialTargets, isTrue);
      expect(snapshot.failedCount, 0);
      expect(snapshot.frameSampleCount, 8);
      expect(snapshot.streamFlushSampleCount, 4);
      expect(snapshot.largeCollectionSampleCount, 1);
      expect(
        snapshot.metrics.map((metric) => metric.id),
        containsAll(<String>[
          'startup',
          'frame-p95',
          'slow-frame-ratio',
          'stream-flush-p95',
          'resident-memory',
          'virtualization',
        ]),
      );
    });

    test('missing measurements never become an implicit performance pass', () {
      final snapshot = P5UiPerformanceMonitor(
        residentMemoryReader: () => 128 * 1024 * 1024,
      ).snapshot();

      expect(snapshot.allMeasured, isFalse);
      expect(snapshot.meetsInitialTargets, isFalse);
      expect(
        snapshot.metrics
            .where(
              (metric) =>
                  metric.state == P5UiPerformanceMetricState.notMeasured,
            )
            .map((metric) => metric.id),
        containsAll(<String>[
          'startup',
          'frame-p95',
          'slow-frame-ratio',
          'stream-flush-p95',
          'resident-memory',
          'virtualization',
        ]),
      );
    });

    test('budget violations are explicit and fail the aggregate target', () {
      final monitor = P5UiPerformanceMonitor(
        residentMemoryReader: () => 900 * 1024 * 1024,
      );
      monitor.recordStartup(const Duration(milliseconds: 4100));
      for (final milliseconds in <int>[18, 40, 44, 50]) {
        monitor.recordFrame(Duration(milliseconds: milliseconds));
      }
      monitor.recordStreamFlush(
        const Duration(milliseconds: 140),
        batchSize: 2,
      );
      monitor.recordVirtualizedCollection(
        id: 'unbounded-list',
        totalItems: 10000,
        mountedItems: 600,
      );
      monitor.sampleResidentMemory();

      final snapshot = monitor.snapshot();
      expect(snapshot.allMeasured, isTrue);
      expect(snapshot.meetsInitialTargets, isFalse);
      expect(snapshot.failedCount, greaterThanOrEqualTo(5));
    });

    testWidgets('performance dashboard exposes measured state semantically', (
      tester,
    ) async {
      final monitor = P5UiPerformanceMonitor(
        residentMemoryReader: () => 160 * 1024 * 1024,
      );
      monitor.recordStartup(const Duration(milliseconds: 500));
      for (var index = 0; index < 20; index++) {
        monitor.recordFrame(const Duration(milliseconds: 12));
      }
      monitor.recordStreamFlush(
        const Duration(milliseconds: 65),
        batchSize: 10,
      );
      monitor.recordVirtualizedCollection(
        id: 'timeline',
        totalItems: 10000,
        mountedItems: 42,
      );
      monitor.sampleResidentMemory();

      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: P5UiPerformanceDashboard(monitor: monitor)),
        ),
      );

      expect(
        find.byKey(const Key('p5-ui-performance-dashboard')),
        findsOneWidget,
      );
      expect(find.text('PASS'), findsOneWidget);
      expect(
        find.bySemanticsLabel('UI performance dashboard: PASS'),
        findsOneWidget,
      );
      expect(find.text('Frame time p95'), findsOneWidget);
      expect(find.text('Large-list mounted item peak'), findsOneWidget);
      semantics.dispose();
    });
  });
}
