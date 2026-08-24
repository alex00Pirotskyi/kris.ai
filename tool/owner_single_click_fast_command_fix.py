#!/usr/bin/env python3
from pathlib import Path

SELF = Path(__file__).resolve()
ROOT = SELF.parents[1]
TARGET = ROOT / 'automation_host/src/host-operations.mjs'
text = TARGET.read_text(encoding='utf-8')

old = """  } else {
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
"""

new = """  } else {
    const child = spawn(spec.executable, spec.arguments, {
      cwd: spec.cwd,
      env: spec.environment,
      detached: true,
      stdio: ['pipe', 'pipe', 'pipe'],
      windowsHide: true,
    });
    // Install output and exit observers before any asynchronous identity lookup.
    // A valid finite command may exit between spawn() and /proc/ps inspection;
    // losing its exit event would turn a successful effect into an ESRCH failure.
    child.stdout.on('data', (chunk) => appendBounded(stdoutState, chunk, spec.maxStdoutBytes));
    child.stderr.on('data', (chunk) => appendBounded(stderrState, chunk, spec.maxStderrBytes));
    exitPromise = new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('exit', (code, signal) => resolve({ type: 'exit', exitCode: code, signal }));
    });
    child.stdin.on('error', (error) => {
      // A process is allowed to exit without reading stdin. EPIPE after an
      // observed exit is not an authorization or process-integrity failure.
      if (error?.code !== 'EPIPE') protocolError = error;
    });
    child.stdin.end(spec.stdin);
    try {
      registration = await registerProcess(child.pid);
    } catch (error) {
      const disappeared =
        error?.code === 'ESRCH' ||
        error?.code === 'ENOENT' ||
        (error?.code === 1 && /(?:ps|process)/i.test(String(error?.message ?? '')));
      const observedExit = disappeared
        ? await Promise.race([
            exitPromise.then((row) => row, () => null),
            new Promise((resolve) => setTimeout(() => resolve(null), 50)),
          ])
        : null;
      if (observedExit == null) {
        try { child.kill('SIGKILL'); } catch {}
        throw error;
      }
      // The child is already gone, so no live PID can be adopted or controlled.
      // Bind the completed effect to a one-shot launch identity instead of
      // pretending that an OS start token was observed. This identity is only
      // returned in the command receipt and is never registered for later
      // process-control operations, preventing PID-reuse ambiguity.
      const completionId = crypto.randomUUID();
      registration = {
        identity: {
          pid: child.pid,
          startToken: `completed:${process.platform}:${child.pid}:${completionId}`,
          supervisorToken: `completed:${completionId}`,
          platformGroupId: `completed:${completionId}`,
          platform: process.platform,
          ...(typeof process.getuid === 'function' ? { uid: process.getuid() } : {}),
          completionOnly: true,
          identityVerifiedWhileAlive: false,
        },
        supervisor: null,
        completionOnly: true,
        registrationFailureCode: String(error?.code ?? 'process_disappeared'),
      };
    }
  }
"""

if text.count(old) != 1:
    raise SystemExit(f'host-operations POSIX command anchor count={text.count(old)}')
text = text.replace(old, new, 1)

old_details = """          processIdentity: result.registration.identity,
          termination: result.termination,
          durationMs: result.durationMs,
          contentLogged: false,
"""
new_details = """          processIdentity: result.registration.identity,
          processIdentityCompletionOnly: result.registration.completionOnly === true,
          termination: result.termination,
          durationMs: result.durationMs,
          contentLogged: false,
"""
if text.count(old_details) != 1:
    raise SystemExit(f'host-operations command detail anchor count={text.count(old_details)}')
text = text.replace(old_details, new_details, 1)

old_output = """          processIdentity: result.registration.identity,
          termination: result.termination,
        },
"""
new_output = """          processIdentity: result.registration.identity,
          processIdentityCompletionOnly: result.registration.completionOnly === true,
          termination: result.termination,
        },
"""
if text.count(old_output) != 1:
    raise SystemExit(f'host-operations command output anchor count={text.count(old_output)}')
text = text.replace(old_output, new_output, 1)

TARGET.write_text(text, encoding='utf-8', newline='\n')
SELF.unlink()
print('OWNER_SINGLE_CLICK_FAST_COMMAND_FIX_OK')
