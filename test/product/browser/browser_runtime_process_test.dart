import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime_bundle.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime_process.dart';

String _hex(String value, int length) =>
    List<String>.filled(length, value).join();

Future<P3BrowserRuntimeResourceSet> _resources(Directory root) async {
  final node = File('${root.path}${Platform.pathSeparator}node-bin');
  final worker = File('${root.path}${Platform.pathSeparator}worker.mjs');
  final browser = File('${root.path}${Platform.pathSeparator}browser-bin');
  final manifest = File('${root.path}${Platform.pathSeparator}manifest.json');
  final lock = File('${root.path}${Platform.pathSeparator}package-lock.json');
  final browserRoot = Directory('${root.path}${Platform.pathSeparator}browser');
  final working = Directory('${root.path}${Platform.pathSeparator}host');
  await browserRoot.create(recursive: true);
  await working.create(recursive: true);
  await node.writeAsString('node');
  await worker.writeAsString('worker');
  await browser.writeAsString('browser');
  await manifest.writeAsString('{}');
  await lock.writeAsString('{}');
  return P3BrowserRuntimeResourceSet(
    root: root,
    manifestPath: manifest.path,
    manifestSha256: _hex('a', 64),
    sourceCommit: _hex('b', 40),
    sourceTree: _hex('c', 40),
    runtimeBuildSha256: _hex('d', 64),
    nodeVersion: '24.18.0',
    automationHostPackageVersion: '2.0.0-p3.1',
    browserEngine: 'chromium',
    browserRevision: 'chromium-test-revision',
    nodeExecutable: node.path,
    nodeExecutableSha256: _hex('e', 64),
    workerScript: worker.path,
    workerScriptSha256: _hex('f', 64),
    workingDirectory: working.path,
    browserExecutable: browser.path,
    browserExecutableSha256: _hex('1', 64),
    browserRoot: browserRoot.path,
    browserRootTreeSha256: _hex('2', 64),
    packageLock: lock.path,
    packageLockSha256: _hex('3', 64),
  );
}

void main() {
  test('probe launch plan uses only bundled node and browser paths', () async {
    final temp = await Directory.systemTemp.createTemp('p3-launch-plan-');
    addTearDown(() => temp.delete(recursive: true));
    final resources = await _resources(temp.absolute);
    final state = Directory('${temp.path}${Platform.pathSeparator}state');
    await state.create();

    final plan = P3BrowserRuntimeLaunchPlan.probe(
      resources: resources,
      stateDirectory: state.absolute,
    );

    expect(plan.executable, resources.nodeExecutable);
    expect(plan.arguments.first, resources.workerScript);
    expect(
      plan.arguments[plan.arguments.indexOf('--browser-executable') + 1],
      resources.browserExecutable,
    );
    expect(
      plan.arguments[plan.arguments.indexOf('--browser-root') + 1],
      resources.browserRoot,
    );
    expect(plan.workingDirectory, resources.workingDirectory);
    expect(plan.environment.containsKey('PATH'), isFalse);
    expect(plan.environment.keys.toSet(), <String>{
      'KRISTIN_P3_RUNTIME_MANIFEST_SHA256',
      'KRISTIN_P3_RUNTIME_BUILD_SHA256',
      'KRISTIN_P3_BROWSER_REVISION',
    });
  });

  test(
    'ready handshake is bound to exact browser revision and executable',
    () async {
      final temp = await Directory.systemTemp.createTemp('p3-ready-');
      addTearDown(() => temp.delete(recursive: true));
      final resources = await _resources(temp.absolute);

      final ready = P3BrowserRuntimeReady.fromJson(<String, Object?>{
        'type': 'ready',
        'schemaVersion': '1.0.0',
        'pid': 101,
        'browserPid': 202,
        'browserEngine': 'chromium',
        'browserVersion': 'test-browser',
        'browserRevision': resources.browserRevision,
        'browserExecutableSha256': resources.browserExecutableSha256,
        'protocol': 'stdio-json-v1',
      }, resources: resources);

      expect(ready.pid, 101);
      expect(ready.browserPid, 202);
      expect(ready.browserRevision, resources.browserRevision);

      expect(
        () => P3BrowserRuntimeReady.fromJson(<String, Object?>{
          'type': 'ready',
          'schemaVersion': '1.0.0',
          'pid': 101,
          'browserPid': 202,
          'browserEngine': 'chromium',
          'browserVersion': 'test-browser',
          'browserRevision': 'different-revision',
          'browserExecutableSha256': resources.browserExecutableSha256,
          'protocol': 'stdio-json-v1',
        }, resources: resources),
        throwsA(isA<P3BrowserRuntimeException>()),
      );
    },
  );

  test(
    'probe plan rejects a missing bundled node instead of falling back',
    () async {
      final temp = await Directory.systemTemp.createTemp('p3-missing-node-');
      addTearDown(() => temp.delete(recursive: true));
      final resources = await _resources(temp.absolute);
      await File(resources.nodeExecutable).delete();
      final state = Directory('${temp.path}${Platform.pathSeparator}state');
      await state.create();

      expect(
        () => P3BrowserRuntimeLaunchPlan.probe(
          resources: resources,
          stateDirectory: state.absolute,
        ),
        throwsA(
          isA<P3BrowserRuntimeException>().having(
            (error) => error.code,
            'code',
            'bundled_node_executable_required',
          ),
        ),
      );
    },
  );
}
