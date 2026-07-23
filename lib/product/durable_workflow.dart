import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'crypto_utils.dart';
import 'domain.dart';
import 'generated/workflow_migrations.g.dart';
import 'repository.dart';

class WorkflowStorageException implements Exception {
  const WorkflowStorageException(
    this.code,
    this.message, {
    this.details = const <String, dynamic>{},
  });

  final String code;
  final String message;
  final Map<String, dynamic> details;

  @override
  String toString() => '$code: $message';
}

class WorkflowStoredEvent {
  const WorkflowStoredEvent({
    required this.sequence,
    required this.id,
    required this.type,
    required this.correlationId,
    required this.timestamp,
    required this.data,
    this.runId,
    this.causationId,
    this.idempotencyKey,
    this.stateVersion,
  });

  final int sequence;
  final String id;
  final String type;
  final String correlationId;
  final String? runId;
  final DateTime timestamp;
  final Map<String, dynamic> data;
  final String? causationId;
  final String? idempotencyKey;
  final int? stateVersion;

  EventEnvelope toEnvelope() => EventEnvelope(
        sequence: sequence,
        id: id,
        type: type,
        correlationId: correlationId,
        timestamp: timestamp,
        data: data,
      );
}

enum IdempotencyClaimKind {
  acquired,
  replay,
  busy,
  terminalFailure,
  effectRecorded,
  manualRecovery,
}

class IdempotencyClaim {
  const IdempotencyClaim({
    required this.kind,
    required this.key,
    required this.executionGeneration,
    this.result,
    this.errorClass,
    this.errorCode,
    this.retryability,
    this.effect,
    this.recoveredLease = false,
  });

  final IdempotencyClaimKind kind;
  final String key;
  final int executionGeneration;
  final Map<String, dynamic>? result;
  final String? errorClass;
  final String? errorCode;
  final String? retryability;
  final Map<String, dynamic>? effect;
  final bool recoveredLease;
}

class WorkflowCheckpoint {
  const WorkflowCheckpoint({
    required this.id,
    required this.runId,
    required this.kind,
    required this.state,
    required this.stateSha256,
    required this.createdAt,
    this.workItemId,
    this.eventSequence,
  });

  final String id;
  final String runId;
  final String? workItemId;
  final String kind;
  final int? eventSequence;
  final Map<String, dynamic> state;
  final String stateSha256;
  final DateTime createdAt;
}

class WorkflowIntegrityReport {
  const WorkflowIntegrityReport({
    required this.ok,
    required this.schemaVersion,
    required this.integrityResult,
    required this.foreignKeyViolations,
    required this.invalidRunHashes,
    required this.invalidEventHashes,
    required this.projectionMismatches,
  });

  final bool ok;
  final int schemaVersion;
  final String integrityResult;
  final int foreignKeyViolations;
  final int invalidRunHashes;
  final int invalidEventHashes;
  final int projectionMismatches;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ok': ok,
        'schemaVersion': schemaVersion,
        'expectedSchemaVersion': generatedWorkflowSchemaVersion,
        'migrationDigest': generatedWorkflowMigrationDigest,
        'integrityResult': integrityResult,
        'foreignKeyViolations': foreignKeyViolations,
        'invalidRunHashes': invalidRunHashes,
        'invalidEventHashes': invalidEventHashes,
        'projectionMismatches': projectionMismatches,
      };
}

class DurableWorkflowStore {
  DurableWorkflowStore._({
    required Database database,
    required this.databaseFile,
    required this.migrationBackupDirectory,
  }) : _database = database;

  final Database _database;
  final File databaseFile;
  final Directory migrationBackupDirectory;
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  static Future<DurableWorkflowStore> open({
    required File databaseFile,
    required Directory migrationBackupDirectory,
    Map<String, File> legacyCollections = const <String, File>{},
    Map<String, File> legacyDocuments = const <String, File>{},
    File? legacyRunsFile,
    File? legacyEventsFile,
  }) async {
    await databaseFile.parent.create(recursive: true);
    await migrationBackupDirectory.create(recursive: true);
    final databaseExistedBeforeOpen = await databaseFile.exists();
    final databaseLengthBeforeOpen = databaseExistedBeforeOpen
        ? await databaseFile.length()
        : 0;
    var legacySourcePresent = false;
    for (final source in <File?>[
      ...legacyCollections.values,
      ...legacyDocuments.values,
      legacyRunsFile,
      legacyEventsFile,
    ]) {
      if (source != null && await source.exists()) {
        legacySourcePresent = true;
        break;
      }
    }

    final database = sqlite3.open(databaseFile.path);
    final store = DurableWorkflowStore._(
      database: database,
      databaseFile: databaseFile,
      migrationBackupDirectory: migrationBackupDirectory,
    );
    File? preStartupBackup;
    try {
      store._configure();
      preStartupBackup = await store._backupDatabaseBeforeMigration(
        force: databaseExistedBeforeOpen && legacySourcePresent,
      );
      store._applyMigrations();
      store._recordPreMigrationBackup(preStartupBackup);
      await store._importLegacyState(
        collections: legacyCollections,
        documents: legacyDocuments,
        runsFile: legacyRunsFile,
        eventsFile: legacyEventsFile,
      );
      final report = await store.verifyIntegrity();
      if (!report.ok) {
        throw WorkflowStorageException(
          'workflow_integrity_failed',
          'The durable workflow database did not pass startup integrity checks.',
          details: report.toJson(),
        );
      }
      return store;
    } catch (error, stackTrace) {
      database.dispose();
      try {
        if (databaseExistedBeforeOpen && databaseLengthBeforeOpen == 0) {
          await _replaceWithEmptyDatabaseFile(databaseFile);
        } else if (preStartupBackup != null) {
          await _restoreDatabaseBackup(
            databaseFile: databaseFile,
            backup: preStartupBackup,
          );
        } else if (!databaseExistedBeforeOpen) {
          await _deleteDatabaseFiles(databaseFile);
        }
      } catch (recoveryError, recoveryStackTrace) {
        Error.throwWithStackTrace(
          WorkflowStorageException(
            'workflow_startup_rollback_failed',
            'Workflow startup failed and the pre-startup database state could not be restored.',
            details: <String, dynamic>{
              'startupError': '$error',
              'rollbackError': '$recoveryError',
              'rollbackStack': '$recoveryStackTrace',
            },
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<File?> _backupDatabaseBeforeMigration({bool force = false}) async {
    final currentVersion = schemaVersion;
    if (currentVersion >= generatedWorkflowSchemaVersion && !force) {
      return null;
    }
    final userTableCount = _asInt(
      _database.select(
        "SELECT COUNT(*) AS value FROM sqlite_master "
        "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      ).first['value'],
    );
    if (currentVersion == 0 && userTableCount == 0 && !force) {
      return null;
    }
    final checkpoint = _database.select('PRAGMA wal_checkpoint(FULL)');
    if (checkpoint.isNotEmpty && _asInt(checkpoint.first['busy']) != 0) {
      throw const WorkflowStorageException(
        'workflow_migration_busy',
        'A workflow schema migration cannot start while another SQLite writer is active.',
      );
    }
    final sourceBytes = await databaseFile.readAsBytes();
    final sourceSha = Sha256.hex(sourceBytes);
    final backup = File(
      '${migrationBackupDirectory.path}${Platform.pathSeparator}'
      'workflow.schema-v$currentVersion-to-v$generatedWorkflowSchemaVersion.'
      '${sourceSha.substring(0, 16)}.sqlite3',
    );
    if (!await backup.exists()) {
      await backup.writeAsBytes(sourceBytes, flush: true);
    }
    final backupSha = Sha256.hex(await backup.readAsBytes());
    if (!constantTimeEquals(sourceSha, backupSha)) {
      throw const WorkflowStorageException(
        'workflow_migration_backup_invalid',
        'The pre-migration SQLite backup does not match the source database.',
      );
    }
    return backup;
  }

  void _recordPreMigrationBackup(File? backup) {
    if (backup == null) {
      return;
    }
    _database.execute(
      '''INSERT INTO workflow_metadata(key, value, updated_at)
         VALUES ('last_pre_migration_backup', ?, ?)
         ON CONFLICT(key) DO UPDATE SET
           value = excluded.value, updated_at = excluded.updated_at''',
      <Object?>[backup.path, _now()],
    );
  }

  static Future<void> _restoreDatabaseBackup({
    required File databaseFile,
    required File backup,
  }) async {
    final temporary = File('${databaseFile.path}.restore-${newId('tmp')}');
    await backup.copy(temporary.path);
    await _deleteDatabaseFiles(databaseFile);
    await temporary.rename(databaseFile.path);
  }

  static Future<void> _replaceWithEmptyDatabaseFile(File databaseFile) async {
    await _deleteDatabaseFiles(databaseFile);
    await databaseFile.writeAsBytes(const <int>[], flush: true);
  }

  static Future<void> _deleteDatabaseFiles(File databaseFile) async {
    for (final suffix in const <String>['', '-wal', '-shm']) {
      final candidate = File('${databaseFile.path}$suffix');
      if (await candidate.exists()) {
        await candidate.delete();
      }
    }
  }

  static String deriveIdempotencyKey({
    required String runId,
    required String workItemId,
    required int attempt,
    required String logicalOperation,
    required String normalizedArgumentsSha256,
  }) {
    return Sha256.text(canonicalJson(<String, dynamic>{
      'runId': runId,
      'workItemId': workItemId,
      'attempt': attempt,
      'logicalOperation': logicalOperation,
      'normalizedArgumentsSha256': normalizedArgumentsSha256,
    }));
  }

  int get schemaVersion {
    final rows = _database.select('PRAGMA user_version');
    if (rows.isEmpty) {
      return 0;
    }
    return _asInt(rows.first.values.first);
  }

  Future<T> _serialize<T>(T Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) {
      if (_disposed) {
        throw const WorkflowStorageException(
          'workflow_store_closed',
          'The durable workflow store is closed.',
        );
      }
      try {
        completer.complete(action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  T _transaction<T>(T Function() action) {
    _database.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      _database.execute('COMMIT');
      return result;
    } catch (_) {
      try {
        _database.execute('ROLLBACK');
      } catch (_) {
        // Preserve the original failure.
      }
      rethrow;
    }
  }

  void _configure() {
    _database.execute('PRAGMA foreign_keys = ON');
    _database.execute('PRAGMA journal_mode = WAL');
    _database.execute('PRAGMA synchronous = FULL');
    _database.execute('PRAGMA busy_timeout = 5000');
    _database.execute('PRAGMA wal_autocheckpoint = 1000');
    _database.execute('PRAGMA temp_store = MEMORY');
  }

  void _applyMigrations() {
    _database.execute('''
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  applied_at TEXT NOT NULL
) WITHOUT ROWID
''');
    final applied = <int, String>{
      for (final row in _database.select(
        'SELECT version, sha256 FROM schema_migrations ORDER BY version',
      ))
        _asInt(row['version']): row['sha256']?.toString() ?? '',
    };
    for (final migration in generatedWorkflowMigrations) {
      final prior = applied[migration.version];
      if (prior != null) {
        if (!constantTimeEquals(prior, migration.sha256)) {
          throw WorkflowStorageException(
            'workflow_migration_drift',
            'Applied workflow migration ${migration.version} no longer matches its reviewed SQL.',
            details: <String, dynamic>{
              'version': migration.version,
              'name': migration.name,
              'appliedSha256': prior,
              'sourceSha256': migration.sha256,
            },
          );
        }
        continue;
      }
      _transaction<void>(() {
        _database.execute(migration.sql);
        _database.execute(
          'INSERT INTO schema_migrations(version, name, sha256, applied_at) VALUES (?, ?, ?, ?)',
          <Object?>[
            migration.version,
            migration.name,
            migration.sha256,
            _now(),
          ],
        );
        _database.execute('PRAGMA user_version = ${migration.version}');
      });
    }
    if (schemaVersion != generatedWorkflowSchemaVersion) {
      throw WorkflowStorageException(
        'workflow_schema_version_mismatch',
        'Workflow schema version $schemaVersion does not match generated version $generatedWorkflowSchemaVersion.',
      );
    }
    _database.execute(
      '''INSERT INTO workflow_metadata(key, value, updated_at)
         VALUES ('migration_digest', ?, ?)
         ON CONFLICT(key) DO UPDATE SET
           value = excluded.value, updated_at = excluded.updated_at
         WHERE workflow_metadata.value <> excluded.value''',
      <Object?>[generatedWorkflowMigrationDigest, _now()],
    );
  }

  Future<void> _importLegacyState({
    required Map<String, File> collections,
    required Map<String, File> documents,
    File? runsFile,
    File? eventsFile,
  }) async {
    for (final entry in collections.entries) {
      await _importLegacyCollection(entry.key, entry.value);
    }
    for (final entry in documents.entries) {
      await _importLegacyDocument(entry.key, entry.value);
    }
    if (eventsFile != null) {
      await _importLegacyEvents(eventsFile);
    }
    if (runsFile != null) {
      await _importLegacyRuns(runsFile);
    }
  }

  Future<void> _importLegacyCollection(String collection, File file) async {
    if (!await file.exists()) {
      return;
    }
    final bytes = await file.readAsBytes();
    final sourceSha = Sha256.hex(bytes);
    final sourceKey = 'collection:$collection:$sourceSha';
    if (_migrationImported(sourceKey)) {
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (error) {
      throw WorkflowStorageException(
        'legacy_state_corrupt',
        'Legacy collection ${file.path} contains invalid JSON.',
        details: <String, dynamic>{'error': '$error'},
      );
    }
    if (decoded is! List) {
      throw WorkflowStorageException(
        'legacy_state_shape_invalid',
        'Legacy collection ${file.path} must contain a JSON array.',
      );
    }
    final decodedItems = decoded;
    final backup = await _backupLegacy(file, sourceSha);
    var imported = 0;
    await _serialize<void>(() {
      _transaction<void>(() {
        for (final item in decodedItems.whereType<Map>()) {
          final value = <String, dynamic>{
            for (final entry in item.entries) entry.key.toString(): entry.value,
          };
          final id = value['id']?.toString() ?? '';
          if (id.isEmpty) {
            continue;
          }
          _putEntityUnlocked(collection, id, value, preserveExisting: true);
          imported++;
        }
        _recordMigrationImportUnlocked(
          sourceKey: sourceKey,
          file: file,
          sourceSha256: sourceSha,
          backupPath: backup.path,
          importedRecords: imported,
          details: <String, dynamic>{'kind': 'collection', 'collection': collection},
        );
      });
    });
  }

  Future<void> _importLegacyDocument(String key, File file) async {
    if (!await file.exists()) {
      return;
    }
    final bytes = await file.readAsBytes();
    final sourceSha = Sha256.hex(bytes);
    final sourceKey = 'document:$key:$sourceSha';
    if (_migrationImported(sourceKey)) {
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (error) {
      throw WorkflowStorageException(
        'legacy_state_corrupt',
        'Legacy document ${file.path} contains invalid JSON.',
        details: <String, dynamic>{'error': '$error'},
      );
    }
    final backup = await _backupLegacy(file, sourceSha);
    await _serialize<void>(() {
      _transaction<void>(() {
        _writeDocumentUnlocked(key, decoded, preserveExisting: true);
        _recordMigrationImportUnlocked(
          sourceKey: sourceKey,
          file: file,
          sourceSha256: sourceSha,
          backupPath: backup.path,
          importedRecords: 1,
          details: <String, dynamic>{'kind': 'document', 'key': key},
        );
      });
    });
  }

  Future<void> _importLegacyEvents(File file) async {
    if (!await file.exists()) {
      return;
    }
    final bytes = await file.readAsBytes();
    final sourceSha = Sha256.hex(bytes);
    final sourceKey = 'events:$sourceSha';
    if (_migrationImported(sourceKey)) {
      return;
    }
    final backup = await _backupLegacy(file, sourceSha);
    final events = <EventEnvelope>[];
    for (final line in utf8.decode(bytes, allowMalformed: true).split('\n')) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          events.add(EventEnvelope.fromJson(<String, dynamic>{
            for (final entry in decoded.entries)
              entry.key.toString(): entry.value,
          }));
        }
      } catch (_) {
        // Preserve valid surrounding records and record the bounded count below.
      }
    }
    await _serialize<void>(() {
      _transaction<void>(() {
        var imported = 0;
        for (final event in events) {
          final payload = canonicalJson(event.data);
          final runExists = _database.select(
            'SELECT 1 FROM runs WHERE id = ? LIMIT 1',
            <Object?>[event.correlationId],
          ).isNotEmpty;
          _database.execute(
            '''INSERT OR IGNORE INTO run_events(
                 sequence, event_id, correlation_id, run_id, type, timestamp,
                 payload_json, payload_sha256
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
            <Object?>[
              event.sequence <= 0 ? null : event.sequence,
              event.id,
              event.correlationId,
              runExists ? event.correlationId : null,
              event.type,
              event.timestamp.toUtc().toIso8601String(),
              payload,
              Sha256.text(payload),
            ],
          );
          if (_database.updatedRows > 0) {
            imported++;
          }
        }
        _recordMigrationImportUnlocked(
          sourceKey: sourceKey,
          file: file,
          sourceSha256: sourceSha,
          backupPath: backup.path,
          importedRecords: imported,
          details: <String, dynamic>{
            'kind': 'events',
            'parsedRecords': events.length,
          },
        );
      });
    });
  }

  Future<void> _importLegacyRuns(File file) async {
    if (!await file.exists()) {
      return;
    }
    final bytes = await file.readAsBytes();
    final sourceSha = Sha256.hex(bytes);
    final sourceKey = 'runs:$sourceSha';
    if (_migrationImported(sourceKey)) {
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (error) {
      throw WorkflowStorageException(
        'legacy_runs_corrupt',
        'Legacy run state contains invalid JSON.',
        details: <String, dynamic>{'error': '$error'},
      );
    }
    if (decoded is! List) {
      throw const WorkflowStorageException(
        'legacy_runs_shape_invalid',
        'Legacy runs must be stored as a JSON array.',
      );
    }
    final decodedRuns = decoded;
    final backup = await _backupLegacy(file, sourceSha);
    final runs = decodedRuns
        .whereType<Map>()
        .map((item) => RunRecord.fromJson(<String, dynamic>{
              for (final entry in item.entries)
                entry.key.toString(): entry.value,
            }))
        .toList(growable: false);
    await _serialize<void>(() {
      _transaction<void>(() {
        var imported = 0;
        for (final run in runs) {
          final exists = _database.select(
            'SELECT 1 FROM runs WHERE id = ? LIMIT 1',
            <Object?>[run.id],
          ).isNotEmpty;
          if (exists) {
            continue;
          }
          _saveRunUnlocked(run, eventType: 'legacy.run_imported');
          imported++;
        }
        _recordMigrationImportUnlocked(
          sourceKey: sourceKey,
          file: file,
          sourceSha256: sourceSha,
          backupPath: backup.path,
          importedRecords: imported,
          details: <String, dynamic>{'kind': 'runs', 'parsedRecords': runs.length},
        );
      });
    });
  }

  bool _migrationImported(String sourceKey) {
    return _database.select(
      'SELECT 1 FROM migration_imports WHERE source_key = ? LIMIT 1',
      <Object?>[sourceKey],
    ).isNotEmpty;
  }

  Future<File> _backupLegacy(File file, String sourceSha) async {
    final safeName = file.uri.pathSegments.last.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final backup = File(
      '${migrationBackupDirectory.path}${Platform.pathSeparator}'
      '${safeName}.${sourceSha.substring(0, 16)}.bak',
    );
    if (!await backup.exists()) {
      await file.copy(backup.path);
    }
    final backupSha = Sha256.hex(await backup.readAsBytes());
    if (!constantTimeEquals(backupSha, sourceSha)) {
      throw WorkflowStorageException(
        'migration_backup_invalid',
        'The legacy-state backup did not preserve the source bytes.',
        details: <String, dynamic>{
          'sourcePathHash': Sha256.text(file.absolute.path),
          'sourceSha256': sourceSha,
          'backupSha256': backupSha,
        },
      );
    }
    return backup;
  }

  void _recordMigrationImportUnlocked({
    required String sourceKey,
    required File file,
    required String sourceSha256,
    required String backupPath,
    required int importedRecords,
    required Map<String, dynamic> details,
  }) {
    _database.execute(
      '''INSERT INTO migration_imports(
           source_key, source_path_hash, source_sha256, backup_path,
           imported_records, imported_at, details_json
         ) VALUES (?, ?, ?, ?, ?, ?, ?)''',
      <Object?>[
        sourceKey,
        Sha256.text(file.absolute.path),
        sourceSha256,
        backupPath,
        importedRecords,
        _now(),
        canonicalJson(details),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> listEntities(String collection) =>
      _serialize<List<Map<String, dynamic>>>(() {
        return _database
            .select(
              '''SELECT record_json FROM entity_records
                 WHERE collection = ? ORDER BY updated_at DESC, id''',
              <Object?>[collection],
            )
            .map((row) => _decodeMap(row['record_json']))
            .toList(growable: false);
      });

  Future<Map<String, dynamic>?> getEntity(String collection, String id) =>
      _serialize<Map<String, dynamic>?>(() {
        final rows = _database.select(
          '''SELECT record_json FROM entity_records
             WHERE collection = ? AND id = ? LIMIT 1''',
          <Object?>[collection, id],
        );
        return rows.isEmpty ? null : _decodeMap(rows.first['record_json']);
      });

  Future<void> putEntity(
    String collection,
    String id,
    Map<String, dynamic> value,
  ) =>
      _serialize<void>(() {
        _transaction<void>(() {
          _putEntityUnlocked(collection, id, value);
        });
      });

  Future<void> putEntities(
    String collection,
    Iterable<MapEntry<String, Map<String, dynamic>>> values,
  ) =>
      _serialize<void>(() {
        _transaction<void>(() {
          for (final entry in values) {
            _putEntityUnlocked(collection, entry.key, entry.value);
          }
        });
      });

  void _putEntityUnlocked(
    String collection,
    String id,
    Map<String, dynamic> value, {
    bool preserveExisting = false,
  }) {
    final json = canonicalJson(value);
    final sha = Sha256.text(json);
    final existing = _database.select(
      '''SELECT record_sha256, created_at FROM entity_records
         WHERE collection = ? AND id = ? LIMIT 1''',
      <Object?>[collection, id],
    );
    if (existing.isNotEmpty) {
      if (preserveExisting ||
          constantTimeEquals(existing.first['record_sha256']?.toString() ?? '', sha)) {
        return;
      }
    }
    final now = _now();
    _database.execute(
      '''INSERT INTO entity_records(
           collection, id, record_json, record_sha256, created_at, updated_at
         ) VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(collection, id) DO UPDATE SET
           record_json = excluded.record_json,
           record_sha256 = excluded.record_sha256,
           updated_at = excluded.updated_at''',
      <Object?>[
        collection,
        id,
        json,
        sha,
        existing.isEmpty ? now : existing.first['created_at'],
        now,
      ],
    );
  }

  Future<void> removeEntity(String collection, String id) =>
      _serialize<void>(() {
        _transaction<void>(() {
          _database.execute(
            'DELETE FROM entity_records WHERE collection = ? AND id = ?',
            <Object?>[collection, id],
          );
        });
      });

  Future<void> replaceEntities(
    String collection,
    Iterable<MapEntry<String, Map<String, dynamic>>> values,
  ) =>
      _serialize<void>(() {
        _transaction<void>(() {
          _database.execute(
            'DELETE FROM entity_records WHERE collection = ?',
            <Object?>[collection],
          );
          for (final entry in values) {
            _putEntityUnlocked(collection, entry.key, entry.value);
          }
        });
      });

  Future<Object?> readDocument(String key, {Object? fallback}) =>
      _serialize<Object?>(() {
        final rows = _database.select(
          'SELECT document_json FROM documents WHERE key = ? LIMIT 1',
          <Object?>[key],
        );
        if (rows.isEmpty) {
          return fallback;
        }
        try {
          return jsonDecode(rows.first['document_json']?.toString() ?? 'null');
        } on FormatException {
          throw WorkflowStorageException(
            'workflow_document_corrupt',
            'SQLite document $key contains invalid JSON.',
          );
        }
      });

  Future<void> writeDocument(String key, Object? value) =>
      _serialize<void>(() {
        _transaction<void>(() {
          _writeDocumentUnlocked(key, value);
        });
      });

  void _writeDocumentUnlocked(
    String key,
    Object? value, {
    bool preserveExisting = false,
  }) {
    final json = canonicalJson(value);
    final sha = Sha256.text(json);
    final existing = _database.select(
      'SELECT document_sha256 FROM documents WHERE key = ? LIMIT 1',
      <Object?>[key],
    );
    if (existing.isNotEmpty) {
      if (preserveExisting ||
          constantTimeEquals(existing.first['document_sha256']?.toString() ?? '', sha)) {
        return;
      }
    }
    _database.execute(
      '''INSERT INTO documents(key, document_json, document_sha256, updated_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET
           document_json = excluded.document_json,
           document_sha256 = excluded.document_sha256,
           updated_at = excluded.updated_at''',
      <Object?>[key, json, sha, _now()],
    );
  }

  Future<List<RunRecord>> listRuns() => _serialize<List<RunRecord>>(() {
        return _database
            .select('SELECT run_json FROM runs ORDER BY updated_at DESC, id')
            .map((row) => RunRecord.fromJson(_decodeMap(row['run_json'])))
            .toList(growable: false);
      });

  Future<RunRecord?> getRun(String id) => _serialize<RunRecord?>(() {
        final rows = _database.select(
          'SELECT run_json FROM runs WHERE id = ? LIMIT 1',
          <Object?>[id],
        );
        return rows.isEmpty
            ? null
            : RunRecord.fromJson(_decodeMap(rows.first['run_json']));
      });

  Future<void> saveRun(
    RunRecord run, {
    String eventType = 'run.snapshot',
  }) =>
      _serialize<void>(() {
        _transaction<void>(() {
          _saveRunUnlocked(run, eventType: eventType);
        });
      });

  Future<void> saveRuns(Iterable<RunRecord> runs) => _serialize<void>(() {
        _transaction<void>(() {
          for (final run in runs) {
            _saveRunUnlocked(run);
          }
        });
      });

  void _saveRunUnlocked(
    RunRecord run, {
    String eventType = 'run.snapshot',
  }) {
    final runJson = canonicalJson(run.toJson());
    final snapshotSha = Sha256.text(runJson);
    final existing = _database.select(
      'SELECT state, state_version, snapshot_sha256 FROM runs WHERE id = ? LIMIT 1',
      <Object?>[run.id],
    );
    if (existing.isNotEmpty &&
        constantTimeEquals(
          existing.first['snapshot_sha256']?.toString() ?? '',
          snapshotSha,
        )) {
      return;
    }
    final priorState = existing.isEmpty
        ? null
        : existing.first['state']?.toString();
    final stateVersion = existing.isEmpty
        ? 1
        : _asInt(existing.first['state_version']) + 1;
    _database.execute(
      '''INSERT INTO runs(
           id, project_id, command_id, source_run_id, state, state_version,
           run_json, snapshot_sha256, created_at, updated_at, completed_at, failure
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           project_id = excluded.project_id,
           command_id = excluded.command_id,
           source_run_id = excluded.source_run_id,
           state = excluded.state,
           state_version = excluded.state_version,
           run_json = excluded.run_json,
           snapshot_sha256 = excluded.snapshot_sha256,
           updated_at = excluded.updated_at,
           completed_at = excluded.completed_at,
           failure = excluded.failure''',
      <Object?>[
        run.id,
        run.command.contract.projectId,
        run.command.id,
        run.sourceRunId,
        run.state.name,
        stateVersion,
        runJson,
        snapshotSha,
        run.createdAt.toUtc().toIso8601String(),
        run.updatedAt.toUtc().toIso8601String(),
        run.completedAt?.toUtc().toIso8601String(),
        run.failure,
      ],
    );
    _appendEventUnlocked(
      id: newId('event'),
      type: eventType,
      correlationId: run.id,
      runId: run.id,
      timestamp: run.updatedAt,
      data: <String, dynamic>{
        'run': run.toJson(),
        'state': run.state.name,
        'previousState': priorState,
        'stateVersion': stateVersion,
        'snapshotSha256': snapshotSha,
      },
      stateVersion: stateVersion,
    );
  }

  Future<void> removeRun(String id) => _serialize<void>(() {
        _transaction<void>(() {
          final rows = _database.select(
            'SELECT state_version FROM runs WHERE id = ? LIMIT 1',
            <Object?>[id],
          );
          if (rows.isEmpty) {
            return;
          }
          final version = _asInt(rows.first['state_version']) + 1;
          _appendEventUnlocked(
            id: newId('event'),
            type: 'run.deleted',
            correlationId: id,
            runId: id,
            timestamp: DateTime.now().toUtc(),
            data: <String, dynamic>{'runId': id, 'stateVersion': version},
            stateVersion: version,
          );
          _database.execute('DELETE FROM runs WHERE id = ?', <Object?>[id]);
          _database.execute('DELETE FROM run_leases WHERE run_id = ?', <Object?>[id]);
        });
      });

  Future<void> replaceRuns(Iterable<RunRecord> values) => _serialize<void>(() {
        _transaction<void>(() {
          final replacement = <String, RunRecord>{
            for (final run in values) run.id: run,
          };
          final currentIds = _database
              .select('SELECT id FROM runs')
              .map((row) => row['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toList(growable: false);
          for (final id in currentIds) {
            if (!replacement.containsKey(id)) {
              _appendEventUnlocked(
                id: newId('event'),
                type: 'run.deleted',
                correlationId: id,
                runId: id,
                timestamp: DateTime.now().toUtc(),
                data: <String, dynamic>{'runId': id},
              );
              _database.execute('DELETE FROM runs WHERE id = ?', <Object?>[id]);
            }
          }
          for (final run in replacement.values) {
            _saveRunUnlocked(run);
          }
        });
      });

  Future<WorkflowStoredEvent> appendEvent({
    required String id,
    required String type,
    required String correlationId,
    required DateTime timestamp,
    required Map<String, dynamic> data,
    String? runId,
    String? causationId,
    String? idempotencyKey,
    int? stateVersion,
  }) =>
      _serialize<WorkflowStoredEvent>(() {
        return _transaction<WorkflowStoredEvent>(() {
          return _appendEventUnlocked(
            id: id,
            type: type,
            correlationId: correlationId,
            timestamp: timestamp,
            data: data,
            runId: runId,
            causationId: causationId,
            idempotencyKey: idempotencyKey,
            stateVersion: stateVersion,
          );
        });
      });

  WorkflowStoredEvent _appendEventUnlocked({
    required String id,
    required String type,
    required String correlationId,
    required DateTime timestamp,
    required Map<String, dynamic> data,
    String? runId,
    String? causationId,
    String? idempotencyKey,
    int? stateVersion,
  }) {
    var resolvedRunId = runId;
    if (resolvedRunId == null &&
        _database.select(
          'SELECT 1 FROM runs WHERE id = ? LIMIT 1',
          <Object?>[correlationId],
        ).isNotEmpty) {
      resolvedRunId = correlationId;
    }
    final payload = canonicalJson(data);
    _database.execute(
      '''INSERT INTO run_events(
           event_id, correlation_id, run_id, type, timestamp, payload_json,
           payload_sha256, causation_id, idempotency_key, state_version
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      <Object?>[
        id,
        correlationId,
        resolvedRunId,
        type,
        timestamp.toUtc().toIso8601String(),
        payload,
        Sha256.text(payload),
        causationId,
        idempotencyKey,
        stateVersion,
      ],
    );
    final sequence = _asInt(
      _database.select('SELECT last_insert_rowid() AS value').first['value'],
    );
    return WorkflowStoredEvent(
      sequence: sequence,
      id: id,
      type: type,
      correlationId: correlationId,
      runId: resolvedRunId,
      timestamp: timestamp.toUtc(),
      data: data,
      causationId: causationId,
      idempotencyKey: idempotencyKey,
      stateVersion: stateVersion,
    );
  }

  Future<int> lastEventSequence() => _serialize<int>(() {
        final rows = _database.select(
          'SELECT COALESCE(MAX(sequence), 0) AS value FROM run_events',
        );
        return rows.isEmpty ? 0 : _asInt(rows.first['value']);
      });

  Future<List<WorkflowStoredEvent>> eventsAfter(
    int sequence, {
    int limit = 500,
  }) =>
      _serialize<List<WorkflowStoredEvent>>(() {
        return _database
            .select(
              '''SELECT sequence, event_id, correlation_id, run_id, type,
                        timestamp, payload_json, causation_id, idempotency_key,
                        state_version
                 FROM run_events WHERE sequence > ?
                 ORDER BY sequence LIMIT ?''',
              <Object?>[sequence, limit.clamp(1, 5000).toInt()],
            )
            .map(_eventFromRow)
            .toList(growable: false);
      });

  Future<List<WorkflowStoredEvent>> eventsForRun(
    String runId, {
    int limit = 5000,
  }) =>
      _serialize<List<WorkflowStoredEvent>>(() {
        return _database
            .select(
              '''SELECT sequence, event_id, correlation_id, run_id, type,
                        timestamp, payload_json, causation_id, idempotency_key,
                        state_version
                 FROM run_events WHERE run_id = ? OR correlation_id = ?
                 ORDER BY sequence LIMIT ?''',
              <Object?>[runId, runId, limit.clamp(1, 50000).toInt()],
            )
            .map(_eventFromRow)
            .toList(growable: false);
      });

  WorkflowStoredEvent _eventFromRow(Row row) => WorkflowStoredEvent(
        sequence: _asInt(row['sequence']),
        id: row['event_id']?.toString() ?? '',
        type: row['type']?.toString() ?? 'unknown',
        correlationId: row['correlation_id']?.toString() ?? '',
        runId: row['run_id']?.toString(),
        timestamp: _parseDate(row['timestamp']),
        data: _decodeMap(row['payload_json']),
        causationId: row['causation_id']?.toString(),
        idempotencyKey: row['idempotency_key']?.toString(),
        stateVersion: row['state_version'] == null
            ? null
            : _asInt(row['state_version']),
      );

  Future<WorkflowCheckpoint> createCheckpoint({
    required String runId,
    required String kind,
    required Map<String, dynamic> state,
    String? workItemId,
    int? eventSequence,
  }) =>
      _serialize<WorkflowCheckpoint>(() {
        return _transaction<WorkflowCheckpoint>(() {
          final id = newId('checkpoint');
          final json = canonicalJson(state);
          final sha = Sha256.text(json);
          final now = DateTime.now().toUtc();
          _database.execute(
            '''INSERT OR IGNORE INTO checkpoints(
                 id, run_id, work_item_id, kind, event_sequence,
                 state_json, state_sha256, created_at
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
            <Object?>[
              id,
              runId,
              workItemId,
              kind,
              eventSequence,
              json,
              sha,
              now.toIso8601String(),
            ],
          );
          return WorkflowCheckpoint(
            id: id,
            runId: runId,
            workItemId: workItemId,
            kind: kind,
            eventSequence: eventSequence,
            state: state,
            stateSha256: sha,
            createdAt: now,
          );
        });
      });

  Future<WorkflowCheckpoint?> latestCheckpoint(
    String runId, {
    String? kind,
  }) =>
      _serialize<WorkflowCheckpoint?>(() {
        final rows = _database.select(
          kind == null
              ? '''SELECT * FROM checkpoints WHERE run_id = ?
                   ORDER BY created_at DESC, id DESC LIMIT 1'''
              : '''SELECT * FROM checkpoints WHERE run_id = ? AND kind = ?
                   ORDER BY created_at DESC, id DESC LIMIT 1''',
          kind == null ? <Object?>[runId] : <Object?>[runId, kind],
        );
        if (rows.isEmpty) {
          return null;
        }
        final row = rows.first;
        return WorkflowCheckpoint(
          id: row['id']?.toString() ?? '',
          runId: row['run_id']?.toString() ?? runId,
          workItemId: row['work_item_id']?.toString(),
          kind: row['kind']?.toString() ?? '',
          eventSequence: row['event_sequence'] == null
              ? null
              : _asInt(row['event_sequence']),
          state: _decodeMap(row['state_json']),
          stateSha256: row['state_sha256']?.toString() ?? '',
          createdAt: _parseDate(row['created_at']),
        );
      });

  Future<void> recordTaskAttempt({
    required String runId,
    required String workItemId,
    required int attempt,
    required String state,
    String? errorClass,
    String? errorCode,
    String? retryDisposition,
    DateTime? startedAt,
    DateTime? completedAt,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) =>
      _serialize<void>(() {
        _transaction<void>(() {
          final now = _now();
          final detailJson = canonicalJson(details);
          _database.execute(
            '''INSERT INTO task_attempts(
                 run_id, work_item_id, attempt, state, error_class, error_code,
                 retry_disposition, started_at, updated_at, completed_at,
                 details_json, details_sha256
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(run_id, work_item_id, attempt) DO UPDATE SET
                 state = excluded.state,
                 error_class = excluded.error_class,
                 error_code = excluded.error_code,
                 retry_disposition = excluded.retry_disposition,
                 updated_at = excluded.updated_at,
                 completed_at = excluded.completed_at,
                 details_json = excluded.details_json,
                 details_sha256 = excluded.details_sha256''',
            <Object?>[
              runId,
              workItemId,
              attempt,
              state,
              errorClass,
              errorCode,
              retryDisposition,
              (startedAt ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
              now,
              completedAt?.toUtc().toIso8601String(),
              detailJson,
              Sha256.text(detailJson),
            ],
          );
        });
      });

  Future<IdempotencyClaim> claimOperation({
    required String key,
    required String runId,
    required String workItemId,
    required int attempt,
    required String operation,
    required String normalizedArgumentsSha256,
    required String ownerId,
    Duration lease = const Duration(minutes: 5),
    bool allowLeaseTakeover = true,
  }) =>
      _serialize<IdempotencyClaim>(() {
        return _transaction<IdempotencyClaim>(() {
          final now = DateTime.now().toUtc();
          final expires = now.add(lease);
          final rows = _database.select(
            'SELECT * FROM idempotency_records WHERE idempotency_key = ? LIMIT 1',
            <Object?>[key],
          );
          if (rows.isEmpty) {
            _database.execute(
              '''INSERT INTO idempotency_records(
                   idempotency_key, run_id, work_item_id, attempt, operation,
                   normalized_arguments_sha256, status, lease_owner,
                   lease_expires_at, execution_generation, created_at, updated_at
                 ) VALUES (?, ?, ?, ?, ?, ?, 'in_progress', ?, ?, 1, ?, ?)''',
              <Object?>[
                key,
                runId,
                workItemId,
                attempt,
                operation,
                normalizedArgumentsSha256,
                ownerId,
                expires.toIso8601String(),
                now.toIso8601String(),
                now.toIso8601String(),
              ],
            );
            return IdempotencyClaim(
              kind: IdempotencyClaimKind.acquired,
              key: key,
              executionGeneration: 1,
            );
          }
          final row = rows.first;
          final storedHash = row['normalized_arguments_sha256']?.toString() ?? '';
          if (!constantTimeEquals(storedHash, normalizedArgumentsSha256)) {
            throw WorkflowStorageException(
              'idempotency_key_collision',
              'An idempotency key was reused with different normalized arguments.',
              details: <String, dynamic>{
                'key': key,
                'operation': operation,
                'storedArgumentsSha256': storedHash,
                'requestedArgumentsSha256': normalizedArgumentsSha256,
              },
            );
          }
          final generation = _asInt(row['execution_generation']);
          final status = row['status']?.toString() ?? '';
          if (status == 'completed') {
            return IdempotencyClaim(
              kind: IdempotencyClaimKind.replay,
              key: key,
              executionGeneration: generation,
              result: _decodeNullableMap(row['result_json']),
            );
          }
          if (status == 'failed') {
            final retryability = row['retryability']?.toString();
            if (retryability != 'transient' &&
                retryability != 'resource' &&
                retryability != 'state_conflict') {
              return IdempotencyClaim(
                kind: IdempotencyClaimKind.terminalFailure,
                key: key,
                executionGeneration: generation,
                errorClass: row['error_class']?.toString(),
                errorCode: row['error_code']?.toString(),
                retryability: retryability,
              );
            }
          }
          final leaseOwner = row['lease_owner']?.toString() ?? '';
          final leaseExpires = _parseDate(row['lease_expires_at']);
          // Do not steal a recorded effect from a live executor. A filesystem
          // mutation can become visible slightly before its handler persists
          // the final ToolResult; the active lease remains the authority until
          // that bounded window closes or the process actually disappears.
          if (status == 'in_progress' &&
              leaseOwner != ownerId &&
              leaseExpires.isAfter(now)) {
            return IdempotencyClaim(
              kind: IdempotencyClaimKind.busy,
              key: key,
              executionGeneration: generation,
            );
          }
          final effectRows = _database.select(
            '''SELECT record_json FROM compensation_records
               WHERE idempotency_key = ? AND status IN ('applied', 'committed')
               ORDER BY updated_at DESC LIMIT 1''',
            <Object?>[key],
          );
          if (effectRows.isNotEmpty) {
            final nextGeneration = generation + 1;
            _database.execute(
              '''UPDATE idempotency_records SET
                   status = 'in_progress', lease_owner = ?, lease_expires_at = ?,
                   execution_generation = ?, updated_at = ?, completed_at = NULL
                 WHERE idempotency_key = ?''',
              <Object?>[
                ownerId,
                expires.toIso8601String(),
                nextGeneration,
                now.toIso8601String(),
                key,
              ],
            );
            return IdempotencyClaim(
              kind: IdempotencyClaimKind.effectRecorded,
              key: key,
              executionGeneration: nextGeneration,
              effect: _decodeMap(effectRows.first['record_json']),
              recoveredLease: true,
            );
          }
          if (!allowLeaseTakeover && leaseOwner != ownerId) {
            return IdempotencyClaim(
              kind: IdempotencyClaimKind.manualRecovery,
              key: key,
              executionGeneration: generation,
            );
          }
          final nextGeneration = generation + 1;
          _database.execute(
            '''UPDATE idempotency_records SET
                 status = 'in_progress', lease_owner = ?, lease_expires_at = ?,
                 execution_generation = ?, result_json = NULL,
                 result_sha256 = NULL, error_class = NULL, error_code = NULL,
                 retryability = NULL, updated_at = ?, completed_at = NULL
               WHERE idempotency_key = ?''',
            <Object?>[
              ownerId,
              expires.toIso8601String(),
              nextGeneration,
              now.toIso8601String(),
              key,
            ],
          );
          return IdempotencyClaim(
            kind: IdempotencyClaimKind.acquired,
            key: key,
            executionGeneration: nextGeneration,
            recoveredLease: true,
          );
        });
      });

  Future<void> completeOperation({
    required String key,
    required String ownerId,
    required Map<String, dynamic> result,
  }) =>
      _serialize<void>(() {
        _transaction<void>(() {
          final rows = _database.select(
            'SELECT status, lease_owner, result_sha256 FROM idempotency_records WHERE idempotency_key = ? LIMIT 1',
            <Object?>[key],
          );
          if (rows.isEmpty) {
            throw const WorkflowStorageException(
              'idempotency_record_missing',
              'Cannot complete an operation that was not claimed.',
            );
          }
          final json = canonicalJson(result);
          final sha = Sha256.text(json);
          final row = rows.first;
          if (row['status']?.toString() == 'completed') {
            final prior = row['result_sha256']?.toString() ?? '';
            if (!constantTimeEquals(prior, sha)) {
              throw const WorkflowStorageException(
                'idempotency_result_conflict',
                'The completed idempotency result does not match the replayed result.',
              );
            }
            return;
          }
          if (row['lease_owner']?.toString() != ownerId) {
            throw const WorkflowStorageException(
              'idempotency_lease_lost',
              'The operation lease was lost before the result was persisted.',
            );
          }
          final now = _now();
          _database.execute(
            '''UPDATE idempotency_records SET
                 status = 'completed', result_json = ?, result_sha256 = ?,
                 updated_at = ?, completed_at = ?, error_class = NULL,
                 error_code = NULL, retryability = NULL
               WHERE idempotency_key = ?''',
            <Object?>[json, sha, now, now, key],
          );
          _appendEventUnlocked(
            id: newId('event'),
            type: 'operation.completed',
            correlationId: key,
            timestamp: DateTime.now().toUtc(),
            data: <String, dynamic>{
              'idempotencyKey': key,
              'resultSha256': sha,
            },
            idempotencyKey: key,
          );
        });
      });

  Future<void> failOperation({
    required String key,
    required String ownerId,
    required String errorClass,
    required String errorCode,
    required String retryability,
  }) =>
      _serialize<void>(() {
        _transaction<void>(() {
          final rows = _database.select(
            'SELECT status, lease_owner FROM idempotency_records WHERE idempotency_key = ? LIMIT 1',
            <Object?>[key],
          );
          if (rows.isEmpty || rows.first['status']?.toString() == 'completed') {
            return;
          }
          if (rows.first['lease_owner']?.toString() != ownerId) {
            return;
          }
          final now = _now();
          _database.execute(
            '''UPDATE idempotency_records SET
                 status = 'failed', error_class = ?, error_code = ?,
                 retryability = ?, lease_expires_at = ?, updated_at = ?,
                 completed_at = ? WHERE idempotency_key = ?''',
            <Object?>[
              errorClass,
              errorCode,
              retryability,
              now,
              now,
              now,
              key,
            ],
          );
          _appendEventUnlocked(
            id: newId('event'),
            type: 'operation.failed',
            correlationId: key,
            timestamp: DateTime.now().toUtc(),
            data: <String, dynamic>{
              'idempotencyKey': key,
              'errorClass': errorClass,
              'errorCode': errorCode,
              'retryability': retryability,
            },
            idempotencyKey: key,
          );
        });
      });

  Future<Map<String, dynamic>?> getModelCircuit({
    required String provider,
    required String model,
  }) =>
      _serialize<Map<String, dynamic>?>(() {
        final rows = _database.select(
          'SELECT * FROM model_circuit_breakers WHERE provider = ? AND model = ?',
          <Object?>[provider, model],
        );
        if (rows.isEmpty) return null;
        return <String, dynamic>{
          for (final entry in rows.first.entries) entry.key: entry.value,
        };
      });

  Future<void> upsertModelCircuit({
    required String provider,
    required String model,
    required String state,
    required int consecutiveFailures,
    required int timeoutFailures,
    required int malformedFailures,
    required int cooldownSeconds,
    DateTime? openedAt,
    DateTime? lastSuccessAt,
    DateTime? lastFailureAt,
  }) =>
      _serialize<void>(() {
        _transaction<void>(() {
          _database.execute(
            '''INSERT INTO model_circuit_breakers(
                 provider, model, state, consecutive_failures, timeout_failures,
                 malformed_failures, opened_at, cooldown_seconds,
                 last_success_at, last_failure_at, updated_at
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(provider, model) DO UPDATE SET
                 state=excluded.state,
                 consecutive_failures=excluded.consecutive_failures,
                 timeout_failures=excluded.timeout_failures,
                 malformed_failures=excluded.malformed_failures,
                 opened_at=excluded.opened_at,
                 cooldown_seconds=excluded.cooldown_seconds,
                 last_success_at=excluded.last_success_at,
                 last_failure_at=excluded.last_failure_at,
                 updated_at=excluded.updated_at''',
            <Object?>[
              provider,
              model,
              state,
              consecutiveFailures,
              timeoutFailures,
              malformedFailures,
              openedAt?.toUtc().toIso8601String(),
              cooldownSeconds,
              lastSuccessAt?.toUtc().toIso8601String(),
              lastFailureAt?.toUtc().toIso8601String(),
              _now(),
            ],
          );
        });
      });

  Future<void> appendModelRouteDecision({
    required String role,
    required String requestSha256,
    required Map<String, dynamic> decision,
    required bool approvalRequired,
    String? runId,
    String? workItemId,
    String? selectedProvider,
    String? selectedModel,
  }) =>
      _serialize<void>(() {
        _transaction<void>(() {
          final json = canonicalJson(decision);
          _database.execute(
            '''INSERT INTO model_route_decisions(
                 id, run_id, work_item_id, role, request_sha256,
                 decision_json, decision_sha256, selected_provider,
                 selected_model, approval_required, created_at
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
            <Object?>[
              newId('route'),
              runId,
              workItemId,
              role,
              requestSha256,
              json,
              Sha256.text(json),
              selectedProvider,
              selectedModel,
              approvalRequired ? 1 : 0,
              _now(),
            ],
          );
        });
      });

  Future<void> appendSemanticProgress({
    required String runId,
    required String workItemId,
    required int attempt,
    required int turn,
    required String beforeSha256,
    required String afterSha256,
    required Map<String, dynamic> delta,
    required bool semanticProgress,
    String? strategyAction,
  }) =>
      _serialize<void>(() {
        _transaction<void>(() {
          final json = canonicalJson(delta);
          _database.execute(
            '''INSERT INTO semantic_progress_records(
                 id, run_id, work_item_id, attempt, turn, before_sha256,
                 after_sha256, delta_json, delta_sha256, semantic_progress,
                 strategy_action, created_at
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
            <Object?>[
              newId('progress'),
              runId,
              workItemId,
              attempt,
              turn,
              beforeSha256,
              afterSha256,
              json,
              Sha256.text(json),
              semanticProgress ? 1 : 0,
              strategyAction,
              _now(),
            ],
          );
        });
      });

  Future<void> appendVerificationReport({
    required String runId,
    required String workItemId,
    required int attempt,
    required String evidenceSha256,
    required Map<String, dynamic> report,
    required bool passed,
  }) =>
      _serialize<void>(() {
        _transaction<void>(() {
          final json = canonicalJson(report);
          _database.execute(
            '''INSERT OR IGNORE INTO verification_reports(
                 id, run_id, work_item_id, attempt, verifier_role,
                 evidence_sha256, report_json, report_sha256, passed, created_at
               ) VALUES (?, ?, ?, ?, 'verifier', ?, ?, ?, ?, ?)''',
            <Object?>[
              newId('verification'),
              runId,
              workItemId,
              attempt,
              evidenceSha256,
              json,
              Sha256.text(json),
              passed ? 1 : 0,
              _now(),
            ],
          );
        });
      });

  Future<void> recordCompensation({
    required String runId,
    required String mutationId,
    required String operation,
    required String relativePath,
    required String status,
    required Map<String, dynamic> record,
    String? workItemId,
    String? idempotencyKey,
    String? beforeSha256,
    String? afterSha256,
    String? backupPath,
    Map<String, dynamic>? rollbackResult,
  }) =>
      _serialize<void>(() {
        _transaction<void>(() {
          final json = canonicalJson(record);
          final now = _now();
          _database.execute(
            '''INSERT INTO compensation_records(
                 id, run_id, work_item_id, idempotency_key, mutation_id,
                 operation, relative_path, before_sha256, after_sha256,
                 backup_path, status, record_json, record_sha256,
                 rollback_result_json, created_at, updated_at
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(run_id, mutation_id) DO UPDATE SET
                 work_item_id = COALESCE(excluded.work_item_id, compensation_records.work_item_id),
                 idempotency_key = COALESCE(excluded.idempotency_key, compensation_records.idempotency_key),
                 status = excluded.status,
                 record_json = excluded.record_json,
                 record_sha256 = excluded.record_sha256,
                 rollback_result_json = excluded.rollback_result_json,
                 updated_at = excluded.updated_at''',
            <Object?>[
              'compensation:$runId:$mutationId',
              runId,
              workItemId,
              idempotencyKey,
              mutationId,
              operation,
              relativePath,
              beforeSha256,
              afterSha256,
              backupPath,
              status,
              json,
              Sha256.text(json),
              rollbackResult == null ? null : canonicalJson(rollbackResult),
              now,
              now,
            ],
          );
        });
      });

  Future<bool> acquireRunLease({
    required String runId,
    required String ownerId,
    Duration lease = const Duration(minutes: 5),
  }) =>
      _serialize<bool>(() {
        return _transaction<bool>(() {
          final now = DateTime.now().toUtc();
          final rows = _database.select(
            'SELECT owner_id, expires_at FROM run_leases WHERE run_id = ? LIMIT 1',
            <Object?>[runId],
          );
          if (rows.isNotEmpty) {
            final owner = rows.first['owner_id']?.toString() ?? '';
            final expires = _parseDate(rows.first['expires_at']);
            if (owner != ownerId && expires.isAfter(now)) {
              return false;
            }
          }
          final expires = now.add(lease).toIso8601String();
          _database.execute(
            '''INSERT INTO run_leases(run_id, owner_id, acquired_at, renewed_at, expires_at)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(run_id) DO UPDATE SET
                 owner_id = excluded.owner_id,
                 acquired_at = CASE
                   WHEN run_leases.owner_id = excluded.owner_id THEN run_leases.acquired_at
                   ELSE excluded.acquired_at
                 END,
                 renewed_at = excluded.renewed_at,
                 expires_at = excluded.expires_at''',
            <Object?>[
              runId,
              ownerId,
              now.toIso8601String(),
              now.toIso8601String(),
              expires,
            ],
          );
          return true;
        });
      });

  Future<bool> renewRunLease({
    required String runId,
    required String ownerId,
    Duration lease = const Duration(minutes: 5),
  }) =>
      _serialize<bool>(() {
        final now = DateTime.now().toUtc();
        _database.execute(
          '''UPDATE run_leases SET renewed_at = ?, expires_at = ?
             WHERE run_id = ? AND owner_id = ?''',
          <Object?>[
            now.toIso8601String(),
            now.add(lease).toIso8601String(),
            runId,
            ownerId,
          ],
        );
        return _database.updatedRows == 1;
      });

  Future<void> releaseRunLease({
    required String runId,
    required String ownerId,
  }) =>
      _serialize<void>(() {
        _database.execute(
          'DELETE FROM run_leases WHERE run_id = ? AND owner_id = ?',
          <Object?>[runId, ownerId],
        );
      });

  Future<List<RunRecord>> recoverInFlightRuns() =>
      _serialize<List<RunRecord>>(() {
        return _transaction<List<RunRecord>>(() {
          final now = DateTime.now().toUtc();
          final rows = _database.select(
            '''SELECT r.run_json
               FROM runs r
               LEFT JOIN run_leases l ON l.run_id = r.id
               WHERE r.state IN ('running', 'cancelling')
                 AND (l.run_id IS NULL OR l.expires_at <= ?)''',
            <Object?>[now.toIso8601String()],
          );
          final recovered = <RunRecord>[];
          for (final row in rows) {
            final run = RunRecord.fromJson(_decodeMap(row['run_json']));
            final committed = _database.select(
              '''SELECT 1 FROM checkpoints
                 WHERE run_id = ? AND kind = 'workspace_committed'
                 LIMIT 1''',
              <Object?>[run.id],
            ).isNotEmpty;
            final allItemsSucceeded = run.items.every(
              (item) => item.state == WorkItemState.succeeded,
            );
            final next = committed && allItemsSucceeded
                ? run.copyWith(
                    state: RunState.succeeded,
                    completedAt: run.completedAt ?? now,
                    summary: run.summary.trim().isEmpty
                        ? 'Recovered a durably committed run after process interruption.'
                        : run.summary,
                    clearFailure: true,
                    updatedAt: now,
                  )
                : run.copyWith(
                    state: RunState.interrupted,
                    failure:
                        'The previous process stopped while this run was active. Durable checkpoints and idempotency records are available for explicit resume.',
                    updatedAt: now,
                  );
            _saveRunUnlocked(
              next,
              eventType: committed && allItemsSucceeded
                  ? 'run.recovered_committed'
                  : 'run.interrupted',
            );
            _database.execute(
              'DELETE FROM run_leases WHERE run_id = ?',
              <Object?>[run.id],
            );
            _database.execute(
              '''INSERT INTO recovery_actions(
                   id, run_id, action, reason, before_state, after_state,
                   details_json, created_at
                 ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
              <Object?>[
                newId('recovery'),
                run.id,
                committed && allItemsSucceeded
                    ? 'finalize_committed_run'
                    : 'mark_interrupted',
                committed && allItemsSucceeded
                    ? 'workspace_commit_checkpoint_present'
                    : 'expired_or_missing_run_lease',
                run.state.name,
                next.state.name,
                canonicalJson(<String, dynamic>{
                  'committedCheckpoint': committed,
                  'allItemsSucceeded': allItemsSucceeded,
                }),
                now.toIso8601String(),
              ],
            );
            recovered.add(next);
          }
          return recovered;
        });
      });

  Future<int> rebuildRunProjectionFromHistory() => _serialize<int>(() {
        return _transaction<int>(() {
          final events = _database.select(
            '''SELECT type, payload_json, state_version
               FROM run_events
               WHERE type IN ('run.snapshot', 'legacy.run_imported',
                              'run.recovered_committed', 'run.interrupted',
                              'run.deleted')
               ORDER BY sequence''',
          );
          final latest = <String, Map<String, dynamic>>{};
          final versions = <String, int>{};
          for (final row in events) {
            final payload = _decodeMap(row['payload_json']);
            if (row['type']?.toString() == 'run.deleted') {
              final id = payload['runId']?.toString() ?? '';
              latest.remove(id);
              versions.remove(id);
              continue;
            }
            final run = mapValue(payload['run']);
            final id = run['id']?.toString() ?? '';
            if (id.isEmpty) {
              continue;
            }
            latest[id] = run;
            versions[id] = _asInt(
              payload['stateVersion'] ?? row['state_version'] ?? 1,
            );
          }
          _database.execute('DELETE FROM runs');
          for (final entry in latest.entries) {
            final run = RunRecord.fromJson(entry.value);
            final json = canonicalJson(entry.value);
            _database.execute(
              '''INSERT INTO runs(
                   id, project_id, command_id, source_run_id, state,
                   state_version, run_json, snapshot_sha256, created_at,
                   updated_at, completed_at, failure
                 ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
              <Object?>[
                run.id,
                run.command.contract.projectId,
                run.command.id,
                run.sourceRunId,
                run.state.name,
                versions[entry.key] ?? 1,
                json,
                Sha256.text(json),
                run.createdAt.toUtc().toIso8601String(),
                run.updatedAt.toUtc().toIso8601String(),
                run.completedAt?.toUtc().toIso8601String(),
                run.failure,
              ],
            );
          }
          return latest.length;
        });
      });

  Future<WorkflowIntegrityReport> verifyIntegrity() =>
      _serialize<WorkflowIntegrityReport>(() {
        final integrityRows = _database.select('PRAGMA integrity_check');
        final integrity = integrityRows.isEmpty
            ? 'missing'
            : integrityRows.first.values.first?.toString() ?? 'missing';
        final foreignKeys = _database.select('PRAGMA foreign_key_check').length;
        var invalidRuns = 0;
        for (final row in _database.select(
          'SELECT run_json, snapshot_sha256 FROM runs',
        )) {
          if (!constantTimeEquals(
            Sha256.text(row['run_json']?.toString() ?? ''),
            row['snapshot_sha256']?.toString() ?? '',
          )) {
            invalidRuns++;
          }
        }
        var invalidEvents = 0;
        for (final row in _database.select(
          'SELECT payload_json, payload_sha256 FROM run_events',
        )) {
          if (!constantTimeEquals(
            Sha256.text(row['payload_json']?.toString() ?? ''),
            row['payload_sha256']?.toString() ?? '',
          )) {
            invalidEvents++;
          }
        }
        var projectionMismatches = 0;
        for (final row in _database.select(
          '''SELECT r.id, r.snapshot_sha256,
                    (SELECT json_extract(e.payload_json, '$.snapshotSha256')
                     FROM run_events e
                     WHERE e.run_id = r.id
                       AND e.type IN ('run.snapshot', 'legacy.run_imported',
                                      'run.recovered_committed', 'run.interrupted')
                     ORDER BY e.sequence DESC LIMIT 1) AS event_sha
             FROM runs r''',
        )) {
          final eventSha = row['event_sha']?.toString() ?? '';
          if (eventSha.isNotEmpty &&
              !constantTimeEquals(
                eventSha,
                row['snapshot_sha256']?.toString() ?? '',
              )) {
            projectionMismatches++;
          }
        }
        return WorkflowIntegrityReport(
          ok: integrity.toLowerCase() == 'ok' &&
              foreignKeys == 0 &&
              invalidRuns == 0 &&
              invalidEvents == 0 &&
              projectionMismatches == 0 &&
              schemaVersion == generatedWorkflowSchemaVersion,
          schemaVersion: schemaVersion,
          integrityResult: integrity,
          foreignKeyViolations: foreignKeys,
          invalidRunHashes: invalidRuns,
          invalidEventHashes: invalidEvents,
          projectionMismatches: projectionMismatches,
        );
      });

  Future<void> checkpointWal() => _serialize<void>(() {
        _database.execute('PRAGMA wal_checkpoint(FULL)');
      });

  Future<void> close() async {
    await _serialize<void>(() {
      _database.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      _disposed = true;
      _database.dispose();
    });
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  static int _asInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

  static DateTime _parseDate(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static Map<String, dynamic> _decodeMap(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
    }
    try {
      final decoded = jsonDecode(value?.toString() ?? '{}');
      return decoded is Map
          ? <String, dynamic>{
              for (final entry in decoded.entries)
                entry.key.toString(): entry.value,
            }
          : <String, dynamic>{};
    } on FormatException {
      throw const WorkflowStorageException(
        'workflow_json_corrupt',
        'A durable workflow JSON payload is corrupt.',
      );
    }
  }

  static Map<String, dynamic>? _decodeNullableMap(Object? value) {
    if (value == null) {
      return null;
    }
    return _decodeMap(value);
  }
}

class SqliteEntityRepository<T> implements EntityRepository<T> {
  const SqliteEntityRepository({
    required this.store,
    required this.collection,
    required this.fromJson,
    required this.toJson,
    required this.idOf,
  });

  final DurableWorkflowStore store;
  final String collection;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T value) toJson;
  final String Function(T value) idOf;

  @override
  Future<List<T>> all() async =>
      (await store.listEntities(collection)).map(fromJson).toList();

  @override
  Future<T?> get(String id) async {
    final value = await store.getEntity(collection, id);
    return value == null ? null : fromJson(value);
  }

  @override
  Future<void> put(T item) =>
      store.putEntity(collection, idOf(item), toJson(item));

  @override
  Future<void> putAll(Iterable<T> values) => store.putEntities(
        collection,
        values.map(
          (value) => MapEntry<String, Map<String, dynamic>>(
            idOf(value),
            toJson(value),
          ),
        ),
      );

  @override
  Future<void> remove(String id) => store.removeEntity(collection, id);

  @override
  Future<void> removeWhere(bool Function(T item) predicate) async {
    for (final item in await all()) {
      if (predicate(item)) {
        await remove(idOf(item));
      }
    }
  }

  @override
  Future<void> replaceAll(Iterable<T> values) => store.replaceEntities(
        collection,
        values.map(
          (value) => MapEntry<String, Map<String, dynamic>>(
            idOf(value),
            toJson(value),
          ),
        ),
      );
}

class SqliteRunRepository implements EntityRepository<RunRecord> {
  const SqliteRunRepository(this.store);

  final DurableWorkflowStore store;

  @override
  Future<List<RunRecord>> all() => store.listRuns();

  @override
  Future<RunRecord?> get(String id) => store.getRun(id);

  @override
  Future<void> put(RunRecord item) => store.saveRun(item);

  @override
  Future<void> putAll(Iterable<RunRecord> values) => store.saveRuns(values);

  @override
  Future<void> remove(String id) => store.removeRun(id);

  @override
  Future<void> removeWhere(bool Function(RunRecord item) predicate) async {
    for (final run in await all()) {
      if (predicate(run)) {
        await remove(run.id);
      }
    }
  }

  @override
  Future<void> replaceAll(Iterable<RunRecord> values) =>
      store.replaceRuns(values);
}

class SqliteJsonDocument implements JsonDocumentRepository {
  const SqliteJsonDocument(this.store, this.key);

  final DurableWorkflowStore store;
  final String key;

  @override
  Future<Object?> read({Object? fallback}) =>
      store.readDocument(key, fallback: fallback);

  @override
  Future<void> write(Object? value) => store.writeDocument(key, value);
}
