import 'dart:convert';
import 'dart:math';

import 'crypto_utils.dart';
import 'p1_authority_service_contract_v1.dart';
import 'p2_automation_host.dart';
import 'p2_automation_host_process_client.dart';
import 'p2_effect_boundary.dart';

abstract interface class P2RuntimeAuthority
    implements
        P2AutomationEnvelopeAuthority,
        P2ProtectedAutomationBootstrapProvider,
        P2RestrictedWorkerIdentitySink,
        P2CompletionEligibleAuthority {
  bool get qaPreview;
  Map<String, Object?>? lastAuthorityObservation(String taskId);
}

abstract interface class P2CompletionEligibleAuthority {
  String get authorityImplementation;
  String get authorityKind;
  bool get completionEligible;
  Map<String, Object?> get authorityProvenance;
}

/// Delegation-only adapter to the separately governed and already merged P1A
/// authority service. P2 owns no policy engine, approval authority, grant
/// issuer, use ledger, revocation state, audit signer, protected-key handle,
/// private key, or arbitrary signing process.
final class P2IsolatedP1AuthorityAdapter implements P2RuntimeAuthority {
  P2IsolatedP1AuthorityAdapter(
    P1AuthorityServiceHandleV1 handle, {
    bool qaPreview = false,
  }) : _handle = handle,
       _qaPreview = qaPreview {
    handle.validateForP2(allowQaPreview: qaPreview);
  }

  final P1AuthorityServiceHandleV1 _handle;
  final bool _qaPreview;
  @override
  bool get qaPreview => _qaPreview;
  bool get _executionEligible => completionEligible || _qaPreview;
  final Random _random = Random.secure();
  final Map<String, Map<String, Object?>> _observations =
      <String, Map<String, Object?>>{};
  String? _workerSessionId;
  String? _channelId;
  int? _expectedRevocationEpoch;
  String? _permitVerifierPublicKeySpkiSha256;
  Map<String, Object?>? _restrictedWorkerIdentity;

  P1AuthorityServiceClientV1 get service => _handle.service;

  @override
  String get authorityImplementation => 'P1IsolatedAuthorityServiceV2';
  @override
  String get authorityKind => 'p1-isolated-authority-service-v2';
  @override
  bool get completionEligible => service.completionEligible;
  @override
  Map<String, Object?> get authorityProvenance => <String, Object?>{
    ...service.provenance,
    'adapter': 'P2IsolatedP1AuthorityAdapter',
    'authorityKind': authorityKind,
    'endpoint': service.endpoint.toJson(),
    'delegatesToMergedP1aService': true,
    'p2PolicyEngine': false,
    'p2GrantIssuer': false,
    'p2UseLedger': false,
    'p2RevocationStore': false,
    'p2AuditSigner': false,
    'p2ProtectedKeyBroker': false,
    'workerCanReachAuthoritySigner': false,
    'workerReceivesSymmetricAuthorityKeys': false,
    'workerReceivesPrivateSigningMaterial': false,
    'restrictedWorkerIdentityBound': _restrictedWorkerIdentity != null,
    'completionEligible': completionEligible,
    'qaPreview': _qaPreview,
    'qaPreviewFormalCompletion': false,
  };

  @override
  Map<String, Object?>? lastAuthorityObservation(String taskId) =>
      _observations[taskId];

  String _id(String prefix) {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    final body = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$prefix-$body';
  }

  @override
  void bindRestrictedWorkerIdentity(Map<String, Object?> identity) {
    final required = <String>[
      'schemaVersion',
      'platform',
      'principalType',
      'sessionId',
      'pid',
      'startToken',
      'launcherSha256',
      'nodeSha256',
      'hostScriptSha256',
      'identitySha256',
    ];
    if (required.any((key) => identity[key] == null) ||
        identity['schemaVersion'] != '2.0.0' ||
        identity['sessionId'] != _workerSessionId ||
        identity['authorityConnectionDenied'] != true ||
        identity['authorityDenialCode'] != 'worker_principal_denied') {
      throw StateError('p1a_restricted_worker_identity_invalid');
    }
    _restrictedWorkerIdentity = Map<String, Object?>.unmodifiable(
      Map<String, Object?>.from(identity),
    );
  }

  @override
  Future<Map<String, Object?>> take() async {
    if (!_executionEligible) throw StateError('merged_p1a_service_ineligible');
    final bootstrap = await service.workerVerifierBootstrap();
    final permitVerifier = bootstrap['permitVerifier'];
    final authorityState = bootstrap['authorityState'];
    final workerSessionId = bootstrap['workerSessionId']?.toString() ?? '';
    final channelId = bootstrap['channelId']?.toString() ?? '';
    if (bootstrap['schemaVersion'] != '4.0.0' ||
        bootstrap['verificationMode'] != 'ecdsa-p256-public-only' ||
        bootstrap['workerCanIssue'] != false ||
        bootstrap['privateSigningMaterialPresent'] != false ||
        bootstrap['symmetricSigningMaterialPresent'] != false ||
        bootstrap['rawAuthoritySecretsReturned'] != false ||
        permitVerifier is! Map ||
        permitVerifier['algorithm'] != 'ecdsa-p256-sha256' ||
        (permitVerifier['publicKeySpkiBase64']?.toString().length ?? 0) < 80 ||
        authorityState is! Map ||
        authorityState['revocationEpoch'] is! int ||
        workerSessionId.length < 16 ||
        channelId.length < 16 ||
        _containsForbiddenAuthorityMaterial(bootstrap)) {
      throw StateError('p1a_worker_bootstrap_invalid');
    }
    _workerSessionId = workerSessionId;
    _channelId = channelId;
    _expectedRevocationEpoch = authorityState['revocationEpoch']! as int;
    _permitVerifierPublicKeySpkiSha256 = Sha256.hex(
      base64Decode(permitVerifier['publicKeySpkiBase64']!.toString()),
    );
    _restrictedWorkerIdentity = null;
    return Map<String, Object?>.unmodifiable(bootstrap);
  }

  @override
  Future<P2AutomationEnvelope> issue({
    required P2EffectBinding binding,
    required String operation,
    required Map<String, Object?> payload,
    String? expectedGrantDigest,
    Duration deadline = const Duration(seconds: 30),
  }) async {
    if (!_executionEligible) throw StateError('merged_p1a_service_ineligible');
    final workerSessionId = _workerSessionId;
    final channelId = _channelId;
    final expectedRevocationEpoch = _expectedRevocationEpoch;
    final workerIdentity = _restrictedWorkerIdentity;
    if (workerSessionId == null ||
        channelId == null ||
        expectedRevocationEpoch == null ||
        workerIdentity == null) {
      throw StateError('p1a_worker_identity_not_bound');
    }
    if (binding.operation != operation ||
        !const <String>{
          'owner',
          'owner_unattended',
        }.contains(binding.accessProfileId)) {
      throw StateError('p1a_effect_binding_invalid');
    }
    final exactPayload = <String, Object?>{'operation': operation, ...payload};
    final ownerApprovalId = exactPayload['ownerApprovalId']?.toString() ?? '';
    if (ownerApprovalId.isEmpty) {
      throw StateError('p1a_explicit_owner_approval_required');
    }
    final requestId = _id('p2-request');
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(deadline);
    final descriptor = P2P1OperationRegistry.descriptor(operation);
    final target = _effectTarget(exactPayload, operation);
    final request = P1AuthorityEffectRequestV1(
      requestId: requestId,
      requestNonce: _id('p2-nonce'),
      runId: binding.runId,
      taskId: binding.taskId,
      actorId: binding.actorId,
      toolId: binding.toolId,
      accessProfileId: binding.accessProfileId,
      capabilityId: binding.capabilityId,
      operation: operation,
      payload: exactPayload,
      payloadSha256: Sha256.text(p1aCanonicalJson(exactPayload)),
      ownerApprovalId: ownerApprovalId,
      workerSessionId: workerSessionId,
      channelId: channelId,
      workerIdentity: workerIdentity,
      policyEffect: <String, Object?>{
        'domain': descriptor.domain,
        'action': descriptor.action,
        'target': target,
        'p2Operation': operation,
      },
      requestedBudgets: _requestedBudgets(exactPayload, deadline),
      expectedRevocationEpoch: expectedRevocationEpoch,
      deadline: expiresAt,
    );
    request.validate(now);
    final permit = await service.authorizeEffect(request);
    final envelope = P2AutomationEnvelope.fromJson(permit.envelope);
    envelope.validate();
    if (envelope.requestId != requestId ||
        envelope.operation != operation ||
        envelope.binding.runId != binding.runId ||
        envelope.binding.taskId != binding.taskId ||
        envelope.binding.actorId != binding.actorId ||
        envelope.binding.toolId != binding.toolId ||
        envelope.binding.accessProfileId != binding.accessProfileId ||
        envelope.binding.capabilityId != binding.capabilityId ||
        envelope.effectPermit.workerIdentitySha256 !=
            workerIdentity['identitySha256'] ||
        p1aCanonicalJson(envelope.payload) != p1aCanonicalJson(exactPayload) ||
        (expectedGrantDigest != null &&
            envelope.grantProof.grantDigest != expectedGrantDigest)) {
      throw StateError('p1a_effect_envelope_binding_mismatch');
    }
    final observation = <String, Object?>{
      ...permit.authorityObservation,
      'authorityImplementation':
          service.provenance['implementation'] ?? 'P1AuthorityServiceClientV2',
      'authorityKind': authorityKind,
      'completionEligible': completionEligible,
      'serviceInstanceId': service.endpoint.serviceInstanceId,
      'serviceBuildSha256': service.endpoint.serviceBuildSha256,
      'osEnforcedIsolation': service.endpoint.osEnforcedIsolation,
      'workerPrincipalSeparated': service.endpoint.workerPrincipalSeparated,
      'typedOperationsOnly': service.endpoint.typedOperationsOnly,
      'nonExportableKeys': service.endpoint.nonExportableKeys,
      'policyDecisionId': envelope.grantProof.policyDecisionId,
      'policyDecisionSha256': envelope.grantProof.policyDecisionDigest,
      'capabilityGrantId': envelope.grantProof.grantId,
      'capabilityGrantSha256': envelope.grantProof.grantDigest,
      'authenticatedIpcChannelId':
          envelope.grantProof.authenticatedIpc['channelId'],
      'authenticatedIpcRequestId': envelope.requestId,
      'authenticatedIpcSha256': Sha256.text(
        p1aCanonicalJson(envelope.grantProof.authenticatedIpc),
      ),
      'auditCheckpointId': envelope.grantProof.auditCheckpoint['id'],
      'auditCheckpointSha256': envelope.grantProof.auditCheckpoint['digest'],
      'effectPermitSha256': Sha256.text(
        p1aCanonicalJson(envelope.effectPermit.toJson()),
      ),
      'effectPermitSignerPublicKeySpkiSha256':
          _permitVerifierPublicKeySpkiSha256,
      'durableConsumptionStateVersion':
          envelope.grantProof.consumptionReceipt.stateVersion,
      'durableConsumptionUseNumber': envelope.grantProof.useNumber,
      'revocationEpoch': envelope.grantProof.revocationEpoch,
      'workerIdentity': workerIdentity,
      'workerIdentitySha256': workerIdentity['identitySha256'],
      'p1aService': true,
      'p2AdapterDelegationOnly': true,
      'p2CanIssueGrants': false,
      'workerPublicVerifierOnly': true,
      'workerCanForgeAuthority': false,
      'workerDeniedByOs': true,
      'workerCanReachAuthoritySigner': false,
      'workerReceivesSymmetricAuthorityKeys': false,
      'workerReceivesPrivateSigningMaterial': false,
      'serviceEndpointAttestationSha256':
          service.provenance['platformReceiptSha256'],
      'p1aPlatformReceiptSha256': service.provenance['platformReceiptSha256'],
      'p1aEvidenceTrustSha256': service.provenance['evidenceTrustSha256'],
      'p1aServiceBehaviorReceiptSha256':
          service.provenance['serviceBehaviorReceiptSha256'],
      'workerDenialReceiptSha256':
          service.provenance['workerDenialReceiptSha256'],
      'p1aWorkerLauncherSha256': service.provenance['workerLauncherSha256'],
      'p1aWorkerExecutableSha256': service.provenance['workerExecutableSha256'],
      'p1aWorkerIdentitySha256': service.provenance['workerIdentitySha256'],
      'p1aDenialTranscriptSha256': service.provenance['denialTranscriptSha256'],
      'p1aPackageSha256': service.provenance['p1aPackageSha256'],
      'p1AmendmentManifestSha256':
          service.provenance['aggregateManifestSha256'],
      'authorityBuildIdentity': <String, Object?>{
        'implementationSha256': service.endpoint.serviceBuildSha256,
        'runtimeBuildSha256':
            service.provenance['runtimeBuildSha256'] ??
            service.endpoint.serviceBuildSha256,
        'runtimeResourceManifestSha256':
            service.provenance['runtimeResourceManifestSha256'] ??
            service.endpoint.serviceBuildSha256,
      },
      'p1aEvidence': service.provenance,
    };
    _observations[binding.taskId] = Map<String, Object?>.unmodifiable(
      observation,
    );
    return envelope;
  }

  Map<String, Object?> _requestedBudgets(
    Map<String, Object?> payload,
    Duration deadline,
  ) {
    final raw = payload['requestedBudgets'];
    if (raw is Map) return Map<String, Object?>.from(raw);
    return <String, Object?>{
      'wallClockMs': deadline.inMilliseconds,
      'maxOutputBytes': 8 * 1024 * 1024,
      'maxNetworkBytes': 0,
      'maxCostMicros': 0,
      'maxMutations': 20,
    };
  }

  String _effectTarget(Map<String, Object?> payload, String operation) {
    for (final key in <String>[
      'path',
      'target',
      'destination',
      'executable',
      'serviceId',
      'applicationId',
      'packageName',
      'sessionId',
    ]) {
      final value = payload[key]?.toString() ?? '';
      if (value.isNotEmpty) return value;
    }
    return operation;
  }

  bool _containsForbiddenAuthorityMaterial(Object? value) {
    final forbidden = RegExp(
      r'(privateKey|seed|hmacKey|signingKey|ipcKeyHex|grantKeyring|consumptionKeyring|protectedKeyHandle|brokerExecutable)',
      caseSensitive: false,
    );
    if (value is Map) {
      for (final entry in value.entries) {
        if (forbidden.hasMatch(entry.key.toString()) ||
            _containsForbiddenAuthorityMaterial(entry.value)) {
          return true;
        }
      }
    } else if (value is Iterable) {
      for (final item in value) {
        if (_containsForbiddenAuthorityMaterial(item)) return true;
      }
    }
    return false;
  }
}

final class P2P1OperationDescriptor {
  const P2P1OperationDescriptor({
    required this.capabilityId,
    required this.actorId,
    required this.toolId,
    required this.domain,
    required this.action,
  });
  final String capabilityId;
  final String actorId;
  final String toolId;
  final String domain;
  final String action;
}

/// Compatibility mapping only. It chooses the requested P1 capability/tool
/// identity; the isolated P1A service remains authoritative and may deny it.
final class P2P1OperationRegistry {
  static P2P1OperationDescriptor descriptor(String operation) {
    if (operation.startsWith('filesystem.')) {
      final destructive =
          operation.endsWith('delete') || operation.endsWith('quarantine');
      final read =
          operation.endsWith('read') ||
          operation.endsWith('enumerate') ||
          operation.endsWith('metadata') ||
          operation.endsWith('search');
      return P2P1OperationDescriptor(
        capabilityId: destructive
            ? 'filesystem.delete'
            : read
            ? 'filesystem.read'
            : 'filesystem.write',
        actorId: 'owner_executor',
        toolId: destructive
            ? 'delete_file'
            : read
            ? 'read_file'
            : 'write_file',
        domain: 'filesystem',
        action: destructive
            ? 'delete'
            : read
            ? 'read'
            : 'write',
      );
    }
    if (operation == 'command.run' ||
        operation.startsWith('process.') ||
        operation.startsWith('application.') ||
        operation.startsWith('host.')) {
      return const P2P1OperationDescriptor(
        capabilityId: 'process.execute',
        actorId: 'automation_host',
        toolId: 'run_command',
        domain: 'process',
        action: 'execute',
      );
    }
    if (operation.startsWith('pty.') || operation.startsWith('watchdog.')) {
      return const P2P1OperationDescriptor(
        capabilityId: 'process.interactive',
        actorId: 'automation_host',
        toolId: 'terminal_open',
        domain: 'process',
        action: 'interactive',
      );
    }
    if (operation.startsWith('package.') ||
        operation == 'sdk.discover' ||
        operation.startsWith('service.')) {
      return const P2P1OperationDescriptor(
        capabilityId: 'package.manage',
        actorId: 'owner_executor',
        toolId: 'package_install',
        domain: 'package',
        action: 'manage',
      );
    }
    if (operation.startsWith('clipboard.') || operation.startsWith('screen.')) {
      return const P2P1OperationDescriptor(
        capabilityId: 'process.execute',
        actorId: 'automation_host',
        toolId: 'run_command',
        domain: 'process',
        action: 'execute',
      );
    }
    if (operation.startsWith('snapshot.')) {
      return const P2P1OperationDescriptor(
        capabilityId: 'filesystem.write',
        actorId: 'owner_executor',
        toolId: 'write_file',
        domain: 'filesystem',
        action: 'write',
      );
    }
    throw StateError('p1_operation_not_registered');
  }

  static P2EffectBinding binding({
    required String runId,
    required String taskId,
    required String accessProfileId,
    required String operation,
    String? actorId,
  }) {
    final operationDescriptor = P2P1OperationRegistry.descriptor(operation);
    return P2EffectBinding(
      runId: runId,
      taskId: taskId,
      actorId: actorId ?? operationDescriptor.actorId,
      toolId: operationDescriptor.toolId,
      accessProfileId: accessProfileId,
      capabilityId: operationDescriptor.capabilityId,
      operation: operation,
    );
  }
}
