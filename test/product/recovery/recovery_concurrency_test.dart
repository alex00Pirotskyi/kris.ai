// Deterministic proof that concurrent supervision cannot double-spend the
// recovery budget or resume the original task twice.
//
// The race being closed is real and reachable: ProductRuntimeAutonomicRecovery
// dispatches supervision with `unawaited(...)` from a runtime event listener,
// so two `run.failed` events put two handle() calls in flight on one
// supervisor. Between reading the attempt list and appending an attempt,
// handle() awaits the experience store, the self-model snapshot, event
// emission and the whole authority preflight.
//
// Nothing here sleeps. Interleaving is controlled with Completers: the
// actuator parks inside perform() until the test releases it, so "both calls
// are past the budget check at the same time" is a fact the test establishes
// rather than a timing hope.

import 'dart:async';

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
  ) async =>
      CapabilityAvailability(
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
  }) async =>
      ApplicationSnapshot(
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
      summary: 'kernel work',
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

/// Parks inside perform() until the test releases it, making the overlap
/// deterministic.
class _GatedActuator implements RecoveryActuator {
  final List<Completer<void>> entered = <Completer<void>>[];
  final List<Completer<void>> release = <Completer<void>>[];
  int performed = 0;
  bool throwOnPerform = false;

  /// Latched by [releaseAll]. Supervision is serialized per recurrence
  /// signature, so a queued second supervision reaches perform() only after
  /// the first one finishes -- strictly after the test has already released.
  /// Without this latch its gate would be created post-release and block
  /// forever, turning a passing invariant into a timeout.
  bool _released = false;

  @override
  Future<RecoveryActionResult> perform(
    RecoveryDecision decision,
    FailureEvent failure,
  ) async {
    performed += 1;
    final gate = Completer<void>();
    release.add(gate);
    if (_released) gate.complete();
    if (entered.isNotEmpty) {
      final waiter = entered.removeAt(0);
      if (!waiter.isCompleted) waiter.complete();
    }
    await gate.future;
    if (throwOnPerform) throw StateError('actuator exploded');
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
  ) async =>
      const RecoveryActionResult(summary: 'rolled back');

  /// Completes when the next perform() call has been entered.
  Future<void> nextEntry() {
    final c = Completer<void>();
    entered.add(c);
    return c.future;
  }

  void releaseAll() {
    _released = true;
    for (final gate in release) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}

class _Verifier implements RecoveryVerifier {
  _Verifier(this.passes);
  final bool passes;
  int calls = 0;
  @override
  Future<RecoveryVerification> verify(
    FailureEvent originalFailure,
    RecoveryActionResult action,
  ) async {
    calls += 1;
    return RecoveryVerification(
      passed: passes,
      check: 'original_failure_absent',
      observed: passes ? 'gone' : 'present',
      materialProgress: passes,
    );
  }
}

class _Allow implements RecoveryAuthorityGate {
  @override
  Future<RecoveryAuthorityEvaluation> evaluate(
    FailureEvent failure,
    RecoveryDecision decision,
  ) async =>
      const RecoveryAuthorityEvaluation(allowed: true, reason: 'test');
}

FailureSupervisor _supervisor({
  required _Journal journal,
  required _Events events,
  required _Router router,
  required _GatedActuator actuator,
  required _Verifier verifier,
  RecoveryPolicy policy = const RecoveryPolicy(),
}) {
  final registry = KristinCapabilityRegistry()
    ..register(_Provider('test', const <CapabilityDescriptor>[]));
  return FailureSupervisor(
    selfModel: KristinSelfModelService(
      registry: registry,
      application: _App(),
    ),
    journal: journal,
    events: events,
    router: router,
    actuator: actuator,
    verifier: verifier,
    authority: _Allow(),
    policy: policy,
  );
}

FailureEvent _failure({String message = 'connection reset', String? runId}) =>
    FailureEvent(
      severity: FailureSeverity.error,
      category: FailureCategory.transient,
      subsystem: 'provider',
      operation: 'complete',
      message: message,
      runId: runId,
    );

void main() {
  group('the same failure cannot be supervised twice at once', () {
    test('a second supervision of one failure id is refused, not duplicated',
        () async {
      final actuator = _GatedActuator();
      final router = _Router();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: router,
        actuator: actuator,
        verifier: _Verifier(true),
      );
      final failure = _failure(runId: 'run-1');

      final entered = actuator.nextEntry();
      final first = supervisor.handle(failure);
      await entered; // first call is now inside the actuator

      // Second supervision of the very same failure, while the first is
      // demonstrably mid-flight.
      final second = await supervisor.handle(failure);
      expect(second?.passed, isFalse);
      expect(second?.check, 'recovery_already_in_progress');

      actuator.releaseAll();
      final firstResult = await first;

      expect(firstResult?.passed, isTrue);
      expect(actuator.performed, 1, reason: 'only one actuator run');
      expect(router.continued, 1, reason: 'exactly one resume');
    });

    test('the refusal is released once supervision finishes', () async {
      final actuator = _GatedActuator();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: _Router(),
        actuator: actuator,
        verifier: _Verifier(true),
      );
      final failure = _failure(runId: 'run-1');

      final entered = actuator.nextEntry();
      final first = supervisor.handle(failure);
      await entered;
      actuator.releaseAll();
      await first;

      // The same failure may be supervised again afterwards; the guard is
      // about concurrency, not a permanent ban.
      final again = await supervisor.handle(failure);
      expect(again?.check, isNot('recovery_already_in_progress'));
    });
  });

  group('overlapping supervisions of one signature share one budget', () {
    test(
      'the second supervision observes the first attempt, so the final '
      'available attempt cannot be reserved twice',
      () async {
        final actuator = _GatedActuator();
        final router = _Router();
        final journal = _Journal();
        final supervisor = _supervisor(
          journal: journal,
          events: _Events(),
          router: router,
          actuator: actuator,
          verifier: _Verifier(false),
          policy: const RecoveryPolicy(maxAttemptsPerFailureSignature: 1),
        );

        // Two distinct failure events, same recurrence signature -- exactly
        // what two `run.failed` events for one recurring fault produce.
        final a = _failure(runId: 'run-1');
        final b = _failure(runId: 'run-1');
        expect(a.recurrenceSignature, b.recurrenceSignature);
        expect(a.id, isNot(b.id));

        final entered = actuator.nextEntry();
        final firstCall = supervisor.handle(a);
        await entered; // A is inside the actuator, past the budget check

        // B starts while A is mid-flight. It must not be able to consume the
        // one remaining attempt.
        final secondCall = supervisor.handle(b);

        actuator.releaseAll();
        await firstCall;
        final secondResult = await secondCall;

        expect(actuator.performed, 1,
            reason: 'the single available attempt was reserved exactly once');
        expect(secondResult, isNull,
            reason: 'the second supervision escalates rather than actuating');
        expect(router.continued, 0);
      },
    );

    test('a serialized second supervision still runs when budget remains',
        () async {
      final actuator = _GatedActuator();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: _Router(),
        actuator: actuator,
        verifier: _Verifier(false),
        policy: const RecoveryPolicy(maxAttemptsPerFailureSignature: 4),
      );

      final entered = actuator.nextEntry();
      final firstCall = supervisor.handle(_failure(runId: 'run-1'));
      await entered;
      final secondCall = supervisor.handle(_failure(runId: 'run-1'));
      actuator.releaseAll();
      await firstCall;
      await secondCall;

      // Serialization is not suppression: with budget left, the ladder
      // advances rather than the second supervision being dropped.
      expect(actuator.performed, 2);
    });

    test('only one original-task resume happens across overlapping calls',
        () async {
      final actuator = _GatedActuator();
      final router = _Router();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: router,
        actuator: actuator,
        verifier: _Verifier(true),
        policy: const RecoveryPolicy(maxAttemptsPerFailureSignature: 1),
      );

      final entered = actuator.nextEntry();
      final firstCall = supervisor.handle(_failure(runId: 'run-1'));
      await entered;
      final secondCall = supervisor.handle(_failure(runId: 'run-1'));
      actuator.releaseAll();
      await firstCall;
      await secondCall;

      expect(router.continued, 1);
    });
  });

  group('accounting survives failure paths', () {
    test('an actuator exception still consumes exactly one attempt', () async {
      final actuator = _GatedActuator()..throwOnPerform = true;
      final journal = _Journal();
      final supervisor = _supervisor(
        journal: journal,
        events: _Events(),
        router: _Router(),
        actuator: actuator,
        verifier: _Verifier(true),
        policy: const RecoveryPolicy(maxAttemptsPerFailureSignature: 1),
      );

      final entered = actuator.nextEntry();
      final call = supervisor.handle(_failure(runId: 'run-1'));
      await entered;
      actuator.releaseAll();
      await call;

      expect(actuator.performed, 1);
      expect(
        journal.attempts.last.state,
        RecoveryAttemptState.failed,
        reason: 'the attempt is recorded as spent, not silently returned',
      );

      // The budget is now genuinely exhausted for this signature.
      final next = await supervisor.handle(_failure(runId: 'run-1'));
      expect(next, isNull);
      expect(actuator.performed, 1);
    });

    test('the in-flight guard is released even when supervision throws',
        () async {
      final actuator = _GatedActuator()..throwOnPerform = true;
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: _Router(),
        actuator: actuator,
        verifier: _Verifier(true),
      );
      final failure = _failure(runId: 'run-1');

      final entered = actuator.nextEntry();
      final call = supervisor.handle(failure);
      await entered;
      actuator.releaseAll();
      await call;

      // If the guard leaked, this would be refused forever.
      final again = await supervisor.handle(failure);
      expect(again?.check, isNot('recovery_already_in_progress'));
    });
  });

  group('unrelated failures are not serialized against each other', () {
    test('two different signatures recover concurrently', () async {
      final actuator = _GatedActuator();
      final supervisor = _supervisor(
        journal: _Journal(),
        events: _Events(),
        router: _Router(),
        actuator: actuator,
        verifier: _Verifier(true),
      );

      final network = _failure(message: 'connection reset', runId: 'run-1');
      final disk = _failure(message: 'no space left on device', runId: 'run-2');
      expect(network.recurrenceSignature, isNot(disk.recurrenceSignature));

      final firstEntered = actuator.nextEntry();
      final secondEntered = actuator.nextEntry();
      final a = supervisor.handle(network);
      final b = supervisor.handle(disk);

      // Both reach the actuator without either having completed: independent
      // faults must not queue behind one another.
      await firstEntered;
      await secondEntered;
      expect(actuator.performed, 2);

      actuator.releaseAll();
      await a;
      await b;
    });
  });
}
