import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'p2_effect_boundary.dart';
import 'p2_effect_journal.dart';

String _p2FileSystemEntityTypeName(FileSystemEntityType type) {
  if (type == FileSystemEntityType.file) {
    return 'file';
  }
  if (type == FileSystemEntityType.directory) {
    return 'directory';
  }
  if (type == FileSystemEntityType.link) {
    return 'link';
  }
  if (type == FileSystemEntityType.notFound) {
    return 'notFound';
  }
  return 'unknown';
}

class P2FilesystemException implements Exception {
  const P2FilesystemException(this.code);

  final String code;

  @override
  String toString() => 'P2FilesystemException($code)';
}

class P2PathIdentity {
  const P2PathIdentity({
    required this.path,
    required this.resolvedPath,
    required this.entityType,
    required this.modifiedMicros,
    required this.size,
  });

  final String path;
  final String resolvedPath;
  final String entityType;
  final int modifiedMicros;
  final int size;

  bool sameObject(P2PathIdentity other) {
    if (resolvedPath != other.resolvedPath || entityType != other.entityType) {
      return false;
    }
    if (entityType == 'directory') {
      return true;
    }
    return modifiedMicros == other.modifiedMicros && size == other.size;
  }
}

abstract interface class P2FilesystemAuthorizer {
  Future<Map<String, Object?>> authorize(
    P2EffectBinding binding,
    String operation,
    String target,
  );
}

class P2FilesystemService {
  P2FilesystemService({
    required this.authorizer,
    required this.journal,
    required this.backupRoot,
  });

  final P2FilesystemAuthorizer authorizer;
  final P2EffectJournal journal;
  final Directory backupRoot;

  String requireAbsolute(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      throw const P2FilesystemException('path_empty');
    }
    final windows = RegExp(
      r'^(?:[A-Za-z]:[\\/]|\\\\|\\\\\?\\)',
    ).hasMatch(value);
    if (!windows && !value.startsWith('/')) {
      throw const P2FilesystemException('absolute_path_required');
    }
    if (value.contains('\u0000')) {
      throw const P2FilesystemException('path_contains_nul');
    }
    return value;
  }

  Future<P2PathIdentity> identify(
    String raw, {
    bool allowMissing = false,
  }) async {
    final path = requireAbsolute(raw);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      if (allowMissing) {
        return P2PathIdentity(
          path: path,
          resolvedPath: path,
          entityType: _p2FileSystemEntityTypeName(type),
          modifiedMicros: 0,
          size: 0,
        );
      }
      throw const P2FilesystemException('not_found');
    }
    final resolved = await _resolve(type, path);
    final stat = await FileStat.stat(path);
    return P2PathIdentity(
      path: path,
      resolvedPath: resolved,
      entityType: _p2FileSystemEntityTypeName(type),
      modifiedMicros: stat.modified.microsecondsSinceEpoch,
      size: stat.size,
    );
  }

  Future<Uint8List> read(
    String path, {
    required P2EffectBinding binding,
    required int maxBytes,
  }) async {
    final absolute = requireAbsolute(path);
    await authorizer.authorize(binding, 'read', absolute);
    final before = await identify(absolute);
    if (before.entityType != 'file') {
      throw const P2FilesystemException('not_a_file');
    }
    final handle = await File(before.resolvedPath).open();
    try {
      final length = await handle.length();
      if (length > maxBytes) {
        throw const P2FilesystemException('read_budget_exceeded');
      }
      final bytes = await handle.read(length);
      final after = await identify(absolute);
      if (!before.sameObject(after)) {
        throw const P2FilesystemException('path_changed_during_read');
      }
      return Uint8List.fromList(bytes);
    } finally {
      await handle.close();
    }
  }

  Future<P2EffectReceipt> write(
    String path,
    Uint8List data, {
    required P2EffectBinding binding,
  }) async {
    final absolute = requireAbsolute(path);
    await authorizer.authorize(binding, 'write', absolute);
    final target = File(absolute);
    final parentIdentity = await identify(target.parent.path);
    if (parentIdentity.entityType != 'directory') {
      throw const P2FilesystemException('parent_not_directory');
    }

    await backupRoot.create(recursive: true);
    final startedAt = DateTime.now().toUtc();
    final before = await identify(absolute, allowMissing: true);
    File? backup;
    if (before.entityType != 'notFound') {
      if (before.entityType != 'file') {
        throw const P2FilesystemException('target_not_regular_file');
      }
      backup = File(
        '${backupRoot.path}/write-${startedAt.microsecondsSinceEpoch}.bak',
      );
      await File(before.resolvedPath).copy(backup.path);
      final afterBackup = await identify(absolute);
      if (!before.sameObject(afterBackup)) {
        await backup.delete();
        throw const P2FilesystemException('path_changed_before_write');
      }
    }

    final transactionId = startedAt.microsecondsSinceEpoch;
    final temporary = File('${target.parent.path}/.kristin-tmp-$transactionId');
    final displaced = File('${target.parent.path}/.kristin-old-$transactionId');
    var displacedExistingTarget = false;
    var committedTarget = false;
    try {
      await temporary.writeAsBytes(data, flush: true);
      final parentAfterWrite = await identify(target.parent.path);
      if (!parentIdentity.sameObject(parentAfterWrite)) {
        throw const P2FilesystemException('parent_changed_before_rename');
      }
      final targetBeforeRename = await identify(absolute, allowMissing: true);
      if (!before.sameObject(targetBeforeRename)) {
        throw const P2FilesystemException('target_changed_before_rename');
      }
      if (before.entityType != 'notFound') {
        await target.rename(displaced.path);
        displacedExistingTarget = true;
        final displacedStat = await displaced.stat();
        if (displacedStat.type != FileSystemEntityType.file ||
            displacedStat.modified.microsecondsSinceEpoch !=
                before.modifiedMicros ||
            displacedStat.size != before.size) {
          throw const P2FilesystemException(
            'displaced_target_identity_mismatch',
          );
        }
      }
      if (await FileSystemEntity.type(absolute, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const P2FilesystemException('target_reappeared_before_commit');
      }
      await temporary.rename(target.path);
      committedTarget = true;
      if (displacedExistingTarget && await displaced.exists()) {
        await displaced.delete();
      }
      final completedAt = DateTime.now().toUtc();
      final receipt = P2EffectReceipt(
        effectId: 'fs-${completedAt.microsecondsSinceEpoch}',
        runId: binding.runId,
        taskId: binding.taskId,
        operation: 'write',
        status: P2EffectStatus.succeeded,
        reversibility: P2Reversibility.reversible,
        startedAt: startedAt,
        completedAt: completedAt,
        details: <String, Object?>{
          'path': target.path,
          'backupPath': backup?.path,
          'createdNew': backup == null,
          'bytes': data.length,
          'parentIdentity': parentIdentity.resolvedPath,
          'transactionId': transactionId,
          'sameDirectoryCommit': true,
        },
      );
      await journal.append(receipt);
      return receipt;
    } catch (_) {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      if (displacedExistingTarget && await displaced.exists()) {
        if (await target.exists()) {
          if (!committedTarget) {
            throw const P2FilesystemException('recovery_target_conflict');
          }
          await target.delete();
        }
        await displaced.rename(target.path);
      } else if (backup != null && await backup.exists()) {
        if (await target.exists() && !committedTarget) {
          throw const P2FilesystemException('recovery_target_conflict');
        }
        await backup.copy(target.path);
      } else if (committedTarget &&
          before.entityType == 'notFound' &&
          await target.exists()) {
        await target.delete();
      }
      rethrow;
    }
  }

  Stream<FileSystemEntity> enumerate(
    String root, {
    required P2EffectBinding binding,
    required int maxEntries,
    bool followLinks = false,
  }) async* {
    final absolute = requireAbsolute(root);
    await authorizer.authorize(binding, 'enumerate', absolute);
    if (maxEntries <= 0) {
      throw const P2FilesystemException('invalid_traversal_budget');
    }
    final rootIdentity = await identify(absolute);
    if (rootIdentity.entityType != 'directory') {
      throw const P2FilesystemException('root_not_directory');
    }
    var count = 0;
    await for (final entity in Directory(
      absolute,
    ).list(recursive: true, followLinks: followLinks)) {
      if (++count > maxEntries) {
        throw const P2FilesystemException('traversal_budget_exceeded');
      }
      yield entity;
    }
  }

  Future<P2EffectReceipt> moveToQuarantine(
    String path, {
    required P2EffectBinding binding,
  }) async {
    final absolute = requireAbsolute(path);
    await authorizer.authorize(binding, 'delete', absolute);
    final identity = await identify(absolute);
    await backupRoot.create(recursive: true);
    final startedAt = DateTime.now().toUtc();
    final quarantine =
        '${backupRoot.path}/delete-${startedAt.microsecondsSinceEpoch}';

    var crossVolumeCopy = false;
    try {
      if (identity.entityType == 'file') {
        await File(absolute).rename(quarantine);
      } else if (identity.entityType == 'directory') {
        await Directory(absolute).rename(quarantine);
      } else {
        throw const P2FilesystemException('quarantine_unsupported_entity_type');
      }
    } on FileSystemException {
      crossVolumeCopy = true;
      if (identity.entityType == 'file') {
        await File(absolute).copy(quarantine);
        await File(absolute).delete();
      } else if (identity.entityType == 'directory') {
        await _copyDirectory(Directory(absolute), Directory(quarantine));
        await Directory(absolute).delete(recursive: true);
      } else {
        throw const P2FilesystemException('quarantine_unsupported_entity_type');
      }
    }

    final completedAt = DateTime.now().toUtc();
    final receipt = P2EffectReceipt(
      effectId: 'delete-${completedAt.microsecondsSinceEpoch}',
      runId: binding.runId,
      taskId: binding.taskId,
      operation: 'delete',
      status: P2EffectStatus.succeeded,
      reversibility: crossVolumeCopy
          ? P2Reversibility.partiallyReversible
          : P2Reversibility.reversible,
      startedAt: startedAt,
      completedAt: completedAt,
      details: <String, Object?>{
        'path': absolute,
        'quarantinePath': quarantine,
        'entityType': identity.entityType,
        'crossVolumeCopy': crossVolumeCopy,
      },
    );
    await journal.append(receipt);
    return receipt;
  }

  Future<String> _resolve(FileSystemEntityType type, String path) {
    if (type == FileSystemEntityType.directory) {
      return Directory(path).resolveSymbolicLinks();
    }
    if (type == FileSystemEntityType.link) {
      return Link(path).resolveSymbolicLinks();
    }
    return File(path).resolveSymbolicLinks();
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      final destination = '${target.path}${Platform.pathSeparator}$name';
      if (entity is File) {
        await entity.copy(destination);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(destination));
      } else {
        throw const P2FilesystemException(
          'directory_contains_unsupported_link',
        );
      }
    }
  }
}
