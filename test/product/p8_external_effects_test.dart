import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p8_external_effects.dart';

void main() {
  group('P8-003 external-effect state machine', () {
    test(
        'normal effect requires authorization, observation and commit evidence',
        () {
      final receipt = ExternalEffectReceipt(
        effectId: 'effect-1',
        idempotencyKey: 'idem-1',
      );
      final now = DateTime.utc(2026, 8, 23, 12);

      expect(receipt.retryAllowed, isTrue);
      receipt.transition(
        ExternalEffectState.authorized,
        evidenceId: 'grant-1',
        recordedAt: now,
      );
      receipt.transition(
        ExternalEffectState.started,
        evidenceId: 'worker-start-1',
        recordedAt: now,
      );
      expect(receipt.retryAllowed, isFalse);
      receipt.transition(
        ExternalEffectState.observed,
        evidenceId: 'observation-1',
        recordedAt: now,
      );
      receipt.transition(
        ExternalEffectState.committed,
        evidenceId: 'commit-1',
        recordedAt: now,
      );

      expect(receipt.state, ExternalEffectState.committed);
      expect(receipt.requiresReconciliation, isFalse);
      expect(receipt.transitions, hasLength(4));
    });

    test('unknown effect cannot be blindly retried', () {
      final receipt = ExternalEffectReceipt(
        effectId: 'effect-2',
        idempotencyKey: 'idem-2',
      );
      final now = DateTime.utc(2026, 8, 23, 12);
      receipt.transition(
        ExternalEffectState.authorized,
        evidenceId: 'grant-2',
        recordedAt: now,
      );
      receipt.transition(
        ExternalEffectState.started,
        evidenceId: 'worker-start-2',
        recordedAt: now,
      );
      receipt.transition(
        ExternalEffectState.unknown,
        evidenceId: 'connection-lost',
        recordedAt: now,
      );

      expect(receipt.retryAllowed, isFalse);
      expect(receipt.requiresReconciliation, isTrue);
      expect(
        () => receipt.transition(
          ExternalEffectState.started,
          evidenceId: 'blind-retry',
          recordedAt: now,
        ),
        throwsStateError,
      );
      receipt.transition(
        ExternalEffectState.reconciliationRequired,
        evidenceId: 'reconcile-queued',
        recordedAt: now,
      );
      receipt.transition(
        ExternalEffectState.committed,
        evidenceId: 'remote-receipt-found',
        recordedAt: now,
      );
      expect(receipt.requiresReconciliation, isFalse);
    });

    test('invalid transition and missing evidence fail closed', () {
      final receipt = ExternalEffectReceipt(
        effectId: 'effect-3',
        idempotencyKey: 'idem-3',
      );
      final now = DateTime.utc(2026, 8, 23, 12);
      expect(
        () => receipt.transition(
          ExternalEffectState.committed,
          evidenceId: 'skip',
          recordedAt: now,
        ),
        throwsStateError,
      );
      expect(
        () => receipt.transition(
          ExternalEffectState.authorized,
          evidenceId: '',
          recordedAt: now,
        ),
        throwsStateError,
      );
    });
  });
}
