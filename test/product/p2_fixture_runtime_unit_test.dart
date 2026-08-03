import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/p2_automation_host.dart';
import 'package:kristin_local_agent/product/p2_automation_host_operations.dart';
import 'package:kristin_local_agent/product/p2_automation_host_process_client.dart';
import 'package:kristin_local_agent/product/p2_effect_boundary.dart';
import 'package:kristin_local_agent/product/p2_effect_journal.dart';
import 'package:kristin_local_agent/product/p2_finite_command_service.dart';
import 'package:kristin_local_agent/product/p2_filesystem_service.dart';
import 'package:kristin_local_agent/product/p2_process_tree.dart';
import 'package:kristin_local_agent/product/p2_product_evidence.dart';
import 'package:kristin_local_agent/product/p2_pty_service.dart';
import 'package:kristin_local_agent/product/p2_runtime_composition.dart';
import 'package:kristin_local_agent/product/p2_snapshot_undo.dart';

void main() {
  final taskId = Platform.environment['KRISTIN_P2_TASK_ID'] ?? '';
  test('fixture runtime diagnostic for $taskId', () async {
    final outputPath = Platform.environment['KRISTIN_P2_PRODUCT_EVIDENCE'];
    final commitSha = Platform.environment['KRISTIN_P2_COMMIT_SHA'] ?? '';
    if (outputPath == null ||
        !RegExp(r'^P2-\d{3}$').hasMatch(taskId) ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(commitSha)) {
      fail('product evidence environment is incomplete');
    }

    final startedAt = DateTime.now().toUtc();
    final output = File(outputPath);
    final temporary = await Directory.systemTemp.createTemp(
      'kristin-p2-product-runtime-',
    );
    final journal = _MemoryJournal();
    var entryPoint = 'P2OwnerRuntimeComposition.start';
    var productionAdapter = 'not_started';
    var osEffect = <String, Object?>{};
    var postcondition = <String, Object?>{'observed': false};
    var receipt = <String, Object?>{'status': 'blocked'};
    var status = 'blocked';
    P2OwnerRuntimeComposition? composition;
    try {
      final node = _requiredAbsoluteExecutable('KRISTIN_NODE_EXECUTABLE');
      final project = Directory.current.absolute;
      final hostScript = File(
        '${project.path}${Platform.pathSeparator}automation_host${Platform.pathSeparator}src${Platform.pathSeparator}host.mjs',
      ).absolute;
      final authorityScript = File(
        '${project.path}${Platform.pathSeparator}automation_host${Platform.pathSeparator}src${Platform.pathSeparator}fixture-authority.mjs',
      ).absolute;
      final interactiveAdapter = File(
        '${project.path}${Platform.pathSeparator}automation_host${Platform.pathSeparator}src${Platform.pathSeparator}interactive-desktop-adapter.mjs',
      ).absolute;
      for (final required in <File>[hostScript, authorityScript]) {
        if (!required.existsSync()) {
          fail('required runtime source missing: ${required.path}');
        }
      }
      final authority = _NodeFixtureDesktopAuthority(
        nodeExecutable: node,
        authorityScript: authorityScript,
        stateFile: File(
          '${temporary.path}${Platform.pathSeparator}authority-state.json',
        ),
        requestDirectory: Directory(
          '${temporary.path}${Platform.pathSeparator}authority-requests',
        ),
        scopeRoots: <String>{
          temporary.path,
          project.path,
          File(node).parent.path,
        }.toList(growable: false),
      );
      final processAuthorizations = <int, P2ProcessAuthorization>{};
      final watchdogAuthorizations = <String, P2WatchdogAuthorization>{};

      Future<P2OwnerRuntimeComposition> startRuntime() =>
          P2OwnerRuntimeComposition.start(
            launchConfig: P2AutomationHostLaunchConfig(
              nodeExecutable: node,
              hostScript: hostScript.path,
              workingDirectory:
                  '${project.path}${Platform.pathSeparator}automation_host',
              restrictedWorkerLauncher: node,
              restrictedWorkerLauncherSha256:
                  Sha256.hex(File(node).readAsBytesSync()),
              workerPolicy: authorityScript.path,
              workerPolicySha256: Sha256.hex(authorityScript.readAsBytesSync()),
              nodeExecutableSha256: Sha256.hex(File(node).readAsBytesSync()),
              hostScriptSha256: Sha256.hex(hostScript.readAsBytesSync()),
              bootstrapProvider: authority,
              windowsJobHelper:
                  _optionalAbsoluteFile('KRISTIN_WINDOWS_JOB_HELPER'),
              posixWatchdog:
                  _optionalAbsoluteFile('KRISTIN_POSIX_WATCHDOG_HELPER'),
              interactiveDesktopAdapter: interactiveAdapter.existsSync()
                  ? interactiveAdapter.path
                  : null,
              interactiveDesktopAttested:
                  Platform.environment['KRISTIN_P2_INTERACTIVE_DESKTOP'] == '1',
              fixtureRoot: temporary.path,
            ),
            authority: authority,
            journal: journal,
            hostBindingProvider: _BindingProvider(taskId),
            processAuthorizationFor: (int pid, String operation) {
              final value = processAuthorizations[pid];
              if (value == null) {
                throw StateError('process_authorization_missing');
              }
              return value;
            },
            watchdogAuthorizationFor: (String id, String operation) {
              final value = watchdogAuthorizations[id];
              if (value == null) {
                throw StateError('watchdog_authorization_missing');
              }
              return value;
            },
          );

      composition = await startRuntime();
      switch (taskId) {
        case 'P2-002':
          final result = await _exerciseProductFilesystem(
            temporary,
            composition.filesystemService(
              Directory(
                '${temporary.path}${Platform.pathSeparator}filesystem-backups',
              ),
            ),
          );
          entryPoint =
              'P2OwnerRuntimeComposition.filesystemService.write/read/enumerate/moveToQuarantine';
          productionAdapter =
              'P2DesktopFilesystemAuthorizer+P2FilesystemService';
          osEffect = result.osEffect;
          postcondition = result.postcondition;
          receipt = result.receipt;
          status = 'passed';
          break;
        case 'P2-003':
          final result = await composition.commandService.run(
            P2CommandSpec(
              executable: node,
              cwd: temporary.path,
              arguments: const <String>[
                '-e',
                "process.stdout.write('KRISTIN_COMMAND_STDOUT_λ');process.stderr.write('KRISTIN_COMMAND_STDERR');",
              ],
              environmentDelta: const <String, String?>{
                'KRISTIN_COMMAND_FIXTURE': '1',
              },
              deadline: const Duration(seconds: 20),
              maxStdoutBytes: 64 * 1024,
              maxStderrBytes: 64 * 1024,
            ),
            binding: _binding(taskId, 'command.run'),
          );
          expect(utf8.decode(result.stdout), 'KRISTIN_COMMAND_STDOUT_λ');
          expect(utf8.decode(result.stderr), 'KRISTIN_COMMAND_STDERR');
          expect(result.status, P2EffectStatus.succeeded);
          productionAdapter = 'P2AutomationFiniteCommandService';
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
          receipt = journal.last('command.run').toJson();
          status = 'passed';
          break;
        case 'P2-010':
          final result = await _exerciseProductUndo(
            temporary,
            composition.snapshotUndoService(
              Directory(
                '${temporary.path}${Platform.pathSeparator}snapshots',
              ),
            ),
            _binding(taskId, 'snapshot.restore'),
          );
          entryPoint = 'P2OwnerRuntimeComposition.snapshotUndoService.restore';
          productionAdapter =
              'P2DesktopHostOperationAuthorizer+P2SnapshotUndoService.restore';
          osEffect = result.osEffect;
          postcondition = result.postcondition;
          receipt = result.receipt;
          status = 'passed';
          break;
        case 'P2-005':
        case 'P2-006':
        case 'P2-011':
          final pty = await _openProductPty(
            composition,
            authority,
            temporary,
            taskId,
            node,
          );
          processAuthorizations[pty.session.processIdentity.pid] =
              P2ProcessAuthorization(
            binding: pty.binding,
            grantDigest: pty.grantDigest,
          );
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
                .listen((List<int> bytes) {
              observed.addAll(bytes);
              if (!marker.isCompleted &&
                  utf8.decode(observed, allowMalformed: true).contains(
                        'KRISTIN_PTY_UNICODE_λ',
                      )) {
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
            await composition.ptyBackend.detach(
              pty.session.sessionId,
              binding: pty.binding,
              grantDigest: pty.grantDigest,
            );
            final attached = await composition.ptyBackend.attach(
              pty.session.sessionId,
              0,
              binding: pty.binding,
              grantDigest: pty.grantDigest,
            );
            await composition.ptyBackend.terminate(
              pty.session.sessionId,
              binding: pty.binding,
              grantDigest: pty.grantDigest,
            );
            await subscription.cancel();
            productionAdapter = 'P2AutomationPtyBackend';
            osEffect = <String, Object?>{
              'kind': 'interactive_pty',
              'processIdentity': pty.session.processIdentity.toJson(),
            };
            postcondition = <String, Object?>{
              'observed': true,
              'unicodeObserved': true,
              'resizeColumns': 132,
              'resizeRows': 44,
              'reconnectCursor': attached.transcriptCursor,
            };
            receipt = composition.ptyBackend
                    .receiptFor(pty.session.sessionId)
                    ?.toJson() ??
                <String, Object?>{'status': 'missing'};
            status = 'passed';
          } else if (taskId == 'P2-006') {
            final manager = P2ProcessTreeManager(
              composition.processTreeAdapter,
            );
            final before = await manager.reconcile(
              pty.session.processIdentity,
            );
            expect(before, P2ProcessLifecycle.running);
            await manager.kill(pty.session.processIdentity);
            final effectReceipt = composition.processTreeAdapter
                .receiptForPid(pty.session.processIdentity.pid);
            expect(effectReceipt, isNotNull);
            final termination = Map<String, Object?>.from(
              effectReceipt!.details['termination']! as Map,
            );
            expect(termination['identityVerified'], true);
            expect(termination['activeProcesses'], 0);
            final after = await manager.reconcile(
              pty.session.processIdentity,
            );
            expect(
              after,
              isIn(<P2ProcessLifecycle>[
                P2ProcessLifecycle.exited,
                P2ProcessLifecycle.killed,
                P2ProcessLifecycle.stopped,
              ]),
            );
            productionAdapter = 'P2AutomationProcessTreeAdapter';
            osEffect = <String, Object?>{
              'kind': 'managed_process_tree_termination',
              'processIdentity': pty.session.processIdentity.toJson(),
            };
            postcondition = <String, Object?>{
              'observed': true,
              'lifecycleBefore': before.name,
              'lifecycleAfter': after.name,
              'identityVerified': termination['identityVerified'],
              'activeProcesses': termination['activeProcesses'],
            };
            receipt = effectReceipt.toJson();
            status = 'passed';
          } else {
            final helper = Platform.isWindows
                ? _optionalAbsoluteFile('KRISTIN_WINDOWS_JOB_HELPER')
                : _optionalAbsoluteFile('KRISTIN_POSIX_WATCHDOG_HELPER');
            if (helper == null) {
              throw StateError('native_external_watchdog_helper_required');
            }
            final watchdogId =
                'p2-watchdog-${DateTime.now().microsecondsSinceEpoch}';
            watchdogAuthorizations[watchdogId] = P2WatchdogAuthorization(
              binding: pty.binding,
              grantDigest: pty.grantDigest,
              sessionId: pty.session.sessionId,
              processIdentity: pty.session.processIdentity,
            );
            final killed = composition.watchdogTransport
                .events(watchdogId)
                .firstWhere(
                  (Map<String, Object?> event) =>
                      event['type'] == 'watchdog.receipt' &&
                      event['receipt'] is Map,
                )
                .timeout(const Duration(seconds: 20));
            await composition.watchdogTransport.arm(
              watchdogId: watchdogId,
              heartbeatTimeout: const Duration(milliseconds: 500),
            );
            // Deliberately block the desktop event loop. The native watchdog is
            // a separately supervised process and must still terminate the tree.
            sleep(const Duration(seconds: 2));
            final event = await killed;
            final raw = Map<String, Object?>.from(event['receipt']! as Map);
            expect(raw['identityVerified'], true);
            expect(raw['activeProcesses'], 0);
            productionAdapter = 'P2AutomationWatchdogTransport';
            osEffect = <String, Object?>{
              'kind': 'external_watchdog_kill_during_ui_freeze',
              'processIdentity': pty.session.processIdentity.toJson(),
            };
            postcondition = <String, Object?>{
              'observed': true,
              'desktopEventLoopBlocked': true,
              'identityVerified': raw['identityVerified'],
              'activeProcesses': raw['activeProcesses'],
            };
            receipt = raw;
            status = 'passed';
          }
          break;
        case 'P2-007':
          final binding = _binding(taskId, 'package.plan');
          final plan = await composition.hostOperations.plan(
            'fixture',
            'install',
            const <String>['kristin-fixture-sdk'],
            binding,
          );
          final applied = await composition.hostOperations.apply(
            plan,
            _binding(taskId, 'package.apply'),
          );
          final sdks = await composition.hostOperations.discoverSdks(
            _binding(taskId, 'sdk.discover'),
          );
          final ledger = File(
            '${temporary.path}${Platform.pathSeparator}package-state.json',
          );
          expect(await ledger.exists(), true);
          expect(applied.status, P2EffectStatus.succeeded);
          productionAdapter = 'P2AutomationHostOperations';
          osEffect = <String, Object?>{
            'kind': 'fixture_package_apply_and_sdk_discovery',
            'ledgerPath': ledger.path,
          };
          postcondition = <String, Object?>{
            'observed': true,
            'packageApplied': applied.output['applied'] == true,
            'sdkRows': sdks.length,
          };
          receipt = applied.receipt.toJson();
          status = 'passed';
          break;
        case 'P2-008':
          const serviceId = 'fixture.kristin-p2-service';
          final started = await composition.hostOperations.serviceStart(
            serviceId,
            _binding(taskId, 'service.start'),
          );
          final running = await composition.hostOperations.serviceStatus(
            serviceId,
            _binding(taskId, 'service.status'),
          );
          expect(running.output['state'], 'running');
          final stopped = await composition.hostOperations.serviceStop(
            serviceId,
            _binding(taskId, 'service.stop'),
          );
          final opened =
              await composition.hostOperations.applicationOpenExecutable(
            node,
            const <String>['-e', 'setInterval(()=>{},1000)'],
            _binding(taskId, 'application.open'),
            cwd: temporary.path,
          );
          final identity = opened.output['identity'];
          expect(identity, isA<String>());
          final closed = await composition.hostOperations.applicationClose(
            identity! as String,
            _binding(taskId, 'application.close'),
          );
          expect(started.status, P2EffectStatus.succeeded);
          expect(stopped.status, P2EffectStatus.succeeded);
          expect(closed.status, P2EffectStatus.succeeded);
          productionAdapter = 'P2AutomationHostOperations';
          osEffect = <String, Object?>{
            'kind': 'fixture_service_and_application_lifecycle',
            'serviceId': serviceId,
          };
          postcondition = <String, Object?>{
            'observed': true,
            'serviceRunningObserved': true,
            'serviceStoppedObserved': true,
            'applicationClosedObserved': true,
          };
          receipt = closed.receipt.toJson();
          status = 'passed';
          break;
        case 'P2-009':
          if (Platform.environment['KRISTIN_P2_INTERACTIVE_DESKTOP'] != '1') {
            throw StateError('governed_interactive_desktop_lane_required');
          }
          final marker =
              'kristin-clipboard-${DateTime.now().microsecondsSinceEpoch}';
          await composition.hostOperations.writeClipboard(
            marker,
            _binding(taskId, 'clipboard.write'),
          );
          final read = await composition.hostOperations.readClipboard(
            _binding(taskId, 'clipboard.read'),
          );
          final screen = await composition.hostOperations.captureScreen(
            _binding(taskId, 'screen.capture'),
          );
          final window = await composition.hostOperations.activeWindowMetadata(
            _binding(taskId, 'screen.activeWindowMetadata'),
          );
          expect(read, marker);
          expect(screen, isNotEmpty);
          expect(window, isNotEmpty);
          productionAdapter = 'P2AutomationHostOperations';
          osEffect = <String, Object?>{
            'kind': 'interactive_clipboard_screen_active_window',
            'screenBytes': screen.length,
          };
          postcondition = <String, Object?>{
            'observed': true,
            'clipboardRoundTrip': true,
            'screenCaptured': true,
            'activeWindowObserved': true,
            'ordinaryLogContent': false,
          };
          receipt = journal.last('screen.activeWindowMetadata').toJson();
          status = 'passed';
          break;
        case 'P2-013':
          await composition.hostOperations.supportMatrix();
          final replayEnvelope = await authority.issue(
            binding: _binding(taskId, 'host.supportMatrix'),
            operation: 'host.supportMatrix',
            payload: const <String, Object?>{
              'operation': 'host.supportMatrix',
            },
          );
          final initial = await composition.client.invoke(replayEnvelope);
          expect(initial['status'], 'ok');
          await composition.close();
          composition = await startRuntime();
          final replay = await composition.client.invoke(replayEnvelope);
          expect(replay['status'], 'error');
          productionAdapter =
              'P2ProcessAutomationHostClient+P2AutomationHostOperations';
          osEffect = <String, Object?>{
            'kind': 'automation_host_restart_replay_reconciliation',
            'requestId': replayEnvelope.requestId,
          };
          postcondition = <String, Object?>{
            'observed': true,
            'firstDispatchSucceeded': true,
            'replayRejectedAfterRestart': true,
            'replayCode': replay['code']?.toString() ?? 'request_failed',
          };
          receipt = <String, Object?>{
            'status': 'succeeded',
            'type': 'restart-replay-adversarial-receipt',
            'requestId': replayEnvelope.requestId,
            'replayRejected': true,
          };
          status = 'passed';
          break;
        default:
          throw StateError('product_runtime_task_not_supported');
      }
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
      await composition?.close();
      status = 'blocked';
      final evidence = P2ProductAssertionEvidence(
        taskId: taskId,
        assertionId: 'p2-${taskId.substring(3)}.product-runtime-e2e',
        platform: _platformName(),
        commitSha: commitSha,
        entryPoint: entryPoint,
        applicationComposition: 'diagnostic-fixture-runtime',
        applicationCompositionSha256: Sha256.text('diagnostic-fixture-runtime'),
        authorizationBoundary: 'p1-isolated-authority-service-effect-permit-v2',
        authority: const <String, Object?>{
          'authorityImplementation': 'diagnostic-only',
          'authorityKind': 'unit-test-only',
          'completionEligible': false,
        },
        productionAdapter: productionAdapter,
        runnerAttestationSha256: '0' * 64,
        toolchainExtensionFingerprint: '0' * 64,
        nativeRuntimeManifestSha256: '0' * 64,
        osEffect: osEffect,
        postcondition: postcondition,
        receipt: receipt,
        status: status,
        sourceOnly: true,
        fixtureAuthority: true,
        completionEligible: false,
        startedAt: startedAt,
        completedAt: DateTime.now().toUtc(),
      );
      await evidence.write(output);
      await temporary.delete(recursive: true);
    }
  },
      skip: taskId.isEmpty
          ? 'diagnostic harness requires an explicit task id'
          : false);
}

final class _ProductPty {
  const _ProductPty({
    required this.session,
    required this.binding,
    required this.grantDigest,
  });

  final P2PtySession session;
  final P2EffectBinding binding;
  final String grantDigest;
}

Future<_ProductPty> _openProductPty(
  P2OwnerRuntimeComposition composition,
  _NodeFixtureDesktopAuthority authority,
  Directory temporary,
  String taskId,
  String node,
) async {
  final binding = _binding(taskId, 'pty.open');
  final prepared = await authority.issue(
    binding: binding,
    operation: 'pty.open',
    payload: const <String, Object?>{
      'operation': 'pty.open',
      'preparedGrantOnly': true,
    },
  );
  final grantDigest = prepared.grantProof.grantDigest;
  final shell = Platform.isWindows
      ? (Platform.environment['ComSpec'] ?? 'C:\\Windows\\System32\\cmd.exe')
      : '/bin/sh';
  final request = P2PtyOpenRequest(
    shell: shell,
    cwd: temporary.path,
    transcriptBudgetBytes: 256 * 1024,
  );
  final session = await P2InteractivePtyService(composition.ptyBackend).open(
    request,
    binding,
    grantDigest,
  );
  return _ProductPty(
    session: session,
    binding: binding,
    grantDigest: grantDigest,
  );
}

final class _FilesystemObservation {
  const _FilesystemObservation({
    required this.osEffect,
    required this.postcondition,
    required this.receipt,
  });

  final Map<String, Object?> osEffect;
  final Map<String, Object?> postcondition;
  final Map<String, Object?> receipt;
}

Future<_FilesystemObservation> _exerciseProductFilesystem(
  Directory temporary,
  P2FilesystemService service,
) async {
  final target = File(
    '${temporary.path}${Platform.pathSeparator}.kristin-ユニコード-λ.txt',
  );
  final payload = Uint8List.fromList(utf8.encode('KRISTIN_FILESYSTEM_λ'));
  final writeReceipt = await service.write(
    target.path,
    payload,
    binding: _binding('P2-002', 'write'),
  );
  final read = await service.read(
    target.path,
    binding: _binding('P2-002', 'read'),
    maxBytes: 64 * 1024,
  );
  final listed = await service
      .enumerate(
        temporary.path,
        binding: _binding('P2-002', 'enumerate'),
        maxEntries: 100,
      )
      .toList();
  expect(read, orderedEquals(payload));
  expect(listed.any((FileSystemEntity item) => item.path == target.path), true);
  final deleteReceipt = await service.moveToQuarantine(
    target.path,
    binding: _binding('P2-002', 'delete'),
  );
  final quarantinePath = deleteReceipt.details['quarantinePath']?.toString();
  expect(await target.exists(), false);
  expect(quarantinePath, isNotNull);
  expect(await FileSystemEntity.type(quarantinePath!, followLinks: false),
      isNot(FileSystemEntityType.notFound));
  return _FilesystemObservation(
    osEffect: <String, Object?>{
      'kind': 'owner_filesystem_transaction_and_quarantine',
      'path': target.path,
      'quarantinePath': quarantinePath,
    },
    postcondition: <String, Object?>{
      'observed': true,
      'unicodeRoundTrip': utf8.decode(read) == 'KRISTIN_FILESYSTEM_λ',
      'enumerated': true,
      'quarantined': true,
      'writeReceiptStatus': writeReceipt.status.name,
    },
    receipt: deleteReceipt.toJson(),
  );
}

final class _UndoObservation {
  const _UndoObservation({
    required this.osEffect,
    required this.postcondition,
    required this.receipt,
  });

  final Map<String, Object?> osEffect;
  final Map<String, Object?> postcondition;
  final Map<String, Object?> receipt;
}

Future<_UndoObservation> _exerciseProductUndo(
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
  return _UndoObservation(
    osEffect: <String, Object?>{
      'kind': 'product_snapshot_restore',
      'target': target.path,
      'backup': backup.path,
    },
    postcondition: <String, Object?>{
      'observed': true,
      'restoredContent': value == 'before',
      'completedSteps': restored.completedSteps,
    },
    receipt: restored.receipt.toJson(),
  );
}

final class _NodeFixtureDesktopAuthority
    implements
        P2AutomationEnvelopeAuthority,
        P2ProtectedAutomationBootstrapProvider {
  _NodeFixtureDesktopAuthority({
    required this.nodeExecutable,
    required this.authorityScript,
    required this.stateFile,
    required this.requestDirectory,
    required this.scopeRoots,
  });

  final String nodeExecutable;
  final File authorityScript;
  final File stateFile;
  final Directory requestDirectory;
  final List<String> scopeRoots;
  var _requestCounter = 0;

  Future<Map<String, Object?>> _run(List<String> arguments) async {
    final result = await Process.run(
      nodeExecutable,
      <String>[authorityScript.path, ...arguments],
      workingDirectory: authorityScript.parent.parent.path,
      environment: <String, String>{
        if (Platform.environment['PATH'] case final value?) 'PATH': value,
        if (Platform.environment['Path'] case final value?) 'Path': value,
        if (Platform.environment['SystemRoot'] case final value?)
          'SystemRoot': value,
        if (Platform.environment['WINDIR'] case final value?) 'WINDIR': value,
        if (Platform.environment['HOME'] case final value?) 'HOME': value,
        if (Platform.environment['USERPROFILE'] case final value?)
          'USERPROFILE': value,
        if (Platform.environment['TEMP'] case final value?) 'TEMP': value,
        if (Platform.environment['TMP'] case final value?) 'TMP': value,
      },
      includeParentEnvironment: false,
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw StateError('fixture_authority_failed:${result.exitCode}');
    }
    final decoded = jsonDecode('${result.stdout}'.trim());
    if (decoded is! Map) throw StateError('fixture_authority_response_invalid');
    return Map<String, Object?>.from(decoded);
  }

  @override
  Future<Map<String, Object?>> take() => _run(
        <String>['bootstrap', '--state', stateFile.path],
      );

  @override
  Future<P2AutomationEnvelope> issue({
    required P2EffectBinding binding,
    required String operation,
    required Map<String, Object?> payload,
    String? expectedGrantDigest,
    Duration deadline = const Duration(seconds: 30),
  }) async {
    await requestDirectory.create(recursive: true);
    final request = File(
      '${requestDirectory.path}${Platform.pathSeparator}request-${_requestCounter++}.json',
    );
    await request.writeAsString(
      jsonEncode(<String, Object?>{
        'binding': <String, Object?>{
          'runId': binding.runId,
          'taskId': binding.taskId,
          'actorId': binding.actorId,
          'toolId': binding.toolId,
          'accessProfileId': binding.accessProfileId,
          'capabilityId': binding.capabilityId,
        },
        'operation': operation,
        'payload': payload,
        if (expectedGrantDigest != null)
          'expectedGrantDigest': expectedGrantDigest,
        'maxUses': 500,
        'deadlineMs': deadline.inMilliseconds,
        'scopeRoots': scopeRoots,
      }),
      flush: true,
    );
    final value = await _run(
      <String>[
        'issue',
        '--state',
        stateFile.path,
        '--request',
        request.path,
      ],
    );
    return P2AutomationEnvelope.fromJson(value);
  }
}

final class _BindingProvider implements P2HostBindingProvider {
  const _BindingProvider(this.taskId);
  final String taskId;

  @override
  P2EffectBinding bindingFor(String operation) => _binding(taskId, operation);
}

final class _MemoryJournal implements P2EffectJournal {
  final List<P2EffectReceipt> receipts = <P2EffectReceipt>[];

  @override
  Future<void> append(P2EffectReceipt receipt) async {
    receipts.add(receipt);
  }

  P2EffectReceipt last(String operation) => receipts.lastWhere(
        (P2EffectReceipt receipt) => receipt.operation == operation,
      );
}

P2EffectBinding _binding(String taskId, String operation) => P2EffectBinding(
      runId: 'p2-product-runtime-run',
      taskId: taskId,
      actorId: 'owner-operator-fixture',
      toolId: 'p2-product-runtime',
      accessProfileId: 'owner',
      capabilityId: 'p2.owner.host-effect',
      operation: operation,
    );

String _requiredAbsoluteExecutable(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty || !File(value).isAbsolute) {
    fail('$name must be an absolute executable path');
  }
  if (!File(value).existsSync()) fail('$name does not exist');
  return File(value).absolute.path;
}

String? _optionalAbsoluteFile(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) return null;
  final file = File(value);
  if (!file.isAbsolute || !file.existsSync()) {
    throw StateError('$name must be an existing absolute file');
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
  final value = error.toString();
  if (RegExp(
    r'(secret|token|password|authorization|api.?key|private.?key|bearer)',
    caseSensitive: false,
  ).hasMatch(value)) {
    return '[REDACTED: credential-shaped diagnostic]';
  }
  return value.length <= 1024 ? value : value.substring(value.length - 1024);
}
