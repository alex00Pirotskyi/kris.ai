import 'dart:convert';
import 'dart:math';

import 'crypto_utils.dart';
import 'p2_automation_host.dart';
import 'p2_effect_boundary.dart';
import 'p2_p1_authority_adapter.dart';

/// Explicit QA-only authority used when the owner accepts reduced isolation.
/// It grants current-account effects locally and never claims P1A completion.
final class P2OwnerRiskQaAuthority implements P2RuntimeAuthority {
  P2OwnerRiskQaAuthority() {
    final random = Random.secure();
    String hex(int bytes) => List<int>.generate(
      bytes,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    _workerSessionId = 'owner-risk-${hex(18)}';
    _channelId = 'owner-risk-channel-${hex(18)}';
  }

  late final String _workerSessionId;
  late final String _channelId;
  int _uses = 0;
  final Map<String, int> _grantUses = <String, int>{};
  final Map<String, Map<String, Object?>> _observations =
      <String, Map<String, Object?>>{};
  Map<String, Object?>? _workerIdentity;

  @override
  String get authorityImplementation => 'P2OwnerRiskQaAuthorityV1';

  @override
  String get authorityKind => 'p2-owner-risk-current-account-v1';

  @override
  bool get completionEligible => false;

  @override
  bool get qaPreview => true;

  @override
  Map<String, Object?>? lastAuthorityObservation(String taskId) =>
      _observations[taskId];

  @override
  Map<String, Object?> get authorityProvenance => <String, Object?>{
    'schemaVersion': '1.0.0',
    'authorityType': 'owner-risk-local-current-account-v1',
    'authorityKind': authorityKind,
    'implementation': authorityImplementation,
    'qaPreview': true,
    'qaPreviewVersion': '1.0.0',
    'qaPreviewFormalCompletion': false,
    'ownerRiskAccepted': true,
    'securityEvidenceWaived': true,
    'authorityDenialCode': 'owner_risk_waived',
    'currentAccountAuthority': true,
    'rootOrAdministratorSupported': true,
    'triPlatformQaRequired': true,
    'privateAuthorityMaterialPresent': false,
    'arbitraryMessageSigningApi': false,
    'completionEligible': false,
  };

  @override
  void bindRestrictedWorkerIdentity(Map<String, Object?> identity) {
    if (identity['schemaVersion'] != '2.0.0' ||
        identity['sessionId'] != _workerSessionId ||
        identity['principalType'] != 'owner-risk-current-account' ||
        identity['ownerRiskQa'] != true ||
        identity['osIsolationWaived'] != true ||
        identity['currentAccountAuthority'] != true ||
        identity['authorityConnectionDenied'] != false ||
        identity['authorityDenialCode'] != 'owner_risk_waived' ||
        (identity['identitySha256']?.toString().isEmpty ?? true)) {
      throw StateError('owner_risk_worker_identity_invalid');
    }
    _workerIdentity = Map<String, Object?>.unmodifiable(
      Map<String, Object?>.from(identity),
    );
  }

  @override
  Future<Map<String, Object?>> take() async => <String, Object?>{
    'schemaVersion': '4.0.0',
    'verificationMode': 'ecdsa-p256-public-only',
    'permitVerifier': <String, Object?>{
      'algorithm': 'ecdsa-p256-sha256',
      'keyId': 'owner-risk-qa-permit',
      // Shape-only public bytes. Signature verification is explicitly
      // bypassed only in KRISTIN_OWNER_RISK_QA builds.
      'publicKeySpkiBase64': base64Encode(List<int>.generate(96, (i) => i)),
    },
    'authorityState': <String, Object?>{
      'revocationEpoch': 1,
      'revokedGrantIds': <String>[],
      'authoritativeGrantUses': <String, int>{},
      'authoritativeConsumedRequestIds': <String>[],
      'authoritativeStateVersion': 0,
    },
    'workerSessionId': _workerSessionId,
    'channelId': _channelId,
    'workerCanIssue': false,
    'privateSigningMaterialPresent': false,
    'symmetricSigningMaterialPresent': false,
    'rawAuthoritySecretsReturned': false,
    'ownerRiskQa': true,
  };

  @override
  Future<P2AutomationEnvelope> issue({
    required P2EffectBinding binding,
    required String operation,
    required Map<String, Object?> payload,
    String? expectedGrantDigest,
    Duration deadline = const Duration(seconds: 30),
  }) async {
    final identity = _workerIdentity;
    if (identity == null) {
      throw StateError('owner_risk_worker_identity_not_bound');
    }
    _uses += 1;
    final now = DateTime.now().toUtc();
    final notBefore = now.subtract(const Duration(seconds: 1));
    final expiresAt = now.add(deadline);
    final requestId = 'owner-risk-request-$_uses';
    final externalGrantDigest = expectedGrantDigest?.toLowerCase();
    if (externalGrantDigest != null &&
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(externalGrantDigest)) {
      throw StateError('owner_risk_expected_grant_digest_invalid');
    }
    final grantId = externalGrantDigest == null
        ? 'owner-risk-grant-$_uses'
        : 'owner-risk-grant-${externalGrantDigest.substring(0, 16)}';
    final useNumber = (_grantUses[grantId] ?? 0) + 1;
    _grantUses[grantId] = useNumber;
    final maxUses = externalGrantDigest == null ? 1 : 64;
    final requestedPathRoots = <String>[];
    for (final key in const <String>[
      'cwd',
      'executable',
      'path',
      'targetPath',
      'sourcePath',
      'destinationPath',
    ]) {
      final value = payload[key];
      if (value is String && value.isNotEmpty) {
        requestedPathRoots.add(value);
      }
    }
    final scope = <String, Object?>{
      'paths': <String, Object?>{
        'roots': requestedPathRoots.isEmpty
            ? <String>['/']
            : List<String>.unmodifiable(requestedPathRoots),
      },
      'process': <String, Object?>{'operation': operation},
      'network': <String, Object?>{'destinations': <String>[]},
      'browser': <String, Object?>{'profiles': <String>[]},
      'secrets': <String, Object?>{'leaseIds': <String>[], 'rawReveal': false},
    };
    final grant = <String, Object?>{
      'schemaVersion': '2.0.0',
      'grantId': grantId,
      'issuer': <String, Object?>{
        'actorId': 'owner-risk-desktop-host',
        'authority': 'owner-risk-current-account',
      },
      'binding': <String, Object?>{
        'runId': binding.runId,
        'taskId': binding.taskId,
        'actorId': binding.actorId,
        'toolId': binding.toolId,
        'accessProfileId': binding.accessProfileId,
        'operation': operation,
      },
      'scope': scope,
      'budgets': <String, int>{'wallClockMs': deadline.inMilliseconds},
      'validity': <String, Object?>{
        'issuedAt': now.toIso8601String(),
        'notBefore': notBefore.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'maxUses': maxUses,
      },
      'nonce': 'owner-risk-nonce-${_uses.toString().padLeft(12, '0')}',
      'auth': <String, Object?>{
        'algorithm': 'hmac-sha256',
        'keyId': 'owner-risk-grant',
        'mac':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      },
    };
    final decision = <String, Object?>{
      'schemaVersion': '2.0.0',
      'decisionId': 'owner-risk-decision-$_uses',
      'status': 'allow',
      'binding': <String, Object?>{
        'runId': binding.runId,
        'taskId': binding.taskId,
        'actorId': binding.actorId,
        'toolId': binding.toolId,
        'accessProfileId': binding.accessProfileId,
        'capabilityId': binding.capabilityId,
      },
      'effect': <String, Object?>{'p2Operation': operation},
      'effectiveScope': scope,
    };
    final grantDigest =
        externalGrantDigest ?? Sha256.text(p2CanonicalJson(grant));
    final consumption = P2GrantConsumption(
      grantId: grantId,
      requestId: requestId,
      useNumber: useNumber,
      previousUseNumber: useNumber - 1,
      stateVersion: _uses,
      revocationEpoch: 1,
      consumedAt: now,
      auth: <String, String>{
        'algorithm': 'hmac-sha256',
        'keyId': 'owner-risk-consumption',
        'mac':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      },
    );
    final workerIdentitySha256 = identity['identitySha256']!.toString();
    final authenticatedIpc = <String, Object?>{
      'schemaVersion': '2.0.0',
      'peerId': 'desktop-host',
      'channelId': _channelId,
      'requestId': requestId,
      'workerIdentitySha256': workerIdentitySha256,
      'workerCanIssue': false,
      'symmetricKeyMaterialTransferred': false,
    };
    final audit = <String, Object?>{
      'id': 'owner-risk-audit-$_uses',
      'digest':
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      'sequence': _uses,
    };
    final authority = <String, Object?>{
      'authorityKind': 'p2-owner-risk-current-account-v1',
      'sharedP1ControlPlane': false,
      'p2CanIssueGrants': false,
      'workerCanIssue': false,
      'osEnforcedIsolation': false,
      'workerDeniedByOs': false,
      'securityEvidenceWaived': true,
      'workerIdentitySha256': workerIdentitySha256,
      'instanceId': 'owner-risk-local-authority',
      'implementationSha256':
          'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      'runtimeBuildSha256':
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      'ownerRiskQa': true,
    };
    final proof = P2WorkerGrantProof(
      grantId: grantId,
      grantDigest: grantDigest,
      policyDecisionId: 'owner-risk-decision-$_uses',
      policyDecisionDigest: Sha256.text(p2CanonicalJson(decision)),
      scopeDigest: Sha256.text(p2CanonicalJson(scope)),
      notBefore: notBefore,
      expiresAt: expiresAt,
      useNumber: useNumber,
      maxUses: maxUses,
      revocationEpoch: 1,
      consumptionReceipt: consumption,
      capabilityGrant: grant,
      policyDecision: decision,
      authenticatedIpc: authenticatedIpc,
      auditCheckpoint: audit,
      authority: authority,
      workerIdentity: identity,
      workerIdentitySha256: workerIdentitySha256,
    );
    final payloadWithOperation = <String, Object?>{
      'operation': operation,
      ...payload,
    };
    final authorization = <String, Object?>{
      'runId': binding.runId,
      'taskId': binding.taskId,
      'actorId': binding.actorId,
      'toolId': binding.toolId,
      'accessProfileId': binding.accessProfileId,
      'capabilityId': binding.capabilityId,
      'operation': operation,
      ...proof.toJson(),
    };
    final permit = P2WorkerEffectPermitV1(
      permitId: 'owner-risk-permit-$_uses',
      workerSessionId: _workerSessionId,
      channelId: _channelId,
      workerIdentitySha256: workerIdentitySha256,
      peerId: 'desktop-host',
      requestId: requestId,
      operation: operation,
      binding: <String, Object?>{
        'runId': binding.runId,
        'taskId': binding.taskId,
        'actorId': binding.actorId,
        'toolId': binding.toolId,
        'accessProfileId': binding.accessProfileId,
        'capabilityId': binding.capabilityId,
      },
      authorizationSha256: Sha256.text(p2CanonicalJson(authorization)),
      payloadSha256: Sha256.text(p2CanonicalJson(payloadWithOperation)),
      grantId: grantId,
      grantDigest: grantDigest,
      policyDecisionId: 'owner-risk-decision-$_uses',
      policyDecisionDigest: proof.policyDecisionDigest,
      scopeDigest: proof.scopeDigest,
      consumptionReceiptSha256: Sha256.text(
        p2CanonicalJson(consumption.toJson()),
      ),
      useNumber: useNumber,
      maxUses: maxUses,
      revocationEpoch: 1,
      authoritativeStateVersion: _uses,
      auditCheckpointId: 'owner-risk-audit-$_uses',
      auditCheckpointSha256:
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      sharedAuthorityInstanceId: 'owner-risk-local-authority',
      authorityImplementationSha256:
          'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      runtimeBuildSha256:
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      sourceCommit: '0000000000000000000000000000000000000000',
      sourceTree: '1111111111111111111111111111111111111111',
      issuedAt: now,
      notBefore: notBefore,
      expiresAt: expiresAt,
      signerKeyId: 'owner-risk-qa-permit',
      signatureBase64:
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );
    final envelope = P2AutomationEnvelope(
      requestId: requestId,
      deadline: expiresAt,
      binding: binding,
      grantProof: proof,
      operation: operation,
      payload: payloadWithOperation,
      effectPermit: permit,
    );
    envelope.validate();
    _observations[binding.taskId] =
        Map<String, Object?>.unmodifiable(<String, Object?>{
          'schemaVersion': '1.0.0',
          'taskId': binding.taskId,
          'operation': operation,
          'authorityKind': authorityKind,
          'authorityImplementation': authorityImplementation,
          'completionEligible': false,
          'qaPreview': true,
          'securityEvidenceWaived': true,
          'currentAccountAuthority': true,
          'durableConsumptionStateVersion': _uses,
          'durableConsumptionUseNumber': useNumber,
          'revocationEpoch': 1,
          'requestId': requestId,
          'grantId': grantId,
          'grantDigest': grantDigest,
          'workerIdentitySha256': workerIdentitySha256,
          'p2CanIssueGrants': false,
          'workerCanIssue': false,
          'workerDeniedByOs': false,
          'osEnforcedIsolation': false,
        });
    return envelope;
  }
}
