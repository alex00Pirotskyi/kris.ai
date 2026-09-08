// Behavioural proof for the rebuildable semantic index over historical memory.
//
// MemoryEpisode stays the source of truth. This index is derived enrichment:
// it may be rebuilt, invalidated, or fail entirely, and canonical memory must
// survive all three. It must also never become a second memory database
// holding raw historical prose or unredacted secrets.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/cognitive/cognitive_model.dart';
import 'package:kristin_local_agent/product/cognitive/memory_fact_index.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/self_awareness/capability_self_model.dart';

import 'cognitive_test_support.dart';

/// A scripted atomizer. Each call returns the next queued response so a test
/// can prove exactly how many model calls a cache decision caused.
class _ScriptedAtomizer {
  _ScriptedAtomizer(this.responses);

  final List<String> responses;
  final List<ModelGenerationRequest> requests = <ModelGenerationRequest>[];
  Object? failWith;

  Future<ModelGenerationResult> call(ModelGenerationRequest request) async {
    requests.add(request);
    final failure = failWith;
    if (failure != null) throw failure;
    final index = requests.length - 1;
    final text = index < responses.length ? responses[index] : responses.last;
    return testModelResult(text, request.identity);
  }
}

String _facts(List<Map<String, Object?>> facts) =>
    jsonEncode(<String, Object?>{'facts': facts});

Directory _cacheDir(String name) =>
    Directory.systemTemp.createTempSync('kristin-facts-$name-');

File _cacheFile(Directory directory) =>
    File('${directory.path}${Platform.pathSeparator}'
        'cognitive-memory-facts-v1.json');

void main() {
  group('memory fact atomization', () {
    late Directory cache;

    setUp(() => cache = _cacheDir('base'));
    tearDown(() {
      if (cache.existsSync()) cache.deleteSync(recursive: true);
    });

    test('atomized facts keep memoryEpisode provenance and episode evidence',
        () async {
      final atomizer = _ScriptedAtomizer(<String>[
        _facts(<Map<String, Object?>>[
          <String, Object?>{
            'subject': 'project',
            'predicate': 'framework',
            'value': 'Flutter',
            'scope': 'project',
            'confidence': 'high',
          },
        ]),
      ]);
      final index = CognitiveMemoryFactIndex(
        cacheDirectory: cache,
        generate: atomizer.call,
      );
      final episode = testEpisode(id: 'episode-1');
      final batch = await index.ensure(
        episodes: <MemoryEpisode>[episode],
        model: testModel(),
      );

      final atoms = batch.byEpisodeId['episode-1']!;
      expect(atoms, hasLength(1));
      expect(atoms.single.subject, 'project:project-1');
      expect(atoms.single.predicate, 'framework');

      final claim = atoms.single.toClaim(episode);
      expect(claim.provenance, CognitiveClaimProvenance.memoryEpisode);
      expect(claim.epistemicStatus, CognitiveEpistemicStatus.remembered);
      expect(
        claim.evidence.single.source,
        'MemoryFactIndex:episode-1',
      );
      expect(claim.evidence.single.detail, contains('sourceHash='));
      expect(
        claim.evidence.single.detail,
        contains('episodeContentHash=content-episode-1'),
      );
      expect(claim.tags, contains('memory:episode:episode-1'));
    });

    test('atomization can never produce a certain claim', () async {
      final atomizer = _ScriptedAtomizer(<String>[
        _facts(<Map<String, Object?>>[
          <String, Object?>{
            'subject': 'project',
            'predicate': 'framework',
            'value': 'Flutter',
            'scope': 'project',
            // A model that ignores the schema and asserts certainty.
            'confidence': 'certain',
          },
        ]),
      ]);
      final index = CognitiveMemoryFactIndex(
        cacheDirectory: cache,
        generate: atomizer.call,
      );
      final episode = testEpisode(id: 'episode-1');
      final batch = await index.ensure(
        episodes: <MemoryEpisode>[episode],
        model: testModel(),
      );
      final atom = batch.byEpisodeId['episode-1']!.single;
      expect(atom.confidence, ObservationConfidence.low);
      expect(
        atom.toClaim(episode).confidence,
        isNot(ObservationConfidence.certain),
      );

      // A diagnostic episode weakens it further, whatever the model said.
      final diagnostic = testEpisode(
        id: 'episode-1',
        diagnosticOnly: true,
        admission: 'quarantined',
      );
      expect(atom.toClaim(diagnostic).confidence, ObservationConfidence.low);
      expect(atom.toClaim(diagnostic).tags, contains('memory:diagnostic'));
    });

    test('an unchanged episode is served from cache without a model call',
        () async {
      final atomizer = _ScriptedAtomizer(<String>[
        _facts(<Map<String, Object?>>[
          <String, Object?>{
            'subject': 'project',
            'predicate': 'framework',
            'value': 'Flutter',
            'scope': 'project',
            'confidence': 'high',
          },
        ]),
      ]);
      final episode = testEpisode(id: 'episode-1');
      final first = CognitiveMemoryFactIndex(
        cacheDirectory: cache,
        generate: atomizer.call,
      );
      await first.ensure(
        episodes: <MemoryEpisode>[episode],
        model: testModel(),
      );
      expect(atomizer.requests, hasLength(1));

      final second = CognitiveMemoryFactIndex(
        cacheDirectory: cache,
        generate: atomizer.call,
      );
      final batch = await second.ensure(
        episodes: <MemoryEpisode>[episode],
        model: testModel(),
      );
      expect(atomizer.requests, hasLength(1));
      expect(batch.byEpisodeId['episode-1'], hasLength(1));
      expect(batch.atomizedEpisodeIds, isEmpty);
    });

    test('a changed episode content hash invalidates the cached entry',
        () async {
      final atomizer = _ScriptedAtomizer(<String>[
        _facts(<Map<String, Object?>>[
          <String, Object?>{
            'subject': 'project',
            'predicate': 'framework',
            'value': 'Flutter',
            'scope': 'project',
            'confidence': 'high',
          },
        ]),
        _facts(<Map<String, Object?>>[
          <String, Object?>{
            'subject': 'project',
            'predicate': 'framework',
            'value': 'Flutter 4',
            'scope': 'project',
            'confidence': 'high',
          },
        ]),
      ]);
      final index = CognitiveMemoryFactIndex(
        cacheDirectory: cache,
        generate: atomizer.call,
      );
      await index.ensure(
        episodes: <MemoryEpisode>[
          testEpisode(id: 'episode-1', contentHash: 'v1'),
        ],
        model: testModel(),
      );
      final batch = await index.ensure(
        episodes: <MemoryEpisode>[
          testEpisode(id: 'episode-1', contentHash: 'v2'),
        ],
        model: testModel(),
      );
      expect(atomizer.requests, hasLength(2));
      expect(batch.byEpisodeId['episode-1']!.single.value, 'Flutter 4');
      expect(
        batch.byEpisodeId['episode-1']!.single.episodeContentHash,
        'v2',
      );
    });

    test('a stale atomizer version invalidates a persisted entry', () async {
      _cacheFile(cache).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'atomizerVersion': 'memory_fact_atomizer_v0',
          'entries': <Object?>[
            <String, Object?>{
              'episodeId': 'episode-1',
              'projectId': 'project-1',
              'episodeContentHash': 'content-episode-1',
              'sourceHash': 'old',
              'atomizerVersion': 'memory_fact_atomizer_v0',
              'modelExactId': 'ollama/old',
              'extractedAt': testNow.toIso8601String(),
              'facts': <Object?>[
                <String, Object?>{
                  'episodeId': 'episode-1',
                  'projectId': 'project-1',
                  'subject': 'project:project-1',
                  'predicate': 'framework',
                  'value': 'Stale answer',
                  'scope': 'project',
                  'confidence': 'high',
                  'sourceHash': 'old',
                  'episodeContentHash': 'content-episode-1',
                  'atomizerVersion': 'memory_fact_atomizer_v0',
                  'modelExactId': 'ollama/old',
                  'extractedAt': testNow.toIso8601String(),
                },
              ],
            },
          ],
        }),
      );

      final atomizer = _ScriptedAtomizer(<String>[
        _facts(<Map<String, Object?>>[
          <String, Object?>{
            'subject': 'project',
            'predicate': 'framework',
            'value': 'Flutter',
            'scope': 'project',
            'confidence': 'high',
          },
        ]),
      ]);
      final index = CognitiveMemoryFactIndex(
        cacheDirectory: cache,
        generate: atomizer.call,
      );
      final batch = await index.ensure(
        episodes: <MemoryEpisode>[testEpisode(id: 'episode-1')],
        model: testModel(),
      );
      expect(atomizer.requests, hasLength(1));
      expect(batch.byEpisodeId['episode-1']!.single.value, 'Flutter');
      expect(
        batch.byEpisodeId['episode-1']!.single.atomizerVersion,
        kCognitiveMemoryFactAtomizerVersion,
      );
    });

    test('a corrupt cache fails open and rebuilds', () async {
      _cacheFile(cache).writeAsStringSync('{ this is not json');
      final failures = <String>[];
      final atomizer = _ScriptedAtomizer(<String>[
        _facts(<Map<String, Object?>>[
          <String, Object?>{
            'subject': 'project',
            'predicate': 'framework',
            'value': 'Flutter',
            'scope': 'project',
            'confidence': 'high',
          },
        ]),
      ]);
      final index = CognitiveMemoryFactIndex(
        cacheDirectory: cache,
        generate: atomizer.call,
        onFailure: (String stage, String episodeId, Object error) async {
          failures.add(stage);
        },
      );
      final batch = await index.ensure(
        episodes: <MemoryEpisode>[testEpisode(id: 'episode-1')],
        model: testModel(),
      );
      expect(failures, contains('cache_load'));
      expect(batch.byEpisodeId['episode-1'], hasLength(1));
    });

    test('a missing cache fails open', () async {
      final missing = Directory(
        '${cache.path}${Platform.pathSeparator}not-created-yet',
      );
      final atomizer = _ScriptedAtomizer(<String>[
        _facts(<Map<String, Object?>>[
          <String, Object?>{
            'subject': 'project',
            'predicate': 'framework',
            'value': 'Flutter',
            'scope': 'project',
            'confidence': 'high',
          },
        ]),
      ]);
      final index = CognitiveMemoryFactIndex(
        cacheDirectory: missing,
        generate: atomizer.call,
      );
      final batch = await index.ensure(
        episodes: <MemoryEpisode>[testEpisode(id: 'episode-1')],
        model: testModel(),
      );
      expect(batch.byEpisodeId['episode-1'], hasLength(1));
    });

    test('a provider failure fails open and is retryable', () async {
      final failures = <List<String>>[];
      final atomizer = _ScriptedAtomizer(<String>[
        _facts(<Map<String, Object?>>[
          <String, Object?>{
            'subject': 'project',
            'predicate': 'framework',
            'value': 'Flutter',
            'scope': 'project',
            'confidence': 'high',
          },
        ]),
      ])
        ..failWith = StateError('model provider is offline');
      final index = CognitiveMemoryFactIndex(
        cacheDirectory: cache,
        generate: atomizer.call,
        onFailure: (String stage, String episodeId, Object error) async {
          failures.add(<String>[stage, episodeId]);
        },
      );
      final episode = testEpisode(id: 'episode-1');
      final failed = await index.ensure(
        episodes: <MemoryEpisode>[episode],
        model: testModel(),
      );
      expect(failed.byEpisodeId, isEmpty);
      expect(failures.single, <String>['atomize', 'episode-1']);
      // Nothing was cached as a successful empty atomization, so a healthy
      // provider can still produce facts for the same episode later.
      expect(_cacheFile(cache).existsSync(), isFalse);

      atomizer.failWith = null;
      final recovered = await index.ensure(
        episodes: <MemoryEpisode>[episode],
        model: testModel(),
      );
      expect(recovered.byEpisodeId['episode-1'], hasLength(1));
    });

    test('a cache write failure does not suppress the derived facts', () async {
      final blocked = File('${cache.path}${Platform.pathSeparator}blocked')
        ..writeAsStringSync('not a directory');
      final failures = <String>[];
      final atomizer = _ScriptedAtomizer(<String>[
        _facts(<Map<String, Object?>>[
          <String, Object?>{
            'subject': 'project',
            'predicate': 'framework',
            'value': 'Flutter',
            'scope': 'project',
            'confidence': 'high',
          },
        ]),
      ]);
      final index = CognitiveMemoryFactIndex(
        cacheDirectory: Directory(blocked.path),
        generate: atomizer.call,
        onFailure: (String stage, String episodeId, Object error) async {
          failures.add(stage);
        },
      );
      final batch = await index.ensure(
        episodes: <MemoryEpisode>[testEpisode(id: 'episode-1')],
        model: testModel(),
      );
      expect(failures, contains('cache_write'));
      expect(batch.byEpisodeId['episode-1'], hasLength(1));
    });

    test('raw historical prose is never persisted in the semantic cache',
        () async {
      const prose = 'The operator manually patched the staging deployment '
          'and then rewrote the release notes by hand.';
      final atomizer = _ScriptedAtomizer(<String>[
        _facts(<Map<String, Object?>>[
          <String, Object?>{
            'subject': 'project',
            'predicate': 'framework',
            'value': 'Flutter',
            'scope': 'project',
            'confidence': 'high',
          },
        ]),
      ]);
      final index = CognitiveMemoryFactIndex(
        cacheDirectory: cache,
        generate: atomizer.call,
      );
      await index.ensure(
        episodes: <MemoryEpisode>[
          testEpisode(
            id: 'episode-1',
            request: prose,
            summary: prose,
            lessons: prose,
          ),
        ],
        model: testModel(),
      );

      final persisted = _cacheFile(cache).readAsStringSync();
      expect(persisted, isNot(contains('manually patched')));
      expect(persisted, isNot(contains('release notes')));
      expect(persisted, contains('episodeContentHash'));
      expect(persisted, contains('sourceHash'));
    });

    test('secrets are redacted before the model and before persistence',
        () async {
      // Composed at run time so the repository never stores a literal that
      // looks like a live provider credential, while the redactor still sees
      // a recognizable one.
      final fakeProviderKey = 'sk-${'abcdefgh' * 4}';
      final atomizer = _ScriptedAtomizer(<String>[
        _facts(<Map<String, Object?>>[
          <String, Object?>{
            'subject': 'service:deploy',
            'predicate': 'configuration',
            'value': 'api_key=$fakeProviderKey',
            'scope': 'project',
            'confidence': 'high',
          },
        ]),
      ]);
      final index = CognitiveMemoryFactIndex(
        cacheDirectory: cache,
        generate: atomizer.call,
      );
      final batch = await index.ensure(
        episodes: <MemoryEpisode>[
          testEpisode(
            id: 'episode-1',
            summary: 'Deployment used api_key=$fakeProviderKey to publish.',
          ),
        ],
        model: testModel(),
      );

      final prompt = atomizer.requests.single.userPrompt;
      expect(prompt, isNot(contains(fakeProviderKey)));
      expect(prompt, contains('[REDACTED]'));

      final value = batch.byEpisodeId['episode-1']!.single.value.toString();
      expect(value, isNot(contains(fakeProviderKey)));
      expect(value, contains('[REDACTED]'));
      expect(
        _cacheFile(cache).readAsStringSync(),
        isNot(contains(fakeProviderKey)),
      );
    });

    test('equivalent duplicate facts normalize to one atom', () async {
      final atomizer = _ScriptedAtomizer(<String>[
        _facts(<Map<String, Object?>>[
          <String, Object?>{
            'subject': 'Current Project',
            'predicate': 'framework',
            'value': 'Flutter',
            'scope': 'project',
            'confidence': 'high',
          },
          <String, Object?>{
            'subject': 'project',
            'predicate': 'Framework',
            'value': 'Flutter',
            'scope': 'project',
            'confidence': 'medium',
          },
          <String, Object?>{
            'subject': 'project',
            'predicate': 'selected_project',
            'value': 'kris.ai',
            'scope': 'application',
            'confidence': 'high',
          },
          <String, Object?>{
            'subject': '   ',
            'predicate': 'ignored',
            'value': 'dropped',
            'scope': 'project',
            'confidence': 'high',
          },
          <String, Object?>{
            'subject': 'project',
            'predicate': 'blank_value',
            'value': '   ',
            'scope': 'project',
            'confidence': 'high',
          },
        ]),
      ]);
      final index = CognitiveMemoryFactIndex(
        cacheDirectory: cache,
        generate: atomizer.call,
      );
      final batch = await index.ensure(
        episodes: <MemoryEpisode>[testEpisode(id: 'episode-1')],
        model: testModel(),
      );
      final atoms = batch.byEpisodeId['episode-1']!;
      expect(
        atoms.map((atom) => '${atom.subject}.${atom.predicate}').toList(),
        <String>[
          'project:project-1.framework',
          'project:project-1.selectedProject',
        ],
      );
    });
  });
}
