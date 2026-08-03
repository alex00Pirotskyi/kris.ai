import 'dart:async';
import 'dart:convert';

import 'crypto_utils.dart';
import 'p2_effect_boundary.dart';

Object? _canonicalJsonValue(Object? value) {
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  if (value is List) {
    return value.map<Object?>(_canonicalJsonValue).toList(growable: false);
  }
  if (value is Map) {
    final keys = value.keys.map<String>((Object? key) {
      if (key is! String) {
        throw StateError('automation_envelope_non_string_key');
      }
      return key;
    }).toList()
      ..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJsonValue(value[key]),
    };
  }
  throw StateError('automation_envelope_unsupported_json_value');
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalJsonValue(value));

String p2CanonicalJson(Object? value) => _canonicalJson(value);

bool _exactJsonEquals(Object? left, Object? right) =>
    _canonicalJson(left) == _canonicalJson(right);

class P2WorkerGrantProof {
  const P2WorkerGrantProof({
    required this.grantId,
    required this.grantDigest,
    required this.policyDecisionId,
    required this.policyDecisionDigest,
    required this.scopeDigest,
    required this.notBefore,
    required this.expiresAt,
    required this.useNumber,
    required this.maxUses,
    required this.revocationEpoch,
    required this.consumptionReceipt,
    required this.capabilityGrant,
    required this.policyDecision,
    required this.authenticatedIpc,
    required this.auditCheckpoint,
    required this.authority,
    required this.workerIdentity,
    required this.workerIdentitySha256,
  });

  final String grantId;
  final String grantDigest;
  final String policyDecisionId;
  final String policyDecisionDigest;
  final String scopeDigest;
  final DateTime notBefore;
  final DateTime expiresAt;
  final int useNumber;
  final int maxUses;
  final int revocationEpoch;
  final P2GrantConsumption consumptionReceipt;
  final Map<String, Object?> capabilityGrant;
  final Map<String, Object?> policyDecision;
  final Map<String, Object?> authenticatedIpc;
  final Map<String, Object?> auditCheckpoint;
  final Map<String, Object?> authority;
  final Map<String, Object?> workerIdentity;
  final String workerIdentitySha256;

  factory P2WorkerGrantProof.fromJson(Map<String, Object?> value) {
    Map<String, Object?> object(String key) {
      final raw = value[key];
      if (raw is! Map) throw FormatException('worker_grant_$key');
      return Map<String, Object?>.from(raw);
    }

    DateTime timestamp(String key) {
      final parsed = DateTime.tryParse(value[key]?.toString() ?? '')?.toUtc();
      if (parsed == null) throw FormatException('worker_grant_$key');
      return parsed;
    }

    final useNumber = value['useNumber'];
    final maxUses = value['maxUses'];
    final revocationEpoch = value['revocationEpoch'];
    if (useNumber is! int || maxUses is! int || revocationEpoch is! int) {
      throw const FormatException('worker_grant_numeric_fields');
    }
    return P2WorkerGrantProof(
      grantId: value['grantId']?.toString() ?? '',
      grantDigest: value['grantDigest']?.toString() ?? '',
      policyDecisionId: value['policyDecisionId']?.toString() ?? '',
      policyDecisionDigest: value['policyDecisionDigest']?.toString() ?? '',
      scopeDigest: value['scopeDigest']?.toString() ?? '',
      notBefore: timestamp('notBefore'),
      expiresAt: timestamp('expiresAt'),
      useNumber: useNumber,
      maxUses: maxUses,
      revocationEpoch: revocationEpoch,
      consumptionReceipt: P2GrantConsumption.fromJson(
        object('consumptionReceipt'),
      ),
      capabilityGrant: object('capabilityGrant'),
      policyDecision: object('policyDecision'),
      authenticatedIpc: object('authenticatedIpc'),
      auditCheckpoint: object('auditCheckpoint'),
      authority: object('authority'),
      workerIdentity: object('workerIdentity'),
      workerIdentitySha256: value['workerIdentitySha256']?.toString() ?? '',
    );
  }

  void validate(DateTime now, String requestId) {
    final hex = RegExp(r'^[0-9a-fA-F]{64}$');
    if (grantId.isEmpty ||
        policyDecisionId.isEmpty ||
        !hex.hasMatch(grantDigest) ||
        !hex.hasMatch(policyDecisionDigest) ||
        !hex.hasMatch(scopeDigest)) {
      throw StateError('worker_grant_proof_invalid');
    }
    if (now.isBefore(notBefore.toUtc()) || !now.isBefore(expiresAt.toUtc())) {
      throw StateError('worker_grant_expired_or_not_yet_valid');
    }
    if (useNumber < 1 || maxUses < 1 || useNumber > maxUses) {
      throw StateError('worker_grant_use_invalid');
    }
    if (revocationEpoch < 0) {
      throw StateError('worker_grant_revocation_epoch_invalid');
    }
    if (consumptionReceipt.grantId != grantId ||
        consumptionReceipt.requestId != requestId ||
        consumptionReceipt.useNumber != useNumber ||
        consumptionReceipt.revocationEpoch != revocationEpoch ||
        consumptionReceipt.stateVersion < useNumber ||
        consumptionReceipt.previousUseNumber != useNumber - 1) {
      throw StateError('worker_consumption_receipt_binding_invalid');
    }
    if (capabilityGrant['schemaVersion'] != '2.0.0' ||
        capabilityGrant['grantId'] != grantId) {
      throw StateError('worker_capability_grant_identity_invalid');
    }
    final grantBinding = Map<String, Object?>.from(
      capabilityGrant['binding']! as Map,
    );
    final validity = Map<String, Object?>.from(
      capabilityGrant['validity']! as Map,
    );
    if (validity['notBefore'] != notBefore.toUtc().toIso8601String() ||
        validity['expiresAt'] != expiresAt.toUtc().toIso8601String() ||
        validity['maxUses'] != maxUses) {
      throw StateError('worker_capability_grant_validity_invalid');
    }
    final decisionScope = policyDecision['effectiveScope'];
    final legacyEffect = policyDecision['effect'];
    if (grantBinding.isEmpty ||
        grantBinding['operation'] == null ||
        policyDecision['status'] != 'allow' ||
        policyDecision['decisionId'] != policyDecisionId ||
        policyDecision['binding'] is! Map ||
        (decisionScope is! Map && legacyEffect is! Map)) {
      throw StateError('worker_policy_decision_invalid');
    }
    final grantScope = capabilityGrant['scope'];
    if (grantScope is! Map ||
        (decisionScope is Map &&
            !_exactJsonEquals(decisionScope, grantScope))) {
      throw StateError('worker_policy_scope_binding_invalid');
    }
    if (authenticatedIpc['schemaVersion'] != '2.0.0' ||
        authenticatedIpc['peerId'] != 'desktop-host' ||
        authenticatedIpc['requestId'] != requestId ||
        authenticatedIpc['workerCanIssue'] != false ||
        authenticatedIpc['symmetricKeyMaterialTransferred'] != false ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(
          authenticatedIpc['workerIdentitySha256']?.toString() ?? '',
        )) {
      throw StateError('worker_authenticated_ipc_record_invalid');
    }
    if ((auditCheckpoint['id'] ?? '').toString().isEmpty ||
        !hex.hasMatch('${auditCheckpoint['digest'] ?? ''}') ||
        authority['authorityKind'] != 'p1-isolated-authority-service-v2' ||
        authority['p2CanIssueGrants'] != false ||
        authority['workerCanIssue'] != false ||
        authority['osEnforcedIsolation'] != true ||
        authority['workerDeniedByOs'] != true ||
        authority['workerIdentitySha256'] !=
            authenticatedIpc['workerIdentitySha256'] ||
        workerIdentitySha256 != authenticatedIpc['workerIdentitySha256'] ||
        authority['workerIdentitySha256'] != workerIdentitySha256 ||
        Sha256.text(_canonicalJson(<String, Object?>{
              for (final entry in workerIdentity.entries)
                if (entry.key != 'identitySha256') entry.key: entry.value,
            })) !=
            workerIdentitySha256 ||
        (workerIdentity['identitySha256'] != null &&
            workerIdentity['identitySha256'] != workerIdentitySha256) ||
        (authority['instanceId'] ?? '').toString().isEmpty) {
      throw StateError('worker_authority_chain_invalid');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'grantId': grantId,
        'grantDigest': grantDigest,
        'policyDecisionId': policyDecisionId,
        'policyDecisionDigest': policyDecisionDigest,
        'scopeDigest': scopeDigest,
        'notBefore': notBefore.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'useNumber': useNumber,
        'maxUses': maxUses,
        'revocationEpoch': revocationEpoch,
        'consumptionReceipt': consumptionReceipt.toJson(),
        'capabilityGrant': capabilityGrant,
        'policyDecision': policyDecision,
        'authenticatedIpc': authenticatedIpc,
        'auditCheckpoint': auditCheckpoint,
        'authority': authority,
        'workerIdentity': workerIdentity,
        'workerIdentitySha256': workerIdentitySha256,
      };
}

/// One-use desktop-issued effect permit. The worker receives only the public
/// ECDSA P-256 verifier key at bootstrap. It never receives any P1 HMAC or private
/// signing material and therefore cannot mint a permit, grant, or consumption
/// receipt.
class P2WorkerEffectPermitV1 {
  const P2WorkerEffectPermitV1({
    required this.permitId,
    required this.workerSessionId,
    required this.channelId,
    required this.workerIdentitySha256,
    required this.peerId,
    required this.requestId,
    required this.operation,
    required this.binding,
    required this.authorizationSha256,
    required this.payloadSha256,
    required this.grantId,
    required this.grantDigest,
    required this.policyDecisionId,
    required this.policyDecisionDigest,
    required this.scopeDigest,
    required this.consumptionReceiptSha256,
    required this.useNumber,
    required this.maxUses,
    required this.revocationEpoch,
    required this.authoritativeStateVersion,
    required this.auditCheckpointId,
    required this.auditCheckpointSha256,
    required this.sharedAuthorityInstanceId,
    required this.authorityImplementationSha256,
    required this.runtimeBuildSha256,
    required this.sourceCommit,
    required this.sourceTree,
    required this.issuedAt,
    required this.notBefore,
    required this.expiresAt,
    required this.signerKeyId,
    required this.signatureBase64,
  });

  final String permitId;
  final String workerSessionId;
  final String channelId;
  final String workerIdentitySha256;
  final String peerId;
  final String requestId;
  final String operation;
  final Map<String, Object?> binding;
  final String authorizationSha256;
  final String payloadSha256;
  final String grantId;
  final String grantDigest;
  final String policyDecisionId;
  final String policyDecisionDigest;
  final String scopeDigest;
  final String consumptionReceiptSha256;
  final int useNumber;
  final int maxUses;
  final int revocationEpoch;
  final int authoritativeStateVersion;
  final String auditCheckpointId;
  final String auditCheckpointSha256;
  final String sharedAuthorityInstanceId;
  final String authorityImplementationSha256;
  final String runtimeBuildSha256;
  final String sourceCommit;
  final String sourceTree;
  final DateTime issuedAt;
  final DateTime notBefore;
  final DateTime expiresAt;
  final String signerKeyId;
  final String signatureBase64;

  factory P2WorkerEffectPermitV1.fromJson(Map<String, Object?> value) {
    DateTime time(String key) {
      final parsed = DateTime.tryParse(value[key]?.toString() ?? '')?.toUtc();
      if (parsed == null) throw FormatException('effect_permit_$key');
      return parsed;
    }

    Map<String, Object?> object(String key) {
      final raw = value[key];
      if (raw is! Map) throw FormatException('effect_permit_$key');
      return Map<String, Object?>.from(raw);
    }

    int integer(String key) {
      final raw = value[key];
      if (raw is! int) throw FormatException('effect_permit_$key');
      return raw;
    }

    return P2WorkerEffectPermitV1(
      permitId: value['permitId']?.toString() ?? '',
      workerSessionId: value['workerSessionId']?.toString() ?? '',
      channelId: value['channelId']?.toString() ?? '',
      workerIdentitySha256: value['workerIdentitySha256']?.toString() ?? '',
      peerId: value['peerId']?.toString() ?? '',
      requestId: value['requestId']?.toString() ?? '',
      operation: value['operation']?.toString() ?? '',
      binding: object('binding'),
      authorizationSha256: value['authorizationSha256']?.toString() ?? '',
      payloadSha256: value['payloadSha256']?.toString() ?? '',
      grantId: value['grantId']?.toString() ?? '',
      grantDigest: value['grantDigest']?.toString() ?? '',
      policyDecisionId: value['policyDecisionId']?.toString() ?? '',
      policyDecisionDigest: value['policyDecisionDigest']?.toString() ?? '',
      scopeDigest: value['scopeDigest']?.toString() ?? '',
      consumptionReceiptSha256:
          value['consumptionReceiptSha256']?.toString() ?? '',
      useNumber: integer('useNumber'),
      maxUses: integer('maxUses'),
      revocationEpoch: integer('revocationEpoch'),
      authoritativeStateVersion: integer('authoritativeStateVersion'),
      auditCheckpointId: value['auditCheckpointId']?.toString() ?? '',
      auditCheckpointSha256: value['auditCheckpointSha256']?.toString() ?? '',
      sharedAuthorityInstanceId:
          value['sharedAuthorityInstanceId']?.toString() ?? '',
      authorityImplementationSha256:
          value['authorityImplementationSha256']?.toString() ?? '',
      runtimeBuildSha256: value['runtimeBuildSha256']?.toString() ?? '',
      sourceCommit: value['sourceCommit']?.toString() ?? '',
      sourceTree: value['sourceTree']?.toString() ?? '',
      issuedAt: time('issuedAt'),
      notBefore: time('notBefore'),
      expiresAt: time('expiresAt'),
      signerKeyId: value['signerKeyId']?.toString() ?? '',
      signatureBase64: value['signatureBase64']?.toString() ?? '',
    );
  }

  Map<String, Object?> unsignedJson() => <String, Object?>{
        'schemaVersion': '2.0.0',
        'permitType': 'p1a-one-use-effect-permit-v2',
        'permitId': permitId,
        'workerSessionId': workerSessionId,
        'channelId': channelId,
        'workerIdentitySha256': workerIdentitySha256,
        'peerId': peerId,
        'requestId': requestId,
        'operation': operation,
        'binding': binding,
        'authorizationSha256': authorizationSha256,
        'payloadSha256': payloadSha256,
        'grantId': grantId,
        'grantDigest': grantDigest,
        'policyDecisionId': policyDecisionId,
        'policyDecisionDigest': policyDecisionDigest,
        'scopeDigest': scopeDigest,
        'consumptionReceiptSha256': consumptionReceiptSha256,
        'useNumber': useNumber,
        'maxUses': maxUses,
        'revocationEpoch': revocationEpoch,
        'authoritativeStateVersion': authoritativeStateVersion,
        'auditCheckpointId': auditCheckpointId,
        'auditCheckpointSha256': auditCheckpointSha256,
        'sharedAuthorityInstanceId': sharedAuthorityInstanceId,
        'authorityImplementationSha256': authorityImplementationSha256,
        'runtimeBuildSha256': runtimeBuildSha256,
        'sourceCommit': sourceCommit,
        'sourceTree': sourceTree,
        'issuedAt': issuedAt.toUtc().toIso8601String(),
        'notBefore': notBefore.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'algorithm': 'ecdsa-p256-sha256',
        'signerKeyId': signerKeyId,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        ...unsignedJson(),
        'signatureBase64': signatureBase64,
      };

  void validateShape() {
    final hex40 = RegExp(r'^[0-9a-f]{40}$');
    final hex64 = RegExp(r'^[0-9a-f]{64}$');
    final base64 = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');
    if (permitId.isEmpty ||
        workerSessionId.length < 16 ||
        channelId.length < 16 ||
        peerId != 'desktop-host' ||
        requestId.isEmpty ||
        operation.isEmpty ||
        binding.isEmpty ||
        grantId.isEmpty ||
        policyDecisionId.isEmpty ||
        auditCheckpointId.isEmpty ||
        sharedAuthorityInstanceId.isEmpty ||
        signerKeyId.isEmpty ||
        !hex64.hasMatch(workerIdentitySha256) ||
        !base64.hasMatch(signatureBase64) ||
        signatureBase64.length < 80 ||
        !hex40.hasMatch(sourceCommit) ||
        !hex40.hasMatch(sourceTree)) {
      throw StateError('effect_permit_identity_invalid');
    }
    for (final value in <String>[
      authorizationSha256,
      payloadSha256,
      grantDigest,
      policyDecisionDigest,
      scopeDigest,
      consumptionReceiptSha256,
      auditCheckpointSha256,
      authorityImplementationSha256,
      runtimeBuildSha256,
    ]) {
      if (!hex64.hasMatch(value)) {
        throw StateError('effect_permit_digest_invalid');
      }
    }
    if (useNumber < 1 ||
        maxUses < useNumber ||
        revocationEpoch < 0 ||
        authoritativeStateVersion < useNumber ||
        !issuedAt.isBefore(expiresAt) ||
        notBefore.isAfter(issuedAt)) {
      throw StateError('effect_permit_state_invalid');
    }
  }
}

class P2AutomationEnvelope {
  const P2AutomationEnvelope({
    required this.requestId,
    required this.deadline,
    required this.binding,
    required this.grantProof,
    required this.operation,
    required this.payload,
    required this.effectPermit,
  });

  final String requestId;
  final DateTime deadline;
  final P2EffectBinding binding;
  final P2WorkerGrantProof grantProof;
  final String operation;
  final Map<String, Object?> payload;
  final P2WorkerEffectPermitV1 effectPermit;

  factory P2AutomationEnvelope.fromJson(Map<String, Object?> value) {
    if (value['schemaVersion'] != '3.0.0') {
      throw const FormatException('automation_envelope_version');
    }
    final rawAuthorization = value['authorization'];
    final rawPayload = value['payload'];
    final rawPermit = value['effectPermit'];
    if (rawAuthorization is! Map || rawPayload is! Map || rawPermit is! Map) {
      throw const FormatException('automation_envelope_shape');
    }
    final authorization = Map<String, Object?>.from(rawAuthorization);
    final deadline =
        DateTime.tryParse(value['deadline']?.toString() ?? '')?.toUtc();
    if (deadline == null) {
      throw const FormatException('automation_envelope_deadline');
    }
    final binding = P2EffectBinding(
      runId: authorization['runId']?.toString() ?? '',
      taskId: authorization['taskId']?.toString() ?? '',
      actorId: authorization['actorId']?.toString() ?? '',
      toolId: authorization['toolId']?.toString() ?? '',
      accessProfileId: authorization['accessProfileId']?.toString() ?? '',
      capabilityId: authorization['capabilityId']?.toString() ?? '',
      operation: authorization['operation']?.toString() ?? '',
    );
    return P2AutomationEnvelope(
      requestId: value['requestId']?.toString() ?? '',
      deadline: deadline,
      binding: binding,
      grantProof: P2WorkerGrantProof.fromJson(authorization),
      operation: binding.operation,
      payload: Map<String, Object?>.from(rawPayload),
      effectPermit: P2WorkerEffectPermitV1.fromJson(
        Map<String, Object?>.from(rawPermit),
      ),
    );
  }

  Map<String, Object?> get authorizationJson => <String, Object?>{
        'runId': binding.runId,
        'taskId': binding.taskId,
        'actorId': binding.actorId,
        'toolId': binding.toolId,
        'accessProfileId': binding.accessProfileId,
        'capabilityId': binding.capabilityId,
        'operation': operation,
        ...grantProof.toJson(),
      };

  void validate() {
    final now = DateTime.now().toUtc();
    if (requestId.isEmpty || effectPermit.requestId != requestId) {
      throw StateError('request_identity_mismatch');
    }
    if (!now.isBefore(deadline.toUtc()) ||
        effectPermit.expiresAt.toUtc() != deadline.toUtc()) {
      throw StateError('deadline_binding_mismatch');
    }
    if (operation != binding.operation ||
        effectPermit.operation != operation ||
        (grantProof.capabilityGrant['binding'] as Map)['operation'] !=
            operation) {
      throw StateError('operation_binding_mismatch');
    }
    grantProof.validate(now, requestId);
    effectPermit.validateShape();
    if (!_exactJsonEquals(effectPermit.binding, <String, Object?>{
      'runId': binding.runId,
      'taskId': binding.taskId,
      'actorId': binding.actorId,
      'toolId': binding.toolId,
      'accessProfileId': binding.accessProfileId,
      'capabilityId': binding.capabilityId,
    })) {
      throw StateError('effect_permit_binding_mismatch');
    }
    if (effectPermit.authorizationSha256 !=
            Sha256.text(_canonicalJson(authorizationJson)) ||
        effectPermit.payloadSha256 != Sha256.text(_canonicalJson(payload)) ||
        effectPermit.grantId != grantProof.grantId ||
        effectPermit.grantDigest != grantProof.grantDigest ||
        effectPermit.policyDecisionId != grantProof.policyDecisionId ||
        effectPermit.policyDecisionDigest != grantProof.policyDecisionDigest ||
        effectPermit.scopeDigest != grantProof.scopeDigest ||
        effectPermit.auditCheckpointId != grantProof.auditCheckpoint['id'] ||
        effectPermit.auditCheckpointSha256 !=
            grantProof.auditCheckpoint['digest'] ||
        effectPermit.sharedAuthorityInstanceId !=
            grantProof.authority['instanceId'] ||
        effectPermit.channelId != grantProof.authenticatedIpc['channelId'] ||
        effectPermit.workerIdentitySha256 !=
            grantProof.authenticatedIpc['workerIdentitySha256'] ||
        effectPermit.workerIdentitySha256 !=
            grantProof.authority['workerIdentitySha256'] ||
        effectPermit.consumptionReceiptSha256 !=
            Sha256.text(
                _canonicalJson(grantProof.consumptionReceipt.toJson())) ||
        effectPermit.useNumber != grantProof.useNumber ||
        effectPermit.maxUses != grantProof.maxUses ||
        effectPermit.revocationEpoch != grantProof.revocationEpoch ||
        effectPermit.authoritativeStateVersion !=
            grantProof.consumptionReceipt.stateVersion) {
      throw StateError('effect_permit_authorization_mismatch');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': '3.0.0',
        'requestId': requestId,
        'deadline': deadline.toUtc().toIso8601String(),
        'authorization': authorizationJson,
        'effectPermit': effectPermit.toJson(),
        'payload': payload,
      };
}

abstract interface class P2AutomationEnvelopeIssuer {
  Future<P2AutomationEnvelope> issue({
    required P2EffectBinding binding,
    required String operation,
    required Map<String, Object?> payload,
    String? expectedGrantDigest,
  });
}

abstract interface class P2AutomationEnvelopeAuthority {
  Future<P2AutomationEnvelope> issue({
    required P2EffectBinding binding,
    required String operation,
    required Map<String, Object?> payload,
    String? expectedGrantDigest,
    Duration deadline = const Duration(seconds: 30),
  });
}

abstract interface class P2AutomationHostClient {
  Stream<Map<String, Object?>> get events;

  Future<Map<String, Object?>> invoke(P2AutomationEnvelope envelope);

  Stream<Map<String, Object?>> stream(
    String requestId, {
    required P2EffectBinding binding,
    required P2WorkerGrantProof grantProof,
  });

  Future<Map<String, Object?>> cancel(P2AutomationEnvelope envelope);

  Future<void> close();
}

class P2SupervisedAutomationHost {
  P2SupervisedAutomationHost(this.client);

  final P2AutomationHostClient client;

  Future<Map<String, Object?>> execute(P2AutomationEnvelope envelope) {
    envelope.validate();
    return client.invoke(envelope);
  }
}
