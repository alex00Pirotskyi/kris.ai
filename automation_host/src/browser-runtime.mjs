import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { createReadStream } from 'node:fs';
import {
  access,
  mkdir,
  readFile,
  realpath,
  rm,
} from 'node:fs/promises';
import path from 'node:path';
import { createInterface } from 'node:readline';
import { pathToFileURL } from 'node:url';

import { chromium } from 'playwright-core';

const READY_SCHEMA_VERSION = '1.0.0';
const PROTOCOL = 'stdio-json-v1';
const MAX_STDERR_BYTES = 1024 * 1024;

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

function requireAbsolute(value, code) {
  if (!path.isAbsolute(value)) fail(code, value);
  return path.resolve(value);
}

export function parseArgs(argv) {
  const allowed = new Set([
    '--mode',
    '--protocol',
    '--browser-executable',
    '--browser-root',
    '--runtime-manifest',
    '--state-directory',
  ]);
  for (let i = 0; i < argv.length; i += 2) {
    if (!allowed.has(argv[i]) || i + 1 >= argv.length) {
      fail('argument_set_invalid', argv[i] ?? 'missing');
    }
  }
  const mode = requiredValue(argv, '--mode');
  const protocol = requiredValue(argv, '--protocol');
  if (mode !== 'probe') fail('mode_not_supported', mode);
  if (protocol !== PROTOCOL) fail('protocol_not_supported', protocol);
  return {
    mode,
    protocol,
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

export function chromiumProbeArgs(profileDirectory) {
  return [
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
    'about:blank',
  ];
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

async function waitForExit(child, timeoutMs) {
  if (child.exitCode !== null) return child.exitCode;
  const result = await Promise.race([
    once(child, 'exit').then(([code]) => ({ exited: true, code })),
    new Promise((resolve) =>
      setTimeout(() => resolve({ exited: false, code: null }), timeoutMs),
    ),
  ]);
  return result.exited ? result.code : null;
}

async function terminateBrowserTree(child) {
  if (child.exitCode !== null) return;
  if (process.platform === 'win32') {
    const killer = spawn(
      'taskkill.exe',
      ['/PID', String(child.pid), '/T', '/F'],
      { stdio: 'ignore', windowsHide: true },
    );
    await waitForExit(killer, 5_000);
  } else {
    try {
      process.kill(-child.pid, 'SIGTERM');
    } catch (error) {
      if (error?.code !== 'ESRCH') throw error;
    }
    if ((await waitForExit(child, 2_000)) === null) {
      try {
        process.kill(-child.pid, 'SIGKILL');
      } catch (error) {
        if (error?.code !== 'ESRCH') throw error;
      }
    }
  }
  if ((await waitForExit(child, 5_000)) === null) fail('chromium_tree_stop_timeout');
}

async function waitForShutdown() {
  const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
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
}

export async function runProbe(options, env = process.env) {
  const binding = await validateManifestBinding(options, env);
  const profileDirectory = path.join(options.stateDirectory, 'chromium-profile');
  await rm(profileDirectory, { recursive: true, force: true });
  await mkdir(profileDirectory, { recursive: true });
  const child = spawn(
    options.browserExecutable,
    chromiumProbeArgs(profileDirectory),
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
  try {
    const port = await waitForDevToolsPort(profileDirectory, child);
    browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
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
      })}\n`,
    );
    await waitForShutdown();
  } catch (error) {
    if (child.exitCode !== null && stderrTail()) {
      error.message = `${error.message}; chromiumStderr=${stderrTail()}`;
    }
    throw error;
  } finally {
    if (browser) {
      try {
        await browser.close();
      } catch {
        // Browser may already have exited; tree cleanup below remains authoritative.
      }
    }
    if ((await waitForExit(child, 3_000)) === null) {
      await terminateBrowserTree(child);
    }
    await rm(profileDirectory, { recursive: true, force: true });
  }
}

async function main() {
  try {
    const options = parseArgs(process.argv.slice(2));
    await runProbe(options);
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
