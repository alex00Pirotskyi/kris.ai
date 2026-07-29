# Kristin P2 Full Integration V60 — Independent Technical Review

## Verdict

**NO-GO for `prepare`, `resume`, push, PR, or merge.**

V60 is the strongest P2 corrective candidate so far. The exact uploaded ZIP and launcher are correctly bound, the archive and internal manifest are coherent, the source/evidence regressions are materially stronger, the workflow now enforces pinned Python/Node/Flutter inputs, target-host package and service paths are real rather than ledgers, the watchdog is owned by the product runtime, and technology-spike receipts are explicitly external and fail closed.

However, V60 still has a critical P1 authority-boundary vulnerability: the protected-key broker returns the raw symmetric HMAC keys for IPC, Capability Grant v2, and grant-consumption receipts to the Dart process and automation worker. A worker that possesses those keys can generate the same MACs it is supposed only to verify. This invalidates the claimed verifier-only boundary and makes a compromised worker capable of forging authority and consumption evidence.

The controlled-runner attestation is also not actually signed per workflow run/job, despite claiming that property, and its cleanup receipt is checked before the current behavioral run rather than proving post-run cleanup.

Request a corrected **V61** before creating the P2 branch.

---

## Exact uploaded-byte verification

### Uploaded ZIP

```text
KRISTIN_P2_FULL_INTEGRATION_V60(1).zip
SHA-256:
2ea48c711b0cfedf9afdda750b73a4f8938df51dcc7b2db7a6d637281828cf1a
```

### Uploaded launcher

```text
integrate_kristin_p2_full_train_v60(1).sh
SHA-256:
d92f123978f35b0c2de6c84c6afb86fbb7b5069b7e71fb13ccfdba11405806f3
```

Both values match the published V60 values and the digest hardcoded by the launcher.

The uploaded launcher’s real `verify-package` mode accepts the exact uploaded ZIP.

## Independently verified positives

### Package integrity

- ZIP integrity passes.
- 199 ZIP members inspected.
- `PACKAGE_MANIFEST.json` identifies schema `5.0.0`.
- The manifest contains 198 payload records.
- Every payload byte count and SHA-256 digest matches.
- No path traversal, absolute path, duplicate/case collision, symlink, encrypted member, cache directory, `.pyc`, `.pyo`, `node_modules`, build output, or `.dart_tool` payload was found.
- Launcher passes `bash -n`.
- Whole-ZIP mutation protection is correctly implemented.

### Source and evidence regressions

- Exact P2 source inventory passes:
  - 28 production Dart files.
  - 14 test/support Dart files.
- Application-composition patch regression passes against its synthetic source fixture.
- Separate P2 toolchain-extension regression passes without modifying the historical P0 lock.
- Evidence tamper/forgery regression passes.
- Strict finalizer no-promotion regression passes.
- All fourteen task assertion CLIs execute without the V58/V59 assertion-runner exception.
- Local task assertions remain blocked without Flutter/platform evidence except the documentation consistency task.
- No `tasks/completed/P2-xxx.md` packets are packaged.
- Aggregate P2 remains source-only and incomplete.

### Node and native checks

- Node authorization/security suite passes **16/16**.
- POSIX CMake configure/build passes with warnings treated as errors.
- POSIX watchdog binary builds.
- Native PTY supplementary probe builds and emits a passing smoke receipt.

### Workflow and merge design

- Actions are pinned by immutable commit.
- Python, Node, Flutter and Dart versions are explicitly checked.
- Behavioral jobs require controlled self-hosted interactive-desktop runners.
- Windows, macOS and Linux use exact runner-label contracts.
- Source commit and evidence commit remain separate.
- Required PR checks and test-merge workflows are awaited.
- Independent PR approval and explicit merge authorization are required.
- Protected main is checked for staleness.
- Squash merge is used.
- The merged tree must equal the reviewed final tree.
- Exact merged-main product and P2 workflows are required.

These are genuine improvements.

---

# Release-blocking findings

## 1. Critical: the worker receives raw grant-signing and consumption-signing keys

The protected-key service claims:

```text
returns only a MAC or one short-lived worker verifier bootstrap
rawKeysExposedToDart: false
```

But `P2ProcessProtectedKeyHmacService.createAutomationVerifierBootstrap()` explicitly requires the broker response to contain:

```text
ipcKeyHex
grantKeyring
consumptionKeyring
```

`p1-authority-crypto-broker.mjs` resolves the real OS-protected secrets and returns:

```javascript
{
  ipcKeyHex: ipc,
  grantKeyring: { [grantKeyId]: grant },
  consumptionKeyring: { [consumptionKeyId]: consumption }
}
```

Those values are raw symmetric HMAC keys.

`host.mjs` then passes them into `createAuthenticatedIpcVerifier()`, which uses them with `crypto.createHmac()` to validate grants and consumption receipts.

With HMAC, verifier material is also signing material. The worker can compute valid:

- authenticated IPC MACs;
- Capability Grant v2 MACs;
- consumption-receipt MACs.

The worker’s ready event claims `grantIssuer: false`, but possession of the HMAC keys means it is cryptographically capable of issuing or forging those records.

### Impact

A compromised automation worker, injected dependency, or same-account process able to inspect worker memory can bypass the intended P1 desktop authority, forge grants, forge durable consumption receipts, and manufacture apparently valid effect authorization.

This is incompatible with:

- protected-key handle semantics;
- desktop-only authority;
- worker-as-verifier claims;
- no raw authority secrets outside the protected broker;
- independent evidence trust.

### Required V61 correction

Use one of these fail-closed designs:

1. **Asymmetric signatures**
   - P1 desktop/broker retains private signing keys.
   - Worker receives only public verification keys.
   - Capability grants and consumption receipts use Ed25519 or another governed asymmetric signature scheme.

2. **Desktop-mediated effect authorization**
   - Worker sends the exact effect request to the authenticated desktop control plane.
   - Desktop validates policy/grant/use/revocation immediately before effect.
   - Worker receives a narrowly scoped, one-use authorization receipt that cannot be minted by the worker.

3. A formally reviewed one-way per-session construction where worker material cannot create new authority records.

The worker must never receive the grant-signing key, consumption-signing key, or a symmetric IPC key that lets it impersonate the desktop.

Add tests that prove worker-held material cannot sign a new grant, consumption receipt, or desktop IPC request.

---

## 2. The “real P1 adapter” creates a parallel P1 authority path inside P2

`P2ProductRuntimeBootstrap` directly reads:

```text
config/access_profiles.v2.json
config/policy_engine.v2.json
```

and creates a new:

```text
DeterministicPolicyEngineV2
P2DurableGrantUseLedger
P2P1ControlPlaneAuthority
```

`P2P1ControlPlaneAuthority.issue()` then:

- evaluates policy;
- constructs Capability Grant v2;
- signs the grant;
- consumes a use in the P2 ledger;
- signs authenticated IPC.

This reuses P1 data types and algorithms, but it is not clearly an adapter to one existing, shared P1 desktop control-plane service. It is a second authority-composition and grant-issuance path implemented under P2.

It passes empty:

```text
overlays
explicitWidening
```

into the policy request and maintains its own `_activeGrants` map and P2-owned consumption state.

### Impact

P2 can diverge from the real live P1 authority with respect to:

- current policy overlays;
- organization policy;
- revocation services;
- audit checkpoints;
- shared grant registry;
- durable policy decision history;
- concurrent authority use by other product subsystems.

Self-labeling the class as `p1-production-control-plane` does not prove it is the single authoritative P1 service.

### Required V61 correction

P2 should depend on the actual shared P1 control-plane interface already owned by `ProductRuntime`, rather than loading P1 configuration and reconstructing policy/grant authority itself.

Evidence must identify the concrete shared P1 service instance and bind:

- policy-decision record ID/hash;
- P1 audit-chain/checkpoint record;
- shared revocation epoch;
- shared grant registry state;
- durable consumption state;
- authenticated IPC channel;
- exact authority implementation build/source identity.

---

## 3. Runner attestations are replayable across workflow runs/jobs

The runner policy declares:

```text
sourceCommitBinding:
exact-signed-attestation-per-workflow-run
```

But the signed attestation template does not contain:

- GitHub workflow run ID;
- run attempt;
- job ID/name;
- repository;
- workflow identity.

`p2_runner_attestation.py` verifies the Ed25519 signature first. It then adds:

```python
workflowRunId = GITHUB_RUN_ID
workflowJob = GITHUB_JOB
```

to the output receipt **after signature verification**.

Therefore, the same signed attestation can be reused for another workflow run or job using the same source commit while it remains within its validity period.

`p2_platform_ci.py` later sees a receipt containing the current run/job, but those values were locally appended and were not signed by the provisioning authority.

### Impact

The package claims exact per-run controlled-runner provenance without cryptographically enforcing it.

### Required V61 correction

The signed attestation must include and verify:

```text
repository
workflow name/path
workflow ref
workflow run ID
run attempt
job name
source commit
runner ID
runner name
runner group
runner ephemeral session ID
```

Compare them to the GitHub environment and, where possible, to GitHub API metadata.

A new signed attestation should be required for every workflow run/attempt/job.

---

## 4. The cleanup receipt is pre-run, not proof of cleanup after the current run

The runner attestation binds a `cleanupReceiptPath` and digest before any V60 behavioral operation begins.

The workflow sequence is:

1. validate runner provisioning/cleanup receipt;
2. install dependencies;
3. execute package install/remove;
4. start/stop services;
5. exercise clipboard/screen/window;
6. run PTY/process/watchdog tests;
7. upload artifacts.

There is no final workflow step that:

- performs runner cleanup;
- generates a new cleanup receipt;
- binds it to the exact current run/job;
- proves no processes/services/packages/secrets/workspaces remain.

### Impact

A stale cleanup receipt can prove that the runner was clean at some earlier time, not that this P2 run cleaned up after itself.

### Required V61 correction

Add an `if: always()` post-run cleanup step on each controlled runner. It must:

- terminate every managed and orphaned process tree;
- stop/remove controlled user services;
- remove controlled packages and prefixes;
- clear clipboard/test artifacts where applicable;
- remove temporary authority material and workspaces;
- verify zero remaining descendants;
- produce a signed cleanup receipt bound to exact run/job/commit;
- upload and validate that receipt before a platform result becomes completion-eligible.

---

## 5. Product runtime availability still depends on source-tree and external environment layout

`P2ProductRuntimeBootstrap.start()` defaults its product root to:

```dart
KRISTIN_P2_PRODUCT_ROOT ?? Directory.current.path
```

It resolves runtime assets from source-tree-style paths:

```text
config/access_profiles.v2.json
config/policy_engine.v2.json
automation_host/src/host.mjs
automation_host/src/p1-authority-crypto-broker.mjs
```

It also requires externally provisioned absolute paths for:

- exact Node executable;
- protected authority root;
- authority handle file;
- revocation file;
- owner-approval trust/provider;
- native helpers;
- runner evidence and resources.

Fail-closed behavior is good, but this proves a controlled source-checkout test configuration—not a self-contained Kristin desktop runtime.

### Impact

The product can compile with Owner Mode present while ordinary installed/runtime execution shows only:

```text
Owner Mode is unavailable
```

because the source-tree payload and controlled external resources are absent.

Release packaging is a later train, but P2 closure still needs an honest runtime/deployment contract for where the worker, broker, Node runtime and native helpers come from in normal development and product execution.

### Required V61 correction

Define and test a governed runtime resource resolver that does not depend on current working directory. At minimum:

- package assets/helpers into an application-owned runtime directory;
- bind every executable/script digest;
- resolve through application installation/data paths;
- prove startup from a directory unrelated to the source checkout;
- prove no ambient developer environment variable is required except explicitly provisioned owner/security resources.

---

## 6. Actual protected-main Flutter integration remains unproved

The application-composition patch regression uses synthetic miniatures of `product_runtime.dart` and `ui.dart`.

The package was not supplied with an authoritative exact P1 source snapshot, and this review environment did not have the governed Flutter SDK. Therefore, the following remain unproved against exact protected-main source:

- patch anchors match the real files;
- imports and constructor fields compile;
- `ProductRuntime.initialize` sequencing is correct;
- `ProductRuntime.close()` is safe in every partial-initialization path;
- the UI wrapper preserves existing navigation/semantics;
- all previous Flutter tests remain green;
- actual application startup reaches P2 without regressions.

### Required acceptance evidence

The V61 source commit must pass exact pinned:

```text
dart format
flutter analyze
flutter test
existing product-gates
P2 behavioral workflow
```

on Windows, macOS and Linux.

This is not merely a future closure item: it is necessary before approving `prepare`, because `prepare` commits and pushes the patch.

---

## 7. P1 base verification remains shallower than the claimed authority gate

The launcher checks for P1 evidence/task filenames and waits for exact tri-OS `product-gates` on current `origin/main`.

It does not:

- parse and require the P1 aggregate manifest status;
- bind the aggregate manifest to the exact base commit/tree;
- execute `tool/p1_exit_gate_test.py`;
- verify the P1 closure record semantically.

The known current P1 main is green, so this is not presently evidence that P1 is broken. It is a fail-closed launcher weakness that can matter if `main` is later modified or evidence files are malformed.

### Required V61 correction

Parse and verify the P1 aggregate manifest, execute the P1 exit gate in a detached worktree at the exact base SHA, and require semantic closure before creating a P2 branch.

---

## 8. Controlled-runner resources are templates, not delivered evidence

V60 correctly refuses to complete without externally signed controlled-runner packets and technology receipts.

However, none of the following were supplied for this review:

- real runner provisioning packets;
- signed per-run attestations;
- controlled authority resources;
- real package/service provisioning receipts;
- three technology-candidate receipt sets;
- Windows/macOS/Linux behavioral artifacts.

Therefore the real behavioral closure path cannot yet be reviewed or approved.

The launcher also requires these repository variables to exist before it will commit:

```text
KRISTIN_P2_RUNNER_PROVISIONING_PACKET_{PLATFORM}
KRISTIN_P2_RUNNER_PROVISIONING_TRUST_{PLATFORM}
KRISTIN_P2_RUNNER_ATTESTATION_{PLATFORM}
```

### Impact

V60 is source architecture plus validators. It is not yet an executable complete P2 train in the user’s repository.

---

## 9. The external package validator was not attached

The user supplied the V60 ZIP and launcher. The separate:

```text
validate_kristin_p2_v60_package.py
```

was not attached to this review message.

The launcher’s embedded package verifier was tested successfully, but the claimed external-validator SHA and its mutation behavior could not be independently reviewed.

This is not the primary blocker, but the final V61 review should include the external validator’s exact bytes.

---

# What V60 genuinely fixed from V59

V60 should receive credit for these corrections:

- exact ZIP/launcher binding is correct;
- package manifest and cache hygiene are correct;
- historical P0 toolchain lock is no longer directly rewritten;
- exact Python setup/checking is present;
- native helpers are built in platform CI;
- package operations use a controlled local npm installation/removal path;
- service operations target real user-scoped providers;
- the product E2E begins at `ProductRuntime.initialize`;
- watchdog arming/heartbeat ownership is implemented in the product runtime;
- the technology-spike finalizer requires three external, independently executed candidates and no longer treats the bundled smoke probe as completion evidence;
- assertion CLI and inventory regressions are materially stronger;
- merge governance is significantly improved.

Those improvements make V60 a strong basis for V61.

---

# Safe action

The only safe action is package verification:

```bash
bash './integrate_kristin_p2_full_train_v60(1).sh' verify-package \
  --package './KRISTIN_P2_FULL_INTEGRATION_V60(1).zip'
```

Do not run:

```text
prepare
resume
--merge-authorized
```

Do not create or push `integration/p2-full-train-v60`.

---

# Minimum V61 acceptance gate

1. Worker receives public verification material only; no grant/consumption/desktop-signing HMAC key leaves protected authority.
2. Tests prove worker material cannot forge grant, consumption, or desktop IPC records.
3. P2 consumes the shared live P1 control-plane service rather than reconstructing a parallel P1 authority.
4. Signed runner attestation binds exact repository/workflow/run/attempt/job/runner session.
5. Post-run cleanup receipt is generated and validated for the exact behavioral run.
6. Runtime resources resolve from application-owned paths, not source CWD.
7. Exact protected-main patch applies and compiles with pinned Flutter.
8. P1 aggregate evidence and exit gate are semantically verified at base SHA.
9. Real signed controlled-runner packets and technology receipts are supplied.
10. Real Windows/macOS/Linux P2 behavioral artifacts pass independent review.
11. Independent security review binds exact source commit/tree, worker/runtime binaries, runner resources and receipts.
12. Exact branch, PR test-merge and merged-main product/P2 workflows pass.
13. Squash-merged protected-main tree equals the reviewed final tree.
14. External package validator exact bytes are included and verified.

---

# Classification

| Area | Result |
|---|---|
| Exact ZIP/launcher binding | PASS |
| ZIP safety and internal manifest | PASS |
| Source inventory | PASS |
| Evidence/finalizer regressions | PASS |
| Assertion CLI no-exception regression | PASS |
| Node tests | 16/16 PASS |
| POSIX native build/probe | PASS |
| Separate P2 toolchain authority | IMPROVED |
| Target-host package/service source path | IMPROVED |
| Product watchdog ownership | IMPROVED |
| Merge governance | STRONG |
| Protected-key boundary | **CRITICAL FAIL** |
| Single shared P1 authority | FAIL / UNPROVEN |
| Signed per-run runner binding | FAIL |
| Post-run cleanup proof | FAIL |
| Installed/runtime resource resolution | INCOMPLETE |
| Exact protected-main Flutter compile | UNPROVEN |
| Controlled tri-OS runner evidence | NOT SUPPLIED |
| Safe to run `verify-package` | YES |
| Safe to run `prepare` | NO |
| Safe to push/PR/merge | NO |
| Safe to mark P2 DONE | NO |
| Required next revision | **V61** |
