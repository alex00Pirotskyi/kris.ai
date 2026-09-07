import 'dart:convert';

import '../domain.dart';
import '../models_research.dart';
import '../storage_security.dart';
import 'task_specification.dart';
import 'task_specification_patch.dart';

typedef TaskSpecificationPatchGeneration = Future<ModelGenerationResult>
    Function(ModelGenerationRequest request);

/// Model-backed semantic classifier for mid-task steering.
///
/// The model is allowed to classify the user's meaning into the small patch
/// vocabulary. It is not allowed to edit the specification directly: the
/// returned proposal is decoded and then validated by [TaskSpecificationPatch]
/// before the caller may replan.
class ModelTaskSpecificationPatchClassifier
    implements TaskSpecificationPatchClassifier {
  const ModelTaskSpecificationPatchClassifier({
    required this.model,
    required this.generate,
  });

  final ModelIdentity model;
  final TaskSpecificationPatchGeneration generate;

  @override
  Future<TaskSpecificationPatch> classify({
    required TaskSpecification specification,
    required String userMessage,
  }) async {
    final message = userMessage.trim();
    if (message.isEmpty) {
      throw ProductException(
        'task_specification_patch_empty',
        'A steering message must not be empty.',
      );
    }
    final result = await generate(
      ModelGenerationRequest(
        identity: model,
        commandId: newId('task_patch'),
        systemPrompt: '''
You classify one user steering message against an active task specification.
Return exactly one JSON object and no markdown.
Allowed kind values:
- objective: change what outcome should be achieved
- hardConstraint: a new rule that must never be violated
- preference: a desirable trade-off, not mandatory
- requestedMethod: an explicitly requested implementation approach
- priority: what should be done first or optimized for
- stopCondition: a condition that must stop further work
- clarificationAnswer: an answer to one currently unresolved question

Schema:
{"kind":"objective|hardConstraint|preference|requestedMethod|priority|stopCondition|clarificationAnswer","value":"user-stated semantic content","question":"exact pending question when kind=clarificationAnswer, otherwise empty","reason":"brief classification rationale"}

Do not invent permissions, capabilities, targets, facts, or constraints the user did not state. Do not convert a preference into a hard constraint. For clarificationAnswer, copy the exact pending question from the specification.
''',
        userPrompt: 'ACTIVE SPECIFICATION\n'
            '${jsonEncode(specification.toJson())}\n\n'
            'USER STEERING MESSAGE\n$message',
        temperature: 0.0,
        maxOutputTokens: 500,
        firstTokenTimeout: const Duration(minutes: 2),
        totalTimeout: const Duration(minutes: 3),
      ),
    );

    final raw = result.text.trim();
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw ProductException(
        'task_specification_patch_invalid',
        'The model did not return a valid semantic steering object.',
      );
    }
    if (decoded is! Map) {
      throw ProductException(
        'task_specification_patch_invalid',
        'The semantic steering response must be a JSON object.',
      );
    }
    TaskSpecificationPatch patch;
    try {
      patch = TaskSpecificationPatch.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      patch.applyTo(specification);
    } on TaskSpecificationPatchException catch (error) {
      throw ProductException(error.code, error.message);
    }
    return patch;
  }
}
