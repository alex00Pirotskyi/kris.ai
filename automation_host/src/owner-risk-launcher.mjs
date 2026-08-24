#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runCli } from './host.mjs';

function sha(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}
function arg(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || index + 1 >= process.argv.length) throw new Error(`missing_${name}`);
  return process.argv[index + 1];
}
const policyPath = path.resolve(arg('--policy'));
const sessionId = arg('--session');
const policy = JSON.parse(fs.readFileSync(policyPath, 'utf8'));
const platform = process.platform === 'win32' ? 'windows' : process.platform === 'darwin' ? 'macos' : 'linux';
const productCurrentAccount = process.env.KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT === '1';
const ownerRiskQa = process.env.KRISTIN_OWNER_RISK_QA === '1';
if (policy.schemaVersion !== '2.0.0' || policy.platform !== platform || sessionId.length < 16 || productCurrentAccount === ownerRiskQa) {
  throw new Error('owner_risk_worker_policy_invalid');
}
const runtimeRoot = path.resolve(path.dirname(policyPath), '..');
const runtimePath = value => productCurrentAccount
  ? path.resolve(runtimeRoot, value)
  : path.resolve(value);
const node = runtimePath(policy.nodeExecutable);
const host = runtimePath(policy.hostScript);
const self = fileURLToPath(import.meta.url);
const identity = {
  type: 'launcher.identity', schemaVersion: '2.0.0', platform,
  principalType: productCurrentAccount ? 'current-account-owner' : 'owner-risk-current-account',
  sessionId, pid: process.pid, startToken: `${productCurrentAccount ? 'current-account' : 'owner-risk'}-${process.pid}-${Date.now()}`,
  launcherSha256: sha(self), nodeSha256: sha(node), hostScriptSha256: sha(host),
  authorityConnectionDenied: false,
  authorityDenialCode: productCurrentAccount ? 'current_account_unisolated' : 'owner_risk_waived',
  authorityDenialObservedBy: productCurrentAccount ? 'current-account-product' : 'owner-risk-waiver',
  ownerRiskQa, productCurrentAccount, osIsolationWaived: true, currentAccountAuthority: true,
  ...(platform === 'linux' ? { workerUid: process.getuid?.() ?? 0, workerGid: process.getgid?.() ?? 0 } : {}),
};
process.stdout.write(`${JSON.stringify(identity)}\n`);
process.env.KRISTIN_WORKER_SESSION_ID = sessionId;
process.env.KRISTIN_RESTRICTED_WORKER = '0';
if (productCurrentAccount) {
  delete process.env.KRISTIN_OWNER_RISK_QA;
  process.env.KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT = '1';
} else {
  process.env.KRISTIN_OWNER_RISK_QA = '1';
  delete process.env.KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT;
}
process.env.KRISTIN_P1A_DENIAL_PROBE_REQUIRED = '0';
process.chdir(runtimePath(policy.workingDirectory));
await runCli();
