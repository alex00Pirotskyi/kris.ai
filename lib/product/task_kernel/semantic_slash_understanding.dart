import '../chat_control_plane.dart';
import '../domain.dart';
import 'planning_failures.dart';
import 'task_specification.dart';
import 'task_understanding.dart';

/// Adds semantic interpretation beneath an explicit slash command without
/// allowing a model to replace the capability selected by that command.
///
/// `/run @project` remains fully deterministic. Commands whose free-text
/// payload materially changes the work (`/create`, `/fix`, `/search`, and
/// project modification) may use the selected model to structure the payload,
/// but the command capability and deterministically resolved targets are
/// reasserted after validation.
class SemanticSlashUnderstandingService extends UnderstandingService {
  const SemanticSlashUnderstandingService({
    super.deterministic,
    super.model,
  });

  static const Set<ChatExecutionRoute> _semanticCommandRoutes =
      <ChatExecutionRoute>{
    ChatExecutionRoute.createProject,
    ChatExecutionRoute.modifyProject,
    ChatExecutionRoute.fixProject,
    ChatExecutionRoute.researchSearch,
  };

  @override
  bool warrantsModelUnderstanding(ChatInteractionDecision decision) {
    if (!decision.parsed.hasExplicitCommand) {
      return super.warrantsModelUnderstanding(decision);
    }
    if (model == null ||
        decision.kind == ChatInteractionKind.reference ||
        decision.kind == ChatInteractionKind.informational) {
      return false;
    }
    final capability = decision.capability;
    if (capability == null ||
        capability.understandingPolicy == ChatUnderstandingPolicy.never) {
      return false;
    }
    return _semanticCommandRoutes.contains(capability.route) &&
        _semanticPayload(decision).isNotEmpty;
  }

  @override
  Future<UnderstandingOutcome> understand({
    required ChatInteractionDecision decision,
    required UnderstandingContext context,
    ModelIdentity? modelIdentity,
    String? specificationId,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  }) async {
    if (!decision.parsed.hasExplicitCommand ||
        !warrantsModelUnderstanding(decision) ||
        model == null ||
        modelIdentity == null) {
      return super.understand(
        decision: decision,
        context: context,
        modelIdentity: modelIdentity,
        specificationId: specificationId,
        cancellation: cancellation,
        isCancelled: isCancelled,
      );
    }

    final lockedCapability = decision.capability;
    if (lockedCapability == null) {
      return deterministic.understand(
        decision,
        specificationId: specificationId,
      );
    }

    try {
      final outcome = await model!.understand(
        request: _semanticPayload(decision),
        model: modelIdentity,
        context: context,
        specificationId: specificationId,
        cancellation: cancellation,
        isCancelled: isCancelled,
      );

      final rejections = <String>[...outcome.rejections];
      for (final capabilityId in outcome.capabilityHints) {
        if (capabilityId != lockedCapability.id) {
          rejections.add(
            'capabilityHints: explicit command locks capability '
            '"${lockedCapability.id}"; model hint "$capabilityId" ignored.',
          );
        }
      }

      final targetIds = outcome.specification.targetRefs
          .map((target) => target.value)
          .toSet();
      final targets = <TaskTargetRef>[
        ...outcome.specification.targetRefs,
        for (final target in decision.targets)
          if (targetIds.add(target.id))
            TaskTargetRef(
              kind: target.type.name,
              value: target.id,
              displayName: target.displayName,
              provenance: EvidenceProvenance.observed,
              resolved: true,
            ),
      ];

      final questionKeys = <String>{};
      final questions = <UnresolvedQuestion>[];
      void addQuestion(UnresolvedQuestion question) {
        final key = question.question.trim().toLowerCase();
        if (key.isEmpty || !questionKeys.add(key)) return;
        questions.add(
          UnresolvedQuestion(
            question: question.question,
            options: question.options,
            blocking: true,
          ),
        );
      }

      for (final question in outcome.specification.unresolvedQuestions) {
        addQuestion(question);
      }
      for (final mention in decision.unresolvedMentions) {
        addQuestion(
          UnresolvedQuestion(
            question: 'Which target does "@$mention" refer to?',
            blocking: true,
          ),
        );
      }

      final specification = outcome.specification.copyWith(
        originalRequest: decision.parsed.originalText,
        targetRefs: targets,
        unresolvedQuestions: questions,
        capabilityHints: <String>[lockedCapability.id],
      );
      final errors = specification.validate();
      if (errors.isNotEmpty) {
        throw PlanningFailure(
          kind: PlanningFailureKind.recoverablePlanning,
          code: 'semantic_slash_specification_invalid',
          message: 'The semantic slash-command interpretation did not '
              'validate: ${errors.join(' ')}',
          details: <String, dynamic>{'errors': errors},
        );
      }
      return UnderstandingOutcome(
        specification: specification,
        path: outcome.path,
        rejections: List<String>.unmodifiable(rejections),
        capabilityHints: <String>[lockedCapability.id],
      );
    } catch (error, stackTrace) {
      final failure = classifyPlanningFailure(error, stackTrace: stackTrace);
      if (failure.allowsConservativeFallback) {
        return deterministic.understand(
          decision,
          specificationId: specificationId,
        );
      }
      throw failure;
    }
  }

  static String _semanticPayload(ChatInteractionDecision decision) =>
      decision.parsed.arguments
          .replaceAll(RegExp(r'@[A-Za-z0-9][A-Za-z0-9._:-]*'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
}
