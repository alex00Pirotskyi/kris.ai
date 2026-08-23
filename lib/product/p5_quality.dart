import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const Color _p5SeedColor = Color(0xff6558d3);

class P5AccessibilityPolicy {
  const P5AccessibilityPolicy._();

  static const double minimumInteractiveExtent = 48;
  static const double minimumSupportedTextScale = 1;
  static const double testedMaximumTextScale = 2;

  static ThemeData theme({
    Brightness brightness = Brightness.light,
    bool highContrast = false,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _p5SeedColor,
      brightness: brightness,
      contrastLevel: highContrast ? 1 : 0,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }

  static Duration motionDuration(
    BuildContext context,
    Duration requested,
  ) {
    final media = MediaQuery.maybeOf(context);
    if (media?.disableAnimations == true ||
        media?.accessibleNavigation == true) {
      return Duration.zero;
    }
    return requested;
  }

  static bool supportsTextScale(double scale) =>
      scale >= minimumSupportedTextScale && scale <= testedMaximumTextScale;
}

class P5PerformanceBudget {
  const P5PerformanceBudget({
    this.maximumStartup = const Duration(seconds: 3),
    this.maximumP95Frame = const Duration(milliseconds: 20),
    this.maximumWorstFrame = const Duration(milliseconds: 80),
    this.minimumTimelineCapacity = 10000,
    this.maximumStreamUpdatesPerSecond = 30,
    this.maximumResidentMemoryBytes = 768 * 1024 * 1024,
  });

  final Duration maximumStartup;
  final Duration maximumP95Frame;
  final Duration maximumWorstFrame;
  final int minimumTimelineCapacity;
  final int maximumStreamUpdatesPerSecond;
  final int maximumResidentMemoryBytes;
}

class P5PerformanceSnapshot {
  const P5PerformanceSnapshot({
    required this.startup,
    required this.p95Frame,
    required this.worstFrame,
    required this.frameCount,
    required this.timelineCapacity,
    required this.streamUpdatesPerSecond,
    required this.residentMemoryBytes,
  });

  final Duration startup;
  final Duration p95Frame;
  final Duration worstFrame;
  final int frameCount;
  final int timelineCapacity;
  final int streamUpdatesPerSecond;
  final int residentMemoryBytes;

  Map<String, Object> toJson() => <String, Object>{
        'startupMicros': startup.inMicroseconds,
        'p95FrameMicros': p95Frame.inMicroseconds,
        'worstFrameMicros': worstFrame.inMicroseconds,
        'frameCount': frameCount,
        'timelineCapacity': timelineCapacity,
        'streamUpdatesPerSecond': streamUpdatesPerSecond,
        'residentMemoryBytes': residentMemoryBytes,
      };
}

class P5PerformanceReport {
  const P5PerformanceReport({
    required this.snapshot,
    required this.violations,
  });

  final P5PerformanceSnapshot snapshot;
  final List<String> violations;

  bool get passed => violations.isEmpty;
}

class P5QualityMonitor {
  P5QualityMonitor({
    this.budget = const P5PerformanceBudget(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final P5PerformanceBudget budget;
  final DateTime Function() _clock;
  final List<Duration> _frames = <Duration>[];
  final List<DateTime> _streamUpdates = <DateTime>[];

  DateTime? _startedAt;
  DateTime? _interactiveAt;
  bool _attached = false;
  int _timelineCapacity = 0;

  void start() {
    _startedAt ??= _clock();
    if (_attached) return;
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _attached = true;
  }

  void markInteractive() {
    _startedAt ??= _clock();
    _interactiveAt ??= _clock();
  }

  void recordTimelineCapacity(int events) {
    if (events > _timelineCapacity) _timelineCapacity = events;
  }

  void recordStreamUpdate() {
    final now = _clock();
    _streamUpdates.add(now);
    _pruneStreamUpdates(now);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frames.add(timing.totalSpan);
    }
    if (_frames.length > 4096) {
      _frames.removeRange(0, _frames.length - 4096);
    }
  }

  void _pruneStreamUpdates(DateTime now) {
    final cutoff = now.subtract(const Duration(seconds: 1));
    _streamUpdates.removeWhere((value) => value.isBefore(cutoff));
  }

  P5PerformanceSnapshot snapshot({int? residentMemoryBytes}) {
    final now = _clock();
    _pruneStreamUpdates(now);
    final started = _startedAt ?? now;
    final interactive = _interactiveAt ?? now;
    final sortedFrames = List<Duration>.from(_frames)
      ..sort((left, right) => left.compareTo(right));
    final p95Index = sortedFrames.isEmpty
        ? 0
        : ((sortedFrames.length - 1) * 0.95).round();
    return P5PerformanceSnapshot(
      startup: interactive.difference(started),
      p95Frame: sortedFrames.isEmpty ? Duration.zero : sortedFrames[p95Index],
      worstFrame: sortedFrames.isEmpty ? Duration.zero : sortedFrames.last,
      frameCount: sortedFrames.length,
      timelineCapacity: _timelineCapacity,
      streamUpdatesPerSecond: _streamUpdates.length,
      residentMemoryBytes: residentMemoryBytes ?? ProcessInfo.currentRss,
    );
  }

  P5PerformanceReport evaluate({int? residentMemoryBytes}) {
    final value = snapshot(residentMemoryBytes: residentMemoryBytes);
    final violations = <String>[];
    if (value.startup > budget.maximumStartup) {
      violations.add('startup_budget_exceeded');
    }
    if (value.frameCount > 0 && value.p95Frame > budget.maximumP95Frame) {
      violations.add('p95_frame_budget_exceeded');
    }
    if (value.frameCount > 0 && value.worstFrame > budget.maximumWorstFrame) {
      violations.add('worst_frame_budget_exceeded');
    }
    if (value.timelineCapacity < budget.minimumTimelineCapacity) {
      violations.add('timeline_capacity_not_demonstrated');
    }
    if (value.streamUpdatesPerSecond > budget.maximumStreamUpdatesPerSecond) {
      violations.add('stream_update_budget_exceeded');
    }
    if (value.residentMemoryBytes > budget.maximumResidentMemoryBytes) {
      violations.add('resident_memory_budget_exceeded');
    }
    return P5PerformanceReport(
      snapshot: value,
      violations: List<String>.unmodifiable(violations),
    );
  }

  void dispose() {
    if (_attached) {
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
      _attached = false;
    }
  }
}
