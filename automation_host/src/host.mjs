import readline from 'node:readline';
import crypto from 'node:crypto';
import fs from 'node:fs';
import net from 'node:net';
import { createRequire } from 'node:module';
import { BoundedTranscript } from './bounded-transcript.mjs';
import {
  createAuthenticatedIpcVerifier,
  assertSessionAuthorization,
} from './authenticated-ipc.mjs';
import {
  launchWindowsPty,
  processIdentity,
  registerProcess,
  terminateTree,
} from './process-tree.mjs';
import { createHostOperations } from './host-operations.mjs';
import { ExternalWatchdogManager } from './external-watchdog.mjs';
import { redact, safeEnvironmentDelta } from './redaction.mjs';

const require = createRequire(import.meta.url);
let pty;
try {
  pty = require('node-pty');
} catch {
  pty = null;
}


async function proveRestrictedWorkerAuthorityDenial() {
  if (process.env.KRISTIN_P1A_DENIAL_PROBE_REQUIRED !== '1') return null;
  const address = process.env.KRISTIN_P1A_AUTHORITY_ADDRESS ?? '';
  const workerSessionId = process.env.KRISTIN_WORKER_SESSION_ID ?? '';
  if (!address || workerSessionId.length < 16) {
    throw new Error('worker_authority_denial_probe_configuration_missing');
  }
  const request = Buffer.from(JSON.stringify({
    schemaVersion: '2.0.0',
    operation: 'describe-authority-v2',
    behaviorSessionId: process.env.KRISTIN_P1A_BEHAVIOR_SESSION_ID ?? undefined,
  }), 'utf8');
  const frame = Buffer.allocUnsafe(4 + request.length);
  frame.writeUInt32BE(request.length, 0);
  request.copy(frame, 4);
  return await new Promise((resolve, reject) => {
    const socket = net.createConnection(address);
    const chunks = [];
    let expected = null;
    let settled = false;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      socket.destroy();
      if (error) reject(error); else resolve(value);
    };
    const timer = setTimeout(() => finish(new Error('worker_authority_denial_probe_timeout')), 5000);
    socket.once('error', (error) => {
      if (['EACCES', 'EPERM'].includes(error?.code)) {
        finish(null, {
          type: 'worker.authority-denial',
          status: 'denied',
          errorCode: 'worker_principal_denied',
          workerSessionId,
          pid: process.pid,
          transport: process.platform === 'win32' ? 'windows-named-pipe-acl' : 'unix-socket-acl',
        });
      } else {
        finish(new Error(`worker_authority_denial_probe_transport:${error?.code ?? 'unknown'}`));
      }
    });
    socket.on('data', (chunk) => {
      chunks.push(chunk);
      const buffer = Buffer.concat(chunks);
      if (expected === null && buffer.length >= 4) expected = buffer.readUInt32BE(0);
      if (expected !== null && expected > 0 && expected <= 65536 && buffer.length >= 4 + expected) {
        try {
          const response = JSON.parse(buffer.subarray(4, 4 + expected).toString('utf8'));
          if (response?.status !== 'denied' || response?.errorCode !== 'worker_principal_denied') {
            finish(new Error('worker_authority_service_not_denied'));
            return;
          }
          finish(null, {
            type: 'worker.authority-denial',
            status: 'denied',
            errorCode: 'worker_principal_denied',
            workerSessionId,
            pid: process.pid,
            transport: process.platform === 'win32' ? 'windows-named-pipe-service' : 'unix-socket-service',
          });
        } catch (error) {
          finish(error);
        }
      }
    });
    socket.once('connect', () => socket.write(frame));
  });
}

const MAX_SESSIONS = 16;
const MAX_INPUT_BYTES = 1024 * 1024;
const BOOTSTRAP_SCHEMA = '4.0.0';

function validateBootstrap(value, expectedChallenge = null) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('bootstrap_object_required');
  }
  if (value.type !== 'bootstrap' || value.schemaVersion !== BOOTSTRAP_SCHEMA) {
    throw new Error('bootstrap_schema_invalid');
  }
  if (expectedChallenge !== null && value.challenge !== expectedChallenge) {
    throw new Error('bootstrap_challenge_mismatch');
  }
  const permitVerifier = value.permitVerifier;
  const authorityState = value.authorityState;
  if (permitVerifier?.algorithm !== 'ecdsa-p256-sha256' ||
      typeof permitVerifier.keyId !== 'string' ||
      typeof permitVerifier.publicKeySpkiBase64 !== 'string' ||
      permitVerifier.publicKeySpkiBase64.length < 80) {
    throw new Error('bootstrap_public_permit_verifier_invalid');
  }
  if (!authorityState || typeof authorityState !== 'object' || Array.isArray(authorityState)) {
    throw new Error('bootstrap_authority_state_invalid');
  }
  const serialized = JSON.stringify(value);
  if (/ipcKeyHex|grantKeyring|consumptionKeyring|privateKey|signingKey|hmacKey/i.test(serialized)) {
    throw new Error('bootstrap_authority_secret_material_rejected');
  }
  if (typeof value.channelId !== 'string' || value.channelId.length < 16) {
    throw new Error('bootstrap_channel_id_invalid');
  }
  if (typeof value.workerSessionId !== 'string' || value.workerSessionId.length < 16) {
    throw new Error('bootstrap_worker_session_id_invalid');
  }
  return {
    permitVerifier,
    authorityState,
    channelId: value.channelId,
    workerSessionId: value.workerSessionId,
  };
}

function minimalEnvironment(delta) {
  const inherited = [
    'PATH',
    'Path',
    'SystemRoot',
    'WINDIR',
    'HOME',
    'USERPROFILE',
    'TMP',
    'TEMP',
    'LANG',
    'LC_ALL',
    'TERM',
    'DISPLAY',
    'WAYLAND_DISPLAY',
    'XDG_RUNTIME_DIR',
    'DBUS_SESSION_BUS_ADDRESS',
  ];
  const env = Object.fromEntries(
    inherited
      .filter((key) => process.env[key] !== undefined)
      .map((key) => [key, process.env[key]]),
  );
  for (const [key, value] of Object.entries(safeEnvironmentDelta(delta))) {
    if (value === null) delete env[key];
    else env[key] = String(value);
  }
  env.TERM ??= 'xterm-256color';
  return env;
}

function validateOpen(payload) {
  if (
    typeof payload.shell !== 'string' ||
    payload.shell.length === 0 ||
    payload.shell.includes('\0')
  ) {
    throw new Error('shell_invalid');
  }
  if (
    typeof payload.cwd !== 'string' ||
    payload.cwd.length === 0 ||
    payload.cwd.includes('\0')
  ) {
    throw new Error('cwd_invalid');
  }
  if (
    !Array.isArray(payload.arguments) ||
    payload.arguments.length > 128 ||
    payload.arguments.some(
      (value) => typeof value !== 'string' || value.includes('\0'),
    )
  ) {
    throw new Error('arguments_invalid');
  }
  const columns = payload.columns ?? 120;
  const rows = payload.rows ?? 40;
  if (
    !Number.isSafeInteger(columns) ||
    columns < 20 ||
    columns > 1000 ||
    !Number.isSafeInteger(rows) ||
    rows < 5 ||
    rows > 500
  ) {
    throw new Error('terminal_size_invalid');
  }
  const transcriptBudgetBytes =
    payload.transcriptBudgetBytes ?? 4 * 1024 * 1024;
  if (
    !Number.isSafeInteger(transcriptBudgetBytes) ||
    transcriptBudgetBytes < 4096 ||
    transcriptBudgetBytes > 64 * 1024 * 1024
  ) {
    throw new Error('transcript_budget_invalid');
  }
  return { columns, rows, transcriptBudgetBytes };
}

function exactIdentityEqual(left, right) {
  return (
    left?.pid === right?.pid &&
    left?.startToken === right?.startToken &&
    left?.platformGroupId === right?.platformGroupId
  );
}

export function createHostRuntime({
  permitVerifier,
  authorityState,
  channelId,
  workerSessionId,
  emit = () => {},
  environment = process.env,
} = {}) {
  const verifyEnvelope = createAuthenticatedIpcVerifier({
    permitVerifier,
    channelId,
    workerSessionId,
    revocationEpoch: authorityState.revocationEpoch,
    revokedGrantIds: authorityState.revokedGrantIds,
    authoritativeGrantUses: authorityState.authoritativeGrantUses,
    authoritativeConsumedRequestIds:
      authorityState.authoritativeConsumedRequestIds,
    authoritativeStateVersion: authorityState.authoritativeStateVersion,
  });
  const sessions = new Map();
  const registrations = new Map();
  const hostOperations = createHostOperations({
    runtimeConfig: {
      fixtureRoot: environment.KRISTIN_P2_FIXTURE_ROOT,
      interactiveDesktopAdapter: environment.KRISTIN_INTERACTIVE_DESKTOP_ADAPTER,
      windowsJobHelper: environment.KRISTIN_WINDOWS_JOB_HELPER,
      posixWatchdogHelper: environment.KRISTIN_POSIX_WATCHDOG_HELPER,
      interactiveDesktopAttested:
        environment.KRISTIN_P2_INTERACTIVE_DESKTOP === '1',
      controlledPackageManager:
        environment.KRISTIN_P2_CONTROLLED_PACKAGE_MANAGER,
      controlledPackageName:
        environment.KRISTIN_P2_CONTROLLED_PACKAGE_NAME,
      controlledPackageSource:
        environment.KRISTIN_P2_CONTROLLED_PACKAGE_SOURCE,
      controlledPackagePrefix:
        environment.KRISTIN_P2_CONTROLLED_PACKAGE_PREFIX,
      npmExecutable: environment.KRISTIN_P2_NPM_EXECUTABLE,
      nativeServiceId: environment.KRISTIN_P2_NATIVE_SERVICE_ID,
      nativeServiceProvider:
        environment.KRISTIN_P2_NATIVE_SERVICE_PROVIDER ||
        environment.KRISTIN_P2_NATIVE_SERVICE_BACKEND,
      nativeServiceAttestation:
        environment.KRISTIN_P2_NATIVE_SERVICE_ATTESTATION,
      nativeServiceAttestationSha256:
        environment.KRISTIN_P2_NATIVE_SERVICE_ATTESTATION_SHA256,
      runnerAttestationReceipt:
        environment.KRISTIN_P2_RUNNER_ATTESTATION_RECEIPT,
      runnerAttestationSha256:
        environment.KRISTIN_P2_RUNNER_ATTESTATION_SHA256,
      commitSha: environment.KRISTIN_P2_COMMIT_SHA,
      workflowRunId: environment.GITHUB_RUN_ID,
      workflowJob: environment.GITHUB_JOB,
      runnerName: environment.RUNNER_NAME,
    },
    emit,
    registrations,
  });
  const watchdogs = new ExternalWatchdogManager({
    posixHelper: environment.KRISTIN_POSIX_WATCHDOG_HELPER,
  });
  watchdogs.on('event', (event) => emit(event));

  async function invokeCore(envelope) {
    const verified = verifyEnvelope(envelope);
    const authorization = verified.authorization;
    const payload = envelope.payload ?? {};
    if (payload.operation !== authorization.operation) {
      throw new Error('payload_operation_mismatch');
    }

    if (payload.operation === 'pty.open') {
      if (sessions.size >= MAX_SESSIONS) throw new Error('session_quota_exceeded');
      if (!pty) {
        return {
          requestId: envelope.requestId,
          status: 'unsupported',
          reason: 'node_pty_not_packaged',
        };
      }
      const { columns, rows, transcriptBudgetBytes } = validateOpen(payload);
      let term;
      let registration;
      const terminalEnvironment = minimalEnvironment(payload.environmentDelta);
      if (process.platform === 'win32') {
        const launched = await launchWindowsPty({
          windowsHelper: environment.KRISTIN_WINDOWS_JOB_HELPER,
          shell: payload.shell,
          arguments: payload.arguments,
          cwd: payload.cwd,
          env: terminalEnvironment,
          columns,
          rows,
        });
        term = launched.term;
        registration = launched.registration;
      } else {
        term = pty.spawn(payload.shell, payload.arguments, {
          name: 'xterm-256color',
          cols: columns,
          rows,
          cwd: payload.cwd,
          env: terminalEnvironment,
        });
        try {
          registration = await registerProcess(term.pid);
        } catch (error) {
          try {
            term.kill();
          } catch {
            // Best effort cleanup after registration failure.
          }
          throw error;
        }
      }
      const id = crypto.randomUUID();
      const transcript = new BoundedTranscript(transcriptBudgetBytes);
      const session = {
        id,
        term,
        registration,
        transcript,
        authorization,
        lastUseNumber: authorization.useNumber,
        state: 'attached',
        inputBytes: 0,
        openRequestId: envelope.requestId,
      };
      sessions.set(id, session);
      registrations.set(`process:${registration.identity.supervisorToken}`, {
        registration,
        authorization,
        lastUseNumber: authorization.useNumber,
        kind: 'pty',
        sessionId: id,
      });
      term.onData((data) => {
        transcript.append(Buffer.from(data));
        if (session.state === 'attached') {
          emit({
            type: 'pty.data',
            requestId: session.openRequestId,
            sessionId: id,
            nextCursor: transcript.cursor,
            dataBase64: Buffer.from(data).toString('base64'),
            authorizationBinding: {
              runId: authorization.runId,
              taskId: authorization.taskId,
              actorId: authorization.actorId,
              toolId: authorization.toolId,
              accessProfileId: authorization.accessProfileId,
              capabilityId: authorization.capabilityId,
              grantId: authorization.grantId,
              grantDigest: authorization.grantDigest,
            },
          });
        }
      });
      term.onExit(({ exitCode, signal }) => {
        session.state = 'exited';
        registrations.delete(
          `process:${registration.identity.supervisorToken}`,
        );
        if (registration.supervisor?.stdin?.writable) {
          registration.supervisor.stdin.end('KRISTIN_CONTROL close\n');
        }
        emit({
          type: 'pty.exit',
          requestId: session.openRequestId,
          sessionId: id,
          exitCode,
          signal,
          processIdentity: registration.identity,
          authorizationBinding: {
            runId: authorization.runId,
            taskId: authorization.taskId,
            actorId: authorization.actorId,
            grantId: authorization.grantId,
            grantDigest: authorization.grantDigest,
          },
        });
      });
      return {
        requestId: envelope.requestId,
        status: 'ok',
        sessionId: id,
        processIdentity: registration.identity,
        transcriptCursor: 0,
      };
    }

    if (
      payload.operation.startsWith('host.') ||
      payload.operation === 'command.run' ||
      payload.operation === 'sdk.discover' ||
      payload.operation.startsWith('package.') ||
      payload.operation.startsWith('service.') ||
      payload.operation.startsWith('application.') ||
      payload.operation.startsWith('clipboard.') ||
      payload.operation.startsWith('screen.')
    ) {
      return hostOperations.invoke(payload.operation, payload, authorization);
    }

    if (payload.operation === 'process.register') {
      return {
        status: 'unsupported',
        reason: 'arbitrary_process_attachment_forbidden_use_managed_launch',
      };
    }
    if (
      ['process.inspect', 'process.stop', 'process.kill'].includes(payload.operation) &&
      !payload.sessionId
    ) {
      const supplied = payload.processIdentity;
      if (!supplied || typeof supplied !== 'object') {
        throw new Error('process_identity_required');
      }
      const entry = registrations.get(`process:${supplied.supervisorToken}`);
      if (
        !entry?.registration ||
        !exactIdentityEqual(entry.registration.identity, supplied)
      ) {
        throw new Error('process_identity_unknown_or_reused');
      }
      assertSessionAuthorization(entry, authorization);
      entry.lastUseNumber = authorization.useNumber;
      const registration = entry.registration;
      if (payload.operation === 'process.inspect') {
        let lifecycle = 'running';
        if (process.platform !== 'win32') {
          const current = await processIdentity(registration.identity.pid).catch(
            () => null,
          );
          lifecycle =
            current && exactIdentityEqual(current, registration.identity)
              ? 'running'
              : 'exited';
        }
        return {
          status: 'ok',
          lifecycle,
          processIdentity: registration.identity,
        };
      }
      const outcome = await terminateTree(registration, {
        graceMs:
          payload.operation === 'process.kill'
            ? 0
            : Number(payload.graceMs ?? 1500),
      });
      if (['killed', 'stopped', 'already_exited'].includes(outcome.status)) {
        registrations.delete(`process:${registration.identity.supervisorToken}`);
      }
      return { status: 'ok', lifecycle: outcome.status, outcome };
    }

    const session = sessions.get(payload.sessionId);
    if (!session) throw new Error('unknown_session');
    assertSessionAuthorization(session, authorization);
    session.lastUseNumber = authorization.useNumber;

    if (payload.processIdentity && !exactIdentityEqual(payload.processIdentity, session.registration.identity)) {
      throw new Error('process_identity_binding_mismatch');
    }

    if (payload.operation === 'pty.input') {
      const data = Buffer.from(
        payload.dataBase64 ?? '',
        'base64',
      );
      session.inputBytes += data.length;
      if (session.inputBytes > MAX_INPUT_BYTES) {
        throw new Error('session_input_budget_exceeded');
      }
      session.term.write(data.toString('utf8'));
      return { status: 'ok', sessionId: session.id };
    }
    if (payload.operation === 'pty.resize') {
      const { columns, rows } = validateOpen({
        ...payload,
        shell: 'bound',
        cwd: 'bound',
        arguments: [],
        transcriptBudgetBytes: 4096,
      });
      session.term.resize(columns, rows);
      return { status: 'ok', sessionId: session.id };
    }
    if (payload.operation === 'pty.detach') {
      session.state = 'detached';
      return {
        status: 'ok',
        sessionId: session.id,
        cursor: session.transcript.cursor,
      };
    }
    if (payload.operation === 'pty.attach') {
      session.state = 'attached';
      const result = session.transcript.read(payload.fromCursor ?? 0);
      return {
        status: 'ok',
        sessionId: session.id,
        state: session.state,
        processIdentity: session.registration.identity,
        nextCursor: result.nextCursor,
        truncatedBefore: result.truncatedBefore,
        dataBase64: result.data.toString('base64'),
      };
    }
    if (payload.operation === 'pty.interrupt') {
      session.term.write('\x03');
      return { status: 'ok', sessionId: session.id };
    }
    if (payload.operation === 'pty.terminate') {
      const outcome = await terminateTree(session.registration);
      session.state = 'killed';
      return { status: 'ok', sessionId: session.id, outcome };
    }
    if (payload.operation === 'process.inspect') {
      let lifecycle = session.state;
      if (process.platform !== 'win32' && !['exited', 'killed'].includes(lifecycle)) {
        const current = await processIdentity(session.registration.identity.pid).catch(() => null);
        lifecycle = current && exactIdentityEqual(current, session.registration.identity)
          ? 'running'
          : 'exited';
      }
      return {
        status: 'ok',
        sessionId: session.id,
        lifecycle,
        processIdentity: session.registration.identity,
      };
    }
    if (payload.operation === 'process.stop' || payload.operation === 'process.kill') {
      const outcome = await terminateTree(session.registration, {
        graceMs: payload.operation === 'process.kill' ? 0 : Number(payload.graceMs ?? 1500),
      });
      session.state = outcome.status === 'stopped' ? 'stopped' : 'killed';
      return {
        status: 'ok',
        sessionId: session.id,
        lifecycle: session.state,
        outcome,
      };
    }
    if (payload.operation === 'watchdog.arm') {
      const result = watchdogs.arm({
        watchdogId: payload.watchdogId,
        session,
        timeoutMs: Number(payload.timeoutMs),
      });
      return { status: 'ok', sessionId: session.id, ...result };
    }
    if (payload.operation === 'watchdog.heartbeat') {
      return {
        status: 'ok',
        sessionId: session.id,
        ...watchdogs.heartbeat(payload.watchdogId),
      };
    }
    if (payload.operation === 'watchdog.kill') {
      return {
        status: 'ok',
        sessionId: session.id,
        ...(await watchdogs.kill(payload.watchdogId)),
      };
    }
    if (payload.operation === 'watchdog.inspect') {
      return {
        status: 'ok',
        sessionId: session.id,
        ...watchdogs.inspect(payload.watchdogId),
      };
    }
    if (payload.operation === 'watchdog.disarm') {
      return {
        status: 'ok',
        sessionId: session.id,
        ...watchdogs.disarm(payload.watchdogId),
      };
    }
    throw new Error('unsupported_operation');
  }

  function runtimeReceipt(envelope, result) {
    const authorization = envelope.authorization ?? {};
    const operation = envelope.payload?.operation ?? authorization.operation ?? 'unknown';
    const succeeded = result?.status === 'ok';
    const unsupported = result?.status === 'unsupported';
    const completedAt = new Date().toISOString();
    const reversibility = operation === 'pty.open' || operation === 'pty.detach' || operation === 'pty.attach'
      ? 'partiallyReversible'
      : 'irreversible';
    return {
      schemaVersion: '1.0.0',
      effectId: `${operation}-${crypto.randomUUID()}`,
      runId: authorization.runId,
      taskId: authorization.taskId,
      operation,
      status: succeeded ? 'succeeded' : unsupported ? 'unsupported' : 'unknown',
      reversibility,
      startedAt: completedAt,
      completedAt,
      details: {
        sessionIdSha256: typeof result?.sessionId === 'string'
          ? crypto.createHash('sha256').update(result.sessionId).digest('hex')
          : null,
        processIdentity: result?.processIdentity ?? result?.outcome?.identity ?? null,
        lifecycle: result?.lifecycle ?? result?.outcome?.status ?? null,
        termination: result?.outcome && typeof result.outcome === 'object'
          ? {
              status: result.outcome.status ?? null,
              activeProcessesBeforeKill: result.outcome.activeProcessesBeforeKill ?? null,
              descendantProcessIdentities: result.outcome.descendantProcessIdentities ?? [],
              activeProcesses: result.outcome.activeProcesses ?? null,
              identityVerified: result.outcome.identityVerified ?? null,
              supervisorExitCode: result.outcome.supervisorExitCode ?? null,
            }
          : null,
        contentLogged: false,
      },
    };
  }

  async function invoke(envelope) {
    const result = await invokeCore(envelope);
    if (result?.receipt || envelope.payload?.operation?.startsWith('host.') ||
        envelope.payload?.operation === 'command.run' ||
        envelope.payload?.operation === 'sdk.discover' ||
        envelope.payload?.operation?.startsWith('package.') ||
        envelope.payload?.operation?.startsWith('service.') ||
        envelope.payload?.operation?.startsWith('application.') ||
        envelope.payload?.operation?.startsWith('clipboard.') ||
        envelope.payload?.operation?.startsWith('screen.')) {
      return result;
    }
    return { ...result, receipt: runtimeReceipt(envelope, result) };
  }

  async function close() {
    for (const session of sessions.values()) {
      await terminateTree(session.registration).catch(() => {});
    }
    sessions.clear();
    registrations.clear();
    await watchdogs.close();
    await hostOperations.close();
  }

  return Object.freeze({ invoke, close, sessions, registrations, watchdogs });
}

function emitLine(value) {
  process.stdout.write(`${JSON.stringify(redact(value))}\n`);
}

export async function runCli() {
  let runtime = null;
  let challenge = null;

  const denial = await proveRestrictedWorkerAuthorityDenial();
  if (denial !== null) emitLine(denial);
  challenge = crypto.randomBytes(32).toString('hex');
  emitLine({
    type: 'bootstrap.challenge',
    schemaVersion: BOOTSTRAP_SCHEMA,
    challenge,
    pid: process.pid,
    privateChildPipeRequired: true,
    publicVerifierOnly: true,
  });

  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  for await (const line of rl) {
    try {
      const message = JSON.parse(line);
      if (runtime === null) {
        const bootstrap = validateBootstrap(message, challenge);
        runtime = createHostRuntime({
          ...bootstrap,
          emit: emitLine,
        });
        challenge = null;
        emitLine({
          type: 'ready',
          schemaVersion: '2.0.0',
          executorOnly: true,
          grantIssuer: false,
          authenticatedIpcRequired: true,
          desktopIssuedEffectPermitRequired: true,
          publicVerifierOnly: true,
          rawAuthorityKeysPresent: false,
          bootstrapTransport: 'private-parent-child-stdio',
          restrictedWorkerPrincipal:
            process.env.KRISTIN_OWNER_RISK_QA === '1'
              ? false
              : process.env.KRISTIN_RESTRICTED_WORKER === '1',
          ownerRiskCurrentAccount: process.env.KRISTIN_OWNER_RISK_QA === '1',
          osIsolationWaived: process.env.KRISTIN_OWNER_RISK_QA === '1',
          workerSessionId: bootstrap.workerSessionId,
          pid: process.pid,
        });
        continue;
      }
      if (message?.type === 'shutdown') {
        await runtime.close();
        emitLine({ type: 'shutdown.complete', status: 'ok' });
        rl.close();
        break;
      }
      const response = await runtime.invoke(message);
      emitLine({
        type: 'response',
        requestId: message.requestId,
        ...response,
      });
    } catch (error) {
      emitLine({
        type: 'response',
        requestId: (() => {
          try {
            return JSON.parse(line).requestId ?? null;
          } catch {
            return null;
          }
        })(),
        status: 'error',
        code: error.code ?? 'request_failed',
        message: String(error.message ?? error),
      });
    }
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  runCli().catch((error) => {
    emitLine({
      type: 'fatal',
      status: 'error',
      code: error.code ?? 'host_start_failed',
      message: String(error.message ?? error),
    });
    process.exitCode = 1;
  });
}
