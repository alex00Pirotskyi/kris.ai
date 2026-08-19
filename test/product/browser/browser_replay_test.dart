import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_replay.dart';

void main() {
  test('failed replay preserves telemetry and hashes without page payloads', () {
    final recorder = P3BrowserReplayRecorder(
      runId: 'run-p3-007',
      sessionId: 'session_1',
      clock: () => DateTime.utc(2026, 8, 19, 18, 0),
    );

    recorder.recordObservationSnapshot(
      sessionId: 'session_1',
      pageId: 'page_1',
      observationHash: 'a' * 64,
      observation: <String, Object?>{
        'url': 'https://example.test/login',
        'title': 'Sign in',
        'dom': '<input value="TOP_SECRET_DOM">',
        'visibleText': 'TOP_SECRET_VISIBLE_TEXT',
        'screenshot': <String, Object?>{
          'bytes': 1234,
          'sha256': 'b' * 64,
          'base64': 'TOP_SECRET_SCREENSHOT',
          'mediaType': 'image/jpeg',
        },
        'console': <String, Object?>{
          'entries': <Object?>[
            <String, Object?>{'type': 'error', 'text': 'request failed'},
          ],
          'dropped': 2,
        },
        'network': <String, Object?>{
          'requests': <Object?>[
            <String, Object?>{
              'url': 'https://example.test/api',
              'method': 'POST',
              'resourceType': 'fetch',
            },
          ],
          'requestsDropped': 1,
          'responses': <Object?>[
            <String, Object?>{
              'url': 'https://example.test/api',
              'status': 500,
              'method': 'POST',
              'resourceType': 'fetch',
            },
          ],
          'responsesDropped': 3,
        },
      },
    );
    recorder.recordActionSnapshot(
      sessionId: 'session_1',
      pageId: 'page_1',
      action: 'fill',
      locatorStrategy: 'label',
      locatorIndex: 0,
      sensitiveInputProvided: true,
      beforeObservationHash: 'a' * 64,
      afterObservationHash: 'c' * 64,
      observationChanged: true,
    );
    recorder.recordFailure(
      code: 'browser_locator_not_found',
      detail: 'failed after structured resolution',
      pageId: 'page_1',
    );

    final bundle = recorder.exportFailedRun();
    expect(bundle.bytes, lessThanOrEqualTo(1024 * 1024));
    expect(bundle.bundleHash, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(bundle.json['failed'], isTrue);
    expect((bundle.json['trace']! as List<Object?>), hasLength(3));
    expect((bundle.json['console']! as List<Object?>), hasLength(1));
    expect((bundle.json['network']! as List<Object?>), hasLength(2));

    final encoded = jsonEncode(bundle.json);
    expect(encoded, contains('request failed'));
    expect(encoded, contains('browser_locator_not_found'));
    expect(encoded, contains('sensitiveInputProvided'));
    expect(encoded, isNot(contains('TOP_SECRET_DOM')));
    expect(encoded, isNot(contains('TOP_SECRET_VISIBLE_TEXT')));
    expect(encoded, isNot(contains('TOP_SECRET_SCREENSHOT')));
  });

  test('replay limits count dropped telemetry and remain exportable', () {
    final recorder = P3BrowserReplayRecorder(
      runId: 'run-bounded',
      sessionId: 'session_2',
      limits: const P3BrowserReplayLimits(
        maxTraceEntries: 1,
        maxConsoleEntries: 1,
        maxNetworkEntries: 1,
        maxStringBytes: 128,
        maxBundleBytes: 16 * 1024,
      ),
      clock: () => DateTime.utc(2026, 8, 19, 18, 1),
    );

    for (var index = 0; index < 3; index += 1) {
      recorder.recordObservationSnapshot(
        sessionId: 'session_2',
        pageId: 'page_2',
        observationHash: '${index + 1}'.padLeft(64, '0'),
        observation: <String, Object?>{
          'url': 'https://example.test/$index',
          'title': 'page-$index',
          'screenshot': <String, Object?>{
            'bytes': 1,
            'sha256': 'd' * 64,
          },
          'console': <String, Object?>{
            'entries': <Object?>[
              <String, Object?>{'type': 'log', 'text': 'line-$index'},
            ],
            'dropped': 0,
          },
          'network': <String, Object?>{
            'requests': <Object?>[
              <String, Object?>{
                'url': 'https://example.test/r/$index',
                'method': 'GET',
                'resourceType': 'document',
              },
            ],
            'requestsDropped': 0,
            'responses': const <Object?>[],
            'responsesDropped': 0,
          },
        },
      );
    }
    recorder.recordFailure(code: 'fixture_failure');
    final bundle = recorder.exportFailedRun();
    final dropped = Map<String, Object?>.from(bundle.json['dropped']! as Map);
    expect(dropped['trace'] as int, greaterThan(0));
    expect(dropped['console'] as int, greaterThan(0));
    expect(dropped['network'] as int, greaterThan(0));
    expect(bundle.bytes, lessThanOrEqualTo(16 * 1024));
  });

  test('successful recorder cannot emit a failure replay', () {
    final recorder = P3BrowserReplayRecorder(
      runId: 'run-success',
      sessionId: 'session_3',
    );
    expect(recorder.exportFailedRun, throwsStateError);
  });
}
