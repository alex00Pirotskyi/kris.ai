import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime_bundle.dart';
import 'package:kristin_local_agent/product/p2_runtime_resource_resolver.dart';

void main() {
  test('P2 and P3 packaged candidates include macOS Contents Resources', () {
    final data = Directory('/tmp/kristin-data');
    const executable = '/Applications/Kristin.app/Contents/MacOS/Kristin';

    final p2 = P2ApplicationOwnedRuntimeResourceResolver.candidateRoots(
      applicationDataRoot: data,
      executablePath: executable,
      macOS: true,
    ).map((item) => item.path).toList();
    final p3 = P3ApplicationOwnedBrowserRuntimeResolver.candidateRoots(
      applicationDataRoot: data,
      executablePath: executable,
      macOS: true,
    ).map((item) => item.path).toList();

    expect(p2.length, 3);
    expect(p3.length, 3);
    expect(p2[1], '/Applications/Kristin.app/Contents/Resources/runtime/p2/current');
    expect(p3[1], '/Applications/Kristin.app/Contents/Resources/runtime/p3/current');
  });

  test('non-macOS packaged candidates stay beside the executable', () {
    final data = Directory('/tmp/kristin-data');
    const executable = '/opt/kristin/Kristin';
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
    expect(p2.last.path, '/opt/kristin/runtime/p2/current');
    expect(p3.last.path, '/opt/kristin/runtime/p3/current');
  });
}
