import 'domain.dart';
import 'task_kernel/task_specification_patch.dart';

enum RunSteeringRecordState { pending, replanning, applied, cleared }

class RunSteeringRecord {
  const RunSteeringRecord({
    required this.id,
    required this.runId,
    required this.text,
    required this.patch,
    required this.state,
    required this.createdAt,
    this.workItemId,
    this.appliedAt,
    this.continuationRunId,
    this.reconciliation = const <Map<String, dynamic>>[],
  });

  final String id;
  final String runId;
  final String text;
  final TaskSpecificationPatch patch;
  final RunSteeringRecordState state;
  final DateTime createdAt;
  final String? workItemId;
  final DateTime? appliedAt;
  final String? continuationRunId;
  final List<Map<String, dynamic>> reconciliation;

  RunSteeringRecord copyWith({
    RunSteeringRecordState? state,
    String? workItemId,
    DateTime? appliedAt,
    String? continuationRunId,
    List<Map<String, dynamic>>? reconciliation,
  }) =>
      RunSteeringRecord(
        id: id,
        runId: runId,
        text: text,
        patch: patch,
        state: state ?? this.state,
        createdAt: createdAt,
        workItemId: workItemId ?? this.workItemId,
        appliedAt: appliedAt ?? this.appliedAt,
        continuationRunId: continuationRunId ?? this.continuationRunId,
        reconciliation: reconciliation ?? this.reconciliation,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'runId': runId,
        'text': text,
        'patch': patch.toJson(),
        'state': state.name,
        'createdAt': createdAt.toIso8601String(),
        if (workItemId != null) 'workItemId': workItemId,
        if (appliedAt != null) 'appliedAt': appliedAt!.toIso8601String(),
        if (continuationRunId != null) 'continuationRunId': continuationRunId,
        if (reconciliation.isNotEmpty) 'reconciliation': reconciliation,
      };

  factory RunSteeringRecord.fromJson(Map<String, dynamic> json) =>
      RunSteeringRecord(
        id: json['id']?.toString() ?? newId('steer'),
        runId: json['runId']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        patch: TaskSpecificationPatch.fromJson(mapValue(json['patch'])),
        state: RunSteeringRecordState.values
                .where((value) => value.name == json['state']?.toString())
                .firstOrNull ??
            RunSteeringRecordState.pending,
        createdAt: _date(json['createdAt']) ?? DateTime.now().toUtc(),
        workItemId: _nullable(json['workItemId']),
        appliedAt: _date(json['appliedAt']),
        continuationRunId: _nullable(json['continuationRunId']),
        reconciliation: (json['reconciliation'] is List
                ? json['reconciliation'] as List
                : const <Object>[])
            .whereType<Map>()
            .map((value) => mapValue(value))
            .toList(growable: false),
      );
}

DateTime? _date(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toUtc();

String? _nullable(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
