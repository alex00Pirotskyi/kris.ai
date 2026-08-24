import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P3 in-app acquisition is pinned and application owned', () {
    final lock = jsonDecode(
      File(
        'config/application_runtime_acquisition.v1.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>;
    final network = lock['networkAcquisition'] as Map<String, dynamic>;
    final windows =
        (lock['platforms'] as Map<String, dynamic>)['windows-x64']
            as Map<String, dynamic>;
    final node = windows['node'] as Map<String, dynamic>;
    final p3 = windows['p3'] as Map<String, dynamic>;

    expect(lock['nodeVersion'], '24.18.0');
    expect(lock['p3BrowserRevision'], '1228');
    expect(lock['p3BrowserVersion'], '149.0.7827.55');
    expect(lock['p3PlaywrightCoreVersion'], '1.61.1');
    expect(
      lock['p3PackageLockSha256'],
      '72d49987b5bcd7244af3934440733ae8b4462162c8c77a3595f455067cc6c8a2',
    );
    expect(network['firstPartyPinnedOnly'], isTrue);
    expect(network['globalNodeFallback'], isFalse);
    expect(network['globalBrowserFallback'], isFalse);
    expect(network['systemChromeFallback'], isFalse);
    expect(node['url'], startsWith('https://nodejs.org/dist/v24.18.0/'));
    expect(
      node['archiveSha256'],
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );
    expect(
      node['executableSha256'],
      '9a4eb5f1c29c6a2e93852ead46b999e284a6a5ca8bab4d4e241d587d025a52de',
    );
    expect(p3['browserExecutableRelativePath'], 'chrome-win64/chrome.exe');
    expect(
      p3['browserExecutableSha256'],
      'b798f9e53a98d29eb7f36f8c409f905d3184780a04d2bcb56989067194784bd1',
    );
    expect(
      p3['browserTreeSha256'],
      '8f79d93ea02accb1ea7d131742f0d3393b080b189012405e83f485c953ddbd4c',
    );
  });

  test('P3 materializer preserves sandbox and rejects fallback design', () {
    final materializer = File(
      'tool/application_runtime_materializer.mjs',
    ).readAsStringSync();
    final provisioner = File(
      'lib/product/application_runtime_provisioner.dart',
    ).readAsStringSync();
    final shell = File(
      'lib/product/runtime_provisioning_shell.dart',
    ).readAsStringSync();
    final bridge = File(
      'lib/product/product_runtime_provisioning.dart',
    ).readAsStringSync();

    expect(materializer, contains('*S-1-15-2-1'));
    expect(materializer, contains('*S-1-15-2-2'));
    expect(materializer, contains('P3 browser executable digest mismatch'));
    expect(materializer, contains('P3 browser tree digest mismatch'));
    expect(materializer, isNot(contains('--no-sandbox')));
    expect(materializer, isNot(contains('chrome.exe --')));
    expect(materializer, isNot(contains('shutil.which')));
    expect(provisioner, contains('nodejs.org'));
    expect(provisioner, contains('application_runtime_download_digest_mismatch'));
    expect(provisioner, contains('p3_windows_sandbox_acl_preparation_failed'));
    expect(shell, contains('Preparing Web Studio...'));
    expect(shell, contains("Web Studio couldn't be prepared."));
    expect(shell, contains('web-runtime-retry'));
    expect(shell, contains('web-runtime-diagnostics'));
    expect(bridge, contains('ensureBrowserRuntimeReady'));
    expect(bridge, contains('startProvisionedBrowserSessions'));
    expect(bridge, contains('attachRenderedPageLoader'));
  });
}
