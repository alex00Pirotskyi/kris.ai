import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime_bundle.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime_process.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';

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

Object? _canonicalTestValue(Object? value) {
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  if (value is List) {
    return value.map<Object?>(_canonicalTestValue).toList(growable: false);
  }
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalTestValue(value[key]),
    };
  }
  throw StateError('unsupported canonical test value');
}

String _canonicalTestJson(Map<String, Object?> value) =>
    jsonEncode(_canonicalTestValue(value));

Map<String, Object?> _downloadReceiptEnvelope({
  String sessionKind = 'ephemeral',
  String sessionId = 'session_one',
  String? profileId,
  String downloadId = 'download_fixture',
  String suggestedFilename = 'report.csv',
}) {
  final scopeId = sessionKind == 'persistent' ? profileId! : sessionId;
  final base = <String, Object?>{
    'schemaVersion': '1.0.0',
    'receiptType': 'kristin-p3-browser-download-receipt-v1',
    'downloadId': downloadId,
    'sessionId': sessionId,
    'sessionKind': sessionKind,
    'profileId': profileId,
    'pageId': 'page_one',
    'sourceUrl': 'https://example.test/export',
    'suggestedFilename': suggestedFilename,
    'content': <String, Object?>{
      'relativePath':
          'downloads/quarantine/$sessionKind/$scopeId/'
          '$downloadId/payload.bin',
      'bytes': 4,
      'sha256': Sha256.hex(<int>[1, 2, 3, 4]),
    },
    'locator': <String, Object?>{'strategy': 'testId', 'index': 0},
    'createdAt': '2026-08-17T00:00:00.000Z',
  };
  return <String, Object?>{
    ...base,
    'receiptHash': Sha256.text(canonicalJson(base)),
  };
}

Map<String, Object?> _uploadStageEnvelope({
  String sessionKind = 'ephemeral',
  String sessionId = 'session_one',
  String? profileId,
  String stageId = 'uploadstage_fixture',
  String fileName = 'evidence.bin',
  String mimeType = 'application/octet-stream',
}) {
  final base = <String, Object?>{
    'schemaVersion': '1.0.0',
    'manifestType': 'kristin-p3-browser-upload-stage-v1',
    'stageId': stageId,
    'sessionId': sessionId,
    'sessionKind': sessionKind,
    'profileId': profileId,
    'file': <String, Object?>{
      'name': fileName,
      'mimeType': mimeType,
      'relativePath': 'uploads/staging/$stageId/payload.bin',
      'bytes': 4,
      'sha256': Sha256.hex(<int>[1, 2, 3, 4]),
    },
    'createdAt': '2026-08-17T00:00:00.000Z',
  };
  return <String, Object?>{
    ...base,
    'manifestHash': Sha256.text(canonicalJson(base)),
  };
}

Map<String, Object?> _uploadReceiptEnvelope({
  Map<String, Object?>? stageEnvelope,
  String receiptId = 'uploadreceipt_fixture',
}) {
  final stage = stageEnvelope ?? _uploadStageEnvelope();
  final stageFile = Map<String, Object?>.from(stage['file']! as Map);
  final base = <String, Object?>{
    'schemaVersion': '1.0.0',
    'receiptType': 'kristin-p3-browser-upload-receipt-v1',
    'receiptId': receiptId,
    'stageId': stage['stageId'],
    'manifestHash': stage['manifestHash'],
    'sessionId': stage['sessionId'],
    'sessionKind': stage['sessionKind'],
    'profileId': stage['profileId'],
    'pageId': 'page_one',
    'file': <String, Object?>{
      'name': stageFile['name'],
      'mimeType': stageFile['mimeType'],
      'bytes': stageFile['bytes'],
      'sha256': stageFile['sha256'],
    },
    'locator': <String, Object?>{'strategy': 'label', 'index': 0},
    'transferMode': 'in-memory-buffer',
    'createdAt': '2026-08-17T00:00:00.000Z',
  };
  return <String, Object?>{
    ...base,
    'receiptHash': Sha256.text(canonicalJson(base)),
  };
}

Map<String, Object?> _observationEnvelope() {
  final screenshot = <int>[1, 2, 3, 4];
  final observation = <String, Object?>{
    'schemaVersion': '1.0.0',
    'url': 'https://example.test/form',
    'title': 'Example form',
    'dom': <String, Object?>{
      'text': '<html></html>',
      'bytes': 13,
      'truncated': false,
    },
    'visibleText': <String, Object?>{
      'text': 'Sign in',
      'bytes': 7,
      'truncated': false,
    },
    'accessibility': <String, Object?>{
      'text': '- heading "Sign in"',
      'bytes': 19,
      'truncated': false,
    },
    'forms': <Object?>[],
    'formsTruncated': false,
    'screenshot': <String, Object?>{
      'bytes': screenshot.length,
      'sha256': Sha256.hex(screenshot),
      'base64': base64Encode(screenshot),
      'mediaType': 'image/jpeg',
    },
    'console': <String, Object?>{'entries': <Object?>[], 'dropped': 0},
    'network': <String, Object?>{
      'requests': <Object?>[],
      'requestsDropped': 0,
      'responses': <Object?>[],
      'responsesDropped': 0,
    },
  };
  return <String, Object?>{
    'sessionId': 'session_one',
    'pageId': 'page_one',
    'observationHash': Sha256.text(_canonicalTestJson(observation)),
    'observation': observation,
  };
}

void main() {
  test('local navigation request is loopback-only and bounded', () {
    expect(
      const P3BrowserLocalNavigationRequest(
        url: 'http://127.0.0.1:3000/index.html',
      ).toJson(),
      <String, Object?>{
        'url': 'http://127.0.0.1:3000/index.html',
        'timeoutMs': 30000,
      },
    );
    expect(
      const P3BrowserLocalNavigationRequest(url: 'about:blank').toJson()['url'],
      'about:blank',
    );
    for (final value in <String>[
      'https://example.com/',
      'file:///tmp/index.html',
      'javascript:alert(1)',
      'http://user:secret@127.0.0.1:3000/',
    ]) {
      expect(
        () => P3BrowserLocalNavigationRequest(url: value).toJson(),
        throwsA(
          isA<P3BrowserRuntimeException>().having(
            (error) => error.code,
            'code',
            'browser_local_navigation_target_forbidden',
          ),
        ),
      );
    }
  });

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

  test(
    'session launch plan binds exact quotas and strips parent PATH',
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
      expect(plan.arguments[plan.arguments.indexOf('--max-sessions') + 1], '3');
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
    },
  );

  test(
    'session launch plan rejects quota mutation after construction',
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
    },
  );

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
      'downloadPolicy': const P3BrowserDownloadPolicy().toJson(),
      'uploadPolicy': const P3BrowserUploadPolicy().toJson(),
    };

    final ready = P3BrowserSessionReady.fromJson(
      value,
      resources: resources,
      expectedQuotas: quotas,
    );

    expect(ready.quotas, quotas);
    expect(ready.downloadPolicy, const P3BrowserDownloadPolicy());
    expect(ready.uploadPolicy, const P3BrowserUploadPolicy());
    expect(ready.provenance['p3_002SessionServiceImplemented'], isTrue);
    expect(ready.provenance['p3_006aDownloadQuarantineImplemented'], isTrue);
    expect(ready.provenance['p3_006bUploadStagingImplemented'], isTrue);
    expect(ready.provenance['persistentProfileStateLocalOnly'], isTrue);
    expect(ready.provenance['downloadQuarantineApplicationOwned'], isTrue);
    expect(ready.provenance['uploadStagingApplicationOwned'], isTrue);
    expect(ready.provenance['uploadReceiptValidationIndependent'], isTrue);
    expect(ready.provenance['uploadBrowserTransferMode'], 'in-memory-buffer');

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
    expect(
      () => P3BrowserSessionReady.fromJson(
        <String, Object?>{
          ...value,
          'downloadPolicy': const P3BrowserDownloadPolicy(
            maxPayloadBytes: 1024,
            maxQuarantineBytes: 1024,
          ).toJson(),
        },
        resources: resources,
        expectedQuotas: quotas,
      ),
      throwsA(
        isA<P3BrowserRuntimeException>().having(
          (error) => error.code,
          'code',
          'browser_session_ready_download_policy_mismatch',
        ),
      ),
    );
    expect(
      () => P3BrowserSessionReady.fromJson(
        <String, Object?>{
          ...value,
          'uploadPolicy': const P3BrowserUploadPolicy(
            maxPayloadBytes: 1024,
            maxStagingBytes: 1024,
          ).toJson(),
        },
        resources: resources,
        expectedQuotas: quotas,
      ),
      throwsA(
        isA<P3BrowserRuntimeException>().having(
          (error) => error.code,
          'code',
          'browser_session_ready_upload_policy_mismatch',
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
      'downloadsEnabled': true,
      'uploadsEnabled': true,
      'createdAt': '2026-08-17T00:00:00Z',
    });
    expect(session.kind, P3BrowserSessionKind.persistent);
    expect(session.profileId, 'work');
    expect(session.downloadsEnabled, isTrue);
    expect(session.uploadsEnabled, isTrue);

    final page = P3BrowserPageInfo.fromJson(<String, Object?>{
      'pageId': 'page_one',
      'sessionId': 'session_one',
    });
    expect(page.pageId, 'page_one');
    expect(page.sessionId, 'session_one');

    expect(
      () => P3BrowserSessionInfo.fromJson(<String, Object?>{
        'sessionId': 'session_bad',
        'kind': 'ephemeral',
        'profileId': 'must-not-exist',
        'pageCount': 0,
        'downloadsEnabled': false,
        'uploadsEnabled': false,
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

  test('download policy and request enforce exact product bounds', () {
    final policy = P3BrowserDownloadPolicy.fromJson(
      const P3BrowserDownloadPolicy().toJson(),
    );
    expect(policy, const P3BrowserDownloadPolicy());
    expect(policy.maxPayloadBytes, 128 * 1024 * 1024);
    expect(
      () => P3BrowserDownloadPolicy.fromJson(<String, Object?>{
        ...const P3BrowserDownloadPolicy().toJson(),
        'maxPayloadBytes': 128 * 1024 * 1024 + 1,
      }),
      throwsA(
        isA<P3BrowserRuntimeException>().having(
          (error) => error.code,
          'code',
          'browser_download_limits_invalid',
        ),
      ),
    );

    final request = P3BrowserDownloadRequest(
      locators: <P3BrowserLocator>[
        P3BrowserLocator.testId('download-report'),
        P3BrowserLocator.text('Download report', exact: true),
      ],
      timeout: const Duration(seconds: 45),
    ).toJson();
    expect(request['timeoutMs'], 45000);
    expect((request['locators']! as List).length, 2);
    expect(request.containsKey('path'), isFalse);
    expect(
      () => const P3BrowserDownloadRequest(
        locators: <P3BrowserLocator>[],
      ).toJson(),
      throwsA(isA<P3BrowserRuntimeException>()),
    );
    expect(
      () => P3BrowserDownloadRequest(
        locators: <P3BrowserLocator>[
          P3BrowserLocator.testId('download-report'),
        ],
        timeout: const Duration(seconds: 61),
      ).toJson(),
      throwsA(isA<P3BrowserRuntimeException>()),
    );
  });

  test(
    'download receipt independently binds identity, path, payload and hash',
    () {
      final envelope = _downloadReceiptEnvelope();
      expect(
        envelope['receiptHash'],
        'e39dd7a3849bea6dc1210691b3a4614c8bf13852b4e5e09d563b04d92e870c4e',
      );
      final receipt = P3BrowserDownloadReceipt.fromJson(envelope);
      expect(receipt.downloadId, 'download_fixture');
      expect(receipt.sessionKind, P3BrowserSessionKind.ephemeral);
      expect(receipt.profileId, isNull);
      expect(receipt.bytes, 4);
      expect(receipt.suggestedFilename, 'report.csv');
      expect(receipt.locatorStrategy, 'testId');
      expect(receipt.locatorIndex, 0);

      expect(
        () => P3BrowserDownloadReceipt.fromJson(<String, Object?>{
          ...envelope,
          'sourceUrl': 'https://example.test/tampered',
        }),
        throwsA(
          isA<P3BrowserRuntimeException>().having(
            (error) => error.code,
            'code',
            'browser_download_receipt_hash_mismatch',
          ),
        ),
      );

      final wrongPath = Map<String, Object?>.from(envelope);
      wrongPath['content'] = <String, Object?>{
        ...Map<String, Object?>.from(envelope['content']! as Map),
        'relativePath': '../escape/report.csv',
      };
      final wrongPathBase = Map<String, Object?>.from(wrongPath)
        ..remove('receiptHash');
      wrongPath['receiptHash'] = Sha256.text(canonicalJson(wrongPathBase));
      expect(
        () => P3BrowserDownloadReceipt.fromJson(wrongPath),
        throwsA(
          isA<P3BrowserRuntimeException>().having(
            (error) => error.code,
            'code',
            'browser_download_receipt_invalid',
          ),
        ),
      );

      final persistent = _downloadReceiptEnvelope(
        sessionKind: 'persistent',
        profileId: 'work',
      );
      final persistentReceipt = P3BrowserDownloadReceipt.fromJson(persistent);
      expect(persistentReceipt.profileId, 'work');
      expect(
        persistentReceipt.payloadRelativePath,
        'downloads/quarantine/persistent/work/download_fixture/payload.bin',
      );

      expect(
        () => P3BrowserDownloadReceipt.fromJson(<String, Object?>{
          ...envelope,
          'unexpected': true,
        }),
        throwsA(isA<P3BrowserRuntimeException>()),
      );
    },
  );

  test('upload policy and staging request enforce exact product bounds', () {
    final policy = P3BrowserUploadPolicy.fromJson(
      const P3BrowserUploadPolicy().toJson(),
    );
    expect(policy, const P3BrowserUploadPolicy());
    expect(policy.maxPayloadBytes, 32 * 1024 * 1024);
    expect(policy.maxStagingBytes, 32 * 1024 * 1024);
    expect(
      () => P3BrowserUploadPolicy.fromJson(<String, Object?>{
        ...const P3BrowserUploadPolicy().toJson(),
        'maxPayloadBytes': 32 * 1024 * 1024 + 1,
      }),
      throwsA(
        isA<P3BrowserRuntimeException>().having(
          (error) => error.code,
          'code',
          'browser_upload_limits_invalid',
        ),
      ),
    );

    final stageRequest = const P3BrowserUploadStageRequest(
      sourcePath: '/tmp/source.bin',
      fileName: '../unsafe\\evidence?.bin ',
      mimeType: 'APPLICATION/OCTET-STREAM',
    ).toJson();
    expect(stageRequest['sourcePath'], '/tmp/source.bin');
    expect(stageRequest['fileName'], 'evidence_.bin');
    expect(stageRequest['mimeType'], 'application/octet-stream');
    expect(stageRequest.containsKey('stageId'), isFalse);
    expect(
      () => const P3BrowserUploadStageRequest(
        sourcePath: 'relative/source.bin',
        fileName: 'source.bin',
      ).toJson(),
      throwsA(
        isA<P3BrowserRuntimeException>().having(
          (error) => error.code,
          'code',
          'browser_upload_source_path_invalid',
        ),
      ),
    );
  });

  test('upload manifest independently binds stage identity and payload', () {
    final envelope = _uploadStageEnvelope();
    expect(
      envelope['manifestHash'],
      '209d1dcb2cfe3bc1dac0375d68128d0223d1d76b28bcdb19f239701b8796b082',
    );
    final stage = P3BrowserUploadStage.fromJson(envelope);
    expect(stage.stageId, 'uploadstage_fixture');
    expect(stage.sessionId, 'session_one');
    expect(stage.sessionKind, P3BrowserSessionKind.ephemeral);
    expect(stage.profileId, isNull);
    expect(stage.fileName, 'evidence.bin');
    expect(stage.mimeType, 'application/octet-stream');
    expect(stage.bytes, 4);
    expect(
      stage.payloadRelativePath,
      'uploads/staging/uploadstage_fixture/payload.bin',
    );

    final request = P3BrowserUploadRequest(
      locators: <P3BrowserLocator>[P3BrowserLocator.label('Upload evidence')],
      stage: stage,
      timeout: const Duration(seconds: 45),
    ).toJson();
    expect(request['timeoutMs'], 45000);
    final identity = Map<String, Object?>.from(request['stage']! as Map);
    expect(identity['stageId'], stage.stageId);
    expect(identity['manifestHash'], stage.manifestHash);
    expect(identity['bytes'], stage.bytes);
    expect(identity.containsKey('sourcePath'), isFalse);
    expect(identity.containsKey('path'), isFalse);

    final tampered = Map<String, Object?>.from(envelope);
    tampered['file'] = <String, Object?>{
      ...Map<String, Object?>.from(envelope['file']! as Map),
      'bytes': 5,
    };
    expect(
      () => P3BrowserUploadStage.fromJson(tampered),
      throwsA(
        isA<P3BrowserRuntimeException>().having(
          (error) => error.code,
          'code',
          'browser_upload_manifest_hash_mismatch',
        ),
      ),
    );

    final persistent = P3BrowserUploadStage.fromJson(
      _uploadStageEnvelope(sessionKind: 'persistent', profileId: 'work'),
    );
    expect(persistent.profileId, 'work');
    expect(
      persistent.payloadRelativePath,
      'uploads/staging/uploadstage_fixture/payload.bin',
    );

    expect(
      () => P3BrowserUploadStage.fromJson(<String, Object?>{
        ...envelope,
        'unexpected': true,
      }),
      throwsA(isA<P3BrowserRuntimeException>()),
    );
  });

  test(
    'upload receipt independently binds stage, browser effect, and hash',
    () {
      final envelope = _uploadReceiptEnvelope();
      expect(
        envelope['receiptHash'],
        '6500b6211d64dfd0d84611fd3bc622e666195f838e39ead08d61755d63069d6d',
      );
      final receipt = P3BrowserUploadReceipt.fromJson(envelope);
      expect(receipt.receiptId, 'uploadreceipt_fixture');
      expect(receipt.stageId, 'uploadstage_fixture');
      expect(
        receipt.manifestHash,
        '209d1dcb2cfe3bc1dac0375d68128d0223d1d76b28bcdb19f239701b8796b082',
      );
      expect(receipt.sessionId, 'session_one');
      expect(receipt.pageId, 'page_one');
      expect(receipt.fileName, 'evidence.bin');
      expect(receipt.mimeType, 'application/octet-stream');
      expect(receipt.bytes, 4);
      expect(receipt.locatorStrategy, 'label');
      expect(receipt.locatorIndex, 0);
      expect(receipt.toJson()['transferMode'], 'in-memory-buffer');

      final tampered = Map<String, Object?>.from(envelope);
      tampered['file'] = <String, Object?>{
        ...Map<String, Object?>.from(envelope['file']! as Map),
        'bytes': 5,
      };
      expect(
        () => P3BrowserUploadReceipt.fromJson(tampered),
        throwsA(
          isA<P3BrowserRuntimeException>().having(
            (error) => error.code,
            'code',
            'browser_upload_receipt_hash_mismatch',
          ),
        ),
      );

      final wrongTransfer = <String, Object?>{
        ...envelope,
        'transferMode': 'filesystem-path',
      };
      final wrongTransferBase = Map<String, Object?>.from(wrongTransfer)
        ..remove('receiptHash');
      wrongTransfer['receiptHash'] = Sha256.text(
        canonicalJson(wrongTransferBase),
      );
      expect(
        () => P3BrowserUploadReceipt.fromJson(wrongTransfer),
        throwsA(
          isA<P3BrowserRuntimeException>().having(
            (error) => error.code,
            'code',
            'browser_upload_receipt_invalid',
          ),
        ),
      );

      final persistentStage = _uploadStageEnvelope(
        sessionKind: 'persistent',
        profileId: 'work',
      );
      final persistent = P3BrowserUploadReceipt.fromJson(
        _uploadReceiptEnvelope(stageEnvelope: persistentStage),
      );
      expect(persistent.profileId, 'work');

      expect(
        () => P3BrowserUploadReceipt.fromJson(<String, Object?>{
          ...envelope,
          'unexpected': true,
        }),
        throwsA(isA<P3BrowserRuntimeException>()),
      );
    },
  );

  test('page observation validates canonical hash and screenshot binding', () {
    final envelope = _observationEnvelope();
    final parsed = P3BrowserPageObservation.fromJson(envelope);
    expect(parsed.sessionId, 'session_one');
    expect(parsed.pageId, 'page_one');
    expect(parsed.observationHash, envelope['observationHash']);

    final tamperedObservation = Map<String, Object?>.from(
      envelope['observation']! as Map,
    )..['title'] = 'Tampered';
    expect(
      () => P3BrowserPageObservation.fromJson(<String, Object?>{
        ...envelope,
        'observation': tamperedObservation,
      }),
      throwsA(
        isA<P3BrowserRuntimeException>().having(
          (error) => error.code,
          'code',
          'browser_observation_hash_invalid',
        ),
      ),
    );

    final screenshot = Map<String, Object?>.from(
      (envelope['observation']! as Map)['screenshot']! as Map,
    )..['base64'] = base64Encode(<int>[9, 9, 9, 9]);
    final tamperedScreenshot = Map<String, Object?>.from(
      envelope['observation']! as Map,
    )..['screenshot'] = screenshot;
    expect(
      () => P3BrowserPageObservation.fromJson(<String, Object?>{
        ...envelope,
        'observationHash': Sha256.text(_canonicalTestJson(tamperedScreenshot)),
        'observation': tamperedScreenshot,
      }),
      throwsA(
        isA<P3BrowserRuntimeException>().having(
          (error) => error.code,
          'code',
          'browser_observation_screenshot_binding_invalid',
        ),
      ),
    );
  });

  test(
    'structured action request and result reject ambiguity-prone payloads',
    () {
      final request = P3BrowserActionRequest(
        action: P3BrowserActionKind.fill,
        locators: <P3BrowserLocator>[
          P3BrowserLocator.role('textbox', 'Email', exact: true),
          P3BrowserLocator.label('Email address', exact: true),
          P3BrowserLocator.css('#email'),
        ],
        value: 'person+secret@example.test',
      );
      final json = request.toJson();
      expect(json['action'], 'fill');
      expect((json['locators']! as List).length, 3);
      expect(json.containsKey('x'), isFalse);
      expect(json.containsKey('y'), isFalse);

      final result = P3BrowserActionResult.fromJson(<String, Object?>{
        'sessionId': 'session_one',
        'pageId': 'page_one',
        'action': 'fill',
        'locatorStrategy': 'label',
        'locatorIndex': 1,
        'sensitiveInputProvided': true,
        'beforeObservationHash': _hex('a', 64),
        'afterObservationHash': _hex('b', 64),
        'observationChanged': true,
      });
      expect(result.action, P3BrowserActionKind.fill);
      expect(result.locatorStrategy, 'label');
      expect(result.sensitiveInputProvided, isTrue);

      expect(
        () => P3BrowserActionRequest(
          action: P3BrowserActionKind.drag,
          locators: <P3BrowserLocator>[P3BrowserLocator.testId('source')],
        ).toJson(),
        throwsA(isA<P3BrowserRuntimeException>()),
      );
      expect(
        () => P3BrowserActionResult.fromJson(<String, Object?>{
          'sessionId': 'session_one',
          'pageId': 'page_one',
          'action': 'click',
          'locatorStrategy': 'role',
          'locatorIndex': 0,
          'sensitiveInputProvided': false,
          'beforeObservationHash': _hex('a', 64),
          'afterObservationHash': _hex('a', 64),
          'observationChanged': true,
        }),
        throwsA(isA<P3BrowserRuntimeException>()),
      );
    },
  );

  test(
    'verified visual action request binds screenshot, confidence, and postcondition',
    () {
      final request = P3BrowserVisualActionRequest(
        action: P3BrowserActionKind.click,
        locators: <P3BrowserLocator>[
          P3BrowserLocator.text('Continue', exact: true),
        ],
        visualSource: P3BrowserVisualSource(
          observationHash: _hex('a', 64),
          screenshotSha256: _hex('b', 64),
          viewportWidth: 1280,
          viewportHeight: 720,
        ),
        visualTarget: const P3BrowserVisualTarget(
          x: 100,
          y: 120,
          width: 80,
          height: 40,
          confidence: 0.97,
          description: 'Continue button',
        ),
        minimumConfidence: 0.95,
        verification: const P3BrowserVisualVerification(
          expectedUrlPrefix: 'https://example.test/',
        ),
      );

      final json = request.toJson();
      expect(json['action'], 'click');
      expect(json['minimumConfidence'], 0.95);
      expect((json['visualSource']! as Map)['observationHash'], _hex('a', 64));
      expect((json['visualTarget']! as Map)['confidence'], 0.97);
      expect(json.containsKey('x'), isFalse);

      expect(
        () => P3BrowserVisualActionRequest(
          action: P3BrowserActionKind.drag,
          locators: <P3BrowserLocator>[P3BrowserLocator.testId('source')],
          visualSource: P3BrowserVisualSource(
            observationHash: _hex('a', 64),
            screenshotSha256: _hex('b', 64),
            viewportWidth: 1280,
            viewportHeight: 720,
          ),
          visualTarget: const P3BrowserVisualTarget(
            x: 1,
            y: 1,
            width: 20,
            height: 20,
            confidence: 1,
            description: 'source',
          ),
        ).toJson(),
        throwsA(
          isA<P3BrowserRuntimeException>().having(
            (error) => error.code,
            'code',
            'browser_action_target_locator_invalid',
          ),
        ),
      );
      expect(
        () => P3BrowserVisualActionRequest(
          action: P3BrowserActionKind.click,
          locators: <P3BrowserLocator>[P3BrowserLocator.testId('button')],
          visualSource: P3BrowserVisualSource(
            observationHash: _hex('a', 64),
            screenshotSha256: _hex('b', 64),
            viewportWidth: 1280,
            viewportHeight: 720,
          ),
          visualTarget: const P3BrowserVisualTarget(
            x: 1,
            y: 1,
            width: 20,
            height: 20,
            confidence: 1,
            description: 'button',
          ),
          minimumConfidence: 0.89,
        ).toJson(),
        throwsA(
          isA<P3BrowserRuntimeException>().having(
            (error) => error.code,
            'code',
            'browser_visual_confidence_invalid',
          ),
        ),
      );
    },
  );

  test(
    'verified visual action result distinguishes execution from takeover',
    () {
      final executed = P3BrowserVisualActionResult.fromJson(<String, Object?>{
        'sessionId': 'session_one',
        'pageId': 'page_one',
        'action': 'click',
        'disposition': 'executed',
        'executionMode': 'visual',
        'structuredFailureCode': 'browser_locator_ambiguous',
        'minimumConfidence': 0.95,
        'visualConfidence': 0.97,
        'beforeObservationHash': _hex('a', 64),
        'beforeScreenshotSha256': _hex('1', 64),
        'afterObservationHash': _hex('b', 64),
        'afterScreenshotSha256': _hex('2', 64),
        'observationChanged': true,
        'verified': true,
      });
      expect(executed.disposition, P3BrowserVisualActionDisposition.executed);
      expect(executed.executionMode, P3BrowserVisualExecutionMode.visual);
      expect(executed.structuredFailureCode, 'browser_locator_ambiguous');
      expect(executed.visualConfidence, 0.97);
      expect(executed.verified, isTrue);

      final paused = P3BrowserVisualActionResult.fromJson(<String, Object?>{
        'sessionId': 'session_one',
        'pageId': 'page_one',
        'action': 'click',
        'disposition': 'user_takeover_required',
        'executionMode': 'visual',
        'structuredFailureCode': 'browser_locator_not_found',
        'minimumConfidence': 0.9,
        'visualConfidence': 0.82,
        'beforeObservationHash': _hex('a', 64),
        'beforeScreenshotSha256': _hex('1', 64),
        'observationChanged': false,
        'verified': false,
        'pauseReason': 'browser_visual_target_low_confidence',
      });
      expect(
        paused.disposition,
        P3BrowserVisualActionDisposition.userTakeoverRequired,
      );
      expect(paused.afterObservationHash, isNull);
      expect(paused.pauseReason, 'browser_visual_target_low_confidence');

      expect(
        () => P3BrowserVisualActionResult.fromJson(<String, Object?>{
          'sessionId': 'session_one',
          'pageId': 'page_one',
          'action': 'click',
          'disposition': 'user_takeover_required',
          'executionMode': 'visual',
          'structuredFailureCode': 'browser_locator_not_found',
          'minimumConfidence': 0.9,
          'visualConfidence': 0.82,
          'beforeObservationHash': _hex('a', 64),
          'beforeScreenshotSha256': _hex('1', 64),
          'afterObservationHash': _hex('b', 64),
          'afterScreenshotSha256': _hex('2', 64),
          'observationChanged': true,
          'verified': false,
          'pauseReason': 'browser_visual_target_low_confidence',
        }),
        throwsA(isA<P3BrowserRuntimeException>()),
      );
    },
  );
}
