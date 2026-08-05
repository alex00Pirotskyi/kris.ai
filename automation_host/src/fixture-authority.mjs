import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createTestAuthority } from './test-authority.mjs';

function load(pathname) {
  if (!fs.existsSync(pathname)) return { schemaVersion: '2.0.0', initialUses: {}, initialRequests: [], initialStateVersion: 0 };
  const value = JSON.parse(fs.readFileSync(pathname, 'utf8'));
  if (value.schemaVersion !== '2.0.0') throw new Error('fixture_state_invalid');
  return value;
}

function save(pathname, state) {
  fs.mkdirSync(path.dirname(pathname), { recursive: true });
  const temporary = `${pathname}.tmp.${process.pid}`;
  fs.writeFileSync(temporary, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temporary, pathname);
}

function parse(argv) {
  const command = argv[2] ?? '';
  const values = {};
  for (let i = 3; i < argv.length; i += 2) {
    if (!argv[i]?.startsWith('--') || i + 1 >= argv.length) throw new Error('fixture_argument_invalid');
    values[argv[i].slice(2)] = argv[i + 1];
  }
  return { command, values };
}

export function runCli(argv = process.argv) {
  const { command, values } = parse(argv);
  if (!values.state) throw new Error('state_path_required');
  const state = load(path.resolve(values.state));
  const authority = createTestAuthority({
    initialUses: state.initialUses,
    initialRequests: state.initialRequests,
    initialStateVersion: state.initialStateVersion,
  });
  if (command === 'bootstrap') {
    process.stdout.write(`${JSON.stringify({ ...authority.bootstrap(), completionEligible: false, authorityKind: 'fixture-test-only' })}\n`);
    return;
  }
  if (command === 'issue') {
    if (!values.request) throw new Error('request_path_required');
    const request = JSON.parse(fs.readFileSync(path.resolve(values.request), 'utf8'));
    const envelope = authority.next(request.operation, request.payload ?? {}, { expectedGrantDigest: request.expectedGrantDigest ?? null });
    const bootstrap = authority.bootstrap();
    state.initialUses = bootstrap.authorityState.authoritativeGrantUses;
    state.initialRequests = bootstrap.authorityState.authoritativeConsumedRequestIds;
    state.initialStateVersion = bootstrap.authorityState.authoritativeStateVersion;
    save(path.resolve(values.state), state);
    process.stdout.write(`${JSON.stringify(envelope)}\n`);
    return;
  }
  throw new Error('command_required');
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  try { runCli(); } catch (error) { process.stderr.write(`${error?.message ?? error}\n`); process.exitCode = 2; }
}
