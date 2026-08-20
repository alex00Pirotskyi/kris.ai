import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_control_plane.dart';
import 'package:kristin_local_agent/product/browser/browser_profile_store.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime.dart';

void main() {
  test('deterministic fixture is local-only and covers browser task surfaces',
      () {
    final html = File('test/product/browser/fixtures/p3_browser/index.html')
        .readAsStringSync();
    final script = File('test/product/browser/fixtures/p3_browser/fixture.js')
        .readAsStringSync();

    expect(html, contains('Browser fixture'));
    expect(html, contains('profile-form'));
    expect(html, contains('drag-source'));
    expect(html, contains('download="fixture.txt"'));
    expect(html, contains('type="file"'));
    expect(script, contains('p3-fixture-ready'));
    expect('$html\n$script', isNot(contains('https://')));
    expect('$html\n$script', isNot(contains('http://')));
    expect('$html\n$script', isNot(contains('fetch(')));
    expect('$html\n$script', isNot(contains('XMLHttpRequest')));
  });

  test('visual fallback refuses confidence below the governed threshold', () {
    expect(
      () => P3BrowserVisualActionRequest(
        action: P3BrowserActionKind.click,
        locators: <P3BrowserLocator>[P3BrowserLocator.text('Run')],
        visualSource: P3BrowserVisualSource(
          observationHash: 'a' * 64,
          screenshotSha256: 'b' * 64,
          viewportWidth: 1280,
          viewportHeight: 720,
        ),
        visualTarget: const P3BrowserVisualTarget(
          x: 10,
          y: 10,
          width: 20,
          height: 20,
          confidence: 0.89,
          description: 'Run button',
        ),
        minimumConfidence: 0.89,
      ).toJson(),
      throwsA(isA<P3BrowserRuntimeException>()),
    );
  });

  test('profile identifiers cannot escape the application-owned profile root',
      () async {
    final root = await Directory.systemTemp.createTemp('p3-profile-security-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final store = P3BrowserProfileStore(root: root, cipher: _RejectingCipher());
    await expectLater(
      store.put('../outside', const <String, Object?>{'cookies': <Object?>[]}),
      throwsA(isA<Exception>()),
    );
  });

  test(
      'takeover state machine blocks automation until fresh observation resume',
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
        structuredFailureCode: 'browser_locator_ambiguous',
        minimumConfidence: 0.9,
        visualConfidence: 0.5,
        visualDestinationConfidence: null,
        beforeObservationHash: 'a' * 64,
        beforeScreenshotSha256: 'b' * 64,
        afterObservationHash: null,
        afterScreenshotSha256: null,
        observationChanged: false,
        verified: false,
        pauseReason: 'ambiguous_target',
      ),
    );
    expect(controller.automationAllowed, isFalse);
    expect(
      () => controller.confirmAutomationResumed('a' * 64),
      throwsStateError,
    );
  });
}

final class _RejectingCipher implements P3BrowserProfileCipher {
  @override
  Future<List<int>> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) async =>
      throw StateError('cipher_should_not_be_reached');

  @override
  Future<List<int>> open(
    List<int> ciphertext, {
    required List<int> associatedData,
  }) async =>
      throw StateError('cipher_should_not_be_reached');
}
