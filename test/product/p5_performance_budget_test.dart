import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_performance_budget.dart';

void main() {
  group('P5-013 performance budgets', () {
    test('passes a healthy deterministic sample', () {
      var now = DateTime.utc(2026, 8, 23, 12);
      final probe = P5PerformanceProbe(clock: () => now);
      addTearDown(probe.dispose);

      probe.start(attachFrameTimings: false);
      now = now.add(const Duration(milliseconds: 1400));
      probe.markInteractive();
      for (var index = 0; index < 95; index++) {
        probe.recordFrame(const Duration(milliseconds: 12));
      }
      for (var index = 0; index < 5; index++) {
        probe.recordFrame(const Duration(milliseconds: 18));
      }
      probe.recordLargeTimelineEvents(10000);
      for (var index = 0; index < 20; index++) {
        probe.recordStreamUpdate();
      }

      final report = probe.evaluate(residentMemoryBytes: 256 * 1024 * 1024);
      expect(report.passed, isTrue);
      expect(report.violations, isEmpty);
      expect(report.snapshot.startup, const Duration(milliseconds: 1400));
      expect(report.snapshot.p95Frame, lessThanOrEqualTo(const Duration(milliseconds: 20)));
    });

    test('reports every breached budget independently', () {
      var now = DateTime.utc(2026, 8, 23, 12);
      final probe = P5PerformanceProbe(clock: () => now);
      addTearDown(probe.dispose);

      probe.start(attachFrameTimings: false);
      now = now.add(const Duration(seconds: 4));
      probe.markInteractive();
      for (var index = 0; index < 95; index++) {
        probe.recordFrame(const Duration(milliseconds: 25));
      }
      probe.recordFrame(const Duration(milliseconds: 90));
      probe.recordLargeTimelineEvents(9000);
      for (var index = 0; index < 31; index++) {
        probe.recordStreamUpdate();
      }

      final report = probe.evaluate(residentMemoryBytes: 769 * 1024 * 1024);
      expect(report.passed, isFalse);
      expect(
        report.violations,
        containsAll(<String>[
          'startup_budget_exceeded',
          'p95_frame_budget_exceeded',
          'worst_frame_budget_exceeded',
          'large_timeline_budget_not_demonstrated',
          'stream_update_budget_exceeded',
          'resident_memory_budget_exceeded',
        ]),
      );
    });

    test('stream-rate window forgets old updates', () {
      var now = DateTime.utc(2026, 8, 23, 12);
      final probe = P5PerformanceProbe(clock: () => now);
      addTearDown(probe.dispose);

      probe.start(attachFrameTimings: false);
      probe.markInteractive();
      probe.recordLargeTimelineEvents(10000);
      for (var index = 0; index < 30; index++) {
        probe.recordStreamUpdate();
      }
      now = now.add(const Duration(seconds: 2));
      probe.recordStreamUpdate();

      final snapshot = probe.snapshot(residentMemoryBytes: 64 * 1024 * 1024);
      expect(snapshot.streamUpdatesPerSecond, 1);
    });
  });
}
