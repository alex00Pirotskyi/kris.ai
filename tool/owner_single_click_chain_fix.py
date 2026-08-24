#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def rep(path: str, old: str, new: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, got {count}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


rep(
    'lib/product/p2_owner_risk_authority.dart',
    "  void bindRestrictedWorkerIdentity(Map<String, Object?> identity) {\n    if (identity['schemaVersion'] != '2.0.0' ||\n        identity['sessionId'] != _workerSessionId ||\n        identity['principalType'] != 'owner-risk-current-account' ||\n        identity['ownerRiskQa'] != true ||\n        identity['osIsolationWaived'] != true ||\n        identity['currentAccountAuthority'] != true ||\n        identity['authorityConnectionDenied'] != false ||\n        identity['authorityDenialCode'] != 'owner_risk_waived' ||\n        (identity['identitySha256']?.toString().isEmpty ?? true)) {\n      throw StateError('owner_risk_worker_identity_invalid');\n    }",
    "  void bindRestrictedWorkerIdentity(Map<String, Object?> identity) {\n    final expectedPrincipal = productCurrentAccount\n        ? 'current-account-owner'\n        : 'owner-risk-current-account';\n    final expectedDenialCode = productCurrentAccount\n        ? 'current_account_unisolated'\n        : 'owner_risk_waived';\n    if (identity['schemaVersion'] != '2.0.0' ||\n        identity['sessionId'] != _workerSessionId ||\n        identity['principalType'] != expectedPrincipal ||\n        identity['ownerRiskQa'] != !productCurrentAccount ||\n        identity['productCurrentAccount'] != productCurrentAccount ||\n        identity['osIsolationWaived'] != true ||\n        identity['currentAccountAuthority'] != true ||\n        identity['authorityConnectionDenied'] != false ||\n        identity['authorityDenialCode'] != expectedDenialCode ||\n        (identity['identitySha256']?.toString().isEmpty ?? true)) {\n      throw StateError('owner_risk_worker_identity_invalid');\n    }",
)

rep(
    'lib/product/p2_automation_host.dart',
    "    final ownerRiskQa = authority['ownerRiskQa'] == true;\n    final authorityModeValid = ownerRiskQa\n        ? authority['authorityKind'] == 'p2-owner-risk-current-account-v1' &&\n            authority['sharedP1ControlPlane'] == false &&\n            authority['securityEvidenceWaived'] == true &&\n            authority['osEnforcedIsolation'] == false &&\n            authority['workerDeniedByOs'] == false &&\n            workerIdentity['principalType'] == 'owner-risk-current-account' &&\n            workerIdentity['ownerRiskQa'] == true &&\n            workerIdentity['osIsolationWaived'] == true &&\n            workerIdentity['currentAccountAuthority'] == true &&\n            workerIdentity['authorityConnectionDenied'] == false &&\n            workerIdentity['authorityDenialCode'] == 'owner_risk_waived'\n        : authority['authorityKind'] == 'p1-isolated-authority-service-v2' &&\n            authority['sharedP1ControlPlane'] == true &&\n            authority['osEnforcedIsolation'] == true &&\n            authority['workerDeniedByOs'] == true;",
    "    final ownerRiskQa = authority['ownerRiskQa'] == true;\n    final productCurrentAccount = authority['productCurrentAccount'] == true;\n    final localCurrentAccountBase =\n        authority['sharedP1ControlPlane'] == false &&\n        authority['securityEvidenceWaived'] == true &&\n        authority['osEnforcedIsolation'] == false &&\n        authority['workerDeniedByOs'] == false &&\n        workerIdentity['osIsolationWaived'] == true &&\n        workerIdentity['currentAccountAuthority'] == true &&\n        workerIdentity['authorityConnectionDenied'] == false;\n    final authorityModeValid = ownerRiskQa\n        ? !productCurrentAccount &&\n            authority['authorityKind'] == 'p2-owner-risk-current-account-v1' &&\n            localCurrentAccountBase &&\n            workerIdentity['principalType'] == 'owner-risk-current-account' &&\n            workerIdentity['ownerRiskQa'] == true &&\n            workerIdentity['productCurrentAccount'] == false &&\n            workerIdentity['authorityDenialCode'] == 'owner_risk_waived'\n        : productCurrentAccount\n            ? authority['authorityKind'] == 'p2-current-account-owner-v1' &&\n                authority['securityProfile'] == 'current-account-unisolated' &&\n                localCurrentAccountBase &&\n                workerIdentity['principalType'] == 'current-account-owner' &&\n                workerIdentity['ownerRiskQa'] == false &&\n                workerIdentity['productCurrentAccount'] == true &&\n                workerIdentity['authorityDenialCode'] ==\n                    'current_account_unisolated'\n            : authority['authorityKind'] ==\n                    'p1-isolated-authority-service-v2' &&\n                authority['sharedP1ControlPlane'] == true &&\n                authority['osEnforcedIsolation'] == true &&\n                authority['workerDeniedByOs'] == true;",
)

rep(
    'automation_host/src/owner-risk-launcher.mjs',
    "const policy = JSON.parse(fs.readFileSync(policyPath, 'utf8'));\nconst platform = process.platform === 'win32' ? 'windows' : process.platform === 'darwin' ? 'macos' : 'linux';\nif (policy.schemaVersion !== '2.0.0' || policy.platform !== platform || sessionId.length < 16) {\n  throw new Error('owner_risk_worker_policy_invalid');\n}",
    "const policy = JSON.parse(fs.readFileSync(policyPath, 'utf8'));\nconst platform = process.platform === 'win32' ? 'windows' : process.platform === 'darwin' ? 'macos' : 'linux';\nconst productCurrentAccount = process.env.KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT === '1';\nconst ownerRiskQa = process.env.KRISTIN_OWNER_RISK_QA === '1';\nif (policy.schemaVersion !== '2.0.0' || policy.platform !== platform || sessionId.length < 16 || productCurrentAccount === ownerRiskQa) {\n  throw new Error('owner_risk_worker_policy_invalid');\n}",
)
rep(
    'automation_host/src/owner-risk-launcher.mjs',
    "const identity = {\n  type: 'launcher.identity', schemaVersion: '2.0.0', platform,\n  principalType: 'owner-risk-current-account',\n  sessionId, pid: process.pid, startToken: `owner-risk-${process.pid}-${Date.now()}`,\n  launcherSha256: sha(self), nodeSha256: sha(node), hostScriptSha256: sha(host),\n  authorityConnectionDenied: false, authorityDenialCode: 'owner_risk_waived',\n  authorityDenialObservedBy: 'owner-risk-waiver',\n  ownerRiskQa: true, osIsolationWaived: true, currentAccountAuthority: true,",
    "const identity = {\n  type: 'launcher.identity', schemaVersion: '2.0.0', platform,\n  principalType: productCurrentAccount ? 'current-account-owner' : 'owner-risk-current-account',\n  sessionId, pid: process.pid, startToken: `${productCurrentAccount ? 'current-account' : 'owner-risk'}-${process.pid}-${Date.now()}`,\n  launcherSha256: sha(self), nodeSha256: sha(node), hostScriptSha256: sha(host),\n  authorityConnectionDenied: false,\n  authorityDenialCode: productCurrentAccount ? 'current_account_unisolated' : 'owner_risk_waived',\n  authorityDenialObservedBy: productCurrentAccount ? 'current-account-product' : 'owner-risk-waiver',\n  ownerRiskQa, productCurrentAccount, osIsolationWaived: true, currentAccountAuthority: true,",
)
rep(
    'automation_host/src/owner-risk-launcher.mjs',
    "process.env.KRISTIN_RESTRICTED_WORKER = '0';\nprocess.env.KRISTIN_OWNER_RISK_QA = '1';\nprocess.env.KRISTIN_P1A_DENIAL_PROBE_REQUIRED = '0';",
    "process.env.KRISTIN_RESTRICTED_WORKER = '0';\nif (productCurrentAccount) {\n  delete process.env.KRISTIN_OWNER_RISK_QA;\n  process.env.KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT = '1';\n} else {\n  process.env.KRISTIN_OWNER_RISK_QA = '1';\n  delete process.env.KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT;\n}\nprocess.env.KRISTIN_P1A_DENIAL_PROBE_REQUIRED = '0';",
)

print('OWNER_SINGLE_CLICK_CHAIN_FIX_OK')
