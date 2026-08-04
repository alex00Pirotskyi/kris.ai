#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

function fail(message) { console.error(`ERROR: ${message}`); process.exit(1); }
function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i];
    if (!key?.startsWith('--') || i + 1 >= argv.length) fail(`invalid argument near ${key ?? '<end>'}`);
    out[key.slice(2)] = argv[i + 1];
  }
  return out;
}
function shaFile(file) { return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().map(k => `${JSON.stringify(k)}:${canonical(value[k])}`).join(',')}}`;
  return JSON.stringify(value);
}
function treeDigest(root) {
  const rows = [];
  function walk(dir) {
    for (const name of fs.readdirSync(dir).sort()) {
      const full = path.join(dir, name);
      const st = fs.lstatSync(full);
      if (st.isSymbolicLink()) fail(`symlink rejected: ${full}`);
      if (st.isDirectory()) walk(full);
      else rows.push(`${path.relative(root, full).split(path.sep).join('/')}\0${shaFile(full)}`);
    }
  }
  walk(root);
  return crypto.createHash('sha256').update(rows.join('\n')).digest('hex');
}
function writeJson(file, value) { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`); }
function relativeFile(root, file, executable = false, kind = 'file') {
  return { kind, path: path.relative(root, file).split(path.sep).join('/'), sha256: shaFile(file), bytes: fs.statSync(file).size, executable };
}
const args = parseArgs(process.argv.slice(2));
const root = path.resolve(args.root ?? '');
const platform = args.platform;
const sourceCommit = args['source-commit'];
const sourceTree = args['source-tree'];
const p2PackageSha256 = args['p2-package-sha256'];
const contract = path.resolve(args['p1-contract'] ?? '');
if (!['windows', 'macos', 'linux'].includes(platform)) fail('platform invalid');
for (const [name, value, length] of [['source-commit', sourceCommit, 40], ['source-tree', sourceTree, 40], ['p2-package-sha256', p2PackageSha256, 64]]) {
  if (!new RegExp(`^[0-9a-f]{${length}}$`).test(value ?? '')) fail(`${name} invalid`);
}
if (!fs.existsSync(root) || !fs.existsSync(contract)) fail('runtime root or P1 contract missing');
const nodeDir = path.join(root, 'node');
const nodeNames = platform === 'windows' ? ['node.exe'] : ['node'];
const node = nodeNames.map(n => path.join(nodeDir, n)).find(fs.existsSync);
const hostRoot = path.join(root, 'automation_host');
const host = path.join(hostRoot, 'src', 'host.mjs');
const launcher = path.join(hostRoot, 'src', 'owner-risk-launcher.mjs');
for (const file of [node, host, launcher]) if (!file || !fs.existsSync(file)) fail(`runtime file missing: ${file}`);
const policyPath = path.join(root, 'provisioning', 'worker-policy.v2.json');
const policy = {
  schemaVersion: '2.0.0', platform,
  authorityAddress: platform === 'windows' ? String.raw`\\.\pipe\KristinOwnerRiskQa` : '/tmp/kristin-owner-risk-qa.sock',
  nodeExecutable: path.resolve(node), nodeSha256: shaFile(node),
  hostScript: path.resolve(host), hostScriptSha256: shaFile(host),
  workingDirectory: path.resolve(hostRoot),
  launcherPath: path.resolve(launcher), launcherSha256: shaFile(launcher),
  packageSha256: p2PackageSha256, sourceCommit, sourceTree,
  ownerRiskQa: true, osIsolationWaived: true,
};
writeJson(policyPath, policy);
const provisioningPath = path.join(root, 'provisioning', 'environment.v1.json');
writeJson(provisioningPath, {
  schemaVersion: '1.0.0', provisioningType: 'kristin-p2-application-runtime-environment-v1', containsSecrets: false,
  environment: {
    KRISTIN_OWNER_RISK_QA: '1', KRISTIN_P2_COMMIT_SHA: sourceCommit,
    KRISTIN_P2_SOURCE_PACKAGE_SHA256: p2PackageSha256,
    KRISTIN_P2_E2E_ROOT: root, KRISTIN_P2_RUNNER_ID: `owner-risk-qa-${platform}`,
    KRISTIN_P2_RUNNER_GROUP: 'github-hosted-tri-platform-qa',
  },
});
const resources = {
  nodeExecutable: relativeFile(root, node, true),
  automationHost: relativeFile(root, host),
  automationHostRoot: { kind: 'directory', path: 'automation_host', treeSha256: treeDigest(hostRoot) },
  restrictedWorkerLauncher: relativeFile(root, launcher, true, 'file'),
  restrictedWorkerPolicy: relativeFile(root, policyPath),
  runtimeProvisioning: relativeFile(root, provisioningPath),
};
for (const [key, rel] of [['windowsJobHelper', 'native/windowsJobHelper'], ['posixWatchdog', 'native/posixWatchdog'], ['interactiveDesktopAdapter', 'native/interactiveDesktopAdapter']]) {
  const dir = path.join(root, rel);
  if (!fs.existsSync(dir)) continue;
  const file = fs.readdirSync(dir).map(name => path.join(dir, name)).find(value => fs.statSync(value).isFile());
  if (file) resources[key] = relativeFile(root, file, true);
}
const contractSha = shaFile(contract);
const buildRows = Object.keys(resources).sort().map(key => `${key}\0${canonical(resources[key])}`);
const runtimeBuildSha256 = crypto.createHash('sha256').update(`${buildRows.join('\n')}\n${sourceCommit}\n${sourceTree}\n${contractSha}`).digest('hex');
const manifest = {
  schemaVersion: '3.0.0', bundleType: 'kristin-p2-application-runtime-v3',
  identity: { sourceCommit, sourceTree, runtimeBuildSha256, p1AuthorityServiceContractSha256: contractSha },
  resources, workingDirectoryIndependent: true, currentWorkingDirectoryUsed: false,
  authorityServiceExternal: false, authorityServiceExecutableStaged: false,
  authorityBrokerStaged: false, rawAuthoritySecretsIncluded: false, p2DelegationOnly: true,
  restrictedWorkerLauncherExternal: false, restrictedWorkerLauncherOsEnforced: false,
  ownerRiskQa: true, securityEvidenceWaived: true,
};
const manifestPath = path.join(root, 'runtime-manifest.v3.json');
writeJson(manifestPath, manifest);
console.log(JSON.stringify({ status: 'passed', platform, runtimeRoot: root, manifestPath, manifestSha256: shaFile(manifestPath), runtimeBuildSha256 }, null, 2));
