import 'dart:convert';

final RegExp _p1aHex40 = RegExp(r'^[0-9a-f]{40}$');
final RegExp _p1aHex64 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _p1aId = RegExp(r'^[A-Za-z0-9_.:@-]{1,192}$');

const String p1aAuthorizeEffectOperationV1 = 'authorize-effect-v2';
const String p1aRecordEffectOutcomeOperationV1 = 'record-effect-outcome-v2';
const String p1aPublicVerifierBootstrapOperationV1 = 'describe-authority-v2';
const String p1aRecordOwnerApprovalOperationV2 = 'record-owner-approval-v2';
const String p1aBeginBehaviorSessionOperationV2 = 'begin-behavior-session-v2';
const String p1aFinalizeBehaviorSessionOperationV2 =
    'finalize-behavior-session-v2';

Object? _canonicalValue(Object? value) {
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  if (value is List) {
    return value.map<Object?>(_canonicalValue).toList(growable: false);
  }
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalValue(value[key]),
    };
  }
  throw StateError('p1a_canonical_value_unsupported');
}

String p1aCanonicalJson(Object? value) => jsonEncode(_canonicalValue(value));

class P1AuthorityServiceEndpointV1 {
  const P1AuthorityServiceEndpointV1({
    required this.platform,
    required this.transport,
    required this.address,
    required this.serviceInstanceId,
    required this.serviceBuildSha256,
    required this.serverIdentity,
    required this.osEnforcedIsolation,
    required this.workerPrincipalSeparated,
    required this.typedOperationsOnly,
    required this.nonExportableKeys,
    required this.connectorLibrarySha256,
    required this.installerSha256,
  });

  factory P1AuthorityServiceEndpointV1.fromJson(Map<String, Object?> value) {
    Map<String, Object?> object(String key) {
      final raw = value[key];
      if (raw is! Map) {
        throw FormatException('p1a_endpoint_$key');
      }
      return Map<String, Object?>.from(raw);
    }

    return P1AuthorityServiceEndpointV1(
      platform: value['platform']?.toString() ?? '',
      transport: value['transport']?.toString() ?? '',
      address: value['address']?.toString() ?? '',
      serviceInstanceId: value['serviceInstanceId']?.toString() ?? '',
      serviceBuildSha256: value['serviceBuildSha256']?.toString() ?? '',
      serverIdentity: object('serverIdentity'),
      osEnforcedIsolation: value['osEnforcedIsolation'] == true,
      workerPrincipalSeparated: value['workerPrincipalSeparated'] == true,
      typedOperationsOnly: value['typedOperationsOnly'] == true,
      nonExportableKeys: value['nonExportableKeys'] == true,
      connectorLibrarySha256: value['connectorLibrarySha256']?.toString() ?? '',
      installerSha256: value['installerSha256']?.toString() ?? '',
    );
  }

  final String platform;
  final String transport;
  final String address;
  final String serviceInstanceId;
  final String serviceBuildSha256;
  final Map<String, Object?> serverIdentity;
  final bool osEnforcedIsolation;
  final bool workerPrincipalSeparated;
  final bool typedOperationsOnly;
  final bool nonExportableKeys;
  final String connectorLibrarySha256;
  final String installerSha256;

  void validate() {
    if (!const {'windows', 'macos', 'linux'}.contains(platform) ||
        !const {'windows-named-pipe', 'macos-xpc', 'linux-af-unix'}
            .contains(transport) ||
        address.isEmpty ||
        !_p1aId.hasMatch(serviceInstanceId) ||
        !_p1aHex64.hasMatch(serviceBuildSha256) ||
        !_p1aHex64.hasMatch(connectorLibrarySha256) ||
        !_p1aHex64.hasMatch(installerSha256) ||
        serverIdentity.isEmpty ||
        !osEnforcedIsolation ||
        !workerPrincipalSeparated ||
        !typedOperationsOnly ||
        !nonExportableKeys) {
      throw StateError('p1a_authority_endpoint_ineligible');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': '2.0.0',
        'platform': platform,
        'transport': transport,
        'address': address,
        'serviceInstanceId': serviceInstanceId,
        'serviceBuildSha256': serviceBuildSha256,
        'connectorLibrarySha256': connectorLibrarySha256,
        'installerSha256': installerSha256,
        'serverIdentity': serverIdentity,
        'osEnforcedIsolation': osEnforcedIsolation,
        'workerPrincipalSeparated': workerPrincipalSeparated,
        'typedOperationsOnly': typedOperationsOnly,
        'nonExportableKeys': nonExportableKeys,
      };
}

class P1AuthorityOwnerApprovalRequestV2 {
  const P1AuthorityOwnerApprovalRequestV2({
    required this.requestId,
    required this.approvalId,
    required this.interactionNonce,
    required this.binding,
    required this.effectOperation,
    required this.payloadSha256,
    required this.uiSurfaceSha256,
    required this.confirmationTextSha256,
    required this.expiresAt,
    this.interactionType = 'native-owner-confirmation',
    this.userPresent = true,
    this.behaviorSessionId,
  });

  final String requestId;
  final String approvalId;
  final String interactionNonce;
  final String interactionType;
  final Map<String, Object?> binding;
  final String effectOperation;
  final String payloadSha256;
  final String uiSurfaceSha256;
  final String confirmationTextSha256;
  final DateTime expiresAt;
  final bool userPresent;
  final String? behaviorSessionId;

  void validate(DateTime now) {
    for (final value in <String>[
      requestId,
      approvalId,
      interactionNonce,
      effectOperation,
    ]) {
      if (!_p1aId.hasMatch(value)) {
        throw StateError('p1a_owner_approval_identity_invalid');
      }
    }
    final profile = binding['accessProfileId']?.toString() ?? '';
    final requiredBinding = <String>[
      'runId',
      'taskId',
      'actorId',
      'toolId',
      'accessProfileId',
      'capabilityId',
    ];
    if (interactionType != 'native-owner-confirmation' ||
        !userPresent ||
        binding.length < requiredBinding.length ||
        requiredBinding
            .any((key) => !_p1aId.hasMatch(binding[key]?.toString() ?? '')) ||
        (profile != 'owner' && profile != 'owner_unattended') ||
        !_p1aHex64.hasMatch(payloadSha256) ||
        !_p1aHex64.hasMatch(uiSurfaceSha256) ||
        !_p1aHex64.hasMatch(confirmationTextSha256) ||
        !now.toUtc().isBefore(expiresAt.toUtc()) ||
        expiresAt.toUtc().difference(now.toUtc()) >
            const Duration(minutes: 15)) {
      throw StateError('p1a_owner_approval_limits_invalid');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': '2.0.0',
        'operation': p1aRecordOwnerApprovalOperationV2,
        'requestId': requestId,
        'approvalId': approvalId,
        'interactionNonce': interactionNonce,
        'interactionType': interactionType,
        'binding': binding,
        'effectOperation': effectOperation,
        'payloadSha256': payloadSha256,
        'uiSurfaceSha256': uiSurfaceSha256,
        'confirmationTextSha256': confirmationTextSha256,
        'userPresent': userPresent,
        'expiresAtEpochSeconds':
            expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        if (behaviorSessionId != null) 'behaviorSessionId': behaviorSessionId,
      };
}

class P1AuthorityEffectRequestV1 {
  const P1AuthorityEffectRequestV1({
    required this.requestId,
    required this.requestNonce,
    required this.runId,
    required this.taskId,
    required this.actorId,
    required this.toolId,
    required this.accessProfileId,
    required this.capabilityId,
    required this.operation,
    required this.payload,
    required this.payloadSha256,
    required this.ownerApprovalId,
    required this.workerSessionId,
    required this.channelId,
    required this.workerIdentity,
    required this.policyEffect,
    required this.requestedBudgets,
    required this.expectedRevocationEpoch,
    required this.deadline,
    this.behaviorSessionId,
  });

  final String requestId;
  final String requestNonce;
  final String runId;
  final String taskId;
  final String actorId;
  final String toolId;
  final String accessProfileId;
  final String capabilityId;
  final String operation;
  final Map<String, Object?> payload;
  final String payloadSha256;
  final String ownerApprovalId;
  final String workerSessionId;
  final String channelId;
  final Map<String, Object?> workerIdentity;
  final Map<String, Object?> policyEffect;
  final Map<String, Object?> requestedBudgets;
  final int expectedRevocationEpoch;
  final DateTime deadline;
  final String? behaviorSessionId;

  void validate(DateTime now) {
    for (final value in <String>[
      requestId,
      requestNonce,
      runId,
      taskId,
      actorId,
      toolId,
      capabilityId,
      operation,
      ownerApprovalId,
      workerSessionId,
      channelId,
    ]) {
      if (!_p1aId.hasMatch(value)) {
        throw StateError('p1a_request_identity_invalid');
      }
    }
    if (accessProfileId != 'owner' && accessProfileId != 'owner_unattended') {
      throw StateError('p1a_owner_profile_required');
    }
    if (!_p1aHex64.hasMatch(payloadSha256) ||
        workerIdentity.isEmpty ||
        policyEffect.isEmpty ||
        requestedBudgets.isEmpty ||
        expectedRevocationEpoch < 0 ||
        !now.toUtc().isBefore(deadline.toUtc()) ||
        deadline.toUtc().difference(now.toUtc()) > const Duration(minutes: 2)) {
      throw StateError('p1a_request_limits_invalid');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': '2.0.0',
        'operation': p1aAuthorizeEffectOperationV1,
        'requestId': requestId,
        'requestNonce': requestNonce,
        'workerSessionId': workerSessionId,
        'channelId': channelId,
        'workerIdentity': workerIdentity,
        'effectOperation': operation,
        'binding': <String, Object?>{
          'runId': runId,
          'taskId': taskId,
          'actorId': actorId,
          'toolId': toolId,
          'accessProfileId': accessProfileId,
          'capabilityId': capabilityId,
        },
        'policyEffect': policyEffect,
        'requestedBudgets': requestedBudgets,
        'payload': payload,
        'payloadSha256': payloadSha256,
        'ownerApprovalId': ownerApprovalId,
        'expectedRevocationEpoch': expectedRevocationEpoch,
        'deadlineEpochSeconds': deadline.toUtc().millisecondsSinceEpoch ~/ 1000,
        if (behaviorSessionId != null) 'behaviorSessionId': behaviorSessionId,
      };
}

class P1AuthorityEffectPermitV1 {
  const P1AuthorityEffectPermitV1({
    required this.envelope,
    required this.policyDecision,
    required this.capabilityGrant,
    required this.authorityObservation,
    required this.workerVerifierBootstrap,
  });

  final Map<String, Object?> envelope;
  final Map<String, Object?> policyDecision;
  final Map<String, Object?> capabilityGrant;
  final Map<String, Object?> authorityObservation;
  final Map<String, Object?> workerVerifierBootstrap;

  factory P1AuthorityEffectPermitV1.fromJson(Map<String, Object?> value) {
    Map<String, Object?> object(String key) {
      final raw = value[key];
      if (raw is! Map) {
        throw FormatException('p1a_permit_$key');
      }
      return Map<String, Object?>.from(raw);
    }

    final result = P1AuthorityEffectPermitV1(
      envelope: object('envelope'),
      policyDecision: object('policyDecision'),
      capabilityGrant: object('capabilityGrant'),
      authorityObservation: object('authorityObservation'),
      workerVerifierBootstrap: object('workerVerifierBootstrap'),
    );
    result.validate();
    return result;
  }

  void validate() {
    final effectPermit = envelope['effectPermit'];
    if (envelope['schemaVersion'] != '3.0.0' ||
        effectPermit is! Map ||
        effectPermit['permitType'] != 'p1a-one-use-effect-permit-v2' ||
        effectPermit['algorithm'] != 'ecdsa-p256-sha256' ||
        (effectPermit['signatureBase64']?.toString().isEmpty ?? true) ||
        policyDecision['status'] != 'allow' ||
        capabilityGrant['schemaVersion'] != '2.0.0' ||
        authorityObservation['authorityType'] !=
            'p1-isolated-authority-service-v2' ||
        authorityObservation['typedOperation'] !=
            p1aAuthorizeEffectOperationV1 ||
        authorityObservation['policyValidatedInsideService'] != true ||
        authorityObservation['grantIssuedInsideService'] != true ||
        authorityObservation['grantValidatedInsideService'] != true ||
        authorityObservation['useConsumedInsideService'] != true ||
        authorityObservation['revocationCheckedInsideService'] != true ||
        authorityObservation['auditAppendedInsideService'] != true ||
        authorityObservation['callerAuthenticatedByOs'] != true ||
        authorityObservation['workerDeniedByOs'] != true ||
        authorityObservation['nonExportableSigningKey'] != true ||
        workerVerifierBootstrap['verificationMode'] !=
            'ecdsa-p256-public-only' ||
        workerVerifierBootstrap['workerCanIssue'] != false ||
        workerVerifierBootstrap['privateSigningMaterialPresent'] != false ||
        workerVerifierBootstrap['symmetricSigningMaterialPresent'] != false) {
      throw StateError('p1a_effect_permit_ineligible');
    }
  }
}

class P1AuthorityEffectOutcomeV1 {
  const P1AuthorityEffectOutcomeV1({
    required this.requestId,
    required this.permitId,
    required this.status,
    required this.receiptSha256,
    required this.finishedAt,
    this.behaviorSessionId,
  });
  final String requestId;
  final String permitId;
  final String status;
  final String receiptSha256;
  final DateTime finishedAt;
  final String? behaviorSessionId;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': '2.0.0',
        'operation': p1aRecordEffectOutcomeOperationV1,
        'requestId': requestId,
        'permitId': permitId,
        'status': status,
        'receiptSha256': receiptSha256,
        'finishedAtEpochSeconds':
            finishedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        if (behaviorSessionId != null) 'behaviorSessionId': behaviorSessionId,
      };
}

abstract interface class P1AuthorityServiceConnectorV1 {
  Future<P1AuthorityServiceClientV1> connect();
}

abstract interface class P1AuthorityServiceClientV1 {
  P1AuthorityServiceEndpointV1 get endpoint;
  bool get completionEligible;
  Map<String, Object?> get provenance;

  Future<Map<String, Object?>> workerVerifierBootstrap();
  Future<Map<String, Object?>> recordOwnerApproval(
    P1AuthorityOwnerApprovalRequestV2 request,
  );
  Future<P1AuthorityEffectPermitV1> authorizeEffect(
    P1AuthorityEffectRequestV1 request,
  );
  Future<Map<String, Object?>> recordEffectOutcome(
    P1AuthorityEffectOutcomeV1 outcome,
  );
  Future<Map<String, Object?>> beginBehaviorSessionForEvidence({
    required String behaviorSessionId,
    required String exactRunBindingSha256,
  });
  Future<Map<String, Object?>> finalizeBehaviorSessionForEvidence({
    required String behaviorSessionId,
    required String exactRunBindingSha256,
  });
  Future<void> close();
}

final class P1AuthorityServiceHandleV1 {
  const P1AuthorityServiceHandleV1(this.service);
  final P1AuthorityServiceClientV1 service;

  void validateForP2({bool allowQaPreview = false}) {
    service.endpoint.validate();
    final provenance = service.provenance;
    final qaPreviewAccepted = allowQaPreview &&
        provenance['qaPreview'] == true &&
        provenance['qaPreviewVersion'] == '1.0.0' &&
        provenance['qaPreviewFormalCompletion'] == false &&
        provenance['privateAuthorityMaterialPresent'] == false &&
        provenance['arbitraryMessageSigningApi'] == false &&
        service.endpoint.osEnforcedIsolation &&
        service.endpoint.workerPrincipalSeparated &&
        service.endpoint.typedOperationsOnly &&
        service.endpoint.nonExportableKeys;
    if (qaPreviewAccepted) {
      return;
    }
    if (!service.completionEligible ||
        provenance['authorityType'] != 'p1-isolated-authority-service-v2' ||
        provenance['p1AmendmentMerged'] != true ||
        provenance['p1AmendmentSchemaVersion'] != '3.0.0' ||
        provenance['independentP1aSecurityReviewApproved'] != true ||
        provenance['workerDenialTriPlatformPassed'] != true ||
        provenance['behavioralWindowsPassed'] != true ||
        provenance['behavioralMacosPassed'] != true ||
        provenance['behavioralLinuxPassed'] != true ||
        !_p1aHex40.hasMatch(provenance['mergedCommit']?.toString() ?? '') ||
        !_p1aHex40.hasMatch(provenance['mergedTree']?.toString() ?? '') ||
        !_p1aHex64.hasMatch(
            provenance['aggregateManifestSha256']?.toString() ?? '') ||
        !_p1aHex64
            .hasMatch(provenance['platformReceiptSha256']?.toString() ?? '') ||
        !_p1aHex64
            .hasMatch(provenance['evidenceTrustSha256']?.toString() ?? '') ||
        !_p1aHex64.hasMatch(
            provenance['serviceBehaviorReceiptSha256']?.toString() ?? '') ||
        !_p1aHex64.hasMatch(
            provenance['workerDenialReceiptSha256']?.toString() ?? '') ||
        !_p1aHex64
            .hasMatch(provenance['workerLauncherSha256']?.toString() ?? '') ||
        !_p1aHex64
            .hasMatch(provenance['workerExecutableSha256']?.toString() ?? '') ||
        !_p1aHex64
            .hasMatch(provenance['workerIdentitySha256']?.toString() ?? '') ||
        !_p1aHex64
            .hasMatch(provenance['denialTranscriptSha256']?.toString() ?? '') ||
        !_p1aHex64.hasMatch(provenance['p1aPackageSha256']?.toString() ?? '') ||
        provenance['privateAuthorityMaterialPresent'] != false ||
        provenance['arbitraryMessageSigningApi'] != false ||
        provenance['completionEligible'] != true) {
      throw StateError('p1a_service_not_completion_eligible');
    }
  }
}
