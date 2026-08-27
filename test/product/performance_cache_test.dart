import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/performance_cache.dart';
import 'package:kristin_local_agent/product/performance_spans.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final temporaryDirectories = <Directory>[];

  Future<Directory> temporaryRoot() async {
    final root = await Directory.systemTemp.createTemp('kristin-cache-test-');
    temporaryDirectories.add(root);
    return root;
  }

  tearDown(() async {
    for (final directory in temporaryDirectories.reversed) {
      try {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      } catch (_) {}
    }
    temporaryDirectories.clear();
  });

  test('cache database is separate from authoritative workflow state',
      () async {
    final root = await temporaryRoot();
    final state = Directory(
      '${root.path}${Platform.pathSeparator}state',
    );
    final cacheDirectory = Directory(
      '${root.path}${Platform.pathSeparator}cache',
    );
    await state.create(recursive: true);
    final workflowFile = File(
      '${state.path}${Platform.pathSeparator}workflow.sqlite3',
    );
    final workflow = sqlite3.open(workflowFile.path);
    workflow.execute('CREATE TABLE authority(value TEXT NOT NULL)');
    workflow.execute(
      'INSERT INTO authority(value) VALUES (?)',
      <Object?>['durable'],
    );
    workflow.dispose();

    final cache = await RebuildableCacheDatabase.open(cacheDirectory);
    final diagnostics = await cache.diagnostics();

    expect(diagnostics.persistent, isTrue);
    expect(diagnostics.lastRebuildAt, isNotNull);
    expect(
      diagnostics.databasePath,
      '${cacheDirectory.path}${Platform.pathSeparator}cache.sqlite3',
    );
    expect(workflowFile.path, isNot(diagnostics.databasePath));

    final reopenedWorkflow = sqlite3.open(workflowFile.path);
    expect(
      reopenedWorkflow.select('SELECT value FROM authority').single['value'],
      'durable',
    );
    reopenedWorkflow.dispose();
    await cache.close();
  });

  test('records spans and advances namespaced generations', () async {
    final root = await temporaryRoot();
    final cache = await RebuildableCacheDatabase.open(
      Directory('${root.path}${Platform.pathSeparator}cache'),
    );
    final projectHash = List<String>.filled(64, 'a').join();

    final span = PerformanceSpan.start(
      'source.search',
      sink: cache,
      projectHash: projectHash,
      cacheResult: PerformanceCacheResult.miss,
      thermalState: PerformanceThermalState.cold,
    );
    span.finish(
      itemCount: 4,
      bytesConsidered: 1024,
      candidateCount: 2,
      indexQueryDuration: const Duration(milliseconds: 3),
    );

    expect(cache.generation('source', projectHash: projectHash), 0);
    expect(cache.advanceGeneration('source', projectHash: projectHash), 1);
    expect(cache.advanceGeneration('source', projectHash: projectHash), 2);
    expect(cache.generation('source', projectHash: projectHash), 2);

    final diagnostics = await cache.diagnostics();
    expect(diagnostics.performanceSpanRows, 1);
    expect(diagnostics.generationRows, 1);
    expect(diagnostics.degraded, isFalse);
    await cache.close();
  });

  test('buffered spans are flushed on close without content columns', () async {
    final root = await temporaryRoot();
    final cacheDirectory = Directory(
      '${root.path}${Platform.pathSeparator}cache',
    );
    final cache = await RebuildableCacheDatabase.open(cacheDirectory);
    cache.recordPerformanceSpan(
      PerformanceSpanRecord(
        operation: 'source.search',
        startedAt: DateTime.now(),
        duration: const Duration(milliseconds: 1),
      ),
    );
    await cache.close();

    final persisted = sqlite3.open(
      '${cacheDirectory.path}${Platform.pathSeparator}cache.sqlite3',
    );
    try {
      expect(
        persisted
            .select('SELECT COUNT(*) AS value FROM performance_spans')
            .single['value'],
        1,
      );
      final columns = persisted
          .select('PRAGMA table_info(performance_spans)')
          .map((row) => row['name']?.toString() ?? '')
          .toSet();
      expect(columns, isNot(contains('prompt')));
      expect(columns, isNot(contains('content')));
      expect(columns, isNot(contains('source_text')));
      expect(columns, isNot(contains('terminal_output')));
      expect(columns, isNot(contains('user_text')));
    } finally {
      persisted.dispose();
    }
  });

  test('invalid SQLite bytes are quarantined and rebuilt automatically',
      () async {
    final root = await temporaryRoot();
    final cacheDirectory = Directory(
      '${root.path}${Platform.pathSeparator}cache',
    );
    await cacheDirectory.create(recursive: true);
    final cacheFile = File(
      '${cacheDirectory.path}${Platform.pathSeparator}cache.sqlite3',
    );
    await cacheFile.writeAsString('not-a-sqlite-database', flush: true);

    final cache = await RebuildableCacheDatabase.open(cacheDirectory);
    final diagnostics = await cache.diagnostics();
    final quarantined = (await cacheDirectory.list().toList())
        .whereType<File>()
        .where((file) => file.path.contains('cache.sqlite3.invalid.'))
        .toList();

    expect(diagnostics.persistent, isTrue);
    expect(diagnostics.startupMode, CacheDatabaseStartupMode.recovered);
    expect(diagnostics.startupFailureType, 'cache_header_invalid');
    expect(quarantined, hasLength(1));
    await cache.close();
  });

  test('unsupported cache schema is discarded instead of migrated', () async {
    final root = await temporaryRoot();
    final cacheDirectory = Directory(
      '${root.path}${Platform.pathSeparator}cache',
    );
    await cacheDirectory.create(recursive: true);
    final cacheFile = File(
      '${cacheDirectory.path}${Platform.pathSeparator}cache.sqlite3',
    );
    final incompatible = sqlite3.open(cacheFile.path);
    incompatible.execute('PRAGMA user_version = 999');
    incompatible.dispose();

    final cache = await RebuildableCacheDatabase.open(cacheDirectory);
    final diagnostics = await cache.diagnostics();

    expect(diagnostics.persistent, isTrue);
    expect(diagnostics.startupMode, CacheDatabaseStartupMode.recovered);
    expect(diagnostics.startupFailureType, 'cache_schema_unsupported_v999');
    expect(diagnostics.schemaVersion, 1);
    await cache.close();
  });

  test('disk cache failure falls back to a functioning memory cache', () async {
    final root = await temporaryRoot();
    final blocker = File(
      '${root.path}${Platform.pathSeparator}cache-blocker',
    );
    await blocker.writeAsString('file-not-directory', flush: true);

    final cache = await RebuildableCacheDatabase.open(
      Directory(blocker.path),
    );
    final span = PerformanceSpan.start('source.search', sink: cache);
    span.finish();
    final diagnostics = await cache.diagnostics();

    expect(diagnostics.persistent, isFalse);
    expect(
      diagnostics.startupMode,
      CacheDatabaseStartupMode.memoryFallback,
    );
    expect(diagnostics.performanceSpanRows, 1);
    expect(cache.advanceGeneration('source'), 1);
    await cache.close();
  });

  test('performance span retention is bounded', () async {
    final root = await temporaryRoot();
    final cache = await RebuildableCacheDatabase.open(
      Directory('${root.path}${Platform.pathSeparator}cache'),
      maxPerformanceSpanRows: 3,
    );

    for (var index = 0; index < 128; index++) {
      cache.recordPerformanceSpan(
        PerformanceSpanRecord(
          operation: 'benchmark.sample',
          startedAt: DateTime.now(),
          duration: Duration(microseconds: index),
        ),
      );
    }

    final diagnostics = await cache.diagnostics();
    expect(diagnostics.performanceSpanRows, 3);
    await cache.close();
    await cache.close();
  });
}
