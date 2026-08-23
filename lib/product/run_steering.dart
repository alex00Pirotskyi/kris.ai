import 'dart:collection';

import 'domain.dart';
import 'run_live_signals.dart';
import 'storage_security.dart';

class RunSteeringInstruction {
  const RunSteeringInstruction({
    required this.id,
    required this.runId,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String runId;
  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'runId': runId,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };
}

class RunSteeringService {
  RunSteeringService({required this.liveSignals});

  final LiveRunSignalBus liveSignals;
  final Map<String, Queue<RunSteeringInstruction>> _pending =
      <String, Queue<RunSteeringInstruction>>{};

  RunSteeringInstruction queue(String runId, String text) {
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
    final instruction = RunSteeringInstruction(
      id: newId('steer'),
      runId: runId,
      text: normalized,
      createdAt: DateTime.now().toUtc(),
    );
    (_pending[runId] ??= Queue<RunSteeringInstruction>()).add(instruction);
    liveSignals.publish(
      LiveRunSignal(
        sequence: 0,
        runId: runId,
        kind: LiveRunSignalKind.steeringQueued,
        timestamp: instruction.createdAt,
        data: <String, dynamic>{
          'instructionId': instruction.id,
          'text': instruction.text,
        },
      ),
    );
    return instruction;
  }

  List<RunSteeringInstruction> takePending(String runId) {
    final queue = _pending.remove(runId);
    if (queue == null || queue.isEmpty) {
      return const <RunSteeringInstruction>[];
    }
    return List<RunSteeringInstruction>.unmodifiable(queue);
  }

  void applied(
    String runId,
    Iterable<RunSteeringInstruction> instructions, {
    String? workItemId,
  }) {
    final values = instructions.toList(growable: false);
    if (values.isEmpty) return;
    liveSignals.publish(
      LiveRunSignal(
        sequence: 0,
        runId: runId,
        workItemId: workItemId,
        kind: LiveRunSignalKind.steeringApplied,
        timestamp: DateTime.now().toUtc(),
        data: <String, dynamic>{
          'instructionIds': values.map((item) => item.id).toList(),
          'count': values.length,
        },
      ),
    );
  }

  void clear(String runId) => _pending.remove(runId);
}
