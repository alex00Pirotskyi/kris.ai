import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { createHostRuntime } from './host.mjs';
import { createTestAuthority } from './test-authority.mjs';

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}
function platformName() {
  return process.platform === 'win32'
    ? 'windows'
    : process.platform === 'darwin'
      ? 'macos'
      : 'linux';
}
function failed(reason, observation = {}) {
  return { status: 'blocked', reason, observation };
}
function assertOk(response, name) {
  if (response?.status !== 'ok' || response?.receipt?.status !== 'succeeded') {
    throw new Error(`${name}_failed:${JSON.stringify(response)}`);
  }
  return response;
}
async function waitForEvent(events, predicate, timeoutMs) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('event_timeout')), timeoutMs);
    const poll = () => {
      const index = events.findIndex(predicate);
      if (index >= 0) {
        clearTimeout(timer);
        resolve(events[index]);
      } else {
        setTimeout(poll, 25);
      }
    };
    poll();
  });
}

async function main() {
  const output = path.resolve(process.argv[2] ?? 'product-path-smoke.json');
  const task = process.argv[3] ?? 'P2-007';
  const fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'kristin-p2-product-'));
  const roots = [
    fixtureRoot,
    os.tmpdir(),
    process.cwd(),
    path.dirname(process.execPath),
  ];
  const authority = createTestAuthority({ roots, taskId: task });
  const events = [];
  const environment = {
    ...process.env,
    KRISTIN_P2_FIXTURE_ROOT: fixtureRoot,
    KRISTIN_WINDOWS_JOB_HELPER: process.env.KRISTIN_WINDOWS_JOB_HELPER,
    KRISTIN_POSIX_WATCHDOG_HELPER: process.env.KRISTIN_POSIX_WATCHDOG_HELPER,
    KRISTIN_INTERACTIVE_DESKTOP_ADAPTER:
      process.env.KRISTIN_INTERACTIVE_DESKTOP_ADAPTER,
    KRISTIN_P2_INTERACTIVE_DESKTOP:
      process.env.KRISTIN_P2_INTERACTIVE_DESKTOP,
  };
  const bootstrap = authority.bootstrap();
  const runtime = createHostRuntime({
    permitVerifier: bootstrap.permitVerifier,
    authorityState: bootstrap.authorityState,
    channelId: bootstrap.channelId,
    workerSessionId: bootstrap.workerSessionId,
    environment,
    emit: (event) => events.push(event),
  });
  const invoke = (operation, payload = {}) => runtime.invoke(authority.next(operation, payload));
  const result = {
    schemaVersion: '1.0.0',
    resultType: 'p2-product-path-observation-v1',
    taskId: task,
    platform: platformName(),
    status: 'blocked',
    chain: [
      'authenticated-desktop-envelope',
      'p1-ipc-and-grant-verifier',
      'production-automation-host-runtime',
      'production-os-adapter',
      'machine-observed-postcondition',
      'structured-effect-receipt',
    ],
    observation: {},
  };
  try {
    if (task === 'P2-003') {
      const command = assertOk(
        await invoke('command.run', {
          executable: process.execPath,
          arguments: [
            '-e',
            "process.stdout.write('KRISTIN_COMMAND_STDOUT_λ');process.stderr.write('KRISTIN_COMMAND_STDERR');",
          ],
          cwd: fixtureRoot,
          environmentDelta: { KRISTIN_COMMAND_FIXTURE: '1' },
          stdinBase64: '',
          deadlineMs: 15_000,
          maxStdoutBytes: 64 * 1024,
          maxStderrBytes: 64 * 1024,
        }),
        'command_run',
      );
      const stdout = Buffer.from(command.output.stdoutBase64, 'base64').toString('utf8');
      const stderr = Buffer.from(command.output.stderrBase64, 'base64').toString('utf8');
      if (stdout !== 'KRISTIN_COMMAND_STDOUT_λ' || stderr !== 'KRISTIN_COMMAND_STDERR') {
        throw new Error('command_output_postcondition_failed');
      }
      result.status = 'passed';
      result.observation = {
        exitCode: command.output.exitCode,
        stdoutSha256: command.output.stdoutSha256,
        stderrSha256: command.output.stderrSha256,
        processIdentity: command.output.processIdentity,
        receiptId: command.receipt.effectId,
      };
    } else if (task === 'P2-007') {
      const plan = assertOk(
        await invoke('package.plan', {
          manager: 'fixture',
          packageOperation: 'install',
          packages: ['kristin-fixture-sdk'],
        }),
        'package_plan',
      );
      const applied = assertOk(
        await invoke('package.apply', { plan: plan.output }),
        'package_apply',
      );
      const ledger = path.join(fixtureRoot, 'package-state.json');
      const ledgerBytes = await fs.readFile(ledger);
      const discovered = assertOk(await invoke('sdk.discover'), 'sdk_discover');
      if (applied.output.stateSha256 !== sha256(ledgerBytes)) {
        throw new Error('package_postcondition_digest_mismatch');
      }
      result.status = 'passed';
      result.observation = {
        packageLedgerSha256: sha256(ledgerBytes),
        sdkCount: discovered.output.sdks.length,
        receiptIds: [
          plan.receipt.effectId,
          applied.receipt.effectId,
          discovered.receipt.effectId,
        ],
      };
    } else if (task === 'P2-008') {
      const serviceId = 'fixture.kristin-p2-service';
      const started = assertOk(
        await invoke('service.start', { serviceId }),
        'service_start',
      );
      const running = assertOk(
        await invoke('service.status', { serviceId }),
        'service_status_running',
      );
      if (running.output.state !== 'running') throw new Error('service_not_running');
      const stopped = assertOk(
        await invoke('service.stop', { serviceId }),
        'service_stop',
      );
      const after = assertOk(
        await invoke('service.status', { serviceId }),
        'service_status_stopped',
      );
      if (after.output.state !== 'stopped') throw new Error('service_not_stopped');
      const executable = process.execPath;
      const opened = assertOk(
        await invoke('application.open', {
          target: executable,
          arguments: ['-e', 'setInterval(()=>{},1000)'],
          cwd: fixtureRoot,
        }),
        'application_open',
      );
      const closed = assertOk(
        await invoke('application.close', { identity: opened.output.identity }),
        'application_close',
      );
      result.status = 'passed';
      result.observation = {
        serviceProcessIdentity: started.output.processIdentity,
        serviceStopped: stopped.output.state === 'stopped',
        applicationIdentity: opened.output.identity,
        applicationClosed: closed.receipt.status === 'succeeded',
      };
    } else if (task === 'P2-009') {
      if (process.env.KRISTIN_P2_INTERACTIVE_DESKTOP !== '1') {
        Object.assign(result, failed('governed_interactive_desktop_lane_required'));
      } else {
        const marker = `kristin-${crypto.randomUUID()}`;
        assertOk(await invoke('clipboard.write', { text: marker }), 'clipboard_write');
        const read = assertOk(await invoke('clipboard.read'), 'clipboard_read');
        const capture = assertOk(
          await invoke('screen.capture', { redactions: [] }),
          'screen_capture',
        );
        const window = assertOk(
          await invoke('screen.activeWindowMetadata'),
          'active_window',
        );
        if (read.output.text !== marker) throw new Error('clipboard_roundtrip_failed');
        if (!capture.output.bytesBase64 || capture.output.bytesBase64.length < 16) {
          throw new Error('screen_capture_empty');
        }
        result.status = 'passed';
        result.observation = {
          clipboardRoundTripSha256: sha256(marker),
          screenSha256: sha256(Buffer.from(capture.output.bytesBase64, 'base64')),
          activeWindowMetadataSha256: sha256(JSON.stringify(window.output)),
          ordinaryReceiptContainsContent: false,
        };
      }
    } else if (['P2-005', 'P2-006', 'P2-011'].includes(task)) {
      const shell =
        process.platform === 'win32'
          ? process.env.ComSpec || 'cmd.exe'
          : process.env.SHELL || '/bin/sh';
      const opened = await invoke('pty.open', {
        shell,
        cwd: fixtureRoot,
        arguments: [],
        environmentDelta: {},
        columns: 100,
        rows: 30,
        transcriptBudgetBytes: 64 * 1024,
      });
      if (opened.status !== 'ok') {
        throw new Error(`pty_open_failed:${JSON.stringify(opened)}`);
      }
      if (task === 'P2-005') {
        await invoke('pty.input', {
          sessionId: opened.sessionId,
          dataBase64: Buffer.from(
            process.platform === 'win32'
              ? 'echo KRISTIN_PTY_UNICODE_λ\r\n'
              : "printf 'KRISTIN_PTY_UNICODE_λ\\n'\n",
          ).toString('base64'),
        });
        await invoke('pty.resize', {
          sessionId: opened.sessionId,
          columns: 132,
          rows: 44,
        });
        const detached = await invoke('pty.detach', { sessionId: opened.sessionId });
        const attached = await invoke('pty.attach', {
          sessionId: opened.sessionId,
          fromCursor: 0,
        });
        await invoke('pty.terminate', { sessionId: opened.sessionId });
        result.status = 'passed';
        result.observation = {
          sessionIdHash: sha256(opened.sessionId),
          detachCursor: detached.cursor,
          attachCursor: attached.nextCursor,
          processIdentity: opened.processIdentity,
        };
      } else if (task === 'P2-006') {
        const killed = await invoke('process.kill', {
          sessionId: opened.sessionId,
          processIdentity: opened.processIdentity,
        });
        if (!['killed', 'stopped', 'already_exited'].includes(killed.outcome.status)) {
          throw new Error('process_tree_kill_unverified');
        }
        result.status = 'passed';
        result.observation = {
          processIdentity: opened.processIdentity,
          outcome: killed.outcome,
        };
      } else {
        if (
          process.platform !== 'win32' &&
          !process.env.KRISTIN_POSIX_WATCHDOG_HELPER
        ) {
          Object.assign(result, failed('external_native_watchdog_helper_required'));
        } else if (
          process.platform === 'win32' &&
          !process.env.KRISTIN_WINDOWS_JOB_HELPER
        ) {
          Object.assign(result, failed('windows_job_supervisor_required'));
        } else {
          const watchdogId = `watchdog-${crypto.randomUUID()}`;
          await invoke('watchdog.arm', {
            sessionId: opened.sessionId,
            processIdentity: opened.processIdentity,
            watchdogId,
            timeoutMs: 500,
          });
          const event = await waitForEvent(
            events,
            (row) =>
              row.type === 'watchdog.receipt' &&
              row.watchdogId === watchdogId &&
              row.receipt?.status === 'killed',
            15_000,
          );
          if (
            event.receipt.identityVerified !== true ||
            event.receipt.activeProcesses !== 0
          ) {
            throw new Error('watchdog_postcondition_invalid');
          }
          result.status = 'passed';
          result.observation = {
            watchdogIdHash: sha256(watchdogId),
            processIdentity: opened.processIdentity,
            receipt: event.receipt,
            uiHeartbeatProvided: false,
            externalProcess: true,
          };
        }
      }
    } else {
      Object.assign(result, failed('product_path_smoke_not_defined_for_task'));
    }
  } catch (error) {
    result.status = 'blocked';
    result.reason = String(error?.message ?? error).slice(0, 2048);
  } finally {
    await runtime.close().catch(() => {});
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  }
  const serialized = `${JSON.stringify(result, null, 2)}\n`;
  await fs.mkdir(path.dirname(output), { recursive: true });
  await fs.writeFile(output, serialized, 'utf8');
  process.stdout.write(serialized);
  process.exitCode = result.status === 'passed' ? 0 : 3;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
