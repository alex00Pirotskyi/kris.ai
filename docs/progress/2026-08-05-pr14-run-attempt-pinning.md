# PR #14 recovery control: exact run and attempt pinning

**Recorded:** 2026-08-05  
**Human roadmap authority:** `docs/roadmap/MASTER.md`  
**Repository:** `alex00Pirotskyi/kris.ai`

## Objective

Prevent a hosted-runner stall or a later duplicate workflow completion from weakening, racing, or overwriting the machine-readable recovery receipt for PR #14.

The target remains `merge/p1-p2-owner-risk-qa-preview` at `0b91e02f2d7413c40dcfa81176877cd3a0daf87e`. This control-plane change does not modify that target or any product behavior. It only narrows which already-reviewed product evidence may authorize construction of the documented repair candidate.

## Situation found

After the broad `workflow_run` handoff landed on protected `main`, product run `30952270186` started from disposable trigger PR #48 at exact SHA `61037b13e71d8b0e6b47feaa9922d476c5666347`.

- Windows completed successfully.
- macOS completed successfully.
- P1A source and native validation completed successfully on Windows, macOS, and Ubuntu.
- Ubuntu product validation remained in the hosted package-installation step without a failure conclusion or available completed-job log.

The incomplete Ubuntu lane was not accepted as tri-platform evidence. Opening another unrestricted source run would have created a race: two later successful `workflow_run` events could each invoke the broad repair helper, and a second invocation could overwrite a valid receipt after the target ref moved.

## Deterministic resolution

The broad listener is replaced by an exact run-attempt-pinned listener:

- source workflow run ID: `30950745333`;
- immutable evidence attempt: `1`;
- fresh event attempt: `2`;
- exact trigger PR: `48`;
- exact trigger branch: `ci/direct-pr14-repair-trigger`;
- exact trigger SHA: `61037b13e71d8b0e6b47feaa9922d476c5666347`;
- same-repository source only.

Attempt 1 is already complete and contains exactly one successful `validate-ubuntu`, `validate-windows`, and `validate-macos` job. After this listener is reviewed and merged, the already-successful Ubuntu job from that run is rerun to produce attempt 2. Attempt 2 is used only as a fresh post-merge event carrier; it is not reclassified as the complete tri-platform evidence set.

The helper independently fetches and verifies:

1. the current source-run object;
2. all three jobs from attempt 1 through the attempt-specific GitHub API endpoint; and
3. the fresh Ubuntu job from attempt 2 through its attempt-specific endpoint.

Every other run ID is ignored, including the stalled `30952270186` run if it later completes.

## Security and authority boundaries

The pinned helper:

- never checks out or executes code from disposable PR #48;
- checks out only the exact status branch and the exact governed PR #14 target;
- requires the exact same repository, PR number, branch, SHA, run ID, run attempt, workflow name, event type, and successful conclusion;
- preserves the existing owner-risk versus formal-dispatch distinction;
- runs the full focused P1/P2, roadmap, generated-state, and whitespace validation before candidate commit creation;
- changes exactly `.github/workflows/ci.yml`, `SOURCE_MANIFEST.sha256`, and `docs/progress/2026-08-05-pr14-ci-recovery.md` in the target candidate;
- publishes a schema-versioned receipt with the evidence attempt and event attempt recorded separately;
- retains the exact candidate commit object when GitHub correctly blocks an Actions token from updating a workflow file.

## Challenges passed

- A partially completed tri-platform run was kept fail-closed rather than treated as two-platform success.
- The recovery avoided spawning unrestricted duplicate source runs that could race the receipt.
- Evidence and event transport were separated explicitly: attempt 1 supplies immutable tri-platform proof, while attempt 2 only emits a fresh post-merge event.
- The listener now ignores every unrelated or later source run by exact run ID and attempt.
- The roadmap authority and owner-risk claim boundary remain unchanged.

## Validation required for this significant push

Before this control change reaches `main`, protected checks must pass on Windows, macOS, and Ubuntu for:

- product source and toolchain gates;
- Flutter formatting, analysis, tests, and native release builds;
- complete P1 trust closure;
- P1A source contracts;
- P1A native authority-service, connector, and restricted-worker builds.

After merge, the rerun attempt must complete successfully before the PR #14 candidate helper can execute.

## Claim boundary

This work does not complete P2 formally and does not make the application public-GA or production-release eligible. PR #14 remains an **owner-risk QA preview** until reconciliation, fresh protected checks, governed merge, landing documentation, cleanup, and roadmap transition required by `docs/roadmap/MASTER.md` are complete.
