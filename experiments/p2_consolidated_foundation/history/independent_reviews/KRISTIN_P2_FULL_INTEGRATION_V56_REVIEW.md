# Kristin P2 Full Integration V56 — Independent Technical Review

Review date: 2026-07-28

## Verdict

**NO-GO for push, PR, merge, or P2 completion.**

The archive is internally consistent and contains useful P2 scaffolding, Linux reference behavior, documentation, and tests. However, the package has compile-blocking Dart defects, incomplete native/product implementations, over-permissive evidence finalization, CI/toolchain violations, security-review binding defects, and merge-orchestration bugs. It must be corrected before it is applied to the governed P2 branch.

## Verified package properties

- Uploaded ZIP SHA-256: `e51892842619d05b924e7540a53c77c45af1ee206dd065f96c7729fb35f722a3`.
- Uploaded launcher SHA-256: `a30b3a7cd776731eb926b0559b89037f2a193ceefab32e8918768720f374c847`.
- Standalone launcher is byte-identical to the launcher in the ZIP.
- 172 ZIP entries inspected: no duplicate names, path traversal, or symlink entries.
- Package manifest: 128 listed payload files; every size and SHA-256 matches.
- Launcher `bash -n`: PASS.
- Python P2 tools compile: PASS.
- Node built-in tests: 3/3 PASS.
- Linux/reference behavioral gate executes and honestly reports several tasks as `source_only`.

## Critical blockers

### C1 — Dart source does not compile

Invalid named-argument syntax uses `=` instead of `:`:

- `lib/product/p2_finite_command_service.dart:18`
- `lib/product/p2_filesystem_service.dart:18`
- `lib/product/p2_filesystem_service.dart:20`

Example:

```dart
P2EffectReceipt(effectId='cmd-...')
```

Must be:

```dart
P2EffectReceipt(effectId: 'cmd-...')
```

The package validation did not run Flutter/Dart, so these defects were not detected.

### C2 — Final evidence promotes source-only tasks to DONE

`tool/p2_finalize_evidence.py` marks every P2-001 through P2-014 manifest `passed` and writes completed task packets after running `p2_task_gate.py` without `--require-tri-os`.

`p2_task_gate.py` accepts `source_only` test results as long as they are not explicitly `failed`. The later `--require-tri-os` check only requires generic platform receipt files and a rewritten manifest. It does not require task-specific behavioral proof.

This can incorrectly close at least P2-001, P2-004, P2-005, P2-007, P2-008, and P2-012, which the package itself currently classifies as `source_only`.

### C3 — Required concrete P2 implementations are missing

`lib/product/p2_host_operations.dart` contains interfaces only. There are no concrete Windows/macOS/Linux implementations for:

- package and SDK operations;
- services and applications;
- clipboard access;
- screen capture and active-window metadata.

The Owner Workspace terminal controls are also placeholders: Copy, Save transcript, Interrupt, and Terminate tree have empty callbacks. The emergency keyboard shortcut displays a snackbar rather than invoking the watchdog.

These cannot satisfy the P2 exit gate or be marked DONE.

### C4 — Security review is not bound to the reviewed code

The launcher and finalizer check only:

- `independent == true`;
- an approval decision;
- a non-empty reviewer name.

They do not enforce:

- `reviewedCommit` equals the exact final/preflight commit;
- `criticalHighFindingsRemaining` is empty;
- `approve_with_conditions` conditions are satisfied;
- the review artifact hash is bound to the exact code and CI receipts.

Additionally, the review JSON is required before the launcher creates the preflight/final commit, making an exact commit-bound review impossible in the current one-shot flow.

### C5 — Worker authorization is not enforced end to end

`automation_host/src/host.mjs` accepts self-asserted `peerIdentity` and `authenticatedChannelId`; it does not verify P1 authenticated-IPC MAC/replay state or Capability Grant v2 authenticity.

After `pty.open`, later operations locate a session by `sessionId` but do not verify that the request's run, task, actor, or grant still matches the stored session. A request with another authorization could input into or terminate a different session if its ID is known.

The host must enforce exact session binding on every request and use the P1-012 authenticated transport/verifier rather than trusting string fields.

### C6 — Windows process termination path is internally incompatible

`automation_host/src/process-tree.mjs` invokes the Windows helper using:

```text
--kill PID --start-token TOKEN
```

But `automation_host/native/windows/job_supervisor.cpp` implements only:

```text
--attach PID
--launch COMMAND_LINE
```

Therefore the runtime termination path cannot work even though the separate interactive smoke test may pass.

### C7 — POSIX watchdog can target an unsafe process group

`watchdog.c` accepts arbitrary signed `PGID` values and calls `kill(-pgid, ...)` without requiring `pgid > 1` or verifying a managed process identity. Invalid values such as `-1`, `0`, or a reused group can signal unintended processes.

The watchdog must validate the managed identity, positive group ID, ownership/lifecycle token, and bounded timeout before signaling.

## High-severity blockers

### H1 — CI violates the repository's pinned-input contract

`.github/workflows/p2-owner-mode.yml` uses floating references:

- `actions/checkout@v4`
- `actions/setup-node@v4`
- `subosito/flutter-action@v2`
- `actions/upload-artifact@v4`
- Flutter `channel: stable`
- Node major version `22`

The repository's P0 toolchain/governance gates require immutable action references and exact toolchain inputs. The workflow also has no `package-lock.json`, runs `npm install` instead of `npm ci`, and therefore cannot claim reproducible dependency resolution.

Playwright is included in the P2 host dependency set even though browser automation belongs to P3; it should be removed from P2 unless a measured P2 requirement justifies it.

### H2 — Flutter tests are invoked incorrectly

`tool/p2_platform_ci.py` calls `dart test` on tests that include Flutter imports. It should use the repository's exact Flutter SDK, run `flutter pub get`, formatter/analyzer gates, and `flutter test` for Flutter tests.

The script also writes a platform receipt with `status: passed` and `sourceOnly: false` when Dart is unavailable, which is an invalid proof classification.

### H3 — Branch CI does not include the required base product gates

The launcher waits only for the `P2 Owner Mode` workflow on preflight and final branch commits. It does not require the existing `product-gates` Windows/Ubuntu/macOS jobs for those exact SHAs.

A P2 branch can therefore pass its custom workflow while failing the repository's base formatting, governance, manifest, source-contract, analyzer, test, or build gates.

### H4 — PR-context checks are not awaited

After creating the PR, the launcher checks for one approved review and immediately calls `gh pr merge`. It does not wait for required PR-context checks or the GitHub test-merge SHA. This repeats the queued-check merge failure already encountered during P1.

### H5 — `_any` CI selection is ambiguous

`wait_ci` with workflow `_any` selects the first run returned for a SHA. After P2 is introduced, a commit can have both `product-gates` and `P2 Owner Mode` runs. The function can select the wrong workflow and report missing jobs or validate the wrong contract.

Every CI wait must select by exact workflow name/ID and exact head SHA.

### H6 — ZIP authenticity and contents are not verified by the launcher

The launcher calls `unzip` directly into a temporary directory. It does not:

- reject traversal/symlink/duplicate entries;
- verify the ZIP's expected SHA-256;
- verify `PACKAGE_MANIFEST.json` before copying the overlay.

The uploaded archive is safe, but the launcher would trust a substituted archive with the same filename.

### H7 — Existing P2 branch contents are not constrained

If `integration/p2-full-train-wip` already exists, the launcher reuses it as long as `origin/main` is an ancestor. It does not require an exact allowed base, direct-child relationship, clean cumulative scope, or byte-identical existing overlay files.

The resulting branch may contain old or unrelated commits and still be described as one aggregate V56 integration.

### H8 — Preflight receipts are weakly selected and cited

Downloaded artifacts contain technology and behavioral JSON files. The finalizer checks whether any matching file has `status == passed`, but then appends the first matching file, which may be a technology-spike file rather than the behavioral receipt.

Task manifests also do not bind platform receipts to the exact preflight SHA, workflow run ID, job ID, or final branch SHA.

## Additional engineering defects

- Filesystem enumeration performs no authorization call.
- Filesystem writes authorize the raw path but do not robustly bind the resolved parent/target identity through the final rename; symlink/TOCTOU protection is incomplete.
- Quarantine deletion handles only `File`, not directories, and has no cross-volume fallback.
- Finite command execution copies the entire parent environment, potentially exposing reusable credentials to every launched process.
- If process-tree registration fails after process start, the child can be orphaned.
- Windows process identity uses a constant PID-based token rather than an actual creation-time identity, weakening PID-reuse protection.
- The bounded transcript discards an entire oversized chunk instead of retaining the newest allowed bytes.
- PTY shell, cwd, rows/columns, transcript budget, and per-session quotas are not validated in the worker.
- The P2 workflow does not run the complete existing repository verification ladder.
- `--owner NAME` is treated as operator approval without a distinct explicit approval flag or reviewed staged digest.

## Required V57 acceptance criteria

A corrected package should not be accepted until it provides all of the following:

1. All Dart files format, analyze, compile, and pass Flutter tests using the repository's exact pinned SDK.
2. Concrete tri-platform adapters or honest task-specific BLOCKED states for P2-007, P2-008, and P2-009.
3. Functional Owner Workspace controls wired to typed services and watchdog actions.
4. Exact P1 IPC and Capability Grant validation at every worker request, including session binding.
5. Compatible, identity-safe Windows and POSIX process-tree termination implementations and tests.
6. Task-specific tri-OS evidence; source-only results can never be rewritten to passed.
7. Two-stage review flow: prepare exact branch SHA, independent review of that SHA, then merge-resume.
8. Security review commit/hash binding, zero unresolved critical/high findings, and enforced conditions.
9. Immutable GitHub Action SHAs, exact Flutter/Node versions, committed lockfile, and `npm ci`.
10. Exact base `product-gates` plus P2 workflow on preflight, branch, PR/test-merge, and merged-main SHAs.
11. PR-context check waiting and idempotent merge-resume logic.
12. Safe ZIP extraction and full package-manifest verification.
13. Exact staged-scope and ancestry checks; no silent overwrite of existing P2 work.
14. Platform receipts bound to SHA, workflow run, jobs, artifacts, and task-specific assertions.
15. No `tasks/completed/P2-xxx.md` or aggregate `P2: passed` until every task and the P2 exit gate genuinely pass.

## Safe action now

Do **not** run this package with `--push`, `--create-pr`, or `--merge-authorized`.

It should be returned to the P2 implementation conversation as a V56 review failure and rebuilt as a corrected, dependency-complete V57 package against the exact P1 main SHA.
