import 'dart:convert';
import 'dart:io';

import '../crypto_utils.dart';
import 'research_runtime.dart';

const String p4ResearchAuthorityVersion = '1.0.0';

const Set<String> p4ResearchAuthorityEntities = <String>{
  'search_queries',
  'search_results',
  'web_sources',
  'web_fetches',
  'web_documents',
  'web_extractions',
  'web_citations',
  'datasets',
  'dataset_versions',
  'dataset_items',
  'crawl_jobs',
  'crawl_frontier',
  'change_monitors',
};

abstract interface class P4ResearchAuthorityStore {
  Future<String?> schemaVersion();
  Future<void> setSchemaVersion(String version);
  Future<void> put(String entity, String id, Map<String, Object?> value);
  Future<Map<String, Object?>?> get(String entity, String id);
  Future<List<Map<String, Object?>>> list(String entity);
  Future<void> remove(String entity, String id);
  Future<void> backupTo(Directory target);
  Future<void> verifyIntegrity();
}

final class P4JsonResearchAuthorityStore implements P4ResearchAuthorityStore {
  P4JsonResearchAuthorityStore(this.root);
  final Directory root;

  void _requireEntity(String entity) {
    if (!p4ResearchAuthorityEntities.contains(entity)) {
      throw const P4ResearchException('research_authority_entity_invalid');
    }
  }

  String _requireId(String id) {
    final normalized = id.trim();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,191}$').hasMatch(normalized)) {
      throw const P4ResearchException('research_authority_id_invalid');
    }
    return normalized;
  }

  File _record(String entity, String id) => File(
    '${root.path}${Platform.pathSeparator}$entity'
    '${Platform.pathSeparator}${_requireId(id)}.json',
  );

  File get _version =>
      File('${root.path}${Platform.pathSeparator}schema-version.txt');

  @override
  Future<String?> schemaVersion() async {
    if (!await _version.exists()) return null;
    return (await _version.readAsString()).trim();
  }

  @override
  Future<void> setSchemaVersion(String version) async {
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      throw const P4ResearchException('research_authority_version_invalid');
    }
    await root.create(recursive: true);
    final temporary = File('${_version.path}.tmp');
    await temporary.writeAsString('$version\n', flush: true);
    if (await _version.exists()) await _version.delete();
    await temporary.rename(_version.path);
  }

  @override
  Future<void> put(String entity, String id, Map<String, Object?> value) async {
    _requireEntity(entity);
    final file = _record(entity, id);
    final canonical = canonicalJson(<String, Object?>{
      'schemaVersion': p4ResearchAuthorityVersion,
      'entity': entity,
      'id': id,
      'value': value,
    });
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString('$canonical\n', flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  @override
  Future<Map<String, Object?>?> get(String entity, String id) async {
    _requireEntity(entity);
    final file = _record(entity, id);
    if (!await file.exists()) return null;
    return _readRecord(file, expectedEntity: entity, expectedId: id);
  }

  @override
  Future<List<Map<String, Object?>>> list(String entity) async {
    _requireEntity(entity);
    final directory = Directory('${root.path}${Platform.pathSeparator}$entity');
    if (!await directory.exists()) return const <Map<String, Object?>>[];
    final output = <Map<String, Object?>>[];
    await for (final child in directory.list(followLinks: false)) {
      if (child is! File || !child.path.endsWith('.json')) continue;
      final filename = child.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      final id = filename.substring(0, filename.length - '.json'.length);
      output.add(
        await _readRecord(child, expectedEntity: entity, expectedId: id),
      );
    }
    output.sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    return List<Map<String, Object?>>.unmodifiable(output);
  }

  Future<Map<String, Object?>> _readRecord(
    File file, {
    required String expectedEntity,
    required String expectedId,
  }) async {
    late final Object? raw;
    try {
      raw = jsonDecode(await file.readAsString());
    } on FormatException {
      throw const P4ResearchException('research_authority_corrupt');
    }
    if (raw is! Map) {
      throw const P4ResearchException('research_authority_corrupt');
    }
    final mapped = raw.map((key, value) => MapEntry(key.toString(), value));
    if (mapped['schemaVersion'] != p4ResearchAuthorityVersion ||
        mapped['entity'] != expectedEntity ||
        mapped['id'] != expectedId ||
        mapped['value'] is! Map) {
      throw const P4ResearchException('research_authority_corrupt');
    }
    return Map<String, Object?>.unmodifiable(mapped);
  }

  @override
  Future<void> remove(String entity, String id) async {
    _requireEntity(entity);
    final file = _record(entity, id);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> backupTo(Directory target) async {
    if (await target.exists()) {
      throw const P4ResearchException(
        'research_authority_backup_target_exists',
      );
    }
    await target.create(recursive: true);
    if (!await root.exists()) return;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory) continue;
      if (entity is! File) continue;
      final relative = entity.path
          .substring(root.path.length)
          .replaceFirst(RegExp(r'^[\\/]'), '');
      final destination = File(
        '${target.path}${Platform.pathSeparator}$relative',
      );
      await destination.parent.create(recursive: true);
      await entity.copy(destination.path);
    }
  }

  @override
  Future<void> verifyIntegrity() async {
    final version = await schemaVersion();
    if (version != null && version != p4ResearchAuthorityVersion) {
      throw const P4ResearchException('research_authority_version_mismatch');
    }
    for (final entity in p4ResearchAuthorityEntities) {
      await list(entity);
    }
  }
}

final class P4ResearchAuthorityMigration {
  const P4ResearchAuthorityMigration({
    required this.fromVersion,
    required this.toVersion,
    required this.apply,
    required this.rollback,
  });
  final String? fromVersion;
  final String toVersion;
  final Future<void> Function(P4ResearchAuthorityStore store) apply;
  final Future<void> Function(P4ResearchAuthorityStore store) rollback;
}

final class P4ResearchAuthorityMigrator {
  const P4ResearchAuthorityMigrator(this.migrations);
  final List<P4ResearchAuthorityMigration> migrations;

  Future<void> migrate(P4ResearchAuthorityStore store) async {
    var current = await store.schemaVersion();
    final applied = <P4ResearchAuthorityMigration>[];
    try {
      while (current != p4ResearchAuthorityVersion) {
        final migration = migrations
            .where((item) => item.fromVersion == current)
            .firstOrNull;
        if (migration == null) {
          throw const P4ResearchException(
            'research_authority_migration_missing',
          );
        }
        await migration.apply(store);
        await store.setSchemaVersion(migration.toVersion);
        applied.add(migration);
        current = migration.toVersion;
      }
      await store.verifyIntegrity();
    } catch (_) {
      for (final migration in applied.reversed) {
        await migration.rollback(store);
        if (migration.fromVersion != null) {
          await store.setSchemaVersion(migration.fromVersion!);
        }
      }
      rethrow;
    }
  }

  static P4ResearchAuthorityMigrator initial() =>
      P4ResearchAuthorityMigrator(<P4ResearchAuthorityMigration>[
        P4ResearchAuthorityMigration(
          fromVersion: null,
          toVersion: p4ResearchAuthorityVersion,
          apply: (store) async {
            for (final entity in p4ResearchAuthorityEntities) {
              await store.list(entity);
            }
          },
          rollback: (store) async {},
        ),
      ]);
}

final class P4AuthorityBackupReceipt {
  const P4AuthorityBackupReceipt({
    required this.path,
    required this.manifestSha256,
    required this.files,
  });
  final String path;
  final String manifestSha256;
  final int files;
}

Future<P4AuthorityBackupReceipt> p4BackupAuthority(
  P4ResearchAuthorityStore store,
  Directory target,
) async {
  await store.verifyIntegrity();
  await store.backupTo(target);
  final entries = <String>[];
  await for (final entity in target.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.path
        .substring(target.path.length)
        .replaceFirst(RegExp(r'^[\\/]'), '');
    final bytes = await entity.readAsBytes();
    entries.add('$relative:${Sha256.hex(bytes)}');
  }
  entries.sort();
  return P4AuthorityBackupReceipt(
    path: target.path,
    manifestSha256: Sha256.text(entries.join('\n')),
    files: entries.length,
  );
}
