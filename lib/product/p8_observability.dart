import 'dart:convert';
import 'dart:io';

import 'crypto_utils.dart';

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
  });

  final bool optedIn;
  final bool hashSensitiveIdentifiers;
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
    required this.policy,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

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

  final P8TelemetryPolicy policy;
  final DateTime Function() _clock;
  final List<P8TraceEvent> _events = <P8TraceEvent>[];

  List<P8TraceEvent> get events => List<P8TraceEvent>.unmodifiable(_events);

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
    if (!policy.optedIn) return false;
    if (traceId.trim().isEmpty || spanId.trim().isEmpty || runId.trim().isEmpty) {
      throw StateError('telemetry_correlation_id_required');
    }
    final unknownKeys = safeAttributes.keys
        .where((key) => !_allowedSafeKeys.contains(key))
        .toList(growable: false);
    if (unknownKeys.isNotEmpty) {
      throw StateError('telemetry_attribute_not_allowlisted:${unknownKeys.join(',')}');
    }
    final hashed = <String, String>{};
    if (policy.hashSensitiveIdentifiers) {
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
        durationMicros: durationMicros < 0 ? 0 : durationMicros,
        status: status,
        safeAttributes: Map<String, Object>.unmodifiable(safeAttributes),
        hashedAttributes: Map<String, String>.unmodifiable(hashed),
      ),
    );
    return true;
  }

  Map<String, Object> preview() => <String, Object>{
        'schemaVersion': '1.0.0',
        'optedIn': policy.optedIn,
        'contentCollection': false,
        'eventCount': _events.length,
        'events': _events.map((event) => event.toJson()).toList(growable: false),
      };

  Map<String, Object> openTelemetryEnvelope() => <String, Object>{
        'resource': <String, Object>{
          'service.name': 'kristin-desktop',
          'telemetry.content.enabled': false,
        },
        'spans': _events.map((event) => event.toJson()).toList(growable: false),
      };

  Future<void> export(File file) async {
    if (!policy.optedIn) {
      throw StateError('telemetry_export_requires_opt_in');
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(preview())}\n',
      flush: true,
    );
  }

  void deleteAll() => _events.clear();
}
