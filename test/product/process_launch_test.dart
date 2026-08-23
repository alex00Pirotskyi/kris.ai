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
        requiresWindowsCommandShell(
          r'C:\tools\bootstrap.CMD',
          isWindows: true,
        ),
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
        requiresWindowsCommandShell(
          r'C:\tools\native.exe',
          isWindows: true,
        ),
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
}
