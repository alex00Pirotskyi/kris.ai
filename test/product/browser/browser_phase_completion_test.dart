import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_control_plane.dart';
import 'package:kristin_local_agent/product/browser/browser_profile_store.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime.dart';
import 'package:kristin_local_agent/product/browser/browser_workspace.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';

void main() {
  test(
    'P3 auth profile store encrypts and authenticates profile state',
    () async {
      final root = await Directory.systemTemp.createTemp('p3-profile-store-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final store = P3BrowserProfileStore(
        root: root,
        cipher: _TestProfileCipher(),
        clock: () => DateTime.utc(2026, 8, 20, 6),
      );
      await store.put('primary', <String, Object?>{
        'cookies': <Object?>[
          <String, Object?>{'name': 'session', 'value': 'secret-cookie'},
        ],
        'origins': const <Object?>[],
      });

      final record = File(
        '${root.path}${Platform.pathSeparator}primary'
        '${Platform.pathSeparator}state.v1.json',
      );
      final atRest = await record.readAsString();
      expect(atRest, isNot(contains('secret-cookie')));
      expect(await store.listProfileIds(), <String>['primary']);
      final restored = await store.get('primary');
      expect(restored?['cookies'], isA<List>());

      await store.remove('primary');
      expect(await store.get('primary'), isNull);
    },
  );

  test(
    'P3 takeover requires a fresh observation before automation resumes',
    () {
      final controller = P3BrowserTakeoverController();
      controller.applyVisualResult(
        P3BrowserVisualActionResult(
          sessionId: 'session-1',
          pageId: 'page-1',
          action: P3BrowserActionKind.click,
          disposition: P3BrowserVisualActionDisposition.userTakeoverRequired,
          executionMode: P3BrowserVisualExecutionMode.visual,
          locatorStrategy: null,
          locatorIndex: null,
          targetLocatorStrategy: null,
          targetLocatorIndex: null,
          structuredFailureCode: 'browser_locator_not_found',
          minimumConfidence: 0.9,
          visualConfidence: 0.4,
          visualDestinationConfidence: null,
          beforeObservationHash: 'a' * 64,
          beforeScreenshotSha256: 'b' * 64,
          afterObservationHash: null,
          afterScreenshotSha256: null,
          observationChanged: false,
          verified: false,
          pauseReason: 'visual_target_low_confidence',
        ),
      );
      expect(
        controller.current.state,
        P3BrowserTakeoverState.takeoverRequested,
      );
      controller.grantUserControl();
      expect(() => controller.beginResume('a' * 64), throwsStateError);
      controller.beginResume('c' * 64);
      controller.confirmAutomationResumed('c' * 64);
      expect(controller.automationAllowed, isTrue);
    },
  );

  test('P3 verifier binds structured and visual results to observations', () {
    P3BrowserActionVerifier.requireStructuredResult(
      P3BrowserActionResult(
        sessionId: 'session-1',
        pageId: 'page-1',
        action: P3BrowserActionKind.click,
        locatorStrategy: 'role',
        locatorIndex: 0,
        targetLocatorStrategy: null,
        targetLocatorIndex: null,
        sensitiveInputProvided: false,
        beforeObservationHash: 'a' * 64,
        afterObservationHash: 'b' * 64,
        observationChanged: true,
      ),
      requireObservationChange: true,
    );

    expect(
      () => P3BrowserActionVerifier.requireStructuredResult(
        P3BrowserActionResult(
          sessionId: 'session-1',
          pageId: 'page-1',
          action: P3BrowserActionKind.click,
          locatorStrategy: 'role',
          locatorIndex: 0,
          targetLocatorStrategy: null,
          targetLocatorIndex: null,
          sensitiveInputProvided: false,
          beforeObservationHash: 'a' * 64,
          afterObservationHash: 'a' * 64,
          observationChanged: false,
        ),
        requireObservationChange: true,
      ),
      throwsStateError,
    );
  });

  testWidgets(
    'Browser Workspace remains usable on constrained desktop surface',
    (tester) async {
      final controller = P3BrowserWorkspaceController()
        ..showObservation(_observation());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: P3BrowserWorkspace(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('https://fixture.invalid'), findsOneWidget);
      expect(find.text('Accessibility'), findsOneWidget);
      await tester.tap(find.text('Test tools'));
      await tester.pumpAndSettle();
      expect(find.text('Responsive and accessibility checks'), findsOneWidget);
      expect(find.text('desktop 1440×900'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

P3BrowserPageObservation _observation() {
  final screenshot = base64Decode(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iiigD//2Q==',
  );
  final observation = <String, Object?>{
    'schemaVersion': '1.0.0',
    'url': 'https://fixture.invalid/',
    'title': 'P3 fixture',
    'dom': <String, Object?>{
      'text': '<main><button>Run</button></main>',
      'bytes': 33,
      'truncated': false,
    },
    'visibleText': <String, Object?>{
      'text': 'Run',
      'bytes': 3,
      'truncated': false,
    },
    'accessibility': <String, Object?>{
      'text': 'button "Run"',
      'bytes': 12,
      'truncated': false,
    },
    'forms': const <Object?>[],
    'console': <String, Object?>{'entries': const <Object?>[]},
    'network': <String, Object?>{'entries': const <Object?>[]},
    'screenshot': <String, Object?>{
      'mediaType': 'image/jpeg',
      'bytes': screenshot.length,
      'sha256': Sha256.hex(screenshot),
      'base64': base64Encode(screenshot),
    },
  };
  return P3BrowserPageObservation.fromJson(<String, Object?>{
    'sessionId': 'session-1',
    'pageId': 'page-1',
    'observationHash': Sha256.text(canonicalJson(observation)),
    'observation': observation,
  });
}

final class _TestProfileCipher implements P3BrowserProfileCipher {
  static const int _mask = 0x5a;

  @override
  Future<List<int>> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) async {
    final encrypted = plaintext.map((value) => value ^ _mask).toList();
    final tag = utf8.encode(Sha256.hex(<int>[...associatedData, ...encrypted]));
    return <int>[...tag, ...encrypted];
  }

  @override
  Future<List<int>> open(
    List<int> ciphertext, {
    required List<int> associatedData,
  }) async {
    if (ciphertext.length <= 64) throw StateError('ciphertext_invalid');
    final tag = utf8.decode(ciphertext.take(64).toList());
    final encrypted = ciphertext.skip(64).toList();
    final expected = Sha256.hex(<int>[...associatedData, ...encrypted]);
    if (!constantTimeEquals(tag, expected)) {
      throw StateError('ciphertext_authentication_failed');
    }
    return encrypted.map((value) => value ^ _mask).toList();
  }
}
