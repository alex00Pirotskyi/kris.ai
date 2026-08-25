import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/application_runtime_provisioner.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime.dart';
import 'package:kristin_local_agent/product/p2_finite_command_service.dart';
import 'package:kristin_local_agent/product/p2_owner_mode.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final enabled = Platform.isWindows &&
      (Platform.environment['GITHUB_WORKFLOW'] == 'product-gates' ||
          Platform.environment['KRISTIN_IN_APP_RUNTIME_ACCEPTANCE'] == '1');

  test(
    'clean source checkout provisions and boots real P2 and P3 in app',
    () async {
      final applicationDataRoot = await Directory.systemTemp.createTemp(
        'kristin-in-app-runtime-acceptance-',
      );
      final p2Current = Directory(
        '${applicationDataRoot.path}${Platform.pathSeparator}runtime'
        '${Platform.pathSeparator}p2${Platform.pathSeparator}current',
      );
      final p3Current = Directory(
        '${applicationDataRoot.path}${Platform.pathSeparator}runtime'
        '${Platform.pathSeparator}p3${Platform.pathSeparator}current',
      );
      final effects = await Directory(
        '${applicationDataRoot.path}${Platform.pathSeparator}acceptance-effects',
      ).create(recursive: true);
      final browserState = Directory(
        '${applicationDataRoot.path}${Platform.pathSeparator}acceptance-browser',
      );
      final provisioner = ApplicationRuntimeProvisioner(
        applicationDataRoot: applicationDataRoot,
      );
      P2ProductRuntimeOwnerModeHandle? ownerHandle;
      P3BrowserSessionProcess? browserProcess;
      String? browserSessionId;
      String? browserPageId;

      try {
        expect(await p2Current.exists(), isFalse);
        expect(await p3Current.exists(), isFalse);

        final gitHead = (await Process.run('git', const <String>[
          'rev-parse',
          'HEAD',
        ]))
            .stdout
            .toString()
            .trim();
        final gitTree = (await Process.run('git', const <String>[
          'rev-parse',
          'HEAD^{tree}',
        ]))
            .stdout
            .toString()
            .trim();
        expect(gitHead, matches(RegExp(r'^[0-9a-f]{40}$')));
        expect(gitTree, matches(RegExp(r'^[0-9a-f]{40}$')));
        final exactCandidate = Platform.environment['PRODUCT_SOURCE_SHA'];
        if (exactCandidate != null && exactCandidate.isNotEmpty) {
          expect(gitHead, exactCandidate);
        }

        final p2 = await provisioner.ensureP2(currentAccountRequired: true);
        expect(p2.root.absolute.path, p2Current.absolute.path);
        expect(p2.sourceCommit, gitHead);
        expect(p2.sourceTree, gitTree);
        expect(
          p2.provisionedEnvironment['KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'],
          '1',
        );
        expect(
          File(p2.nodeExecutable).absolute.path,
          startsWith(applicationDataRoot.absolute.path),
        );
        expect(await File(p2.nodeExecutable).exists(), isTrue);

        final activeOwnerHandle = await P2ProductRuntimeBootstrap.start(
          dataRoot: applicationDataRoot,
          p1AuthorityService: null,
          runtimeResources: p2,
          interactiveDesktopAttested: true,
        );
        ownerHandle = activeOwnerHandle;
        expect(
          activeOwnerHandle.available,
          isTrue,
          reason: activeOwnerHandle.failureCode,
        );
        expect(activeOwnerHandle.completionEligible, isFalse);
        expect(activeOwnerHandle.secureIsolationActive, isFalse);
        final owner = activeOwnerHandle.runtime!;
        expect(owner.authority.authorityKind, 'p2-current-account-owner-v1');
        activeOwnerHandle.activateEffectContext(
          runId: 'in-app-runtime-acceptance',
          taskId: 'P2-P3',
        );
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

        final filesystem = owner.composition.filesystemService(
          Directory(
            '${applicationDataRoot.path}${Platform.pathSeparator}acceptance-backups',
          ),
        );
        final target = File(
          '${effects.path}${Platform.pathSeparator}in-app-owner-λ.txt',
        );
        await filesystem.write(
          target.path,
          Uint8List.fromList(utf8.encode('KRISTIN_IN_APP_P2_OK')),
          binding: owner.bindingContext.bindingFor('filesystem.write'),
        );
        final read = await filesystem.read(
          target.path,
          binding: owner.bindingContext.bindingFor('filesystem.read'),
          maxBytes: 65536,
        );
        expect(utf8.decode(read), 'KRISTIN_IN_APP_P2_OK');

        final command = await owner.composition.commandService.run(
          P2CommandSpec(
            executable: p2.nodeExecutable,
            cwd: effects.path,
            arguments: const <String>[
              '-e',
              "process.stdout.write('KRISTIN_IN_APP_NODE_OK')",
            ],
            deadline: const Duration(seconds: 30),
          ),
          binding: owner.bindingContext.bindingFor('command.run'),
        );
        expect(utf8.decode(command.stdout), 'KRISTIN_IN_APP_NODE_OK');

        final p3 = await provisioner.ensureP3();
        expect(p3.root.absolute.path, p3Current.absolute.path);
        expect(p3.sourceCommit, gitHead);
        expect(p3.sourceTree, gitTree);
        expect(p3.nodeExecutableSha256, p2.nodeExecutableSha256);
        expect(
          File(p3.nodeExecutable).absolute.path,
          startsWith(applicationDataRoot.absolute.path),
        );
        expect(p3.browserRevision, '1228');
        expect(await File(p3.browserExecutable).exists(), isTrue);
        expect(
          File(p3.browserExecutable).absolute.path,
          startsWith(applicationDataRoot.absolute.path),
        );

        final activeBrowserProcess = await P3BrowserRuntimeService(
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
        browserProcess = activeBrowserProcess;
        final session = await activeBrowserProcess.openSession(
          kind: P3BrowserSessionKind.ephemeral,
          blockServiceWorkers: true,
        );
        browserSessionId = session.sessionId;
        final activeSessionId = session.sessionId;
        final page = await activeBrowserProcess.openPage(activeSessionId);
        browserPageId = page.pageId;
        expect(page.pageId, isNotEmpty);

        final p2Cached = await provisioner.ensureP2(
          currentAccountRequired: true,
        );
        final p3Cached = await provisioner.ensureP3();
        expect(p2Cached.manifestSha256, p2.manifestSha256);
        expect(p3Cached.manifestSha256, p3.manifestSha256);
      } finally {
        final process = browserProcess;
        final sessionId = browserSessionId;
        final pageId = browserPageId;
        if (process != null) {
          if (sessionId != null && pageId != null) {
            try {
              await process.closePage(sessionId, pageId);
            } catch (_) {}
          }
          if (sessionId != null) {
            try {
              await process.closeSession(sessionId);
            } catch (_) {}
          }
          try {
            await process.close();
          } catch (_) {}
        }
        try {
          await ownerHandle?.close();
        } catch (_) {}
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
    timeout: const Timeout(Duration(minutes: 15)),
    skip: enabled
        ? false
        : 'runs only in exact Windows product-gates or explicit local acceptance',
  );
}
