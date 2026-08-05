import test from 'node:test';
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
