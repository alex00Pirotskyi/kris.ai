import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'crypto_utils.dart';
import 'domain.dart';

enum P8TelemetryCategory {
  model,
  policy,
  tool,
  terminal,
  browser,
  web,
  update,
}

extension P8TelemetryCategoryWire on P8TelemetryCategory {
  String get wireName => name;
}

class P8TelemetryPolicy {
  const P8TelemetryPolicy({
    this.optedIn = false,
    this.hashSensitiveIdentifiers = true,
    this.retentionDays = 7,
    this.maxBufferedEvents = 20000,
  })  : assert(retentionDays >= 0),
        assert(maxBufferedEvents > 0);

  final bool optedIn;
  final bool hashSensitiveIdentifiers;
  final int retentionDays;
  final int maxBufferedEvents;

  Map<String, Object> toJson() => <String, Object>{
        'optedIn': optedIn,
        'hashSensitiveIdentifiers': hashSensitiveIdentifiers,
        'retentionDays': retentionDays,
        'maxBufferedEvents': maxBufferedEvents,
        'contentCollection': false,
      };
}

class P8TraceEvent {
  const P8TraceEvent({
    required this.traceId,
    required this.spanId,
    required this.runId,
    required this.category,
    required this.operation,
    required this.recordedAt,
    required this.durationMicros,
    required this.status,
    required this.safeAttributes,
    required this.hashedAttributes,
  });

  final String traceId;
  final String spanId;
  final String runId;
  final P8TelemetryCategory category;
  final String operation;
  final DateTime recordedAt;
  final int durationMicros;
  final String status;
  final Map<String, Object> safeAttributes;
  final Map<String, String> hashedAttributes;

  Map<String, Object> toJson() => <String, Object>{
        'traceId': traceId,
        'spanId': spanId,
        'runId': runId,
        'category': category.wireName,
        'operation': operation,
        'recordedAt': recordedAt.toUtc().toIso8601String(),
        'durationMicros': durationMicros,
        'status': status,
        'safeAttributes': safeAttributes,
        'hashedAttributes': hashedAttributes,
      };
}

class P8TelemetryBuffer {
  P8TelemetryBuffer({
    required P8TelemetryPolicy policy,
    DateTime Function()? clock,
  })  : _policy = policy,
        _clock = clock ?? DateTime.now;

  static const Set<String> _allowedSafeKeys = <String>{
    'modelProvider',
    'modelName',
    'toolName',
    'policyDecision',
    'errorCode',
    'retryability',
    'effectState',
    'httpStatusClass',
    'attempt',
    'itemCount',
    'bytesCount',
    'success',
  };

  P8TelemetryPolicy _policy;
  final DateTime Function() _clock;
  final List<P8TraceEvent> _events = <P8TraceEvent>[];
  int _droppedEventCount = 0;

  P8TelemetryPolicy get policy => _policy;
  List<P8TraceEvent> get events => List<P8TraceEvent>.unmodifiable(_events);
  int get droppedEventCount => _droppedEventCount;

  void updatePolicy(P8TelemetryPolicy policy) {
    _policy = policy;
    if (!policy.optedIn) {
      deleteAll();
      return;
    }
    _trimToLimit();
    pruneExpired();
  }

  bool record({
    required String traceId,
    required String spanId,
    required String runId,
    required P8TelemetryCategory category,
    required String operation,
    required int durationMicros,
    required String status,
    Map<String, Object> safeAttributes = const <String, Object>{},
    Map<String, String> sensitiveIdentifiers = const <String, String>{},
  }) {
    if (!_policy.optedIn) return false;
    if (traceId.trim().isEmpty ||
        spanId.trim().isEmpty ||
        runId.trim().isEmpty ||
        operation.trim().isEmpty ||
        status.trim().isEmpty ||
        durationMicros < 0) {
      throw StateError('telemetry_correlation_id_required');
    }
    final unknownKeys = safeAttributes.keys
        .where((key) => !_allowedSafeKeys.contains(key))
        .toList(growable: false)
      ..sort();
    if (unknownKeys.isNotEmpty) {
      throw StateError('telemetry_attribute_not_allowlisted:${unknownKeys.join(',')}');
    }
    final hashed = <String, String>{};
    if (_policy.hashSensitiveIdentifiers) {
      for (final entry in sensitiveIdentifiers.entries) {
        hashed[entry.key] = Sha256.text(entry.value);
      }
    }
    _events.add(
      P8TraceEvent(
        traceId: traceId,
        spanId: spanId,
        runId: runId,
        category: category,
        operation: operation,
        recordedAt: _clock().toUtc(),
        durationMicros: durationMicros,
        status: status,
        safeAttributes: Map<String, Object>.unmodifiable(safeAttributes),
        hashedAttributes: Map<String, String>.unmodifiable(hashed),
      ),
    );
    _trimToLimit();
    return true;
  }

  void _trimToLimit() {
    final overflow = _events.length - _policy.maxBufferedEvents;
    if (overflow <= 0) return;
    _events.removeRange(0, overflow);
    _droppedEventCount += overflow;
  }

  void pruneExpired() {
    if (_policy.retentionDays <= 0) {
      _events.clear();
      return;
    }
    final cutoff = _clock().toUtc().subtract(
          Duration(days: _policy.retentionDays),
        );
    _events.removeWhere((event) => event.recordedAt.isBefore(cutoff));
  }

  Map<String, Object> preview() => <String, Object>{
        'schemaVersion': '1.0.0',
        ..._policy.toJson(),
        'eventCount': _events.length,
        'droppedEventCount': _droppedEventCount,
        'events': _events.map((event) => event.toJson()).toList(growable: false),
      };

  Map<String, Object> openTelemetryEnvelope() => <String, Object>{
        'resource': <String, Object>{
          'service.name': 'kristin-desktop',
          'telemetry.content.enabled': false,
          'telemetry.opted_in': _policy.optedIn,
        },
        'spans': _events.map((event) => event.toJson()).toList(growable: false),
      };

  Future<void> export(File file) async {
    if (!_policy.optedIn) {
      throw StateError('telemetry_export_requires_opt_in');
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(preview())}\n',
      flush: true,
    );
  }

  void deleteAll() {
    _events.clear();
    _droppedEventCount = 0;
  }
}

class P8ProductTelemetryBridge {
  P8ProductTelemetryBridge({
    required this.buffer,
    required Stream<EventEnvelope> events,
  }) : _events = events;

  final P8TelemetryBuffer buffer;
  final Stream<EventEnvelope> _events;
  StreamSubscription<EventEnvelope>? _subscription;

  bool get running => _subscription != null;

  void start() {
    if (_subscription != null) return;
    _subscription = _events.listen(_recordEvent);
  }

  Future<void> close() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  void _recordEvent(EventEnvelope event) {
    final category = categoryForEventType(event.type);
    if (category == null || !buffer.policy.optedIn) return;
    final correlation = event.correlationId.trim().isEmpty
        ? event.id
        : event.correlationId.trim();
    final runHash = Sha256.text('run:$correlation');
    final lower = event.type.toLowerCase();
    final failed = lower.contains('fail') ||
        lower.contains('error') ||
        lower.contains('denied') ||
        lower.contains('rejected');
    buffer.record(
      traceId: runHash,
      spanId: Sha256.text('${event.sequence}:${event.id}').substring(0, 32),
      runId: runHash,
      category: category,
      operation: event.type,
      durationMicros: 0,
      status: failed ? 'error' : 'event',
      safeAttributes: <String, Object>{'success': !failed},
    );
  }

  static P8TelemetryCategory? categoryForEventType(String type) {
    final value = type.toLowerCase();
    if (value.contains('browser')) return P8TelemetryCategory.browser;
    if (value.contains('terminal') ||
        value.contains('process') ||
        value.contains('command.execut')) {
      return P8TelemetryCategory.terminal;
    }
    if (value.contains('research') ||
        value.contains('web.') ||
        value.contains('search.') ||
        value.contains('fetch.')) {
      return P8TelemetryCategory.web;
    }
    if (value.contains('update') || value.contains('release.')) {
      return P8TelemetryCategory.update;
    }
    if (value.contains('policy') ||
        value.contains('permission') ||
        value.contains('approval') ||
        value.contains('authority') ||
        value.contains('preflight')) {
      return P8TelemetryCategory.policy;
    }
    if (value.contains('model') || value.contains('prompt.')) {
      return P8TelemetryCategory.model;
    }
    if (value.contains('tool') || value.contains('mcp')) {
      return P8TelemetryCategory.tool;
    }
    return null;
  }
}
