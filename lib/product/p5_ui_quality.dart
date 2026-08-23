import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

@immutable
final class P5UiPerformanceBudgets {
  const P5UiPerformanceBudgets({
    this.startupToFirstFrameMs = 3000,
    this.p95FrameMs = 25,
    this.slowFrameThresholdMs = 34,
    this.maxSlowFrameRatio = 0.05,
    this.streamFlushP95Ms = 100,
    this.maxResidentMemoryMiB = 768,
    this.virtualizedCollectionFloor = 1000,
    this.maxMountedItemsForLargeCollection = 250,
  });

  final int startupToFirstFrameMs;
  final double p95FrameMs;
  final double slowFrameThresholdMs;
  final double maxSlowFrameRatio;
  final double streamFlushP95Ms;
  final int maxResidentMemoryMiB;
  final int virtualizedCollectionFloor;
  final int maxMountedItemsForLargeCollection;
}

enum P5UiPerformanceMetricState { pass, fail, notMeasured }

@immutable
final class P5UiPerformanceMetric {
  const P5UiPerformanceMetric({
    required this.id,
    required this.label,
    required this.state,
    required this.valueLabel,
    required this.targetLabel,
    required this.detail,
  });

  final String id;
  final String label;
  final P5UiPerformanceMetricState state;
  final String valueLabel;
  final String targetLabel;
  final String detail;
}

@immutable
final class P5UiPerformanceSnapshot {
  const P5UiPerformanceSnapshot({
    required this.metrics,
    required this.frameSampleCount,
    required this.streamFlushSampleCount,
    required this.largeCollectionSampleCount,
  });

  final List<P5UiPerformanceMetric> metrics;
  final int frameSampleCount;
  final int streamFlushSampleCount;
  final int largeCollectionSampleCount;

  bool get allMeasured => metrics.every(
    (metric) => metric.state != P5UiPerformanceMetricState.notMeasured,
  );

  bool get meetsInitialTargets =>
      allMeasured &&
      metrics.every(
        (metric) => metric.state == P5UiPerformanceMetricState.pass,
      );

  int get failedCount => metrics
      .where((metric) => metric.state == P5UiPerformanceMetricState.fail)
      .length;
}

final class P5UiPerformanceMonitor extends ChangeNotifier {
  P5UiPerformanceMonitor({
    this.budgets = const P5UiPerformanceBudgets(),
    int Function()? residentMemoryReader,
  }) : _residentMemoryReader = residentMemoryReader ?? _defaultResidentMemory;

  static final P5UiPerformanceMonitor shared = P5UiPerformanceMonitor();

  final P5UiPerformanceBudgets budgets;
  final int Function() _residentMemoryReader;
  final Stopwatch _startupStopwatch = Stopwatch();
  final List<double> _frameDurationsMs = <double>[];
  final List<double> _streamFlushDurationsMs = <double>[];
  final Map<String, _VirtualizedCollectionSample> _virtualizedCollections =
      <String, _VirtualizedCollectionSample>{};

  bool _frameMonitoring = false;
  int? _startupToFirstFrameMs;
  int? _residentMemoryBytes;

  void start() {
    if (!_startupStopwatch.isRunning && _startupToFirstFrameMs == null) {
      _startupStopwatch.start();
    }
    if (!_frameMonitoring) {
      SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
      _frameMonitoring = true;
    }
    sampleResidentMemory(notify: false);
  }

  void stop() {
    if (_frameMonitoring) {
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
      _frameMonitoring = false;
    }
    _startupStopwatch.stop();
  }

  void reset() {
    _startupStopwatch
      ..stop()
      ..reset();
    _startupToFirstFrameMs = null;
    _residentMemoryBytes = null;
    _frameDurationsMs.clear();
    _streamFlushDurationsMs.clear();
    _virtualizedCollections.clear();
    notifyListeners();
  }

  void markFirstFrame() {
    if (_startupToFirstFrameMs != null) return;
    if (!_startupStopwatch.isRunning) _startupStopwatch.start();
    _startupStopwatch.stop();
    _startupToFirstFrameMs = _startupStopwatch.elapsedMilliseconds;
    sampleResidentMemory(notify: false);
    notifyListeners();
  }

  void recordStartup(Duration elapsed) {
    _startupToFirstFrameMs = elapsed.inMilliseconds;
    notifyListeners();
  }

  void recordFrame(Duration totalSpan) {
    _appendBounded(_frameDurationsMs, _milliseconds(totalSpan), 600);
    notifyListeners();
  }

  void recordStreamFlush(Duration elapsed, {required int batchSize}) {
    if (batchSize <= 0) return;
    _appendBounded(_streamFlushDurationsMs, _milliseconds(elapsed), 600);
    notifyListeners();
  }

  void recordVirtualizedCollection({
    required String id,
    required int totalItems,
    required int mountedItems,
  }) {
    if (id.trim().isEmpty || totalItems < 0 || mountedItems < 0) return;
    final current = _virtualizedCollections[id];
    _virtualizedCollections[id] = _VirtualizedCollectionSample(
      totalItems: math.max(totalItems, current?.totalItems ?? 0),
      peakMountedItems: math.max(mountedItems, current?.peakMountedItems ?? 0),
    );
    notifyListeners();
  }

  void recordResidentMemoryBytes(int bytes) {
    if (bytes <= 0) return;
    _residentMemoryBytes = bytes;
    notifyListeners();
  }

  void sampleResidentMemory({bool notify = true}) {
    final bytes = _residentMemoryReader();
    if (bytes <= 0) return;
    _residentMemoryBytes = bytes;
    if (notify) notifyListeners();
  }

  P5UiPerformanceSnapshot snapshot() {
    final frameP95 = _percentile(_frameDurationsMs, 0.95);
    final slowFrames = _frameDurationsMs
        .where((value) => value > budgets.slowFrameThresholdMs)
        .length;
    final slowRatio = _frameDurationsMs.isEmpty
        ? null
        : slowFrames / _frameDurationsMs.length;
    final streamP95 = _percentile(_streamFlushDurationsMs, 0.95);
    final largeCollections = _virtualizedCollections.values
        .where(
          (sample) => sample.totalItems >= budgets.virtualizedCollectionFloor,
        )
        .toList(growable: false);
    final worstMounted = largeCollections.isEmpty
        ? null
        : largeCollections
              .map((sample) => sample.peakMountedItems)
              .reduce(math.max);
    final residentMiB = _residentMemoryBytes == null
        ? null
        : _residentMemoryBytes! / (1024 * 1024);

    return P5UiPerformanceSnapshot(
      frameSampleCount: _frameDurationsMs.length,
      streamFlushSampleCount: _streamFlushDurationsMs.length,
      largeCollectionSampleCount: largeCollections.length,
      metrics: List<P5UiPerformanceMetric>.unmodifiable(<P5UiPerformanceMetric>[
        _upperBoundMetric(
          id: 'startup',
          label: 'Startup → first frame',
          value: _startupToFirstFrameMs?.toDouble(),
          target: budgets.startupToFirstFrameMs.toDouble(),
          unit: 'ms',
          detail: 'Desktop UI startup instrumentation.',
        ),
        _upperBoundMetric(
          id: 'frame-p95',
          label: 'Frame time p95',
          value: frameP95,
          target: budgets.p95FrameMs,
          unit: 'ms',
          detail: '${_frameDurationsMs.length} recent frame samples.',
        ),
        _upperBoundMetric(
          id: 'slow-frame-ratio',
          label: 'Slow-frame ratio',
          value: slowRatio == null ? null : slowRatio * 100,
          target: budgets.maxSlowFrameRatio * 100,
          unit: '%',
          detail:
              'Slow means > ${budgets.slowFrameThresholdMs.toStringAsFixed(0)} ms.',
        ),
        _upperBoundMetric(
          id: 'stream-flush-p95',
          label: 'Live stream UI flush p95',
          value: streamP95,
          target: budgets.streamFlushP95Ms,
          unit: 'ms',
          detail:
              '${_streamFlushDurationsMs.length} non-empty coalesced flush samples.',
        ),
        _upperBoundMetric(
          id: 'resident-memory',
          label: 'Kristin resident memory',
          value: residentMiB,
          target: budgets.maxResidentMemoryMiB.toDouble(),
          unit: 'MiB',
          detail: 'Desktop process RSS only; model-host memory is separate.',
        ),
        _upperBoundMetric(
          id: 'virtualization',
          label: 'Large-list mounted item peak',
          value: worstMounted?.toDouble(),
          target: budgets.maxMountedItemsForLargeCollection.toDouble(),
          unit: 'items',
          detail: largeCollections.isEmpty
              ? 'No collection ≥ ${budgets.virtualizedCollectionFloor} items observed.'
              : '${largeCollections.length} large collection sample(s).',
        ),
      ]),
    );
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    for (final timing in timings) {
      _appendBounded(_frameDurationsMs, _milliseconds(timing.totalSpan), 600);
    }
    notifyListeners();
  }

  static int _defaultResidentMemory() => ProcessInfo.currentRss;

  static double _milliseconds(Duration duration) =>
      duration.inMicroseconds / Duration.microsecondsPerMillisecond;

  static void _appendBounded(List<double> values, double value, int limit) {
    if (!value.isFinite || value < 0) return;
    values.add(value);
    if (values.length > limit) values.removeRange(0, values.length - limit);
  }

  static double? _percentile(List<double> input, double percentile) {
    if (input.isEmpty) return null;
    final sorted = List<double>.from(input)..sort();
    final index = ((sorted.length - 1) * percentile).ceil();
    return sorted[index.clamp(0, sorted.length - 1).toInt()];
  }

  static P5UiPerformanceMetric _upperBoundMetric({
    required String id,
    required String label,
    required double? value,
    required double target,
    required String unit,
    required String detail,
  }) {
    if (value == null) {
      return P5UiPerformanceMetric(
        id: id,
        label: label,
        state: P5UiPerformanceMetricState.notMeasured,
        valueLabel: 'Not measured',
        targetLabel: '≤ ${_format(target)} $unit',
        detail: detail,
      );
    }
    return P5UiPerformanceMetric(
      id: id,
      label: label,
      state: value <= target
          ? P5UiPerformanceMetricState.pass
          : P5UiPerformanceMetricState.fail,
      valueLabel: '${_format(value)} $unit',
      targetLabel: '≤ ${_format(target)} $unit',
      detail: detail,
    );
  }

  static String _format(double value) {
    if ((value - value.roundToDouble()).abs() < 0.01) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(value.abs() < 10 ? 2 : 1);
  }
}

@immutable
final class _VirtualizedCollectionSample {
  const _VirtualizedCollectionSample({
    required this.totalItems,
    required this.peakMountedItems,
  });

  final int totalItems;
  final int peakMountedItems;
}

class P5UiPerformanceDashboard extends StatelessWidget {
  const P5UiPerformanceDashboard({super.key, required this.monitor});

  final P5UiPerformanceMonitor monitor;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: monitor,
      builder: (context, _) {
        final snapshot = monitor.snapshot();
        final overall = snapshot.meetsInitialTargets
            ? 'PASS'
            : snapshot.failedCount > 0
            ? 'OVER BUDGET'
            : 'CALIBRATING';
        return Semantics(
          container: true,
          label: 'UI performance dashboard: $overall',
          child: Card(
            key: const Key('p5-ui-performance-dashboard'),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.speed_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'UI performance budgets',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      _P5PerformanceStatus(state: overall),
                      const SizedBox(width: 8),
                      IconButton(
                        key: const Key('p5-performance-refresh'),
                        tooltip: 'Refresh memory sample',
                        onPressed: monitor.sampleResidentMemory,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Live desktop measurements. Missing samples stay CALIBRATING; they are never treated as passing.',
                  ),
                  const SizedBox(height: 12),
                  for (final metric in snapshot.metrics)
                    _P5PerformanceMetricRow(metric: metric),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _P5PerformanceMetricRow extends StatelessWidget {
  const _P5PerformanceMetricRow({required this.metric});

  final P5UiPerformanceMetric metric;

  @override
  Widget build(BuildContext context) {
    final icon = switch (metric.state) {
      P5UiPerformanceMetricState.pass => Icons.check_circle_outline,
      P5UiPerformanceMetricState.fail => Icons.error_outline,
      P5UiPerformanceMetricState.notMeasured => Icons.hourglass_empty,
    };
    return Semantics(
      label:
          '${metric.label}: ${metric.valueLabel}; target ${metric.targetLabel}; ${metric.state.name}',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(metric.label),
        subtitle: Text('${metric.detail}\nTarget ${metric.targetLabel}'),
        trailing: Text(metric.valueLabel),
      ),
    );
  }
}

class _P5PerformanceStatus extends StatelessWidget {
  const _P5PerformanceStatus({required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('p5-performance-overall-state'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(state, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}
