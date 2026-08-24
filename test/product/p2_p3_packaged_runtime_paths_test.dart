import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime_bundle.dart';
import 'package:kristin_local_agent/product/p2_runtime_resource_resolver.dart';

String _nativePath(Directory root, List<String> parts) =>
    <String>[root.absolute.path, ...parts].join(Platform.pathSeparator);

void main() {
  test('P2 and P3 packaged candidates include macOS Contents Resources', () {
    final fixture = Directory.systemTemp.createTempSync(
      'kristin-p2-p3-paths-',
    );
    try {
      final data = Directory(_nativePath(fixture, <String>['kristin-data']));
      final executable = _nativePath(fixture, <String>[
        'Kristin.app',
        'Contents',
        'MacOS',
        'Kristin',
      ]);

      final p2 = P2ApplicationOwnedRuntimeResourceResolver.candidateRoots(
        applicationDataRoot: data,
        executablePath: executable,
        macOS: true,
      );
      final p3 = P3ApplicationOwnedBrowserRuntimeResolver.candidateRoots(
        applicationDataRoot: data,
        executablePath: executable,
        macOS: true,
      );

      expect(p2.length, 3);
      expect(p3.length, 3);
      expect(
        p2[1].absolute.path,
        _nativePath(fixture, <String>[
          'Kristin.app',
          'Contents',
          'Resources',
          'runtime',
          'p2',
          'current',
        ]),
      );
      expect(
        p3[1].absolute.path,
        _nativePath(fixture, <String>[
          'Kristin.app',
          'Contents',
          'Resources',
          'runtime',
          'p3',
          'current',
        ]),
      );
    } finally {
      fixture.deleteSync(recursive: true);
    }
  });

  test('non-macOS packaged candidates stay beside the executable', () {
    final fixture = Directory.systemTemp.createTempSync(
      'kristin-p2-p3-paths-',
    );
    try {
      final data = Directory(_nativePath(fixture, <String>['kristin-data']));
      final executable = _nativePath(fixture, <String>[
        'opt',
        'kristin',
        'Kristin',
      ]);
      final executableRoot = File(executable).absolute.parent;
      final p2 = P2ApplicationOwnedRuntimeResourceResolver.candidateRoots(
        applicationDataRoot: data,
        executablePath: executable,
        macOS: false,
      );
      final p3 = P3ApplicationOwnedBrowserRuntimeResolver.candidateRoots(
        applicationDataRoot: data,
        executablePath: executable,
        macOS: false,
      );
      expect(p2.length, 2);
      expect(p3.length, 2);
      expect(
        p2.last.absolute.path,
        _nativePath(executableRoot, <String>['runtime', 'p2', 'current']),
      );
      expect(
        p3.last.absolute.path,
        _nativePath(executableRoot, <String>['runtime', 'p3', 'current']),
      );
    } finally {
      fixture.deleteSync(recursive: true);
    }
  });
}
