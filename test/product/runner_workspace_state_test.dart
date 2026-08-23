import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/execution_intelligence.dart';
import 'package:kristin_local_agent/product/runner_attempt_ledger.dart';

void main() {
  const policy = RunnerAttemptLedgerPolicy();

  test('workspace fingerprint tracks source changes and ignores volatile paths',
      () async {
    final root = await Directory.systemTemp.createTemp('kristin-runner-state-');
    try {
      final lib = Directory('${root.path}${Platform.pathSeparator}lib');
      await lib.create(recursive: true);
      final source = File('${lib.path}${Platform.pathSeparator}main.dart');
      await source.writeAsString('void main() {}\n');

      final initial = await policy.workspaceSha256(root);

      final dartTool = Directory(
        '${root.path}${Platform.pathSeparator}.dart_tool',
      );
      await dartTool.create(recursive: true);
      await File('${dartTool.path}${Platform.pathSeparator}noise.json')
          .writeAsString('{"volatile":true}\n');
      final build = Directory('${root.path}${Platform.pathSeparator}build');
      await build.create(recursive: true);
      await File('${build.path}${Platform.pathSeparator}artifact.bin')
          .writeAsBytes(<int>[1, 2, 3, 4]);

      expect(await policy.workspaceSha256(root), initial);

      await source.writeAsString('void main() { print("changed"); }\n');
      expect(await policy.workspaceSha256(root), isNot(initial));
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test('workspace fingerprint detects created files from external tools', () async {
    final root = await Directory.systemTemp.createTemp('kristin-runner-create-');
    try {
      final before = await policy.workspaceSha256(root);
      final created = Directory(
        '${root.path}${Platform.pathSeparator}generated_app',
      );
      await created.create(recursive: true);
      await File('${created.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsString('name: generated_app\n');
      final after = await policy.workspaceSha256(root);
      expect(after, isNot(before));
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test('material workspace digest participates in world-state identity', () {
    const semantic = SemanticProgressSnapshot(
      artifacts: <String, String>{},
      evidenceIds: <String>{'evidence-only'},
      satisfiedCriteria: <String>{},
      externalState: <String>{},
      planHash: 'plan',
    );

    final before = policy.worldStateSha256(
      semantic,
      mutationEpoch: 0,
      workspaceSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    final after = policy.worldStateSha256(
      semantic,
      mutationEpoch: 0,
      workspaceSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );

    expect(after, isNot(before));
  });
}
