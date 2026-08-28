// Binding the kernel to the real product runtime.
//
// This file is the only place that knows both the kernel's vocabulary
// and PromptPlanningService's. Keeping the translation here is what lets
// the kernel stay a plain, testable, Prompt-Studio-free domain while
// still reusing the production planner rather than reimplementing it.
import '../chat_control_plane.dart';
import '../domain.dart';
import '../models_research.dart';
import '../prompt_planning.dart';
import '../workspace_tools.dart';
import 'complexity_router.dart';
import 'plan_compiler.dart';
import 'software_family.dart';
import 'task_families.dart';
import 'task_specification.dart';
import 'task_understanding.dart';
import 'task_kernel.dart';

/// Implements the kernel's narrow planning seam over the existing
/// PromptPlanningService.
///
/// Two responsibilities beyond plain delegation:
///
///   * the specification's structure reaches the model as structure
///     (renderForPlanner), not as a flattened request string; and
///   * the specification's established facts are re-asserted onto the
///     model's draft afterwards, so a hard constraint the user stated
///     cannot be dropped by a generator that decided it was optional.
class PromptPlanningKernelGateway implements KernelPlanningGateway {
  const PromptPlanningKernelGateway({
    required this.planning,
    this.capabilityBriefing = '',
  });

  final PromptPlanningService planning;

  /// What Kristin can actually do right now, handed to the planning model
  /// so it plans against real capabilities. Availability, not authority.
  final String capabilityBriefing;

  @override
  Future<PromptStudioDraft> draftFor({
    required TaskSpecification specification,
    required ModelIdentity model,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  }) async {
    final draft = await planning.generatePrompt(
      // The planner receives the semantic sections -- objective, hard
      // constraints, preferences, criteria -- rather than a re-flattened
      // sentence.
      goal: specification.renderForPlanner(),
      model: model,
      cancellation: cancellation,
      isCancelled: isCancelled,
    );
    return _reassertSpecification(draft, specification);
  }

  @override
  Future<TaskPlanRecord> generateTaskPlan({
    required PromptVersionRecord promptVersion,
    required String projectId,
    required ModelIdentity model,
    int maxLeafTasks = 25,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  }) =>
      planning.generateTaskPlan(
        promptVersion: promptVersion,
        projectId: projectId,
        model: model,
        maxLeafTasks: maxLeafTasks,
        capabilityBriefing: capabilityBriefing,
        cancellation: cancellation,
        isCancelled: isCancelled,
      );

  /// Deterministic code puts the specification's established content back
  /// onto the model's draft.
  ///
  /// This is the mechanism behind the constraint scenario: "make this app
  /// faster but don't touch the database" keeps "the database must not be
  /// modified" as a guardrail on the draft the planner plans against,
  /// whatever the draft generator chose to write.
  PromptStudioDraft _reassertSpecification(
    PromptStudioDraft draft,
    TaskSpecification specification,
  ) {
    List<String> merge(List<String> existing, Iterable<String> required) {
      final seen = existing
          .map((item) => item.trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toSet();
      return <String>[
        ...existing,
        for (final item in required)
          if (item.trim().isNotEmpty && seen.add(item.trim().toLowerCase()))
            item.trim(),
      ];
    }

    return draft.copyWith(
      guardrails: merge(
        draft.guardrails,
        <String>[
          ...specification.hardConstraints.map((claim) => claim.statement),
          ...specification.prohibitedEffects.map((effect) => 'Never: $effect'),
        ],
      ),
      acceptanceCriteria: merge(
        draft.acceptanceCriteria,
        specification.successCriteria.map((claim) => claim.statement),
      ),
      assumptions: merge(
        draft.assumptions,
        specification.assumptions.map((claim) => claim.statement),
      ),
      clarifyingQuestions: merge(
        draft.clarifyingQuestions,
        specification.unresolvedQuestions.map((item) => item.question),
      ),
    );
  }
}

/// Builds the production kernel.
///
/// Every task family is registered here. Adding Browser later means
/// adding one planner to this list -- not a second planning architecture.
UniversalTaskKernel buildUniversalTaskKernel({
  required PromptPlanningService planning,
  required ToolRegistry tools,
  required ModelRegistry models,
  List<KristinCapability> capabilities = kKristinCapabilities,
  String ownerCapabilityId = 'owner.mode',
  ModelGenerationDelegate? understandingGenerator,
}) {
  final briefing = UnderstandingContext(
    availableCapabilities: capabilities,
  ).describeCapabilities();
  final gateway = PromptPlanningKernelGateway(
    planning: planning,
    capabilityBriefing: briefing,
  );
  return UniversalTaskKernel(
    understanding: UnderstandingService(
      model: ModelBackedUnderstanding(
        generate: understandingGenerator ??
            (request) => models.providerFor(request.identity).generate(request),
      ),
    ),
    compiler: UniversalPlanCompiler(tools: tools),
    router: ComplexityRouter(
      registry: ChatCapabilityRegistry(capabilities: capabilities),
    ),
    planners: <TaskFamilyPlanner>[
      SoftwareTaskFamilyPlanner(gateway: gateway),
      const ResearchTaskFamilyPlanner(),
      const DiagnosticsTaskFamilyPlanner(),
      OwnerTaskFamilyPlanner(capabilityId: ownerCapabilityId),
    ],
  );
}
