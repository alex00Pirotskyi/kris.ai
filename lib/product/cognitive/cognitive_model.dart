import 'dart:math';

import '../crypto_utils.dart';
import '../domain.dart';
import '../knowledge_memory_v2.dart';
import '../models_research.dart';
import '../self_awareness/capability_self_model.dart';

enum CognitiveClaimScope {
  application,
  globalKristin,
  user,
  project,
  session,
  run,
  capability,
  skill,
}

enum CognitiveClaimProvenance {
  runtimeObservation,
  registeredProductProvider,
  configuration,
  repository,
  projectKnowledge,
  research,
  memoryEpisode,
  publishedSkill,
  userStatement,
  modelInference,
}

enum CognitiveEpistemicStatus {
  observed,
  configured,
  verified,
  remembered,
  inferred,
  userAsserted,
  stale,
  unknown,
  conflicting,
}

enum CognitiveLifecycleState {
  valid,
  stale,
  contradicted,
  superseded,
  revoked,
}

enum CognitiveMemoryKind {
  working,
  episodic,
  semantic,
  procedural,
  diagnostic,
  pinned,
}

enum CognitiveSkillUsability { usable, blocked, unknown }

enum CognitiveReasoningPathway {
  conversation,
  taskUnderstanding,
  taskPlanning,
  execution,
  recovery,
  introspection,
}

enum CognitiveConversationKind { knowledgeOnly, effectfulObjective, unclear }

final class CognitiveClaim {
  CognitiveClaim({
    String? id,
    required this.subject,
    required this.predicate,
    required this.value,
    required this.scope,
    required this.provenance,
    required this.epistemicStatus,
    required this.confidence,
    required this.createdAt,
    this.observedAt,
    this.expiresAt,
    this.lifecycle = CognitiveLifecycleState.valid,
    this.evidence = const <KnowledgeEvidence>[],
    this.tags = const <String>{},
  }) : id = id ??
            'cognitive_claim_${Sha256.text(canonicalJson(<String, dynamic>{
              'subject': subject,
              'predicate': predicate,
              'value': value,
              'scope': scope.name,
              'provenance': provenance.name,
            })).substring(0, 24)}';

  final String id;
  final String subject;
  final String predicate;
  final Object? value;
  final CognitiveClaimScope scope;
  final CognitiveClaimProvenance provenance;
  final CognitiveEpistemicStatus epistemicStatus;
  final ObservationConfidence confidence;
  final DateTime createdAt;
  final DateTime? observedAt;
  final DateTime? expiresAt;
  final CognitiveLifecycleState lifecycle;
  final List<KnowledgeEvidence> evidence;
  final Set<String> tags;

  bool freshAt(DateTime now) =>
      lifecycle == CognitiveLifecycleState.valid &&
      (expiresAt == null || expiresAt!.isAfter(now.toUtc()));

  String get resolutionKey => '${scope.name}|$subject|$predicate';

  CognitiveClaim copyWith({
    CognitiveEpistemicStatus? epistemicStatus,
    CognitiveLifecycleState? lifecycle,
  }) =>
      CognitiveClaim(
        id: id,
        subject: subject,
        predicate: predicate,
        value: value,
        scope: scope,
        provenance: provenance,
        epistemicStatus: epistemicStatus ?? this.epistemicStatus,
        confidence: confidence,
        createdAt: createdAt,
        observedAt: observedAt,
        expiresAt: expiresAt,
        lifecycle: lifecycle ?? this.lifecycle,
        evidence: evidence,
        tags: tags,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'subject': subject,
        'predicate': predicate,
        'value': value,
        'scope': scope.name,
        'provenance': provenance.name,
        'epistemicStatus': epistemicStatus.name,
        'confidence': confidence.name,
        'lifecycle': lifecycle.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (observedAt != null)
          'observedAt': observedAt!.toUtc().toIso8601String(),
        if (expiresAt != null)
          'expiresAt': expiresAt!.toUtc().toIso8601String(),
        'evidence': evidence.map((item) => item.toJson()).toList(growable: false),
        'tags': tags.toList()..sort(),
      };
}

final class CognitiveClaimConflict {
  const CognitiveClaimConflict({
    required this.key,
    required this.preferredClaimId,
    required this.conflictingClaimIds,
    required this.explanation,
  });

  final String key;
  final String preferredClaimId;
  final List<String> conflictingClaimIds;
  final String explanation;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'preferredClaimId': preferredClaimId,
        'conflictingClaimIds': conflictingClaimIds,
        'explanation': explanation,
      };
}

final class CognitiveClaimResolution {
  const CognitiveClaimResolution({
    required this.claims,
    required this.conflicts,
  });

  final List<CognitiveClaim> claims;
  final List<CognitiveClaimConflict> conflicts;
}

/// Authority/freshness/provenance are the primary ordering dimensions.
/// Textual similarity is intentionally absent from this policy: retrieval
/// relevance may select candidates, but it can never promote a weaker source
/// over fresh runtime truth.
final class CognitiveClaimTrustPolicy {
  const CognitiveClaimTrustPolicy();

  int score(CognitiveClaim claim, DateTime now) {
    final provenance = switch (claim.provenance) {
      CognitiveClaimProvenance.runtimeObservation => 900,
      CognitiveClaimProvenance.configuration => 820,
      CognitiveClaimProvenance.registeredProductProvider => 780,
      CognitiveClaimProvenance.repository => 720,
      CognitiveClaimProvenance.projectKnowledge => 690,
      CognitiveClaimProvenance.research => 640,
      CognitiveClaimProvenance.publishedSkill => 610,
      CognitiveClaimProvenance.memoryEpisode => 500,
      CognitiveClaimProvenance.userStatement => 340,
      CognitiveClaimProvenance.modelInference => 160,
    };
    final epistemic = switch (claim.epistemicStatus) {
      CognitiveEpistemicStatus.observed => 90,
      CognitiveEpistemicStatus.configured => 82,
      CognitiveEpistemicStatus.verified => 74,
      CognitiveEpistemicStatus.remembered => 52,
      CognitiveEpistemicStatus.userAsserted => 40,
      CognitiveEpistemicStatus.inferred => 24,
      CognitiveEpistemicStatus.unknown => 0,
      CognitiveEpistemicStatus.stale => -80,
      CognitiveEpistemicStatus.conflicting => -100,
    };
    final confidence = switch (claim.confidence) {
      ObservationConfidence.certain => 30,
      ObservationConfidence.high => 24,
      ObservationConfidence.medium => 16,
      ObservationConfidence.low => 8,
      ObservationConfidence.unknown => 0,
    };
    final lifecycle = switch (claim.lifecycle) {
      CognitiveLifecycleState.valid => 0,
      CognitiveLifecycleState.stale => -260,
      CognitiveLifecycleState.superseded => -360,
      CognitiveLifecycleState.contradicted => -420,
      CognitiveLifecycleState.revoked => -1000,
    };
    final freshness = claim.freshAt(now) ? 40 : -180;
    return provenance + epistemic + confidence + lifecycle + freshness;
  }

  CognitiveClaimResolution resolve(
    Iterable<CognitiveClaim> input, {
    DateTime? now,
  }) {
    final reference = (now ?? DateTime.now().toUtc()).toUtc();
    final grouped = <String, List<CognitiveClaim>>{};
    for (final claim in input) {
      grouped.putIfAbsent(claim.resolutionKey, () => <CognitiveClaim>[]).add(claim);
    }
    final resolved = <CognitiveClaim>[];
    final conflicts = <CognitiveClaimConflict>[];
    final keys = grouped.keys.toList()..sort();
    for (final key in keys) {
      final claims = grouped[key]!..sort((a, b) {
        final trust = score(b, reference).compareTo(score(a, reference));
        if (trust != 0) return trust;
        final observedA = a.observedAt ?? a.createdAt;
        final observedB = b.observedAt ?? b.createdAt;
        final freshness = observedB.compareTo(observedA);
        if (freshness != 0) return freshness;
        return a.id.compareTo(b.id);
      });
      final preferred = claims.first;
      final preferredExpired = preferred.lifecycle == CognitiveLifecycleState.valid &&
          preferred.expiresAt != null &&
          !preferred.expiresAt!.isAfter(reference);
      resolved.add(
        preferredExpired
            ? preferred.copyWith(
                epistemicStatus: CognitiveEpistemicStatus.stale,
                lifecycle: CognitiveLifecycleState.stale,
              )
            : preferred,
      );
      final preferredValue = canonicalJson(preferred.value);
      final contradictory = <String>[];
      for (final candidate in claims.skip(1)) {
        if (canonicalJson(candidate.value) == preferredValue) {
          resolved.add(
            candidate.copyWith(lifecycle: CognitiveLifecycleState.superseded),
          );
          continue;
        }
        contradictory.add(candidate.id);
        resolved.add(
          candidate.copyWith(
            epistemicStatus: CognitiveEpistemicStatus.conflicting,
            lifecycle: CognitiveLifecycleState.contradicted,
          ),
        );
      }
      if (contradictory.isNotEmpty) {
        conflicts.add(
          CognitiveClaimConflict(
            key: key,
            preferredClaimId: preferred.id,
            conflictingClaimIds: List<String>.unmodifiable(contradictory),
            explanation:
                'Conflicting values are retained as history. The higher-authority, fresher claim is preferred; similarity never changes this ordering.',
          ),
        );
      }
    }
    return CognitiveClaimResolution(
      claims: List<CognitiveClaim>.unmodifiable(resolved),
      conflicts: List<CognitiveClaimConflict>.unmodifiable(conflicts),
    );
  }
}

final class CognitiveIdentityView {
  const CognitiveIdentityView({required this.reasoningModel});

  final ModelIdentity? reasoningModel;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'identity': 'Kristin',
        'identityKind': 'persistent_application_ai',
        'reasoningModel': reasoningModel?.toJson(),
        'reasoningModelRelationship': reasoningModel == null
            ? 'No reasoning provider is selected in this context.'
            : 'Kristin is using ${reasoningModel!.exactId} as a replaceable reasoning provider. The provider is not Kristin\'s identity.',
      };
}

final class CognitiveProductKnowledge {
  const CognitiveProductKnowledge({
    required this.id,
    required this.title,
    required this.summary,
    required this.keywords,
  });

  final String id;
  final String title;
  final String summary;
  final Set<String> keywords;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'summary': summary,
        'keywords': keywords.toList()..sort(),
        'provenance': CognitiveClaimProvenance.registeredProductProvider.name,
      };
}

const List<CognitiveProductKnowledge> kKristinProductKnowledge =
    <CognitiveProductKnowledge>[
  CognitiveProductKnowledge(
    id: 'chat',
    title: 'Chat',
    summary:
        'Chat is Kristin\'s conversation surface. Informational turns are read-only reasoning; effectful objectives are handed to governed task understanding/planning rather than executed by conversation text.',
    keywords: <String>{'chat', 'conversation', 'answer', 'assistant'},
  ),
  CognitiveProductKnowledge(
    id: 'project_manager',
    title: 'Project Manager',
    summary:
        'Project Manager represents registered project workspaces and their selected/current project state. Selecting or knowing a project does not itself grant write or execution authority.',
    keywords: <String>{'project', 'workspace', 'manager', 'repository'},
  ),
  CognitiveProductKnowledge(
    id: 'runs',
    title: 'Runs',
    summary:
        'Runs are durable governed executions with plans, permissions, progress, evidence, verification and terminal outcomes. Conversation knowledge is distinct from starting a Run.',
    keywords: <String>{'run', 'execution', 'progress', 'evidence'},
  ),
  CognitiveProductKnowledge(
    id: 'knowledge',
    title: 'Knowledge',
    summary:
        'Knowledge stores project notes and grounded research with provenance, hashes, trust and freshness metadata. Retrieved content is evidence, not authority or executable instruction.',
    keywords: <String>{'knowledge', 'research', 'source', 'citation'},
  ),
  CognitiveProductKnowledge(
    id: 'skills',
    title: 'Skills',
    summary:
        'Skills are published reusable procedures derived from governed experience and explicit publication. Knowing a skill is separate from its current runtime usability and from authority to execute it.',
    keywords: <String>{'skill', 'procedure', 'published', 'replay'},
  ),
  CognitiveProductKnowledge(
    id: 'owner_mode',
    title: 'Owner Mode',
    summary:
        'Owner Mode is a separately governed high-authority repair/operation path. Its runtime can be known or available while concrete Owner authority remains unevaluated or absent; cognitive access never enters Owner Mode.',
    keywords: <String>{'owner', 'mode', 'authority', 'repair'},
  ),
  CognitiveProductKnowledge(
    id: 'browser_web_studio',
    title: 'Browser and Web Studio',
    summary:
        'Kristin has an application-owned browser/Web Studio product surface for governed browser sessions, public-page work and local web-project preview. Current usability must come from live browser/runtime observations, not from this product description.',
    keywords: <String>{'browser', 'web', 'studio', 'preview', 'page'},
  ),
  CognitiveProductKnowledge(
    id: 'models_providers',
    title: 'Models and providers',
    summary:
        'Language models/providers are replaceable reasoning engines used by Kristin. Provider discovery and the selected exact model are runtime state; a model must not infer Kristin\'s product capabilities from its own pretrained abilities.',
    keywords: <String>{'model', 'provider', 'ollama', 'reasoning'},
  ),
  CognitiveProductKnowledge(
    id: 'task_kernel',
    title: 'Universal Task Kernel',
    summary:
        'The Universal Task Kernel turns an effectful objective into validated understanding, routing, a canonical task plan and a compiled governed execution contract. The cognitive substrate supplies knowledge; it is not a second planner.',
    keywords: <String>{'task', 'kernel', 'plan', 'planning', 'objective'},
  ),
  CognitiveProductKnowledge(
    id: 'capabilities',
    title: 'Capabilities',
    summary:
        'A capability can be known while unavailable, unhealthy, unauthorized or non-executable. Capability descriptors, live availability, health and authority observations are separate facts.',
    keywords: <String>{'capability', 'available', 'health', 'blocked'},
  ),
  CognitiveProductKnowledge(
    id: 'recovery',
    title: 'Recovery',
    summary:
        'Recovery observes failures, classifies recoverability and can route bounded repair work through existing governed mechanisms. Recovery knowledge does not bypass permissions or widen tools.',
    keywords: <String>{'recovery', 'failure', 'repair', 'diagnostic'},
  ),
  CognitiveProductKnowledge(
    id: 'authority_execution',
    title: 'Authority and execution',
    summary:
        'Knowledge, capability availability and model proposals never mint permissions. Concrete effects remain constrained by the existing authority service, grants, Owner boundaries and the Runner/tool allow-list.',
    keywords: <String>{'authority', 'permission', 'grant', 'tool', 'runner'},
  ),
];

final class CognitiveSkillView {
  const CognitiveSkillView({
    required this.id,
    required this.title,
    required this.version,
    required this.instructions,
    required this.origin,
    required this.sourceEpisodeId,
    required this.evidenceHashes,
    required this.recommendedTools,
    required this.requiredCapabilityIds,
    required this.requiredAuthority,
    required this.prerequisites,
    required this.applicability,
    required this.limitations,
    required this.risk,
    required this.publicationState,
    required this.usability,
    required this.blockers,
    required this.publishedAt,
    required this.lastObservedAt,
    this.lastVerifiedAt,
  });

  final String id;
  final String title;
  final int version;
  final String instructions;
  final String origin;
  final String sourceEpisodeId;
  final List<String> evidenceHashes;
  final Set<String> recommendedTools;
  final Set<String> requiredCapabilityIds;
  final Set<String> requiredAuthority;
  final List<String> prerequisites;
  final List<String> applicability;
  final List<String> limitations;
  final String risk;
  final String publicationState;
  final CognitiveSkillUsability usability;
  final List<String> blockers;
  final DateTime publishedAt;
  final DateTime lastObservedAt;
  final DateTime? lastVerifiedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'version': version,
        'instructions': instructions,
        'origin': origin,
        'sourceEpisodeId': sourceEpisodeId,
        'evidenceHashes': evidenceHashes,
        'recommendedTools': recommendedTools.toList()..sort(),
        'requiredCapabilities': requiredCapabilityIds.toList()..sort(),
        'requiredAuthority': requiredAuthority.toList()..sort(),
        'prerequisites': prerequisites,
        'applicability': applicability,
        'limitations': limitations,
        'risk': risk,
        'publicationState': publicationState,
        'usability': usability.name,
        'blockers': blockers,
        'publishedAt': publishedAt.toUtc().toIso8601String(),
        'lastObservedAt': lastObservedAt.toUtc().toIso8601String(),
        if (lastVerifiedAt != null)
          'lastVerifiedAt': lastVerifiedAt!.toUtc().toIso8601String(),
      };
}

final class CognitiveKnowledgeView {
  const CognitiveKnowledgeView({
    required this.id,
    required this.projectId,
    required this.title,
    required this.summary,
    required this.tags,
    required this.sourceUrl,
    required this.contentHash,
    required this.trust,
    required this.kind,
    required this.pinned,
    required this.updatedAt,
    required this.freshness,
    required this.evidence,
  });

  final String id;
  final String projectId;
  final String title;
  final String summary;
  final Set<String> tags;
  final String sourceUrl;
  final String contentHash;
  final String trust;
  final String kind;
  final bool pinned;
  final DateTime updatedAt;
  final ResearchFreshnessState freshness;
  final List<KnowledgeEvidence> evidence;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'projectId': projectId,
        'title': title,
        'summary': summary,
        'tags': tags.toList()..sort(),
        'sourceUrl': sourceUrl,
        'contentHash': contentHash,
        'trust': trust,
        'kind': kind,
        'pinned': pinned,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'freshness': freshness.name,
        'evidence': evidence.map((item) => item.toJson()).toList(growable: false),
      };
}

final class CognitiveMemoryView {
  const CognitiveMemoryView({
    required this.id,
    required this.projectId,
    required this.runId,
    required this.request,
    required this.summary,
    required this.lessons,
    required this.outcome,
    required this.kinds,
    required this.admission,
    required this.admissionReason,
    required this.retrievalAllowed,
    required this.evidenceHashes,
    required this.createdAt,
    required this.conflictsWithCurrentPolicy,
  });

  final String id;
  final String projectId;
  final String runId;
  final String request;
  final String summary;
  final String lessons;
  final String outcome;
  final Set<CognitiveMemoryKind> kinds;
  final String admission;
  final String admissionReason;
  final bool retrievalAllowed;
  final List<String> evidenceHashes;
  final DateTime createdAt;
  final bool conflictsWithCurrentPolicy;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'projectId': projectId,
        'runId': runId,
        'request': request,
        'summary': summary,
        'lessons': lessons,
        'outcome': outcome,
        'kinds': kinds.map((item) => item.name).toList()..sort(),
        'admission': admission,
        'admissionReason': admissionReason,
        'retrievalAllowed': retrievalAllowed,
        'evidenceHashes': evidenceHashes,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'conflictsWithCurrentPolicy': conflictsWithCurrentPolicy,
      };
}

final class CognitiveUncertainty {
  const CognitiveUncertainty({
    required this.id,
    required this.domain,
    required this.status,
    required this.detail,
  });

  final String id;
  final String domain;
  final CognitiveEpistemicStatus status;
  final String detail;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'domain': domain,
        'status': status.name,
        'detail': detail,
      };
}

final class KristinCognitiveSnapshot {
  const KristinCognitiveSnapshot({
    required this.capturedAt,
    required this.identity,
    required this.self,
    required this.claims,
    required this.productKnowledge,
    required this.skills,
    required this.knowledge,
    required this.memory,
    required this.conflicts,
    required this.uncertainty,
  });

  final DateTime capturedAt;
  final CognitiveIdentityView identity;
  final KristinSelfSnapshot self;
  final List<CognitiveClaim> claims;
  final List<CognitiveProductKnowledge> productKnowledge;
  final List<CognitiveSkillView> skills;
  final List<CognitiveKnowledgeView> knowledge;
  final List<CognitiveMemoryView> memory;
  final List<CognitiveClaimConflict> conflicts;
  final List<CognitiveUncertainty> uncertainty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'identity': identity.toJson(),
        'self': self.toJson(),
        'claims': claims.map((item) => item.toJson()).toList(growable: false),
        'productKnowledge':
            productKnowledge.map((item) => item.toJson()).toList(growable: false),
        'skills': skills.map((item) => item.toJson()).toList(growable: false),
        'knowledge': knowledge.map((item) => item.toJson()).toList(growable: false),
        'memory': memory.map((item) => item.toJson()).toList(growable: false),
        'conflicts': conflicts.map((item) => item.toJson()).toList(growable: false),
        'uncertainty':
            uncertainty.map((item) => item.toJson()).toList(growable: false),
      };
}

typedef CognitiveSelfSnapshotLoader = Future<KristinSelfSnapshot> Function({
  ProjectRecord? selectedProject,
  ModelIdentity? selectedModel,
  bool forceRefresh,
});
typedef CognitiveProjectLoader = Future<ProjectRecord?> Function(String id);
typedef CognitiveKnowledgeLoader = Future<List<KnowledgeEntry>> Function(
  String projectId,
);
typedef CognitiveMemoryLoader = Future<List<MemoryEpisode>> Function(
  String projectId,
);
typedef CognitivePublishedSkillLoader = Future<List<PublishedSkillRecord>>
    Function();
typedef CognitiveSkillCandidateLoader = Future<List<SkillCandidateRecord>>
    Function();

final class CognitiveContextRequest {
  const CognitiveContextRequest({
    required this.objective,
    this.pathway = CognitiveReasoningPathway.conversation,
    this.selectedProject,
    this.projectId,
    this.selectedModel,
    this.sessionKey = 'default',
    this.taskFamily = '',
    this.capabilityHints = const <String>{},
    this.workingMemory = const <String>[],
    this.maxCharacters = 7200,
    this.forceRefresh = false,
  });

  final String objective;
  final CognitiveReasoningPathway pathway;
  final ProjectRecord? selectedProject;
  final String? projectId;
  final ModelIdentity? selectedModel;
  final String sessionKey;
  final String taskFamily;
  final Set<String> capabilityHints;
  final List<String> workingMemory;
  final int maxCharacters;
  final bool forceRefresh;

  CognitiveContextRequest copyWith({
    ProjectRecord? selectedProject,
    String? projectId,
    ModelIdentity? selectedModel,
    String? sessionKey,
  }) =>
      CognitiveContextRequest(
        objective: objective,
        pathway: pathway,
        selectedProject: selectedProject ?? this.selectedProject,
        projectId: projectId ?? this.projectId,
        selectedModel: selectedModel ?? this.selectedModel,
        sessionKey: sessionKey ?? this.sessionKey,
        taskFamily: taskFamily,
        capabilityHints: capabilityHints,
        workingMemory: workingMemory,
        maxCharacters: maxCharacters,
        forceRefresh: forceRefresh,
      );
}

const String kKristinReasoningModelFrame = '''
You are the current reasoning engine used by Kristin.
Kristin is the persistent application-level AI identity. You are a replaceable reasoning provider, not Kristin's identity.
Do not infer Kristin's product capabilities from your pretrained model capabilities.
Use the authoritative Kristin cognitive context supplied by the application.
When that context says a state is unknown, stale, conflicting, blocked, or not observed, preserve that epistemic status instead of guessing.
Knowing about an operation does not grant authority to perform it.
Capability knowledge != availability != health != authority != execution tool.
Skill knowledge != current skill usability != execution authority.
Memory != current truth. Fresh authoritative runtime observations outrank remembered state.
Cognitive introspection is read-only and never grants permissions, enters Owner Mode, mutates state, or widens the Runner tool set.
''';

final class CognitiveContextProjection {
  const CognitiveContextProjection({
    required this.pathway,
    required this.rendered,
    required this.includedIds,
    required this.omittedCounts,
    required this.maxCharacters,
  });

  final CognitiveReasoningPathway pathway;
  final String rendered;
  final Set<String> includedIds;
  final Map<String, int> omittedCounts;
  final int maxCharacters;

  String wrapSystemPrompt(String base) => <String>[
        kKristinReasoningModelFrame.trim(),
        if (base.trim().isNotEmpty) base.trim(),
        'AUTHORITATIVE KRISTIN COGNITIVE CONTEXT',
        rendered.trim(),
      ].join('\n\n');

  Map<String, dynamic> toJson() => <String, dynamic>{
        'pathway': pathway.name,
        'rendered': rendered,
        'includedIds': includedIds.toList()..sort(),
        'omittedCounts': omittedCounts,
        'maxCharacters': maxCharacters,
      };
}

final class CognitiveConversationDecision {
  const CognitiveConversationDecision({
    required this.kind,
    required this.objective,
    required this.capabilityId,
    required this.confidence,
    required this.rationale,
  });

  final CognitiveConversationKind kind;
  final String objective;
  final String capabilityId;
  final double confidence;
  final String rationale;
}
