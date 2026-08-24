import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime_bundle.dart';
import 'package:kristin_local_agent/product/p2_finite_command_service.dart';
import 'package:kristin_local_agent/product/p2_owner_mode.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_bootstrap.dart';
import 'package:kristin_local_agent/product/p2_runtime_resource_resolver.dart';

enum _PackagedQualificationSandboxMode { required, disabled }

_PackagedQualificationSandboxMode _qualificationSandboxMode(
  Map<String, String> environment, {
  required bool hostIsLinux,
}) {
  final override = environment['KRISTIN_PACKAGED_BROWSER_SANDBOX_MODE'];
  if (override != null && override.isNotEmpty) {
    if (override == 'required') {
      return _PackagedQualificationSandboxMode.required;
    }
    if (override == 'disabled' && hostIsLinux) {
      return _PackagedQualificationSandboxMode.disabled;
    }
    throw StateError('packaged_browser_sandbox_mode_invalid:$override');
  }
  if (hostIsLinux &&
      environment['GITHUB_ACTIONS'] == 'true' &&
      environment['RUNNER_OS'] == 'Linux') {
    return _PackagedQualificationSandboxMode.disabled;
  }
  return _PackagedQualificationSandboxMode.required;
}

Future<Map<String, Object?>> _runHostedLinuxQualificationProbe({
  required P3BrowserRuntimeResourceSet bundle,
  required Directory stateDirectory,
  Duration startupTimeout = const Duration(seconds: 45),
}) async {
  if (!Platform.isLinux) {
    throw StateError('hosted_linux_qualification_requires_linux');
  }
  await stateDirectory.create(recursive: true);
  final process = await Process.start(
    bundle.nodeExecutable,
    <String>[
      bundle.workerScript,
      '--mode',
      'probe',
      '--protocol',
      'stdio-json-v1',
      '--sandbox-mode',
      'disabled',
      '--browser-executable',
      bundle.browserExecutable,
      '--browser-root',
      bundle.browserRoot,
      '--runtime-manifest',
      bundle.manifestPath,
      '--state-directory',
      stateDirectory.absolute.path,
    ],
    workingDirectory: bundle.workingDirectory,
    environment: <String, String>{
      'KRISTIN_P3_RUNTIME_MANIFEST_SHA256': bundle.manifestSha256,
      'KRISTIN_P3_RUNTIME_BUILD_SHA256': bundle.runtimeBuildSha256,
      'KRISTIN_P3_BROWSER_REVISION': bundle.browserRevision,
    },
    includeParentEnvironment: false,
    runInShell: false,
    mode: ProcessStartMode.normal,
  );
  final stderr = StringBuffer();
  final stderrSubscription = process.stderr
      .transform(utf8.decoder)
      .listen(stderr.write);
  try {
    final line = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(startupTimeout);
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      throw StateError('packaged_browser_ready_not_object');
    }
    final ready = Map<String, Object?>.from(decoded);
    if (ready['type'] != 'ready' ||
        ready['schemaVersion'] != '1.0.0' ||
        ready['browserEngine'] != bundle.browserEngine ||
        ready['browserRevision'] != bundle.browserRevision ||
        ready['browserExecutableSha256'] != bundle.browserExecutableSha256 ||
        ready['protocol'] != 'stdio-json-v1' ||
        ready['sandboxMode'] != 'disabled' ||
        ready['pid'] is! int ||
        ready['browserPid'] is! int) {
      throw StateError('packaged_browser_ready_invalid:$ready');
    }
    process.stdin.writeln(
      jsonEncode(const <String, Object?>{
        'type': 'shutdown',
        'schemaVersion': '1.0.0',
      }),
    );
    await process.stdin.flush();
    final exit = await process.exitCode.timeout(const Duration(seconds: 10));
    if (exit != 0) {
      throw StateError(
        'packaged_browser_worker_exit:$exit:${stderr.toString()}',
      );
    }
    return ready;
  } on TimeoutException {
    process.kill();
    throw StateError('packaged_browser_worker_start_timeout:${stderr.toString()}');
  } finally {
    await stderrSubscription.cancel();
    try {
      await process.stdin.close();
    } catch (_) {}
  }
}

void main() {
  test('packaged browser qualification sandbox selection fails closed', () {
    expect(
      _qualificationSandboxMode(const <String, String>{}, hostIsLinux: false),
      _PackagedQualificationSandboxMode.required,
    );
    expect(
      _qualificationSandboxMode(
        const <String, String>{
          'KRISTIN_PACKAGED_BROWSER_SANDBOX_MODE': 'required',
        },
        hostIsLinux: true,
      ),
      _PackagedQualificationSandboxMode.required,
    );
    expect(
      _qualificationSandboxMode(
        const <String, String>{
          'KRISTIN_PACKAGED_BROWSER_SANDBOX_MODE': 'disabled',
        },
        hostIsLinux: true,
      ),
      _PackagedQualificationSandboxMode.disabled,
    );
    expect(
      () => _qualificationSandboxMode(
        const <String, String>{
          'KRISTIN_PACKAGED_BROWSER_SANDBOX_MODE': 'disabled',
        },
        hostIsLinux: false,
      ),
      throwsStateError,
    );
    expect(
      () => _qualificationSandboxMode(
        const <String, String>{
          'KRISTIN_PACKAGED_BROWSER_SANDBOX_MODE': 'permissive',
        },
        hostIsLinux: true,
      ),
      throwsStateError,
    );
    expect(
      _qualificationSandboxMode(
        const <String, String>{
          'GITHUB_ACTIONS': 'true',
          'RUNNER_OS': 'Linux',
        },
        hostIsLinux: true,
      ),
      _PackagedQualificationSandboxMode.disabled,
    );
  });

  final executable =
      Platform.environment['KRISTIN_PACKAGED_APP_EXECUTABLE'] ?? '';
  test(
    'packaged product resolves P2 and P3 and performs real host/browser work',
    () async {
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
        final sandboxMode = _qualificationSandboxMode(
          Platform.environment,
          hostIsLinux: Platform.isLinux,
        );
        if (sandboxMode == _PackagedQualificationSandboxMode.disabled) {
          final ready = await _runHostedLinuxQualificationProbe(
            bundle: bundle,
            stateDirectory: Directory(
              '${dataRoot.path}${Platform.pathSeparator}p3-state',
            ),
          );
          expect(ready['browserEngine'], 'chromium');
          expect(ready['browserRevision'], bundle.browserRevision);
          expect(ready['sandboxMode'], 'disabled');
        } else {
          final probe = await browser.probe(
            stateDirectory: Directory(
              '${dataRoot.path}${Platform.pathSeparator}p3-state',
            ),
            startupTimeout: const Duration(seconds: 45),
          );
          expect(probe.ready.browserEngine, 'chromium');
          expect(probe.ready.browserRevision, bundle.browserRevision);
          expect(probe.ready.sandboxMode, 'required');
        }
      } finally {
        if (await dataRoot.exists()) {
          await dataRoot.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip:
        executable.isEmpty ? 'requires packaged P2+P3 product payload' : false,
  );
}
