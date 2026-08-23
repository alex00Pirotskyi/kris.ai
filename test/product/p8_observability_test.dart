import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p8_observability.dart';

void main() {
  group('P8-009/P8-010 observability privacy', () {
    test('telemetry is opt-in and content-free by construction', () {
      final buffer = P8TelemetryBuffer(
        policy: const P8TelemetryPolicy(),
        clock: () => DateTime.utc(2026, 8, 23, 12),
      );
      final recorded = buffer.record(
        traceId: 'trace-1',
        spanId: 'span-1',
        runId: 'run-1',
        category: P8TelemetryCategory.model,
        operation: 'model.request',
        durationMicros: 100,
        status: 'ok',
        safeAttributes: const <String, Object>{'modelName': 'qwen'},
      );
      expect(recorded, isFalse);
      expect(buffer.events, isEmpty);
      expect(buffer.preview()['contentCollection'], isFalse);
    });

    test('allowlisted metadata is correlated and sensitive ids are hashed', () {
      final buffer = P8TelemetryBuffer(
        policy: const P8TelemetryPolicy(optedIn: true),
        clock: () => DateTime.utc(2026, 8, 23, 12),
      );
      expect(
        buffer.record(
          traceId: 'trace-1',
          spanId: 'span-1',
          runId: 'run-1',
          category: P8TelemetryCategory.tool,
          operation: 'tool.execute',
          durationMicros: 250,
          status: 'ok',
          safeAttributes: const <String, Object>{
            'toolName': 'read_file',
            'success': true,
          },
          sensitiveIdentifiers: const <String, String>{
            'projectPath': r'C:\secret\workspace',
          },
        ),
        isTrue,
      );
      final event = buffer.events.single;
      expect(event.traceId, 'trace-1');
      expect(event.hashedAttributes['projectPath'], isNot(r'C:\secret\workspace'));
      expect(event.hashedAttributes['projectPath'], hasLength(64));
      expect(buffer.openTelemetryEnvelope()['spans'], isA<List<Object?>>());
    });

    test('unknown attributes are rejected instead of leaking content', () {
      final buffer = P8TelemetryBuffer(
        policy: const P8TelemetryPolicy(optedIn: true),
      );
      expect(
        () => buffer.record(
          traceId: 'trace-1',
          spanId: 'span-1',
          runId: 'run-1',
          category: P8TelemetryCategory.web,
          operation: 'web.fetch',
          durationMicros: 10,
          status: 'ok',
          safeAttributes: const <String, Object>{
            'pageContent': 'private page body',
          },
        ),
        throwsStateError,
      );
    });

    test('preview export and delete are user-controllable', () async {
      final buffer = P8TelemetryBuffer(
        policy: const P8TelemetryPolicy(optedIn: true),
      );
      buffer.record(
        traceId: 'trace-export',
        spanId: 'span-export',
        runId: 'run-export',
        category: P8TelemetryCategory.update,
        operation: 'update.check',
        durationMicros: 50,
        status: 'ok',
        safeAttributes: const <String, Object>{'success': true},
      );
      final directory = await Directory.systemTemp.createTemp('kristin-telemetry-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/telemetry.json');
      await buffer.export(file);
      expect(await file.readAsString(), contains('"contentCollection": false'));
      buffer.deleteAll();
      expect(buffer.events, isEmpty);
    });
  });
}
