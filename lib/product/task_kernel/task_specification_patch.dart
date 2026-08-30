import 'task_specification.dart';

/// Semantic kinds of user steering that may change an active task.
///
/// Steering is expressed against the structured specification instead of by
/// concatenating prose onto the old request. This preserves the distinction
/// between objective, hard constraints, preferences, method, priorities and
/// clarification answers all the way into replanning.
enum TaskSpecificationPatchKind {
  objective,
  hardConstraint,
  preference,
  requestedMethod,
  priority,
  stopCondition,
  clarificationAnswer,
}

class TaskSpecificationPatchException implements Exception {
  const TaskSpecificationPatchException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class TaskSpecificationPatch {
  const TaskSpecificationPatch({
    required this.kind,
    required this.value,
    this.question = '',
    this.reason = '',
  });

  final TaskSpecificationPatchKind kind;
  final String value;
  final String question;
  final String reason;

  TaskSpecification applyTo(TaskSpecification specification) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const TaskSpecificationPatchException(
        'task_specification_patch_empty',
        'A semantic steering patch must contain a non-empty value.',
      );
    }

    switch (kind) {
      case TaskSpecificationPatchKind.objective:
        return specification.copyWith(objective: normalized);
      case TaskSpecificationPatchKind.hardConstraint:
        return specification.copyWith(
          hardConstraints: _appendClaim(
            specification.hardConstraints,
            SpecificationClaim.stated(normalized, source: 'conversation_steering'),
          ),
        );
      case TaskSpecificationPatchKind.preference:
        return specification.copyWith(
          preferences: _appendClaim(
            specification.preferences,
            SpecificationClaim.stated(normalized, source: 'conversation_steering'),
          ),
        );
      case TaskSpecificationPatchKind.requestedMethod:
        return specification.copyWith(requestedMethod: normalized);
      case TaskSpecificationPatchKind.priority:
        return specification.copyWith(
          preferences: _appendClaim(
            specification.preferences,
            SpecificationClaim.stated(
              'Priority: $normalized',
              source: 'conversation_steering',
            ),
          ),
        );
      case TaskSpecificationPatchKind.stopCondition:
        return specification.copyWith(
          hardConstraints: _appendClaim(
            specification.hardConstraints,
            SpecificationClaim.stated(
              'Stop condition: $normalized',
              source: 'conversation_steering',
            ),
          ),
        );
      case TaskSpecificationPatchKind.clarificationAnswer:
        final requestedQuestion = question.trim();
        if (requestedQuestion.isEmpty) {
          throw const TaskSpecificationPatchException(
            'task_specification_patch_question_missing',
            'A clarification answer must identify the question it answers.',
          );
        }
        final matching = specification.unresolvedQuestions.where(
          (item) => _sameText(item.question, requestedQuestion),
        );
        if (matching.isEmpty) {
          throw TaskSpecificationPatchException(
            'task_specification_patch_question_unknown',
            'The clarification question is not pending on this task: $requestedQuestion',
          );
        }
        return specification.copyWith(
          unresolvedQuestions: specification.unresolvedQuestions
              .where((item) => !_sameText(item.question, requestedQuestion))
              .toList(growable: false),
          assumptions: _appendClaim(
            specification.assumptions,
            SpecificationClaim.stated(
              'Clarification — $requestedQuestion: $normalized',
              source: 'conversation_clarification',
            ),
          ),
        );
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind.name,
        'value': value,
        if (question.trim().isNotEmpty) 'question': question.trim(),
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      };

  factory TaskSpecificationPatch.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind']?.toString() ?? '';
    final kind = TaskSpecificationPatchKind.values
        .where((candidate) => candidate.name == kindName)
        .firstOrNull;
    if (kind == null) {
      throw TaskSpecificationPatchException(
        'task_specification_patch_kind_invalid',
        'Unknown semantic steering patch kind: $kindName',
      );
    }
    return TaskSpecificationPatch(
      kind: kind,
      value: json['value']?.toString() ?? '',
      question: json['question']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
    );
  }

  static List<SpecificationClaim> _appendClaim(
    List<SpecificationClaim> existing,
    SpecificationClaim addition,
  ) {
    final normalized = addition.statement.trim().toLowerCase();
    if (existing.any(
      (claim) => claim.statement.trim().toLowerCase() == normalized,
    )) {
      return existing;
    }
    return List<SpecificationClaim>.unmodifiable(<SpecificationClaim>[
      ...existing,
      addition,
    ]);
  }

  static bool _sameText(String left, String right) =>
      left.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') ==
      right.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

abstract interface class TaskSpecificationPatchClassifier {
  Future<TaskSpecificationPatch> classify({
    required TaskSpecification specification,
    required String userMessage,
  });
}
