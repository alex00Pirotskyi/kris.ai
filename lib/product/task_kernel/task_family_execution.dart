import '../domain.dart';
import 'universal_task_plan.dart';

enum TaskFamilyExecutionState { running, succeeded, failed, interrupted }

enum TaskFamilyTaskState { queued, running, succeeded, failed }

class TaskFamilyTaskProgress {
  const TaskFamilyTaskProgress({
    required this.taskId,
    required this.title,
    required this.phase,
    required this.state,
    this.resultCount = 0,
    this.failure = '',
    this.startedAt,
    this.completedAt,
  });

  final String taskId;
  final String title;
  final String phase;
  final TaskFamilyTaskState state;
  final int resultCount;
  final String failure;
  final DateTime? startedAt;
  final DateTime? completedAt;

  TaskFamilyTaskProgress copyWith({
    TaskFamilyTaskState? state,
    int? resultCount,
    String? failure,
    DateTime? startedAt,
    DateTime? completedAt,
  }) =>
      TaskFamilyTaskProgress(
        taskId: taskId,
        title: title,
        phase: phase,
        state: state ?? this.state,
        resultCount: resultCount ?? this.resultCount,
        failure: failure ?? this.failure,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'taskId': taskId,
        'title': title,
        'phase': phase,
        'state': state.name,
        'resultCount': resultCount,
        if (failure.isNotEmpty) 'failure': failure,
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };

  factory TaskFamilyTaskProgress.fromJson(Map<String, dynamic> json) =>
      TaskFamilyTaskProgress(
        taskId: json['taskId']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        phase: json['phase']?.toString() ?? '',
        state: TaskFamilyTaskState.values
                .where((value) => value.name == json['state']?.toString())
                .firstOrNull ??
            TaskFamilyTaskState.queued,
        resultCount: int.tryParse(json['resultCount']?.toString() ?? '') ?? 0,
        failure: json['failure']?.toString() ?? '',
        startedAt: _date(json['startedAt']),
        completedAt: _date(json['completedAt']),
      );
}

/// Durable execution identity for non-Runner task-family executors.
///
/// A Research execution can exist without a project. [projectId] is optional
/// enrichment/archive context only and never defines the execution boundary.
class TaskFamilyExecutionRecord {
  const TaskFamilyExecutionRecord({
    required this.id,
    required this.family,
    required this.planId,
    required this.specificationId,
    required this.request,
    required this.state,
    required this.tasks,
    required this.createdAt,
    required this.updatedAt,
    this.projectId,
    this.sourceExecutionId,
    this.planSnapshot,
    this.evidence = const <Map<String, String>>[],
    this.answer = '',
    this.failure = '',
    this.completedAt,
  });

  final String id;
  final TaskFamily family;
  final String planId;
  final String specificationId;
  final String request;
  final String? projectId;
  final String? sourceExecutionId;
  final UniversalTaskPlan? planSnapshot;
  final TaskFamilyExecutionState state;
  final List<TaskFamilyTaskProgress> tasks;
  final List<Map<String, String>> evidence;
  final String answer;
  final String failure;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  TaskFamilyExecutionRecord copyWith({
    TaskFamilyExecutionState? state,
    List<TaskFamilyTaskProgress>? tasks,
    List<Map<String, String>>? evidence,
    String? answer,
    String? failure,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) =>
      TaskFamilyExecutionRecord(
        id: id,
        family: family,
        planId: planId,
        specificationId: specificationId,
        request: request,
        projectId: projectId,
        sourceExecutionId: sourceExecutionId,
        planSnapshot: planSnapshot,
        state: state ?? this.state,
        tasks: tasks ?? this.tasks,
        evidence: evidence ?? this.evidence,
        answer: answer ?? this.answer,
        failure: failure ?? this.failure,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        completedAt: completedAt ?? this.completedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'family': family.name,
        'planId': planId,
        'specificationId': specificationId,
        'request': request,
        if (projectId != null) 'projectId': projectId,
        if (sourceExecutionId != null) 'sourceExecutionId': sourceExecutionId,
        if (planSnapshot != null) 'planSnapshot': planSnapshot!.toJson(),
        'state': state.name,
        'tasks': tasks.map((value) => value.toJson()).toList(),
        'evidence': evidence,
        if (answer.isNotEmpty) 'answer': answer,
        if (failure.isNotEmpty) 'failure': failure,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };

  factory TaskFamilyExecutionRecord.fromJson(Map<String, dynamic> json) {
    final family = TaskFamily.values
            .where((value) => value.name == json['family']?.toString())
            .firstOrNull ??
        TaskFamily.research;
    return TaskFamilyExecutionRecord(
      id: json['id']?.toString() ?? newId('family_execution'),
      family: family,
      planId: json['planId']?.toString() ?? '',
      specificationId: json['specificationId']?.toString() ?? '',
      request: json['request']?.toString() ?? '',
      projectId: _nullable(json['projectId']),
      sourceExecutionId: _nullable(json['sourceExecutionId']),
      planSnapshot: json['planSnapshot'] is Map
          ? UniversalTaskPlan.fromJson(mapValue(json['planSnapshot']))
          : null,
      state: TaskFamilyExecutionState.values
              .where((value) => value.name == json['state']?.toString())
              .firstOrNull ??
          TaskFamilyExecutionState.interrupted,
      tasks: (json['tasks'] is List ? json['tasks'] as List : const <Object>[])
          .whereType<Map>()
          .map((value) => TaskFamilyTaskProgress.fromJson(mapValue(value)))
          .toList(growable: false),
      evidence: (json['evidence'] is List
              ? json['evidence'] as List
              : const <Object>[])
          .whereType<Map>()
          .map((value) => <String, String>{
                for (final entry in value.entries)
                  entry.key.toString(): entry.value?.toString() ?? '',
              })
          .toList(growable: false),
      answer: json['answer']?.toString() ?? '',
      failure: json['failure']?.toString() ?? '',
      createdAt: _date(json['createdAt']) ?? DateTime.now().toUtc(),
      updatedAt: _date(json['updatedAt']) ?? DateTime.now().toUtc(),
      completedAt: _date(json['completedAt']),
    );
  }
}

DateTime? _date(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed?.toUtc();
}

String? _nullable(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
