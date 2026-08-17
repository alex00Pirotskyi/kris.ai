import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime.dart';
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
      plan.arguments[plan.arguments.indexOf('--sandbox-mode') + 1],
      'required',
    );
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

    const identityKeys = <String>{
      'KRISTIN_P3_RUNTIME_MANIFEST_SHA256',
      'KRISTIN_P3_RUNTIME_BUILD_SHA256',
      'KRISTIN_P3_BROWSER_REVISION',
    };
    expect(plan.environment.keys.toSet().containsAll(identityKeys), isTrue);
    if (Platform.isWindows) {
      const allowedWindowsKeys = <String>{
        ...identityKeys,
        'SYSTEMROOT',
        'WINDIR',
        'COMSPEC',
        'TEMP',
        'TMP',
        'USERPROFILE',
        'LOCALAPPDATA',
        'APPDATA',
        'PROGRAMFILES',
        'PROGRAMFILES(X86)',
        'PROGRAMDATA',
        'HOMEDRIVE',
        'HOMEPATH',
      };
      expect(plan.environment['SYSTEMROOT'], isNotEmpty);
      expect(
        plan.environment.keys.toSet().difference(allowedWindowsKeys),
        isEmpty,
      );
    } else {
      expect(plan.environment.keys.toSet(), identityKeys);
    }
  });

  test('probe launch plan rejects sandbox downgrade', () async {
    final temp = await Directory.systemTemp.createTemp('p3-sandbox-plan-');
    addTearDown(() => temp.delete(recursive: true));
    final resources = await _resources(temp.absolute);
    final state = Directory('${temp.path}${Platform.pathSeparator}state');
    await state.create();

    final valid = P3BrowserRuntimeLaunchPlan.probe(
      resources: resources,
      stateDirectory: state.absolute,
    );
    final arguments = List<String>.from(valid.arguments);
    arguments[arguments.indexOf('--sandbox-mode') + 1] = 'disabled';
    final downgraded = P3BrowserRuntimeLaunchPlan(
      executable: valid.executable,
      arguments: arguments,
      workingDirectory: valid.workingDirectory,
      environment: valid.environment,
      startupTimeout: valid.startupTimeout,
    );

    expect(
      downgraded.validate,
      throwsA(
        isA<P3BrowserRuntimeException>().having(
          (error) => error.code,
          'code',
          'browser_sandbox_mode_invalid',
        ),
      ),
    );
  });

  test(
    'ready handshake is bound to exact browser revision executable and sandbox',
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
        'sandboxMode': 'required',
      }, resources: resources);

      expect(ready.pid, 101);
      expect(ready.browserPid, 202);
      expect(ready.browserRevision, resources.browserRevision);
      expect(ready.sandboxMode, 'required');

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
          'sandboxMode': 'required',
        }, resources: resources),
        throwsA(isA<P3BrowserRuntimeException>()),
      );
      expect(
        () => P3BrowserRuntimeReady.fromJson(<String, Object?>{
          'type': 'ready',
          'schemaVersion': '1.0.0',
          'pid': 101,
          'browserPid': 202,
          'browserEngine': 'chromium',
          'browserVersion': 'test-browser',
          'browserRevision': resources.browserRevision,
          'browserExecutableSha256': resources.browserExecutableSha256,
          'protocol': 'stdio-json-v1',
          'sandboxMode': 'disabled',
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

  test('session launch plan binds exact quotas and strips parent PATH',
      () async {
    final temp = await Directory.systemTemp.createTemp('p3-session-plan-');
    addTearDown(() => temp.delete(recursive: true));
    final resources = await _resources(temp.absolute);
    final state = Directory('${temp.path}${Platform.pathSeparator}sessions');
    await state.create();
    const quotas = P3BrowserSessionQuotas(
      maxSessions: 3,
      maxPagesPerSession: 5,
      maxPersistentProfiles: 7,
    );

    final plan = P3BrowserSessionLaunchPlan.create(
      resources: resources,
      stateDirectory: state.absolute,
      quotas: quotas,
    );

    expect(plan.executable, resources.nodeExecutable);
    expect(plan.arguments.first, resources.workerScript);
    expect(plan.arguments[plan.arguments.indexOf('--mode') + 1], 'sessions');
    expect(
      plan.arguments[plan.arguments.indexOf('--max-sessions') + 1],
      '3',
    );
    expect(
      plan.arguments[plan.arguments.indexOf('--max-pages-per-session') + 1],
      '5',
    );
    expect(
      plan.arguments[plan.arguments.indexOf('--max-persistent-profiles') + 1],
      '7',
    );
    expect(plan.quotas, quotas);
    expect(plan.environment.containsKey('PATH'), isFalse);
  });

  test('session launch plan rejects quota mutation after construction',
      () async {
    final temp = await Directory.systemTemp.createTemp('p3-session-mutate-');
    addTearDown(() => temp.delete(recursive: true));
    final resources = await _resources(temp.absolute);
    final state = Directory('${temp.path}${Platform.pathSeparator}sessions');
    await state.create();
    final valid = P3BrowserSessionLaunchPlan.create(
      resources: resources,
      stateDirectory: state.absolute,
    );
    final arguments = List<String>.from(valid.arguments);
    arguments[arguments.indexOf('--max-sessions') + 1] = '16';
    final mutated = P3BrowserSessionLaunchPlan(
      executable: valid.executable,
      arguments: arguments,
      workingDirectory: valid.workingDirectory,
      environment: valid.environment,
      startupTimeout: valid.startupTimeout,
      requestTimeout: valid.requestTimeout,
      quotas: valid.quotas,
    );

    expect(
      mutated.validate,
      throwsA(
        isA<P3BrowserRuntimeException>().having(
          (error) => error.code,
          'code',
          'browser_session_quota_binding_invalid',
        ),
      ),
    );
  });

  test('session ready handshake binds service mode and exact quotas', () async {
    final temp = await Directory.systemTemp.createTemp('p3-session-ready-');
    addTearDown(() => temp.delete(recursive: true));
    final resources = await _resources(temp.absolute);
    const quotas = P3BrowserSessionQuotas(
      maxSessions: 3,
      maxPagesPerSession: 5,
      maxPersistentProfiles: 7,
    );
    final value = <String, Object?>{
      'type': 'ready',
      'schemaVersion': '1.0.0',
      'pid': 101,
      'browserPid': 202,
      'browserEngine': 'chromium',
      'browserVersion': 'test-browser',
      'browserRevision': resources.browserRevision,
      'browserExecutableSha256': resources.browserExecutableSha256,
      'protocol': 'stdio-json-v1',
      'sandboxMode': 'required',
      'serviceMode': 'sessions',
      'quotas': quotas.toJson(),
    };

    final ready = P3BrowserSessionReady.fromJson(
      value,
      resources: resources,
      expectedQuotas: quotas,
    );

    expect(ready.quotas, quotas);
    expect(ready.provenance['p3_002SessionServiceImplemented'], isTrue);
    expect(ready.provenance['persistentProfileStateLocalOnly'], isTrue);

    expect(
      () => P3BrowserSessionReady.fromJson(
        <String, Object?>{
          ...value,
          'quotas': const P3BrowserSessionQuotas(
            maxSessions: 4,
            maxPagesPerSession: 5,
            maxPersistentProfiles: 7,
          ).toJson(),
        },
        resources: resources,
        expectedQuotas: quotas,
      ),
      throwsA(
        isA<P3BrowserRuntimeException>().having(
          (error) => error.code,
          'code',
          'browser_session_ready_quota_mismatch',
        ),
      ),
    );
  });

  test('session and page response models reject inconsistent identities', () {
    final session = P3BrowserSessionInfo.fromJson(<String, Object?>{
      'sessionId': 'session_one',
      'kind': 'persistent',
      'profileId': 'work',
      'pageCount': 1,
      'createdAt': '2026-08-17T00:00:00Z',
    });
    expect(session.kind, P3BrowserSessionKind.persistent);
    expect(session.profileId, 'work');

    final page = P3BrowserPageInfo.fromJson(<String, Object?>{
      'pageId': 'page_one',
      'sessionId': 'session_one',
    });
    expect(page.pageId, 'page_one');

    expect(
      () => P3BrowserSessionInfo.fromJson(<String, Object?>{
        'sessionId': 'session_bad',
        'kind': 'ephemeral',
        'profileId': 'must-not-exist',
        'pageCount': 0,
        'createdAt': '2026-08-17T00:00:00Z',
      }),
      throwsA(isA<P3BrowserRuntimeException>()),
    );
    expect(
      () => P3BrowserPageInfo.fromJson(<String, Object?>{
        'pageId': '',
        'sessionId': 'session_one',
      }),
      throwsA(isA<P3BrowserRuntimeException>()),
    );
  });
}
