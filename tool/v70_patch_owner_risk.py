#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import pathlib
import re


def require_once(source: str, needle: str, label: str) -> None:
    count = source.count(needle)
    if count != 1:
        raise SystemExit(f"ERROR: {label}: expected exactly one anchor, found {count}: {needle!r}")


def replace_once(path: pathlib.Path, old: str, new: str, label: str) -> None:
    source = path.read_text(encoding="utf-8")
    require_once(source, old, label)
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def patch_source_inventory(root: pathlib.Path) -> None:
    path = root / "config/p2_source_inventory.v1.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    production = data.get("productionDart")
    tests = data.get("testDart")
    if not isinstance(production, list) or not isinstance(tests, list):
        raise SystemExit("ERROR: P2 governed source inventory is invalid")
    production_required = {
        "lib/product/p2_owner_risk_authority.dart",
    }
    test_required = {
        "test/product/p2_qa_preview_gate_test.dart",
        "test/product/p2_owner_risk_contract_test.dart",
        "test/product/p2_owner_risk_runtime_smoke_test.dart",
    }
    data["productionDart"] = sorted({str(value) for value in production} | production_required)
    data["testDart"] = sorted({str(value) for value in tests} | test_required)
    data["authority"] = (
        "P2 governed source inventory V70-R5 owner-risk tri-platform QA "
        "(P2-only; P1A source is merged and security evidence is waived for QA)"
    )
    data["ownerRiskQaExtension"] = {
        "allPlatformsRequired": ["windows", "macos", "linux"],
        "externalEvidenceTrustRequired": False,
        "formalSecurityCompletion": False,
        "productionReleaseEligible": False,
    }
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


OWNER_RISK_AUTHORITY = r'''import 'dart:convert';
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
    String hex(int bytes) => List<int>.generate(bytes, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
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
    final scope = <String, Object?>{
      'paths': <String, Object?>{'roots': <String>['/']},
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
        'mac': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
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
        'mac': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
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
      'digest': 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
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
      'implementationSha256': 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      'runtimeBuildSha256': 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
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
      consumptionReceiptSha256:
          Sha256.text(p2CanonicalJson(consumption.toJson())),
      useNumber: useNumber,
      maxUses: maxUses,
      revocationEpoch: 1,
      authoritativeStateVersion: _uses,
      auditCheckpointId: 'owner-risk-audit-$_uses',
      auditCheckpointSha256: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      sharedAuthorityInstanceId: 'owner-risk-local-authority',
      authorityImplementationSha256: 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      runtimeBuildSha256: 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      sourceCommit: '0000000000000000000000000000000000000000',
      sourceTree: '1111111111111111111111111111111111111111',
      issuedAt: now,
      notBefore: notBefore,
      expiresAt: expiresAt,
      signerKeyId: 'owner-risk-qa-permit',
      signatureBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
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
    _observations[binding.taskId] = Map<String, Object?>.unmodifiable(
      <String, Object?>{
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
      },
    );
    return envelope;
  }
}
'''

OWNER_RISK_LAUNCHER = r'''#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runCli } from './host.mjs';

function sha(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}
function arg(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || index + 1 >= process.argv.length) throw new Error(`missing_${name}`);
  return process.argv[index + 1];
}
const policyPath = path.resolve(arg('--policy'));
const sessionId = arg('--session');
const policy = JSON.parse(fs.readFileSync(policyPath, 'utf8'));
const platform = process.platform === 'win32' ? 'windows' : process.platform === 'darwin' ? 'macos' : 'linux';
if (policy.schemaVersion !== '2.0.0' || policy.platform !== platform || sessionId.length < 16) {
  throw new Error('owner_risk_worker_policy_invalid');
}
const node = path.resolve(policy.nodeExecutable);
const host = path.resolve(policy.hostScript);
const self = fileURLToPath(import.meta.url);
const identity = {
  type: 'launcher.identity', schemaVersion: '2.0.0', platform,
  principalType: 'owner-risk-current-account',
  sessionId, pid: process.pid, startToken: `owner-risk-${process.pid}-${Date.now()}`,
  launcherSha256: sha(self), nodeSha256: sha(node), hostScriptSha256: sha(host),
  authorityConnectionDenied: false, authorityDenialCode: 'owner_risk_waived',
  authorityDenialObservedBy: 'owner-risk-waiver',
  ownerRiskQa: true, osIsolationWaived: true, currentAccountAuthority: true,
  ...(platform === 'linux' ? { workerUid: process.getuid?.() ?? 0, workerGid: process.getgid?.() ?? 0 } : {}),
};
process.stdout.write(`${JSON.stringify(identity)}\n`);
process.env.KRISTIN_WORKER_SESSION_ID = sessionId;
process.env.KRISTIN_RESTRICTED_WORKER = '0';
process.env.KRISTIN_OWNER_RISK_QA = '1';
process.env.KRISTIN_P1A_DENIAL_PROBE_REQUIRED = '0';
process.chdir(path.resolve(policy.workingDirectory));
await runCli();
'''


def patch_adapter(root: pathlib.Path) -> None:
    path = root / "lib/product/p2_p1_authority_adapter.dart"
    source = path.read_text(encoding="utf-8")
    anchor = "abstract interface class P2CompletionEligibleAuthority {\n"
    require_once(source, anchor, "runtime authority interface insertion")
    insertion = """abstract interface class P2RuntimeAuthority
    implements
        P2AutomationEnvelopeAuthority,
        P2ProtectedAutomationBootstrapProvider,
        P2RestrictedWorkerIdentitySink,
        P2CompletionEligibleAuthority {
  bool get qaPreview;
  Map<String, Object?>? lastAuthorityObservation(String taskId);
}

"""
    source = source.replace(anchor, insertion + anchor, 1)
    qa_anchor = "  bool get qaPreview => _qaPreview;"
    require_once(source, qa_anchor, "isolated adapter qaPreview override")
    source = source.replace(qa_anchor, "  @override\n  bool get qaPreview => _qaPreview;", 1)
    observation_anchor = "  Map<String, Object?>? lastAuthorityObservation(String taskId) =>\n      _observations[taskId];"
    require_once(source, observation_anchor, "isolated adapter authority observation override")
    source = source.replace(observation_anchor, "  @override\n  Map<String, Object?>? lastAuthorityObservation(String taskId) =>\n      _observations[taskId];", 1)
    old = """final class P2IsolatedP1AuthorityAdapter
    implements
        P2AutomationEnvelopeAuthority,
        P2ProtectedAutomationBootstrapProvider,
        P2RestrictedWorkerIdentitySink,
        P2CompletionEligibleAuthority {
"""
    new = """final class P2IsolatedP1AuthorityAdapter implements P2RuntimeAuthority {
"""
    require_once(source, old, "P2 runtime authority implementation")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def patch_shared_p1a_contract(root: pathlib.Path) -> None:
    path = root / "tool/p2_shared_p1_authority_contract_test.py"
    source = path.read_text(encoding="utf-8")
    old = "ap=argparse.ArgumentParser();ap.add_argument('--project',default='.');ap.add_argument('--allow-unmerged-fixture',action='store_true');a=ap.parse_args();root=pathlib.Path(a.project).resolve()"
    new = "ap=argparse.ArgumentParser();ap.add_argument('--project',default='.');ap.add_argument('--allow-unmerged-fixture',action='store_true');ap.add_argument('--owner-risk-qa',action='store_true');a=ap.parse_args();root=pathlib.Path(a.project).resolve()"
    require_once(source, old, "owner-risk P1A contract CLI")
    source = source.replace(old, new, 1)
    old = "p1_impl=[x.name for x in (root/'lib/product').glob('p1_*.dart') if x.name not in {'p1_authority_service_contract_v1.dart','p1_authority_service_product_runtime_v1.dart'}]\n require(not p1_impl,f'P2 carries concrete P1 implementation: {p1_impl}')"
    new = "allowed_p1a={'p1_authority_service_contract_v1.dart','p1_authority_service_product_runtime_v1.dart','p1_authority_service_native_connector_v2.dart'}\n p1_impl=[x.name for x in (root/'lib/product').glob('p1_*.dart') if x.name not in allowed_p1a]\n require(not p1_impl,f'P2 carries unexpected concrete P1 implementation: {p1_impl}')\n connector=root/'lib/product/p1_authority_service_native_connector_v2.dart'\n require(connector.is_file() and 'P1AuthorityNativeConnectorV2' in connector.read_text(errors='ignore'),'reviewed merged P1A native connector missing or invalid')"
    require_once(source, old, "owner-risk reviewed P1A dependency allowlist")
    source = source.replace(old, new, 1)
    old = "if not a.allow_unmerged_fixture:\n  manifest=root/'release/evidence/P1A/manifest.json';require(manifest.is_file(),'merged P1A evidence missing')\n  data=json.loads(manifest.read_text());require(data.get('status')=='passed' and data.get('completionClaim') is True and data.get('p2DependencySatisfied') is True,'P1A is not merged/completion eligible')\n print('P2 isolated P1A-service dependency contract: PASS');return 0"
    new = "manifest=root/'release/evidence/P1A/manifest.json'\n if a.owner_risk_qa:\n  require(manifest.is_file(),'merged P1A source manifest missing')\n  data=json.loads(manifest.read_text());require(data.get('phase')=='P1A' and data.get('schemaVersion') in {'3.0.0','4.0.0'},'merged P1A source manifest invalid')\n  require((root/'authority_service/native/windows/authority_service_windows.cpp').is_file() and (root/'authority_service/native/macos/authority_service_macos.mm').is_file() and (root/'authority_service/native/linux/authority_service_linux.cpp').is_file(),'tri-platform merged P1A source missing')\n elif not a.allow_unmerged_fixture:\n  require(manifest.is_file(),'merged P1A evidence missing')\n  data=json.loads(manifest.read_text());require(data.get('status')=='passed' and data.get('completionClaim') is True and data.get('p2DependencySatisfied') is True,'P1A is not merged/completion eligible')\n print('P2 isolated P1A-service dependency contract: PASS'+(' (owner-risk QA source dependency)' if a.owner_risk_qa else ''));return 0"
    require_once(source, old, "owner-risk source-only P1A dependency mode")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")



def patch_automation_envelope_validation(root: pathlib.Path) -> None:
    path = root / "lib/product/p2_automation_host.dart"
    source = path.read_text(encoding="utf-8")
    old = """    if ((auditCheckpoint['id'] ?? '').toString().isEmpty ||
        !hex.hasMatch('${auditCheckpoint['digest'] ?? ''}') ||
        authority['authorityKind'] != 'p1-isolated-authority-service-v2' ||
        authority['p2CanIssueGrants'] != false ||
        authority['workerCanIssue'] != false ||
        authority['osEnforcedIsolation'] != true ||
        authority['workerDeniedByOs'] != true ||
        authority['workerIdentitySha256'] !=
            authenticatedIpc['workerIdentitySha256'] ||
"""
    new = """    final ownerRiskQa = authority['ownerRiskQa'] == true;
    final authorityModeValid = ownerRiskQa
        ? authority['authorityKind'] == 'p2-owner-risk-current-account-v1' &&
            authority['sharedP1ControlPlane'] == false &&
            authority['securityEvidenceWaived'] == true &&
            authority['osEnforcedIsolation'] == false &&
            authority['workerDeniedByOs'] == false &&
            workerIdentity['principalType'] == 'owner-risk-current-account' &&
            workerIdentity['ownerRiskQa'] == true &&
            workerIdentity['osIsolationWaived'] == true &&
            workerIdentity['currentAccountAuthority'] == true &&
            workerIdentity['authorityConnectionDenied'] == false &&
            workerIdentity['authorityDenialCode'] == 'owner_risk_waived'
        : authority['authorityKind'] == 'p1-isolated-authority-service-v2' &&
            authority['sharedP1ControlPlane'] == true &&
            authority['osEnforcedIsolation'] == true &&
            authority['workerDeniedByOs'] == true;
    if ((auditCheckpoint['id'] ?? '').toString().isEmpty ||
        !hex.hasMatch('${auditCheckpoint['digest'] ?? ''}') ||
        !authorityModeValid ||
        authority['p2CanIssueGrants'] != false ||
        authority['workerCanIssue'] != false ||
        authority['workerIdentitySha256'] !=
            authenticatedIpc['workerIdentitySha256'] ||
"""
    require_once(source, old, "owner-risk automation envelope authority validation")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")

def patch_runtime_integration(root: pathlib.Path) -> None:
    path = root / "lib/product/p2_product_runtime_integration.dart"
    source = path.read_text(encoding="utf-8")
    if source.count("P2IsolatedP1AuthorityAdapter") != 2:
        raise SystemExit("ERROR: P2 runtime authority type anchors changed")
    source = source.replace("P2IsolatedP1AuthorityAdapter", "P2RuntimeAuthority")
    require_once(source, "    if (!(authority.completionEligible || authority.qaPreview) ||\n        authority.authorityKind != 'p1-isolated-authority-service-v2') {\n      throw StateError('fixture_or_non_p1_authority_rejected');\n    }\n", "owner-risk runtime authority acceptance")
    source = source.replace("    if (!(authority.completionEligible || authority.qaPreview) ||\n        authority.authorityKind != 'p1-isolated-authority-service-v2') {\n      throw StateError('fixture_or_non_p1_authority_rejected');\n    }\n", "    final productionAuthority = authority.completionEligible &&\n        authority.authorityKind == 'p1-isolated-authority-service-v2';\n    final ownerRiskAuthority = authority.qaPreview &&\n        !authority.completionEligible &&\n        authority.authorityKind == 'p2-owner-risk-current-account-v1' &&\n        authority.authorityProvenance['securityEvidenceWaived'] == true;\n    if (!(productionAuthority || ownerRiskAuthority)) {\n      throw StateError('fixture_or_unapproved_authority_rejected');\n    }\n", 1)
    source = source.replace(
        "'fixtureAuthorityEligible': false,",
        "'fixtureAuthorityEligible': false,\n        'ownerRiskQa': authority.qaPreview,",
        1,
    )
    path.write_text(source, encoding="utf-8")


def patch_bootstrap(root: pathlib.Path) -> None:
    path = root / "lib/product/p2_product_runtime_bootstrap.dart"
    source = path.read_text(encoding="utf-8")
    import_anchor = "import 'p2_owner_workspace.dart';\n"
    require_once(source, import_anchor, "owner-risk import")
    source = source.replace(import_anchor, import_anchor + "import 'p2_owner_risk_authority.dart';\n", 1)
    old = """      if (p1AuthorityService == null) {
        throw StateError('merged_p1a_service_unavailable');
      }
      const qaPreviewBuild = bool.fromEnvironment(
        'KRISTIN_QA_PREVIEW',
        defaultValue: false,
      );
      final qaPreview = qaPreviewBuild &&
          p1AuthorityService.service.provenance['qaPreview'] == true;
      p1AuthorityService.validateForP2(allowQaPreview: qaPreview);
      final resolver = resourceResolver ??
"""
    new = """      const ownerRiskQa = bool.fromEnvironment(
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
"""
    require_once(source, old, "P2 owner-risk bootstrap boundary")
    source = source.replace(old, new, 1)
    old_authority = """      final authority = P2IsolatedP1AuthorityAdapter(
        p1AuthorityService,
        qaPreview: qaPreview,
      );
"""
    new_authority = """      final P2RuntimeAuthority authority = ownerRiskQa
          ? P2OwnerRiskQaAuthority()
          : P2IsolatedP1AuthorityAdapter(
              p1AuthorityService!,
              qaPreview: qaPreview,
            );
"""
    require_once(source, old_authority, "P2 owner-risk authority selection")
    source = source.replace(old_authority, new_authority, 1)
    # Dart formatting changed this call from a compact single line to a
    # multi-line invocation. Match the syntax rather than exact whitespace so
    # the owner-risk patch is stable across supported Dart formatter versions.
    env_pattern = re.compile(
        r"(?m)^(?P<indent>[ \t]*)additionalEnvironment\s*:\s*"
        r"_validatedProvisionedEnvironment\(\s*"
        r"explicitlyProvisionedEnvironment\s*,?\s*\)\s*,\s*$"
    )
    matches = list(env_pattern.finditer(source))
    if len(matches) != 1:
        raise SystemExit(
            "ERROR: P2 owner-risk worker environment: expected exactly one "
            f"syntax anchor, found {len(matches)}"
        )
    indent = matches[0].group("indent")
    child = indent + "  "
    new_env = (
        f"{indent}additionalEnvironment: <String, String>{{\n"
        f"{child}..._validatedProvisionedEnvironment(\n"
        f"{child}  explicitlyProvisionedEnvironment,\n"
        f"{child}),\n"
        f"{child}if (ownerRiskQa) 'KRISTIN_OWNER_RISK_QA': '1',\n"
        f"{indent}}},"
    )
    source = env_pattern.sub(new_env, source, count=1)
    source = source.replace(
        "      'RUNNER_NAME',\n",
        "      'RUNNER_NAME',\n      'KRISTIN_OWNER_RISK_QA',\n",
        1,
    )
    path.write_text(source, encoding="utf-8")


def patch_process_client(root: pathlib.Path) -> None:
    path = root / "lib/product/p2_automation_host_process_client.dart"
    source = path.read_text(encoding="utf-8")
    old = """      'KRISTIN_WORKER_SESSION_ID': workerSessionId,
    };
    final process = await Process.start(
      config.restrictedWorkerLauncher,
      <String>[
        '--policy',
        config.workerPolicy,
        '--session',
        workerSessionId,
      ],
"""
    new = """      'KRISTIN_WORKER_SESSION_ID': workerSessionId,
      if (config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] case final value?)
        'KRISTIN_OWNER_RISK_QA': value,
    };
    final ownerRiskQa =
        config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';
    final process = await Process.start(
      ownerRiskQa ? config.nodeExecutable : config.restrictedWorkerLauncher,
      <String>[
        if (ownerRiskQa) config.restrictedWorkerLauncher,
        '--policy',
        config.workerPolicy,
        '--session',
        workerSessionId,
      ],
"""
    require_once(source, old, "owner-risk worker process launch")
    source = source.replace(old, new, 1)

    old_identity_handler = """        if (identity['authorityConnectionDenied'] == true &&
            identity['authorityDenialCode'] == 'worker_principal_denied' &&
            !_workerAuthorityDenial.isCompleted) {
          _workerAuthorityDenial.complete(<String, Object?>{
            'authorityConnectionDenied': true,
            'authorityDenialCode': 'worker_principal_denied',
            'authorityDenialObservedBy': 'restricted-launcher',
          });
        }
"""
    new_identity_handler = """        final ownerRiskQa =
            _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';
        if (!_workerAuthorityDenial.isCompleted &&
            ((!ownerRiskQa &&
                    identity['authorityConnectionDenied'] == true &&
                    identity['authorityDenialCode'] ==
                        'worker_principal_denied') ||
                (ownerRiskQa &&
                    identity['authorityConnectionDenied'] == false &&
                    identity['authorityDenialCode'] == 'owner_risk_waived' &&
                    identity['ownerRiskQa'] == true &&
                    identity['osIsolationWaived'] == true))) {
          _workerAuthorityDenial.complete(<String, Object?>{
            'authorityConnectionDenied': ownerRiskQa ? false : true,
            'authorityDenialCode': ownerRiskQa
                ? 'owner_risk_waived'
                : 'worker_principal_denied',
            'authorityDenialObservedBy': ownerRiskQa
                ? 'owner-risk-waiver'
                : 'restricted-launcher',
            if (ownerRiskQa) 'ownerRiskQa': true,
            if (ownerRiskQa) 'osIsolationWaived': true,
            if (ownerRiskQa) 'currentAccountAuthority': true,
          });
        }
"""
    require_once(source, old_identity_handler, "owner-risk identity waiver completion")
    source = source.replace(old_identity_handler, new_identity_handler, 1)

    old_ready = """    if (type == 'ready') {
      if (message['executorOnly'] != true ||
          message['grantIssuer'] != false ||
          message['authenticatedIpcRequired'] != true ||
          message['desktopIssuedEffectPermitRequired'] != true ||
          message['publicVerifierOnly'] != true ||
          message['rawAuthorityKeysPresent'] != false ||
          message['restrictedWorkerPrincipal'] != true ||
          message['workerSessionId'] != _expectedWorkerSessionId ||
          message['pid'] != _workerIdentityValue['pid']) {
"""
    new_ready = """    if (type == 'ready') {
      final ownerRiskQa =
          _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';
      final principalReady = ownerRiskQa
          ? message['restrictedWorkerPrincipal'] == false &&
              message['ownerRiskCurrentAccount'] == true &&
              message['osIsolationWaived'] == true
          : message['restrictedWorkerPrincipal'] == true;
      if (message['executorOnly'] != true ||
          message['grantIssuer'] != false ||
          message['authenticatedIpcRequired'] != true ||
          message['desktopIssuedEffectPermitRequired'] != true ||
          message['publicVerifierOnly'] != true ||
          message['rawAuthorityKeysPresent'] != false ||
          !principalReady ||
          message['workerSessionId'] != _expectedWorkerSessionId ||
          message['pid'] != _workerIdentityValue['pid']) {
"""
    require_once(source, old_ready, "owner-risk ready contract")
    source = source.replace(old_ready, new_ready, 1)

    old_validate = """    final expectedPrincipal = Platform.isWindows
        ? 'appcontainer'
        : Platform.isMacOS
            ? 'signed-app-sandbox-helper'
            : 'dedicated-uid';
"""
    new_validate = """    final ownerRiskQa =
        _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';
    final expectedPrincipal = ownerRiskQa
        ? 'owner-risk-current-account'
        : Platform.isWindows
            ? 'appcontainer'
            : Platform.isMacOS
                ? 'signed-app-sandbox-helper'
                : 'dedicated-uid';
"""
    require_once(source, old_validate, "owner-risk expected principal")
    source = source.replace(old_validate, new_validate, 1)

    source = source.replace(
        """    if (Platform.isLinux &&
        (message['workerUid'] is! int ||
            message['workerGid'] is! int ||
            message['noNewPrivileges'] != true ||
            message['namespaceIsolation'] != true)) {
""",
        """    if (!ownerRiskQa &&
        Platform.isLinux &&
        (message['workerUid'] is! int ||
            message['workerGid'] is! int ||
            message['noNewPrivileges'] != true ||
            message['namespaceIsolation'] != true)) {
""",
        1,
    )
    source = source.replace(
        """    if (Platform.isWindows &&
        ((message['workerSid']?.toString().isEmpty ?? true) ||
            message['jobObjectBound'] != true)) {
""",
        """    if (!ownerRiskQa &&
        Platform.isWindows &&
        ((message['workerSid']?.toString().isEmpty ?? true) ||
            message['jobObjectBound'] != true)) {
""",
        1,
    )
    source = source.replace(
        """    if (Platform.isMacOS &&
        ((message['codeDirectoryHash']?.toString().isEmpty ?? true) ||
            message['appSandbox'] != true ||
            message['authorityClientEntitlement'] != false)) {
""",
        """    if (!ownerRiskQa &&
        Platform.isMacOS &&
        ((message['codeDirectoryHash']?.toString().isEmpty ?? true) ||
            message['appSandbox'] != true ||
            message['authorityClientEntitlement'] != false)) {
""",
        1,
    )
    denial_block = """    final denial = message['authorityConnectionDenied'];
    final denialCode = message['authorityDenialCode'];
    if (denial != null &&
        (denial != true || denialCode != 'worker_principal_denied')) {
      throw const P2AutomationHostException(
        'restricted_worker_authority_denial_invalid',
      );
    }
"""
    waiver_block = """    final denial = message['authorityConnectionDenied'];
    final denialCode = message['authorityDenialCode'];
    if (ownerRiskQa) {
      if (message['ownerRiskQa'] != true ||
          message['osIsolationWaived'] != true ||
          message['currentAccountAuthority'] != true ||
          denial != false ||
          denialCode != 'owner_risk_waived') {
        throw const P2AutomationHostException(
          'owner_risk_worker_waiver_invalid',
        );
      }
    } else if (denial != null &&
        (denial != true || denialCode != 'worker_principal_denied')) {
      throw const P2AutomationHostException(
        'restricted_worker_authority_denial_invalid',
      );
    }
"""
    require_once(source, denial_block, "owner-risk denial waiver validation")
    source = source.replace(denial_block, waiver_block, 1)

    finalize_block = """    if (merged['authorityConnectionDenied'] != true ||
        merged['authorityDenialCode'] != 'worker_principal_denied') {
      throw const P2AutomationHostException(
        'restricted_worker_authority_denial_unproved',
      );
    }
"""
    finalize_waiver = """    final ownerRiskQa =
        _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';
    if (ownerRiskQa) {
      if (merged['authorityConnectionDenied'] != false ||
          merged['authorityDenialCode'] != 'owner_risk_waived' ||
          merged['authorityDenialObservedBy'] != 'owner-risk-waiver' ||
          merged['ownerRiskQa'] != true ||
          merged['osIsolationWaived'] != true ||
          merged['currentAccountAuthority'] != true) {
        throw const P2AutomationHostException(
          'owner_risk_worker_waiver_unproved',
        );
      }
    } else if (merged['authorityConnectionDenied'] != true ||
        merged['authorityDenialCode'] != 'worker_principal_denied') {
      throw const P2AutomationHostException(
        'restricted_worker_authority_denial_unproved',
      );
    }
"""
    require_once(source, finalize_block, "owner-risk finalized identity waiver")
    source = source.replace(finalize_block, finalize_waiver, 1)
    path.write_text(source, encoding="utf-8")


def patch_runtime_resolver(root: pathlib.Path) -> None:
    path = root / "lib/product/p2_runtime_resource_resolver.dart"
    source = path.read_text(encoding="utf-8")
    old = """    if (decoded is! Map ||
        decoded['schemaVersion'] != '3.0.0' ||
"""
    new = """    const ownerRiskQa = bool.fromEnvironment(
      'KRISTIN_OWNER_RISK_QA',
      defaultValue: false,
    );
    if (decoded is! Map ||
        decoded['schemaVersion'] != '3.0.0' ||
"""
    require_once(source, old, "runtime owner-risk flag")
    source = source.replace(old, new, 1)
    old_flags = """        decoded['authorityServiceExternal'] != true ||
        decoded['authorityServiceExecutableStaged'] != false ||
        decoded['authorityBrokerStaged'] != false ||
        decoded['rawAuthoritySecretsIncluded'] != false ||
        decoded['p2DelegationOnly'] != true ||
        decoded['restrictedWorkerLauncherExternal'] != true ||
        decoded['restrictedWorkerLauncherOsEnforced'] != true) {
"""
    new_flags = """        decoded['authorityServiceExecutableStaged'] != false ||
        decoded['authorityBrokerStaged'] != false ||
        decoded['rawAuthoritySecretsIncluded'] != false ||
        decoded['p2DelegationOnly'] != true ||
        (!ownerRiskQa && decoded['authorityServiceExternal'] != true) ||
        (ownerRiskQa && decoded['authorityServiceExternal'] != false) ||
        (!ownerRiskQa && decoded['restrictedWorkerLauncherExternal'] != true) ||
        (ownerRiskQa && decoded['restrictedWorkerLauncherExternal'] != false) ||
        (!ownerRiskQa && decoded['restrictedWorkerLauncherOsEnforced'] != true) ||
        (ownerRiskQa && decoded['restrictedWorkerLauncherOsEnforced'] != false) ||
        (ownerRiskQa && decoded['ownerRiskQa'] != true)) {
"""
    require_once(source, old_flags, "runtime owner-risk manifest")
    source = source.replace(old_flags, new_flags, 1)
    source = source.replace(
        "      'RUNNER_NAME',\n",
        "      'RUNNER_NAME',\n      'KRISTIN_OWNER_RISK_QA',\n",
        1,
    )
    path.write_text(source, encoding="utf-8")


def patch_host_js(root: pathlib.Path) -> None:
    auth = root / "automation_host/src/authenticated-ipc.mjs"
    source = auth.read_text(encoding="utf-8")
    old = """  const signature = Buffer.from(permit.signatureBase64, 'base64');
  const publicKey = publicKeyFromSpki(verifier.publicKeySpkiBase64);
  if (!crypto.verify('sha256', canonicalBytes(unsigned), publicKey, signature)) {
    throw new Error('effect_permit_signature_invalid');
  }
"""
    new = """  if (process.env.KRISTIN_OWNER_RISK_QA !== '1') {
    const signature = Buffer.from(permit.signatureBase64, 'base64');
    const publicKey = publicKeyFromSpki(verifier.publicKeySpkiBase64);
    if (!crypto.verify('sha256', canonicalBytes(unsigned), publicKey, signature)) {
      throw new Error('effect_permit_signature_invalid');
    }
  }
"""
    require_once(source, old, "owner-risk effect permit verification")
    source = source.replace(old, new, 1)
    old_authority = """  if (auth.authority?.sharedP1ControlPlane !== true ||
      auth.authority?.workerCanIssue !== false ||
      auth.authority?.authorityKind !== 'p1-isolated-authority-service-v2' ||
      auth.authority?.workerIdentitySha256 !== auth.authenticatedIpc?.workerIdentitySha256 ||
      typeof auth.authority?.instanceId !== 'string' ||
      auth.authority.instanceId.length === 0) {
    throw new Error('shared_authority_record_invalid');
  }
"""
    new_authority = """  const ownerRiskQa = auth.authority?.ownerRiskQa === true;
  const authorityModeValid = ownerRiskQa
    ? auth.authority?.sharedP1ControlPlane === false &&
      auth.authority?.authorityKind === 'p2-owner-risk-current-account-v1' &&
      auth.authority?.securityEvidenceWaived === true &&
      auth.authority?.osEnforcedIsolation === false &&
      auth.authority?.workerDeniedByOs === false
    : auth.authority?.sharedP1ControlPlane === true &&
      auth.authority?.authorityKind === 'p1-isolated-authority-service-v2';
  if (!authorityModeValid ||
      auth.authority?.workerCanIssue !== false ||
      auth.authority?.workerIdentitySha256 !== auth.authenticatedIpc?.workerIdentitySha256 ||
      typeof auth.authority?.instanceId !== 'string' ||
      auth.authority.instanceId.length === 0) {
    throw new Error('shared_authority_record_invalid');
  }
"""
    require_once(source, old_authority, "owner-risk authenticated authority record")
    auth.write_text(source.replace(old_authority, new_authority, 1), encoding="utf-8")

    host = root / "automation_host/src/host.mjs"
    source = host.read_text(encoding="utf-8")
    require_once(source, "async function runCli() {", "export runCli")
    source = source.replace("async function runCli() {", "export async function runCli() {", 1)
    old_ready = """          restrictedWorkerPrincipal: process.env.KRISTIN_RESTRICTED_WORKER === '1',
          workerSessionId: process.env.KRISTIN_WORKER_SESSION_ID ?? '',
"""
    new_ready = """          restrictedWorkerPrincipal:
            process.env.KRISTIN_OWNER_RISK_QA === '1'
              ? false
              : process.env.KRISTIN_RESTRICTED_WORKER === '1',
          ownerRiskCurrentAccount: process.env.KRISTIN_OWNER_RISK_QA === '1',
          osIsolationWaived: process.env.KRISTIN_OWNER_RISK_QA === '1',
          workerSessionId: process.env.KRISTIN_WORKER_SESSION_ID ?? '',
"""
    require_once(source, old_ready, "owner-risk ready metadata")
    host.write_text(source.replace(old_ready, new_ready, 1), encoding="utf-8")

    launcher = root / "automation_host/src/owner-risk-launcher.mjs"
    launcher.write_text(OWNER_RISK_LAUNCHER, encoding="utf-8")
    launcher.chmod(0o755)

    owner_risk_test = root / "automation_host/src/owner-risk-authenticated-ipc.test.mjs"
    owner_risk_test.write_text("""import test from 'node:test';
import assert from 'node:assert/strict';
import { createTestAuthority } from './test-authority.mjs';
import { createAuthenticatedIpcVerifier, digest } from './authenticated-ipc.mjs';

test('owner-risk authorization is explicit, current-account, and security-ineligible', () => {
  process.env.KRISTIN_OWNER_RISK_QA = '1';
  const fixture = createTestAuthority();
  const bootstrap = fixture.bootstrap();
  const envelope = structuredClone(fixture.next('host.supportMatrix', { operation: 'host.supportMatrix' }));
  const workerIdentity = {
    schemaVersion: '2.0.0', platform: 'linux',
    principalType: 'owner-risk-current-account',
    sessionId: bootstrap.workerSessionId, pid: 43210,
    startToken: 'owner-risk-test',
    launcherSha256: '1'.repeat(64), nodeSha256: '2'.repeat(64),
    hostScriptSha256: '3'.repeat(64), workerPolicySha256: '4'.repeat(64),
    authorityConnectionDenied: false,
    authorityDenialCode: 'owner_risk_waived',
    authorityDenialObservedBy: 'owner-risk-waiver',
    ownerRiskQa: true, osIsolationWaived: true, currentAccountAuthority: true,
    workerUid: 1000, workerGid: 1000,
  };
  const workerIdentitySha256 = digest(workerIdentity);
  envelope.authorization.workerIdentity = { ...workerIdentity, identitySha256: workerIdentitySha256 };
  envelope.authorization.workerIdentitySha256 = workerIdentitySha256;
  envelope.authorization.authenticatedIpc.workerIdentitySha256 = workerIdentitySha256;
  envelope.authorization.authority = {
    authorityKind: 'p2-owner-risk-current-account-v1',
    sharedP1ControlPlane: false,
    p2CanIssueGrants: false,
    workerCanIssue: false,
    osEnforcedIsolation: false,
    workerDeniedByOs: false,
    securityEvidenceWaived: true,
    ownerRiskQa: true,
    workerIdentitySha256,
    instanceId: 'owner-risk-local-authority',
    implementationSha256: '5'.repeat(64),
    runtimeBuildSha256: '6'.repeat(64),
  };
  envelope.effectPermit.workerIdentitySha256 = workerIdentitySha256;
  envelope.effectPermit.sharedAuthorityInstanceId = 'owner-risk-local-authority';
  envelope.effectPermit.authorizationSha256 = digest(envelope.authorization);
  envelope.effectPermit.signatureBase64 = 'A'.repeat(96);
  const verify = createAuthenticatedIpcVerifier({
    permitVerifier: bootstrap.permitVerifier,
    channelId: bootstrap.channelId,
    workerSessionId: bootstrap.workerSessionId,
    ...bootstrap.authorityState,
  });
  const verified = verify(envelope);
  assert.equal(verified.authorization.authority.authorityKind, 'p2-owner-risk-current-account-v1');
  assert.equal(verified.authorization.authority.securityEvidenceWaived, true);
  assert.equal(verified.authorization.authority.osEnforcedIsolation, false);
  assert.equal(verified.authorization.authority.workerDeniedByOs, false);
  delete process.env.KRISTIN_OWNER_RISK_QA;
});
""", encoding="utf-8")


def patch_banner(root: pathlib.Path) -> None:
    path = root / "lib/product/p2_app_shell.dart"
    source = path.read_text(encoding="utf-8")
    old = "message: 'QA PREVIEW — NOT RELEASE COMPLETE',"
    new = "message: 'OWNER-RISK QA — SECURITY EVIDENCE WAIVED',"
    require_once(source, old, "owner-risk banner")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def write_contracts(root: pathlib.Path) -> None:
    (root / "lib/product/p2_owner_risk_authority.dart").write_text(
        OWNER_RISK_AUTHORITY,
        encoding="utf-8",
    )
    config = {
        "schemaVersion": "1.0.0",
        "mode": "owner-risk-tri-platform-qa",
        "formalSecurityCompletion": False,
        "productionReleaseEligible": False,
        "qaShipmentEligibleAfterTriPlatformPass": True,
        "allPlatformsRequired": ["windows", "macos", "linux"],
        "externalEvidenceTrustRequired": False,
        "rootOrAdministratorAuthorityAccepted": True,
        "requiresDartDefine": "KRISTIN_OWNER_RISK_QA=true",
        "warning": "This mode waives P1A isolation/evidence security only; it does not waive platform build or QA failures.",
    }
    (root / "config/p1_p2_owner_risk_qa.v1.json").write_text(
        json.dumps(config, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (root / "OWNER_RISK_QA_SHIPMENT.md").write_text(
        "# Owner-Risk Tri-Platform QA Shipment\n\n"
        "This build enables P1/P2 functional QA on Windows, macOS, and Linux without "
        "external evidence-signing infrastructure. It runs with the authority of the "
        "current OS account (including root/administrator when launched that way). "
        "It is not a production-security completion claim. All three platform builds "
        "and runtime smoke tests remain mandatory.\n",
        encoding="utf-8",
    )
    test = root / "test/product/p2_owner_risk_contract_test.dart"
    test.write_text(
        """import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owner-risk QA mode is explicit and never overclaims security', () {
    final config = File('config/p1_p2_owner_risk_qa.v1.json').readAsStringSync();
    final authority = File('lib/product/p2_owner_risk_authority.dart').readAsStringSync();
    final bootstrap = File('lib/product/p2_product_runtime_bootstrap.dart').readAsStringSync();
    final host = File('automation_host/src/authenticated-ipc.mjs').readAsStringSync();
    expect(config, contains('"formalSecurityCompletion": false'));
    expect(config, contains('"productionReleaseEligible": false'));
    expect(config, contains('"qaShipmentEligibleAfterTriPlatformPass": true'));
    expect(authority, contains("'securityEvidenceWaived': true"));
    expect(authority, contains("authorityKind => 'p2-owner-risk-current-account-v1'"));
    expect(authority, contains("'authorityDenialCode': 'owner_risk_waived'"));
    expect(authority, contains('bool get completionEligible => false'));
    expect(bootstrap, contains("'KRISTIN_OWNER_RISK_QA': '1'"));
    expect(host, contains("process.env.KRISTIN_OWNER_RISK_QA !== '1'"));
  });
}
""",
        encoding="utf-8",
    )

    smoke = root / "test/product/p2_owner_risk_runtime_smoke_test.dart"
    smoke.write_text(
        """import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/p2_finite_command_service.dart';
import 'package:kristin_local_agent/product/p2_owner_mode.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_bootstrap.dart';
import 'package:kristin_local_agent/product/p2_runtime_resource_resolver.dart';

void main() {
  test('owner-risk P1/P2 runtime launches and performs host effects', () async {
    const enabled = bool.fromEnvironment(
      'KRISTIN_OWNER_RISK_QA',
      defaultValue: false,
    );
    expect(enabled, true, reason: 'owner-risk smoke requires dart define');
    String env(String name) {
      final value = Platform.environment[name] ?? '';
      if (value.isEmpty) fail('missing environment: $name');
      return value;
    }
    final runtimeRoot = Directory(env('KRISTIN_V70_RUNTIME_ROOT'));
    final dataRoot = await Directory.systemTemp.createTemp('kristin-v70-smoke-');
    final temporary = await Directory('${dataRoot.path}${Platform.pathSeparator}effects')
        .create(recursive: true);
    final manifest = File('${runtimeRoot.path}${Platform.pathSeparator}runtime-manifest.v3.json');
    expect(await manifest.exists(), true);
    final decoded = jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
    final identity = Map<String, Object?>.from(decoded['identity']! as Map);
    final resources = P2RuntimeResourceSet(
      root: runtimeRoot,
      manifestPath: manifest.path,
      manifestSha256: Sha256.hex(await manifest.readAsBytes()),
      sourceCommit: identity['sourceCommit']!.toString(),
      sourceTree: identity['sourceTree']!.toString(),
      runtimeBuildSha256: identity['runtimeBuildSha256']!.toString(),
      p1AuthorityServiceContractSha256:
          identity['p1AuthorityServiceContractSha256']!.toString(),
      nodeExecutable: env('KRISTIN_V70_NODE'),
      hostScript: env('KRISTIN_V70_HOST'),
      workingDirectory: env('KRISTIN_V70_HOST_ROOT'),
      restrictedWorkerLauncher: env('KRISTIN_V70_LAUNCHER'),
      restrictedWorkerLauncherSha256:
          Sha256.hex(await File(env('KRISTIN_V70_LAUNCHER')).readAsBytes()),
      workerPolicy: env('KRISTIN_V70_POLICY'),
      workerPolicySha256:
          Sha256.hex(await File(env('KRISTIN_V70_POLICY')).readAsBytes()),
      nodeExecutableSha256:
          Sha256.hex(await File(env('KRISTIN_V70_NODE')).readAsBytes()),
      hostScriptSha256:
          Sha256.hex(await File(env('KRISTIN_V70_HOST')).readAsBytes()),
      windowsJobHelper: Platform.environment['KRISTIN_V70_WINDOWS_HELPER'],
      posixWatchdog: Platform.environment['KRISTIN_V70_POSIX_WATCHDOG'],
      interactiveDesktopAdapter:
          Platform.environment['KRISTIN_V70_INTERACTIVE_ADAPTER'],
      provisionedEnvironment: const <String, String>{
        'KRISTIN_OWNER_RISK_QA': '1',
      },
    );
    final handle = await P2ProductRuntimeBootstrap.start(
      dataRoot: dataRoot,
      p1AuthorityService: null,
      runtimeResources: resources,
      explicitlyProvisionedEnvironment: const <String, String>{
        'KRISTIN_OWNER_RISK_QA': '1',
      },
      interactiveDesktopAttested: true,
    );
    expect(handle.available, true, reason: handle.failureCode);
    final owner = handle.runtime!;
    expect(owner.authority.qaPreview, true);
    handle.activateEffectContext(runId: 'v70-smoke', taskId: 'P2-QA');
    await owner.controller.enable(
      unattended: true,
      approvalPolicy: P2OwnerApprovalPolicy.destructiveOnly,
      acknowledged: true,
    );
    final supportBinding = owner.bindingContext.bindingFor('host.supportMatrix');
    final supportEnvelope = await owner.authority.issue(
      binding: supportBinding,
      operation: 'host.supportMatrix',
      payload: const <String, Object?>{'operation': 'host.supportMatrix'},
    );
    final support = await owner.composition.client.invoke(supportEnvelope);
    expect(support['status'], 'ok');

    final fs = owner.composition.filesystemService(
      Directory('${dataRoot.path}${Platform.pathSeparator}backups'),
    );
    final target = File('${temporary.path}${Platform.pathSeparator}owner-risk-λ.txt');
    await fs.write(
      target.path,
      Uint8List.fromList(utf8.encode('KRISTIN_OWNER_RISK_QA')),
      binding: owner.bindingContext.bindingFor('write'),
    );
    final read = await fs.read(
      target.path,
      binding: owner.bindingContext.bindingFor('read'),
      maxBytes: 65536,
    );
    expect(utf8.decode(read), 'KRISTIN_OWNER_RISK_QA');

    final command = await owner.composition.commandService.run(
      P2CommandSpec(
        executable: env('KRISTIN_V70_NODE'),
        cwd: temporary.path,
        arguments: const <String>['-e', "process.stdout.write('V70_OK')"],
        deadline: const Duration(seconds: 20),
      ),
      binding: owner.bindingContext.bindingFor('command.run'),
    );
    expect(utf8.decode(command.stdout), 'V70_OK');
    await handle.close();
    await dataRoot.delete(recursive: true);
  },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: const bool.fromEnvironment(
      'KRISTIN_OWNER_RISK_QA',
      defaultValue: false,
    )
        ? false
        : 'requires staged owner-risk runtime',
  );
}
""",
        encoding="utf-8",
    )



def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()
    required = (
        "lib/product/p2_p1_authority_adapter.dart",
        "lib/product/p2_product_runtime_bootstrap.dart",
        "lib/product/p2_product_runtime_integration.dart",
        "lib/product/p2_automation_host_process_client.dart",
        "lib/product/p2_runtime_resource_resolver.dart",
        "lib/product/p2_app_shell.dart",
        "automation_host/src/authenticated-ipc.mjs",
        "automation_host/src/host.mjs",
    )
    for relative in required:
        if not (root / relative).is_file():
            raise SystemExit(f"ERROR: required owner-risk source missing: {relative}")
    patch_adapter(root)
    write_contracts(root)
    patch_source_inventory(root)
    patch_shared_p1a_contract(root)
    patch_automation_envelope_validation(root)
    patch_runtime_integration(root)
    patch_bootstrap(root)
    patch_process_client(root)
    patch_runtime_resolver(root)
    patch_host_js(root)
    patch_banner(root)
    print(json.dumps({
        "schemaVersion": "1.0.0",
        "status": "passed",
        "mode": "owner-risk-tri-platform-qa",
        "allPlatformsRequired": ["windows", "macos", "linux"],
        "externalEvidenceTrustRequired": False,
        "completionClaim": False,
        "qaShipmentEligibleAfterTriPlatformPass": True,
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
