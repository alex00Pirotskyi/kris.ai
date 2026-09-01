import 'domain.dart';

enum AgentDelegationState { running, succeeded, failed, interrupted }

class AgentDelegationRecord {
  const AgentDelegationRecord({
    required this.id,
    required this.parentRunId,
    required this.workItemId,
    required this.parentAttempt,
    required this.destination,
    required this.task,
    required this.inputs,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.attempts = 0,
    this.result = '',
    this.resultSha256 = '',
    this.failure = '',
    this.completedAt,
  });

  final String id;
  final String parentRunId;
  final String workItemId;
  final int parentAttempt;
  final String destination;
  final String task;
  final Map<String, dynamic> inputs;
  final AgentDelegationState state;
  final int attempts;
  final String result;
  final String resultSha256;
  final String failure;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  AgentDelegationRecord copyWith({
    AgentDelegationState? state,
    int? attempts,
    String? result,
    String? resultSha256,
    String? failure,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) =>
      AgentDelegationRecord(
        id: id,
        parentRunId: parentRunId,
        workItemId: workItemId,
        parentAttempt: parentAttempt,
        destination: destination,
        task: task,
        inputs: inputs,
        state: state ?? this.state,
        attempts: attempts ?? this.attempts,
        result: result ?? this.result,
        resultSha256: resultSha256 ?? this.resultSha256,
        failure: failure ?? this.failure,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        completedAt:
            clearCompletedAt ? null : (completedAt ?? this.completedAt),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'parentRunId': parentRunId,
        'workItemId': workItemId,
        'parentAttempt': parentAttempt,
        'destination': destination,
        'task': task,
        'inputs': inputs,
        'state': state.name,
        'attempts': attempts,
        if (result.isNotEmpty) 'result': result,
        if (resultSha256.isNotEmpty) 'resultSha256': resultSha256,
        if (failure.isNotEmpty) 'failure': failure,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };

  factory AgentDelegationRecord.fromJson(Map<String, dynamic> json) =>
      AgentDelegationRecord(
        id: json['id']?.toString() ?? newId('delegation'),
        parentRunId: json['parentRunId']?.toString() ?? '',
        workItemId: json['workItemId']?.toString() ?? '',
        parentAttempt:
            int.tryParse(json['parentAttempt']?.toString() ?? '') ?? 0,
        destination: json['destination']?.toString() ?? '',
        task: json['task']?.toString() ?? '',
        inputs: mapValue(json['inputs']),
        attempts: int.tryParse(json['attempts']?.toString() ?? '') ?? 0,
        state: AgentDelegationState.values
                .where((value) => value.name == json['state']?.toString())
                .firstOrNull ??
            AgentDelegationState.failed,
        result: json['result']?.toString() ?? '',
        resultSha256: json['resultSha256']?.toString() ?? '',
        failure: json['failure']?.toString() ?? '',
        createdAt: _date(json['createdAt']) ?? DateTime.now().toUtc(),
        updatedAt: _date(json['updatedAt']) ?? DateTime.now().toUtc(),
        completedAt: _date(json['completedAt']),
      );
}

DateTime? _date(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toUtc();
