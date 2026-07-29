# Kristin P2 Full Integration V57 — Independent Technical Review

**Review date:** 2026-07-28
**Package reviewed:** `KRISTIN_P2_FULL_INTEGRATION_V57(1).zip`
**Launcher reviewed:** `integrate_kristin_p2_full_train_v57(1).sh`
**Verdict:** **NO-GO for prepare, push, PR, or merge**

## Executive summary

V57 is a meaningful improvement over V56. It fixes the previously reported Dart named-argument defects, adds a real two-stage prepare/review/resume flow, hardens ZIP extraction, binds owner and independent-review artifacts to an exact source commit/tree/package digest, waits for product and P2 workflows, and introduces substantially better IPC/grant/session tests.

However, V57 still contains two immediate release blockers:

1. The launcher always rejects the correct ZIP because its SHA predicate is inverted.
2. The tri-platform receipt generator can label most P2 tasks as behavioral PASS using hard-coded assertion descriptions rather than task-specific observed test results.

Additional integration and lifecycle blockers remain around the Node toolchain lock, explicit runner pinning, durable replay/use state, Windows Job Object termination verification, and merge strategy.

Do not execute `prepare` or `resume` against the production repository until these findings are corrected in a new package.

## What passed

### Package and launcher integrity

- ZIP SHA-256 matches the published value:
  `470a57b41dd94a3ce4e3706cafb2d8521c7f83dd01cd8b3da17ccc2e9eeee85f`.
- Launcher SHA-256 matches the published value:
  `22263293645f8483bea4c40bc44222d747659b663621cb6cc1c3759033200764`.
- 136 ZIP entries were inspected.
- No traversal paths, absolute paths, duplicate/case-colliding entries, encrypted entries, or symlinks were found.
- Every payload file matches `PACKAGE_MANIFEST.json` by size and SHA-256.
- Standalone and packaged launcher contents agree.
- Launcher passes `bash -n`.

### Local source tests

- All P2 Python tools compile.
- 11/11 Node authorization and security tests pass.
- POSIX watchdog compiles with strict C11 warnings-as-errors.
- The source/local P2 gate is honest about unsupported evidence: P2-001, P2-004, P2-005, P2-007, P2-008, and P2-012 remain `source_only` locally.
- The source-only exit gate does not claim P2 completion.
- Previously reported Dart constructor syntax defects are corrected.
- Owner workspace terminal controls are no longer empty callbacks.

### Review and governance design improvements

- Prepare and resume are separate stages.
- Review is bound to exact commit, tree, package digest, and platform receipt digests.
- Critical/high findings must explicitly be empty.
- Conditional approval requires every condition to be satisfied.
- Owner approval explicitly acknowledges full current-account authority and non-sandbox semantics.
- The prepare branch must be exactly one commit above final P1 main.
- Resume permits only an evidence/roadmap/source-authority commit.
- Product and P2 workflows are required on source, final, PR test-merge, and merged-main SHAs.
- Required PR checks and independent GitHub PR approval are enforced before merge authorization.

## Release blockers

## 1. Critical — launcher always rejects the correct package

The embedded verifier contains:

```python
if expected == '470a57b41dd94a3ce4e3706cafb2d8521c7f83dd01cd8b3da17ccc2e9eeee85f' or digest != expected:
    raise SystemExit(...)
```

The launcher always passes that exact literal as `expected`. The first condition is therefore always true, so both `prepare` and `resume` stop with a package mismatch even when the ZIP is correct.

Required correction:

```python
if expected != '470a57b41dd94a3ce4e3706cafb2d8521c7f83dd01cd8b3da17ccc2e9eeee85f':
    raise SystemExit('ERROR: launcher expected-package constant changed')
if digest != expected:
    raise SystemExit(f'ERROR: package SHA-256 mismatch: {digest} != {expected}')
```

A regression test must execute the verifier with both the genuine ZIP and a modified ZIP.

## 2. Critical — behavioral receipts still overclaim task completion

`tool/p2_platform_ci.py` creates a `task_specific` dictionary of descriptive strings and then initializes every P2 task as:

```python
assertions = {
    task: {
        'status': 'passed',
        'sourceOnly': False,
        'assertions': task_specific[task],
    }
    for task in TASKS
}
```

Only P2-007, P2-008, and P2-009 are replaced with parsed task rows from a host-smoke report. The remaining tasks become behavioral PASS merely because broad commands completed and a non-empty list of assertion labels exists.

This is especially problematic because the same package's local behavioral gate honestly reports several tasks as `source_only`. The tri-platform runner does not parse those statuses or correlate individual test cases to individual task claims before overwriting them as passed.

`validate_platform_receipt()` then checks only:

- `status == passed`;
- `sourceOnly == false`;
- a non-empty assertion-string list.

It does not require machine-observed assertion results, test IDs, commands, output hashes, or task-specific evidence artifacts. `p2_finalize_evidence.py` can therefore promote all fourteen tasks to DONE from self-declared receipt rows.

Required correction:

- Every P2 task must emit a separate machine-readable result from an executed test/gate.
- Each assertion needs at least: stable assertion ID, task ID, platform, command/test source, observed status, result hash, and evidence path.
- `p2_platform_ci.py` must derive task status exclusively from those observed result files.
- Any `source_only`, `unsupported`, `blocked`, `skipped`, `not_tested`, absent, or malformed assertion must block the task.
- Receipt validation must reject plain descriptive strings as behavioral proof.
- The strict finalizer simulation must include forged hard-coded assertion rows and prove they are rejected.

## 3. High — exact Node version is required but not added to the governed toolchain lock

`p2_toolchains.py` requires exact Flutter and Node versions from `config/toolchains.lock.json`. The package does not modify that lock file.

The evidenced P0-004 toolchain shape currently covers Python, Flutter, Dart, and immutable Actions. Unless protected main has acquired an unshown Node field, the P2 workflow will fail before setup-node with:

```text
exact node version missing from toolchain lock
```

Required correction:

- Add an explicit Node version to the existing governed toolchain lock through the same P0-004 authority model.
- Update toolchain-lock tests, source manifest, release validation, and evidence.
- Do not infer Node from the local workstation or use a floating major version.
- Prove the same exact Node version on Windows, macOS, and Ubuntu.

## 4. High — runner labels remain floating and configuration-dependent

The workflow uses repository variables with `*-latest` fallbacks:

```yaml
ubuntu-latest
macos-latest
windows-latest
```

The existing P0-004 contract requires explicit runner labels. The established pins are `ubuntu-24.04`, `windows-2025`, and `macos-15`.

Repository variables may be used only if their exact values are validated against the governed lock and the workflow fails when they are absent or different. A `*-latest` fallback is not acceptable.

Required correction:

- Use explicit pinned labels directly, or load exact labels from the governed lock and validate them before jobs are dispatched.
- Remove all `*-latest` fallbacks.
- Extend `toolchain_lock_test.py` and release validation to cover the P2 workflow.

## 5. High — replay and grant-use state is lost on automation-host restart

The Node IPC verifier creates in-memory maps:

```javascript
const replay = new Map();
const grantUses = new Map();
```

The protected descriptor supplies keys, revocation epoch, and revoked grant IDs, but no durable prior-use or replay state is restored. Restarting the automation host clears both maps.

This weakens the claimed replay and use-count guarantees across crashes/restarts, which are explicitly in P2's adversarial scope.

Required correction:

- Desktop authority must durably consume each grant use before the worker effect, or provide a cryptographically bound monotonic use state that cannot be reset by worker restart.
- The worker must receive and verify the authoritative prior-use/replay state at startup or per request.
- Add crash/restart tests proving that a previously consumed grant use and request cannot be replayed after host restart.

## 6. High — Windows Job Object termination outcome is not verified

`terminateTree()` writes `kill\n`, waits for the supervisor to exit, and returns `status: killed` without validating:

- supervisor exit code;
- the structured `{"status":"killed", ...}` receipt;
- active-process count;
- stderr or partial protocol failure.

A helper failure or premature exit can therefore be reported as successful termination.

There is also a race in attaching a Job Object after node-pty has already started the process. A child can create descendants before assignment, and assignment may fail under pre-existing Job Object constraints.

Required correction:

- Capture and parse the supervisor kill receipt.
- Require exit code 0, receipt status `killed`, correct identity, and zero remaining active processes where supported.
- Treat missing/malformed receipt, nonzero exit, timeout, or stderr protocol error as failure.
- Prefer launching the process inside the Job Object before it runs, such as suspended creation followed by assignment and resume, rather than post-spawn attach.
- Add real Windows descendant-race and nested-job tests.

## 7. Medium-high — merge strategy may conflict with repository governance

The launcher uses:

```bash
gh pr merge ... --merge
```

Previous governed integrations used squash merges. If merge commits are disallowed, this will fail after all evidence work. Even if allowed, it changes the intended protected-main history shape.

Required correction:

- Use the repository's established squash strategy unless the governance contract explicitly authorizes merge commits.
- After merge, verify that protected main contains the reviewed source tree/evidence state and exact task closure, not merely that the final evidence commit is an ancestor.

## 8. Medium — complete local Flutter validation remains unproven

The package corrects obvious Dart syntax defects, but Flutter/Dart were unavailable in this review environment. The actual governed checkout still needs:

- pinned `flutter pub get`;
- non-mutating formatting gate;
- `flutter analyze`;
- all P2 Flutter tests;
- existing product source-contract and release validation;
- clean-tree verification after tests.

The launcher intends to enforce these in CI, but blockers 1–4 currently prevent reliable execution of that path.

## Additional observations

- The ZIP safety design is good once the SHA predicate is corrected.
- The independent-review structure is substantially improved and should be preserved.
- The two-commit source/evidence model is reasonable.
- P2 must not be marked complete based solely on generic tri-platform workflow success; each task's exact behavioral proof remains mandatory.
- The uploaded files have `(1)` in their filenames, but V57 requires an explicit `--package` argument, so this is manageable after the package itself is corrected.

## Required V58 acceptance gate

A corrected package should not be approved until all of the following pass:

1. Genuine ZIP accepted and one-byte-mutated ZIP rejected.
2. Exact Node and Flutter versions plus exact runner labels come from the governed toolchain authority.
3. Full product-gates and P2 workflow pass on the exact source commit.
4. Every P2 task result is derived from executed, task-specific, machine-readable assertions.
5. Forged string-only assertion receipts are rejected.
6. `source_only`, unsupported, skipped, absent, or blocked evidence can never become DONE.
7. Grant replay/use consumption remains enforced after automation-host restart.
8. Windows supervisor kill receipt and exit status are verified; process-tree race tests pass.
9. Independent review is bound to exact source/tree/package and exact platform receipts.
10. PR required checks, test-merge workflows, independent approval, and explicit owner merge authorization pass.
11. Protected-main merge uses the repository-authorized strategy.
12. Exact merged-main product and P2 workflows pass on Windows, macOS, and Ubuntu.

## Safe action

Do not run:

```text
prepare
resume
--merge-authorized
```

against the production repository with V57. Return this report to the P2 implementation conversation and request V58 with the blockers above corrected.
