import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/application_runtime_provisioner.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';

Future<Map<String, String>> _snapshot(Directory root) async {
  final result = <String, String>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.absolute.path
        .substring(root.absolute.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    result[relative] = Sha256.hex(await entity.readAsBytes());
  }
  return result;
}

List<String> _delta(
  Map<String, String> before,
  Map<String, String> after,
) {
  final paths = <String>{...before.keys, ...after.keys}.toList()..sort();
  return paths
      .where((path) => before[path] != after[path])
      .take(32)
      .map((path) {
        if (!before.containsKey(path)) return 'added:$path';
        if (!after.containsKey(path)) return 'removed:$path';
        return 'changed:$path';
      })
      .toList(growable: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final enabled = Platform.isWindows &&
      (Platform.environment['GITHUB_WORKFLOW'] == 'product-gates' ||
          Platform.environment['KRISTIN_IN_APP_RUNTIME_ACCEPTANCE'] == '1');

  test(
    'live Windows P3 session does not mutate packaged Chromium tree',
    () async {
      final applicationDataRoot = await Directory.systemTemp.createTemp(
        'kristin-p3-immutability-',
      );
      final browserState = Directory(
        '${applicationDataRoot.path}${Platform.pathSeparator}browser-state',
      );
      final provisioner = ApplicationRuntimeProvisioner(
        applicationDataRoot: applicationDataRoot,
      );
      P3BrowserSessionProcess? process;
      String? sessionId;
      String? pageId;
      try {
        final runtime = await provisioner.ensureP3();
        final browserRoot = Directory(runtime.browserRoot);
        final before = await _snapshot(browserRoot);

        process = await P3BrowserRuntimeService(
          applicationDataRoot: applicationDataRoot,
        ).startSessions(
          stateDirectory: browserState,
          quotas: const P3BrowserSessionQuotas(
            maxSessions: 1,
            maxPagesPerSession: 1,
            maxPersistentProfiles: 1,
          ),
          startupTimeout: const Duration(seconds: 90),
          requestTimeout: const Duration(seconds: 60),
        );
        final session = await process.openSession(
          kind: P3BrowserSessionKind.ephemeral,
          blockServiceWorkers: true,
        );
        sessionId = session.sessionId;
        final page = await process.openPage(session.sessionId);
        pageId = page.pageId;

        final during = await _snapshot(browserRoot);
        final changedPaths = _delta(before, during);
        expect(
          changedPaths,
          isEmpty,
          reason: 'live P3 mutated browserRoot: ${changedPaths.join(', ')}',
        );
      } finally {
        final active = process;
        if (active != null) {
          if (sessionId != null && pageId != null) {
            try {
              await active.closePage(sessionId!, pageId!);
            } catch (_) {}
          }
          if (sessionId != null) {
            try {
              await active.closeSession(sessionId!);
            } catch (_) {}
          }
          try {
            await active.close();
          } catch (_) {}
        }
        try {
          await provisioner.close();
        } catch (_) {}
        try {
          if (await applicationDataRoot.exists()) {
            await applicationDataRoot.delete(recursive: true);
          }
        } catch (_) {}
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: enabled
        ? false
        : 'runs only in exact Windows product-gates or explicit local acceptance',
  );
}
