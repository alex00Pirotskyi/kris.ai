import { execFile, spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { promisify } from 'node:util';
import fs from 'node:fs/promises';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
const execFileAsync = promisify(execFile);

async function linuxStartToken(pid) {
  const stat = await fs.readFile(`/proc/${pid}/stat`, 'utf8');
  const close = stat.lastIndexOf(')');
  const fields = stat.slice(close + 2).split(' ');
  return fields[19];
}
async function posixPgid(pid) {
  const { stdout } = await execFileAsync('/bin/ps', ['-o', 'pgid=', '-p', String(pid)]);
  const pgid = Number.parseInt(stdout.trim(), 10);
  if (!Number.isSafeInteger(pgid) || pgid <= 1) throw new Error('unsafe_process_group');
  return pgid;
}
export async function processIdentity(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 1) throw new Error('invalid_pid');
  if (process.platform === 'linux') {
    const [start, pgid] = await Promise.all([linuxStartToken(pid), posixPgid(pid)]);
    return { pid, startToken: `linux:${pid}:${start}`, supervisorToken: `posix-pgid:${pgid}:linux:${pid}:${start}`, platformGroupId: String(pgid), platform: process.platform, uid: process.getuid() };
  }
  if (process.platform === 'darwin') {
    const [{ stdout }, pgid] = await Promise.all([
      execFileAsync('/bin/ps', ['-o', 'lstart=', '-p', String(pid)]),
      posixPgid(pid),
    ]);
    return { pid, startToken: `darwin:${pid}:${stdout.trim()}`, supervisorToken: `posix-pgid:${pgid}:darwin:${pid}:${stdout.trim()}`, platformGroupId: String(pgid), platform: process.platform, uid: process.getuid() };
  }
  throw new Error('windows_identity_requires_job_supervisor');
}

function waitForSupervisorReceipt(receipts, expectedStatus, timeoutMs = 7000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error(`windows_job_${expectedStatus}_timeout`));
    }, timeoutMs);
    const handler = (receipt) => {
      if (receipt.status === 'error') {
        cleanup();
        reject(new Error(`windows_job_supervisor_error:${JSON.stringify(receipt)}`));
        return;
      }
      if (receipt.status !== expectedStatus) return;
      cleanup();
      resolve(receipt);
    };
    const cleanup = () => {
      clearTimeout(timer);
      receipts.off('receipt', handler);
    };
    receipts.on('receipt', handler);
  });
}

function writeSupervisorLine(supervisor, line) {
  if (!supervisor?.stdin?.writable) throw new Error('windows_job_supervisor_stdin_missing');
  // Writable.write returning false means the bytes were accepted but buffered.
  // The line protocol remains bounded and the native supervisor applies OS pipe backpressure.
  supervisor.stdin.write(line);
}

export async function launchWindowsPty({
  windowsHelper,
  shell,
  arguments: args,
  cwd,
  env,
  columns,
  rows,
  nestedJobSelfTest = false,
}) {
  if (process.platform !== 'win32') throw new Error('windows_only');
  if (!windowsHelper) throw new Error('windows_job_object_helper_required');
  const broker = path.join(path.dirname(fileURLToPath(import.meta.url)), 'windows-pty-broker.mjs');
  const launchMode = nestedJobSelfTest ? '--launch-broker-nested-test' : '--launch-broker';
  const supervisor = spawn(windowsHelper, [launchMode, process.execPath, broker], {
    stdio: ['pipe', 'pipe', 'pipe'],
    windowsHide: true,
  });
  const receipts = new EventEmitter();
  const stderrReader = readline.createInterface({ input: supervisor.stderr, crlfDelay: Infinity });
  stderrReader.on('line', (line) => {
    if (!line.startsWith('KRISTIN_SUPERVISOR ')) return;
    try {
      receipts.emit('receipt', JSON.parse(line.slice('KRISTIN_SUPERVISOR '.length)));
    } catch {
      receipts.emit('receipt', { status: 'error', message: 'malformed_supervisor_receipt' });
    }
  });
  const launchedPromise = waitForSupervisorReceipt(receipts, 'launched', 7000);
  const brokerReader = readline.createInterface({ input: supervisor.stdout, crlfDelay: Infinity });
  let dataCallback = () => {};
  let exitCallback = () => {};
  let brokerReadyResolve;
  let brokerReadyReject;
  const brokerReady = new Promise((resolve, reject) => {
    brokerReadyResolve = resolve;
    brokerReadyReject = reject;
  });
  brokerReader.on('line', (line) => {
    try {
      const message = JSON.parse(line);
      if (message.type === 'ready') brokerReadyResolve(message);
      else if (message.type === 'data') dataCallback(Buffer.from(message.dataBase64, 'base64').toString('utf8'));
      else if (message.type === 'exit') exitCallback({ exitCode: message.exitCode, signal: message.signal });
      else if (message.type === 'error') brokerReadyReject(new Error(`windows_pty_broker_${message.message}`));
    } catch {
      brokerReadyReject(new Error('windows_pty_broker_protocol_invalid'));
    }
  });
  supervisor.once('error', brokerReadyReject);
  writeSupervisorLine(supervisor, `${JSON.stringify({ shell, arguments: args, cwd, environment: env, columns, rows })}\n`);
  const [launched, ready] = await Promise.all([launchedPromise, brokerReady]);
  if (
    !launched.assignedBeforeResume ||
    launched.nestedJobSelfTest !== nestedJobSelfTest ||
    launched.pid <= 1 ||
    ready.shellPid <= 1
  ) {
    throw new Error('windows_job_launch_receipt_invalid');
  }
  const term = {
    pid: ready.shellPid,
    write(value) {
      writeSupervisorLine(supervisor, `${JSON.stringify({ type: 'write', dataBase64: Buffer.from(value).toString('base64') })}\n`);
    },
    resize(nextColumns, nextRows) {
      writeSupervisorLine(supervisor, `${JSON.stringify({ type: 'resize', columns: nextColumns, rows: nextRows })}\n`);
    },
    kill() {
      writeSupervisorLine(supervisor, `${JSON.stringify({ type: 'close' })}\n`);
    },
    onData(callback) { dataCallback = callback; },
    onExit(callback) { exitCallback = callback; },
  };
  return {
    term,
    registration: {
      identity: {
        pid: launched.pid,
        startToken: launched.startToken,
        supervisorToken: launched.jobId,
        platformGroupId: launched.jobId,
        platform: 'win32',
      },
      nestedJobSelfTest,
      supervisor,
      receipts,
    },
  };
}


export async function launchWindowsManagedProcess({
  windowsHelper,
  executable,
  arguments: args = [],
  cwd,
  env,
  stdinBase64 = '',
}) {
  if (process.platform !== 'win32') throw new Error('windows_only');
  if (!windowsHelper) throw new Error('windows_job_object_helper_required');
  const broker = path.join(path.dirname(fileURLToPath(import.meta.url)), 'windows-process-broker.mjs');
  const supervisor = spawn(windowsHelper, ['--launch-broker', process.execPath, broker], {
    stdio: ['pipe', 'pipe', 'pipe'],
    windowsHide: true,
  });
  const receipts = new EventEmitter();
  const stderrReader = readline.createInterface({ input: supervisor.stderr, crlfDelay: Infinity });
  stderrReader.on('line', (line) => {
    if (!line.startsWith('KRISTIN_SUPERVISOR ')) return;
    try { receipts.emit('receipt', JSON.parse(line.slice('KRISTIN_SUPERVISOR '.length))); }
    catch { receipts.emit('receipt', { status: 'error', message: 'malformed_supervisor_receipt' }); }
  });
  const launchedPromise = waitForSupervisorReceipt(receipts, 'launched', 7000);
  const brokerReader = readline.createInterface({ input: supervisor.stdout, crlfDelay: Infinity });
  let readyResolve; let readyReject; let exitResolve;
  const readyPromise = new Promise((resolve, reject) => { readyResolve = resolve; readyReject = reject; });
  const exitPromise = new Promise((resolve) => { exitResolve = resolve; });
  const stdoutChunks = [];
  const stderrChunks = [];
  let protocolError = null;
  brokerReader.on('line', (line) => {
    try {
      const message = JSON.parse(line);
      if (message.type === 'ready') readyResolve(message);
      else if (message.type === 'stdout') stdoutChunks.push(Buffer.from(message.dataBase64 ?? '', 'base64'));
      else if (message.type === 'stderr') stderrChunks.push(Buffer.from(message.dataBase64 ?? '', 'base64'));
      else if (message.type === 'exit') exitResolve(message);
      else if (message.type === 'error') {
        protocolError = new Error(`windows_process_broker_${message.message}`);
        readyReject(protocolError);
        exitResolve({ type: 'error', error: protocolError });
      }
    } catch {
      protocolError = new Error('windows_process_broker_protocol_invalid');
      readyReject(protocolError);
      exitResolve({ type: 'error', error: protocolError });
    }
  });
  supervisor.once('error', (error) => {
    protocolError = error;
    readyReject(error);
    exitResolve({ type: 'error', error });
  });
  writeSupervisorLine(supervisor, `${JSON.stringify({ executable, arguments: args, cwd, environment: env, stdinBase64 })}\n`);
  const [launched, ready] = await Promise.all([launchedPromise, readyPromise]);
  if (!launched.assignedBeforeResume || launched.pid <= 1 || ready.childPid <= 1) {
    throw new Error('windows_managed_process_launch_invalid');
  }
  return {
    childPid: ready.childPid,
    stdoutChunks,
    stderrChunks,
    exitPromise,
    get protocolError() { return protocolError; },
    registration: {
      identity: {
        pid: launched.pid,
        startToken: launched.startToken,
        supervisorToken: launched.jobId,
        platformGroupId: launched.jobId,
        platform: 'win32',
      },
      supervisor,
      receipts,
    },
  };
}

export async function registerProcess(pid) {
  if (process.platform === 'win32') throw new Error('windows_requires_prelaunch_job_assignment');
  return { identity: await processIdentity(pid), supervisor: null };
}

async function posixProcessGroupMembers(pgid) {
  const { stdout } = await execFileAsync('/bin/ps', ['-axo', 'pid=,ppid=,pgid=,lstart=']);
  const rows = [];
  for (const line of stdout.split(/\r?\n/)) {
    const match = line.trim().match(/^(\d+)\s+(\d+)\s+(\d+)\s+(.+)$/);
    if (!match || Number.parseInt(match[3], 10) !== pgid) continue;
    const pid = Number.parseInt(match[1], 10);
    const ppid = Number.parseInt(match[2], 10);
    const identity = await processIdentity(pid).catch(() => null);
    if (identity) rows.push({ pid, ppid, ...identity });
  }
  return rows.sort((left, right) => left.pid - right.pid);
}

async function waitForProcessGroupGone(pgid, timeoutMs = 10000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      process.kill(-pgid, 0);
    } catch (error) {
      if (error.code === 'ESRCH') return true;
      throw error;
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  return false;
}

export async function terminateTree(registration, { graceMs = 1500 } = {}) {
  const identity = registration?.identity ?? registration;
  if (!identity || !Number.isSafeInteger(identity.pid) || identity.pid <= 1) throw new Error('invalid_process_identity');
  if (process.platform === 'win32') {
    const supervisor = registration.supervisor;
    const receipts = registration.receipts;
    if (!supervisor?.stdin?.writable || !receipts) throw new Error('windows_job_supervisor_control_missing');
    const receiptPromise = waitForSupervisorReceipt(receipts, 'killed', 10000);
    const exitPromise = new Promise((resolve, reject) => {
      supervisor.once('error', reject);
      supervisor.once('exit', (code, signal) => resolve({ code, signal }));
    });
    writeSupervisorLine(supervisor, 'KRISTIN_CONTROL kill\n');
    const [receipt, exited] = await Promise.all([receiptPromise, exitPromise]);
    if (
      exited.code !== 0 ||
      receipt.activeProcesses !== 0 ||
      receipt.identityVerified !== true ||
      receipt.controlProtocolOk !== true ||
      receipt.pid !== identity.pid ||
      receipt.startToken !== identity.startToken
    ) {
      throw new Error(`windows_job_kill_unverified:${JSON.stringify({ receipt, exited })}`);
    }
    return {
      status: 'killed',
      identity,
      activeProcessesBeforeKill: receipt.activeProcessesBeforeKill,
      descendantProcessIdentities: Number(receipt.activeProcessesBeforeKill) >= 2
        ? [{ platformGroupId: identity.platformGroupId, observedCount: Number(receipt.activeProcessesBeforeKill) - 1 }]
        : [],
      activeProcesses: 0,
      identityVerified: true,
      supervisorReceipt: receipt,
      supervisorExitCode: exited.code,
    };
  }
  const current = await processIdentity(identity.pid).catch(() => null);
  if (!current) {
    return {
      status: 'already_exited',
      identity,
      activeProcesses: 0,
      identityVerified: null,
    };
  }
  if (current.startToken !== identity.startToken || current.platformGroupId !== identity.platformGroupId) {
    throw new Error('process_identity_reused');
  }
  const pgid = Number.parseInt(identity.platformGroupId, 10);
  if (!Number.isSafeInteger(pgid) || pgid <= 1 || pgid !== identity.pid) {
    throw new Error('unsafe_or_unmanaged_process_group');
  }
  const membersBeforeKill = await posixProcessGroupMembers(pgid);
  const descendantProcessIdentities = membersBeforeKill.filter((row) => row.pid !== identity.pid);
  try {
    process.kill(-pgid, 'SIGTERM');
  } catch (error) {
    if (error.code === 'ESRCH') return { status: 'already_exited' };
    throw error;
  }
  const deadline = Date.now() + graceMs;
  while (Date.now() < deadline) {
    try {
      process.kill(-pgid, 0);
      await new Promise((resolve) => setTimeout(resolve, 25));
    } catch (error) {
      if (error.code === 'ESRCH') {
        return {
          status: 'stopped',
          identity,
          activeProcessesBeforeKill: membersBeforeKill.length,
          descendantProcessIdentities,
          activeProcesses: 0,
          identityVerified: true,
        };
      }
      throw error;
    }
  }
  try {
    process.kill(-pgid, 'SIGKILL');
  } catch (error) {
    if (error.code !== 'ESRCH') throw error;
  }
  if (!(await waitForProcessGroupGone(pgid, 10000))) {
    throw new Error('process_group_termination_unverified');
  }
  return {
    status: 'killed',
    identity,
    activeProcessesBeforeKill: membersBeforeKill.length,
    descendantProcessIdentities,
    activeProcesses: 0,
    identityVerified: true,
  };
}
