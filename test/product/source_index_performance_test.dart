import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/extensions_index.dart';
import 'package:kristin_local_agent/product/performance_spans.dart';

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

void main() {
  test('source update and search emit structured performance spans', () async {
    final root = await Directory.systemTemp.createTemp('source-perf-test-');
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
      final sourceIndex = SourceIndexService(
        Directory('${root.path}${Platform.pathSeparator}index'),
        performance: sink,
      );
      final now = DateTime.now().toUtc();
      final project = ProjectRecord(
        id: 'source_perf_project',
        name: 'Source performance',
        rootPath: projectRoot.path,
        createdAt: now,
        updatedAt: now,
      );

      await sourceIndex.update(project);
      await sourceIndex.search(project.id, 'SearchableSymbol');
      await sourceIndex.update(project);

      expect(
        sink.records.map((record) => record.operation),
        <String>[
          'source.index.update',
          'source.search',
          'source.index.update',
        ],
      );
      expect(
        sink.records.first.cacheResult,
        PerformanceCacheResult.miss,
      );
      expect(
        sink.records.last.cacheResult,
        PerformanceCacheResult.hit,
      );
      expect(sink.records.first.bytesConsidered, greaterThan(0));
      expect(sink.records[1].bytesConsidered, greaterThan(0));
      expect(sink.records.last.bytesConsidered, 0);
      expect(
        sink.records.every(
          (record) => record.projectHash?.length == 64,
        ),
        isTrue,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('source operations do not fail when performance recording fails',
      () async {
    final root =
        await Directory.systemTemp.createTemp('source-perf-fail-test-');
    try {
      final projectRoot = Directory(
        '${root.path}${Platform.pathSeparator}project',
      );
      await projectRoot.create(recursive: true);
      await File(
        '${projectRoot.path}${Platform.pathSeparator}sample.dart',
      ).writeAsString('const searchableValue = 1;\n', flush: true);
      final sourceIndex = SourceIndexService(
        Directory('${root.path}${Platform.pathSeparator}index'),
        performance: _FailingPerformanceSink(),
      );
      final now = DateTime.now().toUtc();
      final project = ProjectRecord(
        id: 'source_perf_failure_project',
        name: 'Source performance failure',
        rootPath: projectRoot.path,
        createdAt: now,
        updatedAt: now,
      );

      final update = await sourceIndex.update(project);
      final results = await sourceIndex.search(project.id, 'searchableValue');

      expect(update.total, 1);
      expect(results, isNotEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
