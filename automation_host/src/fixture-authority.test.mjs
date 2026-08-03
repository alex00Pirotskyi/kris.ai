import test from 'node:test';
import assert from 'node:assert/strict';
import { createTestAuthority } from './test-authority.mjs';
import { createAuthenticatedIpcVerifier } from './authenticated-ipc.mjs';

test('fixture authority is explicitly completion-ineligible', () => {
  const authority = createTestAuthority();
  const bootstrap = authority.bootstrap();
  assert.equal(Object.hasOwn(bootstrap, 'ipcKeyHex'), false);
  assert.equal(Object.hasOwn(bootstrap, 'grantKeyring'), false);
});

test('fixture envelope is verifiable only by public permit key', () => {
  const authority = createTestAuthority();
  const bootstrap = authority.bootstrap();
  const verify = createAuthenticatedIpcVerifier({
    permitVerifier: bootstrap.permitVerifier,
    channelId: bootstrap.channelId,
    workerSessionId: bootstrap.workerSessionId,
    ...bootstrap.authorityState,
  });
  assert.equal(verify(authority.next()).authorization.taskId, 'task');
});
