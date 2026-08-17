import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { createReadStream } from 'node:fs';
import {
  access,
  lstat,
  mkdir,
  open,
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
const DOWNLOAD_ID = /^download_[A-Za-z0-9_-]{1,119}$/u;
const SHA256_HEX = /^[0-9a-f]{64}$/u;
const DOWNLOAD_RECEIPT_TYPE = 'kristin-p3-browser-download-receipt-v1';
const HARD_MAX_DOWNLOAD_BYTES = 128 * 1024 * 1024;
export const P3_DOWNLOAD_LIMITS = Object.freeze({
  maxPayloadBytes: HARD_MAX_DOWNLOAD_BYTES,
  maxQuarantineBytes: HARD_MAX_DOWNLOAD_BYTES,
  maxReceipts: 1024,
  maxReceiptBytes: 64 * 1024,
});

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

export function validateDownloadLimits(value = P3_DOWNLOAD_LIMITS) {
  const limits = {
    maxPayloadBytes: value?.maxPayloadBytes,
    maxQuarantineBytes: value?.maxQuarantineBytes,
    maxReceipts: value?.maxReceipts,
    maxReceiptBytes: value?.maxReceiptBytes,
  };
  if (
    !Number.isSafeInteger(limits.maxPayloadBytes) ||
    limits.maxPayloadBytes < 1 ||
    limits.maxPayloadBytes > HARD_MAX_DOWNLOAD_BYTES ||
    !Number.isSafeInteger(limits.maxQuarantineBytes) ||
    limits.maxQuarantineBytes < limits.maxPayloadBytes ||
    limits.maxQuarantineBytes > HARD_MAX_DOWNLOAD_BYTES ||
    !Number.isSafeInteger(limits.maxReceipts) ||
    limits.maxReceipts < 1 ||
    limits.maxReceipts > 4096 ||
    !Number.isSafeInteger(limits.maxReceiptBytes) ||
    limits.maxReceiptBytes < 1024 ||
    limits.maxReceiptBytes > 64 * 1024
  ) {
    fail('browser_download_limits_invalid');
  }
  return Object.freeze(limits);
}

function canonicalDownloadReceiptValue(value) {
  if (
    value === null ||
    typeof value === 'string' ||
    typeof value === 'boolean'
  ) {
    return value;
  }
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (Array.isArray(value)) {
    return value.map((item) => canonicalDownloadReceiptValue(item));
  }
  if (value && typeof value === 'object') {
    const result = {};
    for (const key of Object.keys(value).sort()) {
      result[key] = canonicalDownloadReceiptValue(value[key]);
    }
    return result;
  }
  fail('browser_download_receipt_value_invalid');
}

export function canonicalDownloadReceiptJson(value) {
  return JSON.stringify(canonicalDownloadReceiptValue(value));
}

export function sanitizeDownloadFilename(raw) {
  let value = String(raw ?? '').split(/[\\/]/u).at(-1) ?? '';
  value = value
    .replace(/[\u0000-\u001f\u007f<>:"|?*]/gu, '_')
    .trim()
    .replace(/[. ]+$/u, '');
  if (!value || value === '.' || value === '..') value = 'download';
  value = boundedUtf8(value, 255).text;
  return value || 'download';
}

function downloadChildPath(root, ...segments) {
  const resolvedRoot = path.resolve(root);
  const candidate = path.resolve(resolvedRoot, ...segments);
  if (
    candidate !== resolvedRoot &&
    !candidate.startsWith(`${resolvedRoot}${path.sep}`)
  ) {
    fail('browser_download_path_escape');
  }
  return candidate;
}

async function rejectDownloadSymlinkIfPresent(value, code) {
  try {
    if ((await lstat(value)).isSymbolicLink()) fail(code);
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
  }
}

function downloadScopeForSession(session) {
  if (session.kind === 'persistent') {
    return { scopeKind: 'persistent', scopeId: session.profileId };
  }
  return { scopeKind: 'ephemeral', scopeId: session.sessionId };
}

function downloadRelativePath(scopeKind, scopeId, downloadId) {
  return [
    'downloads',
    'quarantine',
    scopeKind,
    scopeId,
    downloadId,
    'payload.bin',
  ].join('/');
}

function canonicalIsoTimestamp(value) {
  if (typeof value !== 'string') return false;
  const parsed = new Date(value);
  return !Number.isNaN(parsed.valueOf()) && parsed.toISOString() === value;
}

function downloadReceiptHashInput(receipt) {
  const { receiptHash: _receiptHash, ...base } = receipt;
  return base;
}

export function validateDownloadReceipt(value, expected = {}) {
  exactObjectKeys(
    value,
    new Set([
      'schemaVersion',
      'receiptType',
      'downloadId',
      'sessionId',
      'sessionKind',
      'profileId',
      'pageId',
      'sourceUrl',
      'suggestedFilename',
      'content',
      'locator',
      'createdAt',
      'receiptHash',
    ]),
    'browser_download_receipt_invalid',
  );
  exactObjectKeys(
    value.content,
    new Set(['relativePath', 'bytes', 'sha256']),
    'browser_download_receipt_invalid',
  );
  exactObjectKeys(
    value.locator,
    new Set(['strategy', 'index']),
    'browser_download_receipt_invalid',
  );
  const profileValid =
    (value.sessionKind === 'ephemeral' && value.profileId === null) ||
    (value.sessionKind === 'persistent' &&
      typeof value.profileId === 'string' &&
      PROFILE_ID.test(value.profileId));
  const scopeId =
    value.sessionKind === 'persistent' ? value.profileId : value.sessionId;
  const expectedRelativePath =
    typeof scopeId === 'string' && DOWNLOAD_ID.test(value.downloadId ?? '')
      ? downloadRelativePath(
          value.sessionKind,
          scopeId,
          value.downloadId,
        )
      : '';
  if (
    value.schemaVersion !== READY_SCHEMA_VERSION ||
    value.receiptType !== DOWNLOAD_RECEIPT_TYPE ||
    typeof value.downloadId !== 'string' ||
    !DOWNLOAD_ID.test(value.downloadId) ||
    typeof value.sessionId !== 'string' ||
    !GENERATED_ID.test(value.sessionId) ||
    !SESSION_MODES.has(value.sessionKind) ||
    !profileValid ||
    typeof value.pageId !== 'string' ||
    !GENERATED_ID.test(value.pageId) ||
    typeof value.sourceUrl !== 'string' ||
    Buffer.byteLength(value.sourceUrl, 'utf8') > 4096 ||
    typeof value.suggestedFilename !== 'string' ||
    sanitizeDownloadFilename(value.suggestedFilename) !==
      value.suggestedFilename ||
    Buffer.byteLength(value.suggestedFilename, 'utf8') > 255 ||
    value.content.relativePath !== expectedRelativePath ||
    !Number.isSafeInteger(value.content.bytes) ||
    value.content.bytes < 0 ||
    value.content.bytes > HARD_MAX_DOWNLOAD_BYTES ||
    typeof value.content.sha256 !== 'string' ||
    !SHA256_HEX.test(value.content.sha256) ||
    !LOCATOR_STRATEGIES.has(value.locator.strategy) ||
    !Number.isSafeInteger(value.locator.index) ||
    value.locator.index < 0 ||
    value.locator.index > 7 ||
    !canonicalIsoTimestamp(value.createdAt) ||
    typeof value.receiptHash !== 'string' ||
    !SHA256_HEX.test(value.receiptHash)
  ) {
    fail('browser_download_receipt_invalid');
  }
  for (const [key, expectedValue] of Object.entries(expected)) {
    if (expectedValue !== undefined && value[key] !== expectedValue) {
      fail('browser_download_receipt_identity_mismatch', key);
    }
  }
  const canonical = canonicalDownloadReceiptJson(
    downloadReceiptHashInput(value),
  );
  if (
    createHash('sha256').update(canonical).digest('hex') !==
    value.receiptHash
  ) {
    fail('browser_download_receipt_hash_mismatch');
  }
  return Object.freeze({
    ...value,
    content: Object.freeze({ ...value.content }),
    locator: Object.freeze({ ...value.locator }),
  });
}

function createDownloadReceipt({
  downloadId,
  session,
  pageId,
  sourceUrl,
  suggestedFilename,
  relativePath,
  bytes,
  sha256,
  locatorStrategy,
  locatorIndex,
  createdAt,
}) {
  const base = {
    schemaVersion: READY_SCHEMA_VERSION,
    receiptType: DOWNLOAD_RECEIPT_TYPE,
    downloadId,
    sessionId: session.sessionId,
    sessionKind: session.kind,
    profileId: session.profileId,
    pageId,
    sourceUrl,
    suggestedFilename,
    content: {
      relativePath,
      bytes,
      sha256,
    },
    locator: {
      strategy: locatorStrategy,
      index: locatorIndex,
    },
    createdAt,
  };
  const receiptHash = createHash('sha256')
    .update(canonicalDownloadReceiptJson(base))
    .digest('hex');
  return validateDownloadReceipt({ ...base, receiptHash });
}


export const P3_PAGE_OBSERVATION_LIMITS = Object.freeze({
  domBytes: 192 * 1024,
  visibleTextBytes: 64 * 1024,
  accessibilityBytes: 96 * 1024,
  screenshotBytes: 256 * 1024,
  maxForms: 50,
  maxControlsPerForm: 50,
  maxConsoleEntries: 50,
  maxNetworkEntries: 100,
  maxEnvelopeBytes: 900 * 1024,
});

function canonicalObservationValue(value) {
  if (
    value === null ||
    typeof value === 'string' ||
    typeof value === 'boolean'
  ) {
    return value;
  }
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (Array.isArray(value)) {
    return value.map((item) => canonicalObservationValue(item));
  }
  if (value && typeof value === 'object') {
    const result = {};
    for (const key of Object.keys(value).sort()) {
      result[key] = canonicalObservationValue(value[key]);
    }
    return result;
  }
  fail('browser_observation_value_invalid');
}

export function canonicalObservationJson(value) {
  return JSON.stringify(canonicalObservationValue(value));
}

function boundedUtf8(raw, maximumBytes) {
  const text = String(raw ?? '');
  const bytes = Buffer.from(text, 'utf8');
  if (bytes.length <= maximumBytes) {
    return { text, bytes: bytes.length, truncated: false };
  }
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let end = maximumBytes;
  while (end > 0) {
    try {
      const bounded = decoder.decode(bytes.subarray(0, end));
      return { text: bounded, bytes: end, truncated: true };
    } catch {
      end -= 1;
    }
  }
  return { text: '', bytes: 0, truncated: true };
}

function boundedScalar(raw, maximumBytes = 4096) {
  return boundedUtf8(raw, maximumBytes).text;
}

function sanitizedNetworkUrl(raw) {
  const value = boundedScalar(raw, 8192);
  try {
    const parsed = new URL(value);
    parsed.username = '';
    parsed.password = '';
    parsed.search = '';
    parsed.hash = '';
    return boundedScalar(parsed.toString(), 4096);
  } catch {
    return boundedScalar(value.split(/[?#]/u, 1)[0], 4096);
  }
}

function telemetryPush(telemetry, key, entry, maximum) {
  if (telemetry[key].length < maximum) {
    telemetry[key].push(entry);
  } else {
    telemetry[`${key}Dropped`] += 1;
  }
}

export function createPageTelemetry(page) {
  const telemetry = {
    console: [],
    consoleDropped: 0,
    requests: [],
    requestsDropped: 0,
    responses: [],
    responsesDropped: 0,
  };
  if (typeof page.on !== 'function') return telemetry;
  page.on('console', (message) => {
    try {
      telemetryPush(
        telemetry,
        'console',
        {
          type: boundedScalar(
            typeof message.type === 'function' ? message.type() : 'log',
            64,
          ),
          text: boundedScalar(
            typeof message.text === 'function' ? message.text() : '',
            4096,
          ),
        },
        P3_PAGE_OBSERVATION_LIMITS.maxConsoleEntries,
      );
    } catch {
      telemetry.consoleDropped += 1;
    }
  });
  page.on('request', (request) => {
    try {
      telemetryPush(
        telemetry,
        'requests',
        {
          url: sanitizedNetworkUrl(request.url()),
          method: boundedScalar(request.method(), 32),
          resourceType: boundedScalar(request.resourceType(), 64),
        },
        P3_PAGE_OBSERVATION_LIMITS.maxNetworkEntries,
      );
    } catch {
      telemetry.requestsDropped += 1;
    }
  });
  page.on('response', (response) => {
    try {
      const request = response.request();
      telemetryPush(
        telemetry,
        'responses',
        {
          url: sanitizedNetworkUrl(response.url()),
          status: response.status(),
          method: boundedScalar(request.method(), 32),
          resourceType: boundedScalar(request.resourceType(), 64),
        },
        P3_PAGE_OBSERVATION_LIMITS.maxNetworkEntries,
      );
    } catch {
      telemetry.responsesDropped += 1;
    }
  });
  return telemetry;
}

function normalizeForms(rawForms) {
  if (!Array.isArray(rawForms)) fail('browser_observation_forms_invalid');
  return rawForms.slice(0, P3_PAGE_OBSERVATION_LIMITS.maxForms).map(
    (form, index) => {
      if (!form || typeof form !== 'object' || Array.isArray(form)) {
        fail('browser_observation_forms_invalid');
      }
      const controls = Array.isArray(form.controls)
        ? form.controls
            .slice(0, P3_PAGE_OBSERVATION_LIMITS.maxControlsPerForm)
            .map((control) => ({
              tag: boundedScalar(control?.tag, 64),
              type: boundedScalar(control?.type, 64),
              name: boundedScalar(control?.name, 512),
              id: boundedScalar(control?.id, 512),
              autocomplete: boundedScalar(control?.autocomplete, 256),
              required: control?.required === true,
              disabled: control?.disabled === true,
              checked: control?.checked === true,
            }))
        : [];
      return {
        index,
        id: boundedScalar(form.id, 512),
        name: boundedScalar(form.name, 512),
        method: boundedScalar(form.method, 32).toUpperCase(),
        action: sanitizedNetworkUrl(form.action),
        controls,
        controlsTruncated:
          Array.isArray(form.controls) &&
          form.controls.length >
            P3_PAGE_OBSERVATION_LIMITS.maxControlsPerForm,
      };
    },
  );
}

export async function capturePageObservation(page, telemetry) {
  if (!page || typeof page.locator !== 'function') {
    fail('browser_observation_page_invalid');
  }
  const body = page.locator('body');
  if (
    !body ||
    typeof body.innerText !== 'function' ||
    typeof body.ariaSnapshot !== 'function'
  ) {
    fail('browser_observation_accessibility_unavailable');
  }
  const [title, dom, visibleText, accessibility, rawForms, screenshot] =
    await Promise.all([
      page.title(),
      page.content(),
      body.innerText(),
      body.ariaSnapshot(),
      page.evaluate(() =>
        Array.from(document.forms).map((form) => ({
          id: form.id,
          name: form.getAttribute('name') ?? '',
          method: form.method,
          action: form.action,
          controls: Array.from(form.elements).map((control) => ({
            tag: control.tagName.toLowerCase(),
            type: control.getAttribute('type') ?? '',
            name: control.getAttribute('name') ?? '',
            id: control.id,
            autocomplete: control.getAttribute('autocomplete') ?? '',
            required: control.required === true,
            disabled: control.disabled === true,
            checked: control.checked === true,
          })),
        })),
      ),
      page.screenshot({
        type: 'jpeg',
        quality: 55,
        fullPage: false,
        animations: 'disabled',
        caret: 'hide',
        scale: 'css',
      }),
    ]);
  if (!Buffer.isBuffer(screenshot)) {
    fail('browser_observation_screenshot_invalid');
  }
  if (screenshot.length > P3_PAGE_OBSERVATION_LIMITS.screenshotBytes) {
    fail('browser_observation_screenshot_too_large');
  }
  const observation = {
    schemaVersion: '1.0.0',
    url: sanitizedNetworkUrl(page.url()),
    title: boundedScalar(title, 4096),
    dom: boundedUtf8(dom, P3_PAGE_OBSERVATION_LIMITS.domBytes),
    visibleText: boundedUtf8(
      visibleText,
      P3_PAGE_OBSERVATION_LIMITS.visibleTextBytes,
    ),
    accessibility: boundedUtf8(
      accessibility,
      P3_PAGE_OBSERVATION_LIMITS.accessibilityBytes,
    ),
    forms: normalizeForms(rawForms),
    formsTruncated:
      Array.isArray(rawForms) &&
      rawForms.length > P3_PAGE_OBSERVATION_LIMITS.maxForms,
    screenshot: {
      bytes: screenshot.length,
      sha256: createHash('sha256').update(screenshot).digest('hex'),
      base64: screenshot.toString('base64'),
      mediaType: 'image/jpeg',
    },
    console: {
      entries: telemetry.console.slice(),
      dropped: telemetry.consoleDropped,
    },
    network: {
      requests: telemetry.requests.slice(),
      requestsDropped: telemetry.requestsDropped,
      responses: telemetry.responses.slice(),
      responsesDropped: telemetry.responsesDropped,
    },
  };
  const canonical = canonicalObservationJson(observation);
  if (Buffer.byteLength(canonical, 'utf8') > P3_PAGE_OBSERVATION_LIMITS.maxEnvelopeBytes) {
    fail('browser_observation_envelope_too_large');
  }
  return {
    observation,
    observationHash: createHash('sha256').update(canonical).digest('hex'),
  };
}


const PAGE_ACTIONS = new Set([
  'click',
  'fill',
  'type',
  'select',
  'check',
  'uncheck',
  'press',
  'hover',
  'drag',
  'wait',
  'scroll',
]);
const LOCATOR_STRATEGIES = new Set([
  'role',
  'label',
  'placeholder',
  'text',
  'testId',
  'css',
]);
const WAIT_STATES = new Set(['attached', 'detached', 'visible', 'hidden']);

function exactObjectKeys(value, allowed, code) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    fail(code);
  }
  const unknown = Object.keys(value).filter((key) => !allowed.has(key));
  if (unknown.length > 0) fail(code, unknown.sort().join(','));
}

function boundedActionString(value, code, maximumBytes = 8192) {
  if (typeof value !== 'string' || value.includes('\0')) fail(code);
  const bytes = Buffer.byteLength(value, 'utf8');
  if (bytes === 0 || bytes > maximumBytes) fail(code);
  return value;
}

function normalizeLocatorDescriptor(value) {
  exactObjectKeys(
    value,
    new Set(['strategy', 'value', 'role', 'name', 'exact']),
    'browser_locator_invalid',
  );
  if (!LOCATOR_STRATEGIES.has(value.strategy)) {
    fail('browser_locator_strategy_invalid');
  }
  const exact = value.exact === true;
  if (value.exact !== undefined && typeof value.exact !== 'boolean') {
    fail('browser_locator_invalid');
  }
  if (value.strategy === 'role') {
    return Object.freeze({
      strategy: 'role',
      role: boundedActionString(value.role, 'browser_locator_role_invalid', 128),
      name: boundedActionString(value.name, 'browser_locator_name_invalid', 4096),
      exact,
    });
  }
  if (value.role !== undefined || value.name !== undefined) {
    fail('browser_locator_invalid');
  }
  return Object.freeze({
    strategy: value.strategy,
    value: boundedActionString(value.value, 'browser_locator_value_invalid', 8192),
    exact,
  });
}

function normalizeLocatorList(value, code = 'browser_locator_list_invalid') {
  if (!Array.isArray(value) || value.length < 1 || value.length > 8) {
    fail(code);
  }
  return Object.freeze(value.map((item) => normalizeLocatorDescriptor(item)));
}

export function validatePageActionRequest(value) {
  exactObjectKeys(
    value,
    new Set([
      'action',
      'locators',
      'targetLocators',
      'value',
      'options',
      'key',
      'state',
      'deltaY',
      'timeoutMs',
    ]),
    'browser_action_request_invalid',
  );
  if (!PAGE_ACTIONS.has(value.action)) {
    fail('browser_action_kind_invalid');
  }
  const timeoutMs = value.timeoutMs ?? 10_000;
  if (
    !Number.isSafeInteger(timeoutMs) ||
    timeoutMs < 100 ||
    timeoutMs > 30_000
  ) {
    fail('browser_action_timeout_invalid');
  }
  const request = {
    action: value.action,
    locators: normalizeLocatorList(value.locators),
    timeoutMs,
  };
  if (value.action === 'fill' || value.action === 'type') {
    request.value = boundedActionString(
      value.value,
      'browser_action_value_invalid',
      64 * 1024,
    );
  } else if (value.value !== undefined) {
    fail('browser_action_request_invalid', 'value');
  }
  if (value.action === 'select') {
    const options = Array.isArray(value.options)
      ? value.options
      : [value.options];
    if (options.length < 1 || options.length > 32) {
      fail('browser_action_options_invalid');
    }
    request.options = Object.freeze(
      options.map((item) =>
        boundedActionString(
          item,
          'browser_action_options_invalid',
          4096,
        ),
      ),
    );
  } else if (value.options !== undefined) {
    fail('browser_action_request_invalid', 'options');
  }
  if (value.action === 'press') {
    request.key = boundedActionString(
      value.key,
      'browser_action_key_invalid',
      128,
    );
  } else if (value.key !== undefined) {
    fail('browser_action_request_invalid', 'key');
  }
  if (value.action === 'wait') {
    request.state = value.state ?? 'visible';
    if (!WAIT_STATES.has(request.state)) {
      fail('browser_action_wait_state_invalid');
    }
  } else if (value.state !== undefined) {
    fail('browser_action_request_invalid', 'state');
  }
  if (value.action === 'scroll') {
    if (
      !Number.isSafeInteger(value.deltaY) ||
      value.deltaY === 0 ||
      Math.abs(value.deltaY) > 100_000
    ) {
      fail('browser_action_scroll_delta_invalid');
    }
    request.deltaY = value.deltaY;
  } else if (value.deltaY !== undefined) {
    fail('browser_action_request_invalid', 'deltaY');
  }
  if (value.action === 'drag') {
    request.targetLocators = normalizeLocatorList(
      value.targetLocators,
      'browser_action_target_locator_invalid',
    );
  } else if (value.targetLocators !== undefined) {
    fail('browser_action_request_invalid', 'targetLocators');
  }
  return Object.freeze(request);
}

export function validatePageDownloadRequest(value) {
  exactObjectKeys(
    value,
    new Set(['locators', 'timeoutMs']),
    'browser_download_request_invalid',
  );
  const timeoutMs = value.timeoutMs ?? 30_000;
  if (
    !Number.isSafeInteger(timeoutMs) ||
    timeoutMs < 100 ||
    timeoutMs > 60_000
  ) {
    fail('browser_download_timeout_invalid');
  }
  return Object.freeze({
    locators: normalizeLocatorList(value.locators),
    timeoutMs,
  });
}

function locatorFromDescriptor(page, descriptor) {
  switch (descriptor.strategy) {
    case 'role':
      if (typeof page.getByRole !== 'function') {
        fail('browser_locator_api_unavailable', 'role');
      }
      return page.getByRole(descriptor.role, {
        name: descriptor.name,
        exact: descriptor.exact,
      });
    case 'label':
      if (typeof page.getByLabel !== 'function') {
        fail('browser_locator_api_unavailable', 'label');
      }
      return page.getByLabel(descriptor.value, {
        exact: descriptor.exact,
      });
    case 'placeholder':
      if (typeof page.getByPlaceholder !== 'function') {
        fail('browser_locator_api_unavailable', 'placeholder');
      }
      return page.getByPlaceholder(descriptor.value, {
        exact: descriptor.exact,
      });
    case 'text':
      if (typeof page.getByText !== 'function') {
        fail('browser_locator_api_unavailable', 'text');
      }
      return page.getByText(descriptor.value, {
        exact: descriptor.exact,
      });
    case 'testId':
      if (typeof page.getByTestId !== 'function') {
        fail('browser_locator_api_unavailable', 'testId');
      }
      return page.getByTestId(descriptor.value);
    case 'css':
      return page.locator(descriptor.value);
    default:
      fail('browser_locator_strategy_invalid');
  }
}

export async function resolvePageActionLocator(page, descriptors) {
  for (let index = 0; index < descriptors.length; index += 1) {
    const descriptor = descriptors[index];
    const locator = locatorFromDescriptor(page, descriptor);
    if (!locator || typeof locator.count !== 'function') {
      fail('browser_locator_api_unavailable', descriptor.strategy);
    }
    const count = await locator.count();
    if (!Number.isSafeInteger(count) || count < 0) {
      fail('browser_locator_count_invalid');
    }
    if (count === 0) continue;
    if (count !== 1) {
      fail('browser_locator_ambiguous', descriptor.strategy);
    }
    return { locator, descriptor, index };
  }
  fail('browser_locator_not_found');
}

async function performResolvedAction(resolved, request, target = null) {
  const locator = resolved.locator;
  const timeout = request.timeoutMs;
  switch (request.action) {
    case 'click':
      await locator.click({ timeout });
      return;
    case 'fill':
      await locator.fill(request.value, { timeout });
      return;
    case 'type':
      await locator.pressSequentially(request.value, { delay: 0, timeout });
      return;
    case 'select':
      await locator.selectOption(request.options, { timeout });
      return;
    case 'check':
      await locator.check({ timeout });
      return;
    case 'uncheck':
      await locator.uncheck({ timeout });
      return;
    case 'press':
      await locator.press(request.key, { timeout });
      return;
    case 'hover':
      await locator.hover({ timeout });
      return;
    case 'drag':
      await locator.dragTo(target.locator, { timeout });
      return;
    case 'wait':
      await locator.waitFor({ state: request.state, timeout });
      return;
    case 'scroll':
      await locator.evaluate(
        (element, deltaY) => element.scrollBy({ top: deltaY, behavior: 'auto' }),
        request.deltaY,
      );
      return;
    default:
      fail('browser_action_kind_invalid');
  }
}

export async function performPageAction(page, rawRequest, telemetry) {
  const request = validatePageActionRequest(rawRequest);
  const before = await capturePageObservation(page, telemetry);
  const resolved = await resolvePageActionLocator(page, request.locators);
  let target = null;
  if (request.action === 'drag') {
    target = await resolvePageActionLocator(page, request.targetLocators);
  }
  await performResolvedAction(resolved, request, target);
  const after = await capturePageObservation(page, telemetry);
  return {
    action: request.action,
    locatorStrategy: resolved.descriptor.strategy,
    locatorIndex: resolved.index,
    ...(target
      ? {
          targetLocatorStrategy: target.descriptor.strategy,
          targetLocatorIndex: target.index,
        }
      : {}),
    sensitiveInputProvided:
      request.action === 'fill' || request.action === 'type',
    beforeObservationHash: before.observationHash,
    afterObservationHash: after.observationHash,
    observationChanged:
      before.observationHash !== after.observationHash,
  };
}


const VISUAL_ACTIONS = new Set(['click', 'drag']);
const VISUAL_FALLBACK_CODES = new Set([
  'browser_locator_not_found',
  'browser_locator_ambiguous',
]);

export const P3_VISUAL_MIN_CONFIDENCE = 0.9;

function finiteVisualNumber(value, code) {
  if (typeof value !== 'number' || !Number.isFinite(value)) fail(code);
  return value;
}

function normalizeVisualSource(value) {
  exactObjectKeys(
    value,
    new Set([
      'observationHash',
      'screenshotSha256',
      'viewportWidth',
      'viewportHeight',
    ]),
    'browser_visual_source_invalid',
  );
  if (
    typeof value.observationHash !== 'string' ||
    !SHA256_HEX.test(value.observationHash) ||
    typeof value.screenshotSha256 !== 'string' ||
    !SHA256_HEX.test(value.screenshotSha256) ||
    !Number.isSafeInteger(value.viewportWidth) ||
    value.viewportWidth < 1 ||
    value.viewportWidth > 32768 ||
    !Number.isSafeInteger(value.viewportHeight) ||
    value.viewportHeight < 1 ||
    value.viewportHeight > 32768
  ) {
    fail('browser_visual_source_invalid');
  }
  return Object.freeze({
    observationHash: value.observationHash,
    screenshotSha256: value.screenshotSha256,
    viewportWidth: value.viewportWidth,
    viewportHeight: value.viewportHeight,
  });
}

function normalizeVisualTarget(value, code = 'browser_visual_target_invalid') {
  exactObjectKeys(
    value,
    new Set(['x', 'y', 'width', 'height', 'confidence', 'description']),
    code,
  );
  const x = finiteVisualNumber(value.x, code);
  const y = finiteVisualNumber(value.y, code);
  const width = finiteVisualNumber(value.width, code);
  const height = finiteVisualNumber(value.height, code);
  const confidence = finiteVisualNumber(value.confidence, code);
  if (
    x < 0 ||
    y < 0 ||
    width <= 0 ||
    height <= 0 ||
    x > 100000 ||
    y > 100000 ||
    width > 100000 ||
    height > 100000 ||
    confidence < 0 ||
    confidence > 1
  ) {
    fail(code);
  }
  return Object.freeze({
    x,
    y,
    width,
    height,
    confidence,
    description: boundedActionString(
      value.description,
      'browser_visual_target_description_invalid',
      4096,
    ),
  });
}

function normalizeVisualVerification(value = {}) {
  exactObjectKeys(
    value,
    new Set([
      'requireObservationChange',
      'expectedUrl',
      'expectedUrlPrefix',
    ]),
    'browser_visual_verification_invalid',
  );
  if (
    value.requireObservationChange !== undefined &&
    typeof value.requireObservationChange !== 'boolean'
  ) {
    fail('browser_visual_verification_invalid');
  }
  if (value.expectedUrl !== undefined && value.expectedUrlPrefix !== undefined) {
    fail('browser_visual_verification_invalid');
  }
  const requireObservationChange = value.requireObservationChange ?? true;
  const expectedUrl =
    value.expectedUrl === undefined
      ? null
      : sanitizedNetworkUrl(
          boundedActionString(
            value.expectedUrl,
            'browser_visual_expected_url_invalid',
            8192,
          ),
        );
  const expectedUrlPrefix =
    value.expectedUrlPrefix === undefined
      ? null
      : sanitizedNetworkUrl(
          boundedActionString(
            value.expectedUrlPrefix,
            'browser_visual_expected_url_invalid',
            8192,
          ),
        );
  if (!requireObservationChange && expectedUrl === null && expectedUrlPrefix === null) {
    fail('browser_visual_verification_required');
  }
  return Object.freeze({
    requireObservationChange,
    expectedUrl,
    expectedUrlPrefix,
  });
}

export function validateVisualActionRequest(value) {
  exactObjectKeys(
    value,
    new Set([
      'action',
      'locators',
      'targetLocators',
      'visualSource',
      'visualTarget',
      'visualDragTarget',
      'minimumConfidence',
      'verification',
      'timeoutMs',
    ]),
    'browser_visual_action_request_invalid',
  );
  if (!VISUAL_ACTIONS.has(value.action)) {
    fail('browser_visual_action_kind_invalid');
  }
  const timeoutMs = value.timeoutMs ?? 10000;
  if (
    !Number.isSafeInteger(timeoutMs) ||
    timeoutMs < 100 ||
    timeoutMs > 30000
  ) {
    fail('browser_action_timeout_invalid');
  }
  const minimumConfidence = finiteVisualNumber(
    value.minimumConfidence ?? P3_VISUAL_MIN_CONFIDENCE,
    'browser_visual_confidence_invalid',
  );
  if (minimumConfidence < P3_VISUAL_MIN_CONFIDENCE || minimumConfidence > 1) {
    fail('browser_visual_confidence_invalid');
  }
  const request = {
    action: value.action,
    locators: normalizeLocatorList(value.locators),
    visualSource: normalizeVisualSource(value.visualSource),
    visualTarget: normalizeVisualTarget(value.visualTarget),
    minimumConfidence,
    verification: normalizeVisualVerification(value.verification),
    timeoutMs,
  };
  if (value.action === 'drag') {
    request.targetLocators = normalizeLocatorList(
      value.targetLocators,
      'browser_action_target_locator_invalid',
    );
    request.visualDragTarget = normalizeVisualTarget(
      value.visualDragTarget,
      'browser_visual_drag_target_invalid',
    );
  } else if (
    value.targetLocators !== undefined ||
    value.visualDragTarget !== undefined
  ) {
    fail('browser_visual_action_request_invalid');
  }
  return Object.freeze(request);
}

async function currentVisualViewport(page) {
  let viewport = null;
  if (typeof page.viewportSize === 'function') {
    viewport = await page.viewportSize();
  }
  if (viewport === null || viewport === undefined) {
    if (typeof page.evaluate !== 'function') {
      fail('browser_visual_viewport_unavailable');
    }
    viewport = await page.evaluate(() => ({
      width: window.innerWidth,
      height: window.innerHeight,
    }));
  }
  if (
    !viewport ||
    !Number.isSafeInteger(viewport.width) ||
    viewport.width < 1 ||
    viewport.width > 32768 ||
    !Number.isSafeInteger(viewport.height) ||
    viewport.height < 1 ||
    viewport.height > 32768
  ) {
    fail('browser_visual_viewport_invalid');
  }
  return { width: viewport.width, height: viewport.height };
}

function visualTargetCenter(target, viewport) {
  if (
    target.x + target.width > viewport.width ||
    target.y + target.height > viewport.height
  ) {
    fail('browser_visual_target_out_of_bounds');
  }
  return {
    x: target.x + target.width / 2,
    y: target.y + target.height / 2,
  };
}

function assertVisualSourceBinding(request, before, viewport) {
  if (
    request.visualSource.observationHash !== before.observationHash ||
    request.visualSource.screenshotSha256 !==
      before.observation.screenshot.sha256
  ) {
    fail('browser_visual_source_stale');
  }
  if (
    request.visualSource.viewportWidth !== viewport.width ||
    request.visualSource.viewportHeight !== viewport.height
  ) {
    fail('browser_visual_viewport_stale');
  }
}

async function resolveStructuredVisualAction(page, request) {
  try {
    const source = await resolvePageActionLocator(page, request.locators);
    let target = null;
    if (request.action === 'drag') {
      target = await resolvePageActionLocator(page, request.targetLocators);
    }
    return { source, target, failureCode: null };
  } catch (error) {
    if (!VISUAL_FALLBACK_CODES.has(error?.code)) throw error;
    return { source: null, target: null, failureCode: error.code };
  }
}

async function performVisualMouseAction(
  page,
  request,
  sourcePoint,
  destinationPoint = null,
) {
  if (
    !page.mouse ||
    typeof page.mouse.click !== 'function' ||
    typeof page.mouse.move !== 'function' ||
    typeof page.mouse.down !== 'function' ||
    typeof page.mouse.up !== 'function'
  ) {
    fail('browser_visual_mouse_unavailable');
  }
  if (request.action === 'click') {
    await page.mouse.click(sourcePoint.x, sourcePoint.y);
    return;
  }
  await page.mouse.move(sourcePoint.x, sourcePoint.y);
  await page.mouse.down();
  let primaryError = null;
  try {
    await page.mouse.move(destinationPoint.x, destinationPoint.y, {
      steps: 12,
    });
  } catch (error) {
    primaryError = error;
  }
  try {
    await page.mouse.up();
  } catch (error) {
    primaryError ??= error;
  }
  if (primaryError) throw primaryError;
}

function verifyVisualActionPostconditions(request, before, after) {
  const observationChanged =
    before.observationHash !== after.observationHash;
  if (
    request.verification.requireObservationChange &&
    !observationChanged
  ) {
    fail('browser_visual_action_unverified');
  }
  let urlTransitionVerified = false;
  if (request.verification.expectedUrl !== null) {
    if (after.observation.url !== request.verification.expectedUrl) {
      fail('browser_visual_action_url_mismatch');
    }
    urlTransitionVerified =
      before.observation.url !== request.verification.expectedUrl;
  }
  if (request.verification.expectedUrlPrefix !== null) {
    if (
      !after.observation.url.startsWith(
        request.verification.expectedUrlPrefix,
      )
    ) {
      fail('browser_visual_action_url_mismatch');
    }
    urlTransitionVerified =
      !before.observation.url.startsWith(
        request.verification.expectedUrlPrefix,
      );
  }
  if (!observationChanged && !urlTransitionVerified) {
    fail('browser_visual_action_unverified');
  }
  return observationChanged;
}

export async function performVerifiedVisualAction(
  page,
  rawRequest,
  telemetry,
) {
  const request = validateVisualActionRequest(rawRequest);
  const before = await capturePageObservation(page, telemetry);
  const structured = await resolveStructuredVisualAction(page, request);
  if (structured.failureCode === null) {
    await performResolvedAction(
      structured.source,
      request,
      structured.target,
    );
    const after = await capturePageObservation(page, telemetry);
    const observationChanged = verifyVisualActionPostconditions(
      request,
      before,
      after,
    );
    return {
      action: request.action,
      disposition: 'executed',
      executionMode: 'structured',
      locatorStrategy: structured.source.descriptor.strategy,
      locatorIndex: structured.source.index,
      ...(structured.target
        ? {
            targetLocatorStrategy:
              structured.target.descriptor.strategy,
            targetLocatorIndex: structured.target.index,
          }
        : {}),
      minimumConfidence: request.minimumConfidence,
      beforeObservationHash: before.observationHash,
      beforeScreenshotSha256: before.observation.screenshot.sha256,
      afterObservationHash: after.observationHash,
      afterScreenshotSha256: after.observation.screenshot.sha256,
      observationChanged,
      verified: true,
    };
  }

  const viewport = await currentVisualViewport(page);
  assertVisualSourceBinding(request, before, viewport);
  const sourcePoint = visualTargetCenter(request.visualTarget, viewport);
  const destinationPoint =
    request.action === 'drag'
      ? visualTargetCenter(request.visualDragTarget, viewport)
      : null;
  const lowConfidence =
    request.visualTarget.confidence < request.minimumConfidence ||
    (request.action === 'drag' &&
      request.visualDragTarget.confidence < request.minimumConfidence);
  const visualBase = {
    action: request.action,
    executionMode: 'visual',
    structuredFailureCode: structured.failureCode,
    minimumConfidence: request.minimumConfidence,
    visualConfidence: request.visualTarget.confidence,
    ...(request.action === 'drag'
      ? {
          visualDestinationConfidence:
            request.visualDragTarget.confidence,
        }
      : {}),
    beforeObservationHash: before.observationHash,
    beforeScreenshotSha256: before.observation.screenshot.sha256,
  };
  if (lowConfidence) {
    return {
      ...visualBase,
      disposition: 'user_takeover_required',
      pauseReason: 'browser_visual_target_low_confidence',
      observationChanged: false,
      verified: false,
    };
  }

  await performVisualMouseAction(
    page,
    request,
    sourcePoint,
    destinationPoint,
  );
  const after = await capturePageObservation(page, telemetry);
  const observationChanged = verifyVisualActionPostconditions(
    request,
    before,
    after,
  );
  return {
    ...visualBase,
    disposition: 'executed',
    afterObservationHash: after.observationHash,
    afterScreenshotSha256: after.observation.screenshot.sha256,
    observationChanged,
    verified: true,
  };
}

export class BrowserSessionRegistry {
  constructor({
    browser,
    stateDirectory,
    quotas,
    idFactory = defaultIdFactory,
    downloadLimits = P3_DOWNLOAD_LIMITS,
    clock = () => new Date(),
  }) {
    if (!browser || typeof browser.newContext !== 'function') {
      fail('browser_session_browser_invalid');
    }
    if (!path.isAbsolute(stateDirectory)) {
      fail('browser_session_state_directory_not_absolute');
    }
    if (typeof idFactory !== 'function' || typeof clock !== 'function') {
      fail('browser_session_dependency_invalid');
    }
    this.browser = browser;
    this.stateDirectory = path.resolve(stateDirectory);
    this.quotas = validateSessionQuotas(quotas);
    this.downloadLimits = validateDownloadLimits(downloadLimits);
    this.idFactory = idFactory;
    this.clock = clock;
    this.sessions = new Map();
    this.persistentProfiles = new Set();
    this.activePersistentProfiles = new Set();
    this.pageTelemetry = new WeakMap();
    this.downloadReceipts = new Map();
    this.quarantineBytes = 0;
    this.downloadsRoot = downloadChildPath(this.stateDirectory, 'downloads');
    this.quarantineRoot = downloadChildPath(
      this.downloadsRoot,
      'quarantine',
    );
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
    await this._initializeDownloadInventory();
    this.initialized = true;
  }

  async _ensureDownloadRoots() {
    await mkdir(this.downloadsRoot, { recursive: true, mode: 0o700 });
    await rejectDownloadSymlinkIfPresent(
      this.downloadsRoot,
      'browser_downloads_root_symlink',
    );
    const downloadEntries = await readdir(this.downloadsRoot, {
      withFileTypes: true,
    });
    for (const entry of downloadEntries) {
      if (entry.name !== 'quarantine') {
        fail('browser_downloads_root_entry_invalid', entry.name);
      }
      if (entry.isSymbolicLink() || !entry.isDirectory()) {
        fail('browser_download_quarantine_root_invalid');
      }
    }
    await mkdir(this.quarantineRoot, { recursive: true, mode: 0o700 });
    await rejectDownloadSymlinkIfPresent(
      this.quarantineRoot,
      'browser_download_quarantine_root_symlink',
    );
    for (const scopeKind of SESSION_MODES) {
      const scopeRoot = downloadChildPath(this.quarantineRoot, scopeKind);
      await mkdir(scopeRoot, { recursive: true, mode: 0o700 });
      await rejectDownloadSymlinkIfPresent(
        scopeRoot,
        'browser_download_scope_root_symlink',
      );
    }
    const quarantineEntries = await readdir(this.quarantineRoot, {
      withFileTypes: true,
    });
    for (const entry of quarantineEntries) {
      if (!SESSION_MODES.has(entry.name)) {
        fail('browser_download_scope_kind_invalid', entry.name);
      }
      if (entry.isSymbolicLink() || !entry.isDirectory()) {
        fail('browser_download_scope_root_invalid', entry.name);
      }
    }
  }

  _downloadPaths(scopeKind, scopeId, downloadId) {
    if (!SESSION_MODES.has(scopeKind)) {
      fail('browser_download_scope_kind_invalid');
    }
    const scopePattern = scopeKind === 'persistent' ? PROFILE_ID : GENERATED_ID;
    if (typeof scopeId !== 'string' || !scopePattern.test(scopeId)) {
      fail('browser_download_scope_id_invalid');
    }
    assertIdentifier(downloadId, DOWNLOAD_ID, 'browser_download_id_invalid');
    const scopeRoot = downloadChildPath(this.quarantineRoot, scopeKind);
    const scopeDirectory = downloadChildPath(scopeRoot, scopeId);
    const entryDirectory = downloadChildPath(scopeDirectory, downloadId);
    return {
      scopeRoot,
      scopeDirectory,
      entryDirectory,
      payloadPath: downloadChildPath(entryDirectory, 'payload.bin'),
      receiptPath: downloadChildPath(entryDirectory, 'receipt.json'),
    };
  }

  async _ensureDownloadScope(scopeKind, scopeId) {
    await this._ensureDownloadRoots();
    const markerId = 'download_scope_marker';
    const { scopeRoot, scopeDirectory } = this._downloadPaths(
      scopeKind,
      scopeId,
      markerId,
    );
    await rejectDownloadSymlinkIfPresent(
      scopeRoot,
      'browser_download_scope_root_symlink',
    );
    await mkdir(scopeDirectory, { recursive: false, mode: 0o700 }).catch(
      (error) => {
        if (error?.code !== 'EEXIST') throw error;
      },
    );
    await rejectDownloadSymlinkIfPresent(
      scopeDirectory,
      'browser_download_scope_directory_symlink',
    );
    const metadata = await lstat(scopeDirectory);
    if (!metadata.isDirectory()) {
      fail('browser_download_scope_directory_invalid');
    }
    return scopeDirectory;
  }

  async _readStoredDownload(scopeKind, scopeId, downloadId) {
    const paths = this._downloadPaths(scopeKind, scopeId, downloadId);
    await rejectDownloadSymlinkIfPresent(
      paths.entryDirectory,
      'browser_download_entry_symlink',
    );
    const entryMetadata = await lstat(paths.entryDirectory).catch((error) => {
      if (error?.code === 'ENOENT') fail('browser_download_not_found', downloadId);
      throw error;
    });
    if (!entryMetadata.isDirectory()) {
      fail('browser_download_entry_invalid', downloadId);
    }
    const entries = await readdir(paths.entryDirectory, { withFileTypes: true });
    const names = entries.map((entry) => entry.name).sort();
    if (
      names.length !== 2 ||
      names[0] !== 'payload.bin' ||
      names[1] !== 'receipt.json' ||
      entries.some((entry) => entry.isSymbolicLink() || !entry.isFile())
    ) {
      fail('browser_download_entry_invalid', downloadId);
    }
    const [payloadMetadata, receiptMetadata] = await Promise.all([
      lstat(paths.payloadPath),
      lstat(paths.receiptPath),
    ]);
    if (
      payloadMetadata.isSymbolicLink() ||
      !payloadMetadata.isFile() ||
      receiptMetadata.isSymbolicLink() ||
      !receiptMetadata.isFile() ||
      receiptMetadata.size < 2 ||
      receiptMetadata.size > this.downloadLimits.maxReceiptBytes
    ) {
      fail('browser_download_entry_invalid', downloadId);
    }
    let rawReceipt;
    try {
      rawReceipt = JSON.parse(await readFile(paths.receiptPath, 'utf8'));
    } catch (error) {
      if (error?.code) throw error;
      fail('browser_download_receipt_invalid', downloadId);
    }
    const receipt = validateDownloadReceipt(rawReceipt, {
      downloadId,
      sessionKind: scopeKind,
      ...(scopeKind === 'persistent'
        ? { profileId: scopeId }
        : { sessionId: scopeId }),
    });
    if (
      payloadMetadata.size !== receipt.content.bytes ||
      payloadMetadata.size > this.downloadLimits.maxPayloadBytes
    ) {
      fail('browser_download_size_mismatch', downloadId);
    }
    const digest = await sha256File(paths.payloadPath);
    if (digest !== receipt.content.sha256) {
      fail('browser_download_sha_mismatch', downloadId);
    }
    return receipt;
  }

  async _initializeDownloadInventory() {
    await this._ensureDownloadRoots();
    const restored = new Map();
    let restoredBytes = 0;
    for (const scopeKind of SESSION_MODES) {
      const scopeRoot = downloadChildPath(this.quarantineRoot, scopeKind);
      const scopes = await readdir(scopeRoot, { withFileTypes: true });
      for (const scope of scopes) {
        if (scope.isSymbolicLink() || !scope.isDirectory()) {
          fail('browser_download_scope_directory_invalid', scope.name);
        }
        const scopePattern =
          scopeKind === 'persistent' ? PROFILE_ID : GENERATED_ID;
        if (!scopePattern.test(scope.name)) {
          fail('browser_download_scope_id_invalid', scope.name);
        }
        const scopeDirectory = downloadChildPath(scopeRoot, scope.name);
        await rejectDownloadSymlinkIfPresent(
          scopeDirectory,
          'browser_download_scope_directory_symlink',
        );
        const entries = await readdir(scopeDirectory, { withFileTypes: true });
        for (const entry of entries) {
          if (entry.name.startsWith('.partial-')) {
            if (entry.isSymbolicLink() || !entry.isDirectory()) {
              fail('browser_download_partial_entry_invalid', entry.name);
            }
            await rm(downloadChildPath(scopeDirectory, entry.name), {
              recursive: true,
              force: true,
            });
            continue;
          }
          if (
            entry.isSymbolicLink() ||
            !entry.isDirectory() ||
            !DOWNLOAD_ID.test(entry.name)
          ) {
            fail('browser_download_entry_invalid', entry.name);
          }
          const receipt = await this._readStoredDownload(
            scopeKind,
            scope.name,
            entry.name,
          );
          if (restored.has(receipt.downloadId)) {
            fail('browser_download_id_collision', receipt.downloadId);
          }
          restoredBytes += receipt.content.bytes;
          if (
            restored.size + 1 > this.downloadLimits.maxReceipts ||
            restoredBytes > this.downloadLimits.maxQuarantineBytes
          ) {
            fail('browser_download_quarantine_quota_exceeded');
          }
          restored.set(receipt.downloadId, receipt);
        }
      }
    }
    this.downloadReceipts = restored;
    this.quarantineBytes = restoredBytes;
  }

  async _quarantineDownload({
    download,
    downloadId,
    session,
    pageId,
    locatorStrategy,
    locatorIndex,
  }) {
    if (
      !download ||
      typeof download.createReadStream !== 'function' ||
      typeof download.suggestedFilename !== 'function' ||
      typeof download.url !== 'function'
    ) {
      fail('browser_download_handle_invalid');
    }
    const { scopeKind, scopeId } = downloadScopeForSession(session);
    const scopeDirectory = await this._ensureDownloadScope(
      scopeKind,
      scopeId,
    );
    const paths = this._downloadPaths(scopeKind, scopeId, downloadId);
    await rejectDownloadSymlinkIfPresent(
      paths.entryDirectory,
      'browser_download_entry_symlink',
    );
    try {
      await lstat(paths.entryDirectory);
      fail('browser_download_id_collision', downloadId);
    } catch (error) {
      if (error?.code !== 'ENOENT') throw error;
    }
    const temporaryDirectory = downloadChildPath(
      scopeDirectory,
      `.partial-${downloadId}-${randomUUID()}`,
    );
    await mkdir(temporaryDirectory, { mode: 0o700 });
    const temporaryPayload = downloadChildPath(
      temporaryDirectory,
      'payload.bin',
    );
    const temporaryReceipt = downloadChildPath(
      temporaryDirectory,
      'receipt.json',
    );
    let payloadHandle;
    try {
      const stream = await download.createReadStream();
      if (!stream || typeof stream[Symbol.asyncIterator] !== 'function') {
        fail('browser_download_stream_unavailable');
      }
      payloadHandle = await open(temporaryPayload, 'wx', 0o600);
      const digest = createHash('sha256');
      let bytes = 0;
      for await (const rawChunk of stream) {
        const chunk = Buffer.isBuffer(rawChunk)
          ? rawChunk
          : Buffer.from(rawChunk);
        bytes += chunk.length;
        if (bytes > this.downloadLimits.maxPayloadBytes) {
          fail('browser_download_too_large');
        }
        if (
          this.quarantineBytes + bytes >
          this.downloadLimits.maxQuarantineBytes
        ) {
          fail('browser_download_quarantine_quota_exceeded');
        }
        digest.update(chunk);
        await payloadHandle.write(chunk);
      }
      await payloadHandle.sync();
      await payloadHandle.close();
      payloadHandle = null;
      if (typeof download.failure === 'function') {
        const failureReason = await download.failure();
        if (failureReason !== null) {
          fail('browser_download_failed', boundedScalar(failureReason, 1024));
        }
      }
      const sourceUrl = sanitizedNetworkUrl(download.url());
      const suggestedFilename = sanitizeDownloadFilename(
        download.suggestedFilename(),
      );
      const now = this.clock();
      if (!(now instanceof Date) || Number.isNaN(now.valueOf())) {
        fail('browser_download_clock_invalid');
      }
      const receipt = createDownloadReceipt({
        downloadId,
        session,
        pageId,
        sourceUrl,
        suggestedFilename,
        relativePath: downloadRelativePath(
          scopeKind,
          scopeId,
          downloadId,
        ),
        bytes,
        sha256: digest.digest('hex'),
        locatorStrategy,
        locatorIndex,
        createdAt: now.toISOString(),
      });
      const receiptBytes = Buffer.from(`${JSON.stringify(receipt)}\n`);
      if (receiptBytes.length > this.downloadLimits.maxReceiptBytes) {
        fail('browser_download_receipt_too_large');
      }
      await writeFile(temporaryReceipt, receiptBytes, {
        mode: 0o600,
        flag: 'wx',
      });
      await rename(temporaryDirectory, paths.entryDirectory);
      this.downloadReceipts.set(downloadId, receipt);
      this.quarantineBytes += bytes;
      return receipt;
    } catch (error) {
      if (payloadHandle) {
        try {
          await payloadHandle.close();
        } catch {
          // Preserve the primary quarantine failure.
        }
      }
      if (
        (error?.code === 'browser_download_too_large' ||
          error?.code === 'browser_download_quarantine_quota_exceeded') &&
        typeof download.cancel === 'function'
      ) {
        try {
          await download.cancel();
        } catch {
          // Preserve the primary policy failure.
        }
      }
      await rm(temporaryDirectory, { recursive: true, force: true });
      throw error;
    }
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
      downloadsEnabled: session.downloadsEnabled,
      createdAt: session.createdAt,
    };
  }

  async openSession({
    kind = 'ephemeral',
    profileId = null,
    downloadsEnabled = false,
  } = {}) {
  await this.initialize();
  if (!SESSION_MODES.has(kind)) fail('browser_session_kind_invalid');
  if (typeof downloadsEnabled !== 'boolean') {
    fail('browser_download_opt_in_invalid');
  }
  if (this.sessions.size >= this.quotas.maxSessions) {
    fail('browser_session_quota_exceeded');
  }
  if (
    kind !== 'persistent' &&
    profileId !== null &&
    profileId !== undefined
  ) {
    fail('browser_ephemeral_profile_forbidden');
  }

  let storageState = null;
  let statePath = null;
  let profileDirectory = null;
  let existingProfile = false;
  let profileReserved = false;
  let context = null;

  if (kind === 'persistent') {
    assertIdentifier(profileId, PROFILE_ID, 'browser_profile_id_invalid');
    if (this.activePersistentProfiles.has(profileId)) {
      fail('browser_profile_in_use', profileId);
    }
    existingProfile = this.persistentProfiles.has(profileId);
    if (
      !existingProfile &&
      this.persistentProfiles.size >= this.quotas.maxPersistentProfiles
    ) {
      fail('browser_persistent_profile_quota_exceeded');
    }
    // Reserve before the first asynchronous filesystem or browser call so
    // concurrent opens cannot race the same persistent profile.
    this.activePersistentProfiles.add(profileId);
    profileReserved = true;
  }

  try {
    if (kind === 'persistent') {
      profileDirectory = childPath(
        this.stateDirectory,
        'profiles',
        profileId,
      );
      await rejectSymlinkIfPresent(
        profileDirectory,
        'browser_profile_directory_symlink',
      );
      await mkdir(profileDirectory, { recursive: true, mode: 0o700 });
      statePath = childPath(profileDirectory, 'storage-state.json');
      storageState = await readStorageState(statePath);
    }

    // Identifiers are allocated only after all request/profile policy
    // checks pass. Rejected requests must have no observable ID side effect.
    const sessionId = this._nextId('session');
    if (this.sessions.has(sessionId)) fail('browser_session_id_collision');

    context = await this.browser.newContext({
      acceptDownloads: downloadsEnabled,
      ...(storageState ? { storageState } : {}),
    });
    const session = {
      sessionId,
      kind,
      profileId: kind === 'persistent' ? profileId : null,
      downloadsEnabled,
      statePath,
      context,
      pages: new Map(),
      createdAt: new Date().toISOString(),
    };
    this.sessions.set(sessionId, session);
    if (kind === 'persistent') {
      this.persistentProfiles.add(profileId);
      // The reservation remains active and is now owned by the tracked
      // session. Only successful tracked cleanup releases it.
      profileReserved = false;
    }
    return this._metadata(session);
  } catch (error) {
    if (context) {
      try {
        await context.close();
      } catch {
        // Preserve the primary open failure; no session was published.
      }
    }
    if (profileReserved) {
      this.activePersistentProfiles.delete(profileId);
    }
    if (kind === 'persistent' && !existingProfile && profileDirectory) {
      try {
        await rm(profileDirectory, { recursive: true, force: true });
      } catch {
        // Preserve the primary failure. A later initialization rejects
        // unsafe symlinks and re-evaluates the durable profile inventory.
      }
    }
    throw error;
  }
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
    const pageId = this._nextId('page');
    if (session.pages.has(pageId)) fail('browser_page_id_collision');
    const page = await session.context.newPage();
    session.pages.set(pageId, page);
    this.pageTelemetry.set(page, createPageTelemetry(page));
    return { pageId, sessionId };
  }

  async observePage(sessionId, pageId) {
  const session = this._session(sessionId);
  assertIdentifier(pageId, GENERATED_ID, 'browser_page_id_invalid');
  const page = session.pages.get(pageId);
  if (!page) fail('browser_page_not_found', pageId);
  let telemetry = this.pageTelemetry.get(page);
  if (!telemetry) {
    telemetry = createPageTelemetry(page);
    this.pageTelemetry.set(page, telemetry);
  }
  const captured = await capturePageObservation(page, telemetry);
  return {
    sessionId,
    pageId,
    observationHash: captured.observationHash,
    observation: captured.observation,
  };
}

  async performAction(sessionId, pageId, request) {
  const session = this._session(sessionId);
  assertIdentifier(pageId, GENERATED_ID, 'browser_page_id_invalid');
  const page = session.pages.get(pageId);
  if (!page) fail('browser_page_not_found', pageId);
  let telemetry = this.pageTelemetry.get(page);
  if (!telemetry) {
    telemetry = createPageTelemetry(page);
    this.pageTelemetry.set(page, telemetry);
  }
  const result = await performPageAction(page, request, telemetry);
  return { sessionId, pageId, ...result };
}

  async performVisualAction(sessionId, pageId, request) {
    const session = this._session(sessionId);
    assertIdentifier(pageId, GENERATED_ID, 'browser_page_id_invalid');
    const page = session.pages.get(pageId);
    if (!page) fail('browser_page_not_found', pageId);
    let telemetry = this.pageTelemetry.get(page);
    if (!telemetry) {
      telemetry = createPageTelemetry(page);
      this.pageTelemetry.set(page, telemetry);
    }
    const result = await performVerifiedVisualAction(
      page,
      request,
      telemetry,
    );
    return { sessionId, pageId, ...result };
  }

  async performDownload(sessionId, pageId, rawRequest) {
    const session = this._session(sessionId);
    if (session.downloadsEnabled !== true) {
      fail('browser_downloads_disabled', sessionId);
    }
    if (
      this.downloadReceipts.size >= this.downloadLimits.maxReceipts ||
      this.quarantineBytes >= this.downloadLimits.maxQuarantineBytes
    ) {
      fail('browser_download_quarantine_quota_exceeded');
    }
    assertIdentifier(pageId, GENERATED_ID, 'browser_page_id_invalid');
    const page = session.pages.get(pageId);
    if (!page) fail('browser_page_not_found', pageId);
    if (typeof page.waitForEvent !== 'function') {
      fail('browser_download_event_api_unavailable');
    }
    const request = validatePageDownloadRequest(rawRequest);
    const resolved = await resolvePageActionLocator(page, request.locators);
    if (!resolved.locator || typeof resolved.locator.click !== 'function') {
      fail('browser_locator_api_unavailable', resolved.descriptor.strategy);
    }
    const [download] = await Promise.all([
      page.waitForEvent('download', { timeout: request.timeoutMs }),
      resolved.locator.click({ timeout: request.timeoutMs }),
    ]);
    const downloadId = this._nextId('download');
    if (this.downloadReceipts.has(downloadId)) {
      fail('browser_download_id_collision', downloadId);
    }
    return this._quarantineDownload({
      download,
      downloadId,
      session,
      pageId,
      locatorStrategy: resolved.descriptor.strategy,
      locatorIndex: resolved.index,
    });
  }

  async listDownloads() {
    const verified = [];
    for (const receipt of this.downloadReceipts.values()) {
      const scopeId =
        receipt.sessionKind === 'persistent'
          ? receipt.profileId
          : receipt.sessionId;
      const stored = await this._readStoredDownload(
        receipt.sessionKind,
        scopeId,
        receipt.downloadId,
      );
      if (stored.receiptHash !== receipt.receiptHash) {
        fail('browser_download_receipt_inventory_mismatch');
      }
      verified.push(stored);
    }
    return verified.sort(
      (left, right) =>
        left.createdAt.localeCompare(right.createdAt) ||
        left.downloadId.localeCompare(right.downloadId),
    );
  }

  async discardDownload(downloadId, receiptHash) {
    assertIdentifier(downloadId, DOWNLOAD_ID, 'browser_download_id_invalid');
    if (typeof receiptHash !== 'string' || !SHA256_HEX.test(receiptHash)) {
      fail('browser_download_receipt_hash_invalid');
    }
    const tracked = this.downloadReceipts.get(downloadId);
    if (!tracked) fail('browser_download_not_found', downloadId);
    if (tracked.receiptHash !== receiptHash) {
      fail('browser_download_receipt_identity_mismatch', 'receiptHash');
    }
    const scopeId =
      tracked.sessionKind === 'persistent'
        ? tracked.profileId
        : tracked.sessionId;
    const stored = await this._readStoredDownload(
      tracked.sessionKind,
      scopeId,
      downloadId,
    );
    if (stored.receiptHash !== receiptHash) {
      fail('browser_download_receipt_inventory_mismatch');
    }
    const paths = this._downloadPaths(
      tracked.sessionKind,
      scopeId,
      downloadId,
    );
    await rm(paths.entryDirectory, { recursive: true, force: false });
    this.downloadReceipts.delete(downloadId);
    this.quarantineBytes -= tracked.content.bytes;
    return { downloadId, discarded: true };
  }

  async closePage(sessionId, pageId) {
    const session = this._session(sessionId);
    assertIdentifier(pageId, GENERATED_ID, 'browser_page_id_invalid');
    const page = session.pages.get(pageId);
    if (!page) fail('browser_page_not_found', pageId);
    await page.close();
    this.pageTelemetry.delete(page);
    session.pages.delete(pageId);
    return { pageId, sessionId, closed: true };
  }

  async closeSession(sessionId) {
    const session = this._session(sessionId);
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
      try {
        await page.close();
        this.pageTelemetry.delete(page);
        session.pages.delete(pageId);
      } catch (error) {
        primaryError ??= error;
      }
    }
    let contextClosed = false;
    try {
      await session.context.close();
      contextClosed = true;
      session.pages.clear();
    } catch (error) {
      primaryError ??= error;
    }
    if (contextClosed) {
      this.sessions.delete(sessionId);
      if (session.kind === 'persistent') {
        this.activePersistentProfiles.delete(session.profileId);
      }
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
    if (message.schemaVersion !== READY_SCHEMA_VERSION) {
      fail('browser_session_request_schema_invalid');
    }
    switch (message.type) {
      case 'session.open':
        return this.openSession({
          kind: message.kind,
          profileId: message.profileId ?? null,
          downloadsEnabled: message.downloadsEnabled ?? false,
        });
      case 'session.list':
        return { sessions: this.listSessions() };
      case 'session.close':
        return this.closeSession(message.sessionId);
      case 'page.open':
        return this.openPage(message.sessionId);
      case 'page.list':
        return { pages: this.listPages(message.sessionId) };
      case 'page.observe':
        return this.observePage(message.sessionId, message.pageId);
      case 'page.action':
        return this.performAction(
          message.sessionId,
          message.pageId,
          message.actionRequest,
        );
      case 'page.visualAction':
        return this.performVisualAction(
          message.sessionId,
          message.pageId,
          message.visualActionRequest,
        );
      case 'page.download':
        return this.performDownload(
          message.sessionId,
          message.pageId,
          message.downloadRequest,
        );
      case 'download.list':
        return { downloads: await this.listDownloads() };
      case 'download.discard':
        return this.discardDownload(
          message.downloadId,
          message.receiptHash,
        );
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
        downloadPolicy: registry.downloadLimits,
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
