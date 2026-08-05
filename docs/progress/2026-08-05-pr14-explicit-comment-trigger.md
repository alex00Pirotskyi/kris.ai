# PR #14 recovery control: explicit owner-only command

**Recorded:** 2026-08-05
**Human roadmap authority:** `docs/roadmap/MASTER.md`
**Repository:** `alex00Pirotskyi/kris.ai`

## Objective

Provide one deterministic, reviewable, auditable trigger for constructing the exact PR #14 product-CI repair candidate after all automatic event transports failed to produce the required machine-readable receipt.

The governed target remains `merge/p1-p2-owner-risk-qa-preview` at `0b91e02f2d7413c40dcfa81176877cd3a0daf87e`. This control-plane change does not mutate that branch, change product behavior, or widen authority. It only defines how one already-validated source evidence set may authorize candidate construction.

## Evidence already established

Exact product workflow run `30950745333`, associated with disposable PR #48 at `61037b13e71d8b0e6b47feaa9922d476c5666347`, has two completed attempts.

Both attempt-specific job sets contain one successful job for each required product platform:

- `validate-ubuntu`;
- `validate-windows`;
- `validate-macos`.

The same trigger revision also passed protected P1A source contracts and strict native authority-service builds on Windows, macOS, and Linux during the reviewed recovery-control PR sequence. The explicit command does not replace or reinterpret those checks; it re-fetches the product run and both attempt-specific job sets before target mutation.

## Event transports attempted and challenges passed

The recovery intentionally failed closed through several delivery mechanisms:

1. **Direct Actions push:** candidate construction succeeded, but GitHub correctly rejected updating a workflow file because the GitHub App token lacked workflow-write authority. The candidate Git object remained inspectable, but the target ref was not moved.
2. **Connector-authored push trigger:** commits created through the connected GitHub authority did not reliably emit the expected push-triggered workflow.
3. **Same-repository pull-request trigger:** the disposable PR ran ordinary protected checks, but the specialized helper did not publish its receipt.
4. **`pull_request_target` trigger:** an exact-SHA, same-repository, non-PR-code executor was reviewed and merged, but reopening the trigger PR still produced no receipt.
5. **Broad `workflow_run` handoff:** the handler was reviewed and merged, but a later Ubuntu hosted runner stalled inside package installation. Windows and macOS succeeded; the incomplete run was rejected rather than treated as two-platform evidence.
6. **Run-and-attempt-pinned `workflow_run` handoff:** run `30950745333` was verified in two successful attempts, and the listener was pinned so unrelated runs could not race the receipt. The rerun completed successfully, but no receipt was emitted.

No missing receipt was treated as success, no partial platform result was promoted, and no roadmap or security gate was bypassed.

## Deterministic owner-only trigger

The successor workflow listens to `issue_comment` on protected `main` and accepts exactly one command:

```text
/kristin pr14-repair 0b91e02f2d7413c40dcfa81176877cd3a0daf87e nonce-20260805-bfcd8c76
```

The job starts only when all of the following are true:

- issue number is exactly PR #48;
- the issue is a pull request;
- comment author is exactly `alex00Pirotskyi`;
- `author_association` is exactly `OWNER`;
- event sender and GitHub actor are exactly `alex00Pirotskyi`;
- comment body, target SHA, and nonce match byte-for-byte.

The workflow then re-fetches the comment through GitHub and verifies its positive comment ID, body, owner, and association. It also re-fetches PR #48 and requires:

- state `open`;
- draft status preserved;
- base `main`;
- head branch `ci/direct-pr14-repair-trigger`;
- exact head SHA `61037b13e71d8b0e6b47feaa9922d476c5666347`;
- same-repository provenance.

No source file from PR #48 is checked out or executed.

## Source evidence verification

Before candidate construction, the workflow independently fetches:

- source run `30950745333`;
- attempt 1 jobs through the attempt-specific endpoint;
- attempt 2 jobs through the attempt-specific endpoint.

It requires the run to be completed successfully, associated with PR #48, and pinned to the exact branch/SHA. Each attempt must contain exactly one successful `validate-ubuntu`, `validate-windows`, and `validate-macos` job.

This makes the owner command an authorization signal only. The command cannot fabricate, replace, or weaken source evidence.

## Exact candidate and focused validation

After all trigger and evidence checks pass, the workflow checks out only the exact governed PR #14 target and constructs a candidate with exactly three paths:

1. `.github/workflows/ci.yml` — install the existing wheel-only, hash-locked P1/P2 Python dependency closure immediately after `flutter pub get`;
2. `SOURCE_MANIFEST.sha256` — regenerate using `tool/p2_refresh_source_manifest.py`;
3. `docs/progress/2026-08-05-pr14-ci-recovery.md` — record implementation, challenges, validation, claim boundary, and next steps.

Before committing, it runs:

- P2 governed source inventory;
- owner-risk P1A dependency contract;
- hash-locked Python bootstrap;
- integration-train validation;
- complete P1 exit gate;
- P0-003 repair gate;
- P0-008 roadmap-control tests and strict validator;
- P0-010 generated-state gate;
- Git whitespace checks;
- exact three-path scope assertions;
- exact-once bootstrap assertions;
- required documentation marker checks.

The candidate must be exactly one child of `0b91e02f2d7413c40dcfa81176877cd3a0daf87e`.

## Receipt and replay boundary

The status branch receives a schema `1.3.0` receipt containing:

- target branch and expected head;
- trigger branch, head, PR, comment ID, owner, and command SHA-256;
- exact source run and evidence attempts;
- candidate commit SHA;
- whether the Actions token moved the target ref;
- executor run and attempt;
- `docs/roadmap/MASTER.md` as roadmap authority;
- exact authorized target paths.

Because publishing the receipt changes the disposable PR head away from the command-pinned SHA, the same command cannot authorize a second candidate. The nonce and exact head therefore provide one-shot behavior without relying on hidden state.

## Significant-push validation

Before this trigger definition reaches `main`, protected checks must pass on Windows, macOS, and Ubuntu for:

- product source, roadmap, generated-state, analyzer, test, security, and native release gates;
- complete P1 trust closure;
- P1A source contracts;
- strict P1A native service, connector, and restricted-worker builds.

Only after protected merge will the owner command be posted to PR #48.

## Claim boundary

This is recovery infrastructure for an **owner-risk QA preview**. It does not complete P2 formally and does not make the application public-GA, signed-installer-ready, unrestricted, or production-release eligible. After the candidate receipt is verified, the branch must still be reconciled with then-current protected `main`, revalidated on all three desktop platforms, landed through protected review, documented, cleaned up, and transitioned according to `docs/roadmap/MASTER.md`.
