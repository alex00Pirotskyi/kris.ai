import 'domain.dart';
import 'repository.dart';
import 'run_live_signals.dart';
import 'run_steering_record.dart';
import 'storage_security.dart';
import 'task_kernel/task_specification.dart';

class RunSteeringInstruction {
  const RunSteeringInstruction({
    required this.id,
    required this.runId,
    required this.text,
    required this.patch,
    required this.createdAt,
    this.continuationRunId,
    this.reconciliationSummary = '',
  });

  final String id;
  final String runId;
  final String text;
  final TaskSpecificationPatch patch;
  final DateTime createdAt;
  final String? continuationRunId;
  final String reconciliationSummary;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'runId': runId,
        'text': text,
        'patch': patch.toJson(),
        'createdAt': createdAt.toIso8601String(),
        if (continuationRunId != null) 'continuationRunId': continuationRunId,
        if (reconciliationSummary.isNotEmpty)
          'reconciliationSummary': reconciliationSummary,
      };

  factory RunSteeringInstruction.fromRecord(RunSteeringRecord record) =>
      RunSteeringInstruction(
        id: record.id,
        runId: record.runId,
        text: record.text,
        patch: record.patch,
        createdAt: record.createdAt,
        continuationRunId: record.continuationRunId,
        reconciliationSummary: record.reconciliation.isEmpty
            ? ''
            : _reconciliationSummary(record.reconciliation),
      );
}

class RunSteeringService {
  RunSteeringService({
    required this.liveSignals,
    required this.repository,
  });

  final LiveRunSignalBus liveSignals;
  final EntityRepository<RunSteeringRecord> repository;

  Future<RunSteeringInstruction> queue(String runId, String text) async {
    final normalized = text.trim();
    if (normalized.length < 2) {
      throw ProductException(
        'steering_too_short',
        'Describe the direction you want Kristin to apply.',
      );
    }
    if (normalized.length > 4000) {
      throw ProductException(
        'steering_too_long',
        'A steering message cannot exceed 4,000 characters.',
      );
    }
    final patch = TaskSpecificationPatch.fromUserSteering(normalized);
    if (patch.authorityClaimRejected) {
      throw ProductException(
        'steering_authority_claim_rejected',
        'Steering can change task intent, but it cannot grant or widen authority.',
        details: <String, dynamic>{
          'runId': runId,
          'patch': patch.toJson(),
          'grantsAuthority': false,
        },
      );
    }
    final now = DateTime.now().toUtc();
    final record = RunSteeringRecord(
      id: newId('steer'),
      runId: runId,
      text: normalized,
      patch: patch,
      state: RunSteeringRecordState.pending,
      createdAt: now,
    );
    await repository.put(record);
    final instruction = RunSteeringInstruction.fromRecord(record);
    liveSignals.publish(
      LiveRunSignal(
        sequence: 0,
        runId: runId,
        kind: LiveRunSignalKind.steeringQueued,
        timestamp: now,
        data: <String, dynamic>{
          'instructionId': instruction.id,
          'text': instruction.text,
          'patch': instruction.patch.toJson(),
          'authorityBearing': false,
          'requiresReplan': instruction.patch.requiresReplan,
        },
      ),
    );
    return instruction;
  }

  Future<List<RunSteeringInstruction>> takePending(String runId) async {
    final values = (await repository.all())
        .where((record) =>
            record.runId == runId &&
            record.state == RunSteeringRecordState.pending &&
            !record.patch.requiresReplan)
        .toList(growable: false)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return List<RunSteeringInstruction>.unmodifiable(
      values.map(RunSteeringInstruction.fromRecord),
    );
  }

  Future<void> applied(
    String runId,
    Iterable<RunSteeringInstruction> instructions, {
    String? workItemId,
  }) async {
    final values = instructions.toList(growable: false);
    if (values.isEmpty) return;
    final now = DateTime.now().toUtc();
    for (final instruction in values) {
      final record = await repository.get(instruction.id);
      if (record == null ||
          record.runId != runId ||
          record.state != RunSteeringRecordState.pending) {
        continue;
      }
      await repository.put(
        record.copyWith(
          state: RunSteeringRecordState.applied,
          workItemId: workItemId,
          appliedAt: now,
        ),
      );
    }
    liveSignals.publish(
      LiveRunSignal(
        sequence: 0,
        runId: runId,
        workItemId: workItemId,
        kind: LiveRunSignalKind.steeringApplied,
        timestamp: now,
        data: <String, dynamic>{
          'instructionIds': values.map((item) => item.id).toList(),
          'count': values.length,
          'authorityBearing': false,
        },
      ),
    );
  }

  Future<List<RunSteeringInstruction>> pendingReplan(String runId) async {
    final values = (await repository.all())
        .where((record) =>
            record.runId == runId &&
            const <RunSteeringRecordState>{
              RunSteeringRecordState.pending,
              RunSteeringRecordState.replanning,
            }.contains(record.state) &&
            record.patch.requiresReplan)
        .toList(growable: false)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return values
        .map(RunSteeringInstruction.fromRecord)
        .toList(growable: false);
  }

  Future<void> markReplanning(
    String runId,
    Iterable<RunSteeringInstruction> instructions,
  ) async {
    for (final instruction in instructions) {
      final record = await repository.get(instruction.id);
      if (record == null ||
          record.runId != runId ||
          record.state != RunSteeringRecordState.pending) {
        continue;
      }
      await repository
          .put(record.copyWith(state: RunSteeringRecordState.replanning));
    }
  }

  Future<void> markContinuationReady(
    String runId,
    Iterable<RunSteeringInstruction> instructions, {
    required String continuationRunId,
    required List<Map<String, dynamic>> reconciliation,
  }) async {
    final now = DateTime.now().toUtc();
    for (final instruction in instructions) {
      final record = await repository.get(instruction.id);
      if (record == null || record.runId != runId) continue;
      await repository.put(
        record.copyWith(
          state: RunSteeringRecordState.applied,
          continuationRunId: continuationRunId,
          reconciliation: reconciliation,
          appliedAt: now,
        ),
      );
    }
  }

  Future<void> clear(String runId) async {
    final pending = (await repository.all()).where(
      (record) =>
          record.runId == runId &&
          record.state == RunSteeringRecordState.pending,
    );
    for (final record in pending) {
      await repository.put(
        record.copyWith(state: RunSteeringRecordState.cleared),
      );
    }
  }
}

String _reconciliationSummary(List<Map<String, dynamic>> values) {
  final counts = <String, int>{};
  for (final value in values) {
    final outcome = value['outcome']?.toString() ?? '';
    if (outcome.isNotEmpty) counts[outcome] = (counts[outcome] ?? 0) + 1;
  }
  final parts = <String>[
    if ((counts['preserved'] ?? 0) > 0) '${counts['preserved']} preserved',
    if ((counts['invalidated'] ?? 0) > 0)
      '${counts['invalidated']} invalidated',
    if ((counts['added'] ?? 0) > 0) '${counts['added']} added',
    if ((counts['removed'] ?? 0) > 0) '${counts['removed']} removed',
  ];
  return parts.isEmpty ? 'Plan reconciled.' : parts.join(', ');
}
