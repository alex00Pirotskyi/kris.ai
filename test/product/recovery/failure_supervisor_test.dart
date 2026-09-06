// Behavioural proof for the autonomic recovery supervisor.
//
// These tests drive the real FailureSupervisor across its real decision,
// actuation, verification and resume boundaries. Only the leaf collaborators
// are fakes, and they are deterministic: no sleeps, no timers, no wall-clock
// races. The property under test throughout is that recovery is bounded and
// that original work resumes only on proven success, exactly once.

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/recovery/failure_recovery.dart';
import 'package:kristin_local_agent/product/self_awareness/capability_self_model.dart';

// --- minimal self-model wiring -------------------------------------------

class _Provider implements KristinCapabilityProvider {
  _Provider(this.providerId, this._descriptors);
  @override
  final String providerId;
  final List<CapabilityDescriptor> _descriptors;

  @override
  Iterable<CapabilityDescriptor> describeCapabilities() => _descriptors;

  @override
  Future<CapabilityAvailability> resolveAvailability(
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
  ) async => CapabilityAvailability(
    capabilityId: descriptor.id,
    state: CapabilityAvailabilityState.available,
    observedAt: DateTime.now().toUtc(),
  );
}

class _App implements ApplicationSnapshotProvider {
  @override
  Future<ApplicationSnapshot> capture({
    bool forceRefresh = false,
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) async => ApplicationSnapshot(
    capturedAt: DateTime.utc(2026, 1, 1),
    applicationIdentity: 'kris.ai',
    platform: 'linux',
  );
}

KristinSelfModelService _selfModel({List<String> capabilityIds = const []}) {
  final registry = KristinCapabilityRegistry()
    ..register(
      _Provider('test', <CapabilityDescriptor>[
        for (final id in capabilityIds)
          CapabilityDescriptor(
            id: id,
            name: id,
            description: id,
            category: 'recovery',
            providerId: 'test',
            freshnessBudget: const Duration(days: 3650),
            healthFreshnessBudget: const Duration(days: 3650),
          ),
      ]),
    );
  return KristinSelfModelService(registry: registry, application: _App());
}

// --- recording fakes ------------------------------------------------------

class _Journal implements FailureJournal {
  final List<FailureEvent> failures = <FailureEvent>[];
  final List<RecoveryAttempt> attempts = <RecoveryAttempt>[];
  @override
  Future<void> recordFailure(FailureEvent event) async => failures.add(event);
  @override
  Future<void> recordAttempt(RecoveryAttempt attempt) async =>
      attempts.add(attempt);
}

class _Events implements RecoveryEventSink {
  final List<String> types = <String>[];
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
  @override
  Future<void> emit(String type, Map<String, Object?> payload) async {
    types.add(type);
    payloads.add(payload);
  }
}

class _Router implements RecoveryTaskRouter {
  _Router({this.workResult, this.onContinue});
  final RecoveryActionResult? workResult;
  final void Function()? onContinue;
  int continued = 0;
  int recoveryWork = 0;
  RecoveryObjective? lastObjective;

  @override
  Future<RecoveryActionResult> runRecoveryWork(
    RecoveryObjective objective,
  ) async {
    recoveryWork += 1;
    lastObjective = objective;
    return workResult ??
        const RecoveryActionResult(
          summary: 'kernel repair complete',
          materialProgress: true,
        );
  }

  @override
  Future<RecoveryActionResult> continueOriginalTask(FailureEvent failure) async {
    continued += 1;
    onContinue?.call();
    return const RecoveryActionResult(summary: 'original task resumed');
  }
}

class _Actuator implements RecoveryActuator {
  _Actuator({this.throwOnPerform = false, this.result});
  final bool throwOnPerform;
  final RecoveryActionResult? result;
  int performed = 0;
  int rolledBack = 0;
  final List<String> strategies = <String>[];

  @override
  Future<RecoveryActionResult> perform(
    RecoveryDecision decision,
    FailureEvent failure,
  ) async {
    performed += 1;
    strategies.add(decision.strategyId);
    if (throwOnPerform) {
      throw StateError('actuator exploded');
    }
    return result ??
        const RecoveryActionResult(
          summary: 'action performed',
          materialProgress: true,
        );
  }

  @override
  Future<RecoveryActionResult> rollback(
    RecoveryDecision decision,
    FailureEvent failure,
    RecoveryActionResult action,
  ) async {
    rolledBack += 1;
    return const RecoveryActionResult(summary: 'rolled back');
  }
}

class _Verifier implements RecoveryVerifier {
  _Verifier(this._behaviour);
  final Future<RecoveryVerification> Function() _behaviour;
  int calls = 0;

  @override
  Future<RecoveryVerification> verify(
    FailureEvent originalFailure,
    RecoveryActionResult action,
  ) {
    calls += 1;
    return _behaviour();
  }

  static _Verifier passing() => _Verifier(
        () async => const RecoveryVerification(
          passed: true,
          check: 'original_failure_absent',
          observed: 'the original failure condition is gone',
          materialProgress: true,
        ),
      );

  static _Verifier failing() => _Verifier(
        () async => const RecoveryVerification(
          passed: false,
          check: 'original_failure_absent',
          observed: 'the original failure condition is still present',
        ),
      );

  static _Verifier throwing() =>
      _Verifier(() async => throw StateError('verifier exploded'));
}

class _AllowAuthority implements RecoveryAuthorityGate {
  @override
  Future<RecoveryAuthorityEvaluation> evaluate(
    FailureEvent failure,
    RecoveryDecision decision,
  ) async => const RecoveryAuthorityEvaluation(
    allowed: true,
    reason: 'test grants authority',
  );
}

class _DenyAuthority implements RecoveryAuthorityGate {
  @override
  Future<RecoveryAuthorityEvaluation> evaluate(
    FailureEvent failure,
    RecoveryDecision decision,
  ) async => const RecoveryAuthorityEvaluation(
    allowed: false,
    reason: 'authority is not granted',
    missing: <String>{'owner'},
  );
}

class _SelfRepair implements RecoverySelfRepairCoordinator {
  int performed = 0;
  @override
  Future<RecoveryActionResult> perform(
    RecoveryDecision decision,
    FailureEvent failure,
  ) async {
    performed += 1;
    return const RecoveryActionResult(summary: 'staged candidate activated');
  }
}

// --- fixtures -------------------------------------------------------------

FailureEvent _transient({String message = 'connection reset', String? runId}) =>
    FailureEvent(
      severity: FailureSeverity.error,
      category: FailureCategory.transient,
      subsystem: 'provider',
      operation: 'complete',
      message: message,
      runId: runId,
    );

FailureSupervisor _supervisor({
  required _Journal journal,
  required _Events events,
  required _Router router,
  required _Actuator actuator,
  required _Verifier verifier,
  RecoveryAuthorityGate? authority,
  RecoverySelfRepairCoordinator? selfRepair,
  RecoveryPolicy policy = const RecoveryPolicy(),
  List<String> capabilityIds = const <String>[],
}) {
  return FailureSupervisor(
    selfModel: _selfModel(capabilityIds: capabilityIds),
    journal: journal,
    events: events,
    router: router,
    actuator: actuator,
    verifier: verifier,
    authority: authority ?? _AllowAuthority(),
    selfRepair: selfRepair,
    policy: policy,
  );
}

void main() {
  group('verify before resume', () {
    test('a successful action alone does not resume the original task', () async {
      final router = _Router();
      final actuator = _Actuator();
      final verifier = _Verifier.failing();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: router,
        actuator: actuator,
        verifier: verifier,
      );

      final result = await supervisor.handle(_transient(runId: 'run-1'));

      expect(actuator.performed, 1, reason: 'the action did run');
      expect(verifier.calls, 1, reason: 'and was verified');
      expect(result?.passed, isFalse);
      expect(router.continued, 0,
          reason: 'a performed action is not proof of repair');
    });

    test('a verifier that throws does not resume the original task', () async {
      final router = _Router();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: router,
        actuator: _Actuator(),
        verifier: _Verifier.throwing(),
      );

      await expectLater(
        supervisor.handle(_transient(runId: 'run-1')),
        throwsA(isA<StateError>()),
      );
      expect(router.continued, 0);
    });

    test('an actuator that throws does not resume the original task', () async {
      final router = _Router();
      final verifier = _Verifier.passing();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: router,
        actuator: _Actuator(throwOnPerform: true),
        verifier: verifier,
      );

      await supervisor.handle(_transient(runId: 'run-1'));

      expect(verifier.calls, 0, reason: 'nothing was produced to verify');
      expect(router.continued, 0);
    });

    test('successful verification resumes the original task exactly once',
        () async {
      final router = _Router();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: router,
        actuator: _Actuator(),
        verifier: _Verifier.passing(),
      );

      final result = await supervisor.handle(_transient(runId: 'run-1'));

      expect(result?.passed, isTrue);
      expect(router.continued, 1);
    });

    test('a failure carrying no run id resumes nothing', () async {
      final router = _Router();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: router,
        actuator: _Actuator(),
        verifier: _Verifier.passing(),
      );

      final result = await supervisor.handle(_transient());

      expect(result?.passed, isTrue);
      expect(router.continued, 0,
          reason: 'there is no original governed run to continue');
    });

    test('resume happens after verification, never before it', () async {
      // Ordering, not timing: the verifier records how many resumes had
      // happened at the moment it was consulted. It must always be zero.
      final router = _Router();
      var continuedWhenVerified = -1;
      late final _Router captured;
      final verifier = _Verifier(() async {
        continuedWhenVerified = captured.continued;
        return const RecoveryVerification(
          passed: true,
          check: 'original_failure_absent',
          observed: 'the original failure condition is gone',
          materialProgress: true,
        );
      });
      captured = router;

      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: router,
        actuator: _Actuator(),
        verifier: verifier,
      );

      await supervisor.handle(_transient(runId: 'run-1'));

      expect(continuedWhenVerified, 0,
          reason: 'nothing may resume before verification returns');
      expect(router.continued, 1);
    });
  });

  group('bounded recovery', () {
    test('the attempt budget for one signature is enforced', () async {
      final actuator = _Actuator();
      final events = _Events();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: events,
        router: _Router(),
        actuator: actuator,
        verifier: _Verifier.failing(),
        policy: const RecoveryPolicy(maxAttemptsPerFailureSignature: 2),
      );

      // Same underlying failure, distinct event ids: the signature is what
      // binds them together.
      for (var i = 0; i < 6; i++) {
        await supervisor.handle(_transient(runId: 'run-1'));
      }

      expect(actuator.performed, lessThanOrEqualTo(2),
          reason: 'ineffective recovery must terminate, not loop');
      // Exhaustion is surfaced, not swallowed: the supervisor escalates and
      // returns null rather than continuing to actuate.
      expect(events.types, contains('recovery_escalated'));
      expect(await supervisor.handle(_transient(runId: 'run-1')), isNull);
      expect(actuator.performed, lessThanOrEqualTo(2));
    });

    test('a repeated ineffective strategy escalates instead of repeating',
        () async {
      final actuator = _Actuator();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: _Router(),
        actuator: actuator,
        verifier: _Verifier.failing(),
        policy: const RecoveryPolicy(maxAttemptsPerFailureSignature: 4),
      );

      await supervisor.handle(_transient(runId: 'run-1'));
      await supervisor.handle(_transient(runId: 'run-1'));

      expect(actuator.strategies.length, 2);
      expect(actuator.strategies.first, 'refresh_and_retry');
      expect(actuator.strategies[1], isNot('refresh_and_retry'),
          reason: 'the ladder must climb rather than retry the same strategy');
    });

    test('a materially different failure is judged on its own budget',
        () async {
      final actuator = _Actuator();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: _Router(),
        actuator: actuator,
        verifier: _Verifier.failing(),
        policy: const RecoveryPolicy(maxAttemptsPerFailureSignature: 1),
      );

      await supervisor.handle(_transient(message: 'connection reset'));
      final performedAfterFirst = actuator.performed;
      await supervisor.handle(_transient(message: 'no space left on device'));

      expect(actuator.performed, greaterThan(performedAfterFirst),
          reason: 'a different signature is not covered by the first budget');
    });
  });

  group('authority is enforced before anything is actuated', () {
    test('a denied authority gate blocks actuation entirely', () async {
      final actuator = _Actuator();
      final router = _Router();
      final events = _Events();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: events,
        router: router,
        actuator: actuator,
        verifier: _Verifier.passing(),
        authority: _DenyAuthority(),
      );

      final result = await supervisor.handle(_transient(runId: 'run-1'));

      expect(result?.passed, isFalse);
      expect(actuator.performed, 0);
      expect(router.continued, 0);
      expect(events.types, contains('recovery_preflight_blocked'));
    });

    test('the fail-closed gate refuses any strategy that needs authority',
        () async {
      const gate = FailClosedRecoveryAuthorityGate();
      final needsAuthority = await gate.evaluate(
        _transient(),
        const RecoveryDecision(
          kind: RecoveryDecisionKind.selfRepair,
          level: RecoveryLevel.l4SelfRepair,
          strategyId: 'staged_self_repair',
          reason: 'test',
          requiredAuthority: <String>{'owner'},
        ),
      );
      expect(needsAuthority.allowed, isFalse);
      expect(needsAuthority.notEvaluated, contains('owner'));

      final needsNothing = await gate.evaluate(
        _transient(),
        const RecoveryDecision(
          kind: RecoveryDecisionKind.retry,
          level: RecoveryLevel.l0Transient,
          strategyId: 'refresh_and_retry',
          reason: 'test',
        ),
      );
      expect(needsNothing.allowed, isTrue);
    });
  });

  group('L3 repair routes through the Universal Task Kernel', () {
    test('substantial repair uses the router, never the raw actuator',
        () async {
      final router = _Router();
      final actuator = _Actuator();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: router,
        actuator: actuator,
        verifier: _Verifier.passing(),
        capabilityIds: <String>['agent.fix_project'],
      );

      final failure = FailureEvent(
        severity: FailureSeverity.error,
        category: FailureCategory.execution,
        subsystem: 'runner',
        operation: 'apply_patch',
        message: 'the patch did not apply',
        recoverability: Recoverability.repairable,
        runId: 'run-7',
        taskId: 'task-7',
      );
      await supervisor.handle(failure);

      expect(router.recoveryWork, 1, reason: 'repair went through the kernel');
      expect(actuator.performed, 0, reason: 'no parallel repair path');
    });

    test('the recovery objective preserves originating failure and lineage',
        () async {
      final router = _Router();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: router,
        actuator: _Actuator(),
        verifier: _Verifier.passing(),
        capabilityIds: <String>['agent.fix_project'],
      );

      final failure = FailureEvent(
        severity: FailureSeverity.error,
        category: FailureCategory.execution,
        subsystem: 'runner',
        operation: 'apply_patch',
        message: 'the patch did not apply',
        recoverability: Recoverability.repairable,
        runId: 'run-7',
        taskId: 'task-7',
      );
      await supervisor.handle(failure);

      final objective = router.lastObjective;
      expect(objective, isNotNull);
      expect(objective!.failure.id, failure.id);
      expect(objective.originalRunId, 'run-7');
      expect(objective.originalTaskId, 'task-7');
      expect(objective.level, RecoveryLevel.l3CodeRepair);
    });

    test('self-context reaches the kernel as context, carrying no tool list',
        () async {
      final router = _Router();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: router,
        actuator: _Actuator(),
        verifier: _Verifier.passing(),
        capabilityIds: <String>['agent.fix_project'],
      );

      await supervisor.handle(
        FailureEvent(
          severity: FailureSeverity.error,
          category: FailureCategory.execution,
          subsystem: 'runner',
          operation: 'apply_patch',
          message: 'the patch did not apply',
          recoverability: Recoverability.repairable,
          runId: 'run-7',
        ),
      );

      final context = router.lastObjective!.selfContext;
      final json = context.toJson();
      expect(json.containsKey('allowedTools'), isFalse);
      expect(json.containsKey('runnerTools'), isFalse);
      expect(context.currentAuthority, isEmpty,
          reason: 'planning context reports authority, it does not grant it');
    });
  });

  group('staged self-repair boundary', () {
    test('L4 fails closed when no coordinator is installed', () async {
      final actuator = _Actuator();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: _Router(),
        actuator: actuator,
        verifier: _Verifier.passing(),
        capabilityIds: <String>['owner.recovery.actuate'],
      );

      final result = await supervisor.handle(
        FailureEvent(
          severity: FailureSeverity.critical,
          category: FailureCategory.application,
          subsystem: 'kristin',
          operation: 'boot',
          message: 'the application will not start',
          recoverability: Recoverability.selfRepairCandidate,
          runId: 'run-9',
        ),
      );

      expect(result?.passed, isFalse);
      expect(actuator.performed, 0,
          reason: 'self-repair must never fall back to ordinary actuation');
    });

    test('an installed coordinator is used instead of the actuator', () async {
      final coordinator = _SelfRepair();
      final actuator = _Actuator();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: _Router(),
        actuator: actuator,
        verifier: _Verifier.passing(),
        authority: _AllowAuthority(),
        selfRepair: coordinator,
        capabilityIds: <String>['owner.recovery.actuate'],
      );

      await supervisor.handle(
        FailureEvent(
          severity: FailureSeverity.critical,
          category: FailureCategory.application,
          subsystem: 'kristin',
          operation: 'boot',
          message: 'the application will not start',
          recoverability: Recoverability.selfRepairCandidate,
          runId: 'run-9',
        ),
      );

      expect(coordinator.performed, 1);
      expect(actuator.performed, 0);
    });
  });

  group('durable evidence', () {
    test('failure, attempts and outcome are journalled', () async {
      final journal = _Journal();
      final events = _Events();
      final supervisor = _supervisor(
        journal: journal,
        events: events,
        router: _Router(),
        actuator: _Actuator(),
        verifier: _Verifier.passing(),
      );

      await supervisor.handle(_transient(runId: 'run-1'));

      expect(journal.failures, hasLength(1));
      expect(journal.attempts, isNotEmpty);
      expect(events.types, contains('failure_detected'));
      expect(events.types, contains('failure_classified'));
      expect(events.types, contains('recovery_started'));
      expect(events.types, contains('recovery_verified'));
      expect(events.types, contains('original_task_resumed'));
      expect(
        journal.attempts.last.state,
        RecoveryAttemptState.succeeded,
      );
    });

    test('a failed verification is journalled as failed, not silently dropped',
        () async {
      final journal = _Journal();
      final events = _Events();
      final supervisor = _supervisor(
        journal: journal,
        events: events,
        router: _Router(),
        actuator: _Actuator(),
        verifier: _Verifier.failing(),
      );

      await supervisor.handle(_transient(runId: 'run-1'));

      expect(events.types, contains('recovery_failed'));
      expect(events.types, isNot(contains('original_task_resumed')));
    });
  });
}
