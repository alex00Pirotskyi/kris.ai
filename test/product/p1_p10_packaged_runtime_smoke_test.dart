import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime.dart';
import 'package:kristin_local_agent/product/p2_finite_command_service.dart';
import 'package:kristin_local_agent/product/p2_owner_mode.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_bootstrap.dart';
import 'package:kristin_local_agent/product/p2_runtime_resource_resolver.dart';

void main() {
  test(
    'packaged product resolves P2 and P3 and performs real host/browser work',
    () async {
      final executable =
          Platform.environment['KRISTIN_PACKAGED_APP_EXECUTABLE'] ?? '';
      expect(executable, isNotEmpty);
      final dataRoot = await Directory.systemTemp.createTemp(
        'kristin-p1-p10-package-',
      );
      try {
        final resources = await P2ApplicationOwnedRuntimeResourceResolver(
          applicationDataRoot: dataRoot,
          executablePath: executable,
        ).resolve();
        expect(
          resources
              .provisionedEnvironment['KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'],
          '1',
        );
        expect(
          resources.provisionedEnvironment.containsKey('KRISTIN_OWNER_RISK_QA'),
          false,
        );

        final handle = await P2ProductRuntimeBootstrap.start(
          dataRoot: dataRoot,
          p1AuthorityService: null,
          runtimeResources: resources,
          explicitlyProvisionedEnvironment: resources.provisionedEnvironment,
          interactiveDesktopAttested: true,
        );
        expect(handle.available, true, reason: handle.failureCode);
        final owner = handle.runtime!;
        handle.activateEffectContext(runId: 'p1-p10-package', taskId: 'P1-P10');
        await owner.controller.enable(
          unattended: true,
          approvalPolicy: P2OwnerApprovalPolicy.destructiveOnly,
          acknowledged: true,
        );
        final effects = await Directory(
          '${dataRoot.path}${Platform.pathSeparator}effects',
        ).create();
        final target = File(
          '${effects.path}${Platform.pathSeparator}packaged-owner-λ.txt',
        );
        final fs = owner.composition.filesystemService(
          Directory('${dataRoot.path}${Platform.pathSeparator}backups'),
        );
        await fs.write(
          target.path,
          Uint8List.fromList(utf8.encode('PACKAGED_P2_OK')),
          binding: owner.bindingContext.bindingFor('filesystem.write'),
        );
        final read = await fs.read(
          target.path,
          binding: owner.bindingContext.bindingFor('filesystem.read'),
          maxBytes: 65536,
        );
        expect(utf8.decode(read), 'PACKAGED_P2_OK');
        final command = await owner.composition.commandService.run(
          P2CommandSpec(
            executable: resources.nodeExecutable,
            cwd: effects.path,
            arguments: const <String>[
              '-e',
              "process.stdout.write('PACKAGED_COMMAND_OK')",
            ],
            deadline: const Duration(seconds: 20),
          ),
          binding: owner.bindingContext.bindingFor('command.run'),
        );
        expect(utf8.decode(command.stdout), 'PACKAGED_COMMAND_OK');
        await handle.close();

        final browser = P3BrowserRuntimeService(
          applicationDataRoot: dataRoot,
          executablePath: executable,
        );
        final bundle = await browser.resolveBundle();
        expect(bundle.browserEngine, 'chromium');
        final probe = await browser.probe(
          stateDirectory: Directory(
            '${dataRoot.path}${Platform.pathSeparator}p3-state',
          ),
          startupTimeout: const Duration(seconds: 45),
        );
        expect(probe.ready.browserEngine, 'chromium');
        expect(probe.ready.browserRevision, bundle.browserRevision);
      } finally {
        if (await dataRoot.exists()) {
          await dataRoot.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: (Platform.environment['KRISTIN_PACKAGED_APP_EXECUTABLE'] ?? '').isEmpty
        ? 'requires packaged P2+P3 product payload'
        : false,
  );
}
