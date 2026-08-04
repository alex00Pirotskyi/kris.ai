import { spawn } from 'node:child_process';
import readline from 'node:readline';
import { EventEmitter } from 'node:events';

function positiveInteger(value, minimum, maximum, code) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new Error(code);
  }
  return value;
}

function parseReceiptLine(line) {
  try {
    const value = JSON.parse(line);
    return value && typeof value === 'object' && !Array.isArray(value)
      ? value
      : null;
  } catch {
    return null;
  }
}

function bindingFromAuthorization(authorization) {
  return Object.freeze({
    runId: authorization.runId,
    taskId: authorization.taskId,
    actorId: authorization.actorId,
    toolId: authorization.toolId,
    accessProfileId: authorization.accessProfileId,
    capabilityId: authorization.capabilityId,
    grantId: authorization.grantId,
    grantDigest: authorization.grantDigest,
  });
}

function waitFor(predicate, emitter, timeoutMs, code) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error(code));
    }, timeoutMs);
    const onReceipt = (receipt) => {
      if (!predicate(receipt)) return;
      cleanup();
      resolve(receipt);
    };
    const onFailure = (error) => {
      cleanup();
      reject(error instanceof Error ? error : new Error(code));
    };
    const cleanup = () => {
      clearTimeout(timer);
      emitter.off('receipt', onReceipt);
      emitter.off('failure', onFailure);
    };
    emitter.on('receipt', onReceipt);
    emitter.on('failure', onFailure);
  });
}

export class ExternalWatchdogManager extends EventEmitter {
  constructor({ posixHelper = process.env.KRISTIN_POSIX_WATCHDOG_HELPER } = {}) {
    super();
    this.posixHelper = posixHelper;
    this.watchdogs = new Map();
  }

  arm({ watchdogId, session, timeoutMs }) {
    if (
      typeof watchdogId !== 'string' ||
      !/^[A-Za-z0-9._:-]{1,160}$/.test(watchdogId)
    ) {
      throw new Error('watchdog_id_invalid');
    }
    positiveInteger(timeoutMs, 100, 3_600_000, 'watchdog_timeout_invalid');
    if (this.watchdogs.has(watchdogId)) {
      throw new Error('watchdog_already_armed');
    }
    const identity = session?.registration?.identity;
    const authorization = session?.authorization;
    if (
      !identity ||
      !Number.isSafeInteger(identity.pid) ||
      identity.pid <= 1 ||
      !authorization
    ) {
      throw new Error('watchdog_target_identity_required');
    }
    const authorizationBinding = bindingFromAuthorization(authorization);
    const events = new EventEmitter();

    if (process.platform === 'win32') {
      const control = session.registration?.supervisor?.stdin;
      const receipts = session.registration?.receipts;
      if (!control?.writable || !receipts) {
        throw new Error('windows_watchdog_control_missing');
      }
      const state = {
        watchdogId,
        platform: 'windows',
        session,
        timeoutMs,
        control,
        identity,
        authorizationBinding,
        status: 'armed',
        receipts: [],
        events,
      };
      const onReceipt = (receipt) => {
        if (receipt?.status !== 'killed' && receipt?.status !== 'error') return;
        state.receipts.push(receipt);
        state.status = receipt.status;
        events.emit(receipt.status === 'error' ? 'failure' : 'receipt', receipt);
        this.emit('event', {
          type: 'watchdog.receipt',
          watchdogId,
          receipt,
          processIdentity: identity,
          authorizationBinding,
        });
      };
      receipts.on('receipt', onReceipt);
      state.detachReceiptListener = () => receipts.off('receipt', onReceipt);
      this.watchdogs.set(watchdogId, state);
      control.write(`KRISTIN_CONTROL arm ${timeoutMs}\n`);
      control.write('KRISTIN_CONTROL beat\n');
      return {
        status: 'armed',
        external: true,
        platform: 'windows',
        watchdogId,
        timeoutMs,
        processIdentity: identity,
        transport: 'job-supervisor-control-pipe',
      };
    }

    if (!this.posixHelper) throw new Error('posix_watchdog_helper_required');
    const uid = identity.uid;
    const pgid = Number.parseInt(identity.platformGroupId, 10);
    if (
      !Number.isSafeInteger(uid) ||
      uid < 0 ||
      !Number.isSafeInteger(pgid) ||
      pgid <= 1 ||
      pgid !== identity.pid
    ) {
      throw new Error('posix_watchdog_identity_invalid');
    }
    const child = spawn(
      this.posixHelper,
      [
        '--watch-pid',
        String(identity.pid),
        '--pgid',
        String(pgid),
        '--start-token',
        identity.startToken,
        '--uid',
        String(uid),
        '--timeout-ms',
        String(timeoutMs),
      ],
      { stdio: ['pipe', 'pipe', 'pipe'], detached: false },
    );
    const state = {
      watchdogId,
      platform: process.platform,
      session,
      timeoutMs,
      child,
      identity,
      authorizationBinding,
      status: 'armed',
      stderr: '',
      receipts: [],
      events,
    };
    this.watchdogs.set(watchdogId, state);
    readline
      .createInterface({ input: child.stdout, crlfDelay: Infinity })
      .on('line', (line) => {
        const receipt = parseReceiptLine(line);
        if (!receipt) return;
        state.receipts.push(receipt);
        state.status = receipt.status ?? state.status;
        events.emit('receipt', receipt);
        this.emit('event', {
          type: 'watchdog.receipt',
          watchdogId,
          receipt,
          processIdentity: identity,
          authorizationBinding,
        });
      });
    child.stderr.on('data', (chunk) => {
      state.stderr = `${state.stderr}${chunk}`.slice(-4096);
    });
    child.on('error', (error) => events.emit('failure', error));
    child.on('exit', (code, signal) => {
      state.status =
        code === 0 ? (state.receipts.at(-1)?.status ?? 'exited') : 'failed';
      if (code !== 0) {
        events.emit('failure', new Error(`watchdog_exit_${code}`));
      }
      this.emit('event', {
        type: 'watchdog.exit',
        watchdogId,
        code,
        signal,
        status: state.status,
        processIdentity: identity,
        authorizationBinding,
        stderrPresent: state.stderr.length > 0,
      });
    });
    child.stdin.write('beat\n');
    return {
      status: 'armed',
      external: true,
      platform: process.platform,
      watchdogId,
      timeoutMs,
      processIdentity: identity,
      watchdogPid: child.pid,
      transport: 'native-watchdog-private-pipe',
    };
  }

  heartbeat(watchdogId) {
    const state = this.watchdogs.get(watchdogId);
    if (!state) throw new Error('unknown_watchdog');
    if (state.platform === 'windows') {
      if (!state.control.writable) throw new Error('watchdog_pipe_closed');
      state.control.write('KRISTIN_CONTROL beat\n');
    } else if (state.child.stdin.writable) {
      state.child.stdin.write('beat\n');
    } else {
      throw new Error('watchdog_pipe_closed');
    }
    return { status: 'ok', watchdogId };
  }

  async kill(watchdogId, { timeoutMs = 12_000 } = {}) {
    const state = this.watchdogs.get(watchdogId);
    if (!state) return { status: 'already_absent', watchdogId };
    const receiptPromise = waitFor(
      (receipt) =>
        receipt?.status === 'killed' &&
        receipt?.identityVerified === true &&
        receipt?.activeProcesses === 0,
      state.events,
      timeoutMs,
      'watchdog_kill_receipt_timeout',
    );
    if (state.platform === 'windows') {
      if (!state.control.writable) throw new Error('watchdog_pipe_closed');
      state.control.write('KRISTIN_CONTROL kill\n');
    } else if (state.child.stdin.writable) {
      state.child.stdin.write('kill\n');
    } else {
      throw new Error('watchdog_pipe_closed');
    }
    state.status = 'killing';
    const receipt = await receiptPromise;
    if (
      receipt.pid !== state.identity.pid ||
      receipt.startToken !== state.identity.startToken
    ) {
      throw new Error('watchdog_kill_identity_mismatch');
    }
    state.status = 'killed';
    return {
      status: 'killed',
      watchdogId,
      processIdentity: state.identity,
      receipt,
    };
  }

  disarm(watchdogId) {
    const state = this.watchdogs.get(watchdogId);
    if (!state) return { status: 'already_absent', watchdogId };
    if (state.platform === 'windows') {
      if (state.control.writable) state.control.write('KRISTIN_CONTROL disarm\n');
    } else if (state.child.stdin.writable) {
      state.child.stdin.end();
    }
    state.detachReceiptListener?.();
    this.watchdogs.delete(watchdogId);
    return { status: 'disarmed', watchdogId };
  }

  inspect(watchdogId) {
    const state = this.watchdogs.get(watchdogId);
    if (!state) return { status: 'absent', watchdogId };
    return {
      status: state.status,
      watchdogId,
      external: true,
      timeoutMs: state.timeoutMs,
      processIdentity: state.identity,
      receipt: state.receipts.at(-1) ?? null,
    };
  }

  async close() {
    for (const [watchdogId, state] of this.watchdogs) {
      try {
        if (state.status === 'armed' || state.status === 'killing') {
          await this.kill(watchdogId, { timeoutMs: 3000 }).catch(() => {});
        }
      } finally {
        this.disarm(watchdogId);
      }
    }
  }
}
