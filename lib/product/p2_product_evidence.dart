import 'dart:convert';
import 'dart:io';

/// Machine-readable proof emitted only by an executed path that begins at the
/// shipped ProductRuntime and crosses the real P1 control-plane authority.
/// Fixture authorities, helper-only smoke tests, source markers, and labels are
/// structurally ineligible for a passing completion record.
final class P2ProductAssertionEvidence {
  P2ProductAssertionEvidence({
    required this.taskId,
    required this.assertionId,
    required this.platform,
    required this.commitSha,
    required this.entryPoint,
    required this.applicationComposition,
    required this.applicationCompositionSha256,
    required this.authorizationBoundary,
    required this.authority,
    required this.productionAdapter,
    required this.runnerAttestationSha256,
    required this.toolchainExtensionFingerprint,
    required this.nativeRuntimeManifestSha256,
    required this.osEffect,
    required this.postcondition,
    required this.receipt,
    required this.status,
    required this.sourceOnly,
    required this.fixtureAuthority,
    required this.completionEligible,
    required this.startedAt,
    required this.completedAt,
  });

  final String taskId;
  final String assertionId;
  final String platform;
  final String commitSha;
  final String entryPoint;
  final String applicationComposition;
  final String applicationCompositionSha256;
  final String authorizationBoundary;
  final Map<String, Object?> authority;
  final String productionAdapter;
  final String runnerAttestationSha256;
  final String toolchainExtensionFingerprint;
  final String nativeRuntimeManifestSha256;
  final Map<String, Object?> osEffect;
  final Map<String, Object?> postcondition;
  final Map<String, Object?> receipt;
  final String status;
  final bool sourceOnly;
  final bool fixtureAuthority;
  final bool completionEligible;
  final DateTime startedAt;
  final DateTime completedAt;

  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

  void validate() {
    if (!RegExp(r'^P2-\d{3}$').hasMatch(taskId) ||
        assertionId != 'p2-${taskId.substring(3)}.product-runtime-e2e' ||
        !const <String>{'windows', 'macos', 'linux'}.contains(platform) ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(commitSha) ||
        authorizationBoundary !=
            'p1-isolated-authority-service-effect-permit-v2') {
      throw const FormatException('p2_product_evidence_identity_invalid');
    }
    if (!const <String>{
      'passed',
      'failed',
      'blocked',
      'unsupported',
      'not_tested',
      'source_only',
    }.contains(status)) {
      throw const FormatException('p2_product_evidence_status_invalid');
    }
    if (status == 'passed') {
      final approval = authority['approval'];
      final protectedKeys = authority['protectedKeys'];
      final p1aEvidence = authority['p1aEvidence'];
      if (sourceOnly ||
          fixtureAuthority ||
          !completionEligible ||
          entryPoint != 'ProductRuntime.initialize' ||
          applicationComposition != 'ProductRuntime.p2OwnerMode' ||
          !_sha256.hasMatch(applicationCompositionSha256) ||
          authority['authorityImplementation'] !=
              'P1IsolatedAuthorityServiceV2' ||
          authority['authorityKind'] != 'p1-isolated-authority-service-v2' ||
          authority['completionEligible'] != true ||
          !_sha256.hasMatch('${authority['policyDecisionSha256'] ?? ''}') ||
          !_sha256.hasMatch('${authority['capabilityGrantSha256'] ?? ''}') ||
          !_sha256.hasMatch('${authority['authenticatedIpcSha256'] ?? ''}') ||
          !_sha256.hasMatch('${authority['effectPermitSha256'] ?? ''}') ||
          !_sha256.hasMatch('${authority['auditCheckpointSha256'] ?? ''}') ||
          !_sha256.hasMatch('${authority['serviceBuildSha256'] ?? ''}') ||
          !_sha256.hasMatch(
            '${authority['serviceEndpointAttestationSha256'] ?? ''}',
          ) ||
          !_sha256.hasMatch('${authority['p1aPlatformReceiptSha256'] ?? ''}') ||
          !_sha256.hasMatch('${authority['p1aEvidenceTrustSha256'] ?? ''}') ||
          !_sha256.hasMatch(
            '${authority['p1aServiceBehaviorReceiptSha256'] ?? ''}',
          ) ||
          !_sha256.hasMatch(
            '${authority['workerDenialReceiptSha256'] ?? ''}',
          ) ||
          !_sha256.hasMatch('${authority['p1aWorkerLauncherSha256'] ?? ''}') ||
          !_sha256.hasMatch(
            '${authority['p1aWorkerExecutableSha256'] ?? ''}',
          ) ||
          !_sha256.hasMatch('${authority['p1aWorkerIdentitySha256'] ?? ''}') ||
          !_sha256.hasMatch(
            '${authority['p1aDenialTranscriptSha256'] ?? ''}',
          ) ||
          !_sha256.hasMatch('${authority['p1aPackageSha256'] ?? ''}') ||
          !_sha256.hasMatch(
            '${authority['p1AmendmentManifestSha256'] ?? ''}',
          ) ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(
            '${authority['effectPermitSignerPublicKeySpkiSha256'] ?? ''}',
          ) ||
          '${authority['policyDecisionId'] ?? ''}'.isEmpty ||
          '${authority['capabilityGrantId'] ?? ''}'.isEmpty ||
          '${authority['authenticatedIpcChannelId'] ?? ''}'.isEmpty ||
          '${authority['authenticatedIpcRequestId'] ?? ''}'.isEmpty ||
          '${authority['auditCheckpointId'] ?? ''}'.isEmpty ||
          '${authority['serviceInstanceId'] ?? ''}'.isEmpty ||
          authority['p1aService'] != true ||
          authority['p2AdapterDelegationOnly'] != true ||
          authority['p2CanIssueGrants'] != false ||
          authority['workerPublicVerifierOnly'] != true ||
          authority['workerCanForgeAuthority'] != false ||
          authority['workerCanReachAuthoritySigner'] != false ||
          authority['workerDeniedByOs'] != true ||
          authority['osEnforcedIsolation'] != true ||
          authority['workerPrincipalSeparated'] != true ||
          authority['typedOperationsOnly'] != true ||
          authority['nonExportableKeys'] != true ||
          authority['durableConsumptionStateVersion'] is! int ||
          authority['durableConsumptionUseNumber'] is! int ||
          authority['revocationEpoch'] is! int ||
          authority['workerReceivesSymmetricAuthorityKeys'] != false ||
          authority['workerReceivesPrivateSigningMaterial'] != false ||
          p1aEvidence is! Map ||
          p1aEvidence['p1AmendmentMerged'] != true ||
          p1aEvidence['independentP1aSecurityReviewApproved'] != true ||
          p1aEvidence['workerDenialTriPlatformPassed'] != true ||
          !_sha256.hasMatch(
            '${p1aEvidence['aggregateManifestSha256'] ?? ''}',
          ) ||
          !_sha256.hasMatch('${p1aEvidence['platformReceiptSha256'] ?? ''}') ||
          !_sha256.hasMatch('${p1aEvidence['evidenceTrustSha256'] ?? ''}') ||
          !_sha256.hasMatch(
            '${p1aEvidence['serviceBehaviorReceiptSha256'] ?? ''}',
          ) ||
          !_sha256.hasMatch(
            '${p1aEvidence['workerDenialReceiptSha256'] ?? ''}',
          ) ||
          !_sha256.hasMatch('${p1aEvidence['workerLauncherSha256'] ?? ''}') ||
          !_sha256.hasMatch('${p1aEvidence['workerExecutableSha256'] ?? ''}') ||
          !_sha256.hasMatch('${p1aEvidence['workerIdentitySha256'] ?? ''}') ||
          !_sha256.hasMatch('${p1aEvidence['denialTranscriptSha256'] ?? ''}') ||
          !_sha256.hasMatch('${p1aEvidence['p1aPackageSha256'] ?? ''}') ||
          p1aEvidence['privateAuthorityMaterialPresent'] != false ||
          p1aEvidence['arbitraryMessageSigningApi'] != false ||
          approval is! Map ||
          approval['completionEligible'] != true ||
          protectedKeys is! Map ||
          protectedKeys['kind'] != 'non-exportable-service-owned-keys' ||
          protectedKeys['completionEligible'] != true ||
          !_sha256.hasMatch(runnerAttestationSha256) ||
          !_sha256.hasMatch(toolchainExtensionFingerprint) ||
          !_sha256.hasMatch(nativeRuntimeManifestSha256) ||
          productionAdapter.isEmpty ||
          osEffect.isEmpty ||
          postcondition['observed'] != true ||
          receipt['completionEligible'] != true ||
          receipt['fixtureAuthority'] != false ||
          receipt['targetHostOperation'] != true ||
          '${receipt['status'] ?? ''}'.isEmpty) {
        throw const FormatException('p2_product_evidence_pass_invalid');
      }
      final specialized = <String, bool>{
        'P2-001':
            osEffect['kind'] == 'owner_mode_settings_enable_disable_reset' &&
                postcondition['explicitAcknowledgementRequired'] == true &&
                postcondition['fullCurrentAccountLabelObserved'] == true &&
                postcondition['notSandboxLabelObserved'] == true &&
                postcondition['persistentIndicatorObserved'] == true &&
                postcondition['disableResetObserved'] == true &&
                postcondition['settingsPersistedAfterReenable'] == true,
        'P2-005': osEffect['kind'] == 'interactive_pty_detach_reconnect' &&
            postcondition['consumerDetached'] == true &&
            postcondition['outputWhileDetached'] == true &&
            postcondition['backlogReplayExact'] == true &&
            postcondition['noDuplicationOrLoss'] == true,
        'P2-006': osEffect['kind'] == 'managed_process_tree_kill' &&
            postcondition['descendantProcessCreated'] == true &&
            postcondition['identityVerified'] == true &&
            postcondition['activeProcesses'] == 0 &&
            postcondition['zeroSurvivingDescendants'] == true,
        'P2-007':
            osEffect['kind'] == 'controlled_target_host_package_lifecycle' &&
                postcondition['controlledTargetHost'] == true &&
                postcondition['dryRunObserved'] == true &&
                postcondition['installObserved'] == true &&
                postcondition['installedStateObserved'] == true &&
                postcondition['removeObserved'] == true &&
                postcondition['removedStateObserved'] == true &&
                postcondition['executableVersionProvenanceObserved'] == true,
        'P2-008': osEffect['kind'] ==
                'controlled_user_service_and_application_lifecycle' &&
            postcondition['startObserved'] == true &&
            postcondition['runningObserved'] == true &&
            postcondition['stopObserved'] == true &&
            postcondition['stoppedObserved'] == true &&
            postcondition['applicationOpenObserved'] == true &&
            postcondition['applicationCloseObserved'] == true &&
            postcondition['elevationExercised'] == false,
        'P2-009':
            osEffect['kind'] == 'interactive_clipboard_screen_active_window' &&
                postcondition['clipboardRoundTrip'] == true &&
                postcondition['screenCaptured'] == true &&
                postcondition['activeWindowObserved'] == true &&
                postcondition['ordinaryLogContentAbsent'] == true,
        'P2-010': osEffect['kind'] == 'product_snapshot_restore' &&
            postcondition['restoredContent'] == true,
        'P2-011': osEffect['kind'] ==
                'product_runtime_external_watchdog_kill_during_ui_freeze' &&
            postcondition['watchdogAutomaticallyArmed'] == true &&
            postcondition['heartbeatObserved'] == true &&
            postcondition['desktopHeartbeatFrozen'] == true &&
            postcondition['externalKillObserved'] == true &&
            postcondition['identityVerified'] == true &&
            postcondition['activeProcesses'] == 0 &&
            postcondition['zeroSurvivingDescendants'] == true,
        'P2-012':
            osEffect['kind'] == 'shipped_terminal_workspace_managed_session' &&
                postcondition['tabCreatedFromManagedPty'] == true &&
                postcondition['shellAndCwdObserved'] == true &&
                postcondition['runTaskGrantIdentityObserved'] == true &&
                postcondition['searchObserved'] == true &&
                postcondition['accessibilityLabelObserved'] == true &&
                postcondition['keyboardEmergencyActionExposed'] == true &&
                postcondition['interruptObserved'] == true &&
                postcondition['terminateTreeObserved'] == true,
        'P2-013': osEffect['kind'] ==
                'production_authority_restart_replay_reconciliation' &&
            postcondition['firstDispatchSucceeded'] == true &&
            postcondition['durableConsumptionRecorded'] == true &&
            postcondition['durableStateVersionRecorded'] == true &&
            postcondition['productRuntimeRestarted'] == true &&
            postcondition['replayRejectedAfterRestart'] == true &&
            postcondition['reconciliationObserved'] == true,
      };
      if (specialized.containsKey(taskId) && specialized[taskId] != true) {
        throw const FormatException(
          'p2_product_evidence_specialized_postcondition_invalid',
        );
      }
    }
    if (completedAt.toUtc().isBefore(startedAt.toUtc())) {
      throw const FormatException('p2_product_evidence_time_invalid');
    }
  }

  Map<String, Object?> toJson() {
    validate();
    return <String, Object?>{
      'schemaVersion': '2.0.0',
      'resultType': 'p2-shipped-product-observation-v2',
      'taskId': taskId,
      'assertionId': assertionId,
      'platform': platform,
      'commitSha': commitSha,
      'entryPoint': entryPoint,
      'applicationComposition': applicationComposition,
      'applicationCompositionSha256': applicationCompositionSha256,
      'authorizationBoundary': authorizationBoundary,
      'authority': authority,
      'productionAdapter': productionAdapter,
      'runnerAttestationSha256': runnerAttestationSha256,
      'toolchainExtensionFingerprint': toolchainExtensionFingerprint,
      'nativeRuntimeManifestSha256': nativeRuntimeManifestSha256,
      'osEffect': osEffect,
      'postcondition': postcondition,
      'receipt': receipt,
      'status': status,
      'sourceOnly': sourceOnly,
      'fixtureAuthority': fixtureAuthority,
      'completionEligible': completionEligible,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'completedAt': completedAt.toUtc().toIso8601String(),
    };
  }

  Future<void> write(File target) async {
    validate();
    await target.parent.create(recursive: true);
    await target.writeAsString('${jsonEncode(toJson())}\n', flush: true);
  }
}
