// Shared deterministic fixtures for the cognitive substrate suites.
//
// Every builder here takes explicit inputs so each behavioural test states the
// exact epistemic situation it asserts about, rather than depending on whatever
// the live application happens to observe.

import 'dart:io';

import 'package:kristin_local_agent/product/cognitive/cognitive_model.dart';
import 'package:kristin_local_agent/product/cognitive/cognitive_substrate.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/knowledge_memory_v2.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/self_awareness/capability_self_model.dart';

final DateTime testNow = DateTime.utc(2026, 6, 1, 12);

String sourceOf(String relativePath) =>
    File(relativePath).readAsStringSync().replaceAll('\r\n', '\n');

/// Production provider symbol names, so a module that silently stops being
/// composed into the runtime registry is visible from the test.
const Map<String, String> productionProviderSymbols = <String, String>{
  'chat': 'chatProductKnowledgeProvider',
  'project_manager': 'projectProductKnowledgeProvider',
  'runs': 'runsProductKnowledgeProvider',
  'knowledge_memory': 'knowledgeProductKnowledgeProvider',
  'owner_mode': 'ownerProductKnowledgeProvider',
  'browser_web_studio': 'browserProductKnowledgeProvider',
  'models_providers': 'modelsProductKnowledgeProvider',
  'universal_task_kernel': 'taskKernelProductKnowledgeProvider',
  'self_awareness': 'capabilitiesProductKnowledgeProvider',
  'autonomic_recovery': 'recoveryProductKnowledgeProvider',
  'authority_execution': 'authorityProductKnowledgeProvider',
};

String providerSymbolFor(String providerId) =>
    productionProviderSymbols[providerId] ??
    (throw StateError('unknown provider id: $providerId'));

/// Returns one titled section of a rendered coordinator projection.
String sectionOf(String rendered, String title) {
  for (final section in rendered.split('\n\n')) {
    if (section == title || section.startsWith('$title\n')) return section;
  }
  return '';
}

String productSection(String rendered) =>
    sectionOf(rendered, 'PRODUCT KNOWLEDGE');

ModelIdentity testModel({String name = 'qwen3', String digest = 'abc123'}) =>
    ModelIdentity(
      providerId: 'ollama',
      name: name,
      digest: digest,
      discoveredAt: testNow,
    );

ProjectRecord testProject({
  String id = 'project-1',
  String name = 'kris.ai',
  String rootPath = '/workspace/kris.ai',
}) =>
    ProjectRecord(
      id: id,
      name: name,
      rootPath: rootPath,
      createdAt: testNow,
      updatedAt: testNow,
    );

KnowledgeEvidence testEvidence({
  KnowledgeEvidenceKind kind = KnowledgeEvidenceKind.observed,
  String source = 'test',
  ObservationConfidence confidence = ObservationConfidence.high,
  DateTime? observedAt,
  DateTime? expiresAt,
}) =>
    KnowledgeEvidence(
      kind: kind,
      source: source,
      confidence: confidence,
      observedAt: observedAt ?? testNow,
      expiresAt: expiresAt,
    );

CapabilityDescriptor testDescriptor(
  String id, {
  String? runnerToolName,
  CapabilityRiskClass riskClass = CapabilityRiskClass.readOnly,
  Set<String> permissionRequirements = const <String>{},
}) =>
    CapabilityDescriptor(
      id: id,
      name: id,
      description: 'test capability $id',
      category: 'test',
      riskClass: riskClass,
      runnerToolName: runnerToolName,
      permissionRequirements: permissionRequirements,
      providerId: 'test',
      freshnessBudget: const Duration(days: 3650),
      healthFreshnessBudget: const Duration(days: 3650),
    );

KnownCapability testCapability(
  String id, {
  CapabilityAvailabilityState state = CapabilityAvailabilityState.available,
  CapabilityHealthState? health,
  AuthorityObservationState authority = AuthorityObservationState.notEvaluated,
  Set<String> requiredAuthority = const <String>{},
  String? runnerToolName,
  CapabilityRiskClass riskClass = CapabilityRiskClass.readOnly,
}) =>
    KnownCapability(
      descriptor: testDescriptor(
        id,
        runnerToolName: runnerToolName,
        riskClass: riskClass,
      ),
      availability: CapabilityAvailability(
        capabilityId: id,
        state: state,
        requiredAuthority: requiredAuthority,
        authorityObservation: authority,
        observedAt: testNow,
        evidence: <KnowledgeEvidence>[testEvidence(source: 'capability:$id')],
      ),
      health: health == null
          ? null
          : CapabilityHealth(
              capabilityId: id,
              state: health,
              observedAt: testNow,
              evidence: <KnowledgeEvidence>[
                testEvidence(source: 'health:$id'),
              ],
            ),
    );

ApplicationSnapshot testApplication({
  Map<String, Object?>? selectedProject,
  Map<String, Object?>? selectedModel,
  List<Map<String, Object?>> providers = const <Map<String, Object?>>[],
  Map<String, Object?> runState = const <String, Object?>{},
  Map<String, Object?> browser = const <String, Object?>{},
  Map<String, Object?> ownerMode = const <String, Object?>{},
  Map<String, Object?> authority = const <String, Object?>{},
  Map<String, KnowledgeEvidence>? knowledgeEvidence,
}) =>
    ApplicationSnapshot(
      capturedAt: testNow,
      applicationIdentity: 'kris.ai',
      platform: 'linux',
      build: const <String, Object?>{'version': '1.9.0+190'},
      selectedProject: selectedProject,
      selectedModel: selectedModel,
      providers: providers,
      runState: runState,
      browser: browser,
      ownerMode: ownerMode,
      authority: authority,
      knowledgeEvidence: knowledgeEvidence ??
          <String, KnowledgeEvidence>{
            'platform': testEvidence(source: 'platform'),
            'projects': testEvidence(source: 'projects'),
            'models': testEvidence(source: 'models'),
            'runs': testEvidence(source: 'runs'),
            'ownerMode': testEvidence(source: 'ownerMode'),
            'browser': testEvidence(source: 'browser'),
            'authority': testEvidence(source: 'authority'),
          },
    );

KristinSelfSnapshot testSelf({
  ApplicationSnapshot? application,
  List<KnownCapability> capabilities = const <KnownCapability>[],
}) =>
    KristinSelfSnapshot(
      application: application ?? testApplication(),
      capabilities: capabilities,
    );

MemoryEpisode testEpisode({
  required String id,
  String projectId = 'project-1',
  String runId = 'run-1',
  String request = 'Set up the project',
  String summary = 'The project was configured.',
  String failure = '',
  String lessons = 'Prefer the governed path.',
  Set<String> tags = const <String>{'setup'},
  List<String> filesChanged = const <String>[],
  List<String> evidenceHashes = const <String>['hash-1'],
  RunState outcome = RunState.succeeded,
  bool pinned = false,
  String admission = 'admitted',
  bool diagnosticOnly = false,
  String? contentHash,
  DateTime? createdAt,
}) =>
    MemoryEpisode(
      id: id,
      projectId: projectId,
      runId: runId,
      request: request,
      mode: CommandMode.build,
      outcome: outcome,
      summary: summary,
      failure: failure,
      lessons: lessons,
      tags: tags,
      completedItems: const <String>[],
      failedItems: const <String>[],
      filesChanged: filesChanged,
      evidenceIds: const <String>[],
      evidenceHashes: evidenceHashes,
      startedAt: createdAt ?? testNow,
      completedAt: createdAt ?? testNow,
      modelRequests: 1,
      toolCalls: 1,
      mutations: 0,
      repairs: 0,
      contentHash: contentHash ?? 'content-$id',
      createdAt: createdAt ?? testNow,
      pinned: pinned,
      admission: admission,
      diagnosticOnly: diagnosticOnly,
    );

KnowledgeEntry testKnowledgeEntry({
  required String id,
  String projectId = 'project-1',
  String title = 'Project note',
  String content = 'The project uses Flutter.',
  KnowledgeKind kind = KnowledgeKind.note,
  String trust = 'user_or_verified',
  Set<String> tags = const <String>{'note'},
}) =>
    KnowledgeEntry(
      id: id,
      projectId: projectId,
      title: title,
      content: content,
      tags: tags,
      sourceUrl: '',
      contentHash: 'khash-$id',
      createdAt: testNow,
      updatedAt: testNow,
      trust: trust,
      kind: kind,
    );

KnowledgeSearchHit testHit({
  required String recordId,
  KnowledgeKind kind = KnowledgeKind.note,
  String episodeId = '',
  String title = 'hit',
  String snippet = 'snippet body',
  double score = 1,
  String trust = 'user_or_verified',
}) =>
    KnowledgeSearchHit(
      citation: 'K1',
      kind: kind,
      recordId: recordId,
      knowledgeId: kind == KnowledgeKind.episode ? '' : recordId,
      episodeId: episodeId,
      archiveId: '',
      title: title,
      sourceUrl: '',
      snippet: snippet,
      contentHash: 'hash-$recordId',
      trust: trust,
      tags: const <String>{},
      score: score,
      lexicalScore: score,
      semanticScore: score,
      recencyScore: 0,
      capturedAt: testNow,
      chunkIndex: 0,
    );

ModelGenerationResult testModelResult(String text, ModelIdentity identity) =>
    ModelGenerationResult(
      text: text,
      identity: identity,
      startedAt: testNow,
      firstTokenAt: testNow,
      completedAt: testNow,
    );

/// Records every retrieval the substrate performs, so a suite can prove that
/// an ordinary conversation never reaches project knowledge or memory.
class RecordingLoaders {
  RecordingLoaders({
    this.knowledge = const <KnowledgeEntry>[],
    this.memory = const <MemoryEpisode>[],
    this.published = const <PublishedSkillRecord>[],
    this.candidates = const <SkillCandidateRecord>[],
  });

  final List<KnowledgeEntry> knowledge;
  final List<MemoryEpisode> memory;
  final List<PublishedSkillRecord> published;
  final List<SkillCandidateRecord> candidates;

  int knowledgeLoads = 0;
  int memoryLoads = 0;
  int publishedLoads = 0;
  final List<Map<String, Object?>> retrievals = <Map<String, Object?>>[];
}

KristinCognitiveSubstrate buildTestSubstrate({
  KristinSelfSnapshot? self,
  ProjectRecord? project,
  RecordingLoaders? loaders,
  CognitiveKnowledgeRetriever? retrieveKnowledge,
  void Function(Map<String, Object?> call)? onSelfSnapshot,
}) {
  final recording = loaders ?? RecordingLoaders();
  final snapshot = self ?? testSelf();
  return KristinCognitiveSubstrate(
    loadSelfSnapshot: ({
      ProjectRecord? selectedProject,
      ModelIdentity? selectedModel,
      bool forceRefresh = false,
    }) async {
      onSelfSnapshot?.call(<String, Object?>{
        'projectId': selectedProject?.id,
        'modelExactId': selectedModel?.exactId,
        'forceRefresh': forceRefresh,
      });
      return snapshot;
    },
    loadProject: (String id) async =>
        project != null && project.id == id ? project : null,
    loadKnowledge: (String projectId) async {
      recording.knowledgeLoads += 1;
      return recording.knowledge;
    },
    loadMemory: (String projectId) async {
      recording.memoryLoads += 1;
      return recording.memory;
    },
    loadPublishedSkills: () async {
      recording.publishedLoads += 1;
      return recording.published;
    },
    loadSkillCandidates: () async => recording.candidates,
    retrieveKnowledge: retrieveKnowledge,
  );
}
