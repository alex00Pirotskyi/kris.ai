import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/extensions_index.dart';
import 'package:kristin_local_agent/product/performance_spans.dart';
import 'package:sqlite3/sqlite3.dart';

final class _CapturingPerformanceSink implements PerformanceSpanSink {
  final List<PerformanceSpanRecord> records = <PerformanceSpanRecord>[];

  @override
  void recordPerformanceSpan(PerformanceSpanRecord record) {
    records.add(record);
  }
}

final class _FailingPerformanceSink implements PerformanceSpanSink {
  @override
  void recordPerformanceSpan(PerformanceSpanRecord record) {
    throw StateError('performance_sink_failed');
  }
}

ProjectRecord _project(String id, Directory root) {
  final now = DateTime.now().toUtc();
  return ProjectRecord(
    id: id,
    name: id,
    rootPath: root.path,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('source update and search use warm SQLite without JSON decoding',
      () async {
    final root = await Directory.systemTemp.createTemp('source-perf-test-');
    SourceIndexService? sourceIndex;
    try {
      final projectRoot = Directory(
        '${root.path}${Platform.pathSeparator}project',
      );
      await projectRoot.create(recursive: true);
      await File(
        '${projectRoot.path}${Platform.pathSeparator}sample.dart',
      ).writeAsString(
        'final class SearchableSymbol { const SearchableSymbol(); }\n',
        flush: true,
      );
      final sink = _CapturingPerformanceSink();
      final indexDirectory = Directory(
        '${root.path}${Platform.pathSeparator}index',
      );
      sourceIndex = SourceIndexService(indexDirectory, performance: sink);
      final project = _project('source_perf_project', projectRoot);

      final cold = await sourceIndex.update(project);
      final results = await sourceIndex.search(project.id, 'SearchableSymbol');
      final warm = await sourceIndex.update(project);
      final diagnostics = await sourceIndex.diagnostics(project.id);

      expect(results, hasLength(1));
      expect(results.single['path'], 'sample.dart');
      expect(cold.generation, 1);
      expect(warm.generation, 1);
      expect(
        sink.records.map((record) => record.operation),
        <String>[
          'source.index.update',
          'source.search',
          'source.index.update',
        ],
      );
      expect(sink.records.first.cacheResult, PerformanceCacheResult.miss);
      expect(sink.records[1].cacheResult, PerformanceCacheResult.hit);
      expect(sink.records.last.cacheResult, PerformanceCacheResult.hit);
      expect(sink.records.first.bytesConsidered, greaterThan(0));
      expect(sink.records[1].bytesConsidered, 0);
      expect(sink.records.last.bytesConsidered, 0);
      expect(
        sink.records.every((record) => record.projectHash?.length == 64),
        isTrue,
      );
      expect(diagnostics.backend, anyOf('fts5', 'terms'));
      expect(diagnostics.persistent, isTrue);
      expect(diagnostics.files, 1);
      expect(diagnostics.generation, 1);
      expect(
        diagnostics.databasePath,
        '${indexDirectory.path}${Platform.pathSeparator}source-index.sqlite3',
      );
      expect(
        (await indexDirectory.list().toList())
            .whereType<File>()
            .where((file) => file.path.endsWith('.json')),
        isEmpty,
      );
    } finally {
      await sourceIndex?.close();
      await root.delete(recursive: true);
    }
  });

  test('product-shaped index directory extends shared cache.sqlite3', () async {
    final root = await Directory.systemTemp.createTemp('source-shared-cache-');
    SourceIndexService? sourceIndex;
    try {
      final cacheFile = File(
        '${root.path}${Platform.pathSeparator}cache.sqlite3',
      );
      final cache = sqlite3.open(cacheFile.path);
      cache.execute('CREATE TABLE sentinel(value TEXT NOT NULL)');
      cache.execute(
        'INSERT INTO sentinel(value) VALUES (?)',
        <Object?>['preserved'],
      );
      cache.dispose();
      final projectRoot = Directory(
        '${root.path}${Platform.pathSeparator}project',
      );
      await projectRoot.create(recursive: true);
      await File(
        '${projectRoot.path}${Platform.pathSeparator}main.dart',
      ).writeAsString('const sharedCacheNeedle = true;\n', flush: true);
      sourceIndex = SourceIndexService(
        Directory('${root.path}${Platform.pathSeparator}source-index'),
      );
      final project = _project('shared_cache_project', projectRoot);

      await sourceIndex.update(project);
      final diagnostics = await sourceIndex.diagnostics(project.id);
      final results = await sourceIndex.search(project.id, 'sharedCacheNeedle');
      await sourceIndex.close();
      sourceIndex = null;

      expect(diagnostics.databasePath, cacheFile.path);
      expect(results, isNotEmpty);
      final reopened = sqlite3.open(cacheFile.path);
      try {
        expect(
          reopened.select('SELECT value FROM sentinel').single['value'],
          'preserved',
        );
        final sourceTables = reopened
            .select(
              "SELECT name FROM sqlite_master WHERE name LIKE 'source_%'",
            )
            .map((row) => row['name']?.toString() ?? '')
            .toSet();
        expect(sourceTables, contains('source_projects'));
        expect(sourceTables, contains('source_files'));
        expect(sourceTables, contains('source_symbols'));
        expect(sourceTables, contains('source_dependencies'));
        expect(
          sourceTables.contains('source_fts') ||
              sourceTables.contains('source_terms'),
          isTrue,
        );
      } finally {
        reopened.dispose();
      }
    } finally {
      await sourceIndex?.close();
      await root.delete(recursive: true);
    }
  });

  test('committed path reindex is file-local and generation based', () async {
    final root = await Directory.systemTemp.createTemp('source-incremental-');
    SourceIndexService? sourceIndex;
    try {
      final projectRoot = Directory(
        '${root.path}${Platform.pathSeparator}project',
      );
      await projectRoot.create(recursive: true);
      final a = File('${projectRoot.path}${Platform.pathSeparator}a.dart');
      final b = File('${projectRoot.path}${Platform.pathSeparator}b.dart');
      await a.writeAsString('const alphaValue = 1;\n', flush: true);
      await b.writeAsString('const betaValue = 2;\n', flush: true);
      final sink = _CapturingPerformanceSink();
      sourceIndex = SourceIndexService(
        Directory('${root.path}${Platform.pathSeparator}index'),
        performance: sink,
      );
      final project = _project('source_incremental_project', projectRoot);
      final initial = await sourceIndex.update(project);

      await a.writeAsString('const alphaReplacement = 3;\n', flush: true);
      final c = File('${projectRoot.path}${Platform.pathSeparator}c.dart');
      await c.writeAsString('const gammaValue = 4;\n', flush: true);
      final changed = await sourceIndex.reindexCommittedPaths(
        project,
        <String>{'a.dart', 'c.dart'},
      );
      final replacement = await sourceIndex.search(
        project.id,
        'alphaReplacement',
      );

      await b.delete();
      final removed = await sourceIndex.reindexCommittedPaths(
        project,
        const <String>{'b.dart'},
      );
      final deleted = await sourceIndex.search(project.id, 'betaValue');

      expect(initial.total, 2);
      expect(initial.generation, 1);
      expect(changed.scanned, 2);
      expect(changed.changed, 2);
      expect(changed.removed, 0);
      expect(changed.total, 3);
      expect(changed.generation, 2);
      expect(replacement.single['path'], 'a.dart');
      expect(removed.scanned, 1);
      expect(removed.changed, 0);
      expect(removed.removed, 1);
      expect(removed.total, 2);
      expect(removed.generation, 3);
      expect(deleted, isEmpty);
      final incrementalSpans = sink.records.where(
        (record) =>
            record.operation == 'source.index.update' &&
            record.taskClass == 'incremental',
      );
      expect(incrementalSpans, hasLength(2));
      expect(incrementalSpans.first.candidateCount, 2);
      expect(incrementalSpans.last.candidateCount, 1);
    } finally {
      await sourceIndex?.close();
      await root.delete(recursive: true);
    }
  });

  test('native watcher propagates external edits when supported', () async {
    final root = await Directory.systemTemp.createTemp('source-watch-test-');
    SourceIndexService? sourceIndex;
    try {
      final projectRoot = Directory(
        '${root.path}${Platform.pathSeparator}project',
      );
      await projectRoot.create(recursive: true);
      final file = File(
        '${projectRoot.path}${Platform.pathSeparator}watched.dart',
      );
      await file.writeAsString('const watcherBefore = 1;\n', flush: true);
      sourceIndex = SourceIndexService(
        Directory('${root.path}${Platform.pathSeparator}index'),
      );
      final project = _project('source_watcher_project', projectRoot);
      await sourceIndex.update(project);
      final diagnostics = await sourceIndex.diagnostics(project.id);
      if (!diagnostics.watcherActive) return;

      await file.writeAsString('const watcherAfter = 2;\n', flush: true);
      List<Map<String, dynamic>> results = const <Map<String, dynamic>>[];
      for (var attempt = 0; attempt < 60; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        results = await sourceIndex.search(project.id, 'watcherAfter');
        if (results.isNotEmpty) break;
      }

      expect(results, isNotEmpty);
      expect(results.single['path'], 'watched.dart');
      final after = await sourceIndex.diagnostics(project.id);
      expect(after.generation, greaterThanOrEqualTo(2));
    } finally {
      await sourceIndex?.close();
      await root.delete(recursive: true);
    }
  });

  test('source operations do not fail when performance recording fails',
      () async {
    final root =
        await Directory.systemTemp.createTemp('source-perf-fail-test-');
    SourceIndexService? sourceIndex;
    try {
      final projectRoot = Directory(
        '${root.path}${Platform.pathSeparator}project',
      );
      await projectRoot.create(recursive: true);
      await File(
        '${projectRoot.path}${Platform.pathSeparator}sample.dart',
      ).writeAsString('const searchableValue = 1;\n', flush: true);
      sourceIndex = SourceIndexService(
        Directory('${root.path}${Platform.pathSeparator}index'),
        performance: _FailingPerformanceSink(),
      );
      final project = _project('source_perf_failure_project', projectRoot);

      final update = await sourceIndex.update(project);
      final results = await sourceIndex.search(project.id, 'searchableValue');

      expect(update.total, 1);
      expect(results, isNotEmpty);
    } finally {
      await sourceIndex?.close();
      await root.delete(recursive: true);
    }
  });
}
