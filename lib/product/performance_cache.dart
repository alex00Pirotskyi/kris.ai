import 'dart:async';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'performance_spans.dart';

enum CacheDatabaseStartupMode { cold, warm, recovered, memoryFallback }

final class CacheDatabaseDiagnostics {
  const CacheDatabaseDiagnostics({
    required this.schemaVersion,
    required this.databasePath,
    required this.persistent,
    required this.startupMode,
    required this.startupDuration,
    required this.onDiskBytes,
    required this.lastRebuildAt,
    required this.performanceSpanRows,
    required this.generationRows,
    required this.droppedPerformanceWrites,
    required this.degraded,
    this.startupFailureType,
  });

  final int schemaVersion;
  final String databasePath;
  final bool persistent;
  final CacheDatabaseStartupMode startupMode;
  final Duration startupDuration;
  final int onDiskBytes;
  final DateTime? lastRebuildAt;
  final int performanceSpanRows;
  final int generationRows;
  final int droppedPerformanceWrites;
  final bool degraded;
  final String? startupFailureType;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'databasePath': databasePath,
        'persistent': persistent,
        'startupMode': startupMode.name,
        'startupDurationMicroseconds': startupDuration.inMicroseconds,
        'onDiskBytes': onDiskBytes,
        'lastRebuildAt': lastRebuildAt?.toUtc().toIso8601String(),
        'performanceSpanRows': performanceSpanRows,
        'generationRows': generationRows,
        'droppedPerformanceWrites': droppedPerformanceWrites,
        'degraded': degraded,
        'startupFailureType': startupFailureType,
      };
}

final class RebuildableCacheDatabase implements PerformanceSpanSink {
  RebuildableCacheDatabase._({
    required Database database,
    required this.databaseFile,
    required this.persistent,
    required this.startupMode,
    required this.startupDuration,
    required this.maxPerformanceSpanRows,
    required this.startupFailureType,
  }) : _database = database;

  static const int currentSchemaVersion = 1;
  static const int _maintenanceInterval = 128;
  static const int _performanceBatchSize = 64;
  static const Duration _performanceFlushDelay = Duration(seconds: 2);
  static final RegExp _generationNamespacePattern =
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:\-]*$');
  static final RegExp _hexHashPattern = RegExp(r'^[A-Fa-f0-9]+$');
  static const List<int> _sqliteHeader = <int>[
    0x53,
    0x51,
    0x4c,
    0x69,
    0x74,
    0x65,
    0x20,
    0x66,
    0x6f,
    0x72,
    0x6d,
    0x61,
    0x74,
    0x20,
    0x33,
    0x00,
  ];

  final Database _database;
  final File databaseFile;
  final bool persistent;
  final CacheDatabaseStartupMode startupMode;
  final Duration startupDuration;
  final int maxPerformanceSpanRows;
  final String? startupFailureType;
  final List<PerformanceSpanRecord> _pendingPerformanceSpans =
      <PerformanceSpanRecord>[];
  Timer? _performanceFlushTimer;
  int _writesSinceMaintenance = 0;
  int _droppedPerformanceWrites = 0;
  bool _degraded = false;
  bool _closed = false;

  static Future<RebuildableCacheDatabase> open(
    Directory cacheDirectory, {
    int maxPerformanceSpanRows = 20000,
  }) async {
    if (maxPerformanceSpanRows <= 0) {
      throw ArgumentError.value(
        maxPerformanceSpanRows,
        'maxPerformanceSpanRows',
        'must be positive',
      );
    }
    final stopwatch = Stopwatch()..start();
    final databaseFile = File(
      '${cacheDirectory.path}${Platform.pathSeparator}cache.sqlite3',
    );
    var hadPersistentState = false;
    try {
      await cacheDirectory.create(recursive: true);
      final existedBeforeOpen = await databaseFile.exists();
      if (existedBeforeOpen) {
        hadPersistentState = await databaseFile.length() > 0;
      }
      if (hadPersistentState && await _hasInvalidSqliteHeader(databaseFile)) {
        throw const _CacheRebuildRequired('cache_header_invalid');
      }
      final database = _openPersistentDatabase(databaseFile);
      stopwatch.stop();
      return RebuildableCacheDatabase._(
        database: database,
        databaseFile: databaseFile,
        persistent: true,
        startupMode: hadPersistentState
            ? CacheDatabaseStartupMode.warm
            : CacheDatabaseStartupMode.cold,
        startupDuration: stopwatch.elapsed,
        maxPerformanceSpanRows: maxPerformanceSpanRows,
        startupFailureType: null,
      );
    } on _CacheRebuildRequired catch (error) {
      await _quarantinePersistentFiles(databaseFile);
      try {
        final database = _openPersistentDatabase(databaseFile);
        stopwatch.stop();
        return RebuildableCacheDatabase._(
          database: database,
          databaseFile: databaseFile,
          persistent: true,
          startupMode: CacheDatabaseStartupMode.recovered,
          startupDuration: stopwatch.elapsed,
          maxPerformanceSpanRows: maxPerformanceSpanRows,
          startupFailureType: error.code,
        );
      } catch (rebuildError) {
        return _openMemoryFallback(
          databaseFile: databaseFile,
          stopwatch: stopwatch,
          maxPerformanceSpanRows: maxPerformanceSpanRows,
          failure: rebuildError,
        );
      }
    } catch (error) {
      return _openMemoryFallback(
        databaseFile: databaseFile,
        stopwatch: stopwatch,
        maxPerformanceSpanRows: maxPerformanceSpanRows,
        failure: error,
      );
    }
  }

  static RebuildableCacheDatabase _openMemoryFallback({
    required File databaseFile,
    required Stopwatch stopwatch,
    required int maxPerformanceSpanRows,
    required Object failure,
  }) {
    final database = sqlite3.openInMemory();
    _configure(database, persistent: false);
    _createSchema(database);
    stopwatch.stop();
    return RebuildableCacheDatabase._(
      database: database,
      databaseFile: databaseFile,
      persistent: false,
      startupMode: CacheDatabaseStartupMode.memoryFallback,
      startupDuration: stopwatch.elapsed,
      maxPerformanceSpanRows: maxPerformanceSpanRows,
      startupFailureType: failure.runtimeType.toString(),
    );
  }

  static Database _openPersistentDatabase(File databaseFile) {
    final database = sqlite3.open(databaseFile.path);
    try {
      database.execute('PRAGMA busy_timeout = 5000');
      _verifyIntegrity(database);
      final schemaVersion = _schemaVersion(database);
      if (schemaVersion == 0) {
        final userTables = _asInt(
          database
              .select(
                "SELECT COUNT(*) AS value FROM sqlite_master "
                "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .first['value'],
        );
        if (userTables != 0) {
          throw const _CacheRebuildRequired(
            'cache_unversioned_schema_present',
          );
        }
      } else if (schemaVersion != currentSchemaVersion) {
        throw _CacheRebuildRequired(
          'cache_schema_unsupported_v$schemaVersion',
        );
      }
      _configure(database, persistent: true);
      if (schemaVersion == 0) {
        _createSchema(database);
      }
      _validateSchema(database);
      return database;
    } catch (_) {
      database.dispose();
      rethrow;
    }
  }

  static void _configure(Database database, {required bool persistent}) {
    database.execute('PRAGMA foreign_keys = ON');
    if (persistent) {
      database.execute('PRAGMA journal_mode = WAL');
      database.execute('PRAGMA synchronous = NORMAL');
      database.execute('PRAGMA journal_size_limit = 16777216');
      database.execute('PRAGMA wal_autocheckpoint = 1000');
    }
    database.execute('PRAGMA busy_timeout = 5000');
    database.execute('PRAGMA temp_store = MEMORY');
    database.execute('PRAGMA cache_size = -8192');
  }

  static void _verifyIntegrity(Database database) {
    try {
      final rows = database.select('PRAGMA quick_check(1)');
      final result = rows.isEmpty ? '' : rows.first.values.first.toString();
      if (result != 'ok') {
        throw const _CacheRebuildRequired('cache_integrity_check_failed');
      }
    } on SqliteException catch (error) {
      if (error.resultCode == 11 || error.resultCode == 26) {
        throw const _CacheRebuildRequired('cache_integrity_check_failed');
      }
      rethrow;
    }
  }

  static void _createSchema(Database database) {
    _transaction<void>(database, () {
      database.execute('''
CREATE TABLE cache_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
) WITHOUT ROWID
''');
      database.execute('''
CREATE TABLE cache_generations (
  namespace TEXT NOT NULL,
  project_hash TEXT NOT NULL DEFAULT '',
  generation INTEGER NOT NULL CHECK(generation >= 0),
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(namespace, project_hash)
) WITHOUT ROWID
''');
      database.execute('''
CREATE TABLE performance_spans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  operation TEXT NOT NULL,
  started_at_ms INTEGER NOT NULL,
  duration_us INTEGER NOT NULL CHECK(duration_us >= 0),
  outcome TEXT NOT NULL,
  project_hash TEXT,
  cache_result TEXT NOT NULL,
  thermal_state TEXT NOT NULL,
  item_count INTEGER,
  bytes_considered INTEGER,
  candidate_count INTEGER,
  input_tokens INTEGER,
  output_tokens INTEGER,
  first_token_latency_us INTEGER,
  total_model_latency_us INTEGER,
  provider TEXT,
  model_exact_id TEXT,
  model_digest TEXT,
  role TEXT,
  task_class TEXT,
  tool_calls INTEGER,
  model_calls INTEGER,
  persistence_duration_us INTEGER,
  verification_duration_us INTEGER,
  process_startup_duration_us INTEGER,
  browser_startup_duration_us INTEGER,
  analyzer_duration_us INTEGER,
  index_update_duration_us INTEGER,
  index_query_duration_us INTEGER,
  knowledge_retrieval_duration_us INTEGER,
  created_at_ms INTEGER NOT NULL
)
''');
      database.execute('''
CREATE INDEX performance_spans_operation_started_idx
ON performance_spans(operation, started_at_ms DESC)
''');
      database.execute('''
CREATE INDEX performance_spans_project_started_idx
ON performance_spans(project_hash, started_at_ms DESC)
WHERE project_hash IS NOT NULL
''');
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      database.execute(
        'INSERT INTO cache_metadata(key, value, updated_at_ms) '
        'VALUES (?, ?, ?)',
        <Object?>['schema_revision', 'wave_a.v1', now],
      );
      database.execute(
        'INSERT INTO cache_metadata(key, value, updated_at_ms) '
        'VALUES (?, ?, ?)',
        <Object?>['last_rebuild_at_ms', now.toString(), now],
      );
      database.execute('PRAGMA user_version = $currentSchemaVersion');
    });
  }

  static void _validateSchema(Database database) {
    const requiredTables = <String>{
      'cache_metadata',
      'cache_generations',
      'performance_spans',
    };
    final actual = database
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .map((row) => row['name']?.toString() ?? '')
        .toSet();
    if (!actual.containsAll(requiredTables)) {
      throw const _CacheRebuildRequired('cache_schema_incomplete');
    }
    final revision = database.select(
      "SELECT value FROM cache_metadata WHERE key = 'schema_revision'",
    );
    if (revision.isEmpty || revision.first['value'] != 'wave_a.v1') {
      throw const _CacheRebuildRequired('cache_schema_revision_mismatch');
    }
    final rebuildMetadata = database.select(
      "SELECT value FROM cache_metadata WHERE key = 'last_rebuild_at_ms'",
    );
    if (rebuildMetadata.isEmpty ||
        _asInt(rebuildMetadata.first['value']) <= 0) {
      throw const _CacheRebuildRequired('cache_rebuild_metadata_missing');
    }
  }

  static int _schemaVersion(Database database) {
    final rows = database.select('PRAGMA user_version');
    return rows.isEmpty ? 0 : _asInt(rows.first.values.first);
  }

  static T _transaction<T>(Database database, T Function() action) {
    database.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      database.execute('COMMIT');
      return result;
    } catch (_) {
      try {
        database.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  void recordPerformanceSpan(PerformanceSpanRecord record) {
    if (_closed || _degraded) {
      _droppedPerformanceWrites++;
      return;
    }
    try {
      _pendingPerformanceSpans.add(record);
      if (_pendingPerformanceSpans.length >= _performanceBatchSize) {
        _performanceFlushTimer?.cancel();
        _performanceFlushTimer = null;
        _flushPerformanceSpans();
      } else {
        _performanceFlushTimer ??= Timer(
          _performanceFlushDelay,
          _flushPerformanceSpans,
        );
      }
    } catch (_) {
      _droppedPerformanceWrites++;
    }
  }

  void _flushPerformanceSpans() {
    _performanceFlushTimer?.cancel();
    _performanceFlushTimer = null;
    if (_closed) return;
    if (_degraded) {
      _markDegraded();
      return;
    }
    if (_pendingPerformanceSpans.isEmpty) return;
    final batch = List<PerformanceSpanRecord>.of(_pendingPerformanceSpans);
    final createdAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    try {
      _transaction<void>(_database, () {
        for (final record in batch) {
          _database.execute(
            _insertPerformanceSpanSql,
            _spanValues(record, createdAtMs),
          );
        }
      });
      _pendingPerformanceSpans.removeRange(0, batch.length);
      _writesSinceMaintenance += batch.length;
      if (_writesSinceMaintenance >= _maintenanceInterval) {
        _trimPerformanceSpans();
        _writesSinceMaintenance = 0;
      }
    } catch (_) {
      _markDegraded();
    }
  }

  void _markDegraded() {
    _performanceFlushTimer?.cancel();
    _performanceFlushTimer = null;
    _droppedPerformanceWrites += _pendingPerformanceSpans.length;
    _pendingPerformanceSpans.clear();
    _degraded = true;
  }

  static const String _insertPerformanceSpanSql =
      '''INSERT INTO performance_spans(
  operation, started_at_ms, duration_us, outcome, project_hash,
  cache_result, thermal_state, item_count, bytes_considered,
  candidate_count, input_tokens, output_tokens, first_token_latency_us,
  total_model_latency_us, provider, model_exact_id, model_digest, role,
  task_class, tool_calls, model_calls, persistence_duration_us,
  verification_duration_us, process_startup_duration_us,
  browser_startup_duration_us, analyzer_duration_us, index_update_duration_us,
  index_query_duration_us, knowledge_retrieval_duration_us, created_at_ms
) VALUES (
  ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
  ?, ?, ?, ?, ?, ?
)''';

  static List<Object?> _spanValues(
    PerformanceSpanRecord record,
    int createdAtMs,
  ) {
    return <Object?>[
      record.operation,
      record.startedAt.millisecondsSinceEpoch,
      record.duration.inMicroseconds,
      record.outcome.name,
      record.projectHash,
      record.cacheResult.name,
      record.thermalState.name,
      record.itemCount,
      record.bytesConsidered,
      record.candidateCount,
      record.inputTokenCount,
      record.outputTokenCount,
      record.firstTokenLatency?.inMicroseconds,
      record.totalModelLatency?.inMicroseconds,
      record.provider,
      record.modelExactId,
      record.modelDigest,
      record.role,
      record.taskClass,
      record.toolCalls,
      record.modelCalls,
      record.persistenceDuration?.inMicroseconds,
      record.verificationDuration?.inMicroseconds,
      record.processStartupDuration?.inMicroseconds,
      record.browserStartupDuration?.inMicroseconds,
      record.analyzerDuration?.inMicroseconds,
      record.indexUpdateDuration?.inMicroseconds,
      record.indexQueryDuration?.inMicroseconds,
      record.knowledgeRetrievalDuration?.inMicroseconds,
      createdAtMs,
    ];
  }

  int generation(String namespace, {String projectHash = ''}) {
    _validateGenerationKey(namespace, projectHash);
    if (_closed || _degraded) return 0;
    try {
      final rows = _database.select(
        'SELECT generation FROM cache_generations '
        'WHERE namespace = ? AND project_hash = ?',
        <Object?>[namespace, projectHash],
      );
      return rows.isEmpty ? 0 : _asInt(rows.first['generation']);
    } catch (_) {
      _markDegraded();
      return 0;
    }
  }

  int advanceGeneration(String namespace, {String projectHash = ''}) {
    _validateGenerationKey(namespace, projectHash);
    if (_closed || _degraded) return 0;
    try {
      return _transaction<int>(_database, () {
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        _database.execute(
          '''INSERT INTO cache_generations(
  namespace, project_hash, generation, updated_at_ms
) VALUES (?, ?, 1, ?)
ON CONFLICT(namespace, project_hash) DO UPDATE SET
  generation = cache_generations.generation + 1,
  updated_at_ms = excluded.updated_at_ms''',
          <Object?>[namespace, projectHash, now],
        );
        final rows = _database.select(
          'SELECT generation FROM cache_generations '
          'WHERE namespace = ? AND project_hash = ?',
          <Object?>[namespace, projectHash],
        );
        return rows.isEmpty ? 0 : _asInt(rows.first['generation']);
      });
    } catch (_) {
      _markDegraded();
      return 0;
    }
  }

  static void _validateGenerationKey(String namespace, String projectHash) {
    if (namespace.isEmpty ||
        namespace.length > 96 ||
        !_generationNamespacePattern.hasMatch(namespace)) {
      throw ArgumentError.value(
          namespace, 'namespace', 'invalid cache namespace');
    }
    if (projectHash.isNotEmpty &&
        (projectHash.length < 16 ||
            projectHash.length > 128 ||
            !_hexHashPattern.hasMatch(projectHash))) {
      throw ArgumentError.value(
        projectHash,
        'projectHash',
        'must be empty or a hexadecimal hash',
      );
    }
  }

  void _trimPerformanceSpans() {
    _database.execute(
      '''DELETE FROM performance_spans
WHERE id <= COALESCE(
  (
    SELECT id FROM performance_spans
    ORDER BY id DESC
    LIMIT 1 OFFSET ?
  ),
  -1
)''',
      <Object?>[maxPerformanceSpanRows],
    );
  }

  Future<CacheDatabaseDiagnostics> diagnostics() async {
    if (!_closed && !_degraded) {
      _flushPerformanceSpans();
    }
    DateTime? lastRebuildAt;
    var performanceSpanRows = 0;
    var generationRows = 0;
    if (!_closed && !_degraded) {
      try {
        final rebuildRows = _database.select(
          "SELECT value FROM cache_metadata "
          "WHERE key = 'last_rebuild_at_ms'",
        );
        if (rebuildRows.isNotEmpty) {
          final milliseconds = _asInt(rebuildRows.first['value']);
          if (milliseconds > 0) {
            lastRebuildAt = DateTime.fromMillisecondsSinceEpoch(
              milliseconds,
              isUtc: true,
            );
          }
        }
        performanceSpanRows = _asInt(
          _database
              .select('SELECT COUNT(*) AS value FROM performance_spans')
              .first['value'],
        );
        generationRows = _asInt(
          _database
              .select('SELECT COUNT(*) AS value FROM cache_generations')
              .first['value'],
        );
      } catch (_) {
        _markDegraded();
      }
    }
    var onDiskBytes = 0;
    if (persistent) {
      for (final suffix in const <String>['', '-wal', '-shm']) {
        final candidate = File('${databaseFile.path}$suffix');
        try {
          if (await candidate.exists()) {
            onDiskBytes += await candidate.length();
          }
        } catch (_) {}
      }
    }
    return CacheDatabaseDiagnostics(
      schemaVersion: currentSchemaVersion,
      databasePath: persistent ? databaseFile.path : ':memory:',
      persistent: persistent,
      startupMode: startupMode,
      startupDuration: startupDuration,
      onDiskBytes: onDiskBytes,
      lastRebuildAt: lastRebuildAt,
      performanceSpanRows: performanceSpanRows,
      generationRows: generationRows,
      droppedPerformanceWrites: _droppedPerformanceWrites,
      degraded: _degraded,
      startupFailureType: startupFailureType,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _performanceFlushTimer?.cancel();
    _performanceFlushTimer = null;
    if (!_degraded) {
      _flushPerformanceSpans();
    }
    if (!_degraded) {
      try {
        _trimPerformanceSpans();
      } catch (_) {}
    }
    _closed = true;
    try {
      _database.dispose();
    } catch (_) {
      _degraded = true;
    }
  }

  static Future<void> discardPersistentCache(Directory cacheDirectory) async {
    final databaseFile = File(
      '${cacheDirectory.path}${Platform.pathSeparator}cache.sqlite3',
    );
    for (final suffix in const <String>['', '-wal', '-shm']) {
      final candidate = File('${databaseFile.path}$suffix');
      try {
        if (await candidate.exists()) {
          await candidate.delete();
        }
      } catch (_) {}
    }
  }

  static Future<bool> _hasInvalidSqliteHeader(File file) async {
    final length = await file.length();
    if (length == 0) return false;
    if (length < _sqliteHeader.length) return true;
    final reader = await file.open();
    try {
      final bytes = await reader.read(_sqliteHeader.length);
      if (bytes.length != _sqliteHeader.length) return true;
      for (var index = 0; index < _sqliteHeader.length; index++) {
        if (bytes[index] != _sqliteHeader[index]) return true;
      }
      return false;
    } finally {
      await reader.close();
    }
  }

  static Future<void> _quarantinePersistentFiles(File databaseFile) async {
    final suffix = '.invalid.'
        '${DateTime.now().toUtc().microsecondsSinceEpoch.toString()}';
    for (final sidecar in const <String>['', '-wal', '-shm']) {
      final candidate = File('${databaseFile.path}$sidecar');
      try {
        if (!await candidate.exists()) continue;
        await candidate.rename('${candidate.path}$suffix');
      } catch (_) {
        try {
          if (await candidate.exists()) {
            await candidate.delete();
          }
        } catch (_) {}
      }
    }
  }
}

final class _CacheRebuildRequired implements Exception {
  const _CacheRebuildRequired(this.code);

  final String code;

  @override
  String toString() => code;
}
