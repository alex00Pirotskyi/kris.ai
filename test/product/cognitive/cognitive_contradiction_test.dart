// Behavioural proof for deterministic contradiction resolution.
//
// Two things can be true at once in a long-lived assistant: an old run
// remembers a fact, and the runtime observes a different one right now. The
// substrate must resolve that deterministically, prefer the authoritative
// observation, and still keep the contradicted memory as history rather than
// deleting it.

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/cognitive/cognitive_model.dart';
import 'package:kristin_local_agent/product/cognitive/memory_fact_index.dart';
import 'package:kristin_local_agent/product/cognitive/runtime_cognitive_enrichment.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/product_knowledge.dart';
import 'package:kristin_local_agent/product/self_awareness/capability_self_model.dart';

import 'cognitive_test_support.dart';

CognitiveClaim _claim({
  required String subject,
  required String predicate,
  required Object? value,
  required CognitiveClaimProvenance provenance,
  required CognitiveEpistemicStatus epistemicStatus,
  CognitiveClaimScope scope = CognitiveClaimScope.application,
  ObservationConfidence confidence = ObservationConfidence.high,
  DateTime? observedAt,
}) =>
    CognitiveClaim(
      subject: subject,
      predicate: predicate,
      value: value,
      scope: scope,
      provenance: provenance,
      epistemicStatus: epistemicStatus,
      confidence: confidence,
      createdAt: observedAt ?? testNow,
      observedAt: observedAt ?? testNow,
    );

CognitiveMemoryFactAtom _atom({
  required String subject,
  required String predicate,
  required Object? value,
  String episodeId = 'episode-1',
  CognitiveClaimScope scope = CognitiveClaimScope.project,
  ObservationConfidence confidence = ObservationConfidence.high,
}) =>
    CognitiveMemoryFactAtom(
      episodeId: episodeId,
      projectId: 'project-1',
      subject: subject,
      predicate: predicate,
      value: value,
      scope: scope,
      confidence: confidence,
      sourceHash: 'source-$episodeId',
      episodeContentHash: 'content-$episodeId',
      atomizerVersion: kCognitiveMemoryFactAtomizerVersion,
      modelExactId: 'ollama/qwen3@abc123',
      extractedAt: testNow,
    );

CognitiveRuntimeEnrichment _enrichment() {
  final registry = KristinProductKnowledgeRegistry()
    ..register(
      const StaticProductKnowledgeProvider(
        providerId: 'test',
        descriptors: <ProductKnowledgeDescriptor>[
          ProductKnowledgeDescriptor(
            id: 'capabilities',
            title: 'Capabilities',
            summary: 'Capability descriptors are separate from live state.',
            keywords: <String>{'capability'},
          ),
        ],
      ),
    );
  return CognitiveRuntimeEnrichment(productKnowledge: registry);
}

void main() {
  group('claim trust resolution', () {
    const policy = CognitiveClaimTrustPolicy();

    test('two historical episodes on one field resolve deterministically', () {
      CognitiveClaimResolution resolve() => policy.resolve(
            <CognitiveClaim>[
              _claim(
                subject: 'project:project-1',
                predicate: 'framework',
                value: 'Flutter',
                scope: CognitiveClaimScope.project,
                provenance: CognitiveClaimProvenance.memoryEpisode,
                epistemicStatus: CognitiveEpistemicStatus.remembered,
                observedAt: DateTime.utc(2026, 1, 1),
              ),
              _claim(
                subject: 'project:project-1',
                predicate: 'framework',
                value: 'React Native',
                scope: CognitiveClaimScope.project,
                provenance: CognitiveClaimProvenance.memoryEpisode,
                epistemicStatus: CognitiveEpistemicStatus.remembered,
                observedAt: DateTime.utc(2026, 5, 1),
              ),
            ],
            now: testNow,
          );

      final first = resolve();
      final second = resolve();
      expect(first.conflicts.single.key, 'project|project:project-1|framework');
      expect(
        first.conflicts.single.preferredClaimId,
        second.conflicts.single.preferredClaimId,
      );
      final preferred = first.claims.firstWhere(
        (claim) => claim.id == first.conflicts.single.preferredClaimId,
      );
      expect(preferred.value, 'React Native');
    });

    test('newer memory supersedes an older equivalent memory', () {
      final resolution = policy.resolve(
        <CognitiveClaim>[
          _claim(
            subject: 'project:project-1',
            predicate: 'framework',
            value: 'Flutter',
            scope: CognitiveClaimScope.project,
            provenance: CognitiveClaimProvenance.memoryEpisode,
            epistemicStatus: CognitiveEpistemicStatus.remembered,
            observedAt: DateTime.utc(2026, 1, 1),
          ),
          _claim(
            subject: 'project:project-1',
            predicate: 'framework',
            value: 'Flutter',
            scope: CognitiveClaimScope.project,
            provenance: CognitiveClaimProvenance.memoryEpisode,
            epistemicStatus: CognitiveEpistemicStatus.remembered,
            observedAt: DateTime.utc(2026, 5, 1),
          ),
        ],
        now: testNow,
      );
      // Agreement is not a conflict, but only one claim stays current.
      expect(resolution.conflicts, isEmpty);
      expect(
        resolution.claims
            .where(
              (claim) => claim.lifecycle == CognitiveLifecycleState.superseded,
            )
            .length,
        1,
      );
      expect(resolution.currentClaims.length, 1);
      expect(
        resolution.currentClaims.single.observedAt,
        DateTime.utc(2026, 5, 1),
      );
    });

    test('a fresh runtime observation outranks contradicting memory', () {
      final resolution = policy.resolve(
        <CognitiveClaim>[
          _claim(
            subject: 'application',
            predicate: 'selectedModel',
            value: 'ollama/old-model',
            provenance: CognitiveClaimProvenance.memoryEpisode,
            epistemicStatus: CognitiveEpistemicStatus.remembered,
            // Deliberately the most recent claim, so only authority can win.
            observedAt: DateTime.utc(2026, 5, 30),
          ),
          _claim(
            subject: 'application',
            predicate: 'selectedModel',
            value: 'ollama/qwen3',
            provenance: CognitiveClaimProvenance.runtimeObservation,
            epistemicStatus: CognitiveEpistemicStatus.observed,
            observedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        now: testNow,
      );
      expect(resolution.currentClaims.single.value, 'ollama/qwen3');
      expect(
        resolution.currentClaims.single.provenance,
        CognitiveClaimProvenance.runtimeObservation,
      );
    });

    test('configuration outranks weaker historical memory', () {
      final resolution = policy.resolve(
        <CognitiveClaim>[
          _claim(
            subject: 'application',
            predicate: 'authority',
            value: <String, Object?>{'ownerMode': 'granted'},
            provenance: CognitiveClaimProvenance.memoryEpisode,
            epistemicStatus: CognitiveEpistemicStatus.remembered,
            observedAt: DateTime.utc(2026, 5, 30),
          ),
          _claim(
            subject: 'application',
            predicate: 'authority',
            value: <String, Object?>{'ownerMode': 'not_evaluated'},
            provenance: CognitiveClaimProvenance.configuration,
            epistemicStatus: CognitiveEpistemicStatus.configured,
            observedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        now: testNow,
      );
      expect(
        resolution.currentClaims.single.provenance,
        CognitiveClaimProvenance.configuration,
      );
      expect(
        resolution.currentClaims.single.value,
        <String, Object?>{'ownerMode': 'not_evaluated'},
      );
    });

    test('model inference never outranks remembered experience', () {
      final resolution = policy.resolve(
        <CognitiveClaim>[
          _claim(
            subject: 'project:project-1',
            predicate: 'framework',
            value: 'Flutter',
            scope: CognitiveClaimScope.project,
            provenance: CognitiveClaimProvenance.memoryEpisode,
            epistemicStatus: CognitiveEpistemicStatus.remembered,
            confidence: ObservationConfidence.low,
          ),
          _claim(
            subject: 'project:project-1',
            predicate: 'framework',
            value: 'Ruby on Rails',
            scope: CognitiveClaimScope.project,
            provenance: CognitiveClaimProvenance.modelInference,
            epistemicStatus: CognitiveEpistemicStatus.inferred,
            confidence: ObservationConfidence.high,
          ),
        ],
        now: testNow,
      );
      expect(resolution.currentClaims.single.value, 'Flutter');
    });

    test('contradicted memory stays as history but not as current truth',
        () async {
      final enrichment = _enrichment();
      final substrate = buildTestSubstrate(
        self: testSelf(
          application: testApplication(
            selectedModel: <String, Object?>{'exactId': 'ollama/qwen3'},
          ),
        ),
      );
      final episode = testEpisode(id: 'episode-old');
      final snapshot = enrichment.enrichSnapshot(
        await substrate.snapshot(),
        factsByEpisodeId: <String, List<CognitiveMemoryFactAtom>>{
          'episode-old': <CognitiveMemoryFactAtom>[
            _atom(
              episodeId: 'episode-old',
              subject: 'application',
              predicate: 'selectedModel',
              value: <String, Object?>{'exactId': 'ollama/legacy'},
              scope: CognitiveClaimScope.application,
            ),
          ],
        },
        episodesById: <String, MemoryEpisode>{'episode-old': episode},
      );

      final remembered = snapshot.claims.where(
        (claim) =>
            claim.provenance == CognitiveClaimProvenance.memoryEpisode &&
            claim.predicate == 'selectedModel',
      );
      expect(remembered, hasLength(1));
      expect(
        remembered.single.lifecycle,
        CognitiveLifecycleState.contradicted,
      );
      expect(
        remembered.single.epistemicStatus,
        CognitiveEpistemicStatus.conflicting,
      );

      // Ordinary lookup returns current truth only.
      final looked = enrichment.lookup(snapshot, 'selectedModel');
      expect(looked, isNotEmpty);
      expect(
        looked.every(
          (claim) => claim.lifecycle != CognitiveLifecycleState.contradicted,
        ),
        isTrue,
      );
      expect(
        looked
            .firstWhere((claim) => claim.predicate == 'selectedModel')
            .provenance,
        CognitiveClaimProvenance.runtimeObservation,
      );
      expect(snapshot.conflicts, isNotEmpty);
      expect(
        snapshot.uncertainty
            .any((item) => item.status == CognitiveEpistemicStatus.conflicting),
        isTrue,
      );
    });

    test('capability availability, health and authority share live keys',
        () async {
      final enrichment = _enrichment();
      final substrate = buildTestSubstrate(
        self: testSelf(
          capabilities: <KnownCapability>[
            testCapability(
              'browser.session',
              state: CapabilityAvailabilityState.unavailable,
              health: CapabilityHealthState.failing,
              authority: AuthorityObservationState.notEvaluated,
            ),
          ],
        ),
      );
      final episode = testEpisode(id: 'episode-old');
      final snapshot = enrichment.enrichSnapshot(
        await substrate.snapshot(),
        factsByEpisodeId: <String, List<CognitiveMemoryFactAtom>>{
          'episode-old': <CognitiveMemoryFactAtom>[
            _atom(
              episodeId: 'episode-old',
              subject: 'capability:browser.session',
              predicate: 'availability',
              value: 'available',
              scope: CognitiveClaimScope.project,
            ),
            _atom(
              episodeId: 'episode-old',
              subject: 'capability:browser.session',
              predicate: 'health',
              value: 'healthy',
              scope: CognitiveClaimScope.project,
            ),
            _atom(
              episodeId: 'episode-old',
              subject: 'capability:browser.session',
              predicate: 'authority',
              value: 'granted',
              scope: CognitiveClaimScope.project,
            ),
          ],
        },
        episodesById: <String, MemoryEpisode>{'episode-old': episode},
      );

      for (final predicate in <String>['availability', 'health', 'authority']) {
        final key = 'capability|capability:browser.session|$predicate';
        final group =
            snapshot.claims.where((claim) => claim.resolutionKey == key);
        expect(
          group.length,
          2,
          reason: 'memory and live state must collide on $key',
        );
        final current = group.where(
          (claim) =>
              claim.lifecycle == CognitiveLifecycleState.valid ||
              claim.lifecycle == CognitiveLifecycleState.stale,
        );
        expect(current, hasLength(1));
        expect(
          current.single.provenance,
          CognitiveClaimProvenance.runtimeObservation,
          reason: 'a remembered $predicate must never become current truth',
        );
      }
      expect(
        snapshot.conflicts.map((conflict) => conflict.key),
        containsAll(<String>[
          'capability|capability:browser.session|availability',
          'capability|capability:browser.session|health',
          'capability|capability:browser.session|authority',
        ]),
      );
    });

    test('application product-state memory normalizes onto live keys',
        () async {
      final enrichment = _enrichment();
      final substrate = buildTestSubstrate(
        self: testSelf(
          application: testApplication(
            selectedProject: <String, Object?>{'id': 'project-1'},
            selectedModel: <String, Object?>{'exactId': 'ollama/qwen3'},
            providers: <Map<String, Object?>>[
              <String, Object?>{'id': 'ollama', 'reachable': true},
            ],
            runState: <String, Object?>{'active': false},
            browser: <String, Object?>{'sessions': 0},
            ownerMode: <String, Object?>{'entered': false},
            authority: <String, Object?>{'ownerMode': 'not_evaluated'},
          ),
        ),
      );
      final episode = testEpisode(id: 'episode-old');
      const predicates = <String>[
        'selectedProject',
        'selectedModel',
        'providers',
        'runState',
        'browser',
        'ownerMode',
        'authority',
      ];
      final snapshot = enrichment.enrichSnapshot(
        await substrate.snapshot(),
        factsByEpisodeId: <String, List<CognitiveMemoryFactAtom>>{
          'episode-old': <CognitiveMemoryFactAtom>[
            for (final predicate in predicates)
              _atom(
                episodeId: 'episode-old',
                // The atomizer chose a project-scoped entity key; the runtime
                // must still canonicalize a live product field.
                subject: 'entity:kris_ai',
                predicate: predicate,
                value: 'remembered-$predicate',
                scope: CognitiveClaimScope.project,
              ),
          ],
        },
        episodesById: <String, MemoryEpisode>{'episode-old': episode},
      );

      for (final predicate in predicates) {
        final key = 'application|application|$predicate';
        final group =
            snapshot.claims.where((claim) => claim.resolutionKey == key);
        expect(group.length, 2, reason: 'memory must normalize onto $key');
        final current = group.where(
          (claim) =>
              claim.lifecycle == CognitiveLifecycleState.valid ||
              claim.lifecycle == CognitiveLifecycleState.stale,
        );
        expect(current, hasLength(1));
        expect(
          current.single.provenance,
          CognitiveClaimProvenance.runtimeObservation,
        );
      }
    });

    test('an expired preferred claim degrades to stale instead of certainty',
        () {
      final resolution = policy.resolve(
        <CognitiveClaim>[
          CognitiveClaim(
            subject: 'application',
            predicate: 'browser',
            value: <String, Object?>{'sessions': 2},
            scope: CognitiveClaimScope.application,
            provenance: CognitiveClaimProvenance.runtimeObservation,
            epistemicStatus: CognitiveEpistemicStatus.observed,
            confidence: ObservationConfidence.high,
            createdAt: DateTime.utc(2026, 1, 1),
            observedAt: DateTime.utc(2026, 1, 1),
            expiresAt: DateTime.utc(2026, 1, 2),
          ),
        ],
        now: testNow,
      );
      expect(
        resolution.claims.single.lifecycle,
        CognitiveLifecycleState.stale,
      );
      expect(
        resolution.claims.single.epistemicStatus,
        CognitiveEpistemicStatus.stale,
      );
    });
  });
}
