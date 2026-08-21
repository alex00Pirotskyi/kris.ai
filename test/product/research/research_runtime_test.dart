import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:kristin_local_agent/product/research/research_runtime.dart';
import 'package:kristin_local_agent/product/research/research_workspace.dart';

void main() {
  test(
      'content store deduplicates immutable objects and preserves fetch versions',
      () async {
    final root = await Directory.systemTemp.createTemp('p4-store-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final store = P4ResearchContentStore(
      root,
      clock: () => DateTime.utc(2026, 8, 20, 7),
    );
    final first =
        await store.putObject(utf8.encode('same'), mediaType: 'text/plain');
    final second =
        await store.putObject(utf8.encode('same'), mediaType: 'text/plain');
    expect(first.sha256, second.sha256);
    expect(await File(first.path).readAsString(), 'same');

    final fetch = await store.saveFetch(
      url: 'https://example.com/source',
      canonicalUrl: 'https://example.com/source',
      rawBytes: utf8.encode('<p>Evidence text</p>'),
      extraction: <String, Object?>{'text': 'Evidence text'},
      title: 'Evidence',
      trustLabel: 'fixture',
    );
    final listed = await store.listFetches();
    expect(listed.single.id, fetch.id);
    expect(listed.single.extractionHash, fetch.extractionHash);

    final citation = await store.createCitation(
      fetch: fetch,
      extractedText: 'Evidence text',
      claim: 'The fixture contains evidence.',
      start: 0,
      end: 8,
    );
    expect(citation.fetchVersionId, fetch.id);
    expect(citation.extractionHash, fetch.extractionHash);
  });

  test('lexical search is scoped and semantic index is optional', () async {
    final index = P4LexicalIndex()
      ..upsert(const P4LexicalDocument(
        id: 'a',
        scope: 'project-a',
        title: 'Flutter BLE reference',
        text: 'Bluetooth low energy reference details',
        metadata: <String, Object?>{},
      ))
      ..upsert(const P4LexicalDocument(
        id: 'b',
        scope: 'project-b',
        title: 'Flutter BLE hidden',
        text: 'Should never cross scope',
        metadata: <String, Object?>{},
      ));
    final lexical = await index.search('Flutter BLE', scope: 'project-a');
    expect(lexical.map((hit) => hit.document.id), <String>['a']);

    index.semantic = _SemanticIndex(<String>['a']);
    final semantic = await index.search(
      'reference',
      scope: 'project-a',
      semanticPreferred: true,
    );
    expect(semantic.single.document.id, 'a');
    index.semantic = null;
    expect(
        (await index.search('reference', scope: 'project-a'))
            .single
            .document
            .id,
        'a');
  });

  test('dataset recipe is reproducible and exports reopen with provenance',
      () async {
    final root = await Directory.systemTemp.createTemp('p4-dataset-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final engine = P4DatasetEngine();
    final transforms = <P4DatasetTransform>[
      const P4DatasetTransform(
        P4DatasetTransformKind.normalizeText,
        <String, Object?>{'field': 'name'},
      ),
      const P4DatasetTransform(
        P4DatasetTransformKind.dedupe,
        <String, Object?>{
          'fields': <String>['name']
        },
      ),
      const P4DatasetTransform(
        P4DatasetTransformKind.sort,
        <String, Object?>{'field': 'name'},
      ),
      const P4DatasetTransform(
        P4DatasetTransformKind.validateRequired,
        <String, Object?>{
          'fields': <String>['name']
        },
      ),
    ];
    final rows = <Map<String, Object?>>[
      <String, Object?>{'name': '  Beta ', 'count': 2},
      <String, Object?>{'name': 'Alpha', 'count': 1},
      <String, Object?>{'name': 'Beta', 'count': 2},
    ];
    final first = engine.create(
      datasetId: 'fixture',
      rows: rows,
      schema: const <String, String>{'name': 'string', 'count': 'int'},
      sourceHashes: <String>['a' * 64],
      transforms: transforms,
      createdAt: DateTime.utc(2026, 8, 20),
    );
    final second = engine.create(
      datasetId: 'fixture',
      rows: rows,
      schema: const <String, String>{'name': 'string', 'count': 'int'},
      sourceHashes: <String>['a' * 64],
      transforms: transforms,
      createdAt: DateTime.utc(2026, 8, 20),
    );
    expect(first.manifestHash, second.manifestHash);
    expect(first.rows.map((row) => row['name']), <Object?>['Alpha', 'Beta']);

    final jsonl = File('${root.path}/data.jsonl');
    final csv = File('${root.path}/data.csv');
    final markdown = File('${root.path}/data.md');
    final sqlite = File('${root.path}/data.sqlite');
    await engine.export(first, jsonl, format: 'jsonl');
    await engine.export(first, csv, format: 'csv');
    await engine.export(first, markdown, format: 'markdown');
    await engine.export(first, sqlite, format: 'sqlite');
    expect((await jsonl.readAsLines()).length, 2);
    expect(await csv.readAsString(), contains('"Alpha"'));
    expect(await markdown.readAsString(), contains('| Alpha |'));
    final db = sqlite3.open(sqlite.path);
    try {
      expect(db.select('SELECT COUNT(*) AS c FROM data').single['c'], 2);
      expect(
        db
            .select("SELECT value FROM manifest WHERE key='manifestHash'")
            .single['value'],
        first.manifestHash,
      );
    } finally {
      db.dispose();
    }
  });

  test('freshness monitor reports precise extraction hash changes', () {
    final monitor = P4FreshnessMonitor();
    final first = monitor.observe(
      canonicalUrl: 'https://example.com/a',
      extractionHash: 'a' * 64,
      recordedAt: DateTime.utc(2026, 8, 20),
    );
    final same = monitor.observe(
      canonicalUrl: 'https://example.com/a',
      extractionHash: 'a' * 64,
      recordedAt: DateTime.utc(2026, 8, 21),
    );
    final changed = monitor.observe(
      canonicalUrl: 'https://example.com/a',
      extractionHash: 'b' * 64,
      recordedAt: DateTime.utc(2026, 8, 22),
    );
    expect(first.changed, isFalse);
    expect(same.changed, isFalse);
    expect(changed.changed, isTrue);
    expect(changed.beforeHash, 'a' * 64);
  });

  testWidgets('Research workspace exposes source and citation inspection',
      (tester) async {
    final controller = P4ResearchWorkspaceController();
    final fetch = _fetch();
    controller
      ..replaceSources(<P4FetchVersion>[fetch])
      ..replaceCitations(<P4CitationSpan>[
        P4CitationSpan(
          id: 'cite-1',
          fetchVersionId: fetch.id,
          extractionHash: fetch.extractionHash,
          claim: 'Fixture claim',
          start: 0,
          end: 7,
          quoteHash: 'c' * 64,
        ),
      ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: P4ResearchWorkspace(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Research question'), findsOneWidget);
    expect(find.text('1 immutable sources'), findsOneWidget);
    await tester.tap(find.text('Results'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture source'), findsOneWidget);
    await tester.tap(find.text('Citations'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture claim'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Data workspace virtualizes large fixture table and exports',
      (tester) async {
    final version = P4DatasetEngine().create(
      datasetId: 'large',
      rows: List<Map<String, Object?>>.generate(
        10000,
        (index) => <String, Object?>{'id': index, 'value': 'row-$index'},
      ),
      schema: const <String, String>{'id': 'int', 'value': 'string'},
      sourceHashes: <String>['d' * 64],
      createdAt: DateTime.utc(2026, 8, 20),
    );
    final controller = P4DataWorkspaceController()
      ..replaceVersions(<P4DatasetVersion>[version]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: P4DataWorkspace(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('row-0'), findsOneWidget);
    expect(find.text('row-9999'), findsNothing);
    await tester.ensureVisible(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('JSONL'), findsOneWidget);
    expect(find.text('SQLITE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

P4FetchVersion _fetch() => P4FetchVersion(
      id: 'fetch-fixture',
      url: 'https://example.com/source',
      canonicalUrl: 'https://example.com/source',
      fetchedAt: DateTime.utc(2026, 8, 20),
      rawObjectSha256: 'a' * 64,
      extractionObjectSha256: 'b' * 64,
      extractionHash: 'b' * 64,
      title: 'Fixture source',
      trustLabel: 'fixture',
    );

final class _SemanticIndex implements P4SemanticIndex {
  _SemanticIndex(this.ids);
  final List<String> ids;
  @override
  Future<List<String>> searchIds(
    String query, {
    required String scope,
    int limit = 20,
  }) async =>
      ids.take(limit).toList();
}
