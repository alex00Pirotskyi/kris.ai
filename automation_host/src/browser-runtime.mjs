import { mkdir } from 'node:fs/promises';
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

async function main() {
  try {
    const options = parseArgs(process.argv.slice(2));
    await mkdir(options.stateDirectory, { recursive: true });
    process.chdir(options.stateDirectory);
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
