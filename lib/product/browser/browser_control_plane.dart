import 'browser_runtime.dart';

enum P3BrowserTakeoverState {
  automated,
  takeoverRequested,
  userControlled,
  resuming,
  failed,
}

final class P3BrowserTakeoverSnapshot {
  const P3BrowserTakeoverSnapshot({
    required this.state,
    required this.sessionId,
    required this.pageId,
    required this.reason,
    required this.lastObservationHash,
    required this.generation,
  });

  final P3BrowserTakeoverState state;
  final String? sessionId;
  final String? pageId;
  final String? reason;
  final String? lastObservationHash;
  final int generation;
}

final class P3BrowserTakeoverController {
  P3BrowserTakeoverState _state = P3BrowserTakeoverState.automated;
  String? _sessionId;
  String? _pageId;
  String? _reason;
  String? _lastObservationHash;
  int _generation = 0;

  P3BrowserTakeoverSnapshot get current => P3BrowserTakeoverSnapshot(
    state: _state,
    sessionId: _sessionId,
    pageId: _pageId,
    reason: _reason,
    lastObservationHash: _lastObservationHash,
    generation: _generation,
  );

  bool get automationAllowed => _state == P3BrowserTakeoverState.automated;

  void applyVisualResult(P3BrowserVisualActionResult result) {
    if (_state != P3BrowserTakeoverState.automated) {
      throw StateError('browser_takeover_transition_invalid');
    }
    if (result.disposition == P3BrowserVisualActionDisposition.executed) {
      if (!result.verified || result.afterObservationHash == null) {
        throw StateError('browser_takeover_unverified_execution');
      }
      _lastObservationHash = result.afterObservationHash;
      _generation += 1;
      return;
    }
    final reason = result.pauseReason?.trim();
    if (reason == null || reason.isEmpty) {
      throw StateError('browser_takeover_reason_required');
    }
    _state = P3BrowserTakeoverState.takeoverRequested;
    _sessionId = result.sessionId;
    _pageId = result.pageId;
    _reason = reason;
    _lastObservationHash = result.beforeObservationHash;
    _generation += 1;
  }

  void grantUserControl() {
    if (_state != P3BrowserTakeoverState.takeoverRequested) {
      throw StateError('browser_takeover_transition_invalid');
    }
    _state = P3BrowserTakeoverState.userControlled;
    _generation += 1;
  }

  void beginResume(String observationHash) {
    if (_state != P3BrowserTakeoverState.userControlled ||
        !_isSha256(observationHash)) {
      throw StateError('browser_takeover_resume_invalid');
    }
    if (observationHash == _lastObservationHash) {
      throw StateError('browser_takeover_resume_requires_fresh_observation');
    }
    _lastObservationHash = observationHash;
    _state = P3BrowserTakeoverState.resuming;
    _generation += 1;
  }

  void confirmAutomationResumed(String observationHash) {
    if (_state != P3BrowserTakeoverState.resuming ||
        !_isSha256(observationHash) ||
        observationHash != _lastObservationHash) {
      throw StateError('browser_takeover_resume_invalid');
    }
    _state = P3BrowserTakeoverState.automated;
    _sessionId = null;
    _pageId = null;
    _reason = null;
    _generation += 1;
  }

  void fail(String reason) {
    if (reason.trim().isEmpty) {
      throw StateError('browser_takeover_failure_reason_required');
    }
    _state = P3BrowserTakeoverState.failed;
    _reason = reason.trim();
    _generation += 1;
  }

  void reset() {
    if (_state != P3BrowserTakeoverState.failed) {
      throw StateError('browser_takeover_reset_invalid');
    }
    _state = P3BrowserTakeoverState.automated;
    _sessionId = null;
    _pageId = null;
    _reason = null;
    _lastObservationHash = null;
    _generation += 1;
  }
}

final class P3BrowserActionVerifier {
  const P3BrowserActionVerifier._();

  static void requireStructuredResult(
    P3BrowserActionResult result, {
    bool requireObservationChange = false,
  }) {
    if (!_isSha256(result.beforeObservationHash) ||
        !_isSha256(result.afterObservationHash) ||
        result.observationChanged !=
            (result.beforeObservationHash != result.afterObservationHash)) {
      throw StateError('browser_action_verification_invalid');
    }
    if (requireObservationChange && !result.observationChanged) {
      throw StateError('browser_action_postcondition_not_met');
    }
    if (result.locatorStrategy.trim().isEmpty || result.locatorIndex < 0) {
      throw StateError('browser_action_locator_proof_invalid');
    }
  }

  static void requireVisualResult(P3BrowserVisualActionResult result) {
    if (!_isSha256(result.beforeObservationHash) ||
        !_isSha256(result.beforeScreenshotSha256)) {
      throw StateError('browser_visual_verification_invalid');
    }
    if (result.disposition == P3BrowserVisualActionDisposition.executed) {
      final afterObservation = result.afterObservationHash;
      final afterScreenshot = result.afterScreenshotSha256;
      if (!result.verified ||
          afterObservation == null ||
          afterScreenshot == null ||
          !_isSha256(afterObservation) ||
          !_isSha256(afterScreenshot) ||
          result.pauseReason != null ||
          result.observationChanged !=
              (result.beforeObservationHash != afterObservation)) {
        throw StateError('browser_visual_postcondition_not_met');
      }
      return;
    }
    if (result.verified ||
        result.afterObservationHash != null ||
        result.afterScreenshotSha256 != null ||
        (result.pauseReason?.trim().isEmpty ?? true)) {
      throw StateError('browser_visual_takeover_proof_invalid');
    }
  }
}

bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
