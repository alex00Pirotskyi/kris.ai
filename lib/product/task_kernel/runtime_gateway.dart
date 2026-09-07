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
    final cognitive = await CognitiveModelContextRegistry.compile(
      cognitiveContextKey,
      CognitiveContextRequest(
        objective: specification.originalRequest,
        pathway: CognitiveReasoningPathway.taskPlanning,
        selectedModel: model,
        taskFamily: 'software',
        capabilityHints: specification.capabilityHints.toSet(),
        maxCharacters: 5600,
      ),
    );
    final executionCognitive = await CognitiveModelContextRegistry.compile(
      cognitiveContextKey,
      CognitiveContextRequest(
        objective: specification.originalRequest,
        pathway: CognitiveReasoningPathway.execution,
        selectedModel: model,
        taskFamily: 'software',
        capabilityHints: specification.capabilityHints.toSet(),
        maxCharacters: 4400,
      ),
    );
    if (executionCognitive != null) {
      CognitiveExecutionContextCache.put(
        specification.originalRequest,
        executionCognitive,
      );
    }
    final goal = cognitive == null
        ? specification.renderForPlanner()
        : '''
$kKristinReasoningModelFrame

AUTHORITATIVE KRISTIN COGNITIVE CONTEXT
${cognitive.rendered}

TASK SPECIFICATION
${specification.renderForPlanner()}
''';
    final draft = await planning.generatePrompt(
      // The planner receives typed task structure plus a bounded cognitive
      // projection. This context is read-only and cannot alter tool grants.
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
        maxCharacters: 4400,
      ),
    );
    final briefing = <String>[
      capabilityBriefing,
      if (cognitive != null)
        '$kKristinReasoningModelFrame\n\nAUTHORITATIVE KRISTIN COGNITIVE CONTEXT\n${cognitive.rendered}',
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

/// Builds the production kernel. The cognitive substrate supplies context to
/// understanding/planning; UTK remains the single governed planner/compiler.
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
