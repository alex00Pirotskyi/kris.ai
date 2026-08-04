import readline from 'node:readline';
import { spawn } from 'node:child_process';

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
let child = null;
function emit(value) { process.stdout.write(`${JSON.stringify(value)}\n`); }

function boundedString(value, limit = 2048) {
  const text = String(value ?? '');
  if (/(secret|token|password|authorization|api.?key|private.?key)/i.test(text)) {
    return '[REDACTED]';
  }
  return text.length <= limit ? text : text.slice(text.length - limit);
}

try {
  const first = await new Promise((resolve, reject) => {
    rl.once('line', resolve);
    rl.once('close', () => reject(new Error('launch_config_missing')));
  });
  const config = JSON.parse(first);
  if (typeof config.executable !== 'string' || !config.executable || config.executable.includes('\0')) {
    throw new Error('executable_invalid');
  }
  if (!Array.isArray(config.arguments) || config.arguments.length > 128 || config.arguments.some((v) => typeof v !== 'string' || v.includes('\0'))) {
    throw new Error('arguments_invalid');
  }
  child = spawn(config.executable, config.arguments, {
    cwd: config.cwd || undefined,
    env: config.environment,
    windowsHide: true,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  child.once('error', (error) => {
    emit({ type: 'error', message: boundedString(error.message || error) });
    process.exitCode = 1;
  });
  child.stdout.on('data', (chunk) => emit({ type: 'stdout', dataBase64: chunk.toString('base64') }));
  child.stderr.on('data', (chunk) => emit({ type: 'stderr', dataBase64: chunk.toString('base64') }));
  child.once('spawn', () => {
    emit({ type: 'ready', childPid: child.pid });
    if (typeof config.stdinBase64 === 'string' && config.stdinBase64.length > 0) {
      child.stdin.write(Buffer.from(config.stdinBase64, 'base64'));
    }
    child.stdin.end();
  });
  child.once('exit', (exitCode, signal) => {
    emit({ type: 'exit', childPid: child.pid, exitCode, signal });
    process.exitCode = Number.isInteger(exitCode) ? exitCode : 0;
    rl.close();
  });
  for await (const line of rl) {
    if (line === 'close') {
      child.kill();
      break;
    }
  }
} catch (error) {
  emit({ type: 'error', message: boundedString(error.message || error) });
  process.exitCode = 1;
}
