import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, realpath, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  chromiumProbeArgs,
  parseArgs,
  validateManifestBinding,
} from './browser-runtime.mjs';

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

async function fixture() {
  const root = await mkdtemp(path.join(os.tmpdir(), 'p3-browser-runtime-test-'));
  const browserRoot = path.join(root, 'browser');
  const browserExecutable = path.join(browserRoot, process.platform === 'win32' ? 'chrome.exe' : 'chrome');
  const stateDirectory = path.join(root, 'state');
  const runtimeManifest = path.join(root, 'browser-runtime-manifest.v1.json');
  await mkdir(browserRoot, { recursive: true });
  await mkdir(stateDirectory, { recursive: true });
  await writeFile(browserExecutable, 'fake-browser\n');
  const browserExecutableSha256 = sha256('fake-browser\n');
  const runtimeBuildSha256 = 'c'.repeat(64);
  const browserRevision = '1234567';
  const manifest = {
    schemaVersion: '1.0.0',
    bundleType: 'kristin-p3-browser-runtime-v1',
    applicationOwned: true,
    workingDirectoryIndependent: true,
    currentWorkingDirectoryUsed: false,
    globalRuntimeRequired: false,
    browserNetworkInstallRequired: false,
    identity: {
      sourceCommit: 'a'.repeat(40),
      sourceTree: 'b'.repeat(40),
      runtimeBuildSha256,
      packageLockSha256: 'd'.repeat(64),
      nodeVersion: '24.18.0',
      automationHostPackageVersion: '2.0.0-p3.1',
      browserEngine: 'chromium',
      browserRevision,
    },
    resources: {
      browserExecutable: {
        kind: 'file',
        path: path.relative(root, browserExecutable).split(path.sep).join('/'),
        sha256: browserExecutableSha256,
        executable: true,
      },
      browserRoot: {
        kind: 'directory',
        path: 'browser',
        treeSha256: 'e'.repeat(64),
      },
    },
  };
  const bytes = Buffer.from(`${JSON.stringify(manifest)}\n`);
  await writeFile(runtimeManifest, bytes);
  return {
    root,
    browserRoot,
    browserExecutable,
    stateDirectory,
    runtimeManifest,
    browserExecutableSha256,
    browserRevision,
    runtimeBuildSha256,
    manifestSha256: sha256(bytes),
    async cleanup() {
      await rm(root, { recursive: true, force: true });
    },
  };
}

test('parseArgs accepts only the exact absolute probe contract', async () => {
  const f = await fixture();
  try {
    const parsed = parseArgs([
      '--mode', 'probe',
      '--protocol', 'stdio-json-v1',
      '--browser-executable', f.browserExecutable,
      '--browser-root', f.browserRoot,
      '--runtime-manifest', f.runtimeManifest,
      '--state-directory', f.stateDirectory,
    ]);
    assert.equal(parsed.mode, 'probe');
    assert.equal(parsed.protocol, 'stdio-json-v1');
    assert.equal(parsed.browserExecutable, path.resolve(f.browserExecutable));
    assert.equal(parsed.browserRoot, path.resolve(f.browserRoot));
  } finally {
    await f.cleanup();
  }
});

test('parseArgs rejects relative paths and unknown arguments', () => {
  assert.throws(
    () => parseArgs([
      '--mode', 'probe',
      '--protocol', 'stdio-json-v1',
      '--browser-executable', 'relative/chrome',
      '--browser-root', '/tmp/browser',
      '--runtime-manifest', '/tmp/manifest.json',
      '--state-directory', '/tmp/state',
    ]),
    /browser_executable_not_absolute/u,
  );
  assert.throws(
    () => parseArgs(['--unexpected', 'value']),
    /argument_set_invalid/u,
  );
});

test('chromiumProbeArgs pins CDP, profile and no-background-update flags', () => {
  const profile = path.resolve(os.tmpdir(), 'p3-profile');
  const args = chromiumProbeArgs(profile);
  assert.ok(args.includes('--headless=new'));
  assert.ok(args.includes('--remote-debugging-port=0'));
  assert.ok(args.includes(`--user-data-dir=${profile}`));
  assert.ok(args.includes('--disable-background-networking'));
  assert.ok(args.includes('--disable-component-update'));
  assert.ok(args.includes('about:blank'));
  assert.equal(args.some((value) => value === '--no-sandbox'), false);
});

test('validateManifestBinding accepts exact manifest, browser path and SHA', async () => {
  const f = await fixture();
  try {
    const result = await validateManifestBinding(
      {
        browserExecutable: f.browserExecutable,
        browserRoot: f.browserRoot,
        runtimeManifest: f.runtimeManifest,
        stateDirectory: f.stateDirectory,
      },
      {
        KRISTIN_P3_RUNTIME_MANIFEST_SHA256: f.manifestSha256,
        KRISTIN_P3_RUNTIME_BUILD_SHA256: f.runtimeBuildSha256,
        KRISTIN_P3_BROWSER_REVISION: f.browserRevision,
      },
    );
    assert.equal(result.manifestSha256, f.manifestSha256);
    assert.equal(result.browserExecutableSha256, f.browserExecutableSha256);
    assert.equal(result.browserRevision, f.browserRevision);
    assert.equal(await realpath(f.browserExecutable), await realpath(f.browserExecutable));
  } finally {
    await f.cleanup();
  }
});

test('validateManifestBinding rejects manifest and executable tampering', async () => {
  const f = await fixture();
  try {
    const options = {
      browserExecutable: f.browserExecutable,
      browserRoot: f.browserRoot,
      runtimeManifest: f.runtimeManifest,
      stateDirectory: f.stateDirectory,
    };
    await assert.rejects(
      validateManifestBinding(options, {
        KRISTIN_P3_RUNTIME_MANIFEST_SHA256: '0'.repeat(64),
        KRISTIN_P3_RUNTIME_BUILD_SHA256: f.runtimeBuildSha256,
        KRISTIN_P3_BROWSER_REVISION: f.browserRevision,
      }),
      /runtime_manifest_sha_mismatch/u,
    );
    await writeFile(f.browserExecutable, 'tampered-browser\n');
    await assert.rejects(
      validateManifestBinding(options, {
        KRISTIN_P3_RUNTIME_MANIFEST_SHA256: f.manifestSha256,
        KRISTIN_P3_RUNTIME_BUILD_SHA256: f.runtimeBuildSha256,
        KRISTIN_P3_BROWSER_REVISION: f.browserRevision,
      }),
      /browser_executable_sha_mismatch/u,
    );
  } finally {
    await f.cleanup();
  }
});
