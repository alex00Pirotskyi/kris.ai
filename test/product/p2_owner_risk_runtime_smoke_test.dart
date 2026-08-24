import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/p2_finite_command_service.dart';
import 'package:kristin_local_agent/product/p2_owner_mode.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_bootstrap.dart';
import 'package:kristin_local_agent/product/p2_runtime_resource_resolver.dart';

void main() {
  test(
    'staged current-account P1/P2 runtime launches and performs host effects',
    () async {
      const qaBuild = bool.fromEnvironment(
        'KRISTIN_OWNER_RISK_QA',
        defaultValue: false,
      );
      final productCurrentAccount =
          Platform.environment['KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'] == '1';
      expect(
        qaBuild || productCurrentAccount,
        true,
        reason: 'smoke requires staged QA or product current-account runtime',
      );

      String env(String name) {
        final value = Platform.environment[name] ?? '';
        if (value.isEmpty) fail('missing environment: $name');
        return value;
      }

      final runtimeRoot = Directory(env('KRISTIN_V70_RUNTIME_ROOT'));
      final dataRoot = await Directory.systemTemp.createTemp(
        'kristin-v70-smoke-',
      );
      final temporary = await Directory(
        '${dataRoot.path}${Platform.pathSeparator}effects',
      ).create(recursive: true);
      final manifest = File(
        '${runtimeRoot.path}${Platform.pathSeparator}runtime-manifest.v3.json',
      );
      expect(await manifest.exists(), true);
      final decoded =
          jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
      final identity = Map<String, Object?>.from(decoded['identity']! as Map);
      final resources = P2RuntimeResourceSet(
        root: runtimeRoot,
        manifestPath: manifest.path,
        manifestSha256: Sha256.hex(await manifest.readAsBytes()),
        sourceCommit: identity['sourceCommit']!.toString(),
        sourceTree: identity['sourceTree']!.toString(),
        runtimeBuildSha256: identity['runtimeBuildSha256']!.toString(),
        p1AuthorityServiceContractSha256:
            identity['p1AuthorityServiceContractSha256']!.toString(),
        nodeExecutable: env('KRISTIN_V70_NODE'),
        hostScript: env('KRISTIN_V70_HOST'),
        workingDirectory: env('KRISTIN_V70_HOST_ROOT'),
        restrictedWorkerLauncher: env('KRISTIN_V70_LAUNCHER'),
        restrictedWorkerLauncherSha256: Sha256.hex(
          await File(env('KRISTIN_V70_LAUNCHER')).readAsBytes(),
        ),
        workerPolicy: env('KRISTIN_V70_POLICY'),
        workerPolicySha256: Sha256.hex(
          await File(env('KRISTIN_V70_POLICY')).readAsBytes(),
        ),
        nodeExecutableSha256: Sha256.hex(
          await File(env('KRISTIN_V70_NODE')).readAsBytes(),
        ),
        hostScriptSha256: Sha256.hex(
          await File(env('KRISTIN_V70_HOST')).readAsBytes(),
        ),
        windowsJobHelper: Platform.environment['KRISTIN_V70_WINDOWS_HELPER'],
        posixWatchdog: Platform.environment['KRISTIN_V70_POSIX_WATCHDOG'],
        interactiveDesktopAdapter:
            Platform.environment['KRISTIN_V70_INTERACTIVE_ADAPTER'],
        provisionedEnvironment: <String, String>{
          'KRISTIN_OWNER_RISK_QA': '1',
          if (productCurrentAccount)
            'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT': '1',
        },
      );
      final handle = await P2ProductRuntimeBootstrap.start(
        dataRoot: dataRoot,
        p1AuthorityService: null,
        runtimeResources: resources,
        explicitlyProvisionedEnvironment: <String, String>{
          'KRISTIN_OWNER_RISK_QA': '1',
          if (productCurrentAccount)
            'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT': '1',
        },
        interactiveDesktopAttested: true,
      );
      expect(handle.available, true, reason: handle.failureCode);
      final owner = handle.runtime!;
      expect(owner.authority.qaPreview, !productCurrentAccount);
      expect(
        owner.authority.authorityKind,
        productCurrentAccount
            ? 'p2-current-account-owner-v1'
            : 'p2-owner-risk-current-account-v1',
      );
      handle.activateEffectContext(runId: 'v70-smoke', taskId: 'P2-QA');
      await owner.controller.enable(
        unattended: true,
        approvalPolicy: P2OwnerApprovalPolicy.destructiveOnly,
        acknowledged: true,
      );
      final supportBinding = owner.bindingContext.bindingFor(
        'host.supportMatrix',
      );
      final supportEnvelope = await owner.authority.issue(
        binding: supportBinding,
        operation: 'host.supportMatrix',
        payload: const <String, Object?>{'operation': 'host.supportMatrix'},
      );
      final support = await owner.composition.client.invoke(supportEnvelope);
      expect(support['status'], 'ok');

      final fs = owner.composition.filesystemService(
        Directory('${dataRoot.path}${Platform.pathSeparator}backups'),
      );
      final target = File(
        '${temporary.path}${Platform.pathSeparator}owner-current-account-λ.txt',
      );
      await fs.write(
        target.path,
        Uint8List.fromList(utf8.encode('KRISTIN_CURRENT_ACCOUNT_OWNER')),
        binding: owner.bindingContext.bindingFor('filesystem.write'),
      );
      final read = await fs.read(
        target.path,
        binding: owner.bindingContext.bindingFor('filesystem.read'),
        maxBytes: 65536,
      );
      expect(utf8.decode(read), 'KRISTIN_CURRENT_ACCOUNT_OWNER');

      final command = await owner.composition.commandService.run(
        P2CommandSpec(
          executable: env('KRISTIN_V70_NODE'),
          cwd: temporary.path,
          arguments: const <String>['-e', "process.stdout.write('V70_OK')"],
          deadline: const Duration(seconds: 20),
        ),
        binding: owner.bindingContext.bindingFor('command.run'),
      );
      expect(utf8.decode(command.stdout), 'V70_OK');
      await handle.close();
      await dataRoot.delete(recursive: true);
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip:
        (const bool.fromEnvironment(
              'KRISTIN_OWNER_RISK_QA',
              defaultValue: false,
            ) ||
            Platform.environment['KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'] ==
                '1')
        ? false
        : 'requires staged current-account runtime',
  );
}
