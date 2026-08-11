import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime_bundle.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';

String _hex(String value, int length) =>
    List<String>.filled(length, value).join();

Future<Directory> _writeBundle(
  Directory dataRoot, {
  bool globalRuntimeRequired = false,
}) async {
  final root = Directory(
    '${dataRoot.path}${Platform.pathSeparator}'
    'runtime${Platform.pathSeparator}p3${Platform.pathSeparator}current',
  );
  final node = File(
    '${root.path}${Platform.pathSeparator}node${Platform.pathSeparator}node-bin',
  );
  final worker = File(
    '${root.path}${Platform.pathSeparator}automation_host'
    '${Platform.pathSeparator}src${Platform.pathSeparator}browser-runtime.mjs',
  );
  final packageLock = File(
    '${root.path}${Platform.pathSeparator}automation_host'
    '${Platform.pathSeparator}package-lock.json',
  );
  final browser = File(
    '${root.path}${Platform.pathSeparator}browser'
    '${Platform.pathSeparator}chromium-bin',
  );
  await node.parent.create(recursive: true);
  await worker.parent.create(recursive: true);
  await browser.parent.create(recursive: true);
  await node.writeAsString('bundled-node\n');
  await worker.writeAsString('console.log("ready");\n');
  await packageLock.writeAsString('{"lockfileVersion":3}\n');
  await browser.writeAsString('bundled-browser\n');
  await File(
    '${browser.parent.path}${Platform.pathSeparator}resources.pak',
  ).writeAsString('browser-resource\n');

  final automationHostTree =
      await P3ApplicationOwnedBrowserRuntimeResolver.treeSha256(
    worker.parent.parent,
  );
  final browserTree = await P3ApplicationOwnedBrowserRuntimeResolver.treeSha256(
    browser.parent,
  );
  final packageLockSha = Sha256.hex(await packageLock.readAsBytes());
  final manifest = <String, Object?>{
    'schemaVersion': '1.0.0',
    'bundleType': 'kristin-p3-browser-runtime-v1',
    'applicationOwned': true,
    'workingDirectoryIndependent': true,
    'currentWorkingDirectoryUsed': false,
    'globalRuntimeRequired': globalRuntimeRequired,
    'browserNetworkInstallRequired': false,
    'identity': <String, Object?>{
      'sourceCommit': _hex('a', 40),
      'sourceTree': _hex('b', 40),
      'runtimeBuildSha256': _hex('c', 64),
      'packageLockSha256': packageLockSha,
      'nodeVersion': '24.18.0',
      'automationHostPackageVersion': '2.0.0-p3.1',
      'browserEngine': 'chromium',
      'browserRevision': 'chromium-test-revision',
    },
    'resources': <String, Object?>{
      'nodeExecutable': <String, Object?>{
        'kind': 'file',
        'path': 'node/node-bin',
        'sha256': Sha256.hex(await node.readAsBytes()),
        'executable': true,
      },
      'browserWorker': <String, Object?>{
        'kind': 'file',
        'path': 'automation_host/src/browser-runtime.mjs',
        'sha256': Sha256.hex(await worker.readAsBytes()),
        'executable': false,
      },
      'automationHostRoot': <String, Object?>{
        'kind': 'directory',
        'path': 'automation_host',
        'treeSha256': automationHostTree,
      },
      'browserExecutable': <String, Object?>{
        'kind': 'file',
        'path': 'browser/chromium-bin',
        'sha256': Sha256.hex(await browser.readAsBytes()),
        'executable': true,
      },
      'browserRoot': <String, Object?>{
        'kind': 'directory',
        'path': 'browser',
        'treeSha256': browserTree,
      },
      'packageLock': <String, Object?>{
        'kind': 'file',
        'path': 'automation_host/package-lock.json',
        'sha256': packageLockSha,
        'executable': false,
      },
    },
  };
  await File(
    '${root.path}${Platform.pathSeparator}browser-runtime-manifest.v1.json',
  ).writeAsString('${jsonEncode(manifest)}\n');
  return root;
}

void main() {
  test(
    'resolves exact application-owned browser bundle without global runtime',
    () async {
      final temp = await Directory.systemTemp.createTemp('p3-browser-bundle-');
      addTearDown(() => temp.delete(recursive: true));
      final root = await _writeBundle(temp);
      final resolver = P3ApplicationOwnedBrowserRuntimeResolver(
        applicationDataRoot: temp.absolute,
        executablePath: '${temp.path}${Platform.pathSeparator}app'
            '${Platform.pathSeparator}kristin',
      );

      final resources = await resolver.resolve();

      expect(resources.root.path, root.absolute.path);
      expect(resources.nodeVersion, '24.18.0');
      expect(resources.browserEngine, 'chromium');
      expect(resources.browserRevision, 'chromium-test-revision');
      expect(File(resources.nodeExecutable).existsSync(), isTrue);
      expect(File(resources.browserExecutable).existsSync(), isTrue);
      expect(resources.provenance['applicationOwned'], isTrue);
      expect(resources.provenance['globalRuntimeRequired'], isFalse);
      expect(resources.provenance['browserNetworkInstallRequired'], isFalse);
    },
  );

  test(
    'invalid application-data current bundle cannot be masked by valid fallback',
    () async {
      final temp = await Directory.systemTemp.createTemp('p3-browser-priority-');
      addTearDown(() => temp.delete(recursive: true));
      final applicationDataRoot = Directory(
        '${temp.path}${Platform.pathSeparator}application-data',
      );
      final preferred = await _writeBundle(applicationDataRoot);
      final executableRoot = Directory(
        '${temp.path}${Platform.pathSeparator}installed-app',
      );
      final fallback = await _writeBundle(executableRoot);
      final preferredWorker = File(
        '${preferred.path}${Platform.pathSeparator}automation_host'
        '${Platform.pathSeparator}src${Platform.pathSeparator}browser-runtime.mjs',
      );
      await preferredWorker.writeAsString(
        '// tampered preferred\n',
        mode: FileMode.append,
      );
      final resolver = P3ApplicationOwnedBrowserRuntimeResolver(
        applicationDataRoot: applicationDataRoot.absolute,
        executablePath:
            '${executableRoot.path}${Platform.pathSeparator}kristin',
      );

      expect(fallback.existsSync(), isTrue);
      expect(
        resolver.resolve(),
        throwsA(
          isA<StateError>().having(
            (error) => '$error',
            'error',
            allOf(
              contains('p3_browser_runtime_bundle_invalid'),
              contains('p3_runtime_resource_digest_mismatch:browserWorker'),
            ),
          ),
        ),
      );
    },
  );

  test(
    'uses executable-root bundle only when application-data current is absent',
    () async {
      final temp = await Directory.systemTemp.createTemp('p3-browser-fallback-');
      addTearDown(() => temp.delete(recursive: true));
      final applicationDataRoot = Directory(
        '${temp.path}${Platform.pathSeparator}application-data',
      );
      await applicationDataRoot.create(recursive: true);
      final executableRoot = Directory(
        '${temp.path}${Platform.pathSeparator}installed-app',
      );
      final fallback = await _writeBundle(executableRoot);
      final resolver = P3ApplicationOwnedBrowserRuntimeResolver(
        applicationDataRoot: applicationDataRoot.absolute,
        executablePath:
            '${executableRoot.path}${Platform.pathSeparator}kristin',
      );

      final resources = await resolver.resolve();

      expect(resources.root.path, fallback.absolute.path);
      expect(resources.browserEngine, 'chromium');
    },
  );

  test(
    'rejects a tampered worker even when manifest identity is unchanged',
    () async {
      final temp = await Directory.systemTemp.createTemp('p3-browser-tamper-');
      addTearDown(() => temp.delete(recursive: true));
      final root = await _writeBundle(temp);
      final worker = File(
        '${root.path}${Platform.pathSeparator}automation_host'
        '${Platform.pathSeparator}src${Platform.pathSeparator}browser-runtime.mjs',
      );
      await worker.writeAsString('// tampered\n', mode: FileMode.append);
      final resolver = P3ApplicationOwnedBrowserRuntimeResolver(
        applicationDataRoot: temp.absolute,
      );

      expect(
        resolver.resolve(),
        throwsA(
          isA<StateError>().having(
            (error) => '$error',
            'error',
            contains('p3_runtime_resource_digest_mismatch:browserWorker'),
          ),
        ),
      );
    },
  );

  test('rejects a manifest that permits global runtime fallback', () async {
    final temp = await Directory.systemTemp.createTemp('p3-browser-global-');
    addTearDown(() => temp.delete(recursive: true));
    await _writeBundle(temp, globalRuntimeRequired: true);
    final resolver = P3ApplicationOwnedBrowserRuntimeResolver(
      applicationDataRoot: temp.absolute,
    );

    expect(
      resolver.resolve(),
      throwsA(
        isA<StateError>().having(
          (error) => '$error',
          'error',
          contains('p3_browser_runtime_manifest_identity_invalid'),
        ),
      ),
    );
  });
}
