# Kristin P2 Full Integration V61 — Independent Technical Review

## Verdict

**NO-GO for `prepare`, `resume`, push, PR, or merge.**

**Package verification is approved.**

V61 is the strongest P2 candidate so far and it genuinely fixes most V60 findings:

- exact package/launcher binding is correct;
- the worker bootstrap now contains Ed25519 public verification material rather than raw symmetric/private keys;
- runner attestations bind the exact run, attempt, job, runner and ephemeral session;
- cleanup is executed after the behavioral run;
- runtime resources are staged under application-owned paths;
- the P1 base is semantically validated in an exact detached worktree;
- source, evidence, inventory, Node and native regressions are substantially stronger.

However, the critical desktop/worker authority boundary is still not enforced against a compromised same-account worker. V61 removes raw key material from the worker bootstrap, but stages an **unauthenticated, arbitrary-message signing oracle** and its protected-key handles under the same operating-system account. The worker has full current-account filesystem/process authority by design and can locate and invoke that broker—or access the same user keychain/DPAPI/secret service directly.

V61 also introduces an extensive new concrete P1 control-plane implementation inside the P2 train without creating corresponding amended P1 security evidence, and the launcher is not safely resumable after validation or CI failure.

Request **V62**, preferably split into:

1. a separately reviewed P1 authority-service amendment; and
2. the P2 Owner Mode train consuming that authority.

---

# Exact uploaded-byte validation

## Uploaded ZIP

```text
KRISTIN_P2_FULL_INTEGRATION_V61(2).zip
984cc378bd9388842d6a97ebce0fee8db66b7022e0115faec4265db4ba9ce00c
```

## Uploaded launcher

```text
integrate_kristin_p2_full_train_v61(2).sh
d9eb8ea89f1d43cf593abfeaead802e0ae0f8b7ca6d2b2b24bfdf9ebd9a18d9d
```

## Uploaded external validator

```text
validate_kristin_p2_v61_package(2).py
1cb785416bf7c77abc40d1ec73ad9f8c0c48e21487e417a5da3f08f05c651eda
```

All three match the published V61 values.

The exact external validation command passed:

```bash
python validate_kristin_p2_v61_package.py \
  KRISTIN_P2_FULL_INTEGRATION_V61.zip \
  --launcher integrate_kristin_p2_full_train_v61.sh \
  --mutation-test
```

Verified result:

```text
ZIP entries:                  225
Manifest payload files:       224
Payload byte/digest checks:   PASS
Launcher package verification: PASS
One-byte mutation rejection:  PASS
Completion claim:             false
```

---

# Independently verified positives

## Package integrity

- ZIP integrity passes.
- Manifest schema is `6.0.0`.
- Package identity is `KRISTIN_P2_FULL_INTEGRATION_V61`.
- All 224 payload rows match exact byte counts and SHA-256 values.
- No traversal paths, absolute paths, duplicate/case-colliding paths, symlinks, encrypted entries, cache directories, bytecode, `node_modules`, `.dart_tool`, or build output.
- No `tasks/completed/P2-xxx.md` files are packaged.
- External validator bytes exactly equal the validator packaged inside the ZIP.
- Launcher passes `bash -n`.

## Source and contract validation

- Exact source inventory passes:
  - 36 production Dart files;
  - 14 test/support Dart files.
- Separate P2 toolchain-extension regression passes without directly rewriting the closed P0 toolchain file.
- Application-composition patch regression passes against the package fixture.
- Evidence tamper/forgery regression passes.
- Strict finalizer no-promotion regression passes.
- All fourteen task assertion CLIs execute without the V58/V59 assertion-runner exception.
- Local evidence remains source-only and cannot mark P2 complete.

## Node and native validation

- Node authorization/security suite passes **25/25**.
- POSIX CMake configure/build passes with warnings treated as errors.
- POSIX watchdog builds.
- Native PTY/process supplementary probe passes.
- The supplementary probe remains correctly marked `completionEligible: false`.
- Unsafe watchdog identity is rejected.

## Workflow and governance improvements

- Immutable Action commits are used.
- Exact Python, Node, Flutter and Dart setup is required.
- Behavioral jobs use controlled self-hosted interactive-desktop labels.
- Signed runner identity binds exact repository/workflow/run/attempt/job/runner session.
- Cleanup is performed with `if: always()` after behavior.
- A blocked provisional result cannot become a passing final platform receipt.
- Source and evidence commits remain separate.
- PR required checks and test-merge workflows are awaited.
- Independent PR approval and explicit merge authorization are required.
- Protected-main staleness is checked.
- Squash merge is used.
- The merged tree must match the reviewed final tree.
- Exact merged-main product and P2 workflows are required.

These are meaningful improvements.

---

# Release-blocking findings

## 1. Critical: the signing broker remains accessible to a compromised worker

V61 correctly removes raw HMAC and Ed25519 private keys from the worker bootstrap.

However, the staged P1 authority bundle contains:

```text
control-plane/p1/current/bin/protectedAuthorityBroker.mjs
control-plane/p1/current/resources/protectedKeyHandles.json
```

The broker supports caller-selected operations:

```text
hmac-sha256
ed25519-public
ed25519-sign
```

and accepts:

```text
handle
expectedPurpose
messageBase64
```

The `ed25519-sign` operation signs arbitrary caller-supplied bytes. The HMAC operation similarly authenticates arbitrary bytes.

The broker performs no caller authentication and does not verify that the message corresponds to an already authorized request, grant, consumption record, audit checkpoint or effect permit.

### Same-account accessibility

The staging tool applies Unix-style `0600`/`0700` modes and records:

```text
workerReadable: false
```

But both desktop and automation worker operate under the same current OS account. Owner Mode is explicitly not a sandbox.

A same-account process can generally:

- read files owned by that account despite `0600`;
- execute files owned by that account despite `0700`;
- derive the application-data directory from `HOME` or `USERPROFILE`;
- discover the deterministic sibling `control-plane/p1/current` directory;
- read the public protected-key handles;
- invoke the Node signing broker;
- on Windows, call DPAPI CurrentUser;
- on Linux, call the user secret service;
- on macOS, attempt access through the same user keychain context.

The worker launch environment includes `HOME`/`USERPROFILE`, `PATH`, `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS`, which makes this especially relevant on Linux and macOS.

### Why this remains critical

V61's bootstrap is public-verifier-only, but the process boundary still exposes a signing capability reachable by the process being constrained.

A compromised worker can potentially mint:

- Capability Grant v2 MACs;
- consumption-receipt MACs;
- authenticated desktop IPC MACs;
- Ed25519 effect permits;
- signed audit checkpoints.

The existing tests prove only that the public key alone cannot sign. They do not prove the worker cannot locate and invoke the broker.

### Required V62 correction

The protected authority must be a separately isolated and authenticated service, not a script executable by any same-account process.

Required properties:

1. **No arbitrary-message signing API.**
   The service accepts typed operation-specific requests only.

2. **Caller authentication.**
   It verifies the exact ProductRuntime desktop process/session and rejects the worker.

3. **OS-enforced isolation.**
   Use a separate OS identity, AppContainer/restricted token, sandbox/ACL boundary, privileged helper, hardened service, or equivalent proven isolation.

4. **Non-exportable keys.**
   Use keychain/keystore ACLs that permit signing only through the authority service.

5. **Authorization inside the service.**
   The service validates policy decision, grant, use consumption, revocation, nonce, deadline and audit state itself before signing.

6. **Worker-denial adversarial test.**
   Launch the real worker and prove it cannot:
   - read the handle bundle;
   - execute or connect to the signing authority;
   - use DPAPI/keychain/secret service to sign;
   - mint any grant, receipt, IPC record, checkpoint or effect permit.

Until that proof exists, `workerReadable: false` is metadata rather than an enforced boundary.

---

## 2. V61 adds a new P1 authority implementation without amended P1 evidence

Completed P1 originally delivered trust primitives such as:

```text
deterministic_policy_engine.dart
capability_grant_v2.dart
key_registry_v2.dart
signed_audit_checkpoint_v1.dart
local_authenticated_ipc_v1.dart
```

V61 now adds many concrete P1 runtime files:

```text
p1_control_plane_state_v2.dart
p1_desktop_control_plane_authority.dart
p1_grant_use_state_v2.dart
p1_live_policy_state_v2.dart
p1_protected_authority.dart
p1_product_runtime_shared_control_plane_factory.dart
p1_shared_control_plane.dart
p1_p2_product_runtime_composition.dart
```

`P1ProductRuntimeControlPlaneFactoryV2.open()` constructs the concrete:

- policy engine;
- live policy state;
- revocation source;
- key registry;
- protected signing broker;
- durable grant-use ledger;
- owner-approval broker;
- grant store;
- signed audit chain;
- P1 desktop authority.

This is not merely a P2 adapter to an already existing concrete runtime service. It is a substantial new P1 authority implementation introduced by the P2 package.

The launcher explicitly allows changes under:

```text
lib/product/p1_
test/product/p1_
```

while forbidding changes to completed P1 evidence.

### Impact

The security-critical P1 trust boundary changes after P1 closure without:

- amended P1 task evidence;
- an updated P1 threat model;
- updated P1 key/IPC security review;
- exact P1-specific cross-platform behavioral evidence;
- a separately reviewed P1 authority-service decision.

### Required V62 correction

Split this into a governed P1 amendment or P1.1 security subtrain:

1. implement and review the shared P1 authority service;
2. update the P1 threat model and authority architecture;
3. prove the isolated broker boundary;
4. run exact P1 regression and cross-platform security evidence;
5. merge the P1 amendment;
6. have P2 consume only the merged P1 service interface.

P2 should not silently redefine the P1 TCB while claiming P1 evidence remains unchanged.

---

## 3. The launcher is not safely resumable after failure

`prepare` creates the local branch and worktree before running:

- application patching;
- Python contract tests;
- Flutter format/analyze/test;
- npm installation/tests;
- runner-variable validation;
- branch CI;
- controlled behavioral CI.

On failure, cleanup removes the temporary worktree but does **not** remove the newly created local branch.

The next invocation refuses to reuse any existing local or remote branch:

```text
branch already exists; V61 will not silently reuse existing work
```

If failure occurs after pushing, the remote branch also remains and blocks reruns.

This is particularly likely because:

- controlled-runner variables may not yet exist;
- controlled self-hosted runners may be offline;
- exact Flutter patching has not yet been proven against the live repository;
- external runner packets are not yet supplied.

### Required V62 correction

Implement explicit staged/resumable modes:

```text
prepare-source
resume-source-ci
collect-review
resume-evidence
merge
```

or add safe recovery rules:

- delete an unpushed local branch automatically when it has no unique commit;
- keep and report a source commit when local validation passed;
- permit exact-SHA resume after CI or runner failure;
- require `--discard-failed-branch <expected-sha>` for destructive reset;
- never require users to manually repair worktree/branch state.

---

## 4. Real controlled-runner evidence is still external and unavailable

V61 supplies schemas, validators and templates, but this review did not receive:

- signed provisioning packets for all platforms;
- signed exact-run attestations;
- post-run cleanup receipts;
- real Windows/macOS/Linux behavioral artifacts;
- three tri-platform technology-candidate measurement sets;
- independent security approval;
- owner approval.

The package correctly keeps P2 incomplete without them.

### Impact

The source architecture can be reviewed, but actual P2 behavior and completion cannot yet be approved.

---

## 5. Exact protected-main Flutter integration remains unproved

The package includes a guarded patcher and synthetic anchor regression. `prepare` also runs Flutter before committing, which is correct.

But the construction validation explicitly did not execute the governed Flutter SDK against the exact live P1 repository.

Still unproved:

- exact patch anchors against current `origin/main`;
- Dart compilation;
- ProductRuntime lifecycle behavior;
- UI navigation/semantics compatibility;
- full existing Flutter regression suite;
- startup outside the synthetic fixture.

This must pass before any source commit is pushed.

---

## 6. Runtime staging remains an installation/deployment dependency

V61 improves runtime resolution by removing dependence on `Directory.current`.

However, the runtime still requires a separately staged application data layout containing:

- exact Node executable;
- automation host;
- native helpers;
- provisioning metadata;
- P1 security metadata;
- protected-key handles;
- owner-approval resources;
- controlled package/service resources.

That is acceptable as a P2 contract, but the provisioning process and security boundary must be independently reviewed and reproducible. Ordinary installed/runtime behavior is not yet proved.

---

# Recommended action

## Approved now

Only verify the immutable package:

```bash
python validate_kristin_p2_v61_package.py \
  KRISTIN_P2_FULL_INTEGRATION_V61.zip \
  --launcher integrate_kristin_p2_full_train_v61.sh \
  --mutation-test
```

## Not approved

Do not run:

```text
prepare
resume
--merge-authorized
```

Do not push `integration/p2-full-train-v61`.

Continue using the already created quarantined safe-foundation branch for non-authority P2 contracts and native probes while V62 is built.

---

# Minimum V62 acceptance gate

1. Signing authority is unreachable by the worker through OS-enforced isolation.
2. Broker accepts typed authorized operations, never arbitrary messages.
3. Real worker adversarial test proves broker/keychain/DPAPI/secret-service denial.
4. New P1 authority implementation is handled as a separately governed P1 amendment.
5. P1 amended threat model and evidence are independently approved.
6. P2 consumes the merged shared P1 service instead of introducing it.
7. Launcher is safely resumable after local, CI or runner failure.
8. Exact live protected-main Flutter patch/analysis/tests pass before push.
9. Signed controlled-runner provisioning packets are available.
10. Exact per-run attestations and post-run cleanup receipts exist for all platforms.
11. Three real tri-platform technology candidates are measured.
12. Real Windows/macOS/Linux task artifacts pass independent review.
13. Independent security review and owner approval bind the exact source/tree/package/evidence graph.
14. Branch, PR test-merge and merged-main product/P2 workflows pass.
15. Squash-merged main tree equals the reviewed final tree.

---

# Classification

| Area | Result |
|---|---|
| Exact package/launcher/validator binding | PASS |
| ZIP safety and manifest | PASS |
| Source inventory | PASS |
| Evidence/finalizer regressions | PASS |
| Assertion CLI regression | PASS |
| Node tests | 25/25 PASS |
| POSIX native build/probe | PASS |
| Public-only worker bootstrap | PASS |
| Worker inability to reach signer | **CRITICAL FAIL / UNPROVEN** |
| Single existing P1 authority consumption | FAIL — new P1 TCB added |
| Runner attestation design | IMPROVED |
| Post-run cleanup design | IMPROVED |
| Launcher recovery/idempotency | FAIL |
| Exact live Flutter integration | UNPROVEN |
| Controlled tri-OS evidence | NOT SUPPLIED |
| Safe to verify package | YES |
| Safe to run `prepare` | NO |
| Safe to push/PR/merge | NO |
| Safe to mark P2 DONE | NO |
| Required revision | **V62** |
