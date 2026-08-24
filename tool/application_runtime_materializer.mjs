#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { spawnSync } from 'node:child_process';

const SKIP_PARTS = new Set(['.git', '.dart_tool', 'build', '__pycache__']);
const HEX40 = /^[0-9a-f]{40}$/;
const HEX64 = /^[0-9a-f]{64}$/;
const WINDOWS_ALL_APPLICATION_PACKAGES_SID = '*S-1-15-2-1';
const WINDOWS_ALL_RESTRICTED_APPLICATION_PACKAGES_SID = '*S-1-15-2-2';

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith('--') || value === undefined) fail(`invalid argument near ${key ?? '<end>'}`);
    result[key.slice(2)] = value;
  }
  return result;
}

function sha256File(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function normalizeRelative(value) {
  return value.split(path.sep).join('/');
}

function isInside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function validateInternalSymlink(item, root) {
  const raw = fs.readlinkSync(item);
  if (path.isAbsolute(raw)) fail(`absolute runtime symlink rejected: ${item}`);
  const resolved = fs.realpathSync(item);
  const resolvedRoot = fs.realpathSync(root);
  if (!isInside(resolvedRoot, resolved)) fail(`escaping runtime symlink rejected: ${item}`);
  return raw;
}

function walk(root) {
  const rows = [];
  function visit(directory) {
    const entries = fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      const full = path.join(directory, entry.name);
      rows.push({ full, relative: path.relative(root, full), entry });
      if (entry.isDirectory()) visit(full);
    }
  }
  visit(root);
  return rows;
}

function treeSha256(root, { allowInternalSymlinks = false } = {}) {
  const rows = [];
  for (const item of walk(root)) {
    const relative = normalizeRelative(item.relative);
    const stat = fs.lstatSync(item.full);
    if (stat.isSymbolicLink()) {
      if (!allowInternalSymlinks) fail(`runtime tree symlink rejected: ${item.full}`);
      const raw = validateInternalSymlink(item.full, root);
      rows.push(`${relative}\0@symlink\0${crypto.createHash('sha256').update(raw).digest('hex')}`);
    } else if (stat.isFile()) {
      rows.push(`${relative}\0${sha256File(item.full)}`);
    }
  }
  rows.sort();
  return crypto.createHash('sha256').update(rows.join('\n')).digest('hex');
}

function copyFile(source, destination, executable = false) {
  const stat = fs.lstatSync(source);
  if (!stat.isFile() || stat.isSymbolicLink()) fail(`runtime input missing or symlinked: ${source}`);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(source, destination);
  if (process.platform !== 'win32') fs.chmodSync(destination, executable ? 0o755 : 0o644);
}

function copyTree(source, destination, { preserveInternalSymlinks = false, skipBinShims = false } = {}) {
  const sourceStat = fs.lstatSync(source);
  if (!sourceStat.isDirectory() || sourceStat.isSymbolicLink()) fail(`runtime source tree invalid: ${source}`);
  fs.mkdirSync(destination, { recursive: true });
  for (const item of walk(source)) {
    const parts = item.relative.split(path.sep);
    if (parts.some((part) => SKIP_PARTS.has(part))) continue;
    if (skipBinShims && parts.some((part, index) => part === 'node_modules' && parts[index + 1] === '.bin')) continue;
    const target = path.join(destination, item.relative);
    const stat = fs.lstatSync(item.full);
    if (stat.isSymbolicLink()) {
      if (!preserveInternalSymlinks) fail(`runtime symlink rejected: ${item.full}`);
      const raw = validateInternalSymlink(item.full, source);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.symlinkSync(raw, target, 'file');
    } else if (stat.isDirectory()) {
      fs.mkdirSync(target, { recursive: true });
    } else if (stat.isFile()) {
      copyFile(item.full, target, Boolean(stat.mode & 0o100));
    }
  }
}

function runNode(node, args, { cwd, environment = {}, timeoutMs = 12 * 60 * 1000 } = {}) {
  const nodeDirectory = path.dirname(node);
  const env = {
    ...process.env,
    ...environment,
    PATH: `${nodeDirectory}${path.delimiter}${process.env.PATH ?? ''}`,
    npm_node_execpath: node,
    NODE: node,
    npm_config_update_notifier: 'false',
    npm_config_audit: 'false',
    npm_config_fund: 'false',
  };
  const result = spawnSync(node, args, {
    cwd,
    env,
    encoding: 'utf8',
    timeout: timeoutMs,
    windowsHide: true,
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) fail(`runtime subprocess failed: ${result.error.message}`);
  if (result.status !== 0) {
    const detail = `${result.stderr ?? ''}\n${result.stdout ?? ''}`.trim().slice(-4096);
    fail(`runtime subprocess exit ${result.status}: ${detail}`);
  }
}

function readJson(file) {
  const value = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(`JSON object required: ${file}`);
  return value;
}

function relativeFile(root, file, executable = false) {
  return {
    kind: 'file',
    path: normalizeRelative(path.relative(root, file)),
    sha256: sha256File(file),
    bytes: fs.statSync(file).size,
    executable,
  };
}

function prepareWindowsSandboxAcl(browserRoot) {
  if (process.platform !== 'win32') return;
  const result = spawnSync('icacls.exe', [
    browserRoot,
    '/grant',
    `${WINDOWS_ALL_APPLICATION_PACKAGES_SID}:(OI)(CI)(RX)`,
    `${WINDOWS_ALL_RESTRICTED_APPLICATION_PACKAGES_SID}:(OI)(CI)(RX)`,
    '/T',
    '/Q',
  ], { encoding: 'utf8', windowsHide: true, timeout: 120000 });
  if (result.error) fail(`P3 Windows browser sandbox ACL preparation failed: ${result.error.message}`);
  if (result.status !== 0) {
    const detail = `${result.stderr ?? ''}\n${result.stdout ?? ''}`.replaceAll('\0', '').trim().slice(-2048);
    fail(`P3 Windows browser sandbox ACL preparation failed: ${detail || `exit=${result.status}`}`);
  }
}

function findBrowserExecutable(cacheRoot, relativePath) {
  const normalizedSuffix = relativePath.split('/').join(path.sep);
  const candidates = walk(cacheRoot)
    .filter((item) => fs.lstatSync(item.full).isFile() && item.full.endsWith(normalizedSuffix))
    .map((item) => item.full);
  if (candidates.length !== 1) fail(`exact pinned browser executable not found: ${relativePath}`);
  const executable = candidates[0];
  const relative = path.relative(cacheRoot, executable).split(path.sep);
  if (relative.length < 2) fail('downloaded browser executable outside Playwright cache');
  return { executable, root: path.join(cacheRoot, relative[0]) };
}

function installAutomationHost({ sourceRoot, destination, node, npmCli }) {
  const source = path.join(sourceRoot, 'automation_host');
  copyTree(source, destination, { preserveInternalSymlinks: false, skipBinShims: true });
  runNode(node, [npmCli, 'ci', '--no-audit', '--no-fund'], { cwd: destination });
  const bin = path.join(destination, 'node_modules', '.bin');
  if (fs.existsSync(bin)) fs.rmSync(bin, { recursive: true, force: true });
  for (const item of walk(destination)) {
    if (fs.lstatSync(item.full).isSymbolicLink()) fail(`automation_host symlink rejected after npm ci: ${item.relative}`);
  }
}

function materializeP2(args, lock) {
  const sourceRoot = path.resolve(args['source-root']);
  const destination = path.resolve(args.destination);
  const node = path.resolve(args.node);
  const npmCli = path.resolve(args['npm-cli']);
  const sourceCommit = args['source-commit'];
  const sourceTree = args['source-tree'];
  if (!HEX40.test(sourceCommit ?? '') || !HEX40.test(sourceTree ?? '')) fail('exact source commit/tree required');
  fs.rmSync(destination, { recursive: true, force: true });
  fs.mkdirSync(destination, { recursive: true });
  const stagedNode = path.join(destination, 'node', process.platform === 'win32' ? 'node.exe' : 'node');
  copyFile(node, stagedNode, true);
  installAutomationHost({
    sourceRoot,
    destination: path.join(destination, 'automation_host'),
    node,
    npmCli,
  });
  const configurator = path.join(sourceRoot, 'tool', 'configure-owner-risk-runtime.mjs');
  const contract = path.join(sourceRoot, 'lib', 'product', 'p1_authority_service_contract_v1.dart');
  runNode(stagedNode, [
    configurator,
    '--root', destination,
    '--platform', process.platform === 'win32' ? 'windows' : process.platform === 'darwin' ? 'macos' : 'linux',
    '--source-commit', sourceCommit,
    '--source-tree', sourceTree,
    '--p2-package-sha256', String(lock.p2PackageSha256),
    '--p1-contract', contract,
    '--mode', 'product-current-account',
  ], { cwd: sourceRoot });
  const manifest = path.join(destination, 'runtime-manifest.v3.json');
  if (!fs.existsSync(manifest)) fail('P2 materializer did not emit runtime manifest');
  process.stdout.write(`${JSON.stringify({ kind: 'p2', destination, manifest, manifestSha256: sha256File(manifest) })}\n`);
}

function materializeP3(args, lock, platformLock) {
  const sourceRoot = path.resolve(args['source-root']);
  const destination = path.resolve(args.destination);
  const node = path.resolve(args.node);
  const npmCli = path.resolve(args['npm-cli']);
  const sourceCommit = args['source-commit'];
  const sourceTree = args['source-tree'];
  if (!HEX40.test(sourceCommit ?? '') || !HEX40.test(sourceTree ?? '')) fail('exact source commit/tree required');
  const packageLock = path.join(sourceRoot, 'automation_host', 'package-lock.json');
  if (sha256File(packageLock) !== lock.p3PackageLockSha256) fail('P3 package-lock SHA mismatch');

  fs.rmSync(destination, { recursive: true, force: true });
  fs.mkdirSync(destination, { recursive: true });
  const stagedNode = path.join(destination, 'node', process.platform === 'win32' ? 'node.exe' : 'node');
  copyFile(node, stagedNode, true);
  const automationTarget = path.join(destination, 'automation_host');
  installAutomationHost({ sourceRoot, destination: automationTarget, node, npmCli });

  const packageJson = readJson(path.join(automationTarget, 'package.json'));
  if (packageJson.version !== '2.0.0-p3.1' || packageJson.dependencies?.['playwright-core'] !== lock.p3PlaywrightCoreVersion) {
    fail('P3 automation-host package identity mismatch');
  }
  const playwrightCli = path.join(automationTarget, 'node_modules', 'playwright-core', 'cli.js');
  const browserCache = path.join(destination, '.browser-download');
  runNode(stagedNode, [playwrightCli, 'install', 'chromium'], {
    cwd: automationTarget,
    environment: { PLAYWRIGHT_BROWSERS_PATH: browserCache },
  });
  const browserSpec = platformLock.p3;
  const resolved = findBrowserExecutable(browserCache, browserSpec.browserExecutableRelativePath);
  const browserTarget = path.join(destination, 'browser');
  copyTree(resolved.root, browserTarget, { preserveInternalSymlinks: true });
  fs.rmSync(browserCache, { recursive: true, force: true });
  prepareWindowsSandboxAcl(browserTarget);

  const stagedBrowser = path.join(browserTarget, ...browserSpec.browserExecutableRelativePath.split('/'));
  if (sha256File(stagedBrowser) !== browserSpec.browserExecutableSha256) fail('P3 browser executable digest mismatch');
  const browserTreeSha256 = treeSha256(browserTarget, { allowInternalSymlinks: true });
  if (browserTreeSha256 !== browserSpec.browserTreeSha256) fail('P3 browser tree digest mismatch');

  const worker = path.join(automationTarget, 'src', 'browser-runtime.mjs');
  const stagedPackageLock = path.join(automationTarget, 'package-lock.json');
  const resources = {
    nodeExecutable: relativeFile(destination, stagedNode, true),
    browserWorker: relativeFile(destination, worker, false),
    automationHostRoot: {
      kind: 'directory',
      path: 'automation_host',
      treeSha256: treeSha256(automationTarget),
    },
    browserExecutable: relativeFile(destination, stagedBrowser, true),
    browserRoot: {
      kind: 'directory',
      path: 'browser',
      treeSha256: browserTreeSha256,
    },
    packageLock: relativeFile(destination, stagedPackageLock, false),
  };
  const buildRows = Object.keys(resources).sort().map((key) => `${key}\0${canonical(resources[key])}`);
  buildRows.push(sourceCommit, sourceTree, lock.p3PackageLockSha256, lock.p3BrowserRevision);
  const runtimeBuildSha256 = crypto.createHash('sha256').update(buildRows.join('\n')).digest('hex');
  const manifest = {
    schemaVersion: '1.0.0',
    bundleType: 'kristin-p3-browser-runtime-v1',
    applicationOwned: true,
    workingDirectoryIndependent: true,
    currentWorkingDirectoryUsed: false,
    globalRuntimeRequired: false,
    browserNetworkInstallRequired: false,
    identity: {
      sourceCommit,
      sourceTree,
      runtimeBuildSha256,
      packageLockSha256: lock.p3PackageLockSha256,
      nodeVersion: lock.nodeVersion,
      automationHostPackageVersion: packageJson.version,
      browserEngine: 'chromium',
      browserRevision: lock.p3BrowserRevision,
      browserVersion: lock.p3BrowserVersion,
      playwrightCoreVersion: lock.p3PlaywrightCoreVersion,
    },
    resources,
  };
  const manifestPath = path.join(destination, 'browser-runtime-manifest.v1.json');
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify({ kind: 'p3', destination, manifest: manifestPath, manifestSha256: sha256File(manifestPath), runtimeBuildSha256 })}\n`);
}

function platformKey() {
  const arch = process.arch === 'x64' ? 'x64' : process.arch === 'arm64' ? 'arm64' : process.arch;
  const os = process.platform === 'win32' ? 'windows' : process.platform === 'darwin' ? 'macos' : process.platform;
  return `${os}-${arch}`;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const kind = args.kind;
  if (!['p2', 'p3'].includes(kind)) fail('runtime kind must be p2 or p3');
  const lock = readJson(path.resolve(args.lock));
  if (lock.schemaVersion !== '1.0.0' || lock.acquisitionType !== 'kristin-application-runtime-acquisition-v1') fail('runtime acquisition lock invalid');
  if (!HEX64.test(String(lock.p2PackageSha256 ?? '')) || !HEX64.test(String(lock.p3PackageLockSha256 ?? ''))) fail('runtime acquisition identity invalid');
  const platformLock = lock.platforms?.[platformKey()];
  if (!platformLock) fail(`runtime acquisition platform unsupported: ${platformKey()}`);
  if (kind === 'p2') materializeP2(args, lock);
  else materializeP3(args, lock, platformLock);
}

try {
  main();
} catch (error) {
  console.error(`ERROR: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
}
