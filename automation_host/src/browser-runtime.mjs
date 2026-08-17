import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { createReadStream } from 'node:fs';
import {
  access,
  lstat,
  mkdir,
  readFile,
  readdir,
  realpath,
  rename,
  rm,
  writeFile,
} from 'node:fs/promises';
import path from 'node:path';
import { createInterface } from 'node:readline';
import { pathToFileURL } from 'node:url';

import { chromium } from 'playwright-core';

const READY_SCHEMA_VERSION = '1.0.0';
const PROTOCOL = 'stdio-json-v1';
const MAX_STDERR_BYTES = 1024 * 1024;
const EXIT_POLL_MS = 25;
const SANDBOX_MODES = new Set(['required', 'disabled']);
const SESSION_MODES = new Set(['ephemeral', 'persistent']);
const PROFILE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/u;
const REQUEST_ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/u;
const GENERATED_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/u;

function fail(code, detail = '') {
  const error = new Error(detail ? `${code}:${detail}` : code);
  error.code = code;
  throw error;
}

function requiredValue(argv, flag) {
  const index = argv.indexOf(flag);
  if (index < 0 || index + 1 >= argv.length) fail('argument_missing', flag);
  const value = argv[index + 1];
  if (!value || value.startsWith('--') || value.includes('\0')) {
    fail('argument_invalid', flag);
  }
  return value;
}

function requiredInteger(argv, flag, minimum, maximum) {
  const raw = requiredValue(argv, flag);
  if (!/^[0-9]+$/u.test(raw)) fail('argument_integer_invalid', flag);
  const value = Number.parseInt(raw, 10);
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    fail('argument_integer_out_of_range', flag);
  }
  return value;
}

function requireAbsolute(value, code) {
  if (!path.isAbsolute(value)) fail(code, value);
  return path.resolve(value);
}

export function validateSessionQuotas(value) {
  const quotas = {
    maxSessions: value?.maxSessions,
    maxPagesPerSession: value?.maxPagesPerSession,
    maxPersistentProfiles: value?.maxPersistentProfiles,
  };
  const bounds = {
    maxSessions: [1, 16],
    maxPagesPerSession: [1, 32],
    maxPersistentProfiles: [1, 32],
  };
  for (const [key, [minimum, maximum]] of Object.entries(bounds)) {
    if (
      !Number.isSafeInteger(quotas[key]) ||
      quotas[key] < minimum ||
      quotas[key] > maximum
    ) {
      fail('browser_session_quota_invalid', key);
    }
  }
  return Object.freeze(quotas);
}

export function parseArgs(argv) {
  const allowed = new Set([
    '--mode',
    '--protocol',
    '--sandbox-mode',
    '--browser-executable',
    '--browser-root',
    '--runtime-manifest',
    '--state-directory',
    '--max-sessions',
    '--max-pages-per-session',
    '--max-persistent-profiles',
  ]);
  const seen = new Set();
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i];
    if (!allowed.has(flag) || i + 1 >= argv.length || seen.has(flag)) {
      fail('argument_set_invalid', flag ?? 'missing');
    }
    seen.add(flag);
  }
  const mode = requiredValue(argv, '--mode');
  const protocol = requiredValue(argv, '--protocol');
  const sandboxMode = requiredValue(argv, '--sandbox-mode');
  if (mode !== 'probe' && mode !== 'sessions') {
    fail('mode_not_supported', mode);
  }
  if (protocol !== PROTOCOL) fail('protocol_not_supported', protocol);
  if (!SANDBOX_MODES.has(sandboxMode)) {
    fail('sandbox_mode_not_supported', sandboxMode);
  }
  const common = {
    mode,
    protocol,
    sandboxMode,
    browserExecutable: requireAbsolute(
      requiredValue(argv, '--browser-executable'),
      'browser_executable_not_absolute',
    ),
    browserRoot: requireAbsolute(
      requiredValue(argv, '--browser-root'),
      'browser_root_not_absolute',
    ),
    runtimeManifest: requireAbsolute(
      requiredValue(argv, '--runtime-manifest'),
      'runtime_manifest_not_absolute',
    ),
    stateDirectory: requireAbsolute(
      requiredValue(argv, '--state-directory'),
      'state_directory_not_absolute',
    ),
  };
  const quotaFlags = [
    '--max-sessions',
    '--max-pages-per-session',
    '--max-persistent-profiles',
  ];
  if (mode === 'probe') {
    if (quotaFlags.some((flag) => seen.has(flag))) {
      fail('argument_not_allowed_for_mode', 'probe');
    }
    return common;
  }
  return {
    ...common,
    quotas: validateSessionQuotas({
      maxSessions: requiredInteger(argv, '--max-sessions', 1, 16),
      maxPagesPerSession: requiredInteger(
        argv,
        '--max-pages-per-session',
        1,
        32,
      ),
      maxPersistentProfiles: requiredInteger(
        argv,
        '--max-persistent-profiles',
        1,
        32,
      ),
    }),
  };
}

async function sha256File(filePath) {
  const digest = createHash('sha256');
  const stream = createReadStream(filePath);
  for await (const chunk of stream) digest.update(chunk);
  return digest.digest('hex');
}

async function sameRealPath(expected, actual, code) {
  const [left, right] = await Promise.all([realpath(expected), realpath(actual)]);
  if (left !== right) fail(code, `${left}!=${right}`);
}

export async function validateManifestBinding(options, env = process.env) {
  await Promise.all([
    access(options.browserExecutable),
    access(options.browserRoot),
    access(options.runtimeManifest),
    mkdir(options.stateDirectory, { recursive: true }),
  ]);
  const manifestBytes = await readFile(options.runtimeManifest);
  const manifestSha256 = createHash('sha256').update(manifestBytes).digest('hex');
  if (env.KRISTIN_P3_RUNTIME_MANIFEST_SHA256 !== manifestSha256) {
    fail('runtime_manifest_sha_mismatch');
  }
  const manifest = JSON.parse(manifestBytes.toString('utf8'));
  if (
    manifest?.schemaVersion !== '1.0.0' ||
    manifest?.bundleType !== 'kristin-p3-browser-runtime-v1' ||
    manifest?.applicationOwned !== true ||
    manifest?.globalRuntimeRequired !== false ||
    manifest?.browserNetworkInstallRequired !== false
  ) {
    fail('runtime_manifest_identity_invalid');
  }
  const identity = manifest.identity ?? {};
  if (
    identity.runtimeBuildSha256 !== env.KRISTIN_P3_RUNTIME_BUILD_SHA256 ||
    identity.browserRevision !== env.KRISTIN_P3_BROWSER_REVISION ||
    identity.browserEngine !== 'chromium'
  ) {
    fail('runtime_identity_environment_mismatch');
  }
  const resources = manifest.resources ?? {};
  const browserExecutableRow = resources.browserExecutable;
  const browserRootRow = resources.browserRoot;
  if (
    browserExecutableRow?.kind !== 'file' ||
    !browserExecutableRow.path ||
    !/^[0-9a-f]{64}$/.test(browserExecutableRow.sha256 ?? '') ||
    browserRootRow?.kind !== 'directory' ||
    !browserRootRow.path
  ) {
    fail('browser_resource_manifest_invalid');
  }
  const manifestRoot = path.dirname(options.runtimeManifest);
  const manifestBrowserExecutable = path.resolve(
    manifestRoot,
    browserExecutableRow.path,
  );
  const manifestBrowserRoot = path.resolve(manifestRoot, browserRootRow.path);
  await sameRealPath(
    manifestBrowserExecutable,
    options.browserExecutable,
    'browser_executable_binding_mismatch',
  );
  await sameRealPath(
    manifestBrowserRoot,
    options.browserRoot,
    'browser_root_binding_mismatch',
  );
  const browserExecutableSha256 = await sha256File(options.browserExecutable);
  if (browserExecutableSha256 !== browserExecutableRow.sha256) {
    fail('browser_executable_sha_mismatch');
  }
  return {
    manifest,
    manifestSha256,
    browserExecutableSha256,
    browserRevision: identity.browserRevision,
  };
}

export function chromiumProbeArgs(profileDirectory, sandboxMode = 'required') {
  if (!SANDBOX_MODES.has(sandboxMode)) {
    fail('sandbox_mode_not_supported', sandboxMode);
  }
  const args = [
    '--headless=new',
    '--remote-debugging-port=0',
    `--user-data-dir=${profileDirectory}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-background-networking',
    '--disable-component-update',
    '--disable-default-apps',
    '--disable-dev-shm-usage',
    '--disable-features=Translate,MediaRouter,OptimizationHints',
    '--metrics-recording-only',
  ];
  if (sandboxMode === 'disabled') args.push('--no-sandbox');
  args.push('about:blank');
  return args;
}

async function waitForDevToolsPort(profileDirectory, child, timeoutMs = 20_000) {
  const portFile = path.join(profileDirectory, 'DevToolsActivePort');
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) fail('chromium_exited_before_cdp', `${child.exitCode}`);
    try {
      const lines = (await readFile(portFile, 'utf8'))
        .split(/\r?\n/u)
        .filter(Boolean);
      const port = Number.parseInt(lines[0] ?? '', 10);
      if (Number.isInteger(port) && port > 0 && port <= 65535) return port;
    } catch (error) {
      if (error?.code !== 'ENOENT') throw error;
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  fail('chromium_cdp_timeout');
}

function drainBounded(stream) {
  let bytes = 0;
  let tail = '';
  stream.setEncoding('utf8');
  stream.on('data', (chunk) => {
    bytes += Buffer.byteLength(chunk);
    tail = `${tail}${chunk}`.slice(-16_384);
    if (bytes > MAX_STDERR_BYTES) tail = tail.slice(-16_384);
  });
  return () => tail;
}

export async function waitForExit(child, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (child.exitCode !== null || child.signalCode !== null) {
      return child.exitCode ?? child.signalCode;
    }
    const remaining = Math.max(1, deadline - Date.now());
    await new Promise((resolve) =>
      setTimeout(resolve, Math.min(EXIT_POLL_MS, remaining)),
    );
  }
  return child.exitCode ?? child.signalCode ?? null;
}

function processGroupAlive(pid) {
  try {
    process.kill(-pid, 0);
    return true;
  } catch (error) {
    if (error?.code === 'ESRCH') return false;
    throw error;
  }
}

async function waitForProcessGroupExit(pid, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (!processGroupAlive(pid)) return true;
    const remaining = Math.max(1, deadline - Date.now());
    await new Promise((resolve) =>
      setTimeout(resolve, Math.min(EXIT_POLL_MS, remaining)),
    );
  }
  return !processGroupAlive(pid);
}

async function terminateBrowserTree(child) {
  if (process.platform === 'win32') {
    if (child.exitCode === null && child.signalCode === null) {
      const systemRoot =
        process.env.SystemRoot ?? process.env.SYSTEMROOT ?? process.env.WINDIR;
      if (!systemRoot || !path.isAbsolute(systemRoot)) {
        fail('windows_system_root_invalid');
      }
      const taskkillExecutable = path.join(systemRoot, 'System32', 'taskkill.exe');
      const killer = spawn(
        taskkillExecutable,
        ['/PID', String(child.pid), '/T', '/F'],
        { stdio: 'ignore', windowsHide: true },
      );
      if ((await waitForExit(killer, 5_000)) === null) {
        fail('chromium_taskkill_timeout');
      }
    }
    if ((await waitForExit(child, 5_000)) === null) {
      fail('chromium_tree_stop_timeout');
    }
    return;
  }

  if (processGroupAlive(child.pid)) {
    try {
      process.kill(-child.pid, 'SIGTERM');
    } catch (error) {
      if (error?.code !== 'ESRCH') throw error;
    }
    await waitForExit(child, 2_000);
    if (processGroupAlive(child.pid)) {
      try {
        process.kill(-child.pid, 'SIGKILL');
      } catch (error) {
        if (error?.code !== 'ESRCH') throw error;
      }
      await waitForExit(child, 2_000);
      if (!(await waitForProcessGroupExit(child.pid, 3_000))) {
        fail('chromium_tree_stop_timeout');
      }
    }
  }
  await waitForExit(child, 1_000);
}

async function boundedBrowserDisconnect(browser, timeoutMs = 1_000) {
  if (!browser || !browser.isConnected()) return;
  let timeout;
  await Promise.race([
    browser.close(),
    new Promise((_, reject) => {
      timeout = setTimeout(() => {
        const error = new Error('browser_disconnect_timeout');
        error.code = 'browser_disconnect_timeout';
        reject(error);
      }, timeoutMs);
    }),
  ]).finally(() => clearTimeout(timeout));
}

export function decorateProbeError(error, stderrTail, cleanupError = null) {
  const primary = error instanceof Error ? error : new Error(String(error));
  const details = [];
  if (stderrTail) details.push(`chromiumStderr=${stderrTail}`);
  if (cleanupError) {
    details.push(
      `cleanup=${String(cleanupError?.code ?? cleanupError?.message ?? cleanupError)}`,
    );
  }
  if (details.length > 0) {
    primary.message = `${primary.message}; ${details.join('; ')}`;
  }
  return primary;
}

async function waitForShutdown() {
  const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
  try {
    for await (const line of lines) {
      if (!line.trim()) continue;
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        continue;
      }
      if (message?.type === 'shutdown' && message?.schemaVersion === READY_SCHEMA_VERSION) {
        return;
      }
    }
  } finally {
    lines.close();
  }
}

function shutdownRequestedError() {
  const error = new Error('browser_shutdown_requested');
  error.code = 'browser_shutdown_requested';
  return error;
}

export async function raceStartupWithShutdown(operation, shutdown) {
  return Promise.race([
    operation,
    shutdown.then(() => {
      throw shutdownRequestedError();
    }),
  ]);
}

function assertIdentifier(value, pattern, code) {
  if (typeof value !== 'string' || !pattern.test(value)) fail(code);
  return value;
}

function childPath(root, ...segments) {
  const resolvedRoot = path.resolve(root);
  const candidate = path.resolve(resolvedRoot, ...segments);
  if (candidate !== resolvedRoot && !candidate.startsWith(`${resolvedRoot}${path.sep}`)) {
    fail('browser_profile_path_escape');
  }
  return candidate;
}

async function rejectSymlinkIfPresent(value, code) {
  try {
    if ((await lstat(value)).isSymbolicLink()) fail(code);
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
  }
}

async function atomicJsonWrite(filePath, value) {
  await mkdir(path.dirname(filePath), { recursive: true, mode: 0o700 });
  await rejectSymlinkIfPresent(path.dirname(filePath), 'browser_profile_directory_symlink');
  await rejectSymlinkIfPresent(filePath, 'browser_profile_state_symlink');
  const temporary = `${filePath}.${process.pid}.${randomUUID()}.tmp`;
  await writeFile(temporary, `${JSON.stringify(value)}\n`, {
    encoding: 'utf8',
    mode: 0o600,
    flag: 'wx',
  });
  try {
    await rm(filePath, { force: true });
    await rename(temporary, filePath);
  } catch (error) {
    await rm(temporary, { force: true });
    throw error;
  }
}

async function readStorageState(filePath) {
  await rejectSymlinkIfPresent(filePath, 'browser_profile_state_symlink');
  try {
    const value = JSON.parse(await readFile(filePath, 'utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      fail('browser_profile_state_invalid');
    }
    return value;
  } catch (error) {
    if (error?.code === 'ENOENT') return null;
    if (error?.code) throw error;
    fail('browser_profile_state_invalid');
  }
}

function defaultIdFactory(prefix) {
  return `${prefix}_${randomUUID().replaceAll('-', '')}`;
}

export class BrowserSessionRegistry {
  constructor({ browser, stateDirectory, quotas, idFactory = defaultIdFactory }) {
    if (!browser || typeof browser.newContext !== 'function') {
      fail('browser_session_browser_invalid');
    }
    if (!path.isAbsolute(stateDirectory)) {
      fail('browser_session_state_directory_not_absolute');
    }
    this.browser = browser;
    this.stateDirectory = path.resolve(stateDirectory);
    this.quotas = validateSessionQuotas(quotas);
    this.idFactory = idFactory;
    this.sessions = new Map();
    this.persistentProfiles = new Set();
    this.initialized = false;
  }

  async initialize() {
    if (this.initialized) return;
    await mkdir(this.stateDirectory, { recursive: true, mode: 0o700 });
    await rejectSymlinkIfPresent(this.stateDirectory, 'browser_session_state_symlink');
    const profilesRoot = childPath(this.stateDirectory, 'profiles');
    await mkdir(profilesRoot, { recursive: true, mode: 0o700 });
    await rejectSymlinkIfPresent(profilesRoot, 'browser_profiles_root_symlink');
    const entries = await readdir(profilesRoot, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory() && PROFILE_ID.test(entry.name)) {
        this.persistentProfiles.add(entry.name);
      } else if (entry.isSymbolicLink()) {
        fail('browser_profile_directory_symlink', entry.name);
      }
    }
    if (this.persistentProfiles.size > this.quotas.maxPersistentProfiles) {
      fail('browser_persistent_profile_quota_exceeded');
    }
    this.initialized = true;
  }

  _nextId(prefix) {
    const value = this.idFactory(prefix);
    assertIdentifier(value, GENERATED_ID, 'browser_generated_identifier_invalid');
    return value;
  }

  _session(sessionId) {
    assertIdentifier(sessionId, GENERATED_ID, 'browser_session_id_invalid');
    const session = this.sessions.get(sessionId);
    if (!session) fail('browser_session_not_found', sessionId);
    return session;
  }

  _metadata(session) {
    return {
      sessionId: session.sessionId,
      kind: session.kind,
      profileId: session.profileId,
      pageCount: session.pages.size,
      createdAt: session.createdAt,
    };
  }

  async openSession({ kind = 'ephemeral', profileId = null } = {}) {
    await this.initialize();
    if (!SESSION_MODES.has(kind)) fail('browser_session_kind_invalid');
    if (this.sessions.size >= this.quotas.maxSessions) {
      fail('browser_session_quota_exceeded');
    }
    let storageState = null;
    let statePath = null;
    if (kind === 'persistent') {
      assertIdentifier(profileId, PROFILE_ID, 'browser_profile_id_invalid');
      const existing = this.persistentProfiles.has(profileId);
      if (!existing && this.persistentProfiles.size >= this.quotas.maxPersistentProfiles) {
        fail('browser_persistent_profile_quota_exceeded');
      }
      const profileDirectory = childPath(this.stateDirectory, 'profiles', profileId);
      await rejectSymlinkIfPresent(profileDirectory, 'browser_profile_directory_symlink');
      await mkdir(profileDirectory, { recursive: true, mode: 0o700 });
      statePath = childPath(profileDirectory, 'storage-state.json');
      storageState = await readStorageState(statePath);
      this.persistentProfiles.add(profileId);
    } else if (profileId !== null && profileId !== undefined) {
      fail('browser_ephemeral_profile_forbidden');
    }
    const context = await this.browser.newContext({
      acceptDownloads: false,
      ...(storageState ? { storageState } : {}),
    });
    const sessionId = this._nextId('session');
    if (this.sessions.has(sessionId)) {
      await context.close();
      fail('browser_session_id_collision');
    }
    const session = {
      sessionId,
      kind,
      profileId: kind === 'persistent' ? profileId : null,
      statePath,
      context,
      pages: new Map(),
      createdAt: new Date().toISOString(),
    };
    this.sessions.set(sessionId, session);
    return this._metadata(session);
  }

  listSessions() {
    return Array.from(this.sessions.values(), (session) => this._metadata(session));
  }

  listPages(sessionId) {
    const session = this._session(sessionId);
    return Array.from(session.pages.keys(), (pageId) => ({ pageId, sessionId }));
  }

  async openPage(sessionId) {
    const session = this._session(sessionId);
    if (session.pages.size >= this.quotas.maxPagesPerSession) {
      fail('browser_page_quota_exceeded');
    }
    const page = await session.context.newPage();
    const pageId = this._nextId('page');
    if (session.pages.has(pageId)) {
      await page.close();
      fail('browser_page_id_collision');
    }
    session.pages.set(pageId, page);
    return { pageId, sessionId };
  }

  async closePage(sessionId, pageId) {
    const session = this._session(sessionId);
    assertIdentifier(pageId, GENERATED_ID, 'browser_page_id_invalid');
    const page = session.pages.get(pageId);
    if (!page) fail('browser_page_not_found', pageId);
    session.pages.delete(pageId);
    await page.close();
    return { pageId, sessionId, closed: true };
  }

  async closeSession(sessionId) {
    const session = this._session(sessionId);
    this.sessions.delete(sessionId);
    let primaryError = null;
    if (session.kind === 'persistent') {
      try {
        const storageState = await session.context.storageState();
        await atomicJsonWrite(session.statePath, storageState);
      } catch (error) {
        primaryError = error;
      }
    }
    for (const [pageId, page] of Array.from(session.pages.entries()).reverse()) {
      session.pages.delete(pageId);
      try {
        await page.close();
      } catch (error) {
        primaryError ??= error;
      }
    }
    try {
      await session.context.close();
    } catch (error) {
      primaryError ??= error;
    }
    if (primaryError) throw primaryError;
    return { sessionId, closed: true };
  }

  async closeAll() {
    let primaryError = null;
    for (const sessionId of Array.from(this.sessions.keys()).reverse()) {
      try {
        await this.closeSession(sessionId);
      } catch (error) {
        primaryError ??= error;
      }
    }
    if (primaryError) throw primaryError;
  }

  async execute(message) {
    if (!message || typeof message !== 'object' || Array.isArray(message)) {
      fail('browser_session_request_invalid');
    }
    switch (message.type) {
      case 'session.open':
        return this.openSession({
          kind: message.kind,
          profileId: message.profileId ?? null,
        });
      case 'session.list':
        return { sessions: this.listSessions() };
      case 'session.close':
        return this.closeSession(message.sessionId);
      case 'page.open':
        return this.openPage(message.sessionId);
      case 'page.list':
        return { pages: this.listPages(message.sessionId) };
      case 'page.close':
        return this.closePage(message.sessionId, message.pageId);
      default:
        fail('browser_session_operation_not_supported', String(message.type ?? 'missing'));
    }
  }
}

function responseLine(value) {
  return `${JSON.stringify(value)}\n`;
}

export async function serveSessionCommands(registry, input, output) {
  const lines = createInterface({ input, crlfDelay: Infinity });
  try {
    for await (const line of lines) {
      if (!line.trim()) continue;
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        continue;
      }
      if (
        message?.type === 'shutdown' &&
        message?.schemaVersion === READY_SCHEMA_VERSION
      ) {
        return;
      }
      const requestId = message?.requestId;
      if (!REQUEST_ID.test(requestId ?? '')) {
        continue;
      }
      try {
        const result = await registry.execute(message);
        output.write(
          responseLine({
            type: 'response',
            schemaVersion: READY_SCHEMA_VERSION,
            requestId,
            ok: true,
            result,
          }),
        );
      } catch (error) {
        output.write(
          responseLine({
            type: 'response',
            schemaVersion: READY_SCHEMA_VERSION,
            requestId,
            ok: false,
            error: {
              code: error?.code ?? 'browser_session_operation_failed',
              message: String(error?.message ?? error),
            },
          }),
        );
      }
    }
  } finally {
    lines.close();
  }
}

export async function runProbe(options, env = process.env) {
  const binding = await validateManifestBinding(options, env);
  const profileDirectory = path.join(options.stateDirectory, 'chromium-profile');
  await rm(profileDirectory, { recursive: true, force: true });
  await mkdir(profileDirectory, { recursive: true });
  const child = spawn(
    options.browserExecutable,
    chromiumProbeArgs(profileDirectory, options.sandboxMode),
    {
      cwd: options.browserRoot,
      detached: process.platform !== 'win32',
      env: {},
      stdio: ['ignore', 'ignore', 'pipe'],
      windowsHide: true,
    },
  );
  const stderrTail = drainBounded(child.stderr);
  const shutdown = waitForShutdown();
  let browser;
  let primaryError = null;
  try {
    const port = await raceStartupWithShutdown(
      waitForDevToolsPort(profileDirectory, child),
      shutdown,
    );
    browser = await raceStartupWithShutdown(
      chromium.connectOverCDP(`http://127.0.0.1:${port}`),
      shutdown,
    );
    const browserVersion = browser.version();
    process.stdout.write(
      `${JSON.stringify({
        type: 'ready',
        schemaVersion: READY_SCHEMA_VERSION,
        pid: process.pid,
        browserPid: child.pid,
        browserEngine: 'chromium',
        browserVersion,
        browserRevision: binding.browserRevision,
        browserExecutableSha256: binding.browserExecutableSha256,
        protocol: PROTOCOL,
        sandboxMode: options.sandboxMode,
      })}\n`,
    );
    await shutdown;
  } catch (error) {
    primaryError = error;
  }

  let cleanupError = null;
  try {
    await terminateBrowserTree(child);
  } catch (error) {
    cleanupError = error;
  }
  try {
    await boundedBrowserDisconnect(browser);
  } catch (error) {
    cleanupError ??= error;
  }
  try {
    await rm(profileDirectory, { recursive: true, force: true });
  } catch (error) {
    cleanupError ??= error;
  }

  if (primaryError) {
    throw decorateProbeError(primaryError, stderrTail(), cleanupError);
  }
  if (cleanupError) throw cleanupError;
}

export async function runSessions(options, env = process.env) {
  const binding = await validateManifestBinding(options, env);
  const profileDirectory = path.join(
    options.stateDirectory,
    'chromium-session-service',
  );
  await rm(profileDirectory, { recursive: true, force: true });
  await mkdir(profileDirectory, { recursive: true });
  const child = spawn(
    options.browserExecutable,
    chromiumProbeArgs(profileDirectory, options.sandboxMode),
    {
      cwd: options.browserRoot,
      detached: process.platform !== 'win32',
      env: {},
      stdio: ['ignore', 'ignore', 'pipe'],
      windowsHide: true,
    },
  );
  const stderrTail = drainBounded(child.stderr);
  let browser;
  let registry;
  let primaryError = null;
  try {
    const port = await waitForDevToolsPort(profileDirectory, child);
    browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
    registry = new BrowserSessionRegistry({
      browser,
      stateDirectory: options.stateDirectory,
      quotas: options.quotas,
    });
    await registry.initialize();
    process.stdout.write(
      responseLine({
        type: 'ready',
        schemaVersion: READY_SCHEMA_VERSION,
        pid: process.pid,
        browserPid: child.pid,
        browserEngine: 'chromium',
        browserVersion: browser.version(),
        browserRevision: binding.browserRevision,
        browserExecutableSha256: binding.browserExecutableSha256,
        protocol: PROTOCOL,
        sandboxMode: options.sandboxMode,
        serviceMode: 'sessions',
        quotas: options.quotas,
      }),
    );
    await serveSessionCommands(registry, process.stdin, process.stdout);
  } catch (error) {
    primaryError = error;
  }

  let cleanupError = null;
  try {
    await registry?.closeAll();
  } catch (error) {
    cleanupError = error;
  }
  try {
    await boundedBrowserDisconnect(browser);
  } catch (error) {
    cleanupError ??= error;
  }
  try {
    await terminateBrowserTree(child);
  } catch (error) {
    cleanupError ??= error;
  }
  try {
    await rm(profileDirectory, { recursive: true, force: true });
  } catch (error) {
    cleanupError ??= error;
  }

  if (primaryError) {
    throw decorateProbeError(primaryError, stderrTail(), cleanupError);
  }
  if (cleanupError) throw cleanupError;
}

async function main() {
  try {
    const options = parseArgs(process.argv.slice(2));
    if (options.mode === 'probe') {
      await runProbe(options);
    } else {
      await runSessions(options);
    }
  } catch (error) {
    process.stderr.write(
      `${JSON.stringify({
        type: 'error',
        schemaVersion: READY_SCHEMA_VERSION,
        code: error?.code ?? 'browser_runtime_failed',
        message: String(error?.message ?? error),
      })}\n`,
    );
    process.exitCode = 1;
  }
}

const invokedDirectly = process.argv[1]
  ? import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
  : false;
if (invokedDirectly) await main();
