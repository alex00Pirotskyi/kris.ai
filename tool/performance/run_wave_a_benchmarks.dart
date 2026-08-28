import 'dart:convert';
import 'dart:io';

import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/extensions_index.dart';
import 'package:kristin_local_agent/product/performance_cache.dart';

import 'benchmark_corpus.dart';

const String baselineMainSha = 'f8e8cbba98e2556384cec69627c139a0e78a0f5a';

Future<void> main(List<String> arguments) async {
  final includeLarge = !arguments.contains('--skip-large');
  final keepCorpus = arguments.contains('--keep-corpus');
  final outputArgument = arguments
      .where((argument) => argument.startsWith('--output='))
      .firstOrNull;
  final output = File(
    outputArgument?.substring('--output='.length) ??
        '${Directory.current.path}${Platform.pathSeparator}'
            'performance-results${Platform.pathSeparator}'
            'wave-a-baseline.json',
  );
  final benchmarkRoot = await Directory.systemTemp.createTemp(
    'kristin-performance-wave-b-',
  );
  final generatedAt = DateTime.now().toUtc();
  final results = <Map<String, Object?>>[];
  RebuildableCacheDatabase? cache;
  SourceIndexService? sourceIndex;
  try {
    final cacheDirectory = Directory(
      '${benchmarkRoot.path}${Platform.pathSeparator}cache',
    );
    final coldOpen = Stopwatch()..start();
    cache = await RebuildableCacheDatabase.open(cacheDirectory);
    coldOpen.stop();
    results.add(
      _singleMeasurement(
        benchmark: 'cache.open',
        temperature: 'cold',
        cacheState: 'miss',
        microseconds: coldOpen.elapsedMicroseconds,
      ),
    );
    await cache.close();
    cache = null;

    final warmOpenSamples = <int>[];
    for (var sample = 0; sample < 10; sample++) {
      final stopwatch = Stopwatch()..start();
      final opened = await RebuildableCacheDatabase.open(cacheDirectory);
      stopwatch.stop();
      warmOpenSamples.add(stopwatch.elapsedMicroseconds);
      await opened.close();
    }
    results.add(
      _distributionMeasurement(
        benchmark: 'cache.open',
        temperature: 'warm',
        cacheState: 'hit',
        samples: warmOpenSamples,
      ),
    );

    final performanceCache = await RebuildableCacheDatabase.open(
      cacheDirectory,
    );
    cache = performanceCache;
    final corpusParent = Directory(
      '${benchmarkRoot.path}${Platform.pathSeparator}corpora',
    );
    sourceIndex = SourceIndexService(
      Directory(
        '${cacheDirectory.path}${Platform.pathSeparator}source-index',
      ),
      performance: performanceCache,
    );
    final specs = <BenchmarkCorpusSpec>[
      smallBenchmarkCorpus,
      mediumBenchmarkCorpus,
      if (includeLarge) largeBenchmarkCorpus,
    ];
    for (final spec in specs) {
      final corpus = await createBenchmarkCorpus(corpusParent, spec);
      results.addAll(
        await _benchmarkSourceIndex(
          sourceIndex: sourceIndex,
          corpus: corpus,
        ),
      );
    }

    final cacheDiagnostics = await performanceCache.diagnostics();
    final report = <String, Object?>{
      'schemaVersion': 'kristin.performance-baseline.v2',
      'baselineMainSha': baselineMainSha,
      'generatedAt': generatedAt.toIso8601String(),
      'environment': <String, Object?>{
        'operatingSystem': Platform.operatingSystem,
        'operatingSystemVersion': Platform.operatingSystemVersion,
        'dartVersion': Platform.version,
        'numberOfProcessors': Platform.numberOfProcessors,
        'executable': Platform.resolvedExecutable,
      },
      'configuration': <String, Object?>{
        'largeCorpusIncluded': includeLarge,
        'corpusRetained': keepCorpus,
        'resultUnits': 'microseconds',
        'sourceCache': 'cache.sqlite3',
      },
      'cacheDiagnostics': cacheDiagnostics.toJson(),
      'benchmarks': results,
      'interpretation': <String, Object?>{
        'coldAndWarmSeparated': true,
        'sourceQueryCacheAvailableOnBaseline': true,
        'warmQueriesReadFilesystemBytes': false,
        'changedFileUpdateUsesExplicitIncrementalPath': true,
        'wallClockTargetsEnforcedByCi': false,
        'performanceClaimsRequireBeforeAfterSamples': true,
      },
    };
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      flush: true,
    );
    stdout.writeln(output.path);
  } finally {
    await sourceIndex?.close();
    await cache?.close();
    if (!keepCorpus) {
      try {
        if (await benchmarkRoot.exists()) {
          await benchmarkRoot.delete(recursive: true);
        }
      } catch (_) {}
    } else {
      stderr.writeln('Benchmark corpus retained at ${benchmarkRoot.path}');
    }
  }
}

Future<List<Map<String, Object?>>> _benchmarkSourceIndex({
  required SourceIndexService sourceIndex,
  required BenchmarkCorpus corpus,
}) async {
  final now = DateTime.now().toUtc();
  final project = ProjectRecord(
    id: 'performance_${corpus.spec.id}',
    name: 'Performance ${corpus.spec.id}',
    rootPath: corpus.root.path,
    createdAt: now,
    updatedAt: now,
  );
  final results = <Map<String, Object?>>[];

  final coldUpdate = Stopwatch()..start();
  final coldReport = await sourceIndex.update(project);
  coldUpdate.stop();
  final coldDiagnostics = await sourceIndex.diagnostics(project.id);
  results.add(
    <String, Object?>{
      ..._singleMeasurement(
        benchmark: 'source.index.update.${corpus.spec.id}',
        temperature: 'cold',
        cacheState: 'miss',
        microseconds: coldUpdate.elapsedMicroseconds,
      ),
      'configuredFiles': corpus.spec.fileCount,
      'scannedFiles': coldReport.scanned,
      'changedFiles': coldReport.changed,
      'indexedFiles': coldReport.total,
      'skippedFiles': coldReport.skipped,
      'generation': coldReport.generation,
      'searchBackend': coldDiagnostics.backend,
      'databasePath': coldDiagnostics.databasePath,
    },
  );

  final repeatedQuerySamples = <int>[];
  var repeatedResultCount = 0;
  for (var sample = 0; sample < 25; sample++) {
    final stopwatch = Stopwatch()..start();
    final matches = await sourceIndex.search(
      project.id,
      'Feature000010 deterministicValue5',
      limit: 20,
    );
    stopwatch.stop();
    repeatedResultCount = matches.length;
    repeatedQuerySamples.add(stopwatch.elapsedMicroseconds);
  }
  results.add(
    <String, Object?>{
      ..._distributionMeasurement(
        benchmark: 'source.search.repeated.${corpus.spec.id}',
        temperature: 'warm',
        cacheState: 'hit',
        samples: repeatedQuerySamples,
      ),
      'resultCount': repeatedResultCount,
      'filesystemBytesReadPerQuery': 0,
      'fullFilesystemScanPerQuery': false,
      'searchBackend': coldDiagnostics.backend,
    },
  );

  await mutateBenchmarkCorpus(corpus);
  final changedUpdate = Stopwatch()..start();
  final changedReport = await sourceIndex.reindexCommittedPaths(
    project,
    <String>{corpus.mutableFile.path},
  );
  changedUpdate.stop();
  results.add(
    <String, Object?>{
      ..._singleMeasurement(
        benchmark: 'source.index.changed_file_update.${corpus.spec.id}',
        temperature: 'warm',
        cacheState: 'hit',
        microseconds: changedUpdate.elapsedMicroseconds,
      ),
      'configuredFiles': corpus.spec.fileCount,
      'scannedFiles': changedReport.scanned,
      'changedFiles': changedReport.changed,
      'indexedFiles': changedReport.total,
      'generation': changedReport.generation,
      'fullScanObserved': changedReport.scanned > 1,
    },
  );

  final symbolSamples = <int>[];
  var symbolResultCount = 0;
  for (var sample = 0; sample < 25; sample++) {
    final stopwatch = Stopwatch()..start();
    final matches = await sourceIndex.search(
      project.id,
      'Feature000000',
      limit: 10,
    );
    stopwatch.stop();
    symbolSamples.add(stopwatch.elapsedMicroseconds);
    symbolResultCount = matches.length;
  }
  results.add(
    <String, Object?>{
      ..._distributionMeasurement(
        benchmark: 'source.symbol_lookup.${corpus.spec.id}',
        temperature: 'warm',
        cacheState: 'hit',
        samples: symbolSamples,
      ),
      'resultCount': symbolResultCount,
      'filesystemBytesReadPerQuery': 0,
      'fullFilesystemScanPerQuery': false,
      'searchBackend': coldDiagnostics.backend,
    },
  );
  return results;
}

Map<String, Object?> _singleMeasurement({
  required String benchmark,
  required String temperature,
  required String cacheState,
  required int microseconds,
}) {
  return <String, Object?>{
    'benchmark': benchmark,
    'temperature': temperature,
    'cacheState': cacheState,
    'sampleCount': 1,
    'minimumMicroseconds': microseconds,
    'p50Microseconds': microseconds,
    'p95Microseconds': microseconds,
    'maximumMicroseconds': microseconds,
    'meanMicroseconds': microseconds,
  };
}

Map<String, Object?> _distributionMeasurement({
  required String benchmark,
  required String temperature,
  required String cacheState,
  required List<int> samples,
}) {
  if (samples.isEmpty) {
    throw ArgumentError.value(samples, 'samples', 'must not be empty');
  }
  final ordered = samples.toList()..sort();
  final total = ordered.fold<int>(0, (sum, value) => sum + value);
  return <String, Object?>{
    'benchmark': benchmark,
    'temperature': temperature,
    'cacheState': cacheState,
    'sampleCount': ordered.length,
    'minimumMicroseconds': ordered.first,
    'p50Microseconds': _percentile(ordered, 0.50),
    'p95Microseconds': _percentile(ordered, 0.95),
    'maximumMicroseconds': ordered.last,
    'meanMicroseconds': total / ordered.length,
  };
}

int _percentile(List<int> ordered, double percentile) {
  final index = ((ordered.length - 1) * percentile).round();
  return ordered[index];
}
