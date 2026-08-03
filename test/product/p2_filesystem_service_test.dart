import 'dart:io';

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
