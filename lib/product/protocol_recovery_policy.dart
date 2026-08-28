// Protocol recovery: stop paying for the same wrong answer twice.
//
// The failure this exists for, observed with a local model at roughly
// 80 seconds per response:
//
//   turn 1  {"action":{"tool":"create_project"}}   -> invalid
//   turn 2  ask the model to correct itself         -> ~80s
//   turn 3  {"action":"create_project"}             -> invalid, same thing
//   turn 4  ask the model to correct itself         -> ~80s
//   turn 5  {"action":{"type":"create_project"}}    -> invalid, same thing
//           -> model_protocol_exhausted
//
// Every one of those turns was "bounded". Together they burned minutes
// and produced no effect. A bound on the NUMBER of corrections is not a
// bound on wasted time, because it cannot tell a model that is making
// progress from one that is restating the same impossible action in a
// new shape.
//
// So this policy asks a different question: has anything actually
// changed? It tracks the SEMANTICS of each invalid decision, not its
// bytes. Rewording the same rejected action is not new information, and
// does not earn another expensive round trip.
//
// Deliberately pure: no I/O, no model, no clock of its own (the caller
// supplies elapsed time), so the whole policy is deterministically
// testable without sleeping.
import 'crypto_utils.dart';

/// What the Runner should do about an invalid model decision.
enum ProtocolRecoveryAction {
  /// Ask the model to correct itself. Worth a round trip: this is new.
  requestCorrection,

  /// Do not ask again. Run the deterministic fallback if one exists.
  useDeterministicFallback,

  /// Stop this work item with a protocol-incompatibility diagnostic.
  stop,
}

/// The decision plus the evidence behind it.
class ProtocolRecoveryDecision {
  const ProtocolRecoveryDecision({
    required this.action,
    required this.reason,
    required this.signature,
    required this.repeated,
    required this.attempts,
    required this.elapsed,
  });

  final ProtocolRecoveryAction action;

  /// Human-readable, safe to show as live status.
  final String reason;

  /// The normalized identity of the invalid decision.
  final String signature;

  /// True when this exact invalid decision has been seen before.
  final bool repeated;

  final int attempts;
  final Duration elapsed;

  Map<String, dynamic> toEvidence() => <String, dynamic>{
        'recoveryAction': action.name,
        'invalidDecisionSignature': signature,
        'repeatedInvalidDecision': repeated,
        'protocolRepairAttempts': attempts,
        'protocolRecoveryElapsedMs': elapsed.inMilliseconds,
      };
}

/// Bounded, progress-aware protocol recovery for one work item.
///
/// Reset semantics are the point. [recordProgress] is called only when
/// something real happened -- a schema-valid decision, a governed tool
/// action, new evidence. It is NOT called because another response
/// arrived or because the bytes changed.
class ProtocolRecoveryPolicy {
  ProtocolRecoveryPolicy({
    this.maxCorrectionRequests = 2,
    this.maxRecoveryWithoutProgress = const Duration(minutes: 6),
  });

  /// How many times a genuinely NEW invalid decision may be corrected.
  final int maxCorrectionRequests;

  /// How long the run may stay in protocol recovery without a single
  /// valid decision.
  ///
  /// This measures recovery time only, never total task time, so a
  /// legitimately slow local model working correctly is unaffected: the
  /// clock starts at the first invalid response and is cleared by any
  /// real progress. Generous enough for two ~80s round trips plus
  /// overhead, tight enough that a stuck run does not idle for many
  /// minutes.
  final Duration maxRecoveryWithoutProgress;

  final Set<String> _seenSignatures = <String>{};
  int _attempts = 0;
  Duration _elapsedAtFirstFailure = Duration.zero;
  bool _recovering = false;

  int get attempts => _attempts;
  bool get isRecovering => _recovering;

  /// The normalized identity of an invalid decision.
  ///
  /// Built from what the model MEANT, not how it wrote it: the error
  /// code, the action it named, and the tool it asked for. So
  /// `{"action":{"tool":"create_project"}}` and
  /// `{"action":"create_project"}` collapse to one signature -- they are
  /// the same impossible request twice.
  static String signatureFor({
    required String errorCode,
    Object? receivedAction,
    Object? requestedTool,
  }) {
    String norm(Object? value) {
      if (value == null) return '';
      final text = value is Iterable
          ? (value.map((item) => item.toString()).toList()..sort()).join(',')
          : value.toString();
      return text
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9,]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
    }

    return Sha256.text(
      <String>[
        norm(errorCode),
        norm(receivedAction),
        norm(requestedTool),
      ].join('|'),
    );
  }

  /// Records a genuinely invalid decision and decides what to do next.
  ///
  /// [elapsed] is the caller's own elapsed run/turn clock; the policy
  /// derives recovery-only time from it rather than keeping its own.
  ProtocolRecoveryDecision onInvalidDecision({
    required String errorCode,
    Object? receivedAction,
    Object? requestedTool,
    required Duration elapsed,
    required bool fallbackAvailable,
  }) {
    if (!_recovering) {
      _recovering = true;
      _elapsedAtFirstFailure = elapsed;
    }
    final signature = signatureFor(
      errorCode: errorCode,
      receivedAction: receivedAction,
      requestedTool: requestedTool,
    );
    final repeated = !_seenSignatures.add(signature);
    final recoveryElapsed = elapsed - _elapsedAtFirstFailure;

    ProtocolRecoveryDecision decide(
      ProtocolRecoveryAction action,
      String reason,
    ) =>
        ProtocolRecoveryDecision(
          action: action,
          reason: reason,
          signature: signature,
          repeated: repeated,
          attempts: _attempts,
          elapsed: recoveryElapsed,
        );

    if (repeated) {
      // Asking again cannot help: the model already saw the correction
      // and answered with the same thing in different clothes.
      return decide(
        fallbackAvailable
            ? ProtocolRecoveryAction.useDeterministicFallback
            : ProtocolRecoveryAction.stop,
        'The model repeated the same invalid action after a correction.',
      );
    }
    if (recoveryElapsed >= maxRecoveryWithoutProgress) {
      return decide(
        fallbackAvailable
            ? ProtocolRecoveryAction.useDeterministicFallback
            : ProtocolRecoveryAction.stop,
        'Protocol recovery has run for '
        '${recoveryElapsed.inSeconds}s without a valid action.',
      );
    }
    if (_attempts >= maxCorrectionRequests) {
      return decide(
        fallbackAvailable
            ? ProtocolRecoveryAction.useDeterministicFallback
            : ProtocolRecoveryAction.stop,
        'The model did not produce a valid action within '
        '$maxCorrectionRequests corrections.',
      );
    }
    _attempts += 1;
    return decide(
      ProtocolRecoveryAction.requestCorrection,
      'The requested action is not available for this work item; asking '
      'the model to choose from the allowed tools.',
    );
  }

  /// Clears recovery state because something real happened.
  ///
  /// Call ONLY for actual progress: a schema-valid decision, a governed
  /// tool action, new objective evidence, a deterministic recovery action
  /// that changed state. Never because a new response arrived.
  void recordProgress() {
    _seenSignatures.clear();
    _attempts = 0;
    _recovering = false;
    _elapsedAtFirstFailure = Duration.zero;
  }
}
