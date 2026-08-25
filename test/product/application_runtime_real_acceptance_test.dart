import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _passMarker = 'APPLICATION_RUNTIME_REAL_ACCEPTANCE:PASS';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final enabled = Platform.isWindows &&
      (Platform.environment['GITHUB_WORKFLOW'] == 'product-gates' ||
          Platform.environment['KRISTIN_IN_APP_RUNTIME_ACCEPTANCE'] == '1');

  test(
    'clean source checkout provisions and boots real P2 and P3 in app',
    () async {
      final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
      expect(flutterRoot, isNotEmpty, reason: 'FLUTTER_ROOT is required');
      final dartExecutable = File(
        '$flutterRoot${Platform.pathSeparator}bin${Platform.pathSeparator}cache'
        '${Platform.pathSeparator}dart-sdk${Platform.pathSeparator}bin'
        '${Platform.pathSeparator}dart.exe',
      );
      expect(
        await dartExecutable.exists(),
        isTrue,
        reason: 'exact Flutter SDK Dart executable is required',
      );

      final process = await Process.start(
        dartExecutable.path,
        const <String>[
          'run',
          'tool/application_runtime_real_acceptance.dart',
        ],
        workingDirectory: Directory.current.path,
        environment: Platform.environment,
        includeParentEnvironment: false,
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(
        const Duration(minutes: 15),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      final childStdout = await stdoutFuture;
      final childStderr = await stderrFuture;

      expect(
        exitCode,
        0,
        reason: 'plain Dart runtime acceptance failed\n'
            'stdout:\n$childStdout\n'
            'stderr:\n$childStderr',
      );
      expect(
        childStdout,
        contains(_passMarker),
        reason: 'plain Dart runtime acceptance did not emit PASS marker',
      );
    },
    timeout: const Timeout(Duration(minutes: 16)),
    skip: enabled
        ? false
        : 'runs only in exact Windows product-gates or explicit local acceptance',
  );
}
