# Kristin P2 Full Integration V59 — Independent Technical Review

## Verdict

**NO-GO. Do not run `verify-package`, `prepare`, `resume`, push, open a PR, or merge the uploaded V59 candidate.**

V59 contains meaningful engineering improvements over V58, but the exact uploaded bytes fail the package’s own first gate, and several closure-critical claims remain untrue:

1. the launcher is not bound to the uploaded ZIP;
2. “production P1 authority” evidence is produced with a fixture authority;
3. the new P2 runtime and workspace are not integrated into Kristin’s actual application composition;
4. P2-007 and P2-008 are completed through fixture package/service operations rather than real target-host operations;
5. the watchdog lacks production arming/heartbeat integration;
6. the technology spike overstates detach/reconnect and process-tree termination;
7. the P0-004 toolchain authority is mutated without matching P0-004 exact-run evidence;
8. the behavioral workflow does not enforce the governed Python runtime.

Request a corrected **V60**.

---

## Exact uploaded-byte verification

### Uploaded ZIP

Actual SHA-256:

```text
baaa1851bcc59a3a7d4b9a93e8b1ac0ed0efc6edc1ed3d42031d89b0363806d8
```

### Uploaded launcher

Actual SHA-256:

```text
2529a85ae8d349336283601ddef3fa06e9a7275b35b6e3578a309a73a614aeb0
```

### Digest expected by the launcher

```text
3d2950b9b0756b125f46ca678c844607dbc1c1fc333bbd1cb7a16cf2fff18121
```

Running the uploaded launcher against the uploaded ZIP returns:

```text
ERROR: package SHA-256 mismatch:
baaa1851bcc59a3a7d4b9a93e8b1ac0ed0efc6edc1ed3d42031d89b0363806d8
!=
3d2950b9b0756b125f46ca678c844607dbc1c1fc333bbd1cb7a16cf2fff18121
```

Therefore the documented “safe first operation” is not executable.

---

## Independently verified positives

Although the whole-archive binding is stale, the ZIP itself is structurally coherent:

- 171 ZIP files inspected.
- `PACKAGE_MANIFEST.json` identifies:
  - schema `4.0.0`;
  - package `KRISTIN_P2_FULL_INTEGRATION_V59`;
  - 170 payload records.
- Every payload byte count and SHA-256 matches the internal manifest.
- ZIP integrity passes.
- No traversal path, duplicate/case collision, symlink, encrypted member, cache directory, `.pyc`, `.pyo`, `node_modules`, build directory, or `.dart_tool` payload was found.
- The standalone launcher passes `bash -n`.
- All 22 P2 Python tools parse and byte-compile.
- Exact P2 source inventory passes:
  - 20 production Dart files;
  - 13 Dart test/support files.
- Evidence-contract positive/tamper/forgery tests pass.
- The task assertion CLI regression executes P2-001 through P2-014 without the V58 `cwd` exception.
- Node authorization/security tests pass **16/16**.
- POSIX CMake configure/build succeeds with warnings as errors.
- The POSIX watchdog and native PTY probe build.
- The POSIX native probe emits a passing receipt.
- No `tasks/completed/P2-xxx.md` packet is packaged.
- Aggregate P2 remains `source_only_not_complete`.

These are genuine improvements. They are not sufficient for P2 closure.

---

## Release-blocking defects

## 1. Exact package verification is broken

The uploaded launcher hardcodes a SHA-256 that does not match the uploaded ZIP.

This is not a cosmetic sidecar mismatch. The launcher itself refuses to extract or execute the candidate.

### Required V60 correction

- Rebuild the final ZIP once.
- Calculate the digest from those exact immutable bytes.
- Insert that digest into the standalone launcher.
- Never modify the ZIP afterward.
- Re-run the external validator and mutation rejection against the final uploaded ZIP and launcher.
- Publish matching SHA-256 sidecars.

---

## 2. Product-path evidence still uses a fixture P1 authority

`test/product/p2_product_runtime_e2e_test.dart` creates:

```text
_NodeFixtureDesktopAuthority
```

and invokes:

```text
automation_host/src/fixture-authority.mjs
```

That fixture authority creates and signs its own grants, bootstrap material, replay state, and consumption receipts.

The evidence nevertheless declares:

```text
authorizationBoundary:
p1-authenticated-ipc-and-capability-grant-v2
```

The final evidence validator checks that this text is present. It does not prove that the real P1-003/P1-004/P1-009/P1-012 implementation issued the envelope.

No concrete production class connecting the existing P1 control plane to `P2AutomationEnvelopeAuthority` exists in the V59 production inventory. The available production code defines the abstract interface, while the closure E2E test supplies the fixture implementation.

### Impact

P2-002, P2-003, P2-005 through P2-011, and P2-013 can be represented as passing through “production P1 authority” without traversing the real P1 authority.

### Required V60 correction

Add an adapter implemented against the actual repository P1 APIs and make closure tests use it.

The evidence must bind:

```text
actual P1 authority implementation type
actual P1 policy decision ID/hash
actual P1 Capability Grant v2 ID/digest
actual P1 authenticated IPC channel identity
actual P1 durable consumption/replay state version
actual revocation epoch
```

Fixture authority may remain for unit tests, but any fixture-authority result must be ineligible for behavioral task completion.

---

## 3. The new runtime composition is not integrated into Kristin’s real application

V59 adds:

```text
P2OwnerRuntimeComposition
P2OwnerWorkspace
P2OwnerWorkspaceServiceActions
```

but no existing Kristin application composition root, startup path, navigation surface, or main runtime is modified to instantiate them.

`p2_integrate_shared_surfaces.py` updates source inventories, release validation, verification scripts, roadmap files, and documentation. It does not connect P2 to the running application.

The E2E test directly instantiates `P2OwnerRuntimeComposition`, so the receipt’s “product entry point” is an isolated P2 test harness, not Kristin’s actual desktop runtime.

The evidence validator accepts any nonempty values beginning with `P2` for:

```text
entryPoint
productionAdapter
```

This is not proof that the application uses that entry point.

### Impact

The source can pass standalone P2 tests while the installed Kristin application exposes no operational Owner Mode, terminal, worker lifecycle, or emergency watchdog.

### Required V60 correction

Wire P2 into the real application:

```text
actual ProductRuntime/startup
actual dependency composition
actual Owner Mode settings/navigation
actual workspace lifecycle
actual shutdown/crash reconciliation
actual terminal/session restoration
```

Run an E2E test beginning at the same application entry point used by the shipped desktop binary.

---

## 4. P2-007 package operations are fixture-only

The closure E2E test calls:

```text
manager = fixture
package.apply
```

The host writes a JSON ledger under `KRISTIN_P2_FIXTURE_ROOT`.

For non-fixture package managers, native `package.apply` returns approval-required/unsupported rather than performing the operation.

The task’s done criterion requires fixture installers and dry-run policies **plus real smoke tests on target images**.

The old `p2_host_platform_smoke.py` contains supplementary local npm smoke logic, but V59 task assertions do not invoke that script. The behavioral completion path uses only the fixture ledger plus SDK discovery.

### Impact

P2-007 can become DONE without proving a real governed package-manager operation on Windows, macOS, or Linux.

### Required V60 correction

For each target platform, exercise at least one controlled, reversible package operation through the actual P2 production adapter:

- target-image package-manager dry run;
- controlled local package install;
- installed-state postcondition;
- controlled remove/rollback;
- executable/version provenance;
- exact owner/elevation interaction where required.

Fixture-ledger results may supplement but cannot replace target-host evidence.

---

## 5. P2-008 service mutation is fixture-only

The closure E2E test uses a service ID beginning with:

```text
fixture.
```

The worker starts and stops a Node process stored in an in-memory fixture service map.

Real service start/stop paths return approval-required/unsupported. Only service status has a real platform command.

Application open/close is closer to a real managed process path, but real service mutation is not proved.

### Impact

P2-008 can be marked DONE while actual user/service control remains unavailable.

### Required V60 correction

Test a controlled user-level service/daemon on each platform through the production adapter:

- Windows user-scoped fixture service or governed service fixture;
- macOS LaunchAgent fixture;
- Linux user service fixture;
- status → start → observed running → stop → observed stopped;
- exact process/service identity and rollback notes;
- no elevation claim where no elevation was exercised.

---

## 6. The emergency watchdog is not armed or heartbeated by production UI/runtime code

`P2EmergencyController` exposes:

```text
arm()
heartbeat()
pauseAndKill()
```

but no production code calls `arm()` or establishes a periodic heartbeat loop.

Search of production P2 sources finds no production invocation of watchdog arming or heartbeat. The workspace emergency button only calls `pauseAndKill()` using a watchdog ID supplied externally.

The closure E2E test directly calls `composition.watchdogTransport.arm()`. That bypasses the production controller/workspace lifecycle.

### Impact

The native timeout helper may work in a test, while the real application never arms it and the emergency button targets an unknown watchdog.

### Required V60 correction

Implement and test:

- watchdog creation when a supervised run/session starts;
- periodic heartbeat from the desktop control plane;
- heartbeat cancellation on normal shutdown;
- exact watchdog/session/process binding;
- frozen real application event loop;
- separately supervised kill;
- receipt reconciliation after desktop recovery;
- idempotent emergency action from the actual UI command path.

---

## 7. P2-004 technology-spike evidence overstates capabilities

### POSIX native candidate

The native PTY probe waits approximately 120 ms before reading from the same master file descriptor and reports:

```text
detachReconnect = true
```

It never detaches a consumer, closes/reopens a transport, reconnects by cursor, or proves backlog replay.

### Windows native candidate

The native ConPTY probe:

- starts `cmd.exe`;
- starts a background PowerShell child;
- terminates only the primary process with `TerminateProcess`;
- checks only that the primary process exited;
- reports `processTreeTermination = true`.

It does not prove that the descendant PowerShell process exited.

It also reports `detachReconnect = true` based only on observing output after a delay.

### Dart/native candidate

The Dart candidate launches the same native probe and republishes its capability map. It is a wrapper measurement, not an independently exercised control-plane lifecycle implementation.

### Impact

All three candidates can be classified as equivalent and passed even though two required capabilities were not actually measured.

### Required V60 correction

Each candidate must independently prove:

- true consumer detach;
- continued PTY output while detached;
- reconnect using a durable cursor;
- exact backlog replay;
- no duplication/loss;
- child and descendant process-tree termination;
- zero surviving descendants;
- equivalent protocol and lifecycle semantics.

---

## 8. The P0-004 toolchain authority is mutated without matching P0 evidence

`p2_extend_toolchain_lock.py` appends:

```text
automation_host/package-lock.json
```

to the P0-004 `lockfiles` list and recomputes the P0 `declaredInputFingerprint`.

The completed P0-004 evidence records exact fingerprints and manifest hashes from its two reviewed tri-OS runs. V59 does not regenerate or supersede those P0-004 exact-run artifacts, and its prepare scope forbids changing P0 evidence.

### Impact

The source authority can diverge from the exact authority proven by P0-004 closure. Existing full product gates may reject this, or the repository may silently carry a P0 lock whose closure evidence proves different inputs.

### Required V60 correction

Do not rewrite the closed P0-004 authority as though the original exact runs included Node.

Use a separate, versioned P2 toolchain-extension authority that:

- references the immutable P0-004 manifest/fingerprint;
- adds Node, setup-node, self-hosted runner requirements, and package-lock digest;
- has its own exact tri-platform receipts and comparison;
- is validated by release gates without rewriting historical P0 evidence.

---

## 9. The P2 workflow does not enforce the governed Python runtime

The P2 workflow sets up exact Node and Flutter versions but does not use the governed `actions/setup-python` pin.

`p2_platform_ci.py` checks exact Node and Flutter versions. It does not verify the runtime Python version against the P0-004 lock.

On self-hosted behavioral runners, all evidence/finalization tools therefore execute with whichever Python happens to be installed.

### Impact

Exact behavioral receipts are not reproducible under the complete governed toolchain.

### Required V60 correction

Use the immutable governed setup-python Action and exact Python version on every P2 behavioral lane, then record and validate:

```text
Python version
Python executable digest/provenance
Node version
Flutter version
Dart version
CMake/compiler identity
native binary build identity
```

---

## 10. Controlled self-hosted desktop runners are required but not delivered or proven

The workflow requires labels such as:

```text
self-hosted
kristin-p2
interactive-desktop
windows-2025 / macos-15 / ubuntu-24.04
```

That is the correct direction for P2-009, but V59 contains no runner provisioning, registration, permission, isolation, or trust evidence.

The receipt later stores Boolean fields:

```text
interactiveDesktopAttested = true
behavioralLaneAttested = true
```

because workflow environment variables were set. It does not independently bind the registered runner group, labels, session identity, desktop login, screen-recording permission, or accessibility permission.

### Impact

`prepare` will queue or time out unless those runners already exist, and a Boolean cannot substitute for governed runner provenance.

### Required V60 correction

Provide a separately reviewed runner-provisioning packet and bind each receipt to:

- GitHub runner ID/name/group;
- exact labels;
- host image/version;
- logged-in interactive session identity;
- permission preflight;
- runner configuration digest;
- cleanup/reset receipt;
- no concurrent untrusted workload.

---

## Additional observations

### Good correction: task assertion CLI

The V58 undefined `cwd` error is fixed. The V59 regression executes all fourteen CLIs.

In the local review environment, only P2-014 passed; the others correctly remained blocked because Flutter/native/platform proof was unavailable. That is an honest no-exception test, not behavioral closure.

### Good correction: evidence digest fixture

The positive evidence fixture now computes a real canonical artifact-directory digest, and mutation/tamper cases are separate.

### Good correction: source inventory

The grant-consumption authority and its test are now included in exact discovered-versus-declared inventory equality.

### Good correction: POSIX native build

The POSIX watchdog and PTY probe compile and execute locally.

### Remaining Flutter uncertainty

The exact Dart/Flutter sources could not be analyzed with the governed Flutter SDK in this review environment. Exact format, compile, analysis, widget tests, and integration with current protected-main source remain mandatory.

---

## Safe action

Do not run the uploaded launcher, including `verify-package`.

The ZIP may be retained as V60 source material because its internal manifest is consistent, but it is not an executable integration candidate.

Request V60 using this report as the required remediation specification.

---

## Minimum V60 acceptance gate

1. Final uploaded ZIP and launcher hashes match.
2. Whole-ZIP verification passes; one-byte mutation fails.
3. Internal manifest and cache/path protections pass.
4. Exact P1 production authority adapter exists and is used by closure E2E tests.
5. Fixture authority is explicitly ineligible for completion.
6. P2 is wired into Kristin’s real application composition and UI.
7. P2-007 performs real controlled target-host package operations.
8. P2-008 performs real controlled user-service lifecycle operations.
9. Production watchdog is automatically armed and heartbeated.
10. Frozen-application watchdog test uses the actual application lifecycle.
11. Technology-spike probes prove real detach/reconnect and descendant kill.
12. P0-004 remains immutable; P2 has a separate exact toolchain-extension authority.
13. Exact Python/Node/Flutter/Dart/native compiler toolchains are enforced.
14. Controlled interactive runner provenance and permissions are receipt-bound.
15. Every task assertion begins at the real shipped application/product entry point where applicable.
16. Exact source branch, final branch, PR test-merge, and merged-main product/P2 workflows pass on Windows, macOS, and Linux.
17. Independent review binds the exact source commit/tree, runner receipts, native binaries, and final package digest.
18. Squash-merged protected-main tree equals the reviewed final tree.

---

## Classification

| Area | Result |
|---|---|
| Internal ZIP manifest | PASS |
| Unsafe/cache entry checks | PASS |
| Python parsing | PASS |
| Source inventory | PASS |
| Evidence regression | PASS |
| Task assertion CLI no-exception regression | PASS |
| Node security tests | 16/16 PASS |
| POSIX native build/probe | PASS |
| Whole-ZIP launcher binding | FAIL |
| Real P1 authority path | FAIL |
| Real application integration | FAIL |
| Real package operations | FAIL |
| Real service mutations | FAIL |
| Production watchdog lifecycle | FAIL |
| Technology-spike measurement integrity | FAIL |
| Historical toolchain authority integrity | FAIL |
| Exact Python enforcement | FAIL |
| Controlled runner provenance | UNPROVEN |
| Safe to run `verify-package` | NO |
| Safe to run `prepare` | NO |
| Safe to push or create PR | NO |
| Safe to mark P2 DONE | NO |
| Safe to merge | NO |
| Required next revision | V60 |
