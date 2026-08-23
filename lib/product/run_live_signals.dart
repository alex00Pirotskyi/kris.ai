import 'dart:async';

import 'domain.dart';

enum LiveRunSignalKind {
  phase,
  preflight,
  modelProgress,
  modelTextDelta,
  toolStarted,
  toolOutput,
  toolCompleted,
  toolFailed,
  steeringQueued,
  steeringApplied,
  heartbeat,
}

class LiveRunSignal {
  const LiveRunSignal({
    required this.sequence,
    required this.runId,
    required this.kind,
    required this.timestamp,
    this.workItemId,
    this.data = const <String, dynamic>{},
  });

  final int sequence;
  final String runId;
  final String? workItemId;
  final LiveRunSignalKind kind;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  LiveRunSignal copyWithSequence(int value) => LiveRunSignal(
        sequence: value,
        runId: runId,
        workItemId: workItemId,
        kind: kind,
        timestamp: timestamp,
        data: data,
      );

  factory LiveRunSignal.phase({
    required String runId,
    required String phase,
    String? workItemId,
    String message = '',
  }) =>
      LiveRunSignal(
        sequence: 0,
        runId: runId,
        workItemId: workItemId,
        kind: LiveRunSignalKind.phase,
        timestamp: DateTime.now().toUtc(),
        data: <String, dynamic>{'phase': phase, 'message': message},
      );

  factory LiveRunSignal.modelProgress({
    required String runId,
    required String workItemId,
    required ModelIdentity model,
    required String stage,
    required String message,
    required int elapsedMilliseconds,
  }) =>
      LiveRunSignal(
        sequence: 0,
        runId: runId,
        workItemId: workItemId,
        kind: LiveRunSignalKind.modelProgress,
        timestamp: DateTime.now().toUtc(),
        data: <String, dynamic>{
          'model': model.toJson(),
          'stage': stage,
          'message': message,
          'elapsedMilliseconds': elapsedMilliseconds,
        },
      );

  factory LiveRunSignal.modelText({
    required String runId,
    required String workItemId,
    required ModelIdentity model,
    required String delta,
  }) =>
      LiveRunSignal(
        sequence: 0,
        runId: runId,
        workItemId: workItemId,
        kind: LiveRunSignalKind.modelTextDelta,
        timestamp: DateTime.now().toUtc(),
        data: <String, dynamic>{'model': model.toJson(), 'delta': delta},
      );

  factory LiveRunSignal.tool({
    required String runId,
    required String workItemId,
    required String tool,
    required LiveRunSignalKind kind,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) =>
      LiveRunSignal(
        sequence: 0,
        runId: runId,
        workItemId: workItemId,
        kind: kind,
        timestamp: DateTime.now().toUtc(),
        data: <String, dynamic>{'tool': tool, ...data},
      );
}

class LiveRunSignalBus {
  final StreamController<LiveRunSignal> _controller =
      StreamController<LiveRunSignal>.broadcast(sync: true);
  int _sequence = 0;
  bool _closed = false;

  Stream<LiveRunSignal> get stream => _controller.stream;

  Stream<LiveRunSignal> forRun(String runId) =>
      stream.where((signal) => signal.runId == runId);

  void publish(LiveRunSignal signal) {
    if (_closed) return;
    _sequence += 1;
    _controller.add(signal.copyWithSequence(_sequence));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }
}
