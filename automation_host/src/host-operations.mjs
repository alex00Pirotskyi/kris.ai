import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import {
  launchWindowsManagedProcess,
  registerProcess,
  terminateTree,
} from './process-tree.mjs';

const execFileAsync = promisify(execFile);
const idPattern = /^[A-Za-z0-9@+._:/-]{1,200}$/;
const servicePattern = /^[A-Za-z0-9_.@-]{1,200}$/;
const receiptStatuses = new Set([
  'authorized',
  'started',
  'succeeded',
  'failed',
  'cancelled',
  'killed',
  'rolledBack',
  'unknown',
  'unsupported',
]);

function now() {
  return new Date().toISOString();
}
function support(status, reason, requiresElevation = false) {
  return { status, reason, requiresElevation };
}
function normalizedReceiptStatus(status) {
  if (receiptStatuses.has(status)) return status;
  if (status === 'blocked' || status === 'unavailable') return 'unsupported';
  return 'unknown';
}
function effectReceipt(
  authorization,
  operation,
  status,
  reversibility,
  details = {},
) {
  const completedAt = now();
  return {
    schemaVersion: '1.0.0',
    effectId: `${operation}-${crypto.randomUUID()}`,
    runId: authorization.runId,
    taskId: authorization.taskId,
    operation,
    status: normalizedReceiptStatus(status),
    reversibility,
    startedAt: completedAt,
    completedAt,
    details,
  };
}
function response(
  authorization,
  operation,
  {
    status = 'succeeded',
    reversibility = 'irreversible',
    supportStatus = 'supported',
    reason = 'native_adapter',
    requiresElevation = false,
    details = {},
    output = {},
    extra = {},
  } = {},
) {
  return {
    status: status === 'succeeded' ? 'ok' : status,
    support: support(supportStatus, reason, requiresElevation),
    receipt: effectReceipt(
      authorization,
      operation,
      status,
      reversibility,
      details,
    ),
    output,
    ...extra,
  };
}
function minimalEnvironment() {
  const keys = [
    'PATH',
    'Path',
    'SystemRoot',
    'WINDIR',
    'HOME',
    'USERPROFILE',
    'TMP',
    'TEMP',
    'TMPDIR',
    'LANG',
    'LC_ALL',
    'DISPLAY',
    'WAYLAND_DISPLAY',
    'XDG_RUNTIME_DIR',
    'DBUS_SESSION_BUS_ADDRESS',
  ];
  return Object.fromEntries(
    keys
      .filter((key) => process.env[key] !== undefined)
      .map((key) => [key, process.env[key]]),
  );
}
function bounded(value, limit = 8192) {
  const text = String(value ?? '');
  return text.length <= limit ? text : text.slice(text.length - limit);
}
function rootsFromAuthorization(authorization) {
  const roots = authorization.capabilityGrant?.scope?.paths?.roots;
  return Array.isArray(roots)
    ? roots.filter((value) => typeof value === 'string')
    : [];
}
function pathInside(candidate, root) {
  const normalizedCandidate = path.resolve(candidate);
  const normalizedRoot = path.resolve(root);
  const relative = path.relative(normalizedRoot, normalizedCandidate);
  return (
    relative === '' ||
    (!relative.startsWith('..') && !path.isAbsolute(relative))
  );
}
function assertAuthorizedPath(authorization, candidate) {
  const roots = rootsFromAuthorization(authorization);
  if (!roots.some((root) => pathInside(candidate, root))) {
    throw new Error('path_outside_grant_scope');
  }
}
function packageManagerCommands(manager, operation, packages) {
  if (process.platform === 'win32' && manager === 'choco') {
    const verb =
      operation === 'remove'
        ? 'uninstall'
        : operation === 'update'
          ? 'upgrade'
          : 'install';
    return {
      executable: 'choco.exe',
      arguments: [verb, ...packages, '--noop', '--yes', '--limit-output'],
    };
  }
  if (process.platform === 'win32' && manager === 'winget') {
    return {
      executable: 'winget.exe',
      arguments: [
        'show',
        '--exact',
        '--id',
        packages[0],
        '--disable-interactivity',
      ],
    };
  }
  if (process.platform === 'darwin' && manager === 'brew') {
    const verb =
      operation === 'remove'
        ? 'uninstall'
        : operation === 'update'
          ? 'upgrade'
          : 'install';
    return { executable: 'brew', arguments: [verb, '--dry-run', ...packages] };
  }
  if (process.platform === 'linux' && manager === 'apt') {
    const verb = operation === 'remove' ? 'remove' : 'install';
    return {
      executable: 'apt-get',
      arguments: ['--simulate', verb, ...packages],
    };
  }
  if (process.platform === 'linux' && manager === 'dnf') {
    const verb =
      operation === 'remove'
        ? 'remove'
        : operation === 'update'
          ? 'upgrade'
          : 'install';
    return { executable: 'dnf', arguments: [verb, '--assumeno', ...packages] };
  }
  if (process.platform === 'linux' && manager === 'pacman') {
    return {
      executable: 'pacman',
      arguments: [operation === 'remove' ? '-Rp' : '-Sp', ...packages],
    };
  }
  return null;
}
async function runBounded(executable, args, options = {}) {
  try {
    const { stdout, stderr } = await execFileAsync(executable, args, {
      cwd: options.cwd,
      env: options.env ?? minimalEnvironment(),
      timeout: options.timeout ?? 60_000,
      maxBuffer: options.maxBuffer ?? 1024 * 1024,
      windowsHide: true,
    });
    return { exitCode: 0, stdout: bounded(stdout), stderr: bounded(stderr) };
  } catch (error) {
    return {
      exitCode: Number.isSafeInteger(error.code) ? error.code : 1,
      stdout: bounded(error.stdout),
      stderr: bounded(error.stderr || error.message),
    };
  }
}
async function discoverSdk(command) {
  const locator = process.platform === 'win32' ? 'where.exe' : '/usr/bin/which';
  const located = await runBounded(locator, [command]);
  if (located.exitCode !== 0) return null;
  const executable = located.stdout.split(/\r?\n/).find(Boolean);
  if (!executable) return null;
  const version = await runBounded(executable, ['--version']);
  return {
    name: command,
    path: executable,
    versionOutputSha256: crypto
      .createHash('sha256')
      .update(`${version.stdout}${version.stderr}`)
      .digest('hex'),
    exitCode: version.exitCode,
    provenance: 'authenticated_worker_native_path_lookup',
  };
}


function sha256Buffer(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

async function readBoundJsonFile(fileName, expectedSha256, label) {
  if (!fileName || !path.isAbsolute(fileName)) {
    throw new Error(`${label}_path_missing`);
  }
  const bytes = await fs.readFile(fileName);
  const digest = sha256Buffer(bytes);
  if (!/^[0-9a-f]{64}$/.test(String(expectedSha256 ?? '')) || digest !== expectedSha256) {
    throw new Error(`${label}_digest_mismatch`);
  }
  const value = JSON.parse(bytes.toString('utf8'));
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label}_invalid`);
  }
  return { value, digest };
}

async function controlledRunnerBinding(runtimeConfig) {
  const receipt = await readBoundJsonFile(
    runtimeConfig.runnerAttestationReceipt,
    runtimeConfig.runnerAttestationSha256,
    'runner_attestation',
  );
  const row = receipt.value;
  if (
    row.schemaVersion !== '2.0.0' ||
    row.receiptType !== 'p2-controlled-runner-validation-v2' ||
    row.status !== 'passed' ||
    row.runnerConfigurationVerified !== true ||
    row.cleanupReceiptVerified !== true ||
    row.authorityProvisioningVerified !== true ||
    row.resourceProvisioningVerified !== true ||
    row.runnerGroup !== 'kristin-p2-controlled' ||
    row.noConcurrentUntrustedWorkload !== true ||
    row.commitSha !== runtimeConfig.commitSha ||
    String(row.workflowRunId ?? '') !== String(runtimeConfig.workflowRunId ?? '') ||
    String(row.runnerName ?? '') !== String(runtimeConfig.runnerName ?? '') ||
    row.interactiveSession?.loggedIn !== true ||
    !row.interactiveSession?.identity ||
    row.interactiveDesktopAttested !== true ||
    row.behavioralLaneAttested !== true
  ) {
    throw new Error('runner_attestation_binding_invalid');
  }
  return receipt;
}

function controlledPackageConfiguration(runtimeConfig) {
  const manager = String(runtimeConfig.controlledPackageManager ?? '');
  const name = String(runtimeConfig.controlledPackageName ?? '');
  const source = String(runtimeConfig.controlledPackageSource ?? '');
  const prefix = String(runtimeConfig.controlledPackagePrefix ?? '');
  const npm = String(runtimeConfig.npmExecutable ?? '');
  if (
    manager !== 'npm-local-controlled' ||
    !idPattern.test(name) ||
    !path.isAbsolute(source) ||
    !path.isAbsolute(prefix) ||
    !path.isAbsolute(npm)
  ) {
    throw new Error('controlled_package_configuration_invalid');
  }
  return { manager, name, source: path.resolve(source), prefix: path.resolve(prefix), npm: path.resolve(npm) };
}

function controlledPackageArguments(config, packageOperation, dryRun) {
  const common = [
    '--prefix', config.prefix,
    '--ignore-scripts',
    '--no-audit',
    '--no-fund',
    '--loglevel', 'error',
  ];
  if (dryRun) common.push('--dry-run');
  if (packageOperation === 'remove') {
    return ['uninstall', config.name, ...common];
  }
  return ['install', config.source, ...common];
}

function controlledPackageManifest(config) {
  const parts = config.name.split('/');
  return path.join(config.prefix, 'node_modules', ...parts, 'package.json');
}

async function inspectControlledPackage(config) {
  const manifestPath = controlledPackageManifest(config);
  try {
    const bytes = await fs.readFile(manifestPath);
    const manifest = JSON.parse(bytes.toString('utf8'));
    return {
      installed: manifest?.name === config.name,
      name: String(manifest?.name ?? ''),
      version: String(manifest?.version ?? ''),
      manifestSha256: sha256Buffer(bytes),
    };
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return { installed: false, name: config.name, version: '', manifestSha256: null };
    }
    throw error;
  }
}

async function controlledServiceConfiguration(runtimeConfig) {
  await controlledRunnerBinding(runtimeConfig);
  const attestation = await readBoundJsonFile(
    runtimeConfig.nativeServiceAttestation,
    runtimeConfig.nativeServiceAttestationSha256,
    'service_attestation',
  );
  const row = attestation.value;
  const expectedProvider =
    process.platform === 'linux'
      ? 'systemd-user'
      : process.platform === 'darwin'
        ? 'launchagent-user'
        : process.platform === 'win32'
          ? 'scheduled-task-user'
          : '';
  if (
    row.schemaVersion !== '2.0.0' ||
    row.status !== 'provisioned' ||
    row.serviceId !== runtimeConfig.nativeServiceId ||
    row.provider !== expectedProvider ||
    runtimeConfig.nativeServiceProvider !== expectedProvider ||
    row.userScoped !== true ||
    row.elevationRequired !== false ||
    row.completionEligible !== true ||
    row.commitSha !== runtimeConfig.commitSha ||
    row.runnerAttestationSha256 !== runtimeConfig.runnerAttestationSha256
  ) {
    throw new Error('controlled_service_attestation_invalid');
  }
  return {
    serviceId: String(row.serviceId),
    provider: expectedProvider,
    attestationSha256: attestation.digest,
  };
}

function controlledServiceCommand(config, operation) {
  if (config.provider === 'systemd-user') {
    if (operation === 'status') return { executable: 'systemctl', arguments: ['--user', 'is-active', config.serviceId] };
    return { executable: 'systemctl', arguments: ['--user', operation, config.serviceId] };
  }
  if (config.provider === 'launchagent-user') {
    const domain = `gui/${process.getuid()}/${config.serviceId}`;
    if (operation === 'status') return { executable: 'launchctl', arguments: ['print', domain] };
    if (operation === 'start') return { executable: 'launchctl', arguments: ['kickstart', '-k', domain] };
    return { executable: 'launchctl', arguments: ['kill', 'SIGTERM', domain] };
  }
  if (config.provider === 'scheduled-task-user') {
    if (operation === 'status') return { executable: 'schtasks.exe', arguments: ['/Query', '/TN', config.serviceId, '/FO', 'LIST', '/V'] };
    if (operation === 'start') return { executable: 'schtasks.exe', arguments: ['/Run', '/TN', config.serviceId] };
    return { executable: 'schtasks.exe', arguments: ['/End', '/TN', config.serviceId] };
  }
  throw new Error('controlled_service_provider_invalid');
}

async function inspectControlledService(config) {
  const command = controlledServiceCommand(config, 'status');
  const result = await runBounded(command.executable, command.arguments, { timeout: 30_000 });
  let running = false;
  if (config.provider === 'systemd-user') running = result.exitCode === 0 && result.stdout.trim() === 'active';
  else if (config.provider === 'launchagent-user') running = result.exitCode === 0;
  else running = result.exitCode === 0 && /status:\s*running/i.test(result.stdout);
  return {
    state: running ? 'running' : 'stopped',
    commandExitCode: result.exitCode,
    stdoutSha256: sha256Buffer(Buffer.from(result.stdout)),
    stderrSha256: sha256Buffer(Buffer.from(result.stderr)),
  };
}

async function waitForControlledService(config, expectedState) {
  let observation = await inspectControlledService(config);
  for (let attempt = 0; attempt < 40 && observation.state !== expectedState; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 250));
    observation = await inspectControlledService(config);
  }
  if (observation.state !== expectedState) throw new Error('controlled_service_postcondition_failed');
  return observation;
}


function validateCommandPayload(payload, authorization) {
  const executable = String(payload.executable ?? '');
  const cwd = String(payload.cwd ?? '');
  const args = payload.arguments ?? [];
  const environmentDelta = payload.environmentDelta ?? {};
  const stdinBase64 = String(payload.stdinBase64 ?? '');
  const deadlineMs = Number(payload.deadlineMs ?? 300_000);
  const maxStdoutBytes = Number(payload.maxStdoutBytes ?? 1024 * 1024);
  const maxStderrBytes = Number(payload.maxStderrBytes ?? 1024 * 1024);
  if (
    executable.length < 1 || executable.length > 4096 || executable.includes('\0') ||
    cwd.length < 1 || cwd.length > 4096 || cwd.includes('\0') || !path.isAbsolute(cwd) ||
    !Array.isArray(args) || args.length > 256 ||
    args.some((value) => typeof value !== 'string' || value.length > 32768 || value.includes('\0')) ||
    !environmentDelta || typeof environmentDelta !== 'object' || Array.isArray(environmentDelta) ||
    Object.keys(environmentDelta).length > 128 ||
    !/^[A-Za-z0-9+/]*={0,2}$/.test(stdinBase64) ||
    !Number.isSafeInteger(deadlineMs) || deadlineMs < 50 || deadlineMs > 24 * 60 * 60 * 1000 ||
    !Number.isSafeInteger(maxStdoutBytes) || maxStdoutBytes < 0 || maxStdoutBytes > 64 * 1024 * 1024 ||
    !Number.isSafeInteger(maxStderrBytes) || maxStderrBytes < 0 || maxStderrBytes > 64 * 1024 * 1024
  ) {
    throw new Error('command_payload_invalid');
  }
  for (const [key, value] of Object.entries(environmentDelta)) {
    if (!/^[A-Za-z_][A-Za-z0-9_]{0,127}$/.test(key) || /secret|token|password|credential|api.?key|private.?key/i.test(key)) {
      throw new Error('command_environment_key_rejected');
    }
    if (value !== null && (typeof value !== 'string' || value.length > 65536 || value.includes('\0'))) {
      throw new Error('command_environment_value_rejected');
    }
  }
  assertAuthorizedPath(authorization, cwd);
  if (path.isAbsolute(executable)) assertAuthorizedPath(authorization, executable);
  const stdin = Buffer.from(stdinBase64, 'base64');
  if (stdin.length > 4 * 1024 * 1024) throw new Error('command_stdin_budget_exceeded');
  const environment = minimalEnvironment();
  for (const [key, value] of Object.entries(environmentDelta)) {
    if (value === null) delete environment[key];
    else environment[key] = value;
  }
  return {
    executable,
    cwd,
    arguments: [...args],
    environment,
    stdin,
    stdinBase64,
    deadlineMs,
    maxStdoutBytes,
    maxStderrBytes,
  };
}

function appendBounded(target, chunk, limit) {
  const remaining = Math.max(0, limit - target.total);
  if (remaining > 0) target.chunks.push(chunk.subarray(0, remaining));
  target.total += chunk.length;
  if (target.total > limit) target.truncated = true;
}

async function runManagedCommand(payload, authorization, runtimeConfig) {
  const spec = validateCommandPayload(payload, authorization);
  const startedAt = Date.now();
  let registration;
  let exitPromise;
  const stdoutState = { chunks: [], total: 0, truncated: false };
  const stderrState = { chunks: [], total: 0, truncated: false };
  let protocolError = null;
  if (process.platform === 'win32') {
    const launched = await launchWindowsManagedProcess({
      windowsHelper: runtimeConfig.windowsJobHelper,
      executable: spec.executable,
      arguments: spec.arguments,
      cwd: spec.cwd,
      env: spec.environment,
      stdinBase64: spec.stdinBase64,
    });
    registration = launched.registration;
    exitPromise = launched.exitPromise.then((row) => {
      for (const chunk of launched.stdoutChunks) appendBounded(stdoutState, chunk, spec.maxStdoutBytes);
      for (const chunk of launched.stderrChunks) appendBounded(stderrState, chunk, spec.maxStderrBytes);
      protocolError = launched.protocolError;
      return row;
    });
  } else {
    const child = spawn(spec.executable, spec.arguments, {
      cwd: spec.cwd,
      env: spec.environment,
      detached: true,
      stdio: ['pipe', 'pipe', 'pipe'],
      windowsHide: true,
    });
    try {
      registration = await registerProcess(child.pid);
    } catch (error) {
      child.kill('SIGKILL');
      throw error;
    }
    child.stdout.on('data', (chunk) => appendBounded(stdoutState, chunk, spec.maxStdoutBytes));
    child.stderr.on('data', (chunk) => appendBounded(stderrState, chunk, spec.maxStderrBytes));
    child.stdin.end(spec.stdin);
    exitPromise = new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('exit', (code, signal) => resolve({ type: 'exit', exitCode: code, signal }));
    });
  }
  const timeoutSentinel = Symbol('timeout');
  let outcome = await Promise.race([
    exitPromise,
    new Promise((resolve) => setTimeout(() => resolve(timeoutSentinel), spec.deadlineMs)),
  ]);
  let termination = null;
  let timedOut = outcome === timeoutSentinel;
  // Output overrun is treated as cancellation, not as successful truncation, so a
  // child cannot bypass evidence budgets by flooding after its useful output.
  const outputOverflow = stdoutState.truncated || stderrState.truncated;
  if (timedOut || outputOverflow || protocolError) {
    termination = await terminateTree(registration).catch((error) => ({ status: 'unknown', error: String(error?.message ?? error) }));
    if (outcome === timeoutSentinel) {
      outcome = await Promise.race([
        exitPromise,
        new Promise((resolve) => setTimeout(() => resolve({ type: 'unknown', exitCode: null, signal: null }), 5000)),
      ]);
    }
  }
  // On Windows, chunks are emitted by the broker and may arrive before/after exit;
  // the exit promise callback performs the final bounded copy.
  await Promise.resolve(exitPromise).catch(() => {});
  const stdout = Buffer.concat(stdoutState.chunks);
  const stderr = Buffer.concat(stderrState.chunks);
  const exitCode = Number.isSafeInteger(outcome?.exitCode) ? outcome.exitCode : null;
  const status = protocolError
    ? 'unknown'
    : timedOut || outputOverflow
      ? 'killed'
      : exitCode === 0
        ? 'succeeded'
        : 'failed';
  return {
    status,
    registration,
    exitCode,
    stdout,
    stderr,
    outputTruncated: outputOverflow,
    timedOut,
    termination,
    durationMs: Date.now() - startedAt,
  };
}

function operationSupport(operation, runtimeConfig) {
  const interactive = runtimeConfig.interactiveDesktopAttested === true;
  if (operation === 'clipboard' || operation === 'screen') {
    return interactive && runtimeConfig.runnerAttestationReceipt
      ? support('supported', 'controlled_interactive_desktop_attested')
      : support('blocked', 'interactive_desktop_attestation_required');
  }
  if (operation === 'command.run') {
    return support('supported', 'authenticated_managed_process_adapter');
  }
  if (operation === 'package.apply' || operation === 'package.plan') {
    return runtimeConfig.controlledPackageManager === 'npm-local-controlled' &&
      runtimeConfig.runnerAttestationReceipt
      ? support('supported', 'controlled_target_host_package_adapter')
      : support('blocked', 'controlled_package_runner_attestation_required');
  }
  if (operation === 'sdk.discover' || operation === 'application.open' || operation === 'application.close') {
    return support('supported', 'authenticated_automation_host_adapter');
  }
  if (operation === 'service.status' || operation === 'service.start' || operation === 'service.stop') {
    return runtimeConfig.nativeServiceAttestation && runtimeConfig.runnerAttestationReceipt
      ? support('supported', 'controlled_user_service_adapter')
      : support('blocked', 'controlled_user_service_attestation_required');
  }
  return support('unsupported', 'operation_unsupported');
}

export function createHostOperations({
  runtimeConfig = {},
  emit = () => {},
  registrations = new Map(),
} = {}) {
  const applications = new Map();
  const fixtureServices = new Map();
  const fixtureRoot = runtimeConfig.fixtureRoot
    ? path.resolve(runtimeConfig.fixtureRoot)
    : null;
  const adapterScript =
    runtimeConfig.interactiveDesktopAdapter ||
    fileURLToPath(new URL('./interactive-desktop-adapter.mjs', import.meta.url));

  function rememberRegistration(key, registration, authorization, kind) {
    const entry = { registration, authorization, kind };
    registrations.set(key, entry);
    registrations.set(String(registration.identity.pid), entry);
    return entry;
  }
  function forgetRegistration(key, registration) {
    registrations.delete(key);
    if (registration?.identity?.pid) {
      registrations.delete(String(registration.identity.pid));
    }
  }

  async function interactive(operation, payload) {
    if (runtimeConfig.interactiveDesktopAttested !== true) {
      throw new Error('interactive_desktop_attestation_required');
    }
    const child = spawn(process.execPath, [adapterScript], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: minimalEnvironment(),
      windowsHide: true,
    });
    const chunks = [];
    const errors = [];
    let total = 0;
    child.stdout.on('data', (chunk) => {
      total += chunk.length;
      if (total <= 32 * 1024 * 1024) chunks.push(chunk);
    });
    child.stderr.on('data', (chunk) => {
      const errorBytes = errors.reduce((sum, value) => sum + value.length, 0);
      if (errorBytes < 8192) errors.push(chunk);
    });
    child.stdin.end(`${JSON.stringify({ operation, payload })}\n`);
    const exitCode = await new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('exit', resolve);
    });
    if (exitCode !== 0 || total > 32 * 1024 * 1024) {
      throw new Error(
        `interactive_adapter_failed:${bounded(Buffer.concat(errors).toString('utf8'))}`,
      );
    }
    const result = JSON.parse(Buffer.concat(chunks).toString('utf8').trim());
    if (
      result?.status !== 'ok' ||
      result?.postcondition?.observed !== true
    ) {
      throw new Error('interactive_adapter_postcondition_missing');
    }
    return result;
  }

  async function invoke(operation, payload, authorization) {
    if (operation === 'host.support') {
      const queried = String(payload.queriedOperation ?? '');
      const row = operationSupport(queried, runtimeConfig);
      return response(authorization, operation, {
        status: row.status === 'unsupported' || row.status === 'blocked'
          ? 'unsupported'
          : 'succeeded',
        supportStatus: row.status,
        reason: row.reason,
        requiresElevation: row.requiresElevation,
        details: { queriedOperation: queried, contentLogged: false },
      });
    }
    if (operation === 'host.supportMatrix') {
      const names = [
        'package.plan',
        'package.apply',
        'sdk.discover',
        'service.status',
        'service.start',
        'service.stop',
        'application.open',
        'application.close',
        'clipboard',
        'screen',
      ];
      const supportMatrix = Object.fromEntries(
        names.map((name) => [name, operationSupport(name, runtimeConfig)]),
      );
      return response(authorization, operation, {
        details: { operationCount: names.length, contentLogged: false },
        extra: { supportMatrix },
      });
    }
    if (operation === 'command.run') {
      const result = await runManagedCommand(payload, authorization, runtimeConfig);
      const stdoutSha256 = crypto.createHash('sha256').update(result.stdout).digest('hex');
      const stderrSha256 = crypto.createHash('sha256').update(result.stderr).digest('hex');
      return response(authorization, operation, {
        status: result.status,
        reversibility: 'irreversible',
        reason: 'authenticated_managed_process_adapter',
        details: {
          executableSha256: crypto.createHash('sha256').update(String(payload.executable)).digest('hex'),
          cwdSha256: crypto.createHash('sha256').update(String(payload.cwd)).digest('hex'),
          argumentCount: Array.isArray(payload.arguments) ? payload.arguments.length : 0,
          environmentKeys: Object.keys(payload.environmentDelta ?? {}).sort(),
          exitCode: result.exitCode,
          stdoutBytes: result.stdout.length,
          stderrBytes: result.stderr.length,
          stdoutSha256,
          stderrSha256,
          outputTruncated: result.outputTruncated,
          timedOut: result.timedOut,
          processIdentity: result.registration.identity,
          termination: result.termination,
          durationMs: result.durationMs,
          contentLogged: false,
        },
        output: {
          exitCode: result.exitCode,
          stdoutBase64: result.stdout.toString('base64'),
          stderrBase64: result.stderr.toString('base64'),
          stdoutSha256,
          stderrSha256,
          outputTruncated: result.outputTruncated,
          timedOut: result.timedOut,
          processIdentity: result.registration.identity,
          termination: result.termination,
        },
      });
    }
    if (operation === 'package.plan') {
      const manager = String(payload.manager ?? '');
      const packageOperation = String(payload.packageOperation ?? '');
      const packages = payload.packages;
      if (
        !['install', 'remove', 'update'].includes(packageOperation) ||
        !Array.isArray(packages) ||
        packages.length !== 1 ||
        typeof packages[0] !== 'string'
      ) {
        throw new Error('package_plan_invalid');
      }
      if (manager === 'fixture') {
        return response(authorization, operation, {
          status: 'unsupported',
          supportStatus: 'blocked',
          reason: 'fixture_package_manager_ineligible_for_completion',
          details: { completionEligible: false, contentLogged: false },
        });
      }
      const config = controlledPackageConfiguration(runtimeConfig);
      if (manager !== config.manager || packages[0] !== config.name) {
        throw new Error('controlled_package_identity_mismatch');
      }
      await controlledRunnerBinding(runtimeConfig);
      assertAuthorizedPath(authorization, config.source);
      assertAuthorizedPath(authorization, config.prefix);
      const before = await inspectControlledPackage(config);
      const command = controlledPackageArguments(config, packageOperation, true);
      const dryRun = await runBounded(config.npm, command, { timeout: 120_000 });
      if (dryRun.exitCode !== 0) {
        return response(authorization, operation, {
          status: 'failed',
          supportStatus: 'unavailable',
          reason: 'controlled_target_host_package_dry_run_failed',
          details: {
            manager,
            packageOperation,
            packageName: config.name,
            exitCode: dryRun.exitCode,
            contentLogged: false,
          },
        });
      }
      return response(authorization, operation, {
        reversibility: 'reversible',
        reason: 'controlled_target_host_package_dry_run',
        details: {
          manager,
          packageOperation,
          packageName: config.name,
          sourcePathSha256: sha256Buffer(Buffer.from(config.source)),
          installPrefixSha256: sha256Buffer(Buffer.from(config.prefix)),
          runnerAttestationSha256: runtimeConfig.runnerAttestationSha256,
          contentLogged: false,
        },
        output: {
          schemaVersion: '2.0.0',
          status: 'planned',
          manager,
          packageOperation,
          packages: [config.name],
          dryRun: true,
          controlledTargetHost: true,
          sourcePathSha256: sha256Buffer(Buffer.from(config.source)),
          installPrefixSha256: sha256Buffer(Buffer.from(config.prefix)),
          before,
          stdoutSha256: sha256Buffer(Buffer.from(dryRun.stdout)),
          stderrSha256: sha256Buffer(Buffer.from(dryRun.stderr)),
        },
      });
    }
    if (operation === 'package.apply') {
      const plan = payload.plan;
      const config = controlledPackageConfiguration(runtimeConfig);
      if (
        !plan ||
        plan.schemaVersion !== '2.0.0' ||
        plan.status !== 'planned' ||
        plan.manager !== config.manager ||
        plan.controlledTargetHost !== true ||
        !Array.isArray(plan.packages) ||
        plan.packages.length !== 1 ||
        plan.packages[0] !== config.name ||
        !['install', 'remove', 'update'].includes(plan.packageOperation)
      ) {
        throw new Error('controlled_package_plan_binding_invalid');
      }
      await controlledRunnerBinding(runtimeConfig);
      assertAuthorizedPath(authorization, config.source);
      assertAuthorizedPath(authorization, config.prefix);
      const before = await inspectControlledPackage(config);
      const args = controlledPackageArguments(config, plan.packageOperation, false);
      const applied = await runBounded(config.npm, args, { timeout: 180_000 });
      const after = await inspectControlledPackage(config);
      const expectedInstalled = plan.packageOperation !== 'remove';
      const observed = applied.exitCode === 0 && after.installed === expectedInstalled;
      return response(authorization, operation, {
        status: observed ? 'succeeded' : 'failed',
        reversibility: 'reversible',
        supportStatus: observed ? 'supported' : 'unavailable',
        reason: 'controlled_target_host_package_lifecycle',
        details: {
          manager: config.manager,
          packageName: config.name,
          packageOperation: plan.packageOperation,
          commandExitCode: applied.exitCode,
          installedStateObserved: observed,
          runnerAttestationSha256: runtimeConfig.runnerAttestationSha256,
          contentLogged: false,
        },
        output: {
          controlledTargetHost: true,
          completionEligible: observed,
          packageOperation: plan.packageOperation,
          before,
          after,
          stdoutSha256: sha256Buffer(Buffer.from(applied.stdout)),
          stderrSha256: sha256Buffer(Buffer.from(applied.stderr)),
        },
      });
    }
    if (operation === 'sdk.discover') {
      const names = [
        'dart',
        'flutter',
        'node',
        'python',
        'python3',
        'java',
        'rustc',
        'go',
        'cmake',
      ];
      const rows = (await Promise.all(names.map(discoverSdk))).filter(Boolean);
      return response(authorization, operation, {
        reason: 'native_sdk_discovery',
        details: { discoveredCount: rows.length, contentLogged: false },
        output: { sdks: rows },
      });
    }
    if (operation.startsWith('service.')) {
      const id = String(payload.serviceId ?? '');
      if (!servicePattern.test(id)) throw new Error('service_id_invalid');
      if (id.startsWith('fixture.')) {
        return response(authorization, operation, {
          status: 'unsupported',
          supportStatus: 'blocked',
          reason: 'fixture_service_ineligible_for_completion',
          details: { completionEligible: false, contentLogged: false },
        });
      }
      const config = await controlledServiceConfiguration(runtimeConfig);
      if (id !== config.serviceId) throw new Error('controlled_service_identity_mismatch');
      if (operation === 'service.status') {
        const observation = await inspectControlledService(config);
        return response(authorization, operation, {
          reversibility: 'reversible',
          reason: 'controlled_user_service_status',
          details: {
            serviceId: config.serviceId,
            provider: config.provider,
            serviceAttestationSha256: config.attestationSha256,
            runnerAttestationSha256: runtimeConfig.runnerAttestationSha256,
            contentLogged: false,
          },
          output: { ...observation, controlledUserService: true },
        });
      }
      const desired = operation === 'service.start' ? 'running' : 'stopped';
      const verb = operation === 'service.start' ? 'start' : 'stop';
      const command = controlledServiceCommand(config, verb);
      const mutation = await runBounded(command.executable, command.arguments, { timeout: 60_000 });
      const observation = await waitForControlledService(config, desired).catch(() => null);
      const observed = mutation.exitCode === 0 && observation?.state === desired;
      return response(authorization, operation, {
        status: observed ? 'succeeded' : 'failed',
        reversibility: 'reversible',
        supportStatus: observed ? 'supported' : 'unavailable',
        reason: 'controlled_user_service_lifecycle',
        details: {
          serviceId: config.serviceId,
          provider: config.provider,
          commandExitCode: mutation.exitCode,
          desiredState: desired,
          observedState: observation?.state ?? 'unknown',
          serviceAttestationSha256: config.attestationSha256,
          runnerAttestationSha256: runtimeConfig.runnerAttestationSha256,
          elevationExercised: false,
          contentLogged: false,
        },
        output: {
          controlledUserService: true,
          completionEligible: observed,
          state: observation?.state ?? 'unknown',
          mutationStdoutSha256: sha256Buffer(Buffer.from(mutation.stdout)),
          mutationStderrSha256: sha256Buffer(Buffer.from(mutation.stderr)),
          observation,
        },
      });
    }
    if (operation === 'application.open') {
      const target = String(payload.target ?? '');
      if (!target || target.includes('\0')) {
        throw new Error('application_target_invalid');
      }
      if (path.isAbsolute(target)) assertAuthorizedPath(authorization, target);
      let registration;
      let childPid;
      if (process.platform === 'win32') {
        const launched = await launchWindowsManagedProcess({
          windowsHelper: runtimeConfig.windowsJobHelper,
          executable: target,
          arguments: Array.isArray(payload.arguments) ? payload.arguments : [],
          cwd: payload.cwd || undefined,
          env: minimalEnvironment(),
        });
        registration = launched.registration;
        childPid = launched.childPid;
      } else {
        const child = spawn(
          target,
          Array.isArray(payload.arguments) ? payload.arguments : [],
          {
            detached: true,
            stdio: 'ignore',
            windowsHide: true,
            env: minimalEnvironment(),
            cwd: payload.cwd || undefined,
          },
        );
        registration = await registerProcess(child.pid);
        childPid = child.pid;
      }
      const identity = crypto.randomUUID();
      const entry = rememberRegistration(
        `application:${identity}`,
        registration,
        authorization,
        'application',
      );
      applications.set(identity, entry);
      return response(authorization, operation, {
        reversibility: 'reversible',
        reason: 'native_application_process',
        details: { applicationIdentity: identity, contentLogged: false },
        output: {
          identity,
          childPid,
          processIdentity: registration.identity,
        },
      });
    }
    if (operation === 'application.close') {
      const identity = String(payload.identity ?? '');
      const entry = applications.get(identity);
      if (!entry) {
        return response(authorization, operation, {
          status: 'failed',
          supportStatus: 'unavailable',
          reason: 'application_identity_unknown',
          details: { applicationIdentity: identity, contentLogged: false },
        });
      }
      const outcome = await terminateTree(entry.registration);
      applications.delete(identity);
      forgetRegistration(`application:${identity}`, entry.registration);
      return response(authorization, operation, {
        status: ['killed', 'stopped', 'already_exited'].includes(outcome.status)
          ? 'succeeded'
          : 'unknown',
        reversibility: 'irreversible',
        reason: 'native_application_process',
        details: {
          applicationIdentity: identity,
          outcome,
          contentLogged: false,
        },
      });
    }
    if (
      [
        'clipboard.read',
        'clipboard.write',
        'screen.capture',
        'screen.activeWindowMetadata',
      ].includes(operation)
    ) {
      const result = await interactive(operation, payload);
      const details = {
        adapter: 'packaged-interactive-desktop-adapter',
        postconditionSha256: crypto
          .createHash('sha256')
          .update(JSON.stringify(result.postcondition))
          .digest('hex'),
        contentLogged: false,
      };
      return response(authorization, operation, {
        reversibility:
          operation === 'clipboard.write'
            ? 'partiallyReversible'
            : 'irreversible',
        reason: 'interactive_desktop_adapter',
        details,
        output: result.output,
      });
    }
    throw new Error('host_operation_unsupported');
  }

  async function close() {
    for (const entry of [...applications.values(), ...fixtureServices.values()]) {
      await terminateTree(entry.registration).catch(() => {});
    }
    applications.clear();
    fixtureServices.clear();
  }

  return { invoke, close };
}
