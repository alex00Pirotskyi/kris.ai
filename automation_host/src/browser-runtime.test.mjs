import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { Readable, Writable } from 'node:stream';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  BrowserSessionRegistry,
  chromiumProbeArgs,
  decorateProbeError,
  parseArgs,
  raceStartupWithShutdown,
  serveSessionCommands,
  validateManifestBinding,
  validateSessionQuotas,
  waitForExit,
} from './browser-runtime.mjs';

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

async function fixture() {
  const root = await mkdtemp(path.join(os.tmpdir(), 'p3-browser-runtime-test-'));
  const browserRoot = path.join(root, 'browser');
  const browserExecutable = path.join(
    browserRoot,
    process.platform === 'win32' ? 'chrome.exe' : 'chrome',
  );
  const stateDirectory = path.join(root, 'state');
  const runtimeManifest = path.join(root, 'browser-runtime-manifest.v1.json');
  await mkdir(browserRoot, { recursive: true });
  await mkdir(stateDirectory, { recursive: true });
  await writeFile(browserExecutable, 'fake-browser\n');
  const browserExecutableSha256 = sha256('fake-browser\n');
  const runtimeBuildSha256 = 'c'.repeat(64);
  const browserRevision = '1234567';
  const manifest = {
    schemaVersion: '1.0.0',
    bundleType: 'kristin-p3-browser-runtime-v1',
    applicationOwned: true,
    workingDirectoryIndependent: true,
    currentWorkingDirectoryUsed: false,
    globalRuntimeRequired: false,
    browserNetworkInstallRequired: false,
    identity: {
      sourceCommit: 'a'.repeat(40),
      sourceTree: 'b'.repeat(40),
      runtimeBuildSha256,
      packageLockSha256: 'd'.repeat(64),
      nodeVersion: '24.18.0',
      automationHostPackageVersion: '2.0.0-p3.1',
      browserEngine: 'chromium',
      browserRevision,
    },
    resources: {
      browserExecutable: {
        kind: 'file',
        path: path.relative(root, browserExecutable).split(path.sep).join('/'),
        sha256: browserExecutableSha256,
        executable: true,
      },
      browserRoot: {
        kind: 'directory',
        path: 'browser',
        treeSha256: 'e'.repeat(64),
      },
    },
  };
  const bytes = Buffer.from(`${JSON.stringify(manifest)}\n`);
  await writeFile(runtimeManifest, bytes);
  return {
    root,
    browserRoot,
    browserExecutable,
    stateDirectory,
    runtimeManifest,
    browserExecutableSha256,
    browserRevision,
    runtimeBuildSha256,
    manifestSha256: sha256(bytes),
    async cleanup() {
      await rm(root, { recursive: true, force: true });
    },
  };
}

function sessionArgs(f, overrides = {}) {
  const quotas = {
    maxSessions: 2,
    maxPagesPerSession: 2,
    maxPersistentProfiles: 2,
    ...overrides,
  };
  return [
    '--mode', 'sessions',
    '--protocol', 'stdio-json-v1',
    '--sandbox-mode', 'required',
    '--browser-executable', f.browserExecutable,
    '--browser-root', f.browserRoot,
    '--runtime-manifest', f.runtimeManifest,
    '--state-directory', f.stateDirectory,
    '--max-sessions', String(quotas.maxSessions),
    '--max-pages-per-session', String(quotas.maxPagesPerSession),
    '--max-persistent-profiles', String(quotas.maxPersistentProfiles),
  ];
}

test('parseArgs accepts only the exact absolute probe contract', async () => {
  const f = await fixture();
  try {
    const parsed = parseArgs([
      '--mode', 'probe',
      '--protocol', 'stdio-json-v1',
      '--sandbox-mode', 'required',
      '--browser-executable', f.browserExecutable,
      '--browser-root', f.browserRoot,
      '--runtime-manifest', f.runtimeManifest,
      '--state-directory', f.stateDirectory,
    ]);
    assert.equal(parsed.mode, 'probe');
    assert.equal(parsed.protocol, 'stdio-json-v1');
    assert.equal(parsed.sandboxMode, 'required');
    assert.equal(parsed.browserExecutable, path.resolve(f.browserExecutable));
    assert.equal(parsed.browserRoot, path.resolve(f.browserRoot));
  } finally {
    await f.cleanup();
  }
});

test('parseArgs accepts bounded session quotas and rejects probe quota injection', async () => {
  const f = await fixture();
  try {
    const parsed = parseArgs(sessionArgs(f));
    assert.equal(parsed.mode, 'sessions');
    assert.deepEqual(parsed.quotas, {
      maxSessions: 2,
      maxPagesPerSession: 2,
      maxPersistentProfiles: 2,
    });
    assert.throws(
      () => parseArgs([
        '--mode', 'probe',
        '--protocol', 'stdio-json-v1',
        '--sandbox-mode', 'required',
        '--browser-executable', f.browserExecutable,
        '--browser-root', f.browserRoot,
        '--runtime-manifest', f.runtimeManifest,
        '--state-directory', f.stateDirectory,
        '--max-sessions', '2',
      ]),
      /argument_not_allowed_for_mode/u,
    );
    assert.throws(
      () => parseArgs(sessionArgs(f, { maxSessions: 0 })),
      /argument_integer_out_of_range/u,
    );
  } finally {
    await f.cleanup();
  }
});

test('parseArgs rejects relative paths, duplicate arguments, unsupported sandbox mode and unknown arguments', () => {
  assert.throws(
    () => parseArgs([
      '--mode', 'probe',
      '--protocol', 'stdio-json-v1',
      '--sandbox-mode', 'required',
      '--browser-executable', 'relative/chrome',
      '--browser-root', '/tmp/browser',
      '--runtime-manifest', '/tmp/manifest.json',
      '--state-directory', '/tmp/state',
    ]),
    /browser_executable_not_absolute/u,
  );
  assert.throws(
    () => parseArgs([
      '--mode', 'probe',
      '--mode', 'probe',
    ]),
    /argument_set_invalid/u,
  );
  assert.throws(
    () => parseArgs([
      '--mode', 'probe',
      '--protocol', 'stdio-json-v1',
      '--sandbox-mode', 'automatic',
      '--browser-executable', '/tmp/chrome',
      '--browser-root', '/tmp/browser',
      '--runtime-manifest', '/tmp/manifest.json',
      '--state-directory', '/tmp/state',
    ]),
    /sandbox_mode_not_supported/u,
  );
  assert.throws(
    () => parseArgs(['--unexpected', 'value']),
    /argument_set_invalid/u,
  );
});

test('session quota validator is bounded and immutable', () => {
  const quotas = validateSessionQuotas({
    maxSessions: 4,
    maxPagesPerSession: 8,
    maxPersistentProfiles: 6,
  });
  assert.equal(Object.isFrozen(quotas), true);
  assert.throws(
    () => validateSessionQuotas({
      maxSessions: 17,
      maxPagesPerSession: 8,
      maxPersistentProfiles: 6,
    }),
    /browser_session_quota_invalid:maxSessions/u,
  );
});

test('chromiumProbeArgs keeps sandbox required by default and exposes explicit disabled mode', () => {
  const profile = path.resolve(os.tmpdir(), 'p3-profile');
  const required = chromiumProbeArgs(profile, 'required');
  assert.ok(required.includes('--headless=new'));
  assert.ok(required.includes('--remote-debugging-port=0'));
  assert.ok(required.includes(`--user-data-dir=${profile}`));
  assert.ok(required.includes('--disable-background-networking'));
  assert.ok(required.includes('--disable-component-update'));
  assert.ok(required.includes('about:blank'));
  assert.equal(required.includes('--no-sandbox'), false);

  const disabled = chromiumProbeArgs(profile, 'disabled');
  assert.ok(disabled.includes('--no-sandbox'));
  assert.ok(disabled.includes('about:blank'));
});

test('waitForExit observes exit state without relying on a single exit event', async () => {
  const child = { exitCode: null, signalCode: null };
  setTimeout(() => {
    child.signalCode = 'SIGTERM';
  }, 10);
  assert.equal(await waitForExit(child, 250), 'SIGTERM');
});

test('raceStartupWithShutdown interrupts startup before readiness', async () => {
  let resolveStartup;
  const startup = new Promise((resolve) => {
    resolveStartup = resolve;
  });
  let requestShutdown;
  const shutdown = new Promise((resolve) => {
    requestShutdown = resolve;
  });

  const pending = raceStartupWithShutdown(startup, shutdown);
  requestShutdown();
  await assert.rejects(
    pending,
    (error) => error?.code === 'browser_shutdown_requested',
  );
  resolveStartup(9222);

  assert.equal(
    await raceStartupWithShutdown(Promise.resolve(9333), new Promise(() => {})),
    9333,
  );
});

test('decorateProbeError preserves the primary failure and appends cleanup evidence', () => {
  const primary = new Error('chromium_cdp_timeout');
  primary.code = 'chromium_cdp_timeout';
  const cleanup = new Error('chromium_tree_stop_timeout');
  cleanup.code = 'chromium_tree_stop_timeout';
  const decorated = decorateProbeError(
    primary,
    'sandbox or startup stderr',
    cleanup,
  );
  assert.equal(decorated.code, 'chromium_cdp_timeout');
  assert.match(decorated.message, /chromium_cdp_timeout/u);
  assert.match(decorated.message, /chromiumStderr=sandbox or startup stderr/u);
  assert.match(decorated.message, /cleanup=chromium_tree_stop_timeout/u);
});

test('validateManifestBinding accepts exact manifest, browser path and SHA', async () => {
  const f = await fixture();
  try {
    const result = await validateManifestBinding(
      {
        browserExecutable: f.browserExecutable,
        browserRoot: f.browserRoot,
        runtimeManifest: f.runtimeManifest,
        stateDirectory: f.stateDirectory,
      },
      {
        KRISTIN_P3_RUNTIME_MANIFEST_SHA256: f.manifestSha256,
        KRISTIN_P3_RUNTIME_BUILD_SHA256: f.runtimeBuildSha256,
        KRISTIN_P3_BROWSER_REVISION: f.browserRevision,
      },
    );
    assert.equal(result.manifestSha256, f.manifestSha256);
    assert.equal(result.browserExecutableSha256, f.browserExecutableSha256);
    assert.equal(result.browserRevision, f.browserRevision);
    assert.equal(await realpath(f.browserExecutable), await realpath(f.browserExecutable));
  } finally {
    await f.cleanup();
  }
});

test('validateManifestBinding rejects manifest and executable tampering', async () => {
  const f = await fixture();
  try {
    const options = {
      browserExecutable: f.browserExecutable,
      browserRoot: f.browserRoot,
      runtimeManifest: f.runtimeManifest,
      stateDirectory: f.stateDirectory,
    };
    await assert.rejects(
      validateManifestBinding(options, {
        KRISTIN_P3_RUNTIME_MANIFEST_SHA256: '0'.repeat(64),
        KRISTIN_P3_RUNTIME_BUILD_SHA256: f.runtimeBuildSha256,
        KRISTIN_P3_BROWSER_REVISION: f.browserRevision,
      }),
      /runtime_manifest_sha_mismatch/u,
    );
    await writeFile(f.browserExecutable, 'tampered-browser\n');
    await assert.rejects(
      validateManifestBinding(options, {
        KRISTIN_P3_RUNTIME_MANIFEST_SHA256: f.manifestSha256,
        KRISTIN_P3_RUNTIME_BUILD_SHA256: f.runtimeBuildSha256,
        KRISTIN_P3_BROWSER_REVISION: f.browserRevision,
      }),
      /browser_executable_sha_mismatch/u,
    );
  } finally {
    await f.cleanup();
  }
});

class FakePage {
  constructor() {
    this.closed = false;
  }

  async close() {
    this.closed = true;
  }
}

class FakeContext {
  constructor(options) {
    this.options = options;
    this.pages = [];
    this.closed = false;
    this.state = options.storageState ?? { cookies: [], origins: [] };
  }

  async newPage() {
    const page = new FakePage();
    this.pages.push(page);
    return page;
  }

  async storageState() {
    return this.state;
  }

  async close() {
    this.closed = true;
  }
}

class FakeBrowser {
  constructor() {
    this.contexts = [];
  }

  async newContext(options) {
    const context = new FakeContext(options);
    this.contexts.push(context);
    return context;
  }
}

class RetryClosePage extends FakePage {
  constructor() {
    super();
    this.closeAttempts = 0;
  }

  async close() {
    this.closeAttempts += 1;
    if (this.closeAttempts === 1) throw new Error('page_close_failed_once');
    await super.close();
  }
}

class RetryCloseContext extends FakeContext {
  constructor(options) {
    super(options);
    this.closeAttempts = 0;
  }

  async newPage() {
    const page = new RetryClosePage();
    this.pages.push(page);
    return page;
  }

  async close() {
    this.closeAttempts += 1;
    if (this.closeAttempts === 1) throw new Error('context_close_failed_once');
    await super.close();
  }
}

class RetryCloseBrowser extends FakeBrowser {
  async newContext(options) {
    const context = this.contexts.length === 0
      ? new RetryCloseContext(options)
      : new FakeContext(options);
    this.contexts.push(context);
    return context;
  }
}

function deterministicIds(...values) {
  const queue = [...values];
  return () => {
    const value = queue.shift();
    if (!value) throw new Error('test identifier queue exhausted');
    return value;
  };
}

test('ephemeral sessions isolate pages and never persist a profile', async () => {
  const f = await fixture();
  try {
    const browser = new FakeBrowser();
    const registry = new BrowserSessionRegistry({
      browser,
      stateDirectory: f.stateDirectory,
      quotas: {
        maxSessions: 2,
        maxPagesPerSession: 2,
        maxPersistentProfiles: 2,
      },
      idFactory: deterministicIds('session_one', 'page_one'),
    });
    const session = await registry.openSession({ kind: 'ephemeral' });
    assert.equal(session.profileId, null);
    const page = await registry.openPage(session.sessionId);
    assert.equal(page.pageId, 'page_one');
    assert.equal(registry.listPages(session.sessionId).length, 1);
    await registry.closeSession(session.sessionId);
    assert.equal(browser.contexts[0].closed, true);
    assert.equal(browser.contexts[0].pages[0].closed, true);
    await assert.rejects(
      readFile(path.join(f.stateDirectory, 'profiles', 'ephemeral', 'storage-state.json')),
      (error) => error?.code === 'ENOENT',
    );
  } finally {
    await f.cleanup();
  }
});

test('persistent profiles restore exact local state without cross-profile leakage', async () => {
  const f = await fixture();
  try {
    const firstBrowser = new FakeBrowser();
    const first = new BrowserSessionRegistry({
      browser: firstBrowser,
      stateDirectory: f.stateDirectory,
      quotas: {
        maxSessions: 2,
        maxPagesPerSession: 2,
        maxPersistentProfiles: 2,
      },
      idFactory: deterministicIds('session_alpha'),
    });
    const alpha = await first.openSession({
      kind: 'persistent',
      profileId: 'alpha',
    });
    firstBrowser.contexts[0].state = {
      cookies: [{ name: 'token', value: 'alpha-only' }],
      origins: [],
    };
    await first.closeSession(alpha.sessionId);

    const secondBrowser = new FakeBrowser();
    const second = new BrowserSessionRegistry({
      browser: secondBrowser,
      stateDirectory: f.stateDirectory,
      quotas: {
        maxSessions: 2,
        maxPagesPerSession: 2,
        maxPersistentProfiles: 2,
      },
      idFactory: deterministicIds('session_alpha_again', 'session_beta'),
    });
    const restored = await second.openSession({
      kind: 'persistent',
      profileId: 'alpha',
    });
    assert.equal(
      secondBrowser.contexts[0].options.storageState.cookies[0].value,
      'alpha-only',
    );
    await second.closeSession(restored.sessionId);
    await second.openSession({ kind: 'persistent', profileId: 'beta' });
    assert.equal(secondBrowser.contexts[1].options.storageState, undefined);
  } finally {
    await f.cleanup();
  }
});

test('session, page and persistent-profile quotas fail closed', async () => {
  const f = await fixture();
  try {
    const browser = new FakeBrowser();
    const registry = new BrowserSessionRegistry({
      browser,
      stateDirectory: f.stateDirectory,
      quotas: {
        maxSessions: 1,
        maxPagesPerSession: 1,
        maxPersistentProfiles: 1,
      },
      idFactory: deterministicIds(
        'session_one',
        'page_one',
        'session_alpha',
      ),
    });
    const ephemeral = await registry.openSession({ kind: 'ephemeral' });
    await assert.rejects(
      registry.openSession({ kind: 'ephemeral' }),
      /browser_session_quota_exceeded/u,
    );
    await registry.openPage(ephemeral.sessionId);
    await assert.rejects(
      registry.openPage(ephemeral.sessionId),
      /browser_page_quota_exceeded/u,
    );
    await registry.closeSession(ephemeral.sessionId);
    const alpha = await registry.openSession({
      kind: 'persistent',
      profileId: 'alpha',
    });
    await registry.closeSession(alpha.sessionId);
    await assert.rejects(
      registry.openSession({ kind: 'persistent', profileId: 'beta' }),
      /browser_persistent_profile_quota_exceeded/u,
    );
  } finally {
    await f.cleanup();
  }
});

test('invalid profile identifiers and unknown operations fail closed', async () => {
  const f = await fixture();
  try {
    const registry = new BrowserSessionRegistry({
      browser: new FakeBrowser(),
      stateDirectory: f.stateDirectory,
      quotas: {
        maxSessions: 2,
        maxPagesPerSession: 2,
        maxPersistentProfiles: 2,
      },
      idFactory: deterministicIds('session_one'),
    });
    await assert.rejects(
      registry.openSession({ kind: 'persistent', profileId: '../escape' }),
      /browser_profile_id_invalid/u,
    );
    await assert.rejects(
      registry.openSession({ kind: 'ephemeral', profileId: 'forbidden' }),
      /browser_ephemeral_profile_forbidden/u,
    );
    await assert.rejects(
      registry.execute({
        type: 'session.list',
        schemaVersion: '0.9.0',
      }),
      /browser_session_request_schema_invalid/u,
    );
    await assert.rejects(
      registry.execute({
        type: 'navigate',
        schemaVersion: '1.0.0',
        url: 'https://example.com',
      }),
      /browser_session_operation_not_supported/u,
    );
  } finally {
    await f.cleanup();
  }
});

test('persistent profiles are exclusive until tracked cleanup succeeds', async () => {
  const f = await fixture();
  try {
    const browser = new RetryCloseBrowser();
    const registry = new BrowserSessionRegistry({
      browser,
      stateDirectory: f.stateDirectory,
      quotas: {
        maxSessions: 2,
        maxPagesPerSession: 2,
        maxPersistentProfiles: 2,
      },
      idFactory: deterministicIds('session_alpha', 'session_alpha_again'),
    });
    const alpha = await registry.openSession({
      kind: 'persistent',
      profileId: 'alpha',
    });
    await assert.rejects(
      registry.openSession({ kind: 'persistent', profileId: 'alpha' }),
      /browser_profile_in_use/u,
    );
    await assert.rejects(
      registry.closeSession(alpha.sessionId),
      /context_close_failed_once/u,
    );
    assert.equal(registry.listSessions().length, 1);
    await assert.rejects(
      registry.openSession({ kind: 'persistent', profileId: 'alpha' }),
      /browser_profile_in_use/u,
    );
    await registry.closeSession(alpha.sessionId);
    const reopened = await registry.openSession({
      kind: 'persistent',
      profileId: 'alpha',
    });
    assert.equal(reopened.profileId, 'alpha');
    await registry.closeSession(reopened.sessionId);
  } finally {
    await f.cleanup();
  }
});

test('failed page close remains tracked and can be retried', async () => {
  const f = await fixture();
  try {
    const browser = new RetryCloseBrowser();
    const registry = new BrowserSessionRegistry({
      browser,
      stateDirectory: f.stateDirectory,
      quotas: {
        maxSessions: 2,
        maxPagesPerSession: 2,
        maxPersistentProfiles: 2,
      },
      idFactory: deterministicIds('session_one', 'page_one'),
    });
    const session = await registry.openSession({ kind: 'ephemeral' });
    const page = await registry.openPage(session.sessionId);
    await assert.rejects(
      registry.closePage(session.sessionId, page.pageId),
      /page_close_failed_once/u,
    );
    assert.equal(registry.listPages(session.sessionId).length, 1);
    await registry.closePage(session.sessionId, page.pageId);
    assert.equal(registry.listPages(session.sessionId).length, 0);
    await assert.rejects(
      registry.closeSession(session.sessionId),
      /context_close_failed_once/u,
    );
    assert.equal(registry.listSessions().length, 1);
    await registry.closeSession(session.sessionId);
  } finally {
    await f.cleanup();
  }
});

test('stdio session protocol correlates responses and shuts down without executing later input', async () => {
  const f = await fixture();
  try {
    const registry = new BrowserSessionRegistry({
      browser: new FakeBrowser(),
      stateDirectory: f.stateDirectory,
      quotas: {
        maxSessions: 2,
        maxPagesPerSession: 2,
        maxPersistentProfiles: 2,
      },
      idFactory: deterministicIds('session_one'),
    });
    const input = Readable.from([
      '{not-json}\n',
      `${JSON.stringify({
        type: 'session.open',
        schemaVersion: '1.0.0',
        requestId: 'req-1',
        kind: 'ephemeral',
      })}\n`,
      `${JSON.stringify({
        type: 'shutdown',
        schemaVersion: '1.0.0',
      })}\n`,
      `${JSON.stringify({
        type: 'session.list',
        schemaVersion: '1.0.0',
        requestId: 'req-2',
      })}\n`,
    ]);
    let outputText = '';
    const output = new Writable({
      write(chunk, _encoding, callback) {
        outputText += chunk.toString();
        callback();
      },
    });
    await serveSessionCommands(registry, input, output);
    const rows = outputText.trim().split('\n').map((row) => JSON.parse(row));
    assert.equal(rows.length, 1);
    assert.equal(rows[0].requestId, 'req-1');
    assert.equal(rows[0].ok, true);
    assert.equal(rows[0].result.sessionId, 'session_one');
    await registry.closeAll();
  } finally {
    await f.cleanup();
  }
});
