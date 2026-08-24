import test from 'node:test';
import assert from 'node:assert/strict';

import {
  assertPublicNavigationTarget,
  blockPublicNavigationWebSockets,
  isForbiddenPublicAddress,
  validatePublicNavigationRequest,
} from './browser-runtime.mjs';

test('public navigation request is bounded and HTTPS-only', async () => {
  assert.deepEqual(
    validatePublicNavigationRequest({
      url: 'https://example.com/path#fragment',
      timeoutMs: 30_000,
    }),
    {
      url: 'https://example.com/path#fragment',
      timeoutMs: 30_000,
    },
  );
  const publicResolver = async () => [{ address: '93.184.216.34', family: 4 }];
  assert.equal(
    await assertPublicNavigationTarget(
      'https://example.com/path#fragment',
      publicResolver,
    ),
    'https://example.com/path',
  );
});

test('public navigation rejects local, credentials, and non-HTTPS targets', async () => {
  const publicResolver = async () => [{ address: '93.184.216.34', family: 4 }];
  for (const url of [
    'http://example.com/',
    'https://localhost/',
    'https://service.local/',
    'https://user:pass@example.com/',
    'https://127.0.0.1/',
    'https://[::1]/',
  ]) {
    await assert.rejects(
      () => assertPublicNavigationTarget(url, publicResolver),
      /browser_public_navigation_target_forbidden/u,
      url,
    );
  }
});

test('public address classifier blocks private and special networks', () => {
  for (const address of [
    '0.0.0.0',
    '10.1.2.3',
    '100.64.0.1',
    '127.0.0.1',
    '169.254.10.20',
    '172.16.0.1',
    '192.168.1.1',
    '198.18.0.1',
    '198.51.100.1',
    '203.0.113.1',
    '224.0.0.1',
    '::',
    '::1',
    '::ffff:127.0.0.1',
    'fc00::1',
    'fe80::1',
    'ff02::1',
    '2001:db8::1',
  ]) {
    assert.equal(isForbiddenPublicAddress(address), true, address);
  }
  assert.equal(isForbiddenPublicAddress('93.184.216.34'), false);
  assert.equal(isForbiddenPublicAddress('2606:4700:4700::1111'), false);
});

test('public navigation rejects a hostname if any DNS answer is private', async () => {
  const mixedResolver = async () => [
    { address: '93.184.216.34', family: 4 },
    { address: '10.0.0.5', family: 4 },
  ];
  await assert.rejects(
    () => assertPublicNavigationTarget('https://example.com/', mixedResolver),
    /browser_public_navigation_target_forbidden/u,
  );
});

test('rendered research blocks WebSocket egress before navigation', async () => {
  let handler;
  const page = {
    routeWebSocket: async (pattern, candidate) => {
      assert.equal(pattern, '**/*');
      handler = candidate;
    },
  };
  await blockPublicNavigationWebSockets(page);
  assert.equal(typeof handler, 'function');
  let closeOptions;
  handler({
    close: (options) => {
      closeOptions = options;
    },
  });
  assert.equal(closeOptions.code, 1008);
  assert.match(closeOptions.reason, /blocks WebSocket egress/u);
  await assert.rejects(
    () => blockPublicNavigationWebSockets({}),
    /browser_public_navigation_websocket_guard_unavailable/u,
  );
});
