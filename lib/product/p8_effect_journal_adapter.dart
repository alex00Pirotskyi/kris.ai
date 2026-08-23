import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'crypto_utils.dart';
import 'p2_effect_journal.dart';
import 'p8_external_effects.dart';

class P8ReconciledEffectJournal implements P2EffectJournal {
  P8ReconciledEffectJournal({
    required this.downstream,
    required this.stateFile,
  });

  final P2EffectJournal downstream;
  final File stateFile;
  final Map<String, ExternalEffectReceipt> _receipts =
      <String, ExternalEffectReceipt>{};
  Future<void> _tail = Future<void>.value();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!await stateFile.exists()) return;
    final lines = await stateFile.readAsLines();
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('p8_effect_journal_line_invalid');
      }
      final receipt = ExternalEffectReceipt.fromJson(
        <String, Object?>{
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value,
        },
      );
      _receipts[receipt.effectId] = receipt;
    }
  }

  @override
  Future<void> append(P2EffectReceipt receipt) {
    final next = _tail.then((_) async {
      await initialize();
      await downstream.append(receipt);
      final tracked = _receipts.putIfAbsent(
        receipt.effectId,
        () => ExternalEffectReceipt(
          effectId: receipt.effectId,
          idempotencyKey: Sha256.text(
            '${receipt.runId}:${receipt.taskId}:${receipt.effectId}',
          ),
        ),
      );
      _apply(tracked, receipt);
      await _persist(tracked);
    });
    _tail = next.catchError((Object _) {});
    return next;
  }

  ExternalEffectReceipt? receipt(String effectId) => _receipts[effectId];

  bool retryAllowed(String effectId) => _receipts[effectId]?.retryAllowed ?? true;

  void requireRetryAllowed(String effectId) {
    final current = _receipts[effectId];
    if (current != null && !current.retryAllowed) {
      throw StateError(
        current.requiresReconciliation
            ? 'external_effect_reconciliation_required'
            : 'external_effect_retry_forbidden:${current.state.wireName}',
      );
    }
  }

  void _apply(ExternalEffectReceipt tracked, P2EffectReceipt receipt) {
    final evidenceId = Sha256.text(canonicalJson(receipt.toJson()));
    final at = receipt.completedAt ?? receipt.startedAt;

    void transition(ExternalEffectState state, String suffix) {
      if (tracked.state == state) return;
      tracked.transition(
        state,
        evidenceId: '$evidenceId:$suffix',
        recordedAt: at,
      );
    }

    void ensureStarted() {
      if (tracked.state == ExternalEffectState.planned) {
        transition(ExternalEffectState.authorized, 'authorized-inferred');
      }
      if (tracked.state == ExternalEffectState.authorized) {
        transition(ExternalEffectState.started, 'started');
      }
    }

    void markUnknown() {
      if (const <ExternalEffectState>{
        ExternalEffectState.committed,
        ExternalEffectState.compensated,
        ExternalEffectState.unknown,
        ExternalEffectState.reconciliationRequired,
      }.contains(tracked.state)) {
        return;
      }
      ensureStarted();
      if (tracked.state == ExternalEffectState.observed ||
          tracked.state == ExternalEffectState.started) {
        transition(ExternalEffectState.unknown, 'unknown');
      }
    }

    switch (receipt.status) {
      case P2EffectStatus.authorized:
        if (tracked.state == ExternalEffectState.planned) {
          transition(ExternalEffectState.authorized, 'authorized');
        }
      case P2EffectStatus.started:
        ensureStarted();
      case P2EffectStatus.succeeded:
        ensureStarted();
        if (tracked.state == ExternalEffectState.started) {
          transition(ExternalEffectState.observed, 'observed');
        }
        if (tracked.state == ExternalEffectState.observed) {
          transition(ExternalEffectState.committed, 'committed');
        }
      case P2EffectStatus.failed:
      case P2EffectStatus.cancelled:
      case P2EffectStatus.killed:
      case P2EffectStatus.unknown:
        markUnknown();
      case P2EffectStatus.rolledBack:
        if (tracked.state == ExternalEffectState.compensated) return;
        if (tracked.state == ExternalEffectState.planned ||
            tracked.state == ExternalEffectState.authorized ||
            tracked.state == ExternalEffectState.started ||
            tracked.state == ExternalEffectState.observed) {
          markUnknown();
        }
        if (tracked.state == ExternalEffectState.unknown) {
          transition(
            ExternalEffectState.reconciliationRequired,
            'rollback-reconcile',
          );
        }
        if (tracked.state == ExternalEffectState.reconciliationRequired ||
            tracked.state == ExternalEffectState.committed) {
          transition(ExternalEffectState.compensated, 'rolled-back');
        }
      case P2EffectStatus.unsupported:
        // No external effect was started. Keep the planned state retryable so a
        // different supported implementation may be selected deliberately.
        return;
    }
  }

  Future<void> _persist(ExternalEffectReceipt receipt) async {
    await stateFile.parent.create(recursive: true);
    final sink = stateFile.openWrite(mode: FileMode.append);
    sink.writeln(jsonEncode(receipt.toJson()));
    await sink.flush();
    await sink.close();
  }
}
