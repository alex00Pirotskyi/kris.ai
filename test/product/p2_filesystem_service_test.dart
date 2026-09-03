import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_effect_boundary.dart';
import 'package:kristin_local_agent/product/p2_effect_journal.dart';
import 'package:kristin_local_agent/product/p2_filesystem_service.dart';

void main() {
  test('relative paths fail closed before authorization', () {
    final service = P2FilesystemService(
      authorizer: _Authorizer(),
      journal: _Journal(),
      backupRoot: Directory.systemTemp,
    );
    expect(
      () => service.requireAbsolute('relative.txt'),
      throwsA(isA<P2FilesystemException>()),
    );
  });

  test('enumeration requires authorization', () async {
    final authorizer = _Authorizer();
    final service = P2FilesystemService(
      authorizer: authorizer,
      journal: _Journal(),
      backupRoot: Directory.systemTemp,
    );
    final directory = await Directory.systemTemp.createTemp('p2-enumerate-');
    addTearDown(() => directory.delete(recursive: true));
    await service
        .enumerate(
          directory.path,
          binding: _binding('enumerate'),
          maxEntries: 10,
        )
        .toList();
    expect(authorizer.operations, contains('enumerate'));
  });

  test('directory identity ignores transaction-owned metadata changes', () {
    const before = P2PathIdentity(
      path: '/tmp/root',
      resolvedPath: '/tmp/root',
      entityType: 'directory',
      modifiedMicros: 1,
      size: 1,
    );
    const after = P2PathIdentity(
      path: '/tmp/root',
      resolvedPath: '/tmp/root',
      entityType: 'directory',
      modifiedMicros: 2,
      size: 2,
    );
    const replaced = P2PathIdentity(
      path: '/tmp/root',
      resolvedPath: '/tmp/other',
      entityType: 'directory',
      modifiedMicros: 2,
      size: 2,
    );
    expect(before.sameObject(after), true);
    expect(before.sameObject(replaced), false);
  });

  test('atomic write accepts its own same-directory temporary file', () async {
    final root = await Directory.systemTemp.createTemp('p2-write-');
    addTearDown(() => root.delete(recursive: true));
    final authorizer = _Authorizer();
    final service = P2FilesystemService(
      authorizer: authorizer,
      journal: _Journal(),
      backupRoot: Directory('${root.path}${Platform.pathSeparator}backups'),
    );
    final target = File('${root.path}${Platform.pathSeparator}target.txt');
    await service.write(
      target.path,
      Uint8List.fromList(<int>[79, 75]),
      binding: _binding('write'),
    );
    expect(await target.readAsString(), 'OK');
    expect(authorizer.operations, contains('write'));
  });
}

P2EffectBinding _binding(String operation) => P2EffectBinding(
  runId: 'run',
  taskId: 'task',
  actorId: 'actor',
  toolId: 'filesystem',
  accessProfileId: 'owner',
  capabilityId: 'filesystem.$operation',
  operation: operation,
);

class _Authorizer implements P2FilesystemAuthorizer {
  final List<String> operations = <String>[];

  @override
  Future<Map<String, Object?>> authorize(
    P2EffectBinding binding,
    String operation,
    String target,
  ) async {
    operations.add(operation);
    return <String, Object?>{'target': target};
  }
}

class _Journal implements P2EffectJournal {
  @override
  Future<void> append(P2EffectReceipt receipt) async {}
}
