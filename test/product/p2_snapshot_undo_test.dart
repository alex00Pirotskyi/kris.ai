import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_effect_boundary.dart';
import 'package:kristin_local_agent/product/p2_effect_journal.dart';
import 'package:kristin_local_agent/product/p2_host_operations.dart';
import 'package:kristin_local_agent/product/p2_snapshot_undo.dart';

import 'p2_test_support.dart';

void main() {
  test('product restore executor restores file and journals rollback',
      () async {
    final directory = await Directory.systemTemp.createTemp('p2-undo-test-');
    addTearDown(() => directory.delete(recursive: true));
    final snapshots = Directory('${directory.path}/snapshots');
    final target = File('${directory.path}/target.txt');
    await target.writeAsString('before');
    final authorizer = _Authorizer();
    final journal = TestJournal();
    final service = P2SnapshotUndoService(
      snapshots,
      authorizer: authorizer,
      journal: journal,
    );
    final backup = await service.backupFile(target, 'effect-1');
    await target.writeAsString('after');
    final receipt = P2EffectReceipt(
      effectId: 'effect-1',
      runId: 'run',
      taskId: 'P2-010',
      operation: 'filesystem.write',
      status: P2EffectStatus.succeeded,
      reversibility: P2Reversibility.reversible,
      startedAt: DateTime.now().toUtc(),
      completedAt: DateTime.now().toUtc(),
      details: <String, Object?>{
        'backupPath': backup.path,
        'path': target.path,
      },
    );
    final plan = service.classify(receipt);
    final result = await service.restore(
      plan,
      testBinding('snapshot.restore', taskId: 'P2-010'),
    );
    expect(await target.readAsString(), 'before');
    expect(result.status, P2EffectStatus.rolledBack);
    expect(result.completedSteps, 1);
    expect(authorizer.operations, <String>['snapshot.restore']);
    expect(journal.receipts.single.status, P2EffectStatus.rolledBack);
  });

  test('restore rejects symlink target without replacing it', () async {
    if (Platform.isWindows) return;
    final directory = await Directory.systemTemp.createTemp('p2-undo-link-');
    addTearDown(() => directory.delete(recursive: true));
    final snapshots = Directory('${directory.path}/snapshots');
    await snapshots.create(recursive: true);
    final backup = File('${snapshots.path}/effect.file.bak');
    await backup.writeAsString('safe');
    final victim = File('${directory.path}/victim.txt');
    await victim.writeAsString('victim');
    final link = Link('${directory.path}/target.txt');
    await link.create(victim.path);
    final service = P2SnapshotUndoService(
      snapshots,
      authorizer: _Authorizer(),
      journal: TestJournal(),
    );
    final plan = P2UndoPlan(
      effectId: 'effect',
      reversibility: P2Reversibility.reversible,
      steps: <Map<String, Object?>>[
        <String, Object?>{
          'type': 'restore_file',
          'backupPath': backup.path,
          'target': link.path,
        },
      ],
      nonRestorableReasons: const <String>[],
    );
    await expectLater(
      service.restore(
        plan,
        testBinding('snapshot.restore', taskId: 'P2-010'),
      ),
      throwsStateError,
    );
    expect(await victim.readAsString(), 'victim');
  });
}

final class _Authorizer implements P2HostOperationAuthorizer {
  final List<String> operations = <String>[];

  @override
  Future<void> authorize(
    P2EffectBinding binding,
    String operation,
    Map<String, Object?> scope,
  ) async {
    expect(binding.operation, operation);
    operations.add(operation);
  }
}
