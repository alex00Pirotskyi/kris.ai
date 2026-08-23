import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'p1_authority_service_contract_v1.dart';
import 'p2_automation_host_process_client.dart';
import 'p2_effect_journal.dart';
import 'p2_managed_authorization_registry.dart';
import 'p2_owner_workspace.dart';
import 'p2_owner_risk_authority.dart';
import 'p2_p1_authority_adapter.dart';
import 'p2_product_binding_context.dart';
import 'p2_product_runtime_integration.dart';
import 'p2_runtime_resource_resolver.dart';
import 'p2_terminal_model.dart';
import 'p8_effect_journal_adapter.dart';

final class P2ProductRuntimeOwnerModeHandle {
  P2ProductRuntimeOwnerModeHandle._({
    required this.runtime,
    required this.failureCode,
  });
  final P2ProductRuntimeOwnerMode? runtime;
  final String? failureCode;
  bool get available => runtime != null;
  bool get completionEligible =>
      runtime?.authority.completionEligible == true &&
      runtime?.authority.authorityKind == 'p1-isolated-authority-service-v2';

  String get diagnosticCode =>
      _normalizedFailureCode(failureCode ?? 'owner_runtime_start_failed');

  String get recoveryMessage {
    if (diagnosticCode == 'merged_p1a_service_unavailable') {
      return 'The Kristin Authority Service is unavailable. Please install or start it, then restart Kristin. Owner Mode stayed locked and no host authority was granted.';
    }
    if (diagnosticCode == 'product_runtime_p2_not_initialized') {
      return 'Owner Mode has not finished starting. Restart Kristin and open Owner Mode again. No host authority was granted.';
    }
    return 'Kristin could not start Owner Mode safely. Review the diagnostic code, repair the local runtime, and restart Kristin. No host authority was granted.';
  }

  Widget buildWorkspace({Key? key}) {
    final active = runtime;
    if (active != null) {
      return active.buildWorkspace(key: key);
    }
    return Scaffold(
      key: key,
      appBar: AppBar(title: const Text('Owner Mode')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.security_outlined, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Owner Mode is unavailable',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  recoveryMessage,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SelectableText('Diagnostic: $diagnosticCode'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void activateEffectContext({required String runId, required String taskId}) {
    final active = runtime;
    if (active == null) {
      throw StateError('owner_mode_runtime_unavailable');
    }
    active.activateEffectContext(runId: runId, taskId: taskId);
  }

  void clearEffectContext({required String runId, required String taskId}) {
    final active = runtime;
    if (active == null) {
      throw StateError('owner_mode_runtime_unavailable');
    }
    active.clearEffectContext(runId: runId, taskId: taskId);
  }

  Map<String, Object?> get runtimeProvenance =>
      runtime?.runtimeProvenance ??
      <String, Object?>{
        'entryPoint': 'ProductRuntime.initialize',
        'available': false,
        'failureCode': failureCode,
        'completionEligible': false,
      };
  Future<void> close() async => runtime?.close();
  static P2ProductRuntimeOwnerModeHandle active(
    P2ProductRuntimeOwnerMode runtime,
  ) =>
      P2ProductRuntimeOwnerModeHandle._(runtime: runtime, failureCode: null);
  static P2ProductRuntimeOwnerModeHandle blocked(String code) =>
      P2ProductRuntimeOwnerModeHandle._(
        runtime: null,
        failureCode: _normalizedFailureCode(code),
      );

  static String _normalizedFailureCode(String code) {
    final normalized = code
        .trim()
        .replaceFirst(
          RegExp(r'^Bad[ _]state[:_ ]+', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'[^A-Za-z0-9_.:-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return normalized.isEmpty ? 'owner_runtime_start_failed' : normalized;
  }
}

/// Starts P2 from application-owned resources and ProductRuntime's merged P1A service handle. It does not read P1 policy/config from the source
/// tree and does not construct a P1 authority, grant registry or ledger.
final class P2ProductRuntimeBootstrap {
  const P2ProductRuntimeBootstrap._();

  static Future<P2ProductRuntimeOwnerModeHandle> start({
    required Directory dataRoot,
    required P1AuthorityServiceHandleV1? p1AuthorityService,
    P2RuntimeResourceSet? runtimeResources,
    P2ApplicationOwnedRuntimeResourceResolver? resourceResolver,
    Map<String, String> explicitlyProvisionedEnvironment =
        const <String, String>{},
    bool interactiveDesktopAttested = false,
  }) async {
    try {
      const ownerRiskQa = bool.fromEnvironment(
        'KRISTIN_OWNER_RISK_QA',
        defaultValue: false,
      );
      const qaPreviewBuild = bool.fromEnvironment(
        'KRISTIN_QA_PREVIEW',
        defaultValue: false,
      );
      final qaPreview = ownerRiskQa ||
          (qaPreviewBuild &&
              p1AuthorityService?.service.provenance['qaPreview'] == true);
      if (!ownerRiskQa) {
        if (p1AuthorityService == null) {
          throw StateError('merged_p1a_service_unavailable');
        }
        p1AuthorityService.validateForP2(allowQaPreview: qaPreview);
      }
      final resolver = resourceResolver ??
          P2ApplicationOwnedRuntimeResourceResolver(
            applicationDataRoot: dataRoot,
          );
      final resources = runtimeResources ?? await resolver.resolve();
      final P2RuntimeAuthority authority = ownerRiskQa
          ? P2OwnerRiskQaAuthority()
          : P2IsolatedP1AuthorityAdapter(
              p1AuthorityService!,
              qaPreview: qaPreview,
            );
      final authorityDirectory = Directory(
        '${dataRoot.path}${Platform.pathSeparator}p2-authority',
      );
      await authorityDirectory.create(recursive: true);
      final p2Journal = P2JsonlEffectJournal(
        File(
          '${dataRoot.path}${Platform.pathSeparator}logs${Platform.pathSeparator}p2-effects.jsonl',
        ),
      );
      final journal = P8ReconciledEffectJournal(
        downstream: p2Journal,
        stateFile: File(
          '${dataRoot.path}${Platform.pathSeparator}logs${Platform.pathSeparator}p8-external-effects.jsonl',
        ),
      );
      await journal.initialize();
      final bindings = P2ProductBindingContext();
      final authorizations = P2ManagedAuthorizationRegistry();
      final runtime = await P2ProductRuntimeOwnerMode.start(
        stateDirectory: Directory(
          '${authorityDirectory.path}${Platform.pathSeparator}watchdogs',
        ),
        authority: authority,
        journal: journal,
        launchConfig: P2AutomationHostLaunchConfig(
          nodeExecutable: resources.nodeExecutable,
          hostScript: resources.hostScript,
          workingDirectory: resources.workingDirectory,
          restrictedWorkerLauncher: resources.restrictedWorkerLauncher,
          restrictedWorkerLauncherSha256:
              resources.restrictedWorkerLauncherSha256,
          workerPolicy: resources.workerPolicy,
          workerPolicySha256: resources.workerPolicySha256,
          nodeExecutableSha256: resources.nodeExecutableSha256,
          hostScriptSha256: resources.hostScriptSha256,
          bootstrapProvider: authority,
          windowsJobHelper: resources.windowsJobHelper,
          posixWatchdog: resources.posixWatchdog,
          interactiveDesktopAdapter: resources.interactiveDesktopAdapter,
          interactiveDesktopAttested: interactiveDesktopAttested,
          additionalEnvironment: <String, String>{
            ..._validatedProvisionedEnvironment(
              explicitlyProvisionedEnvironment,
            ),
            if (ownerRiskQa) 'KRISTIN_OWNER_RISK_QA': '1',
          },
        ),
        hostBindingProvider: bindings,
        processAuthorizationFor: authorizations.processForPid,
        watchdogAuthorizationFor: authorizations.watchdogFor,
        terminalAuthorizationFor: (P2TerminalTab tab, String operation) {
          final binding = P2P1OperationRegistry.binding(
            runId: tab.runId,
            taskId: tab.taskId,
            accessProfileId: 'owner',
            operation: operation,
          );
          return P2TerminalAuthorization(
            binding: binding,
            grantDigest: tab.grantId,
          );
        },
        selectionBytes: (_) async => const <int>[],
        transcriptBytes: (_) async => const <int>[],
        writeClipboardText: (String text) async =>
            Clipboard.setData(ClipboardData(text: text)),
        writeTranscriptFile: (P2TerminalTab tab, List<int> bytes) async {
          final file = File(
            '${dataRoot.path}${Platform.pathSeparator}exports${Platform.pathSeparator}terminal-${tab.id}.log',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes, flush: true);
        },
        persistOwnerSettings: (value) async {
          final file = File(
            '${authorityDirectory.path}${Platform.pathSeparator}owner-mode.v1.json',
          );
          await file.writeAsString('${jsonEncode(value)}\n', flush: true);
        },
        clearOwnerSettings: () async {
          final file = File(
            '${authorityDirectory.path}${Platform.pathSeparator}owner-mode.v1.json',
          );
          if (await file.exists()) {
            await file.delete();
          }
        },
        emergencyWatchdogId: 'product-emergency-watchdog',
        bindingContext: bindings,
        authorizationRegistry: authorizations,
      );
      return P2ProductRuntimeOwnerModeHandle.active(runtime);
    } catch (error) {
      return P2ProductRuntimeOwnerModeHandle.blocked(_safeFailureCode(error));
    }
  }

  static Map<String, String> _validatedProvisionedEnvironment(
    Map<String, String> input,
  ) {
    final allowed = <String>{
      'KRISTIN_P2_NATIVE_SERVICE_ID',
      'KRISTIN_P2_NATIVE_SERVICE_PROVIDER',
      'KRISTIN_P2_NATIVE_SERVICE_ATTESTATION',
      'KRISTIN_P2_NATIVE_SERVICE_ATTESTATION_SHA256',
      'KRISTIN_P2_RUNNER_ATTESTATION_RECEIPT',
      'KRISTIN_P2_RUNNER_ATTESTATION_SHA256',
      'KRISTIN_P2_RUNNER_POLICY',
      'KRISTIN_P2_RUNNER_POLICY_SHA256',
      'KRISTIN_P2_COMMIT_SHA',
      'KRISTIN_P2_SOURCE_PACKAGE_SHA256',
      'KRISTIN_P2_E2E_ROOT',
      'KRISTIN_P2_RUNNER_ID',
      'KRISTIN_P2_RUNNER_GROUP',
      'KRISTIN_P2_RUNNER_CONFIGURATION_SHA256',
      'KRISTIN_P1A_MERGED_MANIFEST',
      'KRISTIN_P1A_MERGED_MANIFEST_SHA256',
      'KRISTIN_P1A_PLATFORM_RECEIPT',
      'KRISTIN_P1A_PLATFORM_RECEIPT_SHA256',
      'KRISTIN_P1A_EVIDENCE_TRUST',
      'KRISTIN_P1A_EVIDENCE_TRUST_SHA256',
      'KRISTIN_P1A_SERVICE_BEHAVIOR_RECEIPT_SHA256',
      'KRISTIN_P1A_WORKER_DENIAL_RECEIPT_SHA256',
      'KRISTIN_P1A_WORKER_LAUNCHER_SHA256',
      'KRISTIN_P1A_WORKER_EXECUTABLE_SHA256',
      'KRISTIN_P1A_WORKER_IDENTITY_SHA256',
      'KRISTIN_P1A_DENIAL_TRANSCRIPT_SHA256',
      'KRISTIN_P2_NPM_EXECUTABLE',
      'KRISTIN_P2_CONTROLLED_PACKAGE_MANAGER',
      'KRISTIN_P2_CONTROLLED_PACKAGE_NAME',
      'KRISTIN_P2_CONTROLLED_PACKAGE_SOURCE',
      'KRISTIN_P2_CONTROLLED_PACKAGE_PREFIX',
      'KRISTIN_P2_TOOLCHAIN_EXTENSION_FINGERPRINT',
      'KRISTIN_P2_NATIVE_RUNTIME_MANIFEST',
      'KRISTIN_P2_NATIVE_RUNTIME_MANIFEST_SHA256',
      'GITHUB_REPOSITORY',
      'GITHUB_WORKFLOW',
      'GITHUB_WORKFLOW_REF',
      'GITHUB_RUN_ID',
      'GITHUB_RUN_ATTEMPT',
      'GITHUB_JOB',
      'RUNNER_NAME',
      'KRISTIN_OWNER_RISK_QA',
    };
    final result = <String, String>{};
    for (final entry in input.entries) {
      if (!allowed.contains(entry.key) ||
          entry.key.contains('=') ||
          entry.value.contains('\u0000')) {
        throw StateError('unapproved_runtime_environment:${entry.key}');
      }
      if (RegExp(
        r'(secret|token|password|credential|api.?key|private.?key)',
        caseSensitive: false,
      ).hasMatch(entry.key)) {
        throw StateError('secret_runtime_environment_forbidden');
      }
      result[entry.key] = entry.value;
    }
    return Map<String, String>.unmodifiable(result);
  }

  static String _safeFailureCode(Object error) {
    if (error is StateError &&
        error.message == 'merged_p1a_service_unavailable') {
      return 'merged_p1a_service_unavailable';
    }
    final value = '$error';
    if (RegExp(
      r'(secret|token|password|credential|api.?key|private.?key|bearer)',
      caseSensitive: false,
    ).hasMatch(value)) {
      return 'owner_runtime_start_failed_redacted';
    }
    final sanitized = value
        .replaceAll(RegExp(r'[^A-Za-z0-9_.:-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return sanitized.length <= 160 ? sanitized : sanitized.substring(0, 160);
  }
}
