import 'dart:io';

import 'p2_effect_boundary.dart';
import 'p2_effect_journal.dart';
import 'p2_host_operations.dart';

class P2UndoPlan {
  const P2UndoPlan({
    required this.effectId,
    required this.reversibility,
    required this.steps,
    required this.nonRestorableReasons,
  });

  final String effectId;
  final P2Reversibility reversibility;
  final List<Map<String, Object?>> steps;
  final List<String> nonRestorableReasons;
}

class P2UndoResult {
  const P2UndoResult({
    required this.status,
    required this.completedSteps,
    required this.receipt,
  });

  final P2EffectStatus status;
  final int completedSteps;
  final P2EffectReceipt receipt;
}

class P2SnapshotUndoService {
  P2SnapshotUndoService(this.root, {this.authorizer, this.journal});

  final Directory root;
  final P2HostOperationAuthorizer? authorizer;
  final P2EffectJournal? journal;

  Future<File> backupFile(File source, String effectId) async {
    if (!source.isAbsolute || effectId.trim().isEmpty) {
      throw StateError('backup_request_invalid');
    }
    final type = await FileSystemEntity.type(source.path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw StateError('backup_source_regular_file_required');
    }
    await root.create(recursive: true);
    final target = File('${root.path}/$effectId.file.bak');
    return source.copy(target.path);
  }

  Future<String?> createGitCheckpoint(
    Directory repository,
    String effectId,
  ) async {
    if (!repository.isAbsolute || effectId.trim().isEmpty) {
      throw StateError('git_checkpoint_request_invalid');
    }
    final git = await Process.run('git', <String>[
      '-C',
      repository.path,
      'rev-parse',
      '--show-toplevel',
    ], runInShell: false);
    if (git.exitCode != 0) {
      return null;
    }
    final tree = await Process.run('git', <String>[
      '-C',
      repository.path,
      'stash',
      'create',
      'kristin-$effectId',
    ], runInShell: false);
    final value = tree.exitCode == 0 ? '${tree.stdout}'.trim() : '';
    return RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(value) ? value : null;
  }

  P2UndoPlan classify(P2EffectReceipt receipt) {
    final steps = <Map<String, Object?>>[];
    final backup = receipt.details['backupPath'];
    final target = receipt.details['path'];
    if (backup is String && target is String) {
      steps.add(<String, Object?>{
        'type': 'restore_file',
        'backupPath': backup,
        'target': target,
      });
    }
    final repository = receipt.details['repository'];
    final checkpoint = receipt.details['gitCheckpoint'];
    if (repository is String &&
        checkpoint is String &&
        RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(checkpoint)) {
      steps.add(<String, Object?>{
        'type': 'restore_git_checkpoint',
        'repository': repository,
        'checkpoint': checkpoint,
      });
    }
    if (steps.isNotEmpty) {
      return P2UndoPlan(
        effectId: receipt.effectId,
        reversibility: receipt.reversibility,
        steps: List<Map<String, Object?>>.unmodifiable(steps),
        nonRestorableReasons: const <String>[],
      );
    }
    return P2UndoPlan(
      effectId: receipt.effectId,
      reversibility: receipt.reversibility,
      steps: const <Map<String, Object?>>[],
      nonRestorableReasons: const <String>[
        'No supported inverse operation was recorded.',
      ],
    );
  }

  /// Executes the recorded inverse through the product service. Direct fixture
  /// file copies are not accepted as P2-010 evidence.
  Future<P2UndoResult> restore(P2UndoPlan plan, P2EffectBinding binding) async {
    final effectAuthorizer = authorizer;
    final effectJournal = journal;
    if (effectAuthorizer == null || effectJournal == null) {
      throw StateError('snapshot_restore_runtime_not_composed');
    }
    if (plan.steps.isEmpty || plan.nonRestorableReasons.isNotEmpty) {
      throw StateError('undo_plan_not_restorable');
    }
    final exact = P2EffectBinding(
      runId: binding.runId,
      taskId: binding.taskId,
      actorId: binding.actorId,
      toolId: binding.toolId,
      accessProfileId: binding.accessProfileId,
      capabilityId: binding.capabilityId,
      operation: 'snapshot.restore',
    );
    await effectAuthorizer.authorize(
      exact,
      'snapshot.restore',
      <String, Object?>{
        'effectId': plan.effectId,
        'stepCount': plan.steps.length,
      },
    );

    final started = DateTime.now().toUtc();
    var completed = 0;
    try {
      for (final step in plan.steps) {
        final type = step['type'];
        if (type == 'restore_file') {
          await _restoreFile(step, plan.effectId, completed);
        } else if (type == 'restore_git_checkpoint') {
          await _restoreGit(step);
        } else {
          throw StateError('undo_step_unsupported');
        }
        completed += 1;
      }
      final receipt = P2EffectReceipt(
        effectId: 'undo-${plan.effectId}',
        runId: exact.runId,
        taskId: exact.taskId,
        operation: 'snapshot.restore',
        status: P2EffectStatus.rolledBack,
        reversibility: plan.reversibility,
        startedAt: started,
        completedAt: DateTime.now().toUtc(),
        details: <String, Object?>{
          'sourceEffectId': plan.effectId,
          'completedSteps': completed,
          'stepCount': plan.steps.length,
          'contentLogged': false,
        },
      );
      await effectJournal.append(receipt);
      return P2UndoResult(
        status: P2EffectStatus.rolledBack,
        completedSteps: completed,
        receipt: receipt,
      );
    } catch (error) {
      final receipt = P2EffectReceipt(
        effectId: 'undo-${plan.effectId}',
        runId: exact.runId,
        taskId: exact.taskId,
        operation: 'snapshot.restore',
        status: completed == 0 ? P2EffectStatus.failed : P2EffectStatus.unknown,
        reversibility: plan.reversibility,
        startedAt: started,
        completedAt: DateTime.now().toUtc(),
        details: <String, Object?>{
          'sourceEffectId': plan.effectId,
          'completedSteps': completed,
          'stepCount': plan.steps.length,
          'errorType': error.runtimeType.toString(),
          'contentLogged': false,
        },
      );
      await effectJournal.append(receipt);
      rethrow;
    }
  }

  Future<void> _restoreFile(
    Map<String, Object?> step,
    String effectId,
    int index,
  ) async {
    final backupPath = step['backupPath'];
    final targetPath = step['target'];
    if (backupPath is! String || targetPath is! String) {
      throw StateError('restore_file_step_invalid');
    }
    final backup = File(backupPath);
    final target = File(targetPath);
    if (!backup.isAbsolute || !target.isAbsolute) {
      throw StateError('restore_file_absolute_paths_required');
    }
    final rootCanonical = await root.resolveSymbolicLinks();
    final backupCanonical = await backup.resolveSymbolicLinks();
    if (!_inside(backupCanonical, rootCanonical)) {
      throw StateError('restore_backup_outside_snapshot_root');
    }
    if (await FileSystemEntity.type(backup.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('restore_backup_regular_file_required');
    }
    await target.parent.create(recursive: true);
    if (await FileSystemEntity.type(target.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('restore_target_symlink_rejected');
    }

    final nonce =
        '${effectId.hashCode}-$index-${DateTime.now().microsecondsSinceEpoch}';
    final staged = File('${target.parent.path}/.kristin-restore-$nonce.tmp');
    final displaced = File(
      '${target.parent.path}/.kristin-restore-$nonce.previous',
    );
    await backup.copy(staged.path);
    var displacedExisting = false;
    try {
      if (await target.exists()) {
        await target.rename(displaced.path);
        displacedExisting = true;
      }
      await staged.rename(target.path);
      if (displacedExisting) {
        await displaced.delete();
      }
    } catch (_) {
      if (await staged.exists()) {
        await staged.delete();
      }
      if (displacedExisting && await displaced.exists()) {
        if (await target.exists()) {
          await target.delete();
        }
        await displaced.rename(target.path);
      }
      rethrow;
    }
  }

  Future<void> _restoreGit(Map<String, Object?> step) async {
    final repository = step['repository'];
    final checkpoint = step['checkpoint'];
    if (repository is! String ||
        checkpoint is! String ||
        !Directory(repository).isAbsolute ||
        !RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(checkpoint)) {
      throw StateError('restore_git_step_invalid');
    }
    final verify = await Process.run('git', <String>[
      '-C',
      repository,
      'cat-file',
      '-e',
      '$checkpoint^{tree}',
    ], runInShell: false);
    if (verify.exitCode != 0) {
      throw StateError('git_checkpoint_missing');
    }
    final restore = await Process.run('git', <String>[
      '-C',
      repository,
      'reset',
      '--hard',
      checkpoint,
    ], runInShell: false);
    if (restore.exitCode != 0) {
      throw StateError('git_checkpoint_restore_failed');
    }
  }

  bool _inside(String candidate, String parent) {
    final separator = Platform.pathSeparator;
    final normalizedParent = parent.endsWith(separator)
        ? parent
        : '$parent$separator';
    return candidate == parent || candidate.startsWith(normalizedParent);
  }
}
