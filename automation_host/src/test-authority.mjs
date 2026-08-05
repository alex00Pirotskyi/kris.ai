import crypto from 'node:crypto';
import { canonical } from './authenticated-ipc.mjs';

export const TEST_PERMIT_KEY_ID = 'p1a-effect-permit-test';

function keyPair() {
  return crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
}

export function testPublicKeySpkiBase64(publicKey) {
  return Buffer.from(publicKey.export({ format: 'der', type: 'spki' })).toString('base64');
}

export function digest(value) {
  return crypto.createHash('sha256').update(canonical(value)).digest('hex');
}

function fakeMac(label) {
  return crypto.createHash('sha256').update(label).digest('hex');
}

export function createTestAuthority({
  roots = ['/tmp'],
  taskId = 'task',
  toolId = 'pty',
  runId = 'run',
  actorId = 'actor',
  capabilityId = 'cap',
  maxUses = 100,
  channelId = `channel-${crypto.randomUUID()}`,
  workerSessionId = `worker-${crypto.randomUUID()}`,
  initialUses = {},
  initialRequests = [],
  initialStateVersion = 0,
  revocationEpoch = 7,
} = {}) {
  const { privateKey, publicKey } = keyPair();
  const publicKeySpkiBase64 = testPublicKeySpkiBase64(publicKey);
  const grants = new Map();
  const grantUses = new Map(Object.entries(initialUses));
  const requestIds = new Set(initialRequests);
  let stateVersion = initialStateVersion;
  const sharedAuthorityInstanceId = `p1a-isolated-${crypto.randomUUID()}`;
  const workerIdentity = {
    schemaVersion: '2.0.0',
    platform: 'linux',
    principalType: 'dedicated-uid',
    sessionId: workerSessionId,
    pid: 43210,
    startToken: '123456789',
    workerUid: 65532,
    workerGid: 65532,
    noNewPrivileges: true,
    namespaceIsolation: true,
    authorityConnectionDenied: true,
    authorityDenialCode: 'worker_principal_denied',
    launcherSha256: fakeMac('launcher'),
    nodeSha256: fakeMac('node'),
    hostScriptSha256: fakeMac('host'),
    workerPolicySha256: fakeMac('worker-policy'),
  };
  const workerIdentitySha256 = digest(workerIdentity);

  function bootstrap() {
    return {
      schemaVersion: '4.0.0',
      verificationMode: 'ecdsa-p256-public-only',
      permitVerifier: {
        algorithm: 'ecdsa-p256-sha256',
        keyId: TEST_PERMIT_KEY_ID,
        publicKeySpkiBase64,
        providerAttestationSha256: fakeMac('provider-attestation'),
      },
      channelId,
      workerSessionId,
      authorityState: {
        revocationEpoch,
        revokedGrantIds: [],
        authoritativeGrantUses: Object.fromEntries(grantUses),
        authoritativeConsumedRequestIds: [...requestIds],
        authoritativeStateVersion: stateVersion,
        sharedAuthorityInstanceId,
      },
      workerCanIssue: false,
      privateSigningMaterialPresent: false,
      symmetricSigningMaterialPresent: false,
      rawAuthoritySecretsReturned: false,
    };
  }

  function next(operation = 'pty.open', payload = {}, { expectedGrantDigest = null } = {}) {
    const now = Date.now();
    const requestId = crypto.randomUUID();
    const notBefore = new Date(now - 1000).toISOString();
    const expiresAt = new Date(now + 60_000).toISOString();
    let grant;
    if (expectedGrantDigest) {
      grant = grants.get(expectedGrantDigest);
      if (!grant) throw new Error('test_expected_grant_unknown');
    } else {
      grant = {
        schemaVersion: '2.0.0',
        grantId: `grant-${crypto.randomUUID()}`,
        issuer: {
          actorId: 'desktop_host',
          authority: 'p1-isolated-authority-service-v2',
          serviceInstanceId: sharedAuthorityInstanceId,
        },
        binding: { runId, taskId, actorId, toolId, accessProfileId: 'owner', capabilityId, operation },
        scope: {
          paths: { roots: [...roots] },
          process: { interactive: true },
          network: { listen: false },
          browser: {},
          secrets: { rawReveal: false, leaseIds: [] },
        },
        budgets: {
          wallClockMs: 60_000,
          maxOutputBytes: 8 * 1024 * 1024,
          maxNetworkBytes: 0,
          maxCostMicros: 0,
          maxMutations: 100,
        },
        validity: { issuedAt: new Date(now).toISOString(), notBefore, expiresAt, maxUses },
        nonce: crypto.randomUUID(),
        auth: {
          algorithm: 'hmac-sha256',
          keyId: 'service-internal-grant-test',
          mac: fakeMac(`grant:${requestId}`),
        },
      };
      grants.set(digest(grant), grant);
    }
    const grantDigest = digest(grant);
    const previousUse = grantUses.get(grant.grantId) ?? 0;
    const useNumber = previousUse + 1;
    stateVersion += 1;
    const policyDecision = {
      schemaVersion: '2.0.0',
      status: 'allow',
      decisionId: `decision-${crypto.randomUUID()}`,
      binding: { runId, taskId, actorId, toolId, accessProfileId: 'owner', capabilityId },
      effect: { action: operation, p2Operation: operation },
    };
    const consumptionReceipt = {
      schemaVersion: '1.0.0',
      grantId: grant.grantId,
      requestId,
      useNumber,
      previousUseNumber: previousUse,
      stateVersion,
      revocationEpoch,
      consumedAt: new Date().toISOString(),
      auth: {
        algorithm: 'hmac-sha256',
        keyId: 'service-internal-consumption-test',
        mac: fakeMac(`consume:${requestId}:${stateVersion}`),
      },
    };
    const authenticatedIpc = {
      schemaVersion: '2.0.0',
      transportType: 'p1a-authenticated-local-ipc-v2',
      authenticationMode: 'desktop-ecdsa-p256-one-use-effect-permit',
      peerId: 'desktop-host',
      channelId,
      requestId,
      workerIdentitySha256,
      workerCanIssue: false,
      symmetricKeyMaterialTransferred: false,
    };
    const auditCheckpoint = {
      id: `audit-${stateVersion}`,
      digest: fakeMac(`audit:${stateVersion}`),
      sequence: stateVersion,
    };
    const authority = {
      authorityKind: 'p1-isolated-authority-service-v2',
      sharedP1ControlPlane: true,
      p2CanIssueGrants: false,
      workerCanIssue: false,
      osEnforcedIsolation: true,
      workerDeniedByOs: true,
      workerIdentity,
      workerIdentitySha256,
      instanceId: sharedAuthorityInstanceId,
      implementationSha256: fakeMac('P1IsolatedAuthorityServiceV2'),
      runtimeBuildSha256: fakeMac('runtime-build'),
    };
    const authorization = {
      runId,
      taskId,
      actorId,
      toolId,
      accessProfileId: 'owner',
      capabilityId,
      operation,
      grantId: grant.grantId,
      grantDigest,
      policyDecisionId: policyDecision.decisionId,
      policyDecisionDigest: digest(policyDecision),
      scopeDigest: digest(grant.scope),
      notBefore: grant.validity.notBefore,
      expiresAt: grant.validity.expiresAt,
      useNumber,
      maxUses: grant.validity.maxUses,
      revocationEpoch,
      capabilityGrant: grant,
      policyDecision,
      consumptionReceipt,
      authenticatedIpc,
      auditCheckpoint,
      workerIdentity,
      workerIdentitySha256,
      authority,
    };
    const exactPayload = { operation, ...payload };
    const permitUnsigned = {
      schemaVersion: '2.0.0',
      permitType: 'p1a-one-use-effect-permit-v2',
      permitId: `permit-${crypto.randomUUID()}`,
      workerSessionId,
      channelId,
      workerIdentitySha256,
      peerId: 'desktop-host',
      requestId,
      operation,
      binding: { runId, taskId, actorId, toolId, accessProfileId: 'owner', capabilityId },
      authorizationSha256: digest(authorization),
      payloadSha256: digest(exactPayload),
      grantId: grant.grantId,
      grantDigest,
      policyDecisionId: policyDecision.decisionId,
      policyDecisionDigest: authorization.policyDecisionDigest,
      scopeDigest: authorization.scopeDigest,
      consumptionReceiptSha256: digest(consumptionReceipt),
      useNumber,
      maxUses: grant.validity.maxUses,
      revocationEpoch,
      authoritativeStateVersion: stateVersion,
      auditCheckpointId: auditCheckpoint.id,
      auditCheckpointSha256: auditCheckpoint.digest,
      sharedAuthorityInstanceId,
      authorityImplementationSha256: fakeMac('P1IsolatedAuthorityServiceV2'),
      runtimeBuildSha256: fakeMac('runtime-build'),
      sourceCommit: 'a'.repeat(40),
      sourceTree: 'b'.repeat(40),
      issuedAt: new Date(now).toISOString(),
      notBefore,
      expiresAt,
      algorithm: 'ecdsa-p256-sha256',
      signerKeyId: TEST_PERMIT_KEY_ID,
    };
    const signatureBase64 = crypto
      .sign('sha256', Buffer.from(canonical(permitUnsigned)), privateKey)
      .toString('base64');
    const envelope = {
      schemaVersion: '3.0.0',
      requestId,
      deadline: expiresAt,
      authorization,
      effectPermit: { ...permitUnsigned, signatureBase64 },
      payload: exactPayload,
    };
    grantUses.set(grant.grantId, useNumber);
    requestIds.add(requestId);
    return envelope;
  }

  return Object.freeze({
    bootstrap,
    next,
    publicKeySpkiBase64,
    channelId,
    workerSessionId,
    privateKey,
    workerIdentity,
  });
}
