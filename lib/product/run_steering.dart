import 'dart:collection';

import 'domain.dart';
import 'repository.dart';
import 'run_live_signals.dart';
import 'run_steering_record.dart';
import 'storage_security.dart';
import 'task_kernel/task_specification.dart';
import 'task_kernel/task_specification_patch.dart';

extension RunSteeringPatchSemantics on TaskSpecificationPatch {
  bool get requiresReplan => switch (kind) {
    TaskSpecificationPatchKind.preference => false,
    TaskSpecificationPatchKind.objective ||
    TaskSpecificationPatchKind.hardConstraint ||
    TaskSpecificationPatchKind.requestedMethod ||
    TaskSpecificationPatchKind.priority ||
    TaskSpecificationPatchKind.stopCondition ||
    TaskSpecificationPatchKind.clarificationAnswer => true,
  };

  bool get grantsAuthority => false;

  TaskSpecification applyForReplan(TaskSpecification specification) =>
      applyTo(specification);

  String renderForExecutor() => switch (kind) {
    TaskSpecificationPatchKind.objective => 'Objective: $value',
    TaskSpecificationPatchKind.hardConstraint => 'Hard constraint: $value',
    TaskSpecificationPatchKind.preference => 'Preference: $value',
    TaskSpecificationPatchKind.requestedMethod => 'Requested method: $value',
    TaskSpecificationPatchKind.priority => 'Priority: $value',
    TaskSpecificationPatchKind.stopCondition => 'Stop condition: $value',
    TaskSpecificationPatchKind.clarificationAnswer =>
      'Clarification — $question: $value',
  };
}

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
  RunSteeringService({required this.liveSignals, this.repository});

  final LiveRunSignalBus liveSignals;
  final EntityRepository<RunSteeringRecord>? repository;
  final Map<String, Queue<RunSteeringInstruction>> _pending =
      <String, Queue<RunSteeringInstruction>>{};

  RunSteeringInstruction queue(String runId, String text) {
    final normalized = _normalize(text);
    final instruction = RunSteeringInstruction(
      id: newId('steer'),
      runId: runId,
      text: normalized,
      patch: TaskSpecificationPatch(
        kind: TaskSpecificationPatchKind.preference,
        value: normalized,
      ),
      createdAt: DateTime.now().toUtc(),
    );
    (_pending[runId] ??= Queue<RunSteeringInstruction>()).add(instruction);
    _publishQueued(instruction);
    return instruction;
  }

  Future<RunSteeringInstruction> queueDurable(
    String runId,
    String text,
    TaskSpecificationPatch patch,
  ) async {
    final normalized = _normalize(text);
    final now = DateTime.now().toUtc();
    final record = RunSteeringRecord(
      id: newId('steer'),
      runId: runId,
      text: normalized,
      patch: patch,
      state: RunSteeringRecordState.pending,
      createdAt: now,
    );
    await _durableRepository.put(record);
    final instruction = RunSteeringInstruction.fromRecord(record);
    _publishQueued(instruction);
    return instruction;
  }

  List<RunSteeringInstruction> takePending(String runId) {
    final queue = _pending.remove(runId);
    if (queue == null || queue.isEmpty) {
      return const <RunSteeringInstruction>[];
    }
    return List<RunSteeringInstruction>.unmodifiable(queue);
  }

  Future<List<RunSteeringInstruction>> takePendingDurable(String runId) async {
    final values =
        (await _durableRepository.all())
            .where(
              (record) =>
                  record.runId == runId &&
                  record.state == RunSteeringRecordState.pending &&
                  !record.patch.requiresReplan,
            )
            .toList(growable: false)
          ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return List<RunSteeringInstruction>.unmodifiable(
      values.map(RunSteeringInstruction.fromRecord),
    );
  }

  void applied(
    String runId,
    Iterable<RunSteeringInstruction> instructions, {
    String? workItemId,
  }) {
    final values = instructions.toList(growable: false);
    if (values.isEmpty) return;
    _publishApplied(runId, values, workItemId: workItemId);
  }

  Future<void> appliedDurable(
    String runId,
    Iterable<RunSteeringInstruction> instructions, {
    String? workItemId,
  }) async {
    final values = instructions.toList(growable: false);
    if (values.isEmpty) return;
    final now = DateTime.now().toUtc();
    for (final instruction in values) {
      final record = await _durableRepository.get(instruction.id);
      if (record == null ||
          record.runId != runId ||
          record.state != RunSteeringRecordState.pending) {
        continue;
      }
      await _durableRepository.put(
        record.copyWith(
          state: RunSteeringRecordState.applied,
          workItemId: workItemId,
          appliedAt: now,
        ),
      );
    }
    _publishApplied(runId, values, workItemId: workItemId, timestamp: now);
  }

  Future<List<RunSteeringInstruction>> pendingReplan(String runId) async {
    final values =
        (await _durableRepository.all())
            .where(
              (record) =>
                  record.runId == runId &&
                  const <RunSteeringRecordState>{
                    RunSteeringRecordState.pending,
                    RunSteeringRecordState.replanning,
                  }.contains(record.state) &&
                  record.patch.requiresReplan,
            )
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
      final record = await _durableRepository.get(instruction.id);
      if (record == null ||
          record.runId != runId ||
          record.state != RunSteeringRecordState.pending) {
        continue;
      }
      await _durableRepository.put(
        record.copyWith(state: RunSteeringRecordState.replanning),
      );
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
      final record = await _durableRepository.get(instruction.id);
      if (record == null || record.runId != runId) continue;
      await _durableRepository.put(
        record.copyWith(
          state: RunSteeringRecordState.applied,
          continuationRunId: continuationRunId,
          reconciliation: reconciliation,
          appliedAt: now,
        ),
      );
    }
  }

  void clear(String runId) => _pending.remove(runId);

  Future<void> clearDurable(String runId) async {
    final pending = (await _durableRepository.all()).where(
      (record) =>
          record.runId == runId &&
          record.state == RunSteeringRecordState.pending,
    );
    for (final record in pending) {
      await _durableRepository.put(
        record.copyWith(state: RunSteeringRecordState.cleared),
      );
    }
  }

  EntityRepository<RunSteeringRecord> get _durableRepository {
    final value = repository;
    if (value == null) {
      throw ProductException(
        'steering_repository_missing',
        'Durable steering requires a steering repository.',
      );
    }
    return value;
  }

  String _normalize(String text) {
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
    return normalized;
  }

  void _publishQueued(RunSteeringInstruction instruction) {
    liveSignals.publish(
      LiveRunSignal(
        sequence: 0,
        runId: instruction.runId,
        kind: LiveRunSignalKind.steeringQueued,
        timestamp: instruction.createdAt,
        data: <String, dynamic>{
          'instructionId': instruction.id,
          'text': instruction.text,
          'patch': instruction.patch.toJson(),
          'authorityBearing': false,
          'requiresReplan': instruction.patch.requiresReplan,
        },
      ),
    );
  }

  void _publishApplied(
    String runId,
    List<RunSteeringInstruction> values, {
    String? workItemId,
    DateTime? timestamp,
  }) {
    liveSignals.publish(
      LiveRunSignal(
        sequence: 0,
        runId: runId,
        workItemId: workItemId,
        kind: LiveRunSignalKind.steeringApplied,
        timestamp: timestamp ?? DateTime.now().toUtc(),
        data: <String, dynamic>{
          'instructionIds': values.map((item) => item.id).toList(),
          'count': values.length,
          'authorityBearing': false,
        },
      ),
    );
  }
}

String _reconciliationSummary(List<Map<String, dynamic>> values) {
  final counts = <String, int>{};
  for (final value in values) {
    final outcome = value['outcome']?.toString() ?? '';
    if (outcome.isNotEmpty) {
      counts[outcome] = (counts[outcome] ?? 0) + 1;
    }
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
