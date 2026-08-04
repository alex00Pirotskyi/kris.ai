import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

void main() {
  late Directory temporary;
  late PersistentCollection<KnowledgeEntry> knowledge;
  late PersistentCollection<ResearchArchiveRecord> archives;
  late PersistentCollection<MemoryEpisode> episodes;
  late KnowledgeService service;

  setUp(() async {
    temporary =
        await Directory.systemTemp.createTemp('kristin-knowledge-test-');
    knowledge = PersistentCollection<KnowledgeEntry>(
      file: File('${temporary.path}/state/knowledge.json'),
      fromJson: KnowledgeEntry.fromJson,
      toJson: (item) => item.toJson(),
      idOf: (item) => item.id,
    );
    archives = PersistentCollection<ResearchArchiveRecord>(
      file: File('${temporary.path}/state/research_archive.json'),
      fromJson: ResearchArchiveRecord.fromJson,
      toJson: (item) => item.toJson(),
      idOf: (item) => item.id,
    );
    episodes = PersistentCollection<MemoryEpisode>(
      file: File('${temporary.path}/state/memory_episodes.json'),
      fromJson: MemoryEpisode.fromJson,
      toJson: (item) => item.toJson(),
      idOf: (item) => item.id,
    );
    service = KnowledgeService(
      knowledge,
      archiveRepository: archives,
      episodeRepository: episodes,
      archiveDirectory: Directory('${temporary.path}/research-archive'),
      indexDirectory: Directory('${temporary.path}/cache/knowledge-index'),
      exportDirectory: Directory('${temporary.path}/exports'),
    );
    await service.initialize();
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('knowledge list is project scoped and newest first', () async {
    final older = DateTime.utc(2026, 7, 14, 8);
    final newer = DateTime.utc(2026, 7, 15, 8);
    await knowledge.put(
      KnowledgeEntry(
        id: 'older-a',
        projectId: 'project-a',
        title: 'Older A',
        content: 'Older project A knowledge.',
        tags: const <String>{'test'},
        sourceUrl: '',
        contentHash: Sha256.text('Older project A knowledge.'),
        createdAt: older,
        updatedAt: older,
      ),
    );
    await knowledge.put(
      KnowledgeEntry(
        id: 'other-project',
        projectId: 'project-b',
        title: 'Project B',
        content: 'Knowledge from another project.',
        tags: const <String>{'test'},
        sourceUrl: '',
        contentHash: Sha256.text('Knowledge from another project.'),
        createdAt: newer,
        updatedAt: newer,
      ),
    );
    await knowledge.put(
      KnowledgeEntry(
        id: 'newer-a',
        projectId: 'project-a',
        title: 'Newer A',
        content: 'Newer project A knowledge.',
        tags: const <String>{'test'},
        sourceUrl: '',
        contentHash: Sha256.text('Newer project A knowledge.'),
        createdAt: newer,
        updatedAt: newer,
      ),
    );

    final listed = await service.list('project-a');
    expect(listed.map((entry) => entry.id), <String>['newer-a', 'older-a']);
  });

  test('research is archived with immutable provenance and cited retrieval',
      () async {
    const extracted =
        'Kristin stores fetched research locally and retrieves cited passages.';
    final note = await service.addNote(
      projectId: 'project-a',
      title: 'Product requirement',
      content: 'Every answer that uses research must expose a citation marker.',
      tags: const <String>{'citations', 'requirements'},
    );
    final source = await service.addResearch(
      'project-a',
      ResearchSource(
        id: 'source-1',
        requestedUrl: Uri.parse('https://example.com/start'),
        url: Uri.parse('https://example.com/final'),
        title: 'Research archive design',
        mimeType: 'text/html',
        contentHash: Sha256.text(extracted),
        fetchedAt: DateTime.utc(2026, 7, 15, 12),
        content: extracted,
        rawContent: '<html><body>$extracted</body></html>',
        statusCode: 200,
        responseHeaders: const <String, String>{
          'content-type': 'text/html',
        },
        redirectChain: const <String>[
          'https://example.com/start',
          'https://example.com/final',
        ],
      ),
    );
    await service.addResearchSearch(
      projectId: 'project-a',
      query: 'local cited retrieval',
      provider: 'test-provider',
      results: const <Map<String, String>>[
        <String, String>{
          'title': 'Local knowledge',
          'url': 'https://example.com/knowledge',
          'snippet': 'A cited retrieval result.',
        },
      ],
    );

    final records = await service.listArchives('project-a');
    expect(records, hasLength(2));
    expect(records.first.knowledgeId, isNotEmpty);
    expect(records.any((record) => record.requestedUrl.endsWith('/start')),
        isTrue);
    for (final record in records) {
      expect(record.contentHash, isNotEmpty);
      expect(record.rawObjectPath, isNotEmpty);
      final object = File(
        '${temporary.path}/research-archive/'
        '${record.rawObjectPath.replaceAll('/', Platform.pathSeparator)}',
      );
      expect(await object.exists(), isTrue, reason: object.path);
    }

    final retrieval = await service.retrieve(
      'project-a',
      'research citation archive',
      includeEpisodes: false,
    );
    expect(retrieval.hits, isNotEmpty);
    expect(retrieval.hits.first.citation, 'K1');
    expect(retrieval.hits.map((hit) => hit.title), contains(source.title));
    expect(retrieval.hits.map((hit) => hit.title), contains(note.title));
    final context = service.buildCitedContext(retrieval);
    expect(context, contains('[K1]'));
    expect(context, contains('CITATION RULE'));
    expect(context, contains('UNTRUSTED EXTERNAL REFERENCE'));
  });

  test('run memory participates in retrieval and portable export', () async {
    final completed = DateTime.utc(2026, 7, 15, 13);
    final episode = MemoryEpisode(
      id: 'episode-1',
      projectId: 'project-b',
      runId: 'run-1',
      request: 'Repair the project test command',
      mode: CommandMode.fix,
      outcome: RunState.succeeded,
      summary: 'Updated the project profile and the quick test passed.',
      failure: '',
      lessons: 'Use the detected project profile before invoking tests.',
      tags: const <String>{'episode', 'tests', 'succeeded'},
      completedItems: const <String>['Detect project', 'Run quick tests'],
      failedItems: const <String>[],
      filesChanged: const <String>['kristin.project.json'],
      evidenceIds: const <String>['evidence-1'],
      evidenceHashes: const <String>['abc123'],
      startedAt: completed.subtract(const Duration(minutes: 2)),
      completedAt: completed,
      modelRequests: 1,
      toolCalls: 3,
      mutations: 1,
      repairs: 0,
      contentHash: Sha256.text('episode-1-content'),
      createdAt: completed,
    );
    await episodes.put(episode);
    await service.addNote(
      projectId: 'project-b',
      title: 'Testing policy',
      content: 'Run the quick test before the full project command.',
    );

    final retrieval = await service.retrieve(
      'project-b',
      'project test command profile',
    );
    expect(retrieval.hits, isNotEmpty);
    expect(
      retrieval.hits.any((hit) => hit.kind == KnowledgeKind.episode),
      isTrue,
    );
    expect(
      retrieval.hits
          .where((hit) => hit.kind == KnowledgeKind.episode)
          .first
          .episodeId,
      episode.id,
    );

    final stats = await service.stats('project-b');
    expect(stats.notes, 1);
    expect(stats.episodes, 1);
    expect(stats.indexedChunks, greaterThanOrEqualTo(2));

    final exported = await service.exportPackage('project-b');
    expect(await exported.exists(), isTrue);
    final bytes = await exported.readAsBytes();
    expect(bytes.take(2).toList(), <int>[0x50, 0x4b]);
  });

  test('automatic retrieval excludes unsuccessful run episodes', () async {
    final captured = DateTime.utc(2026, 7, 16, 9);
    final failed = MemoryEpisode(
      id: 'failed-hello',
      projectId: 'project-memory-policy',
      runId: 'run-failed',
      request: 'hello',
      mode: CommandMode.ask,
      outcome: RunState.failed,
      summary: '',
      failure: 'model_action_invalid: The model returned an invalid action.',
      lessons: 'model_action_invalid: The model returned an invalid action.\n'
          'Failed work: Inspect project and establish evidence baseline.',
      tags: const <String>{'episode', 'ask', 'failed', 'hello'},
      completedItems: const <String>[],
      failedItems: const <String>[
        'Inspect project and establish evidence baseline: invalid action',
      ],
      filesChanged: const <String>[],
      evidenceIds: const <String>[],
      evidenceHashes: const <String>[],
      startedAt: captured.subtract(const Duration(minutes: 1)),
      completedAt: captured,
      modelRequests: 2,
      toolCalls: 0,
      mutations: 0,
      repairs: 1,
      contentHash: Sha256.text('failed-hello'),
      createdAt: captured,
    );
    final succeeded = MemoryEpisode(
      id: 'successful-hello',
      projectId: 'project-memory-policy',
      runId: 'run-succeeded',
      request: 'hello project overview',
      mode: CommandMode.ask,
      outcome: RunState.succeeded,
      summary: 'Provided a concise project overview.',
      failure: '',
      lessons: 'Use project evidence only when the request depends on it.',
      tags: const <String>{'episode', 'ask', 'succeeded', 'hello'},
      completedItems: const <String>['Answer from grounded context'],
      failedItems: const <String>[],
      filesChanged: const <String>[],
      evidenceIds: const <String>[],
      evidenceHashes: const <String>[],
      startedAt: captured.subtract(const Duration(minutes: 2)),
      completedAt: captured.subtract(const Duration(minutes: 1)),
      modelRequests: 1,
      toolCalls: 0,
      mutations: 0,
      repairs: 0,
      contentHash: Sha256.text('successful-hello'),
      createdAt: captured.subtract(const Duration(minutes: 1)),
    );
    await episodes.put(failed);
    await episodes.put(succeeded);

    final automatic = await service.retrieve(
      'project-memory-policy',
      'hello',
      includeUnsuccessfulEpisodes: false,
    );
    expect(
      automatic.hits.map((hit) => hit.episodeId),
      isNot(contains(failed.id)),
    );
    expect(
      automatic.hits.map((hit) => hit.episodeId),
      contains(succeeded.id),
    );

    final diagnosticWithoutOptIn = await service.retrieve(
      'project-memory-policy',
      'debug previous failed hello run',
    );
    expect(
      diagnosticWithoutOptIn.hits.map((hit) => hit.episodeId),
      isNot(contains(failed.id)),
    );

    final applicationRequest = await service.retrieve(
      'project-memory-policy',
      'calculator history view, input validation, and error handling',
    );
    expect(
      applicationRequest.hits.map((hit) => hit.episodeId),
      isNot(contains(failed.id)),
    );

    final diagnostic = await service.retrieve(
      'project-memory-policy',
      'debug previous failed hello run',
      includeUnsuccessfulEpisodes: true,
    );
    expect(
      diagnostic.hits.map((hit) => hit.episodeId),
      contains(failed.id),
    );
    final failedHit = diagnostic.hits.firstWhere(
      (hit) => hit.episodeId == failed.id,
    );
    expect(
      RegExp('Failed work:').allMatches(failedHit.snippet),
      hasLength(1),
    );
  });

  test('automatic context excludes unsuccessful and conversational episodes',
      () async {
    final now = DateTime.utc(2026, 7, 16, 9);

    MemoryEpisode makeEpisode({
      required String id,
      required String request,
      required RunState outcome,
      required String summary,
      String failure = '',
      List<String> failedItems = const <String>[],
    }) {
      return MemoryEpisode(
        id: id,
        projectId: 'project-memory-filter',
        runId: 'run-$id',
        request: request,
        mode:
            outcome == RunState.succeeded ? CommandMode.build : CommandMode.fix,
        outcome: outcome,
        summary: summary,
        failure: failure,
        lessons: failure,
        tags: <String>{'episode', outcome.name},
        completedItems: outcome == RunState.succeeded
            ? const <String>['Create baseline']
            : const <String>[],
        failedItems: failedItems,
        filesChanged: const <String>[],
        evidenceIds: const <String>[],
        evidenceHashes: const <String>[],
        startedAt: now.subtract(const Duration(minutes: 1)),
        completedAt: now,
        modelRequests: 1,
        toolCalls: 0,
        mutations: 0,
        repairs: 0,
        contentHash: Sha256.text('$id-$request-$outcome-$summary-$failure'),
        createdAt: now,
      );
    }

    await episodes.put(makeEpisode(
      id: 'successful',
      request: 'Create the project evidence baseline',
      outcome: RunState.succeeded,
      summary: 'The project evidence baseline was created successfully.',
    ));
    await episodes.put(makeEpisode(
      id: 'failed',
      request: 'Create the project evidence baseline',
      outcome: RunState.failed,
      summary: '',
      failure: 'model_action_invalid: response schema was invalid.',
      failedItems: const <String>[
        'Inspect project and establish evidence baseline: invalid response',
      ],
    ));
    await episodes.put(makeEpisode(
      id: 'greeting',
      request: 'hello',
      outcome: RunState.succeeded,
      summary: 'Hello!',
    ));

    final automatic = await service.retrieve(
      'project-memory-filter',
      'project evidence baseline',
      includeEpisodes: true,
      includeUnsuccessfulEpisodes: false,
    );
    expect(
      automatic.hits.map((hit) => hit.episodeId),
      contains('successful'),
    );
    expect(
      automatic.hits.map((hit) => hit.episodeId),
      isNot(contains('failed')),
    );

    final diagnostic = await service.retrieve(
      'project-memory-filter',
      'invalid response schema failed work',
      includeEpisodes: true,
      includeUnsuccessfulEpisodes: true,
    );
    final failedHit = diagnostic.hits.firstWhere(
      (hit) => hit.episodeId == 'failed',
    );
    expect(RegExp(r'Failed work:').allMatches(failedHit.snippet), hasLength(1));

    final greetingSearch = await service.retrieve(
      'project-memory-filter',
      'hello',
      includeEpisodes: true,
      includeUnsuccessfulEpisodes: true,
    );
    expect(
      greetingSearch.hits.map((hit) => hit.episodeId),
      isNot(contains('greeting')),
    );
  });

  test('v0.8 archive files migrate idempotently and repair missing entries',
      () async {
    const projectId = 'project-c';
    const sourceText =
        'The legacy archive contains a durable project research finding.';
    final sourceHash = Sha256.text(sourceText);
    final legacyDirectory =
        Directory('${temporary.path}/research-archive/$projectId');
    await legacyDirectory.create(recursive: true);
    final source = ResearchSource(
      id: 'legacy-source',
      requestedUrl: Uri.parse('https://example.com/requested'),
      url: Uri.parse('https://example.com/final'),
      title: 'Legacy source',
      mimeType: 'text/plain',
      contentHash: sourceHash,
      fetchedAt: DateTime.utc(2026, 7, 14, 8),
      content: sourceText,
      rawContent: sourceText,
      statusCode: 200,
      responseHeaders: const <String, String>{
        'content-type': 'text/plain',
      },
      redirectChain: const <String>[
        'https://example.com/requested',
        'https://example.com/final',
      ],
    );
    await File('${legacyDirectory.path}/$sourceHash.source.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'kind': 'research_source',
        'projectId': projectId,
        'capturedAt': '2026-07-14T08:00:00.000Z',
        'source': source.toJson(),
      }),
      flush: true,
    );

    final searchWrapper = <String, dynamic>{
      'kind': 'research_search',
      'projectId': projectId,
      'provider': 'legacy-provider',
      'query': 'durable local archive',
      'capturedAt': '2026-07-14T08:05:00.000Z',
      'results': const <Map<String, String>>[
        <String, String>{
          'title': 'Archived search result',
          'url': 'https://example.com/result',
          'snippet': 'A legacy search snapshot.',
        },
      ],
    };
    final searchContent =
        const JsonEncoder.withIndent('  ').convert(searchWrapper);
    final searchHash = Sha256.text(searchContent);
    await File('${legacyDirectory.path}/$searchHash.search.json')
        .writeAsString(searchContent, flush: true);

    await service.initialize();
    await service.initialize();

    final migratedArchives = await service.listArchives(projectId);
    final migratedKnowledge = await service.list(projectId);
    expect(migratedArchives, hasLength(2));
    expect(migratedKnowledge, hasLength(2));
    expect(
      migratedArchives.map((record) => record.provider),
      containsAll(<String>{'legacy-v0.8-source-file', 'legacy-provider'}),
    );
    expect(
      migratedKnowledge.every((entry) => entry.tags.contains('migrated-v0.8')),
      isTrue,
    );
    expect(
      migratedKnowledge.every((entry) => entry.archiveId.isNotEmpty),
      isTrue,
    );

    final removed = migratedKnowledge.first;
    await knowledge.remove(removed.id);
    expect(await knowledge.get(removed.id), isNull);
    await service.initialize();

    expect(await service.listArchives(projectId), hasLength(2));
    expect(await service.list(projectId), hasLength(2));
    expect(await knowledge.get(removed.id), isNotNull);
  });
}
