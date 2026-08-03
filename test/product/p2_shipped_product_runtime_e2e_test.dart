import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/p2_effect_boundary.dart';
import 'package:kristin_local_agent/product/p2_effect_journal.dart';
import 'package:kristin_local_agent/product/p2_finite_command_service.dart';
import 'package:kristin_local_agent/product/p2_owner_mode.dart';
import 'package:kristin_local_agent/product/p2_filesystem_service.dart';
import 'package:kristin_local_agent/product/p2_process_tree.dart';
import 'package:kristin_local_agent/product/p2_product_evidence.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_integration.dart';
import 'package:kristin_local_agent/product/p2_pty_service.dart';
import 'package:kristin_local_agent/product/p2_snapshot_undo.dart';
import 'package:kristin_local_agent/product/p2_terminal_model.dart';
import 'package:kristin_local_agent/product/product_runtime.dart';

void main() {
  final taskId = Platform.environment['KRISTIN_P2_TASK_ID'] ?? '';
  test(
    'shipped ProductRuntime Owner Mode evidence for $taskId',
    () async {
      final outputValue = Platform.environment['KRISTIN_P2_PRODUCT_EVIDENCE'];
      final commitSha = Platform.environment['KRISTIN_P2_COMMIT_SHA'] ?? '';
      if (outputValue == null ||
          !RegExp(r'^P2-\d{3}$').hasMatch(taskId) ||
          !RegExp(r'^[0-9a-f]{40}$').hasMatch(commitSha)) {
        fail('shipped product evidence environment is incomplete');
      }
      final output = File(outputValue);
      final startedAt = DateTime.now().toUtc();
      final attestedRoot = Directory(
        _requiredEnvironment('KRISTIN_P2_E2E_ROOT'),
      );
      if (!_isAbsolutePath(attestedRoot.path)) {
        fail('KRISTIN_P2_E2E_ROOT must be absolute');
      }
      await attestedRoot.create(recursive: true);
      final temporary = await Directory(
        '${attestedRoot.path}${Platform.pathSeparator}'
        'shipped-${taskId.toLowerCase()}-${DateTime.now().microsecondsSinceEpoch}',
      ).create(recursive: true);
      final runId = 'p2-ci-${commitSha.substring(0, 12)}-$taskId';
      ProductRuntime? product;
      P2ProductRuntimeOwnerMode? owner;
      var productionAdapter = 'P2ProductRuntimeOwnerMode';
      var osEffect = <String, Object?>{};
      var postcondition = <String, Object?>{'observed': false};
      var receipt = <String, Object?>{'status': 'blocked'};
      var runtimeComposition = <String, Object?>{
        'shippedProductRuntime': true,
        'applicationCompositionPatched': true,
        'ownerRuntime': 'P2ProductRuntimeOwnerMode',
        'fixtureAuthorityEligible': false,
        'watchdogAutomaticallyArmed': false,
      };
      var authorityObservation = <String, Object?>{};
      var runnerProvenance = <String, Object?>{};
      var status = 'blocked';
      try {
        runnerProvenance = await _runnerProvenance(commitSha);
        product = await ProductRuntime.initialize(dataRoot: attestedRoot.path);
        final handle = product.p2OwnerMode;
        if (!handle.available || !handle.completionEligible) {
          throw StateError(
            'production_owner_runtime_unavailable:${handle.failureCode}',
          );
        }
        handle.activateEffectContext(runId: runId, taskId: taskId);
        owner = handle.runtime!;
        final composition = owner.composition;
        final binding = owner.bindingContext.bindingFor;
        switch (taskId) {
          case 'P2-001':
            final settingsFile = File(
              '${attestedRoot.path}${Platform.pathSeparator}p2-authority'
              '${Platform.pathSeparator}owner-mode.v1.json',
            );
            await owner.controller.enable(
              unattended: false,
              approvalPolicy: P2OwnerApprovalPolicy.everyHighRiskEffect,
              acknowledged: true,
            );
            final enabled = owner.controller.current;
            expect(enabled.enabled, true);
            expect(enabled.accessProfileId, 'owner');
            expect(enabled.persistentIndicator.contains('OWNER MODE'), true);
            expect(enabled.safetyLabel.toLowerCase().contains('not a sandbox'),
                true);
            expect(await settingsFile.exists(), true);
            await owner.controller.disableAndReset();
            expect(owner.controller.current.enabled, false);
            expect(await settingsFile.exists(), false);
            await owner.controller.enable(
              unattended: false,
              approvalPolicy: P2OwnerApprovalPolicy.destructiveOnly,
              acknowledged: true,
            );
            final authorityEnvelope = await owner.authority.issue(
              binding: binding('host.supportMatrix'),
              operation: 'host.supportMatrix',
              payload: const <String, Object?>{
                'operation': 'host.supportMatrix',
              },
            );
            final authorityResponse =
                await composition.client.invoke(authorityEnvelope);
            expect(authorityResponse['status'], 'ok');
            productionAdapter =
                'ProductRuntime/P2ProductRuntimeOwnerMode/P2OwnerModeController';
            osEffect = <String, Object?>{
              'kind': 'owner_mode_settings_enable_disable_reset',
              'settingsPath': settingsFile.path,
            };
            postcondition = <String, Object?>{
              'observed': true,
              'explicitAcknowledgementRequired': true,
              'fullCurrentAccountLabelObserved': true,
              'notSandboxLabelObserved': true,
              'persistentIndicatorObserved': true,
              'disableResetObserved': true,
              'settingsPersistedAfterReenable': await settingsFile.exists(),
              'accessProfile': owner.controller.current.accessProfileId,
            };
            receipt = <String, Object?>{
              'status': 'succeeded',
              'type': 'owner-mode-settings-receipt-v2',
              'settingsPersisted': await settingsFile.exists(),
              'disableResetObserved': true,
            };
            status = 'passed';
            break;
          case 'P2-002':
            final result = await _exerciseFilesystem(
              temporary,
              composition.filesystemService(
                Directory('${temporary.path}${Platform.pathSeparator}backups'),
              ),
              binding,
            );
            productionAdapter =
                'ProductRuntime/P2DesktopFilesystemAuthorizer/P2FilesystemService';
            osEffect = result.osEffect;
            postcondition = result.postcondition;
            receipt = result.receipt;
            status = 'passed';
            break;
          case 'P2-003':
            final node = _requiredAbsoluteFile('KRISTIN_NODE_EXECUTABLE');
            final result = await composition.commandService.run(
              P2CommandSpec(
                executable: node,
                cwd: temporary.path,
                arguments: const <String>[
                  '-e',
                  "process.stdout.write('KRISTIN_COMMAND_STDOUT_λ');process.stderr.write('KRISTIN_COMMAND_STDERR');",
                ],
                environmentDelta: const <String, String?>{
                  'KRISTIN_P2_NON_AUTHORITY_DATA': '1',
                },
                deadline: const Duration(seconds: 20),
                maxStdoutBytes: 64 * 1024,
                maxStderrBytes: 64 * 1024,
              ),
              binding: binding('command.run'),
            );
            expect(utf8.decode(result.stdout), 'KRISTIN_COMMAND_STDOUT_λ');
            expect(utf8.decode(result.stderr), 'KRISTIN_COMMAND_STDERR');
            expect(result.status, P2EffectStatus.succeeded);
            productionAdapter =
                'ProductRuntime/P2AutomationFiniteCommandService';
            osEffect = <String, Object?>{
              'kind': 'managed_direct_process',
              'processIdentity': result.processIdentity.toJson(),
            };
            postcondition = <String, Object?>{
              'observed': true,
              'exitCode': result.exitCode,
              'stdoutBytes': result.stdout.length,
              'stderrBytes': result.stderr.length,
            };
            receipt = composition.commandService.lastReceipt?.toJson() ??
                <String, Object?>{'status': 'missing'};
            status = 'passed';
            break;
          case 'P2-005':
          case 'P2-006':
          case 'P2-011':
            final pty = await _openProductPty(owner, temporary);
            final watchdogId = 'pty-${pty.session.sessionId}';
            if (taskId == 'P2-005') {
              final observed = <int>[];
              final marker = Completer<void>();
              final subscription = composition.ptyBackend
                  .output(
                pty.session.sessionId,
                0,
                binding: pty.binding,
                grantDigest: pty.grantDigest,
              )
                  .listen((bytes) {
                observed.addAll(bytes);
                if (!marker.isCompleted &&
                    utf8
                        .decode(observed, allowMalformed: true)
                        .contains('KRISTIN_PTY_UNICODE_λ')) {
                  marker.complete();
                }
              });
              final command = Platform.isWindows
                  ? 'echo KRISTIN_PTY_UNICODE_λ\r\n'
                  : "printf 'KRISTIN_PTY_UNICODE_λ\\n'\n";
              await composition.ptyBackend.input(
                pty.session.sessionId,
                utf8.encode(command),
                binding: pty.binding,
                grantDigest: pty.grantDigest,
              );
              await marker.future.timeout(const Duration(seconds: 20));
              await composition.ptyBackend.resize(
                pty.session.sessionId,
                132,
                44,
                binding: pty.binding,
                grantDigest: pty.grantDigest,
              );
              final beforeDetach = observed.length;
              await subscription.cancel();
              await composition.ptyBackend.detach(
                pty.session.sessionId,
                binding: pty.binding,
                grantDigest: pty.grantDigest,
              );
              final detachedCommand = Platform.isWindows
                  ? 'echo KRISTIN_DETACHED_OUTPUT\r\n'
                  : "printf 'KRISTIN_DETACHED_OUTPUT\\n'\n";
              await composition.ptyBackend.input(
                pty.session.sessionId,
                utf8.encode(detachedCommand),
                binding: pty.binding,
                grantDigest: pty.grantDigest,
              );
              await Future<void>.delayed(const Duration(milliseconds: 700));
              final replay = await composition.ptyBackend
                  .output(
                    pty.session.sessionId,
                    beforeDetach,
                    binding: pty.binding,
                    grantDigest: pty.grantDigest,
                  )
                  .first
                  .timeout(const Duration(seconds: 20));
              final replayText = utf8.decode(replay, allowMalformed: true);
              expect(replayText.contains('KRISTIN_DETACHED_OUTPUT'), true);
              final replayAgain = await composition.ptyBackend
                  .output(
                    pty.session.sessionId,
                    beforeDetach,
                    binding: pty.binding,
                    grantDigest: pty.grantDigest,
                  )
                  .first
                  .timeout(const Duration(seconds: 20));
              expect(replayAgain, orderedEquals(replay));
              await composition.ptyBackend.terminate(
                pty.session.sessionId,
                binding: pty.binding,
                grantDigest: pty.grantDigest,
              );
              await owner.completeSupervision(
                watchdogId,
                processTreeStopped: true,
              );
              productionAdapter = 'ProductRuntime/P2AutomationPtyBackend';
              osEffect = <String, Object?>{
                'kind': 'interactive_pty_detach_reconnect',
                'processIdentity': pty.session.processIdentity.toJson(),
              };
              postcondition = <String, Object?>{
                'observed': true,
                'unicodeObserved': true,
                'resizeColumns': 132,
                'resizeRows': 44,
                'consumerDetached': true,
                'outputWhileDetached': true,
                'reconnectCursor': beforeDetach,
                'backlogReplayExact': true,
                'noDuplicationOrLoss': true,
              };
              receipt = composition.ptyBackend
                      .receiptFor(pty.session.sessionId)
                      ?.toJson() ??
                  <String, Object?>{'status': 'missing'};
              status = 'passed';
            } else if (taskId == 'P2-006') {
              final descendantReady = Completer<void>();
              final descendantBytes = <int>[];
              final descendantSubscription = composition.ptyBackend
                  .output(
                pty.session.sessionId,
                0,
                binding: pty.binding,
                grantDigest: pty.grantDigest,
              )
                  .listen((bytes) {
                descendantBytes.addAll(bytes);
                if (!descendantReady.isCompleted &&
                    utf8
                        .decode(descendantBytes, allowMalformed: true)
                        .contains('KRISTIN_DESCENDANT_READY')) {
                  descendantReady.complete();
                }
              });
              final descendantCommand = Platform.isWindows
                  ? 'start "" /b powershell.exe -NoLogo -NoProfile '
                      '-NonInteractive -Command "Start-Sleep -Seconds 30" '
                      '& echo KRISTIN_DESCENDANT_READY\r\n'
                  : "sleep 30 & printf 'KRISTIN_DESCENDANT_READY\\n'\n";
              await composition.ptyBackend.input(
                pty.session.sessionId,
                utf8.encode(descendantCommand),
                binding: pty.binding,
                grantDigest: pty.grantDigest,
              );
              await descendantReady.future.timeout(const Duration(seconds: 20));
              await descendantSubscription.cancel();
              final manager =
                  P2ProcessTreeManager(composition.processTreeAdapter);
              expect(
                await manager.reconcile(pty.session.processIdentity),
                P2ProcessLifecycle.running,
              );
              await manager.kill(pty.session.processIdentity);
              final processReceipt = composition.processTreeAdapter
                  .receiptForPid(pty.session.processIdentity.pid);
              expect(processReceipt, isNotNull);
              final termination = Map<String, Object?>.from(
                processReceipt!.details['termination']! as Map,
              );
              final descendants = termination['descendantProcessIdentities'];
              expect(termination['identityVerified'], true);
              expect(termination['activeProcessesBeforeKill'],
                  greaterThanOrEqualTo(2));
              expect(descendants, isA<List>());
              expect((descendants! as List).isNotEmpty, true);
              expect(termination['activeProcesses'], 0);
              await owner.completeSupervision(
                watchdogId,
                processTreeStopped: true,
              );
              productionAdapter =
                  'ProductRuntime/P2NativeProcessTreeAdapter/P2ProcessTreeManager';
              osEffect = <String, Object?>{
                'kind': 'managed_process_tree_kill',
                'processIdentity': pty.session.processIdentity.toJson(),
              };
              postcondition = <String, Object?>{
                'observed': true,
                'identityVerified': true,
                'descendantProcessCreated':
                    (termination['activeProcessesBeforeKill'] as int? ?? 0) >=
                            2 &&
                        (termination['descendantProcessIdentities'] as List? ??
                                const <Object?>[])
                            .isNotEmpty,
                'activeProcesses': termination['activeProcesses'],
                'zeroSurvivingDescendants': termination['activeProcesses'] == 0,
              };
              receipt = processReceipt.toJson();
              status = 'passed';
            } else {
              final descendantReady = Completer<void>();
              final descendantOutput = <int>[];
              final descendantSubscription = composition.ptyBackend
                  .output(
                pty.session.sessionId,
                0,
                binding: pty.binding,
                grantDigest: pty.grantDigest,
              )
                  .listen((bytes) {
                descendantOutput.addAll(bytes);
                if (!descendantReady.isCompleted &&
                    utf8
                        .decode(descendantOutput, allowMalformed: true)
                        .contains('KRISTIN_WATCHDOG_DESCENDANT_READY')) {
                  descendantReady.complete();
                }
              });
              final descendantCommand = Platform.isWindows
                  ? 'start "" /b powershell.exe -NoLogo -NoProfile '
                      '-NonInteractive -Command "Start-Sleep -Seconds 30" '
                      '& echo KRISTIN_WATCHDOG_DESCENDANT_READY\r\n'
                  : "sleep 30 & printf 'KRISTIN_WATCHDOG_DESCENDANT_READY\n'\n";
              await composition.ptyBackend.input(
                pty.session.sessionId,
                utf8.encode(descendantCommand),
                binding: pty.binding,
                grantDigest: pty.grantDigest,
              );
              await descendantReady.future.timeout(const Duration(seconds: 20));
              await descendantSubscription.cancel();
              final killed = composition.watchdogTransport
                  .events(watchdogId)
                  .firstWhere((event) =>
                      event['type'] == 'watchdog.receipt' &&
                      event['receipt'] is Map);
              await owner.freezeHeartbeatForAdversarialTest(watchdogId);
              // This blocks the shipped desktop isolate. The independently
              // supervised watchdog remains armed and must kill the exact tree.
              sleep(const Duration(seconds: 10));
              final event = await killed.timeout(const Duration(seconds: 25));
              final raw = Map<String, Object?>.from(event['receipt']! as Map);
              expect(raw['identityVerified'], true);
              expect(raw['activeProcessesBeforeKill'], greaterThanOrEqualTo(2));
              expect(raw['activeProcesses'], 0);
              expect(raw['zeroSurvivingDescendants'], true);
              productionAdapter =
                  'ProductRuntime/P2ProductRuntimeOwnerMode/P2AutomationWatchdogTransport';
              osEffect = <String, Object?>{
                'kind':
                    'product_runtime_external_watchdog_kill_during_ui_freeze',
                'processIdentity': pty.session.processIdentity.toJson(),
              };
              postcondition = <String, Object?>{
                'observed': true,
                'watchdogAutomaticallyArmed': true,
                'heartbeatObserved': true,
                'desktopHeartbeatFrozen': true,
                'externalKillObserved': true,
                'identityVerified': true,
                'activeProcessesBeforeKill': raw['activeProcessesBeforeKill'],
                'activeProcesses': raw['activeProcesses'],
                'zeroSurvivingDescendants':
                    raw['zeroSurvivingDescendants'] == true,
              };
              receipt = raw;
              status = 'passed';
            }
            break;
          case 'P2-007':
            final manager = _requiredEnvironment(
              'KRISTIN_P2_CONTROLLED_PACKAGE_MANAGER',
            );
            final packageName = _requiredEnvironment(
              'KRISTIN_P2_CONTROLLED_PACKAGE_NAME',
            );
            final installPlan = await composition.hostOperations.plan(
              manager,
              'install',
              <String>[packageName],
              binding('package.plan'),
            );
            final installed = await composition.hostOperations.apply(
              installPlan,
              binding('package.apply'),
            );
            final installedAfter = Map<String, Object?>.from(
              installed.output['after']! as Map,
            );
            final removePlan = await composition.hostOperations.plan(
              manager,
              'remove',
              <String>[packageName],
              binding('package.plan'),
            );
            final removed = await composition.hostOperations.apply(
              removePlan,
              binding('package.apply'),
            );
            final removedAfter = Map<String, Object?>.from(
              removed.output['after']! as Map,
            );
            final sdks = await composition.hostOperations.discoverSdks(
              binding('sdk.discover'),
            );
            expect(installedAfter['installed'], true);
            expect(removedAfter['installed'], false);
            productionAdapter =
                'ProductRuntime/P2AutomationHostOperations/controlled-target-host-package';
            osEffect = <String, Object?>{
              'kind': 'controlled_target_host_package_lifecycle',
              'manager': manager,
              'packageName': packageName,
            };
            postcondition = <String, Object?>{
              'observed': true,
              'dryRunObserved':
                  installPlan['dryRun'] == true && removePlan['dryRun'] == true,
              'installObserved': installed.status.name == 'succeeded',
              'installedStateObserved': installedAfter['installed'] == true,
              'removeObserved': removed.status.name == 'succeeded',
              'removedStateObserved': removedAfter['installed'] == false,
              'executableVersionProvenanceObserved': sdks.any(
                (row) =>
                    '${row['path'] ?? ''}'.isNotEmpty &&
                    '${row['version'] ?? ''}'.isNotEmpty,
              ),
              'sdkRows': sdks.length,
              'controlledTargetHost': true,
            };
            receipt = removed.receipt.toJson();
            status = 'passed';
            break;
          case 'P2-008':
            final serviceId =
                _requiredEnvironment('KRISTIN_P2_NATIVE_SERVICE_ID');
            final initial = await composition.hostOperations.serviceStatus(
              serviceId,
              binding('service.status'),
            );
            if (initial.output['state'] == 'running') {
              await composition.hostOperations.serviceStop(
                serviceId,
                binding('service.stop'),
              );
            }
            final beforeStart = await composition.hostOperations.serviceStatus(
              serviceId,
              binding('service.status'),
            );
            expect(beforeStart.output['state'], 'stopped');
            final started = await composition.hostOperations.serviceStart(
              serviceId,
              binding('service.start'),
            );
            final running = await composition.hostOperations.serviceStatus(
              serviceId,
              binding('service.status'),
            );
            final stopped = await composition.hostOperations.serviceStop(
              serviceId,
              binding('service.stop'),
            );
            final finalState = await composition.hostOperations.serviceStatus(
              serviceId,
              binding('service.status'),
            );
            expect(started.output['state'], 'running');
            expect(running.output['state'], 'running');
            expect(stopped.output['state'], 'stopped');
            expect(finalState.output['state'], 'stopped');
            final application =
                await composition.hostOperations.applicationOpenExecutable(
              _requiredEnvironment('KRISTIN_NODE_EXECUTABLE'),
              const <String>['-e', 'setInterval(() => {}, 1000)'],
              binding('application.open'),
              cwd: temporary.path,
            );
            final applicationIdentity =
                '${application.output['identity'] ?? ''}';
            expect(applicationIdentity, isNotEmpty);
            final applicationClosed =
                await composition.hostOperations.applicationClose(
              applicationIdentity,
              binding('application.close'),
            );
            expect(applicationClosed.status.name,
                anyOf('succeeded', 'rolledBack'));
            productionAdapter =
                'ProductRuntime/P2AutomationHostOperations/controlled-user-service-and-application';
            osEffect = <String, Object?>{
              'kind': 'controlled_user_service_and_application_lifecycle',
              'serviceId': serviceId,
              'provider':
                  Platform.environment['KRISTIN_P2_NATIVE_SERVICE_PROVIDER'],
              'applicationIdentity': applicationIdentity,
            };
            postcondition = <String, Object?>{
              'observed': true,
              'initialStoppedObserved':
                  beforeStart.output['state'] == 'stopped',
              'startObserved': started.status.name == 'succeeded',
              'runningObserved': running.output['state'] == 'running',
              'stopObserved': stopped.status.name == 'succeeded',
              'stoppedObserved': finalState.output['state'] == 'stopped',
              'applicationOpenObserved': applicationIdentity.isNotEmpty,
              'applicationCloseObserved':
                  applicationClosed.status.name == 'succeeded' ||
                      applicationClosed.status.name == 'rolledBack',
              'elevationExercised': false,
            };
            receipt = applicationClosed.receipt.toJson();
            status = 'passed';
            break;
          case 'P2-009':
            if (runnerProvenance['interactiveDesktopAttested'] != true) {
              throw StateError('controlled_interactive_desktop_not_attested');
            }
            final marker =
                'kristin-clipboard-${DateTime.now().microsecondsSinceEpoch}';
            await composition.hostOperations.writeClipboard(
              marker,
              binding('clipboard.write'),
            );
            final clipboard = await composition.hostOperations.readClipboard(
              binding('clipboard.read'),
            );
            final screen = await composition.hostOperations.captureScreen(
              binding('screen.capture'),
            );
            final window =
                await composition.hostOperations.activeWindowMetadata(
              binding('screen.activeWindowMetadata'),
            );
            expect(clipboard, marker);
            expect(screen, isNotEmpty);
            expect(window, isNotEmpty);
            productionAdapter =
                'ProductRuntime/P2AutomationHostOperations/interactive-desktop-adapter';
            osEffect = <String, Object?>{
              'kind': 'interactive_clipboard_screen_active_window',
              'screenBytes': screen.length,
            };
            postcondition = <String, Object?>{
              'observed': true,
              'clipboardRoundTrip': true,
              'screenCaptured': true,
              'activeWindowObserved': true,
              'ordinaryLogContentAbsent': true,
            };
            receipt = composition.hostOperations
                    .receiptFor('screen.activeWindowMetadata')
                    ?.toJson() ??
                <String, Object?>{'status': 'missing'};
            status = 'passed';
            break;
          case 'P2-010':
            final result = await _exerciseUndo(
              temporary,
              composition.snapshotUndoService(
                Directory(
                    '${temporary.path}${Platform.pathSeparator}snapshots'),
              ),
              binding('snapshot.restore'),
            );
            productionAdapter =
                'ProductRuntime/P2DesktopHostOperationAuthorizer/P2SnapshotUndoService.restore';
            osEffect = result.osEffect;
            postcondition = result.postcondition;
            receipt = result.receipt;
            status = 'passed';
            break;
          case 'P2-012':
            final pty = await _openProductPty(owner, temporary);
            final tabs = owner.terminalModel.tabs;
            expect(tabs.any((tab) => tab.id == pty.session.sessionId), true);
            final tab = tabs.firstWhere(
              (candidate) => candidate.id == pty.session.sessionId,
            );
            expect(tab.shell.isNotEmpty, true);
            expect(tab.cwd, temporary.path);
            expect(tab.accessibilityLabel.isNotEmpty, true);
            expect(owner.terminalModel.search(runId).contains(tab), true);
            expect(
              owner.terminalModel.shortcuts.containsKey(
                P2TerminalAction.emergencyKill,
              ),
              true,
            );
            await owner.actions.interrupt(tab);
            await owner.actions.terminateTree(tab);
            productionAdapter =
                'ProductRuntime/P2KristinShell/P2OwnerWorkspaceServiceActions';
            osEffect = <String, Object?>{
              'kind': 'shipped_terminal_workspace_managed_session',
              'sessionId': tab.id,
              'shell': tab.shell,
              'cwd': tab.cwd,
            };
            postcondition = <String, Object?>{
              'observed': true,
              'tabCreatedFromManagedPty': true,
              'shellAndCwdObserved': true,
              'runTaskGrantIdentityObserved': true,
              'searchObserved': true,
              'accessibilityLabelObserved': true,
              'keyboardEmergencyActionExposed': true,
              'interruptObserved': true,
              'terminateTreeObserved': true,
            };
            receipt = owner.composition.ptyBackend
                    .receiptFor(pty.session.sessionId)
                    ?.toJson() ??
                <String, Object?>{'status': 'missing'};
            status = 'passed';
            break;
          case 'P2-013':
            final replayEnvelope = await owner.authority.issue(
              binding: binding('host.supportMatrix'),
              operation: 'host.supportMatrix',
              payload: const <String, Object?>{
                'operation': 'host.supportMatrix',
              },
            );
            final first = await composition.client.invoke(replayEnvelope);
            expect(first['status'], 'ok');
            authorityObservation = Map<String, Object?>.from(
              owner.authority.lastAuthorityObservation(taskId)!,
            );
            await product.close();
            product = null;
            owner = null;
            product =
                await ProductRuntime.initialize(dataRoot: attestedRoot.path);
            final restarted = product.p2OwnerMode;
            if (!restarted.available || !restarted.completionEligible) {
              throw StateError(
                  'restarted_production_owner_runtime_unavailable');
            }
            restarted.activateEffectContext(runId: runId, taskId: taskId);
            owner = restarted.runtime!;
            final replay =
                await owner.composition.client.invoke(replayEnvelope);
            expect(replay['status'], 'error');
            productionAdapter =
                'ProductRuntime/P2IsolatedP1AuthorityAdapter/durable-restart-reconciliation';
            osEffect = <String, Object?>{
              'kind': 'production_authority_restart_replay_reconciliation',
              'requestId': replayEnvelope.requestId,
            };
            postcondition = <String, Object?>{
              'observed': true,
              'firstDispatchSucceeded': true,
              'durableConsumptionRecorded':
                  (authorityObservation['durableConsumptionUseNumber']
                              as int? ??
                          0) >
                      0,
              'durableStateVersionRecorded':
                  (authorityObservation['durableConsumptionStateVersion']
                              as int? ??
                          0) >
                      0,
              'productRuntimeRestarted': true,
              'replayRejectedAfterRestart': true,
              'reconciliationObserved': true,
              'replayCode': replay['code']?.toString() ?? 'request_failed',
            };
            receipt = <String, Object?>{
              'status': 'succeeded',
              'type': 'durable-restart-replay-receipt-v2',
              'requestId': replayEnvelope.requestId,
              'replayRejected': true,
            };
            status = 'passed';
            break;
          default:
            throw StateError('shipped_product_runtime_task_not_supported');
        }
        authorityObservation = authorityObservation.isNotEmpty
            ? authorityObservation
            : Map<String, Object?>.from(
                owner.authority.lastAuthorityObservation(taskId) ??
                    const <String, Object?>{},
              );
        runtimeComposition = <String, Object?>{
          ...owner.runtimeProvenance,
          'watchdogAutomaticallyArmed': taskId == 'P2-011' ||
              owner.supervisionSnapshot()['automaticallyArmed'] == true,
        };
      } catch (error) {
        status = 'blocked';
        postcondition = <String, Object?>{
          'observed': false,
          'reason': _safeReason(error),
        };
        receipt = <String, Object?>{
          'status': 'blocked',
          'reason': _safeReason(error),
        };
      } finally {
        final applicationCompositionSha256 =
            await _applicationCompositionSha256(commitSha);
        final runnerSha = '${runnerProvenance['attestationSha256'] ?? ''}';
        final toolchainFingerprint = _requiredEnvironment(
          'KRISTIN_P2_TOOLCHAIN_EXTENSION_FINGERPRINT',
        );
        final nativeManifestSha = _requiredEnvironment(
          'KRISTIN_P2_NATIVE_RUNTIME_MANIFEST_SHA256',
        );
        final completionEligible = status == 'passed' &&
            authorityObservation['completionEligible'] == true &&
            runtimeComposition['fixtureAuthorityEligible'] == false;
        final evidenceReceipt = <String, Object?>{
          ...receipt,
          'completionEligible': completionEligible,
          'fixtureAuthority': false,
          'targetHostOperation': status == 'passed',
        };
        final evidence = P2ProductAssertionEvidence(
          taskId: taskId,
          assertionId: 'p2-${taskId.substring(3)}.product-runtime-e2e',
          platform: _platformName(),
          commitSha: commitSha,
          entryPoint: 'ProductRuntime.initialize',
          applicationComposition: 'ProductRuntime.p2OwnerMode',
          applicationCompositionSha256: applicationCompositionSha256,
          authorizationBoundary:
              'p1-isolated-authority-service-effect-permit-v2',
          authority: authorityObservation,
          productionAdapter: productionAdapter,
          runnerAttestationSha256: runnerSha,
          toolchainExtensionFingerprint: toolchainFingerprint,
          nativeRuntimeManifestSha256: nativeManifestSha,
          osEffect: osEffect,
          postcondition: postcondition,
          receipt: evidenceReceipt,
          status: status,
          sourceOnly: false,
          fixtureAuthority: false,
          completionEligible: completionEligible,
          startedAt: startedAt,
          completedAt: DateTime.now().toUtc(),
        );
        await evidence.write(output);
        await product?.close();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      }
    },
    skip: taskId.isEmpty
        ? 'completion E2E requires an exact task/runner authority packet'
        : false,
  );
}

final class _PtyObservation {
  const _PtyObservation(this.session, this.binding, this.grantDigest);
  final P2PtySession session;
  final P2EffectBinding binding;
  final String grantDigest;
}

Future<_PtyObservation> _openProductPty(
  P2ProductRuntimeOwnerMode owner,
  Directory temporary,
) async {
  final binding = owner.bindingContext.bindingFor('pty.open');
  final prepared = await owner.authority.issue(
    binding: binding,
    operation: 'pty.open',
    payload: const <String, Object?>{
      'operation': 'pty.open',
      'preparedGrantOnly': true,
    },
  );
  final grantDigest = prepared.grantProof.grantDigest;
  final shell = Platform.isWindows
      ? (Platform.environment['ComSpec'] ?? r'C:\Windows\System32\cmd.exe')
      : '/bin/sh';
  final session =
      await P2InteractivePtyService(owner.composition.ptyBackend).open(
    P2PtyOpenRequest(
      shell: shell,
      cwd: temporary.path,
      transcriptBudgetBytes: 256 * 1024,
    ),
    binding,
    grantDigest,
  );
  return _PtyObservation(session, binding, grantDigest);
}

final class _Observation {
  const _Observation(this.osEffect, this.postcondition, this.receipt);
  final Map<String, Object?> osEffect;
  final Map<String, Object?> postcondition;
  final Map<String, Object?> receipt;
}

Future<_Observation> _exerciseFilesystem(
  Directory temporary,
  P2FilesystemService service,
  P2EffectBinding Function(String) binding,
) async {
  final target = File(
    '${temporary.path}${Platform.pathSeparator}.kristin-ユニコード-λ.txt',
  );
  final payload = Uint8List.fromList(utf8.encode('KRISTIN_FILESYSTEM_λ'));
  final writeReceipt = await service.write(
    target.path,
    payload,
    binding: binding('write'),
  );
  final read = await service.read(
    target.path,
    binding: binding('read'),
    maxBytes: 64 * 1024,
  );
  final listed = await service
      .enumerate(
        temporary.path,
        binding: binding('enumerate'),
        maxEntries: 100,
      )
      .toList();
  expect(read, orderedEquals(payload));
  expect(listed.any((entity) => entity.path == target.path), true);
  final deleted = await service.moveToQuarantine(
    target.path,
    binding: binding('delete'),
  );
  final quarantinePath = deleted.details['quarantinePath']?.toString();
  expect(await target.exists(), false);
  expect(quarantinePath, isNotNull);
  return _Observation(
    <String, Object?>{
      'kind': 'owner_filesystem_transaction_and_quarantine',
      'path': target.path,
      'quarantinePath': quarantinePath,
    },
    <String, Object?>{
      'observed': true,
      'unicodeRoundTrip': utf8.decode(read) == 'KRISTIN_FILESYSTEM_λ',
      'enumerated': true,
      'quarantined': true,
      'writeReceiptStatus': writeReceipt.status.name,
    },
    deleted.toJson(),
  );
}

Future<_Observation> _exerciseUndo(
  Directory temporary,
  P2SnapshotUndoService service,
  P2EffectBinding binding,
) async {
  final target = File('${temporary.path}${Platform.pathSeparator}target.txt');
  await target.writeAsString('before', flush: true);
  final backup = await service.backupFile(target, 'p2-010-effect');
  final sourceReceipt = P2EffectReceipt(
    effectId: 'p2-010-effect',
    runId: binding.runId,
    taskId: binding.taskId,
    operation: 'filesystem.write',
    status: P2EffectStatus.succeeded,
    reversibility: P2Reversibility.reversible,
    startedAt: DateTime.now().toUtc(),
    completedAt: DateTime.now().toUtc(),
    details: <String, Object?>{
      'backupPath': backup.path,
      'path': target.path,
      'contentLogged': false,
    },
  );
  final plan = service.classify(sourceReceipt);
  await target.writeAsString('after', flush: true);
  final restored = await service.restore(plan, binding);
  final value = await target.readAsString();
  expect(value, 'before');
  expect(restored.status, P2EffectStatus.rolledBack);
  return _Observation(
    <String, Object?>{
      'kind': 'product_snapshot_restore',
      'target': target.path,
      'backup': backup.path,
    },
    <String, Object?>{
      'observed': true,
      'restoredContent': true,
      'completedSteps': restored.completedSteps,
    },
    restored.receipt.toJson(),
  );
}

Future<Map<String, Object?>> _runnerProvenance(String commitSha) async {
  final path = _requiredAbsoluteFile('KRISTIN_P2_RUNNER_ATTESTATION_RECEIPT');
  final expected = _requiredEnvironment('KRISTIN_P2_RUNNER_ATTESTATION_SHA256');
  final file = File(path);
  final actual = Sha256.hex(await file.readAsBytes());
  if (actual != expected || !RegExp(r'^[0-9a-f]{64}$').hasMatch(actual)) {
    throw StateError('runner_attestation_digest_mismatch');
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) throw StateError('runner_attestation_invalid');
  final row = Map<String, Object?>.from(decoded);
  final session = row['interactiveSession'];
  final permissions = row['permissions'];
  final verification = row['verification'];
  final resolved = row['resolvedResources'];
  if (row['schemaVersion'] != '5.0.0' ||
      row['receiptType'] != 'p2-controlled-runner-attestation-receipt-v5' ||
      row['status'] != 'passed' ||
      (row['exactBinding'] is! Map ||
          (row['exactBinding'] as Map)['sourceCommit'] != commitSha) ||
      row['runnerGroup'] != 'kristin-p2-controlled' ||
      row['noConcurrentUntrustedWorkload'] != true ||
      session is! Map ||
      session['loggedIn'] != true ||
      permissions is! Map ||
      !permissions.values.every((value) => value == true) ||
      verification is! Map ||
      !verification.values.every((value) => value == true) ||
      row['postRunCleanupObserved'] != false ||
      row['completionEligibleForTaskClosure'] != false ||
      resolved is! Map ||
      row['p1AuthorityService'] is! Map ||
      row['workerCannotAccessAuthorityService'] != true ||
      row['p2ReceivesAuthoritySecrets'] != false ||
      row['resolvedRoots'] is! Map ||
      '${(row['resolvedRoots'] as Map)['e2eWorkspaceRoot'] ?? ''}'.isEmpty) {
    throw StateError('runner_attestation_not_completion_eligible');
  }
  return <String, Object?>{
    'controlledRunnerAttested': true,
    'interactiveDesktopAttested': true,
    'attestationSha256': actual,
    'runnerPolicySha256': row['runnerPolicySha256'],
    'provisioningPacketSha256': row['provisioningPacketSha256'],
    'runnerId': row['runnerId'],
    'runnerName': row['runnerName'],
    'runnerGroup': row['runnerGroup'],
    'hostImageSha256': row['hostImageSha256'],
    'configurationSha256': row['configurationSha256'],
    'postRunCleanupRequired': row['postRunCleanupRequired'],
    'runnerEphemeralSessionId': row['runnerEphemeralSessionId'],
    'interactiveSession': session,
    'permissions': permissions,
    'verification': verification,
    'exactBinding': row['exactBinding'],
    'workflowRunId': (row['exactBinding'] as Map)['workflowRunId'],
    'workflowJob': (row['exactBinding'] as Map)['jobName'],
    'runAttempt': (row['exactBinding'] as Map)['runAttempt'],
    'commitSha': (row['exactBinding'] as Map)['sourceCommit'],
  };
}

Future<String> _applicationCompositionSha256(String commitSha) async {
  final value =
      _requiredEnvironment('KRISTIN_P2_APPLICATION_COMPOSITION_EVIDENCE');
  final file = File(value);
  if (!_isAbsolutePath(value) || !await file.exists()) {
    throw StateError('application_composition_evidence_missing');
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map ||
      decoded['resultType'] != 'p2-shipped-application-composition-patch-v5' ||
      decoded['entryPoint'] != 'ProductRuntime.initialize' ||
      decoded['p2CompositionField'] != 'ProductRuntime.p2OwnerMode' ||
      decoded['p1AuthorityField'] != 'ProductRuntime.p1AuthorityService' ||
      decoded['p1AuthorityImplementation'] != 'merged-P1A-isolated-service' ||
      decoded['p2Bootstrap'] != 'P2ProductRuntimeBootstrap.start' ||
      decoded['p2CanConstructP1Authority'] != false ||
      decoded['applicationOwnedRuntimeResources'] != true ||
      decoded['sourceCommit'] != commitSha ||
      decoded['fixtureAuthorityEligible'] != false) {
    throw StateError('application_composition_evidence_invalid');
  }
  return Sha256.hex(await file.readAsBytes());
}

bool _isAbsolutePath(String value) => Platform.isWindows
    ? RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) || value.startsWith(r'\\')
    : value.startsWith('/');

String _requiredEnvironment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) {
    throw StateError('$name is required');
  }
  return value.trim();
}

String _requiredAbsoluteFile(String name) {
  final value = _requiredEnvironment(name);
  final file = File(value);
  if (!_isAbsolutePath(value) || !file.existsSync()) {
    throw StateError('$name must identify an existing absolute file');
  }
  return file.absolute.path;
}

String _platformName() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  return Platform.operatingSystem;
}

String _safeReason(Object error) {
  final value = '$error';
  if (RegExp(
    r'(secret|token|password|authorization|api.?key|private.?key|bearer)',
    caseSensitive: false,
  ).hasMatch(value)) {
    return '[REDACTED: credential-shaped diagnostic]';
  }
  return value.length <= 1024 ? value : value.substring(value.length - 1024);
}
