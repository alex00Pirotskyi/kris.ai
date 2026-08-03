import readline from 'node:readline';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const pty = require('node-pty');
const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
let term;
let configured = false;

function emit(value) {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

function validateConfig(config) {
  if (typeof config.shell !== 'string' || !config.shell || config.shell.includes('\0')) throw new Error('shell_invalid');
  if (!Array.isArray(config.arguments) || config.arguments.some((v) => typeof v !== 'string' || v.includes('\0'))) throw new Error('arguments_invalid');
  if (typeof config.cwd !== 'string' || !config.cwd || config.cwd.includes('\0')) throw new Error('cwd_invalid');
  if (!Number.isSafeInteger(config.columns) || config.columns < 20 || config.columns > 1000) throw new Error('columns_invalid');
  if (!Number.isSafeInteger(config.rows) || config.rows < 5 || config.rows > 500) throw new Error('rows_invalid');
  if (!config.environment || typeof config.environment !== 'object' || Array.isArray(config.environment)) throw new Error('environment_invalid');
}

rl.on('line', (line) => {
  try {
    const message = JSON.parse(line);
    if (!configured) {
      validateConfig(message);
      term = pty.spawn(message.shell, message.arguments, {
        name: 'xterm-256color',
        cols: message.columns,
        rows: message.rows,
        cwd: message.cwd,
        env: message.environment,
      });
      configured = true;
      term.onData((data) => emit({ type: 'data', dataBase64: Buffer.from(data).toString('base64') }));
      term.onExit(({ exitCode, signal }) => {
        emit({ type: 'exit', exitCode, signal });
        process.exitCode = 0;
        rl.close();
      });
      emit({ type: 'ready', shellPid: term.pid });
      return;
    }
    if (message.type === 'write') term.write(Buffer.from(message.dataBase64, 'base64').toString('utf8'));
    else if (message.type === 'resize') term.resize(message.columns, message.rows);
    else if (message.type === 'interrupt') term.write('\x03');
    else if (message.type === 'close') term.kill();
    else throw new Error('unsupported_broker_command');
  } catch (error) {
    emit({ type: 'error', message: String(error.message ?? error) });
    process.exitCode = 1;
  }
});
