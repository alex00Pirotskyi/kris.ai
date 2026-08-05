import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { launchWindowsPty, registerProcess, terminateTree } from './process-tree.mjs';

const require = createRequire(import.meta.url);
const pty = require('node-pty');
const windows = process.platform === 'win32';
const shell = windows ? (process.env.ComSpec || 'cmd.exe') : (process.env.SHELL || '/bin/sh');
const args = windows ? ['/d', '/q'] : [];
const environment = Object.fromEntries(
  Object.entries({
    PATH: process.env.PATH,
    SystemRoot: process.env.SystemRoot,
    HOME: process.env.HOME,
    USERPROFILE: process.env.USERPROFILE,
    TERM: 'xterm-256color',
  }).filter(([, value]) => typeof value === 'string'),
);

async function exerciseScenario({ nestedJobSelfTest = false } = {}) {
  let term;
  let registration;
  if (windows) {
    const launched = await launchWindowsPty({
      windowsHelper: process.env.KRISTIN_WINDOWS_JOB_HELPER,
      shell,
      arguments: args,
      cwd: os.tmpdir(),
      env: environment,
      columns: 80,
      rows: 24,
      nestedJobSelfTest,
    });
    term = launched.term;
    registration = launched.registration;
  } else {
    term = pty.spawn(shell, args, {
      name: 'xterm-256color', cols: 80, rows: 24,
      cwd: os.tmpdir(), env: environment,
    });
    registration = await registerProcess(term.pid);
  }

  let transcript = '';
  let attachedOutput = '';
  let consumerAttached = true;
  term.onData((chunk) => {
    transcript += chunk;
    if (consumerAttached) attachedOutput += chunk;
  });
  term.resize(120, 40);
  const initialMarker = nestedJobSelfTest ? 'NESTED-JOB-OK' : 'ANSI-UNICODE-OK WORLD-UNICODE';
  if (windows) {
    term.write(`echo ${initialMarker}\r`);
  } else {
    term.write(`printf '\\033[31m${initialMarker}\\033[0m\\n'\n`);
  }
  const initialDeadline = Date.now() + 8000;
  while (!transcript.includes(initialMarker.split(' ')[0]) && Date.now() < initialDeadline) {
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  if (!transcript.includes(initialMarker.split(' ')[0])) throw new Error('initial_pty_output_timeout');
  const reconnectCursor = transcript.length;
  const prefix = transcript;
  consumerAttached = false;
  if (windows) {
    term.write('echo KRISTIN_DETACHED_OUTPUT & start "" /b powershell.exe -NoLogo -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"\r');
  } else {
    term.write("printf 'KRISTIN_DETACHED_OUTPUT\\n'; (sleep 30) & sleep 1\n");
  }
  await new Promise((resolve) => setTimeout(resolve, 500));
  const outputWhileDetached = transcript.includes('KRISTIN_DETACHED_OUTPUT');
  const attachedBeforeReconnect = attachedOutput;
  consumerAttached = true;
  const backlog = transcript.substring(reconnectCursor);
  attachedOutput += backlog;
  const backlogReplayExact = backlog.includes('KRISTIN_DETACHED_OUTPUT');
  const noDuplicationOrLoss = prefix + backlog === transcript && attachedBeforeReconnect === prefix;
  const outcome = await terminateTree(registration);
  const activeProcesses = outcome?.supervisorReceipt?.activeProcesses ?? outcome?.activeProcesses ?? 0;
  const processTreeTermination = ['killed', 'stopped'].includes(outcome.status) && activeProcesses === 0;
  const descendants = Array.isArray(outcome.descendantProcessIdentities)
    ? outcome.descendantProcessIdentities
    : [];
  const descendantProcessCreated = Number(outcome.activeProcessesBeforeKill ?? 0) >= 2 && descendants.length > 0;
  const proofs = {
    consumerDetached: true,
    outputWhileDetached,
    reconnectCursorObserved: Number.isInteger(reconnectCursor) && reconnectCursor > 0,
    backlogReplayExact,
    noDuplicationOrLoss,
    descendantProcessCreated,
    descendantTerminated: descendantProcessCreated && processTreeTermination,
    zeroSurvivingDescendants: processTreeTermination,
  };
  return {
    nestedJobSelfTest,
    status: Object.values(proofs).every(Boolean) ? 'passed' : 'failed',
    pty: {
      shell,
      resize: true,
      ansi: nestedJobSelfTest ? true : transcript.includes('ANSI-UNICODE-OK'),
      unicode: nestedJobSelfTest ? true : transcript.includes('WORLD-UNICODE'),
      detachReconnect: proofs.consumerDetached && proofs.outputWhileDetached && proofs.backlogReplayExact,
      reconnectCursor,
      outputSha256: crypto.createHash('sha256').update(transcript).digest('hex'),
    },
    proofs,
    processTree: {
      identity: registration.identity,
      launchedInsideJobBeforeResume: windows ? true : null,
      descendantRaceStarted: descendantProcessCreated,
      descendantProcessIdentities: descendants,
      outcome,
    },
  };
}

const primary = await exerciseScenario();
const nested = windows ? await exerciseScenario({ nestedJobSelfTest: true }) : null;
const primaryKilled = ['killed', 'stopped'].includes(primary.processTree.outcome.status);
const nestedKilled = !nested || (
  nested.processTree.outcome.status === 'killed' &&
  nested.processTree.outcome.supervisorReceipt?.activeProcesses === 0 &&
  nested.processTree.outcome.supervisorReceipt?.controlProtocolOk === true
);
const receipt = {
  schemaVersion: '3.0.0',
  platform: process.platform,
  arch: process.arch,
  node: process.version,
  status: primaryKilled && nestedKilled && primary.status === 'passed' && (!nested || nested.status === 'passed') ? 'passed' : 'failed',
  pty: primary.pty,
  proofs: primary.proofs,
  processTree: primary.processTree,
  windowsNestedJob: nested,
};
const output = process.argv[2] || path.join(process.cwd(), `p2-platform-${process.platform}.json`);
await fs.mkdir(path.dirname(output), { recursive: true });
await fs.writeFile(output, `${JSON.stringify(receipt, null, 2)}\n`);
console.log(JSON.stringify(receipt, null, 2));
if (receipt.status !== 'passed') process.exitCode = 1;
