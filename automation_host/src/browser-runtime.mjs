import childProcess from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { syncBuiltinESMExports } from 'node:module';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

import {
  parseArgs,
  runProbe,
  runSessions,
} from './browser-runtime-core.mjs';

export * from './browser-runtime-core.mjs';

const READY_SCHEMA_VERSION = '1.0.0';
const WINDOWS_BROWSER_ENVIRONMENT_KEYS = Object.freeze([
  'SYSTEMROOT',
  'WINDIR',
  'COMSPEC',
  'TEMP',
  'TMP',
  'USERPROFILE',
  'LOCALAPPDATA',
  'APPDATA',
  'PROGRAMFILES',
  'PROGRAMFILES(X86)',
  'PROGRAMDATA',
  'HOMEDRIVE',
  'HOMEPATH',
]);

function environmentValue(environment, key) {
  const direct = environment[key];
  if (direct !== undefined) return direct;
  const normalized = key.toUpperCase();
  for (const [candidate, value] of Object.entries(environment)) {
    if (candidate.toUpperCase() === normalized) return value;
  }
  return undefined;
}

export function browserChildEnvironment(
  environment = process.env,
  platform = process.platform,
) {
  if (platform !== 'win32') return {};
  const result = {};
  for (const key of WINDOWS_BROWSER_ENVIRONMENT_KEYS) {
    const value = environmentValue(environment, key);
    if (typeof value === 'string' && value.length > 0 && !value.includes('\0')) {
      result[key] = value;
    }
  }
  return result;
}

function routeBrowserLaunchToStateDirectory(options) {
  const spawn = childProcess.spawn;
  const environment = browserChildEnvironment();
  childProcess.spawn = (command, args, spawnOptions = {}) => {
    if (
      command === options.browserExecutable &&
      spawnOptions.cwd === options.browserRoot
    ) {
      return spawn(command, args, {
        ...spawnOptions,
        cwd: options.stateDirectory,
        env: environment,
      });
    }
    return spawn(command, args, spawnOptions);
  };
  syncBuiltinESMExports();
}

async function main() {
  try {
    const options = parseArgs(process.argv.slice(2));
    await mkdir(options.stateDirectory, { recursive: true });
    process.chdir(options.stateDirectory);
    routeBrowserLaunchToStateDirectory(options);
    if (options.mode === 'probe') {
      await runProbe(options);
    } else {
      await runSessions(options);
    }
  } catch (error) {
    process.stderr.write(
      `${JSON.stringify({
        type: 'error',
        schemaVersion: READY_SCHEMA_VERSION,
        code: error?.code ?? 'browser_runtime_failed',
        message: String(error?.message ?? error),
      })}\n`,
    );
    process.exitCode = 1;
  }
}

const invokedDirectly = process.argv[1]
  ? import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
  : false;
if (invokedDirectly) await main();