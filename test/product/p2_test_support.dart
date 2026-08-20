import 'dart:async';

import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/p2_automation_host.dart';
import 'package:kristin_local_agent/product/p2_effect_boundary.dart';
import 'package:kristin_local_agent/product/p2_effect_journal.dart';

P2EffectBinding testBinding(String operation, {String taskId = 'P2-test'}) =>
    P2EffectBinding(
      runId: 'run',
      taskId: taskId,
      actorId: 'owner_executor',
      toolId: 'p2-runtime',
      accessProfileId: 'owner',
      capabilityId: 'capability',
      operation: operation,
    );

Map<String, Object?> testReceipt(
  P2EffectBinding binding,
  String operation, {
  String status = 'succeeded',
  String reversibility = 'reversible',
  Map<String, Object?> details = const <String, Object?>{},
}) =>
    <String, Object?>{
      'schemaVersion': '1.0.0',
      'effectId': '$operation-effect',
      'runId': binding.runId,
      'taskId': binding.taskId,
      'operation': operation,
      'status': status,
      'reversibility': reversibility,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'completedAt': DateTime.now().toUtc().toIso8601String(),
      'details': details,
    };

final class TestEnvelopeAuthority implements P2AutomationEnvelopeAuthority {
  TestEnvelopeAuthority({this.operationBoundGrants = true});

  final bool operationBoundGrants;
  int _requests = 0;
  final Map<String, int> _grantUses = <String, int>{};
  final List<P2AutomationEnvelope> issued = <P2AutomationEnvelope>[];

  @override
  Future<P2AutomationEnvelope> issue({
    required P2EffectBinding binding,
    required String operation,
    required Map<String, Object?> payload,
    String? expectedGrantDigest,
    Duration deadline = const Duration(seconds: 30),
  }) async {
    _requests += 1;
    final now = DateTime.now().toUtc();
    final notBefore = now.subtract(const Duration(seconds: 1));
    final expiresAt = now.add(deadline);
    final requestId = 'request-$_requests';
    final externalGrantDigest = expectedGrantDigest?.toLowerCase();
    if (externalGrantDigest != null &&
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(externalGrantDigest)) {
      throw StateError('expected_grant_digest_invalid');
    }
    final grantId = externalGrantDigest == null
        ? 'grant-$_requests'
        : 'grant-${externalGrantDigest.substring(0, 16)}';
    final useNumber = (_grantUses[grantId] ?? 0) + 1;
    _grantUses[grantId] = useNumber;
    final maxUses = externalGrantDigest == null ? 1 : 64;
    final scope = <String, Object?>{
      'paths': <String, Object?>{
        'roots': <String>['/'],
      },
      'process': operationBoundGrants
          ? <String, Object?>{'operation': operation}
          : <String, Object?>{'sessionOperations': true},
      'network': <String, Object?>{'destinations': <String>[]},
      'browser': <String, Object?>{'profiles': <String>[]},
      'secrets': <String, Object?>{'leaseIds': <String>[], 'rawReveal': false},
    };
    final grant = <String, Object?>{
      'schemaVersion': '2.0.0',
      'grantId': grantId,
      'issuer': <String, Object?>{
        'actorId': 'desktop_host',
        'authority': 'desktop_host:deterministic_policy',
      },
      'binding': <String, Object?>{
        'runId': binding.runId,
        'taskId': binding.taskId,
        'actorId': binding.actorId,
        'toolId': binding.toolId,
        'accessProfileId': binding.accessProfileId,
        if (operationBoundGrants) 'operation': operation,
      },
      'scope': scope,
      'budgets': <String, int>{'wallClockMs': 30000},
      'validity': <String, Object?>{
        'issuedAt': now.toIso8601String(),
        'notBefore': notBefore.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'maxUses': maxUses,
      },
      'nonce': 'test-nonce-${_requests.toString().padLeft(16, '0')}',
      'auth': <String, Object?>{
        'algorithm': 'hmac-sha256',
        'keyId': 'test-grant',
        'mac': 'a' * 64,
      },
    };
    final decision = <String, Object?>{
      'schemaVersion': '2.0.0',
      'decisionId': 'decision-$_requests',
      'status': 'allow',
      'binding': <String, Object?>{
        'runId': binding.runId,
        'taskId': binding.taskId,
        'actorId': binding.actorId,
        'toolId': binding.toolId,
        'accessProfileId': binding.accessProfileId,
        'capabilityId': binding.capabilityId,
      },
      'effectiveScope': scope,
    };
    final grantDigest =
        externalGrantDigest ?? Sha256.text(p2CanonicalJson(grant));
    final consumption = P2GrantConsumption(
      grantId: grantId,
      requestId: requestId,
      useNumber: useNumber,
      previousUseNumber: useNumber - 1,
      stateVersion: _requests,
      revocationEpoch: 1,
      consumedAt: now,
      auth: <String, String>{
        'algorithm': 'hmac-sha256',
        'keyId': 'test-consumption',
        'mac': 'b' * 64,
      },
    );
    final workerIdentity = <String, Object?>{
      'schemaVersion': '2.0.0',
      'platform': 'linux',
      'principalType': 'dedicated-uid',
      'sessionId': 'test-worker-session-000001',
      'pid': 4242,
      'startToken': 'start-4242',
      'workerUid': 65534,
      'workerGid': 65534,
      'noNewPrivileges': true,
      'namespaceIsolation': true,
      'authorityConnectionDenied': true,
      'authorityDenialCode': 'worker_principal_denied',
      'launcherSha256': '1' * 64,
      'nodeSha256': '2' * 64,
      'hostScriptSha256': '3' * 64,
      'workerPolicySha256': '4' * 64,
    };
    final workerIdentitySha256 = Sha256.text(p2CanonicalJson(workerIdentity));
    final authenticatedIpc = <String, Object?>{
      'schemaVersion': '2.0.0',
      'peerId': 'desktop-host',
      'channelId': 'test-channel-0000000000001',
      'requestId': requestId,
      'workerIdentitySha256': workerIdentitySha256,
      'workerCanIssue': false,
      'symmetricKeyMaterialTransferred': false,
    };
    final audit = <String, Object?>{
      'id': 'audit-$_requests',
      'digest': 'd' * 64,
      'sequence': _requests,
    };
    final authority = <String, Object?>{
      'authorityKind': 'p1-isolated-authority-service-v2',
      'sharedP1ControlPlane': true,
      'p2CanIssueGrants': false,
      'workerCanIssue': false,
      'osEnforcedIsolation': true,
      'workerDeniedByOs': true,
      'workerIdentitySha256': workerIdentitySha256,
      'instanceId': 'p1a-test-instance',
      'implementationSha256': 'e' * 64,
      'runtimeBuildSha256': 'f' * 64,
    };
    final proof = P2WorkerGrantProof(
      grantId: grantId,
      grantDigest: grantDigest,
      policyDecisionId: 'decision-$_requests',
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
      workerIdentity: workerIdentity,
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
      permitId: 'permit-$_requests',
      workerSessionId: 'test-worker-session-000001',
      channelId: 'test-channel-0000000000001',
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
      policyDecisionId: 'decision-$_requests',
      policyDecisionDigest: proof.policyDecisionDigest,
      scopeDigest: proof.scopeDigest,
      consumptionReceiptSha256: Sha256.text(
        p2CanonicalJson(consumption.toJson()),
      ),
      useNumber: useNumber,
      maxUses: maxUses,
      revocationEpoch: 1,
      authoritativeStateVersion: _requests,
      auditCheckpointId: 'audit-$_requests',
      auditCheckpointSha256: 'd' * 64,
      sharedAuthorityInstanceId: 'p1a-test-instance',
      authorityImplementationSha256: 'e' * 64,
      runtimeBuildSha256: 'f' * 64,
      sourceCommit: '0000000000000000000000000000000000000000',
      sourceTree: '1111111111111111111111111111111111111111',
      issuedAt: now,
      notBefore: notBefore,
      expiresAt: expiresAt,
      signerKeyId: 'test-effect-permit',
      signatureBase64: 'A' * 96,
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
    issued.add(envelope);
    return envelope;
  }
}

typedef TestResponseBuilder = Map<String, Object?> Function(
    P2AutomationEnvelope envelope);

final class TestAutomationHostClient implements P2AutomationHostClient {
  TestAutomationHostClient(this.builder);
  final TestResponseBuilder builder;
  final List<P2AutomationEnvelope> calls = <P2AutomationEnvelope>[];
  final StreamController<Map<String, Object?>> controller =
      StreamController<Map<String, Object?>>.broadcast();
  @override
  Stream<Map<String, Object?>> get events => controller.stream;
  @override
  Future<Map<String, Object?>> invoke(P2AutomationEnvelope envelope) async {
    envelope.validate();
    calls.add(envelope);
    return builder(envelope);
  }

  @override
  Stream<Map<String, Object?>> stream(
    String requestId, {
    required P2EffectBinding binding,
    required P2WorkerGrantProof grantProof,
  }) =>
      controller.stream.where((event) => event['requestId'] == requestId);
  @override
  Future<Map<String, Object?>> cancel(P2AutomationEnvelope envelope) =>
      invoke(envelope);
  @override
  Future<void> close() => controller.close();
}

final class TestJournal implements P2EffectJournal {
  final List<P2EffectReceipt> receipts = <P2EffectReceipt>[];
  @override
  Future<void> append(P2EffectReceipt receipt) async => receipts.add(receipt);
}
