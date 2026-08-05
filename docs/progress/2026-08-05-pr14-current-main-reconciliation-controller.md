# PR #14 current-main reconciliation controller — 2026-08-05

## Roadmap authority

This reconciliation controller is governed by `docs/roadmap/MASTER.md`. The machine dependency ledger remains `docs/roadmap/roadmap.yaml`.

This is a repository-integration control change. It does not independently change product behavior, APIs, runtime message formats or sizes, access profiles, capability authority, policy semantics, formal-security status, public-GA eligibility, or production-release eligibility.

## Exact state entering reconciliation

- Protected `main`: `950865fe363bf9556a5760faa06e1a4bff5cb177`
- Governed P1/P2 landing branch: `merge/p1-p2-owner-risk-qa-preview`
- Repaired P1/P2 head: `40b3b1002f37bc9c301bfb5faf9c0b32f5f9a18a`
- PR #14 state: open, `mergeable_state: dirty`
- PR #14 recovery parent: `0b91e02f2d7413c40dcfa81176877cd3a0daf87e`
- Protected recovery controller: `950865fe363bf9556a5760faa06e1a4bff5cb177`
- Source product run: `30974509667`, attempt `1`
- Protected candidate run: `30977682920`, attempt `1`

The repaired P1/P2 head is exactly one child of the authorized recovery parent and changes exactly:

1. `.github/workflows/ci.yml`;
2. `SOURCE_MANIFEST.sha256`;
3. `docs/progress/2026-08-05-pr14-ci-recovery.md`.

Its receipt recorded `repairRc: 0`, candidate `40b3b1002f37bc9c301bfb5faf9c0b32f5f9a18a`, and the expected workflow-write restriction. The authenticated repository connector then fast-forwarded the governed target to the receipted candidate and verified the ref.

## Why a separate reconciliation controller is required

Protected `main` advanced while the fixed P1/P2 branch was being recovered. It now contains repository branch hygiene, protected recovery control, recovery bookkeeping correction, and current execution documentation. The P1/P2 branch contains the integrated product and authority-service source plus the clean-runner Python bootstrap.

GitHub reports PR #14 as `dirty`, so the two histories have genuine merge conflicts. Selecting either side wholesale would be unsafe:

- choosing the P1/P2 branch could discard protected-main governance and recovery controls;
- choosing protected `main` could discard the repaired P1/P2 integration;
- manually editing without first recording the conflict stages would make the resolution difficult to audit;
- merging a generated source manifest by hand would not prove that the final tree is governed.

The controller therefore separates **discovery** from **execution**.

## Phase 1: read-only conflict discovery

The initial policy is intentionally:

```json
{
  "ready": false,
  "expectedConflicts": [],
  "resolutions": {}
}
```

On the controller pull request, the discovery job:

1. checks out the exact controller commit as trusted code;
2. checks out the exact P1/P2 target with full history;
3. verifies the local and remote target SHA;
4. attempts a no-commit merge of the pull request’s exact protected-main base SHA;
5. records every unmerged path;
6. records every Git index stage, mode, and blob SHA from `git ls-files -u`;
7. records paths that merged automatically into the index;
8. aborts the merge and proves the target checkout is clean;
9. uploads a 30-day JSON discovery artifact.

No resolution is applied and no branch is updated during discovery.

## Phase 2: reviewed exact resolution

After the discovery artifact is inspected, this same controller change will be updated to:

- set `ready: true`;
- pin the sorted exact conflict set;
- assign exactly one reviewed strategy per conflict;
- document why each strategy preserves the intended authority and product state.

Supported strategies are intentionally narrow:

- `ours`: preserve the P1/P2 target path;
- `theirs`: preserve the protected-main path;
- `delete`: remove an explicitly obsolete path;
- `source_manifest`: do not choose either conflicted manifest; regenerate it from the final tree;
- `compose_ci`: start from the current protected-main product workflow and insert the exact reviewed P1/P2 bootstrap once.

Any new, missing, reordered, protected, or otherwise unexpected conflict blocks execution.

## Product-gate trigger hygiene included in this control change

The current product workflow runs on unrestricted `push` and `pull_request`. A feature-branch update can therefore create two matrices with the same required names:

- one push matrix;
- one pull-request matrix.

That duplicate context caused PR #57 to remain blocked after every real pull-request check passed. The duplicate push-run Windows job also exposed a transient workflow-kernel failure, while the pull-request Windows job on the same commit passed. The failed duplicate context was rerun and completed successfully, but the trigger topology remained unnecessarily expensive and fragile.

The reviewed product-gate control now uses:

```yaml
on:
  workflow_dispatch:
  push:
    branches:
      - main
  pull_request:
```

This preserves:

- a complete matrix for every pull request;
- a complete post-merge matrix on protected `main`;
- explicit manual dispatch;

while preventing a second feature-branch push matrix from publishing the same required contexts.

The permanent product workflow also removes two completed one-shot jobs:

- `pr14-documented-repair` for closed PR #48;
- `pr54-source-manifest-candidate` for the completed recovery-controller setup.

Their durable records, receipts, and merged controller implementations remain in repository history and progress documentation.

## Protected execution design

Execution is disabled until the reviewed policy is ready and merged through normal protected checks. After that protected merge, the push-to-main job:

1. executes only code checked out from the exact protected-main merge commit;
2. requires repository identity `alex00Pirotskyi/kris.ai`;
3. requires the P1/P2 target to remain at `40b3b1002f37bc9c301bfb5faf9c0b32f5f9a18a`;
4. requires the protected control commit to descend from `950865fe363bf9556a5760faa06e1a4bff5cb177`;
5. merges the exact protected control commit into the exact target;
6. requires the observed conflicts to equal the reviewed set exactly;
7. applies only the reviewed path strategies;
8. commits `docs/progress/2026-08-05-pr14-current-main-reconciliation.md` with the exact parents, conflicts, resolutions, validation, challenges, and claim boundary;
9. regenerates `SOURCE_MANIFEST.sha256` from the fully resolved tree;
10. runs the P2 source inventory, exact Python lock, integration-train, complete P1 exit, P0-003, P0-008, P0-010, benchmark, and Git whitespace gates;
11. verifies the final product-workflow trigger and bootstrap contract;
12. creates a two-parent merge commit with the P1/P2 target first and protected `main` second;
13. uploads a 90-day JSON receipt with the candidate, parents, conflicts, stage identities, resolutions, changed paths, run identity, result, and target-update state.

If GitHub correctly blocks an Actions token from moving a ref containing a workflow-file update, only the known workflow-write rejection is accepted. The candidate object and receipt remain available for a separately authenticated fast-forward after independent verification.

## Earlier challenges already passed

### Repository branch explosion

The repository had accumulated 38 live branches. PR #55 introduced a fail-closed, exact-SHA hygiene policy and protected execution receipt. Run `30975239926` deleted 32 reviewed redundant refs and reduced the repository to six retained lineages before this reconciliation work began.

### Clean-runner cryptographic dependency ordering

The full P1 exit gate reached Ed25519 reference tests before the existing hash-locked Python bundle was installed. Protected recovery added the existing wheel-only lock immediately after `flutter pub get`, without weakening tests or changing dependency versions.

### Workflow-write restrictions

GitHub correctly rejected Actions-token updates to a branch when the candidate modified `.github/workflows/ci.yml`. The exact candidate was receipted, its parent and three-path scope were independently verified, and the authenticated repository connector performed only the corresponding fast-forward.

### Untracked documentation and ignored receipt transcript

The first protected handoff correctly failed because an untracked progress document was not included by `git diff --name-only`, and an intentionally ignored `repair.log` could not be staged ordinarily. PR #57 preserved the original authorization and gates while combining tracked and non-ignored untracked candidate paths and force-adding only `repair.log` and `repair-status.json`.

### Duplicate required contexts

Unrestricted feature-branch push plus pull-request triggers produced duplicate `validate-*` contexts. The new trigger contract removes that collision without reducing pull-request or protected-main coverage.

## Current claim boundary

This controller does not claim that reconciliation has succeeded. The initial commit authorizes **discovery only**. It does not land P1/P2, complete P2 evidence closure, approve independent security, authorize public GA, authorize production release, or unblock P3.

## Next controlled steps

1. Run read-only discovery and inspect the exact conflict paths and stage SHAs.
2. Fetch both parent versions of every conflict and document the reviewed resolution.
3. Update this controller’s exact policy to `ready: true` only after the conflict set is understood.
4. Regenerate the source manifest and pass protected product, P1A, branch-hygiene, and controller checks.
5. Merge the controller and verify the protected execution receipt.
6. Move the P1/P2 target only to the exact receipted two-parent candidate.
7. Require fresh protected PR #14 Windows, macOS, Ubuntu, P1A, P2, and native-release checks.
8. Merge P1/P2 only when all required checks are green.
9. Finalize owner-risk P2 evidence, clean temporary reconciliation/recovery refs, and select the first dependency-satisfied next task from `docs/roadmap/MASTER.md`.
