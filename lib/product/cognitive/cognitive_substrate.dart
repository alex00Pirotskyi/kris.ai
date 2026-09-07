import 'dart:math';

import '../crypto_utils.dart';
import '../domain.dart';
import '../knowledge_memory_v2.dart';
import '../models_research.dart';
import '../self_awareness/capability_self_model.dart';
import 'cognitive_model.dart';

/// Immutable snapshot builder plus bounded compiler. Storage remains owned by
/// the existing Knowledge/Memory/Skills services; this layer only interprets
/// those records for reasoning.
final class KristinCognitiveSubstrate {
  KristinCognitiveSubstrate({
    required this.loadSelfSnapshot,
    required this.loadProject,
    required this.loadKnowledge,
    required this.loadMemory,
    required this.loadPublishedSkills,
    required this.loadSkillCandidates,
    this.trustPolicy = const CognitiveClaimTrustPolicy(),
    this.maxKnowledgeItems = 80,
    this.maxMemoryItems = 80,
    this.maxSkills = 60,
  });

  final CognitiveSelfSnapshotLoader loadSelfSnapshot;
  final CognitiveProjectLoader loadProject;
  final CognitiveKnowledgeLoader loadKnowledge;
  final CognitiveMemoryLoader loadMemory;
  final CognitivePublishedSkillLoader loadPublishedSkills;
  final CognitiveSkillCandidateLoader loadSkillCandidates;
  final CognitiveClaimTrustPolicy trustPolicy;
  final int maxKnowledgeItems;
  final int maxMemoryItems;
  final int maxSkills;

  Future<ProjectRecord?> _resolveProject(CognitiveContextRequest request) async {
    final direct = request.selectedProject;
    if (direct != null) return direct;
    final id = request.projectId?.trim() ?? '';
    if (id.isEmpty) return null;
    return loadProject(id);
  }

  Future<KristinCognitiveSnapshot> snapshot({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    bool forceRefresh = false,
    List<String> workingMemory = const <String>[],
  }) async {
    final now = DateTime.now().toUtc();
    final self = await loadSelfSnapshot(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
      forceRefresh: forceRefresh,
    );
    final uncertainty = <CognitiveUncertainty>[];

    var knowledge = <KnowledgeEntry>[];
    var episodes = <MemoryEpisode>[];
    if (selectedProject != null) {
      try {
        knowledge = await loadKnowledge(selectedProject.id);
      } catch (error) {
        uncertainty.add(CognitiveUncertainty(
          id: 'knowledge_unavailable',
          domain: 'knowledge',
          status: CognitiveEpistemicStatus.unknown,
          detail: 'Project knowledge could not be observed: $error',
        ));
      }
      try {
        episodes = await loadMemory(selectedProject.id);
      } catch (error) {
        uncertainty.add(CognitiveUncertainty(
          id: 'memory_unavailable',
          domain: 'memory',
          status: CognitiveEpistemicStatus.unknown,
          detail: 'Project memory could not be observed: $error',
        ));
      }
    }

    var published = <PublishedSkillRecord>[];
    var candidates = <SkillCandidateRecord>[];
    try {
      published = await loadPublishedSkills();
      candidates = await loadSkillCandidates();
    } catch (error) {
      uncertainty.add(CognitiveUncertainty(
        id: 'skills_unavailable',
        domain: 'skills',
        status: CognitiveEpistemicStatus.unknown,
        detail: 'Published skill state could not be observed: $error',
      ));
    }

    final knowledgeViews = knowledge
        .take(maxKnowledgeItems)
        .map(_knowledgeView)
        .toList(growable: false);
    final memoryViews = episodes
        .take(maxMemoryItems)
        .map(_memoryView)
        .toList(growable: false);
    final candidateById = <String, SkillCandidateRecord>{
      for (final candidate in candidates) candidate.id: candidate,
    };
    final skills = published
        .take(maxSkills)
        .map((skill) => _skillView(skill, candidateById[skill.candidateId], self))
        .toList(growable: false);

    final claims = <CognitiveClaim>[
      ..._identityClaims(now, selectedProject, selectedModel),
      ..._applicationClaims(self),
      ..._capabilityClaims(self, now),
      ..._productKnowledgeClaims(now),
      ..._knowledgeClaims(knowledgeViews),
      ..._memoryClaims(memoryViews),
      ..._skillClaims(skills),
      ..._workingMemoryClaims(workingMemory, now),
    ];
    final resolution = trustPolicy.resolve(claims, now: now);
    for (final item in resolution.claims) {
      if (item.lifecycle == CognitiveLifecycleState.stale) {
        uncertainty.add(CognitiveUncertainty(
          id: 'stale_${item.id}',
          domain: item.scope.name,
          status: CognitiveEpistemicStatus.stale,
          detail: '${item.subject}.${item.predicate} is stale.',
        ));
      }
    }
    for (final conflict in resolution.conflicts) {
      uncertainty.add(CognitiveUncertainty(
        id: 'conflict_${Sha256.text(conflict.key).substring(0, 12)}',
        domain: 'claims',
        status: CognitiveEpistemicStatus.conflicting,
        detail: conflict.explanation,
      ));
    }
    final selected = self.application.selectedModel;
    if (selectedModel != null &&
        (selected == null || selected['discovered'] != true)) {
      uncertainty.add(const CognitiveUncertainty(
        id: 'selected_model_not_observed',
        domain: 'models',
        status: CognitiveEpistemicStatus.unknown,
        detail:
            'A reasoning model is selected for this session, but fresh provider discovery does not currently prove it is available.',
      ));
    }

    return KristinCognitiveSnapshot(
      capturedAt: now,
      identity: CognitiveIdentityView(reasoningModel: selectedModel),
      self: self,
      claims: resolution.claims,
      productKnowledge: kKristinProductKnowledge,
      skills: List<CognitiveSkillView>.unmodifiable(skills),
      knowledge: List<CognitiveKnowledgeView>.unmodifiable(knowledgeViews),
      memory: List<CognitiveMemoryView>.unmodifiable(memoryViews),
      conflicts: resolution.conflicts,
      uncertainty: List<CognitiveUncertainty>.unmodifiable(uncertainty),
    );
  }

  Future<CognitiveContextProjection> compile(CognitiveContextRequest request) async {
    final project = await _resolveProject(request);
    final cognitive = await snapshot(
      selectedProject: project,
      selectedModel: request.selectedModel,
      forceRefresh: request.forceRefresh,
      workingMemory: request.workingMemory,
    );
    return const CognitiveContextCompiler().compile(
      cognitive,
      request.copyWith(selectedProject: project),
    );
  }

  Future<List<CognitiveClaim>> lookup(
    String query, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    int limit = 20,
  }) async {
    final current = await snapshot(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    final terms = _terms(query);
    final ranked = current.claims
        .map((claim) => MapEntry(
              claim,
              _overlapScore(terms, _claimSearchText(claim)),
            ))
        .toList()
      ..sort((a, b) {
        final relevance = b.value.compareTo(a.value);
        if (relevance != 0) return relevance;
        return trustPolicy
            .score(b.key, current.capturedAt)
            .compareTo(trustPolicy.score(a.key, current.capturedAt));
      });
    return ranked
        .where((entry) => entry.value > 0 || terms.isEmpty)
        .take(limit.clamp(1, 100))
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  Future<List<CognitiveSkillView>> findSkills(
    String query, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    int limit = 12,
  }) async {
    final current = await snapshot(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    final terms = _terms(query);
    final values = current.skills.toList()
      ..sort((a, b) {
        final aScore = _overlapScore(
          terms,
          '${a.id} ${a.title} ${a.instructions} ${a.applicability.join(' ')}',
        );
        final bScore = _overlapScore(
          terms,
          '${b.id} ${b.title} ${b.instructions} ${b.applicability.join(' ')}',
        );
        if (aScore != bScore) return bScore.compareTo(aScore);
        return b.publishedAt.compareTo(a.publishedAt);
      });
    return values.take(limit.clamp(1, 60)).toList(growable: false);
  }

  Future<List<CognitiveKnowledgeView>> searchKnowledge(
    String query, {
    required ProjectRecord selectedProject,
    ModelIdentity? selectedModel,
    int limit = 12,
  }) async {
    final current = await snapshot(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    final terms = _terms(query);
    final values = current.knowledge.toList()
      ..sort((a, b) {
        int score(CognitiveKnowledgeView item) =>
            _overlapScore(
              terms,
              '${item.title} ${item.summary} ${item.tags.join(' ')}',
            ) +
            (item.pinned ? 8 : 0) +
            (item.freshness == ResearchFreshnessState.fresh ? 4 : 0);
        final comparison = score(b).compareTo(score(a));
        if (comparison != 0) return comparison;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return values.take(limit.clamp(1, 80)).toList(growable: false);
  }

  Future<List<CognitiveMemoryView>> recallMemory(
    String query, {
    required ProjectRecord selectedProject,
    ModelIdentity? selectedModel,
    bool includeDiagnostic = false,
    int limit = 12,
  }) async {
    final current = await snapshot(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    final terms = _terms(query);
    final values = current.memory
        .where((item) =>
            item.retrievalAllowed ||
            (includeDiagnostic &&
                item.kinds.contains(CognitiveMemoryKind.diagnostic)))
        .toList()
      ..sort((a, b) {
        int score(CognitiveMemoryView item) =>
            _overlapScore(
              terms,
              '${item.request} ${item.summary} ${item.lessons}',
            ) +
            (item.kinds.contains(CognitiveMemoryKind.pinned) ? 10 : 0) +
            (item.kinds.contains(CognitiveMemoryKind.semantic) ? 6 : 0);
        final comparison = score(b).compareTo(score(a));
        if (comparison != 0) return comparison;
        return b.createdAt.compareTo(a.createdAt);
      });
    return values.take(limit.clamp(1, 80)).toList(growable: false);
  }

  Future<String> explainSource(
    String claimId, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) async {
    final current = await snapshot(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    for (final claim in current.claims) {
      if (claim.id != claimId) continue;
      final sources = claim.evidence.map((item) => item.source).toSet().toList()
        ..sort();
      return 'Claim ${claim.id} is ${claim.epistemicStatus.name}/${claim.lifecycle.name} from ${claim.provenance.name}. '
          '${sources.isEmpty ? 'No direct evidence source is attached.' : 'Evidence: ${sources.join(', ')}.'}';
    }
    return 'No cognitive claim with id $claimId is present in the current bounded snapshot.';
  }

  CognitiveKnowledgeView _knowledgeView(KnowledgeEntry entry) {
    final research = entry.kind == KnowledgeKind.researchSource ||
        entry.kind == KnowledgeKind.researchSearch;
    final freshness = research
        ? const ResearchFreshnessPolicy().evaluate(entry.updatedAt)
        : ResearchFreshnessState.fresh;
    final evidence = <KnowledgeEvidence>[
      KnowledgeEvidence(
        kind: KnowledgeEvidenceKind.cached,
        source: 'KnowledgeService:${entry.id}',
        confidence: entry.contentHash.isEmpty
            ? ObservationConfidence.medium
            : ObservationConfidence.high,
        observedAt: entry.updatedAt,
        detail: entry.contentHash.isEmpty
            ? 'Knowledge record has no content hash.'
            : 'contentHash=${entry.contentHash}',
      ),
    ];
    return CognitiveKnowledgeView(
      id: entry.id,
      projectId: entry.projectId,
      title: entry.title,
      summary: _bounded(entry.content, 720),
      tags: Set<String>.unmodifiable(entry.tags),
      sourceUrl: entry.sourceUrl,
      contentHash: entry.contentHash,
      trust: entry.trust,
      kind: entry.kind.name,
      pinned: entry.pinned,
      updatedAt: entry.updatedAt,
      freshness: freshness,
      evidence: List<KnowledgeEvidence>.unmodifiable(evidence),
    );
  }

  CognitiveMemoryView _memoryView(MemoryEpisode episode) {
    final current = const MemoryAdmissionPolicy().evaluateEpisode(episode);
    final storedRetrievalAllowed =
        episode.admission == 'admitted' && !episode.diagnosticOnly;
    final kinds = <CognitiveMemoryKind>{CognitiveMemoryKind.episodic};
    if (episode.pinned) kinds.add(CognitiveMemoryKind.pinned);
    if (episode.diagnosticOnly || episode.admission == 'quarantined') {
      kinds.add(CognitiveMemoryKind.diagnostic);
    }
    if (current.retrievalAllowed &&
        episode.successful &&
        episode.lessons.trim().isNotEmpty) {
      kinds.add(CognitiveMemoryKind.semantic);
    }
    return CognitiveMemoryView(
      id: episode.id,
      projectId: episode.projectId,
      runId: episode.runId,
      request: _bounded(episode.request, 520),
      summary: _bounded(episode.summary, 640),
      lessons: _bounded(episode.lessons, 640),
      outcome: episode.outcome.name,
      kinds: Set<CognitiveMemoryKind>.unmodifiable(kinds),
      admission: episode.admission,
      admissionReason: episode.admissionReason,
      retrievalAllowed: storedRetrievalAllowed && current.retrievalAllowed,
      evidenceHashes: List<String>.unmodifiable(episode.evidenceHashes),
      createdAt: episode.createdAt,
      conflictsWithCurrentPolicy:
          storedRetrievalAllowed != current.retrievalAllowed ||
              episode.diagnosticOnly != current.diagnosticOnly,
    );
  }

  CognitiveSkillView _skillView(
    PublishedSkillRecord skill,
    SkillCandidateRecord? candidate,
    KristinSelfSnapshot self,
  ) {
    final requiredCapabilities = <String>{};
    final requiredAuthority = <String>{};
    final blockers = <String>[];
    final unresolvedTools = <String>[];
    for (final tool in skill.recommendedTools) {
      final matching = self.capabilities.where(
        (item) => item.descriptor.runnerToolName == tool,
      );
      if (matching.isEmpty) {
        unresolvedTools.add(tool);
        continue;
      }
      for (final capability in matching) {
        requiredCapabilities.add(capability.descriptor.id);
        requiredAuthority.addAll(capability.availability.requiredAuthority);
        if (!capability.operationallyUsableAt(self.application.capturedAt)) {
          final reasons = <String>[
            ...capability.availability.reasons,
            ...?capability.health?.reasons,
          ];
          blockers.add(
            '${capability.descriptor.id}: ${reasons.isEmpty ? capability.availability.state.name : reasons.first}',
          );
        }
      }
    }
    final usability = blockers.isNotEmpty
        ? CognitiveSkillUsability.blocked
        : unresolvedTools.isNotEmpty || skill.recommendedTools.isEmpty
            ? CognitiveSkillUsability.unknown
            : CognitiveSkillUsability.usable;
    return CognitiveSkillView(
      id: skill.id,
      title: skill.title,
      version: skill.version,
      instructions: _bounded(skill.instructions, 1200),
      origin: candidate == null
          ? 'published-skill:${skill.candidateId}'
          : 'memory-episode:${candidate.sourceEpisodeId}',
      sourceEpisodeId: candidate?.sourceEpisodeId ?? '',
      evidenceHashes:
          List<String>.unmodifiable(candidate?.evidenceHashes ?? const <String>[]),
      recommendedTools: Set<String>.unmodifiable(skill.recommendedTools),
      requiredCapabilityIds: Set<String>.unmodifiable(requiredCapabilities),
      requiredAuthority: Set<String>.unmodifiable(requiredAuthority),
      prerequisites: <String>[
        for (final capability in requiredCapabilities) 'capability:$capability',
        for (final tool in unresolvedTools) 'runtime dependency for tool:$tool',
      ],
      applicability: List<String>.unmodifiable(
        candidate?.triggers.toList() ?? const <String>[],
      ),
      limitations: <String>[
        'Publication proves approval/replay at publication time; it does not prove current runtime usability.',
        if (unresolvedTools.isNotEmpty)
          'Current capability descriptors do not map these recommended tools: ${unresolvedTools.join(', ')}.',
      ],
      risk: requiredAuthority.isEmpty
          ? 'derived:unknown_or_read_only'
          : 'derived:governed',
      publicationState: 'published',
      usability: usability,
      blockers: List<String>.unmodifiable(blockers),
      publishedAt: skill.publishedAt,
      lastObservedAt: self.application.capturedAt,
      lastVerifiedAt: null,
    );
  }

  Iterable<CognitiveClaim> _identityClaims(
    DateTime now,
    ProjectRecord? project,
    ModelIdentity? model,
  ) sync* {
    yield CognitiveClaim(
      subject: 'kristin',
      predicate: 'identity',
      value: 'persistent_application_ai',
      scope: CognitiveClaimScope.globalKristin,
      provenance: CognitiveClaimProvenance.registeredProductProvider,
      epistemicStatus: CognitiveEpistemicStatus.verified,
      confidence: ObservationConfidence.certain,
      createdAt: now,
      observedAt: now,
      evidence: <KnowledgeEvidence>[
        KnowledgeEvidence(
          kind: KnowledgeEvidenceKind.configured,
          source: 'cognitive.identity_provider',
          confidence: ObservationConfidence.certain,
          observedAt: now,
        ),
      ],
    );
    if (model != null) {
      yield CognitiveClaim(
        subject: 'kristin',
        predicate: 'reasoning_provider',
        value: model.exactId,
        scope: CognitiveClaimScope.session,
        provenance: CognitiveClaimProvenance.configuration,
        epistemicStatus: CognitiveEpistemicStatus.configured,
        confidence: ObservationConfidence.high,
        createdAt: now,
        observedAt: now,
        evidence: <KnowledgeEvidence>[
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.configured,
            source: 'session.selected_model',
            confidence: ObservationConfidence.high,
            observedAt: now,
          ),
        ],
      );
    }
    if (project != null) {
      yield CognitiveClaim(
        subject: 'kristin.session',
        predicate: 'selected_project',
        value: <String, Object?>{'id': project.id, 'name': project.name},
        scope: CognitiveClaimScope.session,
        provenance: CognitiveClaimProvenance.configuration,
        epistemicStatus: CognitiveEpistemicStatus.configured,
        confidence: ObservationConfidence.high,
        createdAt: now,
        observedAt: now,
      );
    }
  }

  Iterable<CognitiveClaim> _applicationClaims(KristinSelfSnapshot self) sync* {
    final app = self.application;
    for (final entry in <String, Object?>{
      'platform': app.platform,
      'build': app.build,
      'selectedProject': app.selectedProject,
      'selectedModel': app.selectedModel,
      'providers': app.providers,
      'runState': app.runState,
      'ownerMode': app.ownerMode,
      'browser': app.browser,
      'processes': app.processes,
      'research': app.research,
      'authority': app.authority,
    }.entries) {
      final evidence = app.knowledgeEvidence[entry.key];
      yield CognitiveClaim(
        subject: 'application',
        predicate: entry.key,
        value: entry.value,
        scope: CognitiveClaimScope.application,
        provenance: CognitiveClaimProvenance.runtimeObservation,
        epistemicStatus: evidence == null
            ? CognitiveEpistemicStatus.unknown
            : evidence.isFreshAt(app.capturedAt)
                ? CognitiveEpistemicStatus.observed
                : CognitiveEpistemicStatus.stale,
        confidence: evidence?.confidence ?? ObservationConfidence.unknown,
        createdAt: app.capturedAt,
        observedAt: evidence?.observedAt ?? app.capturedAt,
        expiresAt: evidence?.expiresAt,
        lifecycle: evidence == null
            ? CognitiveLifecycleState.valid
            : evidence.isFreshAt(app.capturedAt)
                ? CognitiveLifecycleState.valid
                : CognitiveLifecycleState.stale,
        evidence: evidence == null
            ? const <KnowledgeEvidence>[]
            : <KnowledgeEvidence>[evidence],
      );
    }
  }

  Iterable<CognitiveClaim> _capabilityClaims(
    KristinSelfSnapshot self,
    DateTime now,
  ) sync* {
    for (final capability in self.capabilities) {
      final id = capability.descriptor.id;
      yield CognitiveClaim(
        subject: 'capability:$id',
        predicate: 'known',
        value: <String, Object?>{
          'name': capability.descriptor.name,
          'description': capability.descriptor.description,
          'risk': capability.descriptor.riskClass.name,
          'runnerToolName': capability.descriptor.runnerToolName,
        },
        scope: CognitiveClaimScope.capability,
        provenance: CognitiveClaimProvenance.registeredProductProvider,
        epistemicStatus: CognitiveEpistemicStatus.verified,
        confidence: ObservationConfidence.certain,
        createdAt: now,
        observedAt: self.application.capturedAt,
      );
      final availabilityFresh = capability.availability.freshAt(
        self.application.capturedAt,
        capability.descriptor.freshnessBudget,
      );
      yield CognitiveClaim(
        subject: 'capability:$id',
        predicate: 'availability',
        value: capability.availability.state.name,
        scope: CognitiveClaimScope.capability,
        provenance: CognitiveClaimProvenance.runtimeObservation,
        epistemicStatus: availabilityFresh
            ? CognitiveEpistemicStatus.observed
            : CognitiveEpistemicStatus.stale,
        confidence: capability.availability.strongestConfidence,
        createdAt: now,
        observedAt: capability.availability.observedAt,
        expiresAt: _evidenceExpiry(capability.availability.evidence),
        lifecycle: availabilityFresh
            ? CognitiveLifecycleState.valid
            : CognitiveLifecycleState.stale,
        evidence: capability.availability.evidence,
      );
      yield CognitiveClaim(
        subject: 'capability:$id',
        predicate: 'authority',
        value: <String, Object?>{
          'observation': capability.availability.authorityObservation.name,
          'required': capability.availability.requiredAuthority.toList()..sort(),
          'current': capability.availability.currentAuthority.toList()..sort(),
        },
        scope: CognitiveClaimScope.capability,
        provenance: CognitiveClaimProvenance.runtimeObservation,
        epistemicStatus: capability.availability.authorityObservation ==
                AuthorityObservationState.notEvaluated
            ? CognitiveEpistemicStatus.unknown
            : CognitiveEpistemicStatus.observed,
        confidence: capability.availability.strongestConfidence,
        createdAt: now,
        observedAt: capability.availability.observedAt,
        expiresAt: _evidenceExpiry(capability.availability.evidence),
        evidence: capability.availability.evidence,
      );
      final health = capability.health;
      if (health != null) {
        final healthFresh = health.freshAt(
          self.application.capturedAt,
          capability.descriptor.healthFreshnessBudget,
        );
        yield CognitiveClaim(
          subject: 'capability:$id',
          predicate: 'health',
          value: health.state.name,
          scope: CognitiveClaimScope.capability,
          provenance: CognitiveClaimProvenance.runtimeObservation,
          epistemicStatus: healthFresh
              ? CognitiveEpistemicStatus.observed
              : CognitiveEpistemicStatus.stale,
          confidence: _strongestConfidence(health.evidence),
          createdAt: now,
          observedAt: health.observedAt,
          expiresAt: health.expiresAt,
          lifecycle: healthFresh
              ? CognitiveLifecycleState.valid
              : CognitiveLifecycleState.stale,
          evidence: health.evidence,
        );
      }
    }
  }

  Iterable<CognitiveClaim> _productKnowledgeClaims(DateTime now) sync* {
    for (final concept in kKristinProductKnowledge) {
      yield CognitiveClaim(
        subject: 'product:${concept.id}',
        predicate: 'description',
        value: concept.summary,
        scope: CognitiveClaimScope.application,
        provenance: CognitiveClaimProvenance.registeredProductProvider,
        epistemicStatus: CognitiveEpistemicStatus.verified,
        confidence: ObservationConfidence.certain,
        createdAt: now,
        observedAt: now,
        evidence: <KnowledgeEvidence>[
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.configured,
            source: 'cognitive.product_knowledge:${concept.id}',
            confidence: ObservationConfidence.certain,
            observedAt: now,
          ),
        ],
      );
    }
  }

  Iterable<CognitiveClaim> _knowledgeClaims(
    Iterable<CognitiveKnowledgeView> knowledge,
  ) sync* {
    for (final item in knowledge) {
      final isResearch = item.kind == KnowledgeKind.researchSource.name ||
          item.kind == KnowledgeKind.researchSearch.name;
      yield CognitiveClaim(
        subject: 'knowledge:${item.id}',
        predicate: 'content',
        value: item.summary,
        scope: CognitiveClaimScope.project,
        provenance: isResearch
            ? CognitiveClaimProvenance.research
            : CognitiveClaimProvenance.projectKnowledge,
        epistemicStatus: item.freshness == ResearchFreshnessState.stale
            ? CognitiveEpistemicStatus.stale
            : CognitiveEpistemicStatus.verified,
        confidence: item.contentHash.isEmpty
            ? ObservationConfidence.medium
            : ObservationConfidence.high,
        createdAt: item.updatedAt,
        observedAt: item.updatedAt,
        lifecycle: item.freshness == ResearchFreshnessState.stale
            ? CognitiveLifecycleState.stale
            : CognitiveLifecycleState.valid,
        evidence: item.evidence,
        tags: <String>{'knowledge', item.kind, ...item.tags},
      );
    }
  }

  Iterable<CognitiveClaim> _memoryClaims(
    Iterable<CognitiveMemoryView> memories,
  ) sync* {
    for (final item in memories) {
      final semantic = item.kinds.contains(CognitiveMemoryKind.semantic);
      yield CognitiveClaim(
        subject: 'memory:${item.id}',
        predicate: 'experience',
        value: <String, Object?>{
          'request': item.request,
          'summary': item.summary,
          'lessons': item.lessons,
          'outcome': item.outcome,
        },
        scope: CognitiveClaimScope.project,
        provenance: CognitiveClaimProvenance.memoryEpisode,
        epistemicStatus: semantic
            ? CognitiveEpistemicStatus.verified
            : CognitiveEpistemicStatus.remembered,
        confidence: item.evidenceHashes.isEmpty
            ? ObservationConfidence.low
            : ObservationConfidence.high,
        createdAt: item.createdAt,
        observedAt: item.createdAt,
        lifecycle: item.retrievalAllowed
            ? CognitiveLifecycleState.valid
            : CognitiveLifecycleState.superseded,
        evidence: <KnowledgeEvidence>[
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.cached,
            source: 'MemoryEpisode:${item.id}',
            confidence: item.evidenceHashes.isEmpty
                ? ObservationConfidence.low
                : ObservationConfidence.high,
            observedAt: item.createdAt,
            detail: item.evidenceHashes.isEmpty
                ? 'No evidence hashes are attached.'
                : '${item.evidenceHashes.length} evidence hash(es) are attached.',
          ),
        ],
        tags: item.kinds.map((kind) => 'memory:${kind.name}').toSet(),
      );
    }
  }

  Iterable<CognitiveClaim> _skillClaims(
    Iterable<CognitiveSkillView> skills,
  ) sync* {
    for (final skill in skills) {
      yield CognitiveClaim(
        subject: 'skill:${skill.id}',
        predicate: 'published',
        value: <String, Object?>{
          'title': skill.title,
          'version': skill.version,
          'usability': skill.usability.name,
          'requiredCapabilities': skill.requiredCapabilityIds.toList()..sort(),
          'requiredAuthority': skill.requiredAuthority.toList()..sort(),
        },
        scope: CognitiveClaimScope.skill,
        provenance: CognitiveClaimProvenance.publishedSkill,
        epistemicStatus: CognitiveEpistemicStatus.verified,
        confidence: ObservationConfidence.high,
        createdAt: skill.publishedAt,
        observedAt: skill.lastObservedAt,
        evidence: <KnowledgeEvidence>[
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.cached,
            source: 'SkillPublicationService:${skill.id}',
            confidence: ObservationConfidence.high,
            observedAt: skill.lastObservedAt,
            detail: 'publicationState=${skill.publicationState}',
          ),
        ],
      );
    }
  }

  Iterable<CognitiveClaim> _workingMemoryClaims(
    List<String> values,
    DateTime now,
  ) sync* {
    for (var index = 0; index < min(values.length, 12); index++) {
      final value = values[index].trim();
      if (value.isEmpty) continue;
      yield CognitiveClaim(
        subject: 'working_memory',
        predicate: 'item_$index',
        value: _bounded(value, 900),
        scope: CognitiveClaimScope.session,
        provenance: CognitiveClaimProvenance.userStatement,
        epistemicStatus: CognitiveEpistemicStatus.userAsserted,
        confidence: ObservationConfidence.medium,
        createdAt: now,
        observedAt: now,
        tags: const <String>{'memory:working'},
      );
    }
  }
}

final class CognitiveContextCompiler {
  const CognitiveContextCompiler();

  CognitiveContextProjection compile(
    KristinCognitiveSnapshot snapshot,
    CognitiveContextRequest request,
  ) {
    final budget = request.maxCharacters.clamp(2500, 12000);
    final writer = _ContextBudgetWriter(budget);
    final included = <String>{};
    final omitted = <String, int>{};
    final objectiveTerms = _terms(request.objective);

    writer.addRequired('IDENTITY\n${_identityLine(snapshot)}');
    writer.addRequired('APPLICATION STATE\n${_applicationLines(snapshot)}');

    final productLines = snapshot.productKnowledge
        .map((item) => '- ${item.id}: ${item.summary}')
        .join('\n');
    writer.addRequired('PRODUCT KNOWLEDGE\n$productLines');
    included.addAll(snapshot.productKnowledge.map((item) => 'product:${item.id}'));

    final capabilities = snapshot.self.capabilities.toList()
      ..sort((a, b) {
        final aScore = _capabilityRelevance(a, request, objectiveTerms);
        final bScore = _capabilityRelevance(b, request, objectiveTerms);
        if (aScore != bScore) return bScore.compareTo(aScore);
        return a.descriptor.id.compareTo(b.descriptor.id);
      });
    final capabilityLines = <String>[];
    for (final item in capabilities) {
      final reasons = <String>[
        ...item.availability.reasons,
        ...?item.health?.reasons,
      ];
      capabilityLines.add(
        '- ${item.descriptor.id} | ${item.descriptor.name} | availability=${item.availability.state.name} | health=${item.health?.state.name ?? 'unknown'} | authority=${item.availability.authorityObservation.name}${reasons.isEmpty ? '' : ' | ${_bounded(reasons.first, 180)}'}',
      );
    }
    writer.add(
      'CAPABILITIES (knowledge != usability/authority/tool)\n${capabilityLines.join('\n')}',
      onOmitted: () => omitted['capabilities'] = capabilities.length,
    );
    included.addAll(
      capabilities.take(24).map((item) => 'capability:${item.descriptor.id}'),
    );

    final skills = snapshot.skills.toList()
      ..sort((a, b) {
        final aScore = _skillRelevance(a, request, objectiveTerms);
        final bScore = _skillRelevance(b, request, objectiveTerms);
        if (aScore != bScore) return bScore.compareTo(aScore);
        return b.publishedAt.compareTo(a.publishedAt);
      });
    final skillDetails = skills.take(5).map((item) {
      included.add('skill:${item.id}');
      return '- ${item.id} v${item.version}: ${item.title} | usability=${item.usability.name} | capabilities=${_compactSet(item.requiredCapabilityIds)} | authority=${_compactSet(item.requiredAuthority)}${item.blockers.isEmpty ? '' : ' | blocker=${_bounded(item.blockers.first, 180)}'}\n  procedure: ${_bounded(item.instructions, 460)}';
    }).join('\n');
    if (skillDetails.isNotEmpty) {
      writer.add(
        'RELEVANT PUBLISHED SKILLS\n$skillDetails',
        onOmitted: () => omitted['skills'] = max(0, skills.length - 5),
      );
    }

    final knowledge = snapshot.knowledge.toList()
      ..sort((a, b) {
        final aScore = _knowledgeRelevance(a, objectiveTerms);
        final bScore = _knowledgeRelevance(b, objectiveTerms);
        if (aScore != bScore) return bScore.compareTo(aScore);
        return b.updatedAt.compareTo(a.updatedAt);
      });
    final knowledgeDetails = knowledge.take(5).map((item) {
      included.add('knowledge:${item.id}');
      return '- ${item.id}: ${item.title} | kind=${item.kind} | trust=${item.trust} | freshness=${item.freshness.name}${item.contentHash.isEmpty ? '' : ' | hash=${item.contentHash}'}\n  ${_bounded(item.summary, 420)}';
    }).join('\n');
    if (knowledgeDetails.isNotEmpty) {
      writer.add(
        'RELEVANT PROJECT KNOWLEDGE\n$knowledgeDetails',
        onOmitted: () => omitted['knowledge'] = max(0, knowledge.length - 5),
      );
    }

    final allowDiagnostic = request.pathway == CognitiveReasoningPathway.recovery;
    final memories = snapshot.memory
        .where((item) =>
            item.retrievalAllowed ||
            (allowDiagnostic &&
                item.kinds.contains(CognitiveMemoryKind.diagnostic)))
        .toList()
      ..sort((a, b) {
        final aScore = _memoryRelevance(a, objectiveTerms, allowDiagnostic);
        final bScore = _memoryRelevance(b, objectiveTerms, allowDiagnostic);
        if (aScore != bScore) return bScore.compareTo(aScore);
        return b.createdAt.compareTo(a.createdAt);
      });
    final memoryDetails = memories.take(4).map((item) {
      included.add('memory:${item.id}');
      return '- ${item.id}: kinds=${item.kinds.map((kind) => kind.name).join('/')} | admission=${item.admission} | outcome=${item.outcome}\n  ${_bounded(item.lessons.isNotEmpty ? item.lessons : item.summary, 400)}';
    }).join('\n');
    if (memoryDetails.isNotEmpty) {
      writer.add(
        'RELEVANT MEMORY (history, never current runtime truth)\n$memoryDetails',
        onOmitted: () => omitted['memory'] = max(0, memories.length - 4),
      );
    }

    if (request.workingMemory.isNotEmpty) {
      final working = request.workingMemory
          .take(8)
          .map((item) => '- ${_bounded(item, 500)}')
          .join('\n');
      writer.add('WORKING MEMORY (user/session assertions)\n$working');
    }

    final issues = <String>[
      for (final conflict in snapshot.conflicts.take(5))
        '- conflicting: ${conflict.key}; preferred=${conflict.preferredClaimId}; retained=${conflict.conflictingClaimIds.join(',')}',
      for (final item in snapshot.uncertainty.take(8))
        '- ${item.status.name}: ${item.domain}: ${item.detail}',
    ];
    if (issues.isNotEmpty) {
      writer.addRequired('UNCERTAINTY / CONFLICTS\n${issues.join('\n')}');
    }

    writer.addRequired(
      'EPISTEMIC RULE\nFresh runtime observation > current configuration > authoritative product/project knowledge > verified semantic memory > admitted episodic memory > user assertion > model inference. If stronger evidence is absent, say what is unknown instead of guessing.',
    );

    return CognitiveContextProjection(
      pathway: request.pathway,
      rendered: writer.value,
      includedIds: Set<String>.unmodifiable(included),
      omittedCounts: Map<String, int>.unmodifiable(omitted),
      maxCharacters: budget,
    );
  }

  String _identityLine(KristinCognitiveSnapshot snapshot) {
    final model = snapshot.identity.reasoningModel;
    return model == null
        ? 'Kristin is the persistent application-level AI identity. No reasoning model is selected in this context.'
        : 'Kristin is the persistent application-level AI identity. Current reasoning provider: ${model.exactId}. The provider is not Kristin.';
  }

  String _applicationLines(KristinCognitiveSnapshot snapshot) {
    final app = snapshot.self.application;
    final selectedProject = app.selectedProject;
    final selectedModel = app.selectedModel;
    final owner = app.ownerMode;
    final browser = app.browser;
    final modelsEvidence = app.knowledgeEvidence['models'];
    final browserEvidence = app.knowledgeEvidence['browser'];
    final ownerEvidence = app.knowledgeEvidence['ownerMode'];
    return <String>[
      '- platform=${app.platform}; build=${app.build}',
      '- selectedProject=${selectedProject == null ? 'none' : canonicalJson(selectedProject)}',
      '- selectedModel=${selectedModel == null ? 'none' : canonicalJson(selectedModel)}; modelObservation=${_evidenceState(modelsEvidence, snapshot.capturedAt)}',
      '- browser=${canonicalJson(browser)}; observation=${_evidenceState(browserEvidence, snapshot.capturedAt)}',
      '- ownerMode=${canonicalJson(owner)}; observation=${_evidenceState(ownerEvidence, snapshot.capturedAt)}',
      '- runState=${canonicalJson(app.runState)}',
      '- authority=${canonicalJson(app.authority)}',
    ].join('\n');
  }

  int _capabilityRelevance(
    KnownCapability capability,
    CognitiveContextRequest request,
    Set<String> terms,
  ) {
    var score = 10;
    if (request.capabilityHints.contains(capability.descriptor.id)) score += 120;
    score += _overlapScore(
          terms,
          '${capability.descriptor.id} ${capability.descriptor.name} ${capability.descriptor.description}',
        ) *
        8;
    if (!capability.operationallyUsableAt(DateTime.now().toUtc())) score += 4;
    if (request.pathway == CognitiveReasoningPathway.execution &&
        capability.descriptor.runnerToolName != null) {
      score += 12;
    }
    return score;
  }

  int _skillRelevance(
    CognitiveSkillView skill,
    CognitiveContextRequest request,
    Set<String> terms,
  ) {
    var score = _overlapScore(
          terms,
          '${skill.id} ${skill.title} ${skill.instructions} ${skill.applicability.join(' ')}',
        ) *
        8;
    score += skill.requiredCapabilityIds.intersection(request.capabilityHints).length * 50;
    if (skill.usability == CognitiveSkillUsability.usable) score += 6;
    return score;
  }

  int _knowledgeRelevance(CognitiveKnowledgeView item, Set<String> terms) {
    var score = _overlapScore(
          terms,
          '${item.id} ${item.title} ${item.summary} ${item.tags.join(' ')}',
        ) *
        8;
    if (item.pinned) score += 18;
    if (item.freshness == ResearchFreshnessState.fresh) score += 6;
    if (item.trust != 'untrusted_external_data') score += 4;
    return score;
  }

  int _memoryRelevance(
    CognitiveMemoryView item,
    Set<String> terms,
    bool allowDiagnostic,
  ) {
    var score = _overlapScore(
          terms,
          '${item.request} ${item.summary} ${item.lessons}',
        ) *
        7;
    if (item.kinds.contains(CognitiveMemoryKind.pinned)) score += 18;
    if (item.kinds.contains(CognitiveMemoryKind.semantic)) score += 10;
    if (allowDiagnostic && item.kinds.contains(CognitiveMemoryKind.diagnostic)) {
      score += 12;
    }
    return score;
  }
}

final class _ContextBudgetWriter {
  _ContextBudgetWriter(this.maxCharacters);

  final int maxCharacters;
  final StringBuffer _buffer = StringBuffer();

  int get length => _buffer.length;
  int get remaining => maxCharacters - length;
  String get value => _buffer.toString().trim();

  void add(String section, {void Function()? onOmitted}) {
    final normalized = section.trim();
    if (normalized.isEmpty) return;
    final separator = _buffer.isEmpty ? 0 : 2;
    if (normalized.length + separator > remaining) {
      onOmitted?.call();
      return;
    }
    if (_buffer.isNotEmpty) _buffer.write('\n\n');
    _buffer.write(normalized);
  }

  void addRequired(String section) {
    final normalized = section.trim();
    if (normalized.isEmpty || remaining <= 0) return;
    if (_buffer.isNotEmpty && remaining >= 2) _buffer.write('\n\n');
    if (normalized.length <= remaining) {
      _buffer.write(normalized);
      return;
    }
    _buffer.write(_bounded(normalized, max(0, remaining)));
  }
}

/// Short-lived execution projection cache keyed by the exact governed request.
///
/// RunCoordinator already asks SkillRegistry for advisory context using that
/// exact request on every model turn. Caching the execution projection here
/// lets newly planned runs receive the same cognitive substrate without
/// widening Runner tools or coupling the executor back to ProductRuntime.
final class CognitiveExecutionContextCache {
  CognitiveExecutionContextCache._();

  static final Map<String, String> _contexts = <String, String>{};
  static const int _maxEntries = 32;

  static void put(String request, CognitiveContextProjection projection) {
    final normalized = request.trim();
    if (normalized.isEmpty) return;
    final key = Sha256.text(normalized);
    if (!_contexts.containsKey(key) && _contexts.length >= _maxEntries) {
      _contexts.remove(_contexts.keys.first);
    }
    _contexts[key] = _bounded(projection.rendered, 4800);
  }

  static String? forRequest(String request) {
    final normalized = request.trim();
    if (normalized.isEmpty) return null;
    return _contexts[Sha256.text(normalized)];
  }
}

/// Model-context registry is keyed by the existing ModelRegistry instance.
/// It transports read-only epistemic context to model entry points without
/// becoming a permission or execution registry. Selection state is only a
/// presentation overlay; every compilation re-observes the authoritative
/// self snapshot before rendering it.
final class CognitiveModelContextRegistry {
  CognitiveModelContextRegistry._();

  static final Expando<Future<CognitiveContextProjection> Function(
    CognitiveContextRequest request,
  )> _compilers = Expando('kristin-cognitive-compiler');
  static final Expando<_CognitiveSelection> _selection =
      Expando('_kristin-cognitive-selection');

  static void register(
    Object key,
    Future<CognitiveContextProjection> Function(CognitiveContextRequest request)
        compiler,
  ) {
    _compilers[key] = compiler;
  }

  static void bindSelection(
    Object key, {
    ProjectRecord? project,
    ModelIdentity? model,
    String sessionKey = 'default',
  }) {
    _selection[key] = _CognitiveSelection(
      project: project,
      model: model,
      sessionKey: sessionKey,
    );
  }

  static Future<CognitiveContextProjection?> compile(
    Object key,
    CognitiveContextRequest request,
  ) async {
    final compiler = _compilers[key];
    if (compiler == null) return null;
    final selection = _selection[key];
    final effective = request.copyWith(
      selectedProject: request.selectedProject ?? selection?.project,
      selectedModel: request.selectedModel ?? selection?.model,
      sessionKey: request.sessionKey == 'default'
          ? selection?.sessionKey ?? request.sessionKey
          : request.sessionKey,
    );
    return compiler(effective);
  }

  static Future<ModelGenerationRequest> enrichModelRequest(
    Object key,
    ModelGenerationRequest request, {
    required CognitiveReasoningPathway pathway,
    String? projectId,
    Set<String> capabilityHints = const <String>{},
    String taskFamily = '',
    int maxCharacters = 6200,
  }) async {
    final cognitive = await compile(
      key,
      CognitiveContextRequest(
        objective: request.userPrompt,
        pathway: pathway,
        projectId: projectId,
        selectedModel: request.identity,
        taskFamily: taskFamily,
        capabilityHints: capabilityHints,
        maxCharacters: maxCharacters,
      ),
    );
    if (cognitive == null) return request;
    return ModelGenerationRequest(
      identity: request.identity,
      systemPrompt: cognitive.wrapSystemPrompt(request.systemPrompt),
      userPrompt: request.userPrompt,
      commandId: request.commandId,
      temperature: request.temperature,
      maxOutputTokens: request.maxOutputTokens,
      loadTimeout: request.loadTimeout,
      loadRetries: request.loadRetries,
      loadRetryDelay: request.loadRetryDelay,
      firstTokenTimeout: request.firstTokenTimeout,
      totalTimeout: request.totalTimeout,
      cancellation: request.cancellation,
      isCancelled: request.isCancelled,
      onProgress: request.onProgress,
      onTextDelta: request.onTextDelta,
    );
  }
}

final class _CognitiveSelection {
  const _CognitiveSelection({
    required this.project,
    required this.model,
    required this.sessionKey,
  });

  final ProjectRecord? project;
  final ModelIdentity? model;
  final String sessionKey;
}

DateTime? _evidenceExpiry(Iterable<KnowledgeEvidence> evidence) {
  DateTime? earliest;
  for (final item in evidence) {
    final expiry = item.expiresAt;
    if (expiry == null) continue;
    if (earliest == null || expiry.isBefore(earliest)) earliest = expiry;
  }
  return earliest;
}

ObservationConfidence _strongestConfidence(Iterable<KnowledgeEvidence> evidence) {
  var best = ObservationConfidence.unknown;
  int rank(ObservationConfidence value) => switch (value) {
        ObservationConfidence.certain => 5,
        ObservationConfidence.high => 4,
        ObservationConfidence.medium => 3,
        ObservationConfidence.low => 2,
        ObservationConfidence.unknown => 1,
      };
  for (final item in evidence) {
    if (rank(item.confidence) > rank(best)) best = item.confidence;
  }
  return best;
}

Set<String> _terms(String value) {
  final normalized =
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._:-]+'), ' ');
  return normalized
      .split(' ')
      .map((item) => item.trim())
      .where((item) => item.length >= 2)
      .take(96)
      .toSet();
}

int _overlapScore(Set<String> terms, String value) {
  if (terms.isEmpty) return 0;
  final candidate = _terms(value);
  return terms.intersection(candidate).length;
}

String _claimSearchText(CognitiveClaim claim) =>
    '${claim.subject} ${claim.predicate} ${canonicalJson(claim.value)} ${claim.tags.join(' ')}';

String _bounded(String value, int maxCharacters) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (maxCharacters <= 0) return '';
  if (normalized.length <= maxCharacters) return normalized;
  if (maxCharacters <= 1) return '…'.substring(0, maxCharacters);
  return '${normalized.substring(0, maxCharacters - 1).trimRight()}…';
}

String _compactSet(Iterable<String> values) {
  final sorted = values.where((item) => item.trim().isNotEmpty).toSet().toList()
    ..sort();
  return sorted.isEmpty ? 'none/unknown' : sorted.join(',');
}

String _evidenceState(KnowledgeEvidence? evidence, DateTime now) {
  if (evidence == null) return 'not_observed';
  return evidence.isFreshAt(now)
      ? '${evidence.kind.name}/${evidence.confidence.name}/fresh'
      : '${evidence.kind.name}/${evidence.confidence.name}/stale';
}
