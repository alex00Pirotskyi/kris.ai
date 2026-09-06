// Deterministic fault injection across the real supervisory boundary.
//
// Each case injects a realistic runtime fault as a structured failure and
// drives the actual FailureSupervisor. What is asserted is not "a method was
// called" but the safety-relevant outcome: which rung of the ladder was
// chosen, whether anything was actuated at all, and whether the original task
// was allowed to resume. No sleeps and no timers -- every fake resolves
// immediately, so ordering is the only thing under test.

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/recovery/failure_recovery.dart';
import 'package:kristin_local_agent/product/self_awareness/capability_self_model.dart';

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

class _Journal implements FailureJournal {
  final List<RecoveryAttempt> attempts = <RecoveryAttempt>[];
  @override
  Future<void> recordFailure(FailureEvent event) async {}
  @override
  Future<void> recordAttempt(RecoveryAttempt attempt) async =>
      attempts.add(attempt);
}

class _Events implements RecoveryEventSink {
  final List<String> types = <String>[];
  @override
  Future<void> emit(String type, Map<String, Object?> payload) async =>
      types.add(type);
}

class _Router implements RecoveryTaskRouter {
  int continued = 0;
  int recoveryWork = 0;
  @override
  Future<RecoveryActionResult> runRecoveryWork(
    RecoveryObjective objective,
  ) async {
    recoveryWork += 1;
    return const RecoveryActionResult(
      summary: 'kernel work complete',
      materialProgress: true,
    );
  }

  @override
  Future<RecoveryActionResult> continueOriginalTask(
    FailureEvent failure,
  ) async {
    continued += 1;
    return const RecoveryActionResult(summary: 'resumed');
  }
}

class _Actuator implements RecoveryActuator {
  final List<RecoveryLevel> levels = <RecoveryLevel>[];
  int performed = 0;

  @override
  Future<RecoveryActionResult> perform(
    RecoveryDecision decision,
    FailureEvent failure,
  ) async {
    performed += 1;
    levels.add(decision.level);
    return const RecoveryActionResult(
      summary: 'performed',
      materialProgress: true,
    );
  }

  @override
  Future<RecoveryActionResult> rollback(
    RecoveryDecision decision,
    FailureEvent failure,
    RecoveryActionResult action,
  ) async => const RecoveryActionResult(summary: 'rolled back');
}

class _Verifier implements RecoveryVerifier {
  _Verifier(this.passes);
  final bool passes;
  @override
  Future<RecoveryVerification> verify(
    FailureEvent originalFailure,
    RecoveryActionResult action,
  ) async => RecoveryVerification(
    passed: passes,
    check: 'original_failure_absent',
    observed: passes ? 'gone' : 'still present',
    materialProgress: passes,
  );
}

class _Allow implements RecoveryAuthorityGate {
  @override
  Future<RecoveryAuthorityEvaluation> evaluate(
    FailureEvent failure,
    RecoveryDecision decision,
  ) async =>
      const RecoveryAuthorityEvaluation(allowed: true, reason: 'test');
}

class _Harness {
  _Harness({bool verifierPasses = true, List<String> capabilityIds = const []})
      : journal = _Journal(),
        events = _Events(),
        router = _Router(),
        actuator = _Actuator() {
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
    supervisor = FailureSupervisor(
      selfModel: KristinSelfModelService(
        registry: registry,
        application: _App(),
      ),
      journal: journal,
      events: events,
      router: router,
      actuator: actuator,
      verifier: _Verifier(verifierPasses),
      authority: _Allow(),
    );
  }

  final _Journal journal;
  final _Events events;
  final _Router router;
  final _Actuator actuator;
  late final FailureSupervisor supervisor;
}

FailureEvent _fault({
  required FailureCategory category,
  required String subsystem,
  required String operation,
  required String message,
  String? runId = 'run-1',
  String? processId,
  String? modelExactId,
  String? projectId,
  Set<String> requiredAuthority = const <String>{},
}) =>
    FailureEvent(
      severity: FailureSeverity.error,
      category: category,
      subsystem: subsystem,
      operation: operation,
      message: message,
      runId: runId,
      processId: processId,
      modelExactId: modelExactId,
      projectId: projectId,
      requiredAuthority: requiredAuthority,
    );

void main() {
  group('runtime faults route to the correct rung of the ladder', () {
    test('a provider disappearing is treated as transient and retried',
        () async {
      final harness = _Harness();
      await harness.supervisor.handle(
        _fault(
          category: FailureCategory.provider,
          subsystem: 'model',
          operation: 'complete',
          message: 'provider endpoint refused the connection',
        ),
      );
      expect(harness.actuator.levels.single, RecoveryLevel.l0Transient);
      expect(harness.router.continued, 1);
    });

    test('an unavailable model is a provider-class fault, not a code repair',
        () async {
      final harness = _Harness();
      await harness.supervisor.handle(
        _fault(
          category: FailureCategory.provider,
          subsystem: 'model',
          operation: 'resolve',
          message: 'model is not available',
          modelExactId: 'local/qwen',
        ),
      );
      expect(harness.actuator.levels.single, RecoveryLevel.l0Transient);
      expect(harness.router.recoveryWork, 0,
          reason: 'a missing model must not open a code-repair task');
    });

    test('a dead browser handle is an operational restart, not a retry',
        () async {
      final harness = _Harness();
      await harness.supervisor.handle(
        _fault(
          category: FailureCategory.browser,
          subsystem: 'browser',
          operation: 'navigate',
          message: 'the browser runtime exited',
        ),
      );
      expect(harness.actuator.levels.single, RecoveryLevel.l1Operational);
    });

    test('a vanished process is an operational restart', () async {
      final harness = _Harness();
      await harness.supervisor.handle(
        _fault(
          category: FailureCategory.process,
          subsystem: 'runner',
          operation: 'process_status',
          message: 'process 4711 is gone',
          processId: '4711',
        ),
      );
      expect(harness.actuator.levels.single, RecoveryLevel.l1Operational);
    });

    test('a stale process handle shares a signature with a vanished process',
        () async {
      // Different pid, same underlying fault: normalisation must fold them
      // together or the attempt budget can never bind.
      final first = _fault(
        category: FailureCategory.process,
        subsystem: 'runner',
        operation: 'process_status',
        message: 'process 4711 is gone',
      );
      final second = _fault(
        category: FailureCategory.process,
        subsystem: 'runner',
        operation: 'process_status',
        message: 'process 5822 is gone',
      );
      expect(first.recurrenceSignature, second.recurrenceSignature);
    });

    test('a broken dependency is a configuration repair', () async {
      final harness = _Harness();
      await harness.supervisor.handle(
        _fault(
          category: FailureCategory.dependency,
          subsystem: 'toolchain',
          operation: 'resolve',
          message: 'a pinned dependency is missing',
        ),
      );
      expect(harness.actuator.levels.single, RecoveryLevel.l2Configuration);
    });

    test('a missing project routes to governed kernel repair, not actuation',
        () async {
      final harness = _Harness(capabilityIds: <String>['agent.fix_project']);
      await harness.supervisor.handle(
        _fault(
          category: FailureCategory.project,
          subsystem: 'project',
          operation: 'open',
          message: 'the project no longer exists',
          projectId: 'proj-1',
        ),
      );
      expect(harness.router.recoveryWork, 1);
      expect(harness.actuator.performed, 0);
    });
  });

  group('faults that must never be auto-recovered', () {
    test('a permission failure is terminal and actuates nothing', () async {
      final harness = _Harness();
      final result = await harness.supervisor.handle(
        _fault(
          category: FailureCategory.permission,
          subsystem: 'runner',
          operation: 'write_file',
          message: 'permission is required',
        ),
      );
      expect(result, isNull, reason: 'the supervisor escalates to a human');
      expect(harness.actuator.performed, 0);
      expect(harness.router.continued, 0);
      expect(harness.events.types, contains('recovery_escalated'));
    });

    test('an unknown failure is terminal until its cause is established',
        () async {
      final harness = _Harness();
      final result = await harness.supervisor.handle(
        _fault(
          category: FailureCategory.unknown,
          subsystem: 'runner',
          operation: 'execute',
          message: 'something went wrong',
        ),
      );
      expect(result, isNull);
      expect(harness.actuator.performed, 0);
    });

    test(
      'a terminal failure that names required authority asks for authority '
      'rather than guessing at it',
      () async {
        final harness = _Harness();
        await harness.supervisor.handle(
          _fault(
            category: FailureCategory.permission,
            subsystem: 'owner',
            operation: 'reset',
            message: 'owner authority is required',
            requiredAuthority: <String>{'owner'},
          ),
        );
        expect(harness.actuator.performed, 0);
        expect(harness.events.types, contains('recovery_escalated'));
      },
    );
  });

  group('a fault whose repair does not hold never resumes the original task',
      () {
    test('verification failure leaves the original task suspended', () async {
      final harness = _Harness(verifierPasses: false);
      await harness.supervisor.handle(
        _fault(
          category: FailureCategory.transient,
          subsystem: 'provider',
          operation: 'complete',
          message: 'connection reset',
        ),
      );
      expect(harness.actuator.performed, 1);
      expect(harness.router.continued, 0);
      expect(
        harness.journal.attempts.last.state,
        RecoveryAttemptState.failed,
      );
    });

    test('a repeated identical fault stops instead of looping', () async {
      final harness = _Harness(verifierPasses: false);
      final calls = <int>[];
      for (var i = 0; i < 8; i++) {
        await harness.supervisor.handle(
          _fault(
            category: FailureCategory.transient,
            subsystem: 'provider',
            operation: 'complete',
            message: 'connection reset',
          ),
        );
        calls.add(harness.actuator.performed);
      }
      // The ladder is finite: L0 -> L1 -> L2 -> L3, each tried at most once
      // per signature, then the budget stops everything.
      expect(harness.actuator.performed, lessThanOrEqualTo(4));
      expect(calls.last, calls[calls.length - 2],
          reason: 'later handles must add no further actuation');
      expect(harness.router.continued, 0);
    });
  });
}
