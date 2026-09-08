// Binding the kernel to the real product runtime.
//
// This file is the only place that knows both the kernel's vocabulary
// and PromptPlanningService's. Keeping the translation here is what lets
// the kernel stay a plain, testable, Prompt-Studio-free domain while
// still reusing the production planner rather than reimplementing it.
import '../chat_control_plane.dart';
import '../cognitive/cognitive_model.dart';
import '../cognitive/cognitive_substrate.dart';
import '../domain.dart';
import '../models_research.dart';
import '../prompt_planning.dart';
import '../workspace_tools.dart';
import 'complexity_router.dart';
import 'plan_compiler.dart';
import 'semantic_slash_understanding.dart';
import 'software_family.dart';
import 'task_families.dart';
import 'task_specification.dart';
import 'task_understanding.dart';
import 'task_kernel.dart';

/// Implements the kernel's narrow planning seam over the existing
/// PromptPlanningService.
class PromptPlanningKernelGateway implements KernelPlanningGateway {
  const PromptPlanningKernelGateway({
    required this.planning,
    required this.cognitiveContextKey,
    this.capabilityBriefing = '',
  });

  final PromptPlanningService planning;
  final Object cognitiveContextKey;

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
    final recovery = specification.contextRefs.any(
      (item) => item.startsWith('failure:'),
    );
    String? resolvedProjectId;
    if (recovery) {
      for (final target in specification.targetRefs) {
        if (target.resolved && target.kind == 'project' && target.value.isNotEmpty) {
          resolvedProjectId = target.value;
          break;
        }
      }
    }

    // Ordinary first-stage planning intentionally does not infer a project
    // selection through mutable session state. Autonomic recovery is different:
    // its deterministic specification carries a resolved project target and
    // failure reference, so the recovery pathway can safely retrieve diagnostic
    // history without widening the planning interface or Runner authority.
    final cognitive = await CognitiveModelContextRegistry.compile(
      cognitiveContextKey,
      CognitiveContextRequest(
        objective: specification.originalRequest,
        pathway: recovery
            ? CognitiveReasoningPathway.recovery
            : CognitiveReasoningPathway.taskPlanning,
        projectId: resolvedProjectId,
        selectedModel: model,
        taskFamily: 'software',
        capabilityHints: specification.capabilityHints.toSet(),
        includeProjectKnowledge: recovery,
        includeMemory: recovery,
        maxCharacters: recovery ? 5600 : 5000,
      ),
    );
    final goal = <String>[
      specification.renderForPlanner(),
      if (cognitive != null && cognitive.contextForUserPrompt().trim().isNotEmpty)
        'KRISTIN COGNITIVE CONTEXT — TRUST LABELS ARE AUTHORITATIVE\n${cognitive.contextForUserPrompt()}',
    ].join('\n\n');
    final draft = await planning.generatePrompt(
      // PromptPlanningService places goal in the user message. Cognitive
      // coordinator facts remain labelled and retrieved recovery evidence stays
      // in untrusted AgentContext envelopes rather than system instructions.
      goal: goal,
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
  }) async {
    final cognitive = await CognitiveModelContextRegistry.compile(
      cognitiveContextKey,
      CognitiveContextRequest(
        objective: promptVersion.sourceGoal,
        pathway: CognitiveReasoningPathway.taskPlanning,
        projectId: projectId,
        selectedModel: model,
        taskFamily: 'software',
        // Canonical KnowledgeService retrieval is available because the
        // project identity is explicit. Any project/web/memory text remains an
        // AgentContext untrusted-data envelope in the user-level briefing.
        includeProjectKnowledge: true,
        includeMemory: true,
        maxCharacters: 5200,
      ),
    );
    final briefing = <String>[
      capabilityBriefing,
      if (cognitive != null && cognitive.contextForUserPrompt().trim().isNotEmpty)
        'KRISTIN COGNITIVE CONTEXT — TRUST LABELS ARE AUTHORITATIVE\n${cognitive.contextForUserPrompt()}',
    ].where((item) => item.trim().isNotEmpty).join('\n\n');
    return planning.generateTaskPlan(
      promptVersion: promptVersion,
      projectId: projectId,
      model: model,
      maxLeafTasks: maxLeafTasks,
      capabilityBriefing: briefing,
      cancellation: cancellation,
      isCancelled: isCancelled,
    );
  }

  /// Deterministic code puts the specification's established content back
  /// onto the model's draft so cognitive context cannot weaken constraints.
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
      guardrails: merge(draft.guardrails, <String>[
        ...specification.hardConstraints.map((claim) => claim.statement),
        ...specification.prohibitedEffects.map((effect) => 'Never: $effect'),
      ]),
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

/// Builds the production kernel. The cognitive substrate supplies bounded,
/// trust-labelled context to understanding/planning; UTK remains the single
/// governed planner/compiler and execution keeps its existing run-scoped
/// KnowledgeService retrieval path.
UniversalTaskKernel buildUniversalTaskKernel({
  required PromptPlanningService planning,
  required ToolRegistry tools,
  required ModelRegistry models,
  List<KristinCapability> capabilities = kKristinCapabilities,
  String ownerCapabilityId = 'owner.mode',
  ModelGenerationDelegate? understandingGenerator,
}) {
  final briefing = UnderstandingContext(
    availableCapabilities: capabilities
        .where((capability) => !capability.isCoordinatorCapability)
        .toList(growable: false),
  ).describeCapabilities();
  final gateway = PromptPlanningKernelGateway(
    planning: planning,
    cognitiveContextKey: models,
    capabilityBriefing: briefing,
  );
  final rawUnderstandingGenerate = understandingGenerator ??
      (ModelGenerationRequest request) =>
          models.providerFor(request.identity).generate(request);
  return UniversalTaskKernel(
    understanding: SemanticSlashUnderstandingService(
      model: ModelBackedUnderstanding(
        generate: (request) async {
          final enriched = await CognitiveModelContextRegistry.enrichModelRequest(
            models,
            request,
            pathway: CognitiveReasoningPathway.taskUnderstanding,
            maxCharacters: 5200,
          );
          return rawUnderstandingGenerate(enriched);
        },
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
