import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'p2_automation_host_operations.dart';
import 'p2_automation_host_process_client.dart';
import 'p2_effect_boundary.dart';
import 'p2_effect_journal.dart';
import 'p2_emergency_watchdog.dart';
import 'p2_owner_mode.dart';
import 'p2_owner_workspace.dart';
import 'p2_managed_authorization_registry.dart';
import 'p2_p1_authority_adapter.dart';
import 'p2_process_tree.dart';
import 'p2_product_binding_context.dart';
import 'p2_pty_service.dart';
import 'p2_runtime_composition.dart';
import 'p2_terminal_model.dart';

class P2SupervisedRunBinding {
  const P2SupervisedRunBinding({
    required this.watchdogId,
    required this.sessionId,
    required this.processIdentity,
    required this.authorization,
  });

  final String watchdogId;
  final String sessionId;
  final P2ProcessIdentity processIdentity;
  final P2WatchdogAuthorization authorization;
}

/// Owner Mode lifecycle owned by the shipped ProductRuntime. Watchdogs are
/// armed and heartbeated here, not from tests or from the Flutter widget.
final class P2ProductRuntimeOwnerMode {
  P2ProductRuntimeOwnerMode._({
    required this.composition,
    required this.controller,
    required this.terminalModel,
    required this.emergencyController,
    required this.actions,
    required this.authority,
    required this.stateDirectory,
    required this.bindingContext,
    required this.authorizationRegistry,
  });

  final P2OwnerRuntimeComposition composition;
  final P2OwnerModeController controller;
  final P2TerminalModel terminalModel;
  final P2EmergencyController emergencyController;
  final P2OwnerWorkspaceServiceActions actions;
  final P2RuntimeAuthority authority;
  final Directory stateDirectory;
  final P2ProductBindingContext bindingContext;
  final P2ManagedAuthorizationRegistry authorizationRegistry;

  final Map<String, Timer> _heartbeats = <String, Timer>{};
  final Map<String, P2SupervisedRunBinding> _supervised =
      <String, P2SupervisedRunBinding>{};
  bool _closed = false;

  static Future<P2ProductRuntimeOwnerMode> start({
    required Directory stateDirectory,
    required P2RuntimeAuthority authority,
    required P2EffectJournal journal,
    required P2AutomationHostLaunchConfig launchConfig,
    required P2HostBindingProvider hostBindingProvider,
    required P2ProcessAuthorizationResolver processAuthorizationFor,
    required P2WatchdogAuthorizationResolver watchdogAuthorizationFor,
    required P2TerminalAuthorizationResolver terminalAuthorizationFor,
    required P2TerminalBytesReader selectionBytes,
    required P2TerminalBytesReader transcriptBytes,
    required P2ClipboardTextWriter writeClipboardText,
    required P2TranscriptFileWriter writeTranscriptFile,
    required Future<void> Function(Map<String, Object?> value)
        persistOwnerSettings,
    required Future<void> Function() clearOwnerSettings,
    required String emergencyWatchdogId,
    required P2ProductBindingContext bindingContext,
    required P2ManagedAuthorizationRegistry authorizationRegistry,
  }) async {
    final productionAuthority = authority.completionEligible &&
        authority.authorityKind == 'p1-isolated-authority-service-v2';
    final ownerRiskAuthority = authority.qaPreview &&
        !authority.completionEligible &&
        authority.authorityKind == 'p2-owner-risk-current-account-v1' &&
        authority.authorityProvenance['securityEvidenceWaived'] == true;
    if (!(productionAuthority || ownerRiskAuthority)) {
      throw StateError('fixture_or_unapproved_authority_rejected');
    }
    await stateDirectory.create(recursive: true);
    late P2ProductRuntimeOwnerMode runtime;
    final terminal = P2TerminalModel();
    final composition = await P2OwnerRuntimeComposition.start(
      launchConfig: launchConfig,
      authority: authority,
      journal: journal,
      hostBindingProvider: hostBindingProvider,
      processAuthorizationFor: processAuthorizationFor,
      watchdogAuthorizationFor: watchdogAuthorizationFor,
      onPtySessionOpened: (
        P2PtyOpenRequest request,
        P2PtySession session,
        P2EffectBinding binding,
        String grantDigest,
      ) async {
        final watchdogId = 'pty-${session.sessionId}';
        final watchdogAuthorization = P2WatchdogAuthorization(
          binding: binding,
          grantDigest: grantDigest,
          sessionId: session.sessionId,
          processIdentity: session.processIdentity,
        );
        await runtime.supervise(
          binding: P2SupervisedRunBinding(
            watchdogId: watchdogId,
            sessionId: session.sessionId,
            processIdentity: session.processIdentity,
            authorization: watchdogAuthorization,
          ),
        );
        terminal.add(
          P2TerminalTab(
            id: session.sessionId,
            title: 'Terminal ${terminal.tabs.length + 1}',
            shell: request.shell,
            cwd: request.cwd,
            runId: session.runId,
            taskId: session.taskId,
            grantId: grantDigest,
            attached: true,
            accessibilityLabel:
                'Owner terminal ${terminal.tabs.length + 1}, run ${session.runId}, task ${session.taskId}',
          ),
        );
      },
    );
    final controller = P2OwnerModeController(
      persistOwnerSettings,
      clearOwnerSettings,
    );
    final emergency = P2EmergencyController(composition.watchdogTransport);
    final actions = P2OwnerWorkspaceServiceActions(
      ptyBackend: composition.ptyBackend,
      emergencyController: emergency,
      watchdogId: emergencyWatchdogId,
      authorizationFor: terminalAuthorizationFor,
      selectionBytes: selectionBytes,
      transcriptBytes: transcriptBytes,
      writeClipboardText: writeClipboardText,
      writeTranscriptFile: writeTranscriptFile,
      emergencyAction: () => runtime.emergencyPauseAndKillAll(),
    );
    runtime = P2ProductRuntimeOwnerMode._(
      composition: composition,
      controller: controller,
      terminalModel: terminal,
      emergencyController: emergency,
      actions: actions,
      authority: authority,
      stateDirectory: stateDirectory,
      bindingContext: bindingContext,
      authorizationRegistry: authorizationRegistry,
    );
    await runtime.reconcileAfterRestart();
    return runtime;
  }

  void activateEffectContext({required String runId, required String taskId}) {
    if (_closed) {
      throw StateError('owner_runtime_closed');
    }
    bindingContext.activate(runId: runId, taskId: taskId);
  }

  void clearEffectContext({required String runId, required String taskId}) {
    bindingContext.clear(runId: runId, taskId: taskId);
  }

  Map<String, Object?> get runtimeProvenance => <String, Object?>{
        'entryPoint':
            'ProductRuntime.initialize -> P2ProductRuntimeBootstrap.start',
        'shippedProductRuntime': true,
        'applicationCompositionPatched': true,
        'ownerRuntime': 'P2ProductRuntimeOwnerMode',
        'authority': authority.authorityProvenance,
        'bindingContext': bindingContext.provenance,
        'authorizationRegistry': authorizationRegistry.provenance,
        'watchdogLifecycleOwnedByProductRuntime': true,
        'watchdogAutomaticallyArmed': _supervised.isNotEmpty,
        'fixtureAuthorityEligible': false,
        'ownerRiskQa': authority.qaPreview,
      };

  Widget buildWorkspace({Key? key}) => P2OwnerWorkspace(
        key: key,
        controller: controller,
        terminalModel: terminalModel,
        actions: actions,
      );

  /// Called by the shipped runtime immediately after a managed session starts.
  Future<void> supervise({
    required P2SupervisedRunBinding binding,
    Duration heartbeatTimeout = const Duration(seconds: 8),
    Duration heartbeatInterval = const Duration(seconds: 2),
  }) async {
    if (_closed) {
      throw StateError('owner_runtime_closed');
    }
    if (_supervised.containsKey(binding.watchdogId)) {
      throw StateError('watchdog_already_supervising');
    }
    if (heartbeatInterval <= Duration.zero ||
        heartbeatInterval >= heartbeatTimeout) {
      throw StateError('watchdog_interval_invalid');
    }
    if (binding.authorization.sessionId != binding.sessionId ||
        binding.authorization.processIdentity.pid !=
            binding.processIdentity.pid ||
        binding.authorization.processIdentity.startToken !=
            binding.processIdentity.startToken) {
      throw StateError('supervision_authorization_identity_mismatch');
    }
    authorizationRegistry.registerProcess(
      identity: binding.processIdentity,
      authorization: P2ProcessAuthorization(
        binding: binding.authorization.binding,
        grantDigest: binding.authorization.grantDigest,
      ),
    );
    authorizationRegistry.registerWatchdog(
      watchdogId: binding.watchdogId,
      authorization: binding.authorization,
    );
    _supervised[binding.watchdogId] = binding;
    await emergencyController.arm(
      binding.watchdogId,
      timeout: heartbeatTimeout,
    );
    await _persistLifecycle(binding, 'armed');
    final timer = Timer.periodic(heartbeatInterval, (_) {
      unawaited(_heartbeat(binding.watchdogId));
    });
    _heartbeats[binding.watchdogId] = timer;
  }

  Future<void> _heartbeat(String watchdogId) async {
    if (_closed || !_supervised.containsKey(watchdogId)) {
      return;
    }
    try {
      await emergencyController.heartbeat(watchdogId);
      await _persistLifecycle(_supervised[watchdogId]!, 'heartbeat');
    } catch (_) {
      // Stop issuing ambiguous heartbeats. The external watchdog remains armed
      // and independently kills/reconciles the exact bound process tree.
      _heartbeats.remove(watchdogId)?.cancel();
      await _persistLifecycle(_supervised[watchdogId]!, 'heartbeat_failed');
    }
  }

  /// Idempotent emergency command used by the actual workspace keyboard/button
  /// path. Every currently supervised session has an independently armed
  /// out-of-process watchdog; the command never relies on Flutter responsiveness.
  Future<void> emergencyPauseAndKillAll() async {
    final ids = _supervised.keys.toList(growable: false)..sort();
    if (ids.isEmpty) {
      throw StateError('no_supervised_process_tree');
    }
    for (final id in ids) {
      await emergencyController.pauseAndKill(id);
      final binding = _supervised[id];
      if (binding != null) {
        await _persistLifecycle(binding, 'emergency_kill_requested');
      }
    }
  }

  Map<String, Object?> supervisionSnapshot() => <String, Object?>{
        'watchdogIds': _supervised.keys.toList(growable: false)..sort(),
        'heartbeatCount': _heartbeats.length,
        'automaticallyArmed': _supervised.isNotEmpty,
      };
  Future<void> completeSupervision(
    String watchdogId, {
    required bool processTreeStopped,
  }) async {
    final binding = _supervised.remove(watchdogId);
    _heartbeats.remove(watchdogId)?.cancel();
    if (binding == null) {
      return;
    }
    authorizationRegistry.unregister(
      watchdogId: binding.watchdogId,
      processIdentity: binding.processIdentity,
    );
    await _persistLifecycle(
      binding,
      processTreeStopped ? 'completed' : 'unknown_requires_reconciliation',
    );
  }

  /// Test-only freeze hook is intentionally on the real runtime lifecycle. It
  /// cancels the desktop heartbeat without stopping the external watchdog.
  Future<void> freezeHeartbeatForAdversarialTest(String watchdogId) async {
    final binding = _supervised[watchdogId];
    if (binding == null) {
      throw StateError('watchdog_not_supervising');
    }
    _heartbeats.remove(watchdogId)?.cancel();
    await _persistLifecycle(binding, 'desktop_event_loop_frozen');
  }

  Future<void> reconcileAfterRestart() async {
    final files = await stateDirectory
        .list(followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.state'))
        .cast<File>()
        .toList();
    for (final file in files) {
      final content = await file.readAsString();
      if (content.contains('unknown_requires_reconciliation') ||
          content.contains('desktop_event_loop_frozen') ||
          content.contains('heartbeat_failed')) {
        // Retain the state for the control plane to reconcile before retry.
        continue;
      }
      if (content.contains('completed')) {
        await file.delete();
      }
    }
  }

  Future<void> _persistLifecycle(
    P2SupervisedRunBinding binding,
    String state,
  ) async {
    final safe = binding.watchdogId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final file = File(
      '${stateDirectory.path}${Platform.pathSeparator}$safe.state',
    );
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      <String>[
        'schemaVersion=2.0.0',
        'watchdogId=${binding.watchdogId}',
        'sessionId=${binding.sessionId}',
        'pid=${binding.processIdentity.pid}',
        'startToken=${binding.processIdentity.startToken}',
        'supervisorToken=${binding.processIdentity.supervisorToken}',
        'platformGroupId=${binding.processIdentity.platformGroupId}',
        'state=$state',
        'updatedAt=${DateTime.now().toUtc().toIso8601String()}',
      ].join('\n'),
      flush: true,
    );
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final timer in _heartbeats.values) {
      timer.cancel();
    }
    _heartbeats.clear();
    for (final binding in _supervised.values) {
      await _persistLifecycle(binding, 'unknown_requires_reconciliation');
    }
    _supervised.clear();
    authorizationRegistry.clear();
    await composition.close();
  }
}
