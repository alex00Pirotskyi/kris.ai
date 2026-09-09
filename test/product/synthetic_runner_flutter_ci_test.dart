import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final enabled = Platform.isLinux && Platform.environment['CI'] == 'true';

  test(
    'product gate runs the real blank-project Flutter Runner smoke',
    () async {
      final result = await Process.run(
        'flutter',
        const <String>[
          'test',
          '--no-pub',
          '--concurrency=1',
          '--reporter',
          'expanded',
          'test/product/synthetic_runner_flutter_smoke_test.dart',
        ],
        workingDirectory: Directory.current.path,
        environment: <String, String>{
          ...Platform.environment,
          'KRISTIN_RUN_REAL_FLUTTER_SMOKE': '1',
        },
        runInShell: Platform.isWindows,
      );
      if (result.stdout.toString().isNotEmpty) {
        stdout.write(result.stdout);
      }
      if (result.stderr.toString().isNotEmpty) {
        stderr.write(result.stderr);
      }
      expect(result.exitCode, 0);
    },
    skip: enabled ? false : 'runs only in the Linux product CI gate',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
