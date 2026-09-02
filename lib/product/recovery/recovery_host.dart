enum RecoveryHostHealth { unknown, healthy, degraded, failed, crashLoop }
enum RecoveryCandidateState { none, staged, qualifying, qualified, active, rejected, rolledBack }

final class RecoveryVersionIdentity {
  const RecoveryVersionIdentity({
    required this.version,
    required this.sourceIdentity,
    required this.artifactIdentity,
  });
  final String version;
  final String sourceIdentity;
  final String artifactIdentity;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'sourceIdentity': sourceIdentity,
        'artifactIdentity': artifactIdentity,
      };
}

/// Durable state owned by an independent recovery boundary, not by the
/// currently executing primary Kristin process.
final class RecoveryHostState {
  const RecoveryHostState({
    required this.current,
    required this.lastKnownGood,
    this.candidate,
    this.health = RecoveryHostHealth.unknown,
    this.candidateState = RecoveryCandidateState.none,
    this.startupAttemptCount = 0,
    this.consecutiveStartupFailures = 0,
    this.lastFailureEvidence = const <String>[],
    this.updatedAt,
  });

  final RecoveryVersionIdentity current;
  final RecoveryVersionIdentity lastKnownGood;
  final RecoveryVersionIdentity? candidate;
  final RecoveryHostHealth health;
  final RecoveryCandidateState candidateState;
  final int startupAttemptCount;
  final int consecutiveStartupFailures;
  final List<String> lastFailureEvidence;
  final DateTime? updatedAt;

  bool get crashLoopDetected =>
      health == RecoveryHostHealth.crashLoop || consecutiveStartupFailures >= 3;

  Map<String, Object?> toJson() => <String, Object?>{
        'current': current.toJson(),
        'lastKnownGood': lastKnownGood.toJson(),
        if (candidate != null) 'candidate': candidate!.toJson(),
        'health': health.name,
        'candidateState': candidateState.name,
        'startupAttemptCount': startupAttemptCount,
        'consecutiveStartupFailures': consecutiveStartupFailures,
        'crashLoopDetected': crashLoopDetected,
        'lastFailureEvidence': lastFailureEvidence,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}

final class RecoveryCandidateProbe {
  const RecoveryCandidateProbe({
    required this.healthy,
    required this.checks,
    this.evidenceReferences = const <String>[],
  });
  final bool healthy;
  final Map<String, bool> checks;
  final List<String> evidenceReferences;
}

/// Staged L4 self-repair seam.
///
/// Implementations must run outside the primary process whose artifact is
/// being repaired. A candidate is staged, built/qualified/probed, activated,
/// re-probed, and rolled back automatically if post-activation health fails.
/// No implementation may overwrite the currently executing installation in
/// place without preserving [lastKnownGood].
abstract interface class KristinRecoveryHost {
  Future<RecoveryHostState> inspect();

  Future<RecoveryHostState> stageCandidate({
    required RecoveryVersionIdentity candidate,
    required List<String> failureEvidence,
  });

  Future<RecoveryCandidateProbe> qualifyCandidate(
    RecoveryVersionIdentity candidate,
  );

  Future<RecoveryHostState> activateCandidate(
    RecoveryVersionIdentity candidate,
  );

  Future<RecoveryCandidateProbe> verifyActiveVersion();

  Future<RecoveryHostState> rollbackToLastKnownGood({
    required String reason,
    required List<String> evidenceReferences,
  });
}

/// Coordinates the switch/rollback protocol without granting the authority to
/// perform it. The supplied host must already be running in the independent,
/// governed recovery boundary.
final class StagedSelfRepairCoordinator {
  const StagedSelfRepairCoordinator(this.host);
  final KristinRecoveryHost host;

  Future<RecoveryHostState> activateVerifiedCandidate(
    RecoveryVersionIdentity candidate, {
    required List<String> failureEvidence,
  }) async {
    await host.stageCandidate(
      candidate: candidate,
      failureEvidence: failureEvidence,
    );
    final preActivation = await host.qualifyCandidate(candidate);
    if (!preActivation.healthy) {
      return host.rollbackToLastKnownGood(
        reason: 'candidate_failed_pre_activation_qualification',
        evidenceReferences: preActivation.evidenceReferences,
      );
    }
    await host.activateCandidate(candidate);
    final postActivation = await host.verifyActiveVersion();
    if (!postActivation.healthy) {
      return host.rollbackToLastKnownGood(
        reason: 'candidate_failed_post_activation_health',
        evidenceReferences: postActivation.evidenceReferences,
      );
    }
    return host.inspect();
  }
}
