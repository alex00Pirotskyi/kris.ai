import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime_bundle.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime_process.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/product_runtime.dart';

String _join(Iterable<String> parts) => parts.join(Platform.pathSeparator);

String _dartExecutable() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    final candidate = File(
      _join(<String>[
        flutterRoot,
        'bin',
        'cache',
        'dart-sdk',
        'bin',
        Platform.isWindows ? 'dart.exe' : 'dart',
      ]),
    );
    if (candidate.existsSync()) return candidate.path;
  }
  return Platform.isWindows ? 'dart.exe' : 'dart';
}

Future<void> _writeFakeBundle(Directory dataRoot) async {
  final bundle = Directory(
    _join(<String>[dataRoot.path, 'runtime', 'p3', 'current']),
  );
  final nodeRoot = Directory(_join(<String>[bundle.path, 'node']));
  final automationHost = Directory(
    _join(<String>[bundle.path, 'automation_host']),
  );
  final browserRoot = Directory(_join(<String>[bundle.path, 'browser']));
  await nodeRoot.create(recursive: true);
  await automationHost.create(recursive: true);
  await browserRoot.create(recursive: true);

  final browserExecutable = File(
    _join(<String>[
      browserRoot.path,
      Platform.isWindows ? 'fake-browser.exe' : 'fake-browser',
    ]),
  );
  await browserExecutable.writeAsString('fake-browser-payload-v1', flush: true);
  final browserSha256 = Sha256.hex(await browserExecutable.readAsBytes());

  final workerScript = File(
    _join(<String>[automationHost.path, 'browser-runtime.mjs']),
  );
  await workerScript.writeAsString('// fake worker script identity\n', flush: true);
  final packageLock = File(
    _join(<String>[automationHost.path, 'package-lock.json']),
  );
  await packageLock.writeAsString(
    '{"name":"p3-product-runtime-fixture","lockfileVersion":3}\n',
    flush: true,
  );

  final workerSource = File(
    _join(<String>[dataRoot.path, 'p3_fake_worker.dart']),
  );
  await workerSource.writeAsString('''
import 'dart:convert';
import 'dart:io';

String valueOf(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) return '';
  return args[index + 1];
}

Future<void> main(List<String> args) async {
  stdout.writeln(jsonEncode(<String, Object?>{
    'type': 'ready',
    'schemaVersion': '1.0.0',
    'pid': pid,
    'browserPid': pid,
    'browserEngine': 'chromium',
    'browserVersion': 'p3-product-runtime-fixture-v1',
    'browserRevision': Platform.environment['KRISTIN_P3_BROWSER_REVISION'] ?? '',
    'browserExecutableSha256': '$browserSha256',
    'protocol': valueOf(args, '--protocol'),
    'sandboxMode': valueOf(args, '--sandbox-mode'),
  }));
  await stdout.flush();
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final decoded = jsonDecode(line);
    if (decoded is Map &&
        decoded['type'] == 'shutdown' &&
        decoded['schemaVersion'] == '1.0.0') {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return;
    }
  }
}
''', flush: true);

  final nodeExecutable = File(
    _join(<String>[
      nodeRoot.path,
      Platform.isWindows ? 'fake-node.exe' : 'fake-node',
    ]),
  );
  final compile = await Process.run(
    _dartExecutable(),
    <String>['compile', 'exe', workerSource.path, '-o', nodeExecutable.path],
  );
  if (compile.exitCode != 0) {
    throw StateError(
      'p3_fake_worker_compile_failed:${compile.exitCode}:${compile.stderr}',
    );
  }

  final packageLockSha256 = Sha256.hex(await packageLock.readAsBytes());
  final manifest = <String, Object?>{
    'schemaVersion': '1.0.0',
    'bundleType': 'kristin-p3-browser-runtime-v1',
    'applicationOwned': true,
    'workingDirectoryIndependent': true,
    'currentWorkingDirectoryUsed': false,
    'globalRuntimeRequired': false,
    'browserNetworkInstallRequired': false,
    'identity': <String, Object?>{
      'sourceCommit': List<String>.filled(40, 'a').join(),
      'sourceTree': List<String>.filled(40, 'b').join(),
      'runtimeBuildSha256': Sha256.text('p3-product-runtime-fixture-build'),
      'packageLockSha256': packageLockSha256,
      'nodeVersion': 'fixture-aot-v1',
      'automationHostPackageVersion': 'fixture-v1',
      'browserEngine': 'chromium',
      'browserRevision': 'fixture-chromium-revision-v1',
    },
    'resources': <String, Object?>{
      'nodeExecutable': <String, Object?>{
        'kind': 'file',
        'path': 'node/${nodeExecutable.uri.pathSegments.last}',
        'sha256': Sha256.hex(await nodeExecutable.readAsBytes()),
        'executable': true,
      },
      'browserWorker': <String, Object?>{
        'kind': 'file',
        'path': 'automation_host/browser-runtime.mjs',
        'sha256': Sha256.hex(await workerScript.readAsBytes()),
      },
      'automationHostRoot': <String, Object?>{
        'kind': 'directory',
        'path': 'automation_host',
        'treeSha256': await P3ApplicationOwnedBrowserRuntimeResolver.treeSha256(
          automationHost,
        ),
      },
      'browserExecutable': <String, Object?>{
        'kind': 'file',
        'path': 'browser/${browserExecutable.uri.pathSegments.last}',
        'sha256': browserSha256,
        'executable': true,
      },
      'browserRoot': <String, Object?>{
        'kind': 'directory',
        'path': 'browser',
        'treeSha256': await P3ApplicationOwnedBrowserRuntimeResolver.treeSha256(
          browserRoot,
        ),
      },
      'packageLock': <String, Object?>{
        'kind': 'file',
        'path': 'automation_host/package-lock.json',
        'sha256': packageLockSha256,
      },
    },
  };
  await File(
    _join(<String>[bundle.path, 'browser-runtime-manifest.v1.json']),
  ).writeAsString('${jsonEncode(manifest)}\n', flush: true);
}

Future<P3ProductRuntimeBrowserHandle> _openIsolatedHandle(
  Directory root,
) =>
    P3ProductRuntimeBrowserHandle.open(
      applicationDataRoot: root.absolute,
      stateDirectory: Directory(
        _join(<String>[root.path, 'cache', 'p3-browser-runtime']),
      ).absolute,
      executablePath: _join(<String>[root.path, 'fake-app', 'kristin']),
    );

void main() {
  test('missing browser bundle is exposed as bounded fail-closed status', () async {
    final temp = await Directory.systemTemp.createTemp('p3-product-missing-');
    addTearDown(() => temp.delete(recursive: true));

    final handle = await _openIsolatedHandle(temp);
    addTearDown(handle.close);

    expect(handle.available, isFalse);
    expect(handle.statusCode, 'p3_browser_runtime_bundle_missing');
    expect(handle.provenance['applicationOwned'], isTrue);
    expect(handle.provenance['globalRuntimeRequired'], isFalse);
    expect(handle.provenance['browserNetworkInstallRequired'], isFalse);
    expect(handle.provenance['p3_002SessionServiceImplemented'], isFalse);
    await expectLater(
      handle.probe(),
      throwsA(
        isA<P3BrowserRuntimeException>().having(
          (error) => error.code,
          'code',
          'p3_product_runtime_unavailable',
        ),
      ),
    );
  });

  test('invalid browser bundle remains blocked instead of falling back', () async {
    final temp = await Directory.systemTemp.createTemp('p3-product-invalid-');
    addTearDown(() => temp.delete(recursive: true));
    final bundle = Directory(
      _join(<String>[temp.path, 'runtime', 'p3', 'current']),
    );
    await bundle.create(recursive: true);
    await File(
      _join(<String>[bundle.path, 'browser-runtime-manifest.v1.json']),
    ).writeAsString('{}\n', flush: true);

    final handle = await _openIsolatedHandle(temp);
    addTearDown(handle.close);

    expect(handle.available, isFalse);
    expect(handle.statusCode, 'p3_browser_runtime_bundle_invalid');
    expect(handle.provenance['globalRuntimeRequired'], isFalse);
    await expectLater(
      handle.probe(),
      throwsA(isA<P3BrowserRuntimeException>()),
    );
  });

  test('ProductRuntime composes P3 probe and close waits for teardown', () async {
    final temp = await Directory.systemTemp.createTemp('p3-product-active-');
    addTearDown(() => temp.delete(recursive: true));
    await _writeFakeBundle(temp);

    final runtime = await ProductRuntime.initialize(dataRoot: temp.path);
    var closed = false;
    try {
      final handle = runtime.p3BrowserRuntime;
      expect(handle.available, isTrue);
      expect(handle.statusCode, 'p3_browser_runtime_available');
      expect(handle.provenance['applicationOwned'], isTrue);
      expect(handle.provenance['globalRuntimeRequired'], isFalse);
      expect(handle.provenance['browserNetworkInstallRequired'], isFalse);
      expect(handle.provenance['p3_002SessionServiceImplemented'], isFalse);

      final probe = handle.probe(startupTimeout: const Duration(seconds: 20));
      final stopwatch = Stopwatch()..start();
      await runtime.close();
      closed = true;
      stopwatch.stop();
      final result = await probe;

      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(500));
      expect(result.ready.sandboxMode, 'required');
      expect(result.provenance['globalRuntimeRequired'], isFalse);
      expect(result.provenance['p3_002SessionServiceImplemented'], isFalse);
      expect(handle.available, isFalse);
      expect(handle.statusCode, 'p3_product_runtime_closed');
    } finally {
      if (!closed) await runtime.close();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
