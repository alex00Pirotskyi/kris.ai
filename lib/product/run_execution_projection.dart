import 'domain.dart';
import 'run_live_signals.dart';

enum RunTimelineCategory {
  model,
  policy,
  preflight,
  file,
  terminal,
  browser,
  web,
  evidence,
  verification,
  retry,
  rollback,
  steering,
  run,
}

class RunTimelineEntry {
  const RunTimelineEntry({
    required this.key,
    required this.timestamp,
    required this.category,
    required this.title,
    required this.detail,
    this.workItemId,
    this.sequence,
    this.live = false,
  });

  final String key;
  final DateTime timestamp;
  final RunTimelineCategory category;
  final String title;
  final String detail;
  final String? workItemId;
  final int? sequence;
  final bool live;
}

class RunExecutionProjection {
  const RunExecutionProjection._();

  static RunTimelineEntry fromEvent(EventEnvelope event) {
    final category = _categoryForType(event.type);
    final title = _titleForType(event.type, event.data);
    final detail =
        event.data['message']?.toString() ??
        event.data['error']?.toString() ??
        event.data['summary']?.toString() ??
        '';
    return RunTimelineEntry(
      key: 'event-${event.sequence}',
      timestamp: event.timestamp,
      category: category,
      title: title,
      detail: detail,
      workItemId: event.data['workItemId']?.toString(),
      sequence: event.sequence,
    );
  }

  static RunTimelineEntry fromLive(LiveRunSignal signal) {
    final category = switch (signal.kind) {
      LiveRunSignalKind.modelProgress ||
      LiveRunSignalKind.modelTextDelta => RunTimelineCategory.model,
      LiveRunSignalKind.toolStarted ||
      LiveRunSignalKind.toolOutput ||
      LiveRunSignalKind.toolCompleted ||
      LiveRunSignalKind.toolFailed => RunTimelineCategory.terminal,
      LiveRunSignalKind.preflight => RunTimelineCategory.preflight,
      LiveRunSignalKind.steeringQueued ||
      LiveRunSignalKind.steeringApplied => RunTimelineCategory.steering,
      _ => RunTimelineCategory.run,
    };
    final title = switch (signal.kind) {
      LiveRunSignalKind.modelProgress =>
        signal.data['message']?.toString() ?? 'Model working',
      LiveRunSignalKind.modelTextDelta => 'Model streaming output',
      LiveRunSignalKind.toolStarted =>
        'Running ${signal.data['tool'] ?? 'tool'}',
      LiveRunSignalKind.toolCompleted =>
        'Completed ${signal.data['tool'] ?? 'tool'}',
      LiveRunSignalKind.toolFailed =>
        '${signal.data['tool'] ?? 'Tool'} needs attention',
      LiveRunSignalKind.preflight =>
        signal.data['message']?.toString() ?? 'Checking readiness',
      LiveRunSignalKind.steeringQueued => 'Direction queued',
      LiveRunSignalKind.steeringApplied => 'Direction applied',
      _ => signal.data['message']?.toString() ?? signal.kind.name,
    };
    final detail = signal.kind == LiveRunSignalKind.modelTextDelta
        ? signal.data['delta']?.toString() ?? ''
        : signal.data['detail']?.toString() ?? '';
    return RunTimelineEntry(
      key: 'live-${signal.sequence}',
      timestamp: signal.timestamp,
      category: category,
      title: title,
      detail: detail,
      workItemId: signal.workItemId,
      live: true,
    );
  }

  static List<RunTimelineEntry> merge({
    required Iterable<EventEnvelope> events,
    required Iterable<LiveRunSignal> liveSignals,
    int limit = 10000,
  }) {
    final result = <RunTimelineEntry>[
      ...events.map(fromEvent),
      ...liveSignals.map(fromLive),
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (result.length <= limit) return List.unmodifiable(result);
    return List.unmodifiable(result.sublist(result.length - limit));
  }

  static RunTimelineCategory _categoryForType(String type) {
    if (type.startsWith('model.')) return RunTimelineCategory.model;
    if (type.startsWith('policy.') || type.startsWith('permission.')) {
      return RunTimelineCategory.policy;
    }
    if (type.contains('preflight')) return RunTimelineCategory.preflight;
    if (type.startsWith('file.') || type.startsWith('mutation.')) {
      return RunTimelineCategory.file;
    }
    if (type.startsWith('tool.') || type.startsWith('process.')) {
      return RunTimelineCategory.terminal;
    }
    if (type.startsWith('browser.')) return RunTimelineCategory.browser;
    if (type.startsWith('research.') || type.startsWith('web.')) {
      return RunTimelineCategory.web;
    }
    if (type.startsWith('evidence.')) return RunTimelineCategory.evidence;
    if (type.startsWith('verification.') || type.startsWith('diagnostics.')) {
      return RunTimelineCategory.verification;
    }
    if (type.contains('retry') || type.contains('repair')) {
      return RunTimelineCategory.retry;
    }
    if (type.contains('rollback') || type.contains('compensation')) {
      return RunTimelineCategory.rollback;
    }
    if (type.startsWith('steering.')) return RunTimelineCategory.steering;
    return RunTimelineCategory.run;
  }

  static String _titleForType(String type, Map<String, dynamic> data) {
    if (type == 'run.preflight_started') return 'Checking execution readiness';
    if (type == 'run.preflight_completed') return 'Readiness check completed';
    if (type == 'run.preflight_blocked') {
      return 'Readiness check blocked the run';
    }
    if (type == 'run.started') return 'Kristin started working';
    if (type == 'run.succeeded') return 'Run completed successfully';
    if (type == 'run.failed') return 'Run failed';
    if (type == 'work_item.started') {
      return 'Started ${data['title'] ?? 'work item'}';
    }
    if (type == 'work_item.succeeded') {
      return 'Completed ${data['title'] ?? 'work item'}';
    }
    if (type == 'tool.started') return 'Running ${data['tool'] ?? 'tool'}';
    if (type == 'tool.completed') {
      return 'Completed ${data['tool'] ?? 'tool'}';
    }
    if (type.startsWith('model.')) {
      return data['message']?.toString() ?? type.replaceAll('.', ' ');
    }
    return type.replaceAll('.', ' ');
  }
}
