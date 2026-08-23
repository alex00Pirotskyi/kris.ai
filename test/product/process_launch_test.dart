import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/process_launch.dart';

void main() {
  group('requiresWindowsCommandShell', () {
    test('uses the command shell only for Windows batch targets', () {
      expect(
        requiresWindowsCommandShell(
          r'C:\flutter\bin\flutter.bat',
          isWindows: true,
        ),
        isTrue,
      );
      expect(
        requiresWindowsCommandShell(r'C:\tools\bootstrap.CMD', isWindows: true),
        isTrue,
      );
      expect(
        requiresWindowsCommandShell(
          r'C:\flutter\bin\cache\dart-sdk\bin\dart.exe',
          isWindows: true,
        ),
        isFalse,
      );
      expect(
        requiresWindowsCommandShell(r'C:\tools\native.exe', isWindows: true),
        isFalse,
      );
    });

    test('never requests a shell on non-Windows platforms', () {
      expect(
        requiresWindowsCommandShell('/usr/local/bin/flutter', isWindows: false),
        isFalse,
      );
      expect(
        requiresWindowsCommandShell('/tmp/script.bat', isWindows: false),
        isFalse,
      );
    });
  });

  test('native resolved executable remains a direct launch target', () async {
    final launch = await resolveProcessLaunchTarget(
      Platform.resolvedExecutable,
    );
    expect(launch.executable, Platform.resolvedExecutable);
    expect(launch.runInShell, isFalse);
  });

  test(
    'Windows batch launch target executes through the command shell',
    () async {
      if (!Platform.isWindows) {
        return;
      }
      final directory = await Directory.systemTemp.createTemp(
        'kristin-process-launch-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final script = File(
        '${directory.path}${Platform.pathSeparator}kristin-launch-test.cmd',
      );
      await script.writeAsString('@echo off\r\necho kristin-launch-ok\r\n');

      final launch = await resolveProcessLaunchTarget(script.path);
      expect(launch.executable, script.path);
      expect(launch.runInShell, isTrue);

      final result = await Process.run(
        launch.executable,
        const <String>[],
        runInShell: launch.runInShell,
      );
      expect(result.exitCode, 0);
      expect(result.stdout.toString(), contains('kristin-launch-ok'));
    },
  );
}
