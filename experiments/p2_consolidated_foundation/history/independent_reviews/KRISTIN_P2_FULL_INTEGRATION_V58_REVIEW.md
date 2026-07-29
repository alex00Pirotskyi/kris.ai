# Kristin P2 Full Integration V58 — Independent Technical Review

## Verdict

**NO-GO. Do not run `prepare`, `resume`, push, create a PR, or merge V58.**

V58 contains real improvements over V57, and the package itself is intact. However, the supplied `prepare` stage is guaranteed to fail before commit, the task-specific CI assertion runner crashes, the Windows helper is never built or supplied, and several “behavioral” tests remain disconnected from the actual Kristin product implementations they would mark complete.

The package is suitable only for archive verification and as source material for a corrected V59.

## Independently verified improvements

### Package integrity and extraction

- Uploaded ZIP SHA-256 matches:
  `0fcff8f6e1f4eb300e3d78ea8de742085846d274a5a2fe7be8dd557a98d9bea5`
- Uploaded launcher SHA-256 matches:
  `1473d96a8b5e67cb1359d46b7c9df9a5fae47fd1aced347e7281229298b960ea`
- 145 ZIP entries inspected.
- `PACKAGE_MANIFEST.json` identifies schema `3.0.0` and package `KRISTIN_P2_FULL_INTEGRATION_V58`.
- All 144 payload records have matching byte counts and SHA-256 digests.
- No unsafe traversal path, duplicate/case-colliding entry, symlink, encrypted entry, or corrupt ZIP member was found.
- The launcher's `verify-package` mode accepts the genuine ZIP.
- A one-byte package mutation is rejected by the whole-archive digest.
- The inverted V57 package-hash predicate is fixed.

### Local source checks

- Launcher passes `bash -n`.
- All package Python files parse and compile.
- Node authorization/security suite passes **13/13**.
- Native POSIX watchdog compiles under strict warnings-as-errors.
- Node, Flutter, runner and Action pinning is substantially improved.
- The workflow uses `npm ci`.
- The two-stage source-commit → independent-review → evidence-commit design remains.
- PR required-check waiting, test-merge verification, protected-main staleness check, squash merge and final tree-equality verification are all meaningful improvements.

## Release-blocking defects

### 1. `prepare` is guaranteed to fail in the evidence-contract regression test

The launcher executes:

```bash
python "$WORKTREE/tool/p2_evidence_contract_test.py"
```

before creating or pushing the source commit.

That test creates a supposedly valid platform receipt whose `artifactSha256` is hard-coded as:

```python
"artifactSha256": "5" * 64
```

The production validator correctly recomputes the canonical digest of the artifact directory. The fixture digest therefore cannot match.

Independent execution fails with a canonical artifact-digest mismatch.

**Impact:** `prepare` stops before the P2 source commit. No branch CI or review package can be produced.

**Required V59 repair:** build the fixture artifact first, calculate the real canonical directory digest using the production algorithm, place that digest in the valid receipt, then separately mutate it for the negative test.

---

### 2. Every task-specific CI assertion runner crashes due to undefined `cwd`

In `tool/p2_task_platform_assertions.py`, the execution loop calls:

```python
result = execute(spec["command"], spec.get("cwd", root))
```

but later records the test source using:

```python
resolve_test_source(spec, result["command"], cwd, root)
```

No local variable named `cwd` is assigned in that loop.

Independent execution of a task assertion returns:

```text
NameError: name 'cwd' is not defined
```

**Impact:** none of the fourteen task result files can be generated. The P2 workflow cannot produce valid tri-platform behavioral receipts.

**Required V59 repair:**

```python
cwd = pathlib.Path(spec.get("cwd", root)).resolve()
result = execute(spec["command"], cwd)
...
test_source = resolve_test_source(spec, result["command"], cwd, root)
```

Add a regression test that runs the real task assertion CLI for all P2-001 through P2-014 and validates every emitted result file.

---

### 3. Two new grant-authority files are missing from governed source inventories

The overlay contains:

```text
lib/product/p2_grant_consumption_authority.dart
test/product/p2_grant_consumption_authority_test.dart
```

but `tool/p2_integrate_shared_surfaces.py` does not include them in its `LIBS` and `TESTS` inventories.

The actual inventory comparison is:

```text
P2 library files present: 14
P2 library files declared: 13

P2 tests present: 8
P2 tests declared: 7
```

**Impact:** critical replay/use-consumption authority code and its test are not fully wired into source contracts, release validation, or product governance. Product gates may fail, or the files may exist without authoritative inventory coverage.

**Required V59 repair:** add both files to every governed inventory and assert exact set equality between discovered and declared P2 production/test files.

---

### 4. Windows native Job Object helper is never built or supplied to CI

The Node runtime requires:

```text
KRISTIN_WINDOWS_JOB_HELPER
```

for Windows PTY/process-tree lifecycle.

The P2 workflow does not:

- run CMake for the Windows helper;
- compile the helper;
- set `KRISTIN_WINDOWS_JOB_HELPER`;
- verify the helper digest or architecture;
- bind the helper output to the platform receipt.

The Windows platform smoke passes the environment variable through, but the runtime fails closed when it is absent.

**Impact:** Windows P2-005, P2-006 and P2-011 cannot pass as configured.

**Required V59 repair:** build the helper in the Windows job using the exact pinned compiler/toolchain, set its absolute path in the environment, run structured launch/terminate verification, and include helper binary/source/build hashes in the exact Windows artifact.

---

### 5. P2-009 cannot pass on the configured ordinary hosted runners

The package documentation correctly says clipboard, screen and active-window evidence must remain blocked when no interactive desktop is available.

The workflow nevertheless uses ordinary:

```text
ubuntu-24.04
windows-2025
macos-15
```

hosted jobs and provides no:

- interactive logged-in desktop;
- self-hosted target-desktop runner;
- deterministic virtual display with proven clipboard/window integration;
- OS permission setup for screen recording/accessibility;
- capability-based lane selection.

The Linux smoke specifically expects clipboard tools, screenshot capture and an active-window observation.

**Impact:** the configured workflow cannot honestly close P2-009 across all three operating systems.

**Required V59 repair:** use controlled interactive desktop runners or a documented, deterministic virtual-display arrangement that exercises the actual Kristin adapter. Keep P2-009 blocked on noninteractive hosted lanes.

---

### 6. Host smoke tests can pass while the Kristin product methods remain blocked

`lib/product/p2_host_operations.dart` still contains incomplete product behavior:

- package `apply()` returns blocked/unsupported;
- service start and stop are blocked mutations;
- application close is blocked;
- clipboard write throws `UnsupportedError`;
- screen capture throws `UnsupportedError`;
- active-window metadata returns blocked.

But P2-007, P2-008 and P2-009 CI assertions run `tool/p2_host_platform_smoke.py`, which directly invokes host commands and APIs outside those product adapters.

**Impact:** runner capability can be reported as task completion even while the application-facing Kristin implementation remains nonfunctional.

**Required V59 repair:** task assertions must invoke the actual production adapter through the authenticated local IPC/runtime composition used by Kristin. Direct shell smoke may be supplementary evidence only.

---

### 7. No production runtime composition connects the P2 modules

The package provides interfaces and wrappers, but no production implementation was found for:

- `P2AutomationHostClient`;
- `P2PtyBackend`;
- `P2NativeProcessTreeAdapter`;
- `P2WatchdogTransport`.

The concrete implementations found are test fakes. There is no demonstrated application startup/composition path that:

- launches the automation worker;
- establishes authenticated P1 IPC;
- creates a real PTY session;
- attaches process-tree supervision;
- starts/arms the external watchdog;
- routes terminal UI actions to the live host;
- reconciles state after crash/restart;
- shuts down cleanly.

**Impact:** the source can pass isolated module tests while Owner Mode remains non-operational in the product.

**Required V59 repair:** add concrete production adapters and a composition root, then test the complete desktop → IPC → worker/native host → receipt path.

---

### 8. The external emergency watchdog requirement is not proved

`P2EmergencyController` calls an abstract transport, but the package does not demonstrate a production bridge that starts and arms the native watchdog outside the Flutter UI process.

The P2-011 assertion largely reuses process-tree behavior. It does not prove emergency termination while the UI/event loop is frozen.

**Impact:** the core P2-011 acceptance criterion remains unproved.

**Required V59 repair:** run an end-to-end fixture where the desktop/UI process is deliberately unresponsive and a separately supervised watchdog terminates the exact process tree, producing a structured identity-bound receipt.

---

### 9. P2-010 product restore/undo is not exercised end to end

The product snapshot service can create backup/checkpoint metadata and classify operations, but the behavioral fixture performs restore using direct file/Git operations rather than the product restore executor.

**Impact:** the test proves that the fixture script can restore state, not that Kristin's P2 snapshot/undo workflow can.

**Required V59 repair:** implement the production restore executor and make the failure-injection test call it through the same product/runtime boundary used in normal operation.

---

### 10. P2-004 technology selection is not a measured multi-option spike

The spike records limited availability/startup observations and then selects:

```text
typescript-node-node-pty-with-native-lifecycle-adapters
```

It does not implement and compare meaningful PTY/process lifecycle prototypes for:

- TypeScript/node-pty;
- Rust/native;
- viable Dart/native.

It lacks comparable tri-OS measurements for packaging, interactive I/O, resize, Unicode, cancellation, process-tree kill, crash recovery and startup cost.

**Impact:** P2-004 can appear complete without satisfying its technology-spike decision contract.

**Required V59 repair:** run equivalent bounded prototypes and collect machine-observed metrics on all supported platforms before making the governed decision.

---

### 11. Task completion still needs end-to-end product evidence

V58's evidence schema is much stronger than V57: stable assertion IDs, command/test-source hashes, evidence paths, canonical artifact digest and exact run/job binding are good.

But strong receipt structure cannot compensate for tests that exercise a standalone helper instead of the product implementation.

Before any task becomes DONE, each platform result must prove:

```text
real Kristin product entry point
→ P1 authenticated IPC and grant/policy checks
→ production P2 adapter
→ real OS effect
→ machine-observed postcondition
→ structured receipt
```

Descriptions, helper-only smoke tests, source markers and interface mocks are insufficient.

## Safe usage

The only safe command from this package is archive verification:

```bash
bash ./integrate_kristin_p2_full_train_v58.sh verify-package \
  --package /path/KRISTIN_P2_FULL_INTEGRATION_V58.zip
```

Do not run:

```text
prepare
resume
--merge-authorized
```

## Classification

| Area | Result |
|---|---|
| Package SHA and manifest | PASS |
| Safe extraction | PASS |
| V57 ZIP predicate correction | PASS |
| Node security tests | 13/13 PASS |
| Exact runner/Action pin design | IMPROVED |
| Persistent grant/replay design | IMPROVED |
| Two-stage review flow | IMPROVED |
| Squash/final-tree governance | IMPROVED |
| `prepare` executable | FAIL |
| Task-specific CI runner | FAIL |
| Governed source inventory | FAIL |
| Windows native helper CI | FAIL |
| Interactive desktop P2-009 proof | FAIL |
| Production runtime composition | FAIL |
| Product-to-evidence binding | FAIL |
| Safe to verify ZIP | YES |
| Safe to run `prepare` | NO |
| Safe to commit or push | NO |
| Safe to create PR | NO |
| Safe to mark P2 DONE | NO |
| Safe to merge | NO |

## Required next package

Request **V59** with all items above repaired.

The minimum acceptance gate for V59 is:

1. `verify-package` passes and mutation fails.
2. `p2_evidence_contract_test.py` passes with a computed real artifact digest.
3. All fourteen real task assertion CLIs execute without exceptions and emit schema-valid results.
4. Exact discovered-vs-declared P2 source/test inventory equality passes.
5. Native helper/watchdog builds and exact binary receipts pass on all applicable platforms.
6. P2-009 runs only in a real interactive desktop lane.
7. Task assertions invoke production Kristin adapters, not only direct host helpers.
8. Complete desktop/runtime/IPC/PTY/process/watchdog composition is exercised.
9. P2-010 restore is performed through the production implementation.
10. P2-004 compares real alternatives with equivalent tri-platform measurements.
11. Pinned Flutter format/analyze/test passes.
12. Exact branch, PR test-merge and merged-main `product-gates` plus `P2 Owner Mode` workflows pass on Windows, macOS and Linux.
13. Independent security review binds to the exact source commit/tree and receipt hashes.
14. Protected-main merged tree equals the reviewed final tree.
