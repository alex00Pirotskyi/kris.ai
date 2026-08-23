import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
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

    test('central event bridge maps subsystem events without copying content',
        () async {
      final controller = StreamController<EventEnvelope>.broadcast();
      addTearDown(controller.close);
      final buffer = P8TelemetryBuffer(
        policy: const P8TelemetryPolicy(optedIn: true),
        clock: () => DateTime.utc(2026, 8, 23, 12),
      );
      final bridge = P8ProductTelemetryBridge(
        buffer: buffer,
        events: controller.stream,
      )..start();
      addTearDown(bridge.close);

      final types = <String>[
        'model.generated',
        'permission.denied',
        'tool.completed',
        'browser.action.completed',
        'research.fetch.completed',
        'release.update.checked',
      ];
      for (var index = 0; index < types.length; index++) {
        controller.add(
          EventEnvelope(
            sequence: index + 1,
            id: 'event-$index',
            type: types[index],
            correlationId: 'run-sensitive-id',
            timestamp: DateTime.utc(2026, 8, 23, 12),
            data: const <String, dynamic>{
              'prompt': 'must never enter telemetry',
              'path': r'C:\private\project',
            },
          ),
        );
      }
      controller.add(
        EventEnvelope(
          sequence: 99,
          id: 'project-event',
          type: 'project.added',
          correlationId: 'project-private-id',
          timestamp: DateTime.utc(2026, 8, 23, 12),
          data: const <String, dynamic>{'name': 'private project'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(buffer.events, hasLength(types.length));
      expect(
        buffer.events.map((event) => event.category).toSet(),
        containsAll(<P8TelemetryCategory>{
          P8TelemetryCategory.model,
          P8TelemetryCategory.policy,
          P8TelemetryCategory.tool,
          P8TelemetryCategory.browser,
          P8TelemetryCategory.web,
          P8TelemetryCategory.update,
        }),
      );
      final encoded = buffer.preview().toString();
      expect(encoded, isNot(contains('must never enter telemetry')));
      expect(encoded, isNot(contains(r'C:\private\project')));
      expect(encoded, isNot(contains('run-sensitive-id')));
      expect(buffer.events.first.runId, hasLength(64));
    });

    test('opting out clears buffered telemetry and resets dropped counts', () {
      final buffer = P8TelemetryBuffer(
        policy: const P8TelemetryPolicy(
          optedIn: true,
          maxBufferedEvents: 1,
        ),
      );
      for (var index = 0; index < 2; index++) {
        buffer.record(
          traceId: 'trace-$index',
          spanId: 'span-$index',
          runId: 'run-$index',
          category: P8TelemetryCategory.tool,
          operation: 'tool.execute',
          durationMicros: 1,
          status: 'ok',
        );
      }
      expect(buffer.events, hasLength(1));
      expect(buffer.droppedEventCount, 1);
      buffer.updatePolicy(const P8TelemetryPolicy());
      expect(buffer.events, isEmpty);
      expect(buffer.droppedEventCount, 0);
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
