import 'dart:async';

enum PerformanceCacheResult { notApplicable, hit, miss }

enum PerformanceThermalState { unknown, cold, warm }

enum PerformanceOutcome { success, failure, cancelled }

abstract interface class PerformanceSpanSink {
  void recordPerformanceSpan(PerformanceSpanRecord record);
}

final class NoopPerformanceSpanSink implements PerformanceSpanSink {
  const NoopPerformanceSpanSink();

  @override
  void recordPerformanceSpan(PerformanceSpanRecord record) {}
}

final class PerformanceSpanRecord {
  static final RegExp _machineLabelPattern =
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/@+\-]*$');
  static final RegExp _hexHashPattern = RegExp(r'^[A-Fa-f0-9]+$');

  PerformanceSpanRecord({
    required this.operation,
    required DateTime startedAt,
    required this.duration,
    this.projectHash,
    this.cacheResult = PerformanceCacheResult.notApplicable,
    this.thermalState = PerformanceThermalState.unknown,
    this.itemCount,
    this.bytesConsidered,
    this.candidateCount,
    this.inputTokenCount,
    this.outputTokenCount,
    this.firstTokenLatency,
    this.totalModelLatency,
    this.provider,
    this.modelExactId,
    this.modelDigest,
    this.role,
    this.taskClass,
    this.toolCalls,
    this.modelCalls,
    this.persistenceDuration,
    this.verificationDuration,
    this.processStartupDuration,
    this.browserStartupDuration,
    this.analyzerDuration,
    this.indexUpdateDuration,
    this.indexQueryDuration,
    this.knowledgeRetrievalDuration,
    this.outcome = PerformanceOutcome.success,
  }) : startedAt = startedAt.toUtc() {
    _validateLabel('operation', operation, maxLength: 128, isRequired: true);
    _validateHash('projectHash', projectHash);
    _validateLabel('provider', provider, maxLength: 96);
    _validateLabel('modelExactId', modelExactId, maxLength: 256);
    _validateLabel('modelDigest', modelDigest, maxLength: 256);
    _validateLabel('role', role, maxLength: 96);
    _validateLabel('taskClass', taskClass, maxLength: 128);
    _validateDuration('duration', duration, isRequired: true);
    _validateDuration('firstTokenLatency', firstTokenLatency);
    _validateDuration('totalModelLatency', totalModelLatency);
    _validateDuration('persistenceDuration', persistenceDuration);
    _validateDuration('verificationDuration', verificationDuration);
    _validateDuration('processStartupDuration', processStartupDuration);
    _validateDuration('browserStartupDuration', browserStartupDuration);
    _validateDuration('analyzerDuration', analyzerDuration);
    _validateDuration('indexUpdateDuration', indexUpdateDuration);
    _validateDuration('indexQueryDuration', indexQueryDuration);
    _validateDuration(
      'knowledgeRetrievalDuration',
      knowledgeRetrievalDuration,
    );
    _validateCount('itemCount', itemCount);
    _validateCount('bytesConsidered', bytesConsidered);
    _validateCount('candidateCount', candidateCount);
    _validateCount('inputTokenCount', inputTokenCount);
    _validateCount('outputTokenCount', outputTokenCount);
    _validateCount('toolCalls', toolCalls);
    _validateCount('modelCalls', modelCalls);
  }

  final String operation;
  final DateTime startedAt;
  final Duration duration;
  final String? projectHash;
  final PerformanceCacheResult cacheResult;
  final PerformanceThermalState thermalState;
  final int? itemCount;
  final int? bytesConsidered;
  final int? candidateCount;
  final int? inputTokenCount;
  final int? outputTokenCount;
  final Duration? firstTokenLatency;
  final Duration? totalModelLatency;
  final String? provider;
  final String? modelExactId;
  final String? modelDigest;
  final String? role;
  final String? taskClass;
  final int? toolCalls;
  final int? modelCalls;
  final Duration? persistenceDuration;
  final Duration? verificationDuration;
  final Duration? processStartupDuration;
  final Duration? browserStartupDuration;
  final Duration? analyzerDuration;
  final Duration? indexUpdateDuration;
  final Duration? indexQueryDuration;
  final Duration? knowledgeRetrievalDuration;
  final PerformanceOutcome outcome;

  static void _validateLabel(
    String field,
    String? value, {
    required int maxLength,
    bool isRequired = false,
  }) {
    if (value == null || value.isEmpty) {
      if (isRequired) {
        throw ArgumentError.value(value, field, 'must not be empty');
      }
      return;
    }
    if (value.length > maxLength || !_machineLabelPattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        field,
        'must be a bounded machine label, not arbitrary text',
      );
    }
  }

  static void _validateHash(String field, String? value) {
    if (value == null || value.isEmpty) return;
    if (value.length < 16 ||
        value.length > 128 ||
        !_hexHashPattern.hasMatch(value)) {
      throw ArgumentError.value(value, field, 'must be a hexadecimal hash');
    }
  }

  static void _validateCount(String field, int? value) {
    if (value != null && value < 0) {
      throw ArgumentError.value(value, field, 'must not be negative');
    }
  }

  static void _validateDuration(
    String field,
    Duration? value, {
    bool isRequired = false,
  }) {
    if (value == null) {
      if (isRequired) {
        throw ArgumentError.value(value, field, 'must not be null');
      }
      return;
    }
    if (value.isNegative) {
      throw ArgumentError.value(value, field, 'must not be negative');
    }
  }
}

final class PerformanceSpan {
  PerformanceSpan._({
    required this.operation,
    required this.startedAt,
    required this.projectHash,
    required this.cacheResult,
    required this.thermalState,
    required this.provider,
    required this.modelExactId,
    required this.modelDigest,
    required this.role,
    required this.taskClass,
    required PerformanceSpanSink sink,
  })  : _sink = sink,
        _stopwatch = Stopwatch()..start();

  factory PerformanceSpan.start(
    String operation, {
    PerformanceSpanSink sink = const NoopPerformanceSpanSink(),
    DateTime? startedAt,
    String? projectHash,
    PerformanceCacheResult cacheResult = PerformanceCacheResult.notApplicable,
    PerformanceThermalState thermalState = PerformanceThermalState.unknown,
    String? provider,
    String? modelExactId,
    String? modelDigest,
    String? role,
    String? taskClass,
  }) {
    return PerformanceSpan._(
      operation: operation,
      startedAt: (startedAt ?? DateTime.now()).toUtc(),
      projectHash: projectHash,
      cacheResult: cacheResult,
      thermalState: thermalState,
      provider: provider,
      modelExactId: modelExactId,
      modelDigest: modelDigest,
      role: role,
      taskClass: taskClass,
      sink: sink,
    );
  }

  final String operation;
  final DateTime startedAt;
  final String? projectHash;
  final PerformanceCacheResult cacheResult;
  final PerformanceThermalState thermalState;
  final String? provider;
  final String? modelExactId;
  final String? modelDigest;
  final String? role;
  final String? taskClass;
  final PerformanceSpanSink _sink;
  final Stopwatch _stopwatch;
  bool _finished = false;

  PerformanceSpanRecord finish({
    int? itemCount,
    int? bytesConsidered,
    int? candidateCount,
    int? inputTokenCount,
    int? outputTokenCount,
    Duration? firstTokenLatency,
    Duration? totalModelLatency,
    int? toolCalls,
    int? modelCalls,
    Duration? persistenceDuration,
    Duration? verificationDuration,
    Duration? processStartupDuration,
    Duration? browserStartupDuration,
    Duration? analyzerDuration,
    Duration? indexUpdateDuration,
    Duration? indexQueryDuration,
    Duration? knowledgeRetrievalDuration,
    PerformanceOutcome outcome = PerformanceOutcome.success,
  }) {
    if (_finished) {
      throw StateError('performance_span_already_finished');
    }
    _finished = true;
    _stopwatch.stop();
    final elapsed = _stopwatch.elapsed;
    final record = PerformanceSpanRecord(
      operation: operation,
      startedAt: startedAt,
      duration: elapsed,
      projectHash: projectHash,
      cacheResult: cacheResult,
      thermalState: thermalState,
      itemCount: itemCount,
      bytesConsidered: bytesConsidered,
      candidateCount: candidateCount,
      inputTokenCount: inputTokenCount,
      outputTokenCount: outputTokenCount,
      firstTokenLatency: firstTokenLatency,
      totalModelLatency: totalModelLatency,
      provider: provider,
      modelExactId: modelExactId,
      modelDigest: modelDigest,
      role: role,
      taskClass: taskClass,
      toolCalls: toolCalls,
      modelCalls: modelCalls,
      persistenceDuration: persistenceDuration,
      verificationDuration: verificationDuration,
      processStartupDuration: processStartupDuration,
      browserStartupDuration: browserStartupDuration,
      analyzerDuration: analyzerDuration,
      indexUpdateDuration: indexUpdateDuration ??
          (operation == 'source.index.update' ? elapsed : null),
      indexQueryDuration:
          indexQueryDuration ?? (operation == 'source.search' ? elapsed : null),
      knowledgeRetrievalDuration: knowledgeRetrievalDuration,
      outcome: outcome,
    );
    try {
      _sink.recordPerformanceSpan(record);
    } catch (_) {}
    return record;
  }

  static Future<T> measure<T>(
    String operation,
    FutureOr<T> Function() action, {
    PerformanceSpanSink sink = const NoopPerformanceSpanSink(),
    String? projectHash,
    PerformanceCacheResult cacheResult = PerformanceCacheResult.notApplicable,
    PerformanceThermalState thermalState = PerformanceThermalState.unknown,
    String? provider,
    String? modelExactId,
    String? modelDigest,
    String? role,
    String? taskClass,
  }) async {
    final span = PerformanceSpan.start(
      operation,
      sink: sink,
      projectHash: projectHash,
      cacheResult: cacheResult,
      thermalState: thermalState,
      provider: provider,
      modelExactId: modelExactId,
      modelDigest: modelDigest,
      role: role,
      taskClass: taskClass,
    );
    try {
      final value = await action();
      try {
        span.finish();
      } catch (_) {}
      return value;
    } catch (error, stackTrace) {
      try {
        span.finish(outcome: PerformanceOutcome.failure);
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
