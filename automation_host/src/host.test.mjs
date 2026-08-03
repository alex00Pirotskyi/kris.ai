import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { BoundedTranscript } from './bounded-transcript.mjs';
import {
  createAuthenticatedIpcVerifier,
  assertSessionAuthorization,
  canonical,
} from './authenticated-ipc.mjs';
import { createTestAuthority } from './test-authority.mjs';
import { redact, safeEnvironmentDelta } from './redaction.mjs';

function verifier(authority, overrides = {}) {
  const bootstrap = authority.bootstrap();
  return createAuthenticatedIpcVerifier({
    permitVerifier: bootstrap.permitVerifier,
    channelId: bootstrap.channelId,
    workerSessionId: bootstrap.workerSessionId,
    ...bootstrap.authorityState,
    ...overrides,
  });
}

test('bounded transcript retains newest exact bytes', () => {
  const transcript = new BoundedTranscript(4096);
  transcript.append(Buffer.alloc(5000, 65));
  const result = transcript.read(0);
  assert.equal(result.data.length, 4096);
  assert.equal(result.truncatedBefore, true);
});

test('desktop-issued ECDSA P-256 one-use effect permit verifies', () => {
  const authority = createTestAuthority();
  const verify = verifier(authority);
  const message = authority.next('pty.open', { shell: '/bin/sh', cwd: '/tmp', arguments: [] });
  assert.equal(verify(message).authorization.runId, 'run');
  assert.throws(() => verify(message), /replay/);
});

test('worker bootstrap contains public verification material only', () => {
  const authority = createTestAuthority();
  const bootstrap = authority.bootstrap();
  const text = JSON.stringify(bootstrap);
  assert.equal(bootstrap.permitVerifier.publicKeySpkiBase64, authority.publicKeySpkiBase64);
  assert.equal(/ipcKeyHex|grantKeyring|consumptionKeyring|privateKey|signingKey|hmacKey/i.test(text), false);
});

test('public ECDSA verifier material cannot sign a new permit', () => {
  const authority = createTestAuthority();
  const publicOnly = crypto.createPublicKey({
    key: Buffer.from(authority.publicKeySpkiBase64, 'base64'),
    format: 'der',
    type: 'spki',
  });
  assert.throws(() => crypto.sign('sha256', Buffer.from('forgery'), publicOnly));
});

test('tampered payload is rejected before dispatch', () => {
  const authority = createTestAuthority();
  const verify = verifier(authority);
  const message = authority.next('pty.open', { shell: '/bin/sh', cwd: '/tmp', arguments: [] });
  message.payload.cwd = '/other';
  assert.throws(() => verify(message), /payload_binding_invalid/);
});

test('tampered authorization is rejected before dispatch', () => {
  const authority = createTestAuthority();
  const verify = verifier(authority);
  const message = authority.next();
  message.authorization.runId = 'other';
  assert.throws(() => verify(message), /payload_binding_invalid|actor_binding_invalid/);
});

test('forged grant cannot be authorized without a new desktop permit', () => {
  const authority = createTestAuthority();
  const verify = verifier(authority);
  const message = authority.next();
  message.authorization.capabilityGrant.auth.mac = '00'.repeat(32);
  assert.throws(() => verify(message), /payload_binding_invalid/);
});

test('forged consumption receipt cannot be authorized without a new desktop permit', () => {
  const authority = createTestAuthority();
  const verify = verifier(authority);
  const message = authority.next();
  message.authorization.consumptionReceipt.auth.mac = '00'.repeat(32);
  assert.throws(() => verify(message), /payload_binding_invalid/);
});

test('unknown permit signer is rejected', () => {
  const authority = createTestAuthority();
  const message = authority.next();
  message.effectPermit.signerKeyId = 'other';
  assert.throws(() => verifier(authority)(message), /signature_shape_invalid/);
});

test('invalid effect permit signature is rejected', () => {
  const authority = createTestAuthority();
  const message = authority.next();
  message.effectPermit.signatureBase64 = Buffer.alloc(72).toString('base64');
  assert.throws(() => verifier(authority)(message), /signature_invalid/);
});

test('channel binding is exact', () => {
  const authority = createTestAuthority();
  const message = authority.next();
  const bootstrap = authority.bootstrap();
  assert.throws(() => createAuthenticatedIpcVerifier({
    permitVerifier: bootstrap.permitVerifier,
    channelId: `other-${crypto.randomUUID()}`,
    workerSessionId: bootstrap.workerSessionId,
    ...bootstrap.authorityState,
  })(message), /transport_binding_invalid/);
});

test('revoked grant is rejected even with valid desktop signature', () => {
  const authority = createTestAuthority();
  const initial = authority.bootstrap();
  const message = authority.next();
  const verify = createAuthenticatedIpcVerifier({
    permitVerifier: initial.permitVerifier,
    channelId: initial.channelId,
    workerSessionId: initial.workerSessionId,
    ...initial.authorityState,
    revokedGrantIds: [message.authorization.grantId],
  });
  assert.throws(() => verify(message), /grant_revoked/);
});

test('grant use is consumed monotonically', () => {
  const authority = createTestAuthority();
  const first = authority.next();
  const second = authority.next('pty.open', { shell: '/bin/sh' }, { expectedGrantDigest: first.authorization.grantDigest });
  const bootstrap = authority.bootstrap();
  const verify = createAuthenticatedIpcVerifier({
    permitVerifier: bootstrap.permitVerifier,
    channelId: bootstrap.channelId,
    workerSessionId: bootstrap.workerSessionId,
    ...bootstrap.authorityState,
  });
  // A bootstrap taken after issuance contains uses=2, so old permits are replay.
  assert.throws(() => verify(first), /replay|sequence/);
  const freshAuthority = createTestAuthority();
  const freshVerify = verifier(freshAuthority);
  const one = freshAuthority.next();
  freshVerify(one);
  const two = freshAuthority.next('pty.open', { shell: '/bin/sh' }, { expectedGrantDigest: one.authorization.grantDigest });
  assert.doesNotThrow(() => freshVerify(two));
  assert.equal(second.authorization.useNumber, 2);
});

test('durable request replay survives worker restart', () => {
  const authority = createTestAuthority();
  const first = authority.next();
  const restarted = createAuthenticatedIpcVerifier({
    permitVerifier: authority.bootstrap().permitVerifier,
    channelId: authority.bootstrap().channelId,
    workerSessionId: authority.bootstrap().workerSessionId,
    revocationEpoch: 7,
    authoritativeGrantUses: { [first.authorization.grantId]: 1 },
    authoritativeConsumedRequestIds: [first.requestId],
    authoritativeStateVersion: first.authorization.consumptionReceipt.stateVersion,
  });
  assert.throws(() => restarted(first), /request_replay/);
});

test('session authorization is exact and monotonic', () => {
  const authority = createTestAuthority();
  const message = authority.next();
  const authorization = message.authorization;
  assert.doesNotThrow(() => assertSessionAuthorization({ authorization, lastUseNumber: 0 }, authorization));
  assert.throws(() => assertSessionAuthorization({ authorization, lastUseNumber: 0 }, { ...authorization, runId: 'other' }), /runId_mismatch/);
  assert.throws(() => assertSessionAuthorization({ authorization, lastUseNumber: authorization.useNumber }, authorization), /use_replay/);
});

test('secret-shaped bootstrap fields are rejected', () => {
  const authority = createTestAuthority();
  const bootstrap = authority.bootstrap();
  assert.throws(() => createAuthenticatedIpcVerifier({
    permitVerifier: { ...bootstrap.permitVerifier, privateKey: '00' },
    channelId: bootstrap.channelId,
    workerSessionId: bootstrap.workerSessionId,
    ...bootstrap.authorityState,
  }), /secret_material_rejected/);
});

test('secret-shaped fields and values are redacted', () => {
  const text = JSON.stringify(redact({ token: 'raw', line: 'Bearer abcdefghijk' }));
  assert.equal(text.includes('raw'), false);
  assert.equal(text.includes('abcdefghijk'), false);
});

test('secret environment keys fail closed', () => {
  assert.throws(() => safeEnvironmentDelta({ API_TOKEN: 'x' }));
});

test('canonical permit encoding is deterministic', () => {
  assert.equal(canonical({ b: 1, a: [2, 3] }), canonical({ a: [2, 3], b: 1 }));
});
