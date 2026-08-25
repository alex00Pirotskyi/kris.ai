import assert from 'node:assert/strict';
import test from 'node:test';

import { browserChildEnvironment } from './browser-runtime.mjs';

test('Windows browser child keeps only bounded bootstrap environment', () => {
  const environment = browserChildEnvironment(
    {
      SystemRoot: 'C:\\Windows',
      TEMP: 'C:\\Temp',
      localappdata: 'C:\\Users\\tester\\AppData\\Local',
      PATH: 'C:\\untrusted',
      HOME: 'C:\\untrusted-home',
      KRISTIN_P3_RUNTIME_MANIFEST_SHA256: 'a'.repeat(64),
      TMP: 'invalid\0value',
    },
    'win32',
  );

  assert.deepEqual(environment, {
    SYSTEMROOT: 'C:\\Windows',
    TEMP: 'C:\\Temp',
    LOCALAPPDATA: 'C:\\Users\\tester\\AppData\\Local',
  });
  assert.equal(environment.PATH, undefined);
  assert.equal(environment.HOME, undefined);
  assert.equal(environment.KRISTIN_P3_RUNTIME_MANIFEST_SHA256, undefined);
  assert.equal(environment.TMP, undefined);
});

test('non-Windows browser child remains environment-scrubbed', () => {
  assert.deepEqual(
    browserChildEnvironment(
      {
        HOME: '/home/tester',
        TMPDIR: '/tmp',
        PATH: '/usr/bin',
      },
      'linux',
    ),
    {},
  );
});
