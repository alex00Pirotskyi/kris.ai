import 'dart:convert';
import 'dart:math';

import '../domain.dart';
import '../models_research.dart';
import '../product_runtime.dart';
import '../product_runtime_self_awareness.dart';
import '../self_awareness/capability_self_model.dart';
import '../task_kernel/task_kernel.dart';
import 'cognitive_model.dart';
import 'cognitive_substrate.dart';

/// Read-only product composition point for Kristin's cognitive substrate.
///
/// This gateway exposes epistemic state only. It cannot mint grants, execute
/// tools, enter Owner Mode, mutate host/project state, or change Runner tools.
final class ProductRuntimeCognitiveGateway {
  ProductRuntimeCognitiveGateway._(this.runtime) {
    awareness = ProductSelfAwarenessRuntime.shared(runtime);
    substrate = KristinCognitiveSubstrate(
      loadSelfSnapshot: ({
        ProjectRecord? selectedProject,
        ModelIdentity? selectedModel,
        bool forceRefresh = false,
      }) =>
          awareness.snapshot(
        selectedProject: selectedProject,
        selectedModel: selectedModel,
        forceRefresh: forceRefresh,
      ),
      loadProject: runtime.getProject,
      loadKnowledge: runtime.listKnowledge,
      loadMemory: runtime.listMemoryEpisodes,
      loadPublishedSkills: runtime.listPublishedSkills,
      loadSkillCandidates: runtime.listSkillCandidates,
      retrieveKnowledge: runtime.searchKnowledge,
      sanitizeDiagnostic: (error) => runtime.redactor.redact('$error'),
    );
    CognitiveModelContextRegistry.register(runtime.models, substrate.compile);
    KernelSelfModelRegistry.register(
      runtime.taskKernel,
      ({
        required ProjectRecord? project,
        required ModelIdentity? model,
        required Set<String> relevantCapabilityIds,
      }) =>
          planningContext(
        selectedProject: project,
        selectedModel: model,
        relevantCapabilityIds: relevantCapabilityIds,
      ),
    );
  }

  static final Expando<ProductRuntimeCognitiveGateway> _instances =
      Expando<ProductRuntimeCognitiveGateway>('product-runtime-cognitive');

  static ProductRuntimeCognitiveGateway shared(ProductRuntime runtime) {
    final existing = _instances[runtime];
    if (existing != null) return existing;
    final created = ProductRuntimeCognitiveGateway._(runtime);
    _instances[runtime] = created;
    return created;
  }

  final ProductRuntime runtime;
  late final ProductSelfAwarenessRuntime awareness;
  late final KristinCognitiveSubstrate substrate;

  Future<KristinCognitiveSnapshot> stateInspect({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    bool forceRefresh = false,
    List<String> workingMemory = const <String>[],
  }) =>
      substrate.snapshot(
        selectedProject: selectedProject,
        selectedModel: selectedModel,
        forceRefresh: forceRefresh,
        workingMemory: workingMemory,
      );

  Future<CognitiveContextProjection> context({
    required String objective,
    CognitiveReasoningPathway pathway = CognitiveReasoningPathway.conversation,
    ProjectRecord? selectedProject,
    String? projectId,
    ModelIdentity? selectedModel,
    String sessionKey = 'chat',
    String taskFamily = '',
    Set<String> capabilityHints = const <String>{},
    List<String> workingMemory = const <String>[],
    int maxCharacters = 7200,
    bool forceRefresh = false,
    bool? includeProjectKnowledge,
    bool? includeMemory,
    bool? includePublishedSkills,
  }) =>
      substrate.compile(CognitiveContextRequest(
        objective: objective,
        pathway: pathway,
        selectedProject: selectedProject,
        projectId: projectId,
        selectedModel: selectedModel,
        sessionKey: sessionKey,
        taskFamily: taskFamily,
        capabilityHints: capabilityHints,
        workingMemory: workingMemory,
        maxCharacters: maxCharacters,
        forceRefresh: forceRefresh,
        includeProjectKnowledge: includeProjectKnowledge,
        includeMemory: includeMemory,
        includePublishedSkills: includePublishedSkills,
      ));

  Future<SelfModelPlanningContext> planningContext({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    Set<String> relevantCapabilityIds = const <String>{},
  }) async {
    final self = await awareness.planningContext(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
      relevantCapabilityIds: relevantCapabilityIds,
    );
    final cognitive = await context(
      objective: relevantCapabilityIds.isEmpty
          ? 'Reason about the current task using Kristin state.'
          : 'Reason about capabilities ${relevantCapabilityIds.join(', ')}.',
      pathway: CognitiveReasoningPathway.taskPlanning,
      selectedProject: selectedProject,
      selectedModel: selectedModel,
      sessionKey: 'kernel',
      capabilityHints: relevantCapabilityIds,
      // SelfModelPlanningContext is trusted planning metadata. Project/web/run
      // evidence remains on the user/evidence side of model prompts and is not
      // copied into this coordinator summary.
      includeProjectKnowledge: false,
      includeMemory: false,
      maxCharacters: 5200,
    );
    return SelfModelPlanningContext(
      summary: _bounded('${self.summary}\n\n${cognitive.rendered}', 7000),
      availableCapabilityIds: self.availableCapabilityIds,
      blockedCapabilityReasons: self.blockedCapabilityReasons,
      currentAuthority: self.currentAuthority,
      relevantCapabilities: self.relevantCapabilities,
      freshnessWarnings: self.freshnessWarnings,
      authorityNotEvaluated: self.authorityNotEvaluated,
    );
  }

  /// Semantic routing only. The classifier intentionally receives no project
  /// knowledge, prior-run memory, or published procedures; product concepts
  /// and fresh self/capability state are enough to distinguish an information
  /// question from a request for effects. Failure returns null so the existing
  /// deterministic policy remains the fail-closed fallback.
  Future<CognitiveConversationDecision?> classifyConversation({
    required String message,
    required ModelIdentity model,
    ProjectRecord? selectedProject,
    List<String> workingMemory = const <String>[],
  }) async {
    final projection = await context(
      objective: message,
      pathway: CognitiveReasoningPathway.conversation,
      selectedProject: selectedProject,
      selectedModel: model,
      sessionKey: 'chat-classification',
      workingMemory: workingMemory,
      maxCharacters: 5000,
      includeProjectKnowledge: false,
      includeMemory: false,
      includePublishedSkills: false,
    );
    final request = ModelGenerationRequest(
      identity: model,
      systemPrompt: projection.wrapSystemPrompt('''
Classify the user's intent for routing only. Return one JSON object with keys kind, objective, capabilityId, confidence, rationale.
kind must be knowledge_only, effectful_objective, or unclear.
Questions asking what a Kristin facility is, what it can do, whether it exists, why it is blocked, or how it works are knowledge_only even when they mention Owner Mode, Browser, Web Studio, Projects, tools, or execution.
Use effectful_objective only when the user is asking Kristin to perform, change, run, enable, connect, create, or repair something now.
A capabilityId is only a routing hint and grants no authority. Use only an id present in the cognitive context, otherwise leave it empty. Do not answer the user here.
'''),
      userPrompt: projection.wrapUserPrompt(message),
      commandId: 'chat_cognitive_classification',
      temperature: 0.0,
      maxOutputTokens: 320,
    );
    try {
      final result = await runtime.models.providerFor(model).generate(request);
      final json = _decodeObject(result.text);
      if (json == null) return null;
      final kind = switch (json['kind']?.toString().trim().toLowerCase()) {
        'knowledge_only' => CognitiveConversationKind.knowledgeOnly,
        'effectful_objective' => CognitiveConversationKind.effectfulObjective,
        _ => CognitiveConversationKind.unclear,
      };
      final raw = double.tryParse(json['confidence']?.toString() ?? '') ?? 0.0;
      final confidence = raw.clamp(0.0, 1.0).toDouble();
      var capabilityId = json['capabilityId']?.toString().trim() ?? '';
      if (capabilityId.isNotEmpty) {
        final self = await awareness.snapshot(
          selectedProject: selectedProject,
          selectedModel: model,
        );
        if (self.capability(capabilityId) == null) capabilityId = '';
      }
      return CognitiveConversationDecision(
        kind: confidence < 0.55 ? CognitiveConversationKind.unclear : kind,
        objective: _bounded(
          json['objective']?.toString().trim().isNotEmpty == true
              ? json['objective'].toString().trim()
              : message.trim(),
          800,
        ),
        capabilityId: capabilityId,
        confidence: confidence,
        rationale: _bounded(json['rationale']?.toString().trim() ?? '', 500),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<CognitiveClaim>> selfLookup(
    String query, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    int limit = 20,
  }) =>
      substrate.lookup(
        query,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
        limit: limit,
      );

  Future<CapabilityRequirementReport> whyBlocked(
    String capabilityId, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) =>
      awareness.requirementsFor(
        capabilityId,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      );

  Future<List<CognitiveSkillView>> findSkills(
    String query, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    int limit = 12,
  }) =>
      substrate.findSkills(
        query,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
        limit: limit,
      );

  Future<List<CognitiveKnowledgeView>> searchKnowledge(
    String query, {
    required ProjectRecord selectedProject,
    ModelIdentity? selectedModel,
    int limit = 12,
  }) =>
      substrate.searchKnowledge(
        query,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
        limit: limit,
      );

  Future<List<CognitiveMemoryView>> recallMemory(
    String query, {
    required ProjectRecord selectedProject,
    ModelIdentity? selectedModel,
    bool includeDiagnostic = false,
    int limit = 12,
  }) =>
      substrate.recallMemory(
        query,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
        includeDiagnostic: includeDiagnostic,
        limit: limit,
      );

  Future<String> explainSource(
    String claimId, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) =>
      substrate.explainSource(
        claimId,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      );
}

Map<String, dynamic>? _decodeObject(String text) {
  var value = text.trim();
  if (value.startsWith('```')) {
    value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
    value = value.replaceFirst(RegExp(r'\s*```$'), '');
  }
  final first = value.indexOf('{');
  final last = value.lastIndexOf('}');
  if (first < 0 || last <= first) return null;
  try {
    final decoded = jsonDecode(value.substring(first, last + 1));
    return decoded is Map ? mapValue(decoded) : null;
  } catch (_) {
    return null;
  }
}

String _bounded(String value, int limit) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= limit) return normalized;
  return '${normalized.substring(0, max(0, limit - 1)).trimRight()}…';
}
