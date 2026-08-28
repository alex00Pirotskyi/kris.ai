// The software task family: create / modify / fix.
//
// This is where the value of the predecessor change (PR #288) is
// preserved. PromptPlanningService already contains a good, tested,
// production model planner: it generates a request-specific,
// dependency-validated, capability-checked task graph and repairs it once
// on validation failure. Nothing here rewrites it.
//
// What changes is ownership and coupling:
//
//   before   Chat -> generatePromptDraft -> saveGeneratedPrompt
//                 -> generateTaskPlan -> prepareTaskPlan
//            (ordinary Chat planning went through Prompt Studio's
//             prompt/version PERSISTENCE workflow)
//
//   after    Chat -> kernel.plan(specification)
//                 -> SoftwareTaskFamilyPlanner -> the same generator
//            (the prompt version is built in memory and never saved;
//             Prompt Studio persists one only when the user opens
//             Prompt Studio and asks for it)
//
// The user does not acquire a Prompt Studio artifact as a side effect of
// asking Kristin to do something.
import '../crypto_utils.dart';
import '../domain.dart';
import 'planning_failures.dart';
import 'task_families.dart';
import 'task_specification.dart';
import 'universal_task_plan.dart';

/// The narrow seam the software planner needs from the existing planning
/// machinery.
///
/// Deliberately smaller than PromptPlanningService: the kernel depends on
/// "generate a draft" and "generate a task plan", not on the prompt
/// library, versioning, evaluation datasets, or anything else Prompt
/// Studio owns. That is what decouples ordinary planning from Prompt
/// Studio without rewriting the planner.
abstract class KernelPlanningGateway {
  /// Produces a structured draft for [specification] without saving a
  /// prompt or a prompt version anywhere.
  Future<PromptStudioDraft> draftFor({
    required TaskSpecification specification,
    required ModelIdentity model,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  });

  /// Generates a validated task graph from an (possibly ephemeral)
  /// prompt version.
  Future<TaskPlanRecord> generateTaskPlan({
    required PromptVersionRecord promptVersion,
    required String projectId,
    required ModelIdentity model,
    int maxLeafTasks,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  });
}

/// Builds an in-memory [PromptVersionRecord] that is never persisted.
///
/// PromptPlanningService.generateTaskPlan reads the version (for the
/// prompt text it plans against) but does not require it to exist in any
/// repository, so an ephemeral one is enough. This is the whole
/// mechanism behind the ephemeral planning path -- no new planner, no
/// forked code path, just not writing a Prompt Studio row nobody asked
/// for.
PromptVersionRecord ephemeralPromptVersion({
  required TaskSpecification specification,
  required PromptStudioDraft draft,
  required ModelIdentity model,
}) {
  final contentHash = Sha256.text(
    canonicalJson(<String, dynamic>{
      'specification': specification.contentKey,
      'draft': draft.toJson(),
    }),
  );
  return PromptVersionRecord(
    // A stable, clearly-marked ephemeral identity: nothing downstream can
    // mistake this for a saved Prompt Studio version.
    id: 'ephemeral_prompt_version_$contentHash',
    promptId: 'ephemeral_prompt_${specification.contentKey}',
    versionNumber: 1,
    sourceGoal: specification.originalRequest,
    action: PromptGenerationAction.generate,
    draft: draft,
    model: model,
    contentHash: contentHash,
    createdBy: 'kernel',
    createdAt: DateTime.now().toUtc(),
  );
}

/// True when a prompt version was produced by the ephemeral planning path
/// rather than saved through Prompt Studio.
bool isEphemeralPromptVersion(PromptVersionRecord version) =>
    version.id.startsWith('ephemeral_prompt_version_');

/// Plans create/modify/fix work by reusing the existing model planner.
class SoftwareTaskFamilyPlanner implements TaskFamilyPlanner {
  const SoftwareTaskFamilyPlanner({
    required this.gateway,
    this.conservative = const ConservativeSoftwarePlanner(),
  });

  final KernelPlanningGateway gateway;

  /// Used for the compact route, where a full model decomposition is not
  /// worth its latency, and as the documented fallback shape.
  final ConservativeSoftwarePlanner conservative;

  @override
  TaskFamily get family => TaskFamily.software;

  @override
  bool supports(TaskSpecification specification, PlanningRoute route) =>
      route != PlanningRoute.direct;

  @override
  Future<UniversalTaskPlan> plan({
    required TaskSpecification specification,
    required PlanningRoute route,
    required PlanningContext context,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  }) async {
    if (route == PlanningRoute.compact) {
      return conservative.plan(
        specification: specification,
        route: route,
        context: context,
        cancellation: cancellation,
        isCancelled: isCancelled,
      );
    }
    final model = context.model;
    final project = context.project;
    if (model == null) {
      throw const PlanningFailure(
        kind: PlanningFailureKind.providerUnavailable,
        code: 'model_not_selected',
        message: 'A model must be connected before Kristin can plan a '
            'substantial software task.',
      );
    }
    if (project == null) {
      throw const PlanningFailure(
        kind: PlanningFailureKind.unexpected,
        code: 'project_missing',
        message: 'A software task plan requires an active project.',
      );
    }
    final draft = await gateway.draftFor(
      specification: specification,
      model: model,
      cancellation: cancellation,
      isCancelled: isCancelled,
    );
    // Ephemeral: nothing is written to the prompt library.
    final version = ephemeralPromptVersion(
      specification: specification,
      draft: draft,
      model: model,
    );
    final record = await gateway.generateTaskPlan(
      promptVersion: version,
      projectId: project.id,
      model: model,
      maxLeafTasks: context.maxLeafTasks,
      cancellation: cancellation,
      isCancelled: isCancelled,
    );
    final capability = specification.capabilityHints
        .where(context.availableCapabilityIds.contains)
        .toSet();
    return UniversalTaskPlan(
      id: newId('universal_plan'),
      specification: specification,
      family: TaskFamily.software,
      route: route,
      title: record.title,
      rationale: record.rationale,
      // The adapter that keeps phase/parentId/dependencies intact instead
      // of flattening them into prose.
      tasks: record.tasks
          .map(
            (task) => UniversalTask.fromPlanTask(
              task,
              requiredCapabilities: capability,
            ),
          )
          .toList(growable: false),
    );
  }
}
