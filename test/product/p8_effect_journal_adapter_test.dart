import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_effect_journal.dart';
import 'package:kristin_local_agent/product/p8_effect_journal_adapter.dart';
import 'package:kristin_local_agent/product/p8_external_effects.dart';

void main() {
  group('P8-003 P2 external-effect integration', () {
    late Directory root;
    late File stateFile;
    late _MemoryJournal downstream;
    late P8ReconciledEffectJournal journal;
    final now = DateTime.utc(2026, 8, 23, 12);

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kristin-p8-effects-');
      stateFile = File('${root.path}${Platform.pathSeparator}effects.jsonl');
      downstream = _MemoryJournal();
      journal = P8ReconciledEffectJournal(
        downstream: downstream,
        stateFile: stateFile,
      );
      await journal.initialize();
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    P2EffectReceipt p2(P2EffectStatus status, {String effectId = 'effect-1'}) =>
        P2EffectReceipt(
          effectId: effectId,
          runId: 'run-1',
          taskId: 'task-1',
          operation: 'filesystem.write',
          status: status,
          reversibility: P2Reversibility.reversible,
          startedAt: now,
          completedAt: status == P2EffectStatus.started ? null : now,
          details: const <String, Object?>{},
        );

    test('successful P2 effect becomes observed and committed', () async {
      await journal.append(p2(P2EffectStatus.authorized));
      await journal.append(p2(P2EffectStatus.started));
      await journal.append(p2(P2EffectStatus.succeeded));

      final receipt = journal.receipt('effect-1')!;
      expect(receipt.state, ExternalEffectState.committed);
      expect(receipt.retryAllowed, isFalse);
      expect(receipt.requiresReconciliation, isFalse);
      expect(downstream.receipts, hasLength(3));
    });

    test('uncertain started effect blocks blind retry and survives restart',
        () async {
      await journal.append(p2(P2EffectStatus.started));
      await journal.append(p2(P2EffectStatus.unknown));
      expect(journal.receipt('effect-1')!.state, ExternalEffectState.unknown);
      expect(journal.retryAllowed('effect-1'), isFalse);
      expect(
        () => journal.requireRetryAllowed('effect-1'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'external_effect_reconciliation_required',
          ),
        ),
      );

      final restarted = P8ReconciledEffectJournal(
        downstream: _MemoryJournal(),
        stateFile: stateFile,
      );
      await restarted.initialize();
      expect(restarted.receipt('effect-1')!.state, ExternalEffectState.unknown);
      expect(restarted.retryAllowed('effect-1'), isFalse);
    });

    test('rollback records reconciliation then compensation', () async {
      await journal.append(p2(P2EffectStatus.started));
      await journal.append(p2(P2EffectStatus.failed));
      await journal.append(p2(P2EffectStatus.rolledBack));

      final receipt = journal.receipt('effect-1')!;
      expect(receipt.state, ExternalEffectState.compensated);
      expect(receipt.retryAllowed, isFalse);
      expect(
        receipt.transitions.map((transition) => transition.to),
        contains(ExternalEffectState.reconciliationRequired),
      );
    });

    test('unsupported operation never masquerades as an executed effect',
        () async {
      await journal.append(p2(P2EffectStatus.unsupported));
      final receipt = journal.receipt('effect-1')!;
      expect(receipt.state, ExternalEffectState.planned);
      expect(receipt.retryAllowed, isTrue);
    });
  });
}

final class _MemoryJournal implements P2EffectJournal {
  final List<P2EffectReceipt> receipts = <P2EffectReceipt>[];

  @override
  Future<void> append(P2EffectReceipt receipt) async {
    receipts.add(receipt);
  }
}
