import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/performance_spans.dart';

final class _ThrowingSink implements PerformanceSpanSink {
  @override
  void recordPerformanceSpan(PerformanceSpanRecord record) {
    throw StateError('sink_failed');
  }
}

final class _CapturingSink implements PerformanceSpanSink {
  final List<PerformanceSpanRecord> records = <PerformanceSpanRecord>[];

  @override
  void recordPerformanceSpan(PerformanceSpanRecord record) {
    records.add(record);
  }
}

void main() {
  test('recording failure never changes the measured action outcome', () async {
    final result = await PerformanceSpan.measure<int>(
      'source.search',
      () => 42,
      sink: _ThrowingSink(),
    );

    expect(result, 42);
  });

  test('invalid measurement metadata cannot change a successful action',
      () async {
    final result = await PerformanceSpan.measure<int>(
      'invalid operation label',
      () => 7,
    );

    expect(result, 7);
  });

  test('the original action error is preserved when the sink also fails',
      () async {
    final actionError = StateError('action_failed');

    await expectLater(
      PerformanceSpan.measure<void>(
        'source.search',
        () => throw actionError,
        sink: _ThrowingSink(),
      ),
      throwsA(same(actionError)),
    );
  });

  test('failed actions emit a failure outcome without replacing the error',
      () async {
    final sink = _CapturingSink();
    final actionError = StateError('action_failed');

    await expectLater(
      PerformanceSpan.measure<void>(
        'source.search',
        () => throw actionError,
        sink: sink,
      ),
      throwsA(same(actionError)),
    );

    expect(sink.records, hasLength(1));
    expect(sink.records.single.outcome, PerformanceOutcome.failure);
  });

  test('records bounded structured metrics without content fields', () {
    final sink = _CapturingSink();
    final span = PerformanceSpan.start(
      'model.generate',
      sink: sink,
      projectHash: List<String>.filled(64, 'a').join(),
      cacheResult: PerformanceCacheResult.hit,
      thermalState: PerformanceThermalState.warm,
      provider: 'ollama',
      modelExactId: 'qwen2.5-coder:7b',
      modelDigest: 'sha256:abcdef1234567890',
      role: 'executor',
      taskClass: 'mechanical_dart_edit',
    );

    final record = span.finish(
      inputTokenCount: 120,
      outputTokenCount: 15,
      firstTokenLatency: const Duration(milliseconds: 12),
      totalModelLatency: const Duration(milliseconds: 30),
      modelCalls: 1,
      toolCalls: 2,
    );

    expect(sink.records, <PerformanceSpanRecord>[record]);
    expect(record.projectHash, List<String>.filled(64, 'a').join());
    expect(record.cacheResult, PerformanceCacheResult.hit);
    expect(record.inputTokenCount, 120);
    expect(record.duration.isNegative, isFalse);
  });

  test('rejects arbitrary text in machine-label fields', () {
    expect(
      () => PerformanceSpanRecord(
        operation: 'search user prompt contents',
        startedAt: DateTime.now(),
        duration: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(
      () => PerformanceSpanRecord(
        operation: 'source.search\nsecret',
        startedAt: DateTime.now(),
        duration: Duration.zero,
      ),
      throwsArgumentError,
    );
  });

  test('a span can only be finished once', () {
    final span = PerformanceSpan.start('source.search');
    span.finish();

    expect(span.finish, throwsStateError);
  });
}
