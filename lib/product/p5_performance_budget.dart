import 'dart:io';

import 'package:flutter/scheduler.dart';

class P5PerformanceBudget {
  const P5PerformanceBudget({
    this.maximumStartup = const Duration(seconds: 3),
    this.maximumP95Frame = const Duration(milliseconds: 20),
    this.maximumWorstFrame = const Duration(milliseconds: 80),
    this.minimumLargeTimelineEvents = 10000,
    this.maximumStreamUpdatesPerSecond = 30,
    this.maximumResidentMemoryBytes = 768 * 1024 * 1024,
  });

  final Duration maximumStartup;
  final Duration maximumP95Frame;
  final Duration maximumWorstFrame;
  final int minimumLargeTimelineEvents;
  final int maximumStreamUpdatesPerSecond;
  final int maximumResidentMemoryBytes;
}

class P5PerformanceSnapshot {
  const P5PerformanceSnapshot({
    required this.startup,
    required this.p95Frame,
    required this.worstFrame,
    required this.frameCount,
    required this.largeTimelineEvents,
    required this.streamUpdatesPerSecond,
    required this.residentMemoryBytes,
  });

  final Duration startup;
  final Duration p95Frame;
  final Duration worstFrame;
  final int frameCount;
  final int largeTimelineEvents;
  final int streamUpdatesPerSecond;
  final int residentMemoryBytes;

  Map<String, Object> toJson() => <String, Object>{
        'startupMicros': startup.inMicroseconds,
        'p95FrameMicros': p95Frame.inMicroseconds,
        'worstFrameMicros': worstFrame.inMicroseconds,
        'frameCount': frameCount,
        'largeTimelineEvents': largeTimelineEvents,
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

class P5PerformanceProbe {
  P5PerformanceProbe({
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
  int _largeTimelineEvents = 0;

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

  void recordFrame(Duration duration) {
    _frames.add(duration);
    if (_frames.length > 4096) {
      _frames.removeRange(0, _frames.length - 4096);
    }
  }

  void recordLargeTimelineEvents(int events) {
    if (events > _largeTimelineEvents) _largeTimelineEvents = events;
  }

  void recordStreamUpdate() {
    final now = _clock();
    _streamUpdates.add(now);
    _pruneStreamUpdates(now);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      recordFrame(timing.totalSpan);
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
      largeTimelineEvents: _largeTimelineEvents,
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
    if (value.largeTimelineEvents < budget.minimumLargeTimelineEvents) {
      violations.add('large_timeline_budget_not_demonstrated');
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
