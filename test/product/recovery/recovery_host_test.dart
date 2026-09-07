// Behavioural proof for the staged self-repair boundary.
//
//   stage -> qualify -> activate -> post-activation verify -> keep or roll back
//
// Kristin repairing Kristin is the highest-risk path in the product, so the
// properties proven here are the ones that stop a bad candidate becoming a
// broken installation: a candidate that fails qualification is never
// activated, a candidate that activates but fails its health probe is rolled
// back automatically, last-known-good survives every path, and nothing
// overwrites the running version in place.

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/recovery/recovery_host.dart';

const _current = RecoveryVersionIdentity(
  version: '1.9.0',
  sourceIdentity: 'src-current',
  artifactIdentity: 'artifact-current',
);
const _candidate = RecoveryVersionIdentity(
  version: '1.9.1',
  sourceIdentity: 'src-candidate',
  artifactIdentity: 'artifact-candidate',
);

/// Records the protocol as it happens so ordering can be asserted, and lets a
/// test decide deterministically where the lifecycle should fail.
class _FakeHost implements KristinRecoveryHost {
  _FakeHost({this.qualifyHealthy = true, this.verifyHealthy = true});

  final bool qualifyHealthy;
  final bool verifyHealthy;
  final List<String> calls = <String>[];

  RecoveryVersionIdentity current = _current;
  RecoveryVersionIdentity lastKnownGood = _current;
  RecoveryVersionIdentity? candidate;
  RecoveryCandidateState candidateState = RecoveryCandidateState.none;
  int consecutiveStartupFailures = 0;
  String? rollbackReason;
  List<String> rollbackEvidence = const <String>[];

  @override
  Future<RecoveryHostState> inspect() async {
    calls.add('inspect');
    return _state();
  }

  @override
  Future<RecoveryHostState> stageCandidate({
    required RecoveryVersionIdentity candidate,
    required List<String> failureEvidence,
  }) async {
    calls.add('stage');
    this.candidate = candidate;
    candidateState = RecoveryCandidateState.staged;
    return _state();
  }

  @override
  Future<RecoveryCandidateProbe> qualifyCandidate(
    RecoveryVersionIdentity candidate,
  ) async {
    calls.add('qualify');
    candidateState = qualifyHealthy
        ? RecoveryCandidateState.qualified
        : RecoveryCandidateState.rejected;
    return RecoveryCandidateProbe(
      healthy: qualifyHealthy,
      checks: <String, bool>{'builds': qualifyHealthy},
      evidenceReferences: const <String>['qualify-log'],
    );
  }

  @override
  Future<RecoveryHostState> activateCandidate(
    RecoveryVersionIdentity candidate,
  ) async {
    calls.add('activate');
    // The running version is replaced, but last-known-good is retained so a
    // rollback target always exists.
    current = candidate;
    candidateState = RecoveryCandidateState.active;
    return _state();
  }

  @override
  Future<RecoveryCandidateProbe> verifyActiveVersion() async {
    calls.add('verify');
    if (!verifyHealthy) consecutiveStartupFailures += 1;
    return RecoveryCandidateProbe(
      healthy: verifyHealthy,
      checks: <String, bool>{'starts': verifyHealthy},
      evidenceReferences: const <String>['health-probe'],
    );
  }

  @override
  Future<RecoveryHostState> rollbackToLastKnownGood({
    required String reason,
    required List<String> evidenceReferences,
  }) async {
    calls.add('rollback');
    rollbackReason = reason;
    rollbackEvidence = evidenceReferences;
    current = lastKnownGood;
    candidateState = RecoveryCandidateState.rolledBack;
    return _state();
  }

  RecoveryHostState _state() => RecoveryHostState(
        current: current,
        lastKnownGood: lastKnownGood,
        candidate: candidate,
        candidateState: candidateState,
        consecutiveStartupFailures: consecutiveStartupFailures,
        health: consecutiveStartupFailures >= 3
            ? RecoveryHostHealth.crashLoop
            : RecoveryHostHealth.healthy,
      );
}

void main() {
  group('staged lifecycle ordering', () {
    test('a healthy candidate is staged, qualified, activated then verified',
        () async {
      final host = _FakeHost();
      final state =
          await StagedSelfRepairCoordinator(host).activateVerifiedCandidate(
        _candidate,
        failureEvidence: const <String>['failure-1'],
      );

      expect(host.calls, <String>[
        'stage',
        'qualify',
        'activate',
        'verify',
        'inspect',
      ]);
      expect(state.current.version, '1.9.1');
      expect(state.candidateState, RecoveryCandidateState.active);
    });

    test('verification always follows activation, never precedes it', () async {
      final host = _FakeHost();
      await StagedSelfRepairCoordinator(host).activateVerifiedCandidate(
        _candidate,
        failureEvidence: const <String>[],
      );
      expect(
        host.calls.indexOf('verify'),
        greaterThan(host.calls.indexOf('activate')),
      );
    });
  });

  group('a candidate that cannot be trusted is never activated', () {
    test('failing pre-activation qualification skips activation entirely',
        () async {
      final host = _FakeHost(qualifyHealthy: false);
      final state =
          await StagedSelfRepairCoordinator(host).activateVerifiedCandidate(
        _candidate,
        failureEvidence: const <String>['failure-1'],
      );

      expect(host.calls, isNot(contains('activate')));
      expect(host.calls, contains('rollback'));
      expect(
          host.rollbackReason, 'candidate_failed_pre_activation_qualification');
      expect(state.current.version, '1.9.0',
          reason: 'the running version is untouched');
      expect(state.candidateState, RecoveryCandidateState.rolledBack);
    });

    test('a rejected candidate still records why, as evidence', () async {
      final host = _FakeHost(qualifyHealthy: false);
      await StagedSelfRepairCoordinator(host).activateVerifiedCandidate(
        _candidate,
        failureEvidence: const <String>['failure-1'],
      );
      expect(host.rollbackEvidence, contains('qualify-log'));
    });
  });

  group('a candidate that activates but is unhealthy rolls back', () {
    test('post-activation health failure restores last-known-good', () async {
      final host = _FakeHost(verifyHealthy: false);
      final state =
          await StagedSelfRepairCoordinator(host).activateVerifiedCandidate(
        _candidate,
        failureEvidence: const <String>['failure-1'],
      );

      expect(host.calls, contains('activate'));
      expect(host.calls, contains('rollback'));
      expect(host.rollbackReason, 'candidate_failed_post_activation_health');
      expect(state.current.version, '1.9.0');
      expect(state.current.artifactIdentity, 'artifact-current');
      expect(host.rollbackEvidence, contains('health-probe'));
    });

    test('activating a candidate does not destroy the rollback target',
        () async {
      final host = _FakeHost(verifyHealthy: false);
      await StagedSelfRepairCoordinator(host).activateVerifiedCandidate(
        _candidate,
        failureEvidence: const <String>[],
      );
      // last-known-good is what makes rollback possible; a self-repair that
      // overwrote it in place would be self-corruption.
      expect(host.lastKnownGood.version, '1.9.0');
      expect(host.lastKnownGood.artifactIdentity, 'artifact-current');
    });
  });

  group('crash-loop detection is bounded, not open-ended', () {
    test('three consecutive startup failures raise a crash loop', () {
      const state = RecoveryHostState(
        current: _candidate,
        lastKnownGood: _current,
        consecutiveStartupFailures: 3,
      );
      expect(state.crashLoopDetected, isTrue);
      expect(state.toJson()['crashLoopDetected'], isTrue);
    });

    test('an explicit crashLoop health is honoured regardless of the counter',
        () {
      const state = RecoveryHostState(
        current: _candidate,
        lastKnownGood: _current,
        health: RecoveryHostHealth.crashLoop,
      );
      expect(state.crashLoopDetected, isTrue);
    });

    test('a healthy host below the threshold is not a crash loop', () {
      const state = RecoveryHostState(
        current: _current,
        lastKnownGood: _current,
        health: RecoveryHostHealth.healthy,
        consecutiveStartupFailures: 2,
      );
      expect(state.crashLoopDetected, isFalse);
    });
  });

  group('durable host state is serializable evidence', () {
    test('state records both the running and the rollback version', () {
      const state = RecoveryHostState(
        current: _candidate,
        lastKnownGood: _current,
        candidate: _candidate,
        candidateState: RecoveryCandidateState.active,
      );
      final json = state.toJson();
      expect((json['current']! as Map)['version'], '1.9.1');
      expect((json['lastKnownGood']! as Map)['version'], '1.9.0');
      expect(json['candidateState'], 'active');
    });

    test('a host with no candidate omits the candidate entry', () {
      const state = RecoveryHostState(
        current: _current,
        lastKnownGood: _current,
      );
      expect(state.toJson().containsKey('candidate'), isFalse);
    });
  });
}
