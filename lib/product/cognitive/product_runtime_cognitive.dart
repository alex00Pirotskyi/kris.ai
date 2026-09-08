import 'dart:convert';
import 'dart:math';

import '../authority_product_knowledge.dart';
import '../browser/product_knowledge.dart';
import '../chat_product_knowledge.dart';
import '../crypto_utils.dart';
import '../domain.dart';
import '../knowledge_product_knowledge.dart';
import '../models_product_knowledge.dart';
import '../models_research.dart';
import '../owner_product_knowledge.dart';
import '../product_knowledge.dart';
import '../product_runtime.dart';
import '../product_runtime_self_awareness.dart';
import '../project_product_knowledge.dart';
import '../recovery/product_knowledge.dart';
import '../self_awareness/capability_self_model.dart';
import '../self_awareness/product_knowledge.dart';
import '../task_kernel/product_knowledge.dart';
import '../task_kernel/task_kernel.dart';
import 'cognitive_model.dart';
import 'cognitive_substrate.dart';
import 'memory_fact_index.dart';
import 'runtime_cognitive_enrichment.dart';

/// Read-only product composition point for Kristin's cognitive substrate.
///
/// This gateway exposes epistemic state only. It cannot mint grants, execute
/// tools, enter Owner Mode, mutate host/project state, or change Runner tools.
final class ProductRuntimeCognitiveGateway {
  ProductRuntimeCognitiveGateway._(this.runtime) {
    awareness = ProductSelfAwarenessRuntime.shared(runtime);
    productKnowledge = _buildProductKnowledgeRegistry();
    memoryFacts = CognitiveMemoryFactIndex(
      cacheDirectory: runtime.directories.cache,
      generate: (request) =>
          runtime.models.providerFor(request.identity).generate(request),
      sanitizeText: runtime.redactor.redact,
      onFailure: _recordMemoryFactFailure,
    );
    enrichment = CognitiveRuntimeEnrichment(
      productKnowledge: productKnowledge,
    );
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
    // Register the enriched request-scoped compiler, not the raw substrate.
    // This makes module-owned product knowledge and memory fact resolution
    // consistent for Chat, task understanding and task planning.
    CognitiveModelContextRegistry.register(
      runtime.models,
      _compileRegisteredContext,
    );
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
  late final KristinProductKnowledgeRegistry productKnowledge;
  late final CognitiveMemoryFactIndex memoryFacts;
  late final CognitiveRuntimeEnrichment enrichment;

  Future<CognitiveContextProjection> _compileRegisteredContext(
    CognitiveContextRequest request,
  ) =>
      context(
        objective: request.objective,
        pathway: request.pathway,
        selectedProject: request.selectedProject,
        projectId: request.projectId,
        selectedModel: request.selectedModel,
        sessionKey: request.sessionKey,
        taskFamily: request.taskFamily,
        capabilityHints: request.capabilityHints,
        workingMemory: request.workingMemory,
        maxCharacters: request.maxCharacters,
        forceRefresh: request.forceRefresh,
        includeProjectKnowledge: request.includeProjectKnowledge,
        includeMemory: request.includeMemory,
        includePublishedSkills: request.includePublishedSkills,
      );

  Future<KristinCognitiveSnapshot> stateInspect({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    bool forceRefresh = false,
    List<String> workingMemory = const <String>[],
  }) async {
    final base = await substrate.snapshot(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
      forceRefresh: forceRefresh,
      workingMemory: workingMemory,
    );
    var facts = const _MemoryFactContext.empty();
    if (selectedProject != null && selectedModel != null) {
      try {
        facts = await _factsForInspection(
          project: selectedProject,
          model: selectedModel,
        );
      } catch (error) {
        await _recordEnrichmentFailure(
          'state_inspection_memory',
          selectedProject.id,
          error,
        );
      }
    }
    return enrichment.enrichSnapshot(
      base,
      factsByEpisodeId: facts.factsByEpisodeId,
      episodesById: facts.episodesById,
    );
  }

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
  }) async {
    final request = CognitiveContextRequest(
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
      // Ordinary conversation gets identity/product/live capability state by
      // default, not the user's global published procedure catalog. Explicit
      // skill introspection and planning paths can still request that catalog.
      includePublishedSkills: includePublishedSkills ??
          pathway != CognitiveReasoningPathway.conversation,
    );
    var projection = await substrate.compile(request);
    projection = enrichment.replaceProductKnowledgeProjection(
      projection,
      objective: objective,
    );

    if (!_contextIncludesMemory(pathway, includeMemory) ||
        selectedModel == null) {
      return projection;
    }
    try {
      final project = selectedProject ??
          ((projectId?.trim().isNotEmpty ?? false)
              ? await runtime.getProject(projectId!.trim())
              : null);
      if (project == null) return projection;

      final facts = await _factsForObjective(
        project: project,
        model: selectedModel,
        objective: objective,
        pathway: pathway,
      );
      if (facts.factsByEpisodeId.isEmpty) return projection;

      final snapshot = enrichment.enrichSnapshot(
        await substrate.snapshot(
          selectedProject: project,
          selectedModel: selectedModel,
          workingMemory: workingMemory,
        ),
        factsByEpisodeId: facts.factsByEpisodeId,
        episodesById: facts.episodesById,
      );
      return enrichment.replaceMemoryWithResolvedFacts(
        projection,
        enrichedSnapshot: snapshot,
        factsByEpisodeId: facts.factsByEpisodeId,
        episodesById: facts.episodesById,
      );
    } catch (error) {
      await _recordEnrichmentFailure(
        'context_memory',
        selectedProject?.id ?? projectId ?? '',
        error,
      );
      return projection;
    }
  }

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
      if (capabilityId.isNotEmpty &&
          !projection.includedIds.contains('capability:$capabilityId')) {
        capabilityId = '';
      }
      final decision = CognitiveConversationDecision(
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
      try {
        await runtime.audit.append(
          'chat.cognitive_classified',
          Sha256.text(message),
          <String, dynamic>{
            'messageHash': Sha256.text(message),
            'objectiveHash': Sha256.text(decision.objective),
            'modelExactId': model.exactId,
            'kind': decision.kind.name,
            'confidence': decision.confidence,
            'capabilityId': decision.capabilityId,
            'snapshotFingerprint': projection.snapshotFingerprint,
            'contextFingerprint': projection.contextFingerprint,
          },
        );
      } catch (_) {
        // Classification audit must not change routing behavior.
      }
      return decision;
    } catch (_) {
      return null;
    }
  }

  Future<List<CognitiveClaim>> selfLookup(
    String query, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    int limit = 20,
  }) async {
    final base = await substrate.snapshot(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    var facts = const _MemoryFactContext.empty();
    if (selectedProject != null && selectedModel != null) {
      try {
        facts = await _factsForObjective(
          project: selectedProject,
          model: selectedModel,
          objective: query,
          pathway: CognitiveReasoningPathway.introspection,
        );
      } catch (error) {
        await _recordEnrichmentFailure(
          'self_lookup_memory',
          selectedProject.id,
          error,
        );
      }
    }
    final snapshot = enrichment.enrichSnapshot(
      base,
      factsByEpisodeId: facts.factsByEpisodeId,
      episodesById: facts.episodesById,
    );
    return enrichment.lookup(snapshot, query, limit: limit);
  }

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
  }) async {
    if (selectedModel != null) {
      try {
        await _factsForObjective(
          project: selectedProject,
          model: selectedModel,
          objective: query,
          pathway: includeDiagnostic
              ? CognitiveReasoningPathway.recovery
              : CognitiveReasoningPathway.introspection,
        );
      } catch (error) {
        await _recordEnrichmentFailure(
          'recall_memory_atomization',
          selectedProject.id,
          error,
        );
        // Fact indexing is derived enrichment; canonical recall must survive it.
      }
    }
    return substrate.recallMemory(
      query,
      selectedProject: selectedProject,
      selectedModel: selectedModel,
      includeDiagnostic: includeDiagnostic,
      limit: limit,
    );
  }

  Future<String> explainSource(
    String claimId, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) async {
    final snapshot = await stateInspect(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    return enrichment.explainClaim(snapshot, claimId);
  }

  Future<_MemoryFactContext> _factsForInspection({
    required ProjectRecord project,
    required ModelIdentity model,
  }) async {
    final episodes = await runtime.listMemoryEpisodes(project.id);
    final candidates = episodes
        .where((episode) =>
            episode.pinned ||
            (episode.admission == 'admitted' && !episode.diagnosticOnly))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final selected = candidates.take(8).toList(growable: false);
    if (selected.isEmpty) return const _MemoryFactContext.empty();
    final batch = await memoryFacts.ensure(
      episodes: selected,
      model: model,
      maxAtomizations: 4,
    );
    return _MemoryFactContext(
      factsByEpisodeId: batch.byEpisodeId,
      episodesById: <String, MemoryEpisode>{
        for (final episode in selected) episode.id: episode,
      },
    );
  }

  Future<_MemoryFactContext> _factsForObjective({
    required ProjectRecord project,
    required ModelIdentity model,
    required String objective,
    required CognitiveReasoningPathway pathway,
  }) async {
    final includeDiagnostic = pathway == CognitiveReasoningPathway.recovery;
    final wantedIds = <String>[];
    try {
      final retrieval = await runtime.searchKnowledge(
        project.id,
        objective,
        limit: 12,
        includeEpisodes: true,
        includeUnsuccessfulEpisodes: includeDiagnostic,
      );
      for (final hit in retrieval.hits) {
        if (hit.kind != KnowledgeKind.episode || hit.episodeId.isEmpty) {
          continue;
        }
        if (!wantedIds.contains(hit.episodeId)) wantedIds.add(hit.episodeId);
      }
    } catch (_) {
      // Fall through to bounded recent memory. Canonical memory remains source.
    }

    final all = await runtime.listMemoryEpisodes(project.id);
    final byId = <String, MemoryEpisode>{
      for (final episode in all) episode.id: episode
    };
    final selected = <MemoryEpisode>[];
    for (final id in wantedIds) {
      final episode = byId[id];
      if (episode == null) continue;
      if (!includeDiagnostic &&
          (episode.diagnosticOnly || episode.admission != 'admitted')) {
        continue;
      }
      selected.add(episode);
      if (selected.length >= 8) break;
    }
    if (selected.isEmpty &&
        pathway == CognitiveReasoningPathway.introspection) {
      final fallback = all
          .where((episode) =>
              episode.pinned ||
              (episode.admission == 'admitted' && !episode.diagnosticOnly))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      selected.addAll(fallback.take(6));
    }
    if (selected.isEmpty) return const _MemoryFactContext.empty();

    final batch = await memoryFacts.ensure(
      episodes: selected,
      model: model,
      maxAtomizations: includeDiagnostic ? 6 : 4,
    );
    return _MemoryFactContext(
      factsByEpisodeId: batch.byEpisodeId,
      episodesById: <String, MemoryEpisode>{
        for (final episode in selected) episode.id: episode,
      },
    );
  }

  Future<void> _recordMemoryFactFailure(
    String stage,
    String episodeId,
    Object error,
  ) =>
      _recordEnrichmentFailure(
        'memory_fact_$stage',
        episodeId,
        error,
      );

  Future<void> _recordEnrichmentFailure(
    String stage,
    String subjectId,
    Object error,
  ) async {
    try {
      final redacted = runtime.redactor.redact('$error');
      await runtime.audit.append(
        'cognitive.enrichment_failed',
        Sha256.text('$stage|$subjectId'),
        <String, dynamic>{
          'stage': stage,
          if (subjectId.isNotEmpty) 'subjectIdHash': Sha256.text(subjectId),
          'errorHash': Sha256.text(redacted),
        },
      );
    } catch (_) {
      // Derived observability cannot alter cognitive behavior.
    }
  }
}

final class _MemoryFactContext {
  const _MemoryFactContext({
    required this.factsByEpisodeId,
    required this.episodesById,
  });

  const _MemoryFactContext.empty()
      : factsByEpisodeId = const <String, List<CognitiveMemoryFactAtom>>{},
        episodesById = const <String, MemoryEpisode>{};

  final Map<String, List<CognitiveMemoryFactAtom>> factsByEpisodeId;
  final Map<String, MemoryEpisode> episodesById;
}

KristinProductKnowledgeRegistry _buildProductKnowledgeRegistry() {
  final registry = KristinProductKnowledgeRegistry();
  registry.register(chatProductKnowledgeProvider);
  registry.register(projectProductKnowledgeProvider);
  registry.register(runsProductKnowledgeProvider);
  registry.register(knowledgeProductKnowledgeProvider);
  registry.register(ownerProductKnowledgeProvider);
  registry.register(browserProductKnowledgeProvider);
  registry.register(modelsProductKnowledgeProvider);
  registry.register(taskKernelProductKnowledgeProvider);
  registry.register(capabilitiesProductKnowledgeProvider);
  registry.register(recoveryProductKnowledgeProvider);
  registry.register(authorityProductKnowledgeProvider);
  return registry;
}

bool _contextIncludesMemory(
  CognitiveReasoningPathway pathway,
  bool? requested,
) =>
    requested ??
    switch (pathway) {
      CognitiveReasoningPathway.taskPlanning ||
      CognitiveReasoningPathway.recovery ||
      CognitiveReasoningPathway.introspection =>
        true,
      CognitiveReasoningPathway.conversation ||
      CognitiveReasoningPathway.taskUnderstanding ||
      CognitiveReasoningPathway.execution =>
        false,
    };

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
