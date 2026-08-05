# PR #14 current-main reconciliation controller — 2026-08-05

## Roadmap authority

This reconciliation controller is governed by `docs/roadmap/MASTER.md`. The machine dependency ledger remains `docs/roadmap/roadmap.yaml`.

This is a repository-integration control change. It does not independently change product behavior, APIs, runtime message formats or sizes, access profiles, capability authority, policy semantics, formal-security status, public-GA eligibility, or production-release eligibility.

## Exact state entering reconciliation

- Protected `main` at discovery: `950865fe363bf9556a5760faa06e1a4bff5cb177`
- Governed P1/P2 landing branch: `merge/p1-p2-owner-risk-qa-preview`
- Repaired P1/P2 head: `40b3b1002f37bc9c301bfb5faf9c0b32f5f9a18a`
- PR #14 state before reconciliation: open, `mergeable_state: dirty`
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

GitHub reported PR #14 as `dirty`, so the two histories had a genuine merge conflict. Selecting either side wholesale would be unsafe:

- choosing the P1/P2 branch could discard protected-main governance and recovery controls;
- choosing protected `main` could discard the repaired P1/P2 integration;
- manually editing without first recording the conflict stages would make the resolution difficult to audit;
- merging a generated source manifest by hand would not prove that the final tree is governed.

The controller therefore separated **discovery** from **execution**.

## Read-only discovery result

The initial controller policy authorized discovery only:

```json
{
  "ready": false,
  "expectedConflicts": [],
  "resolutions": {}
}
```

PR #58 run `30978329386` checked out the exact repaired target, attempted a no-commit merge with exact protected-main base `950865fe363bf9556a5760faa06e1a4bff5cb177`, recorded the Git index stages, aborted the merge, and proved the target checkout returned clean.

Discovery artifact:

- artifact ID: `8919135524`
- artifact name: `pr14-main-reconciliation-discovery-30978329386-1`
- digest: `sha256:1b40f2ce1b89ca26999bfbb884756e19d8fce119da5475d369bd5ff5fc5b7004`
- retention: 30 days

### Exact conflict set

The only conflict was:

```text
SOURCE_MANIFEST.sha256
```

The conflict stages were:

| Stage | Meaning | Mode | Blob SHA |
|---|---|---:|---|
| `1` | merge base | `100644` | `32ba45b07621912015c45100a64d8e2171587b04` |
| `2` | P1/P2 target (`ours`) | `100644` | `aebf3eddad4f9fdf30a839ae91a032e45567d033` |
| `3` | protected main (`theirs`) | `100644` | `d567fa2247ddcd4408f2acb24f1dd6450aec77ad` |

No product source, native authority-service source, roadmap document, policy file, or workflow file conflicted.

### Automatically merged paths

Git merged the following protected-main paths into the target index without conflict:

```text
.github/workflows/branch-hygiene.yml
.github/workflows/ci.yml
.github/workflows/pr14-protected-main-repair.yml
.github/workflows/temp-direct-pr14-repair.yml
.github/workflows/temp-pr14-pull-request-repair.yml
SOURCE_MANIFEST.sha256
config/branch_hygiene.json
docs/progress/2026-08-05-branch-hygiene-cleanup.md
docs/progress/2026-08-05-pr14-explicit-comment-trigger.md
docs/progress/2026-08-05-pr14-handoff-bookkeeping-fix.md
docs/progress/2026-08-05-pr14-product-gate-handoff.md
docs/progress/2026-08-05-pr14-protected-main-push-handoff.md
docs/progress/2026-08-05-pr14-run-attempt-pinning.md
tool/branch_hygiene.py
tool/pr14_main_push_repair.py
tool/pr14_main_push_repair_v2.py
tool/pr14_product_gate_repair.py
```

`SOURCE_MANIFEST.sha256` appears in the automatically staged set because Git could stage non-conflicting portions while still retaining one unmerged file entry. It remains the sole unresolved path.

## Reviewed exact resolution

The controller policy is now:

```json
{
  "ready": true,
  "expectedConflicts": [
    "SOURCE_MANIFEST.sha256"
  ],
  "resolutions": {
    "SOURCE_MANIFEST.sha256": "source_manifest"
  }
}
```

The `source_manifest` strategy does not accept either conflicted parent version as final. It stages a temporary side only to clear the index, then regenerates `SOURCE_MANIFEST.sha256` with the governed P2 inventory generator after:

- every automatically merged protected-main file is present;
- the exact reviewed product workflow is present;
- the final reconciliation progress record is created;
- all conflict resolutions are complete.

The regenerated manifest must then pass `tool/p2_source_inventory_test.py`. This resolution is narrower and more trustworthy than manually merging hash lines.

## Product-gate trigger hygiene included in this control change

The previous product workflow ran on unrestricted `push` and `pull_request`. A feature-branch update could therefore create two matrices with the same required names:

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

The discovery merge showed that `.github/workflows/ci.yml` itself did not conflict between repaired target and protected-main base. During protected execution, the controller’s current-main workflow change and the target’s exact bootstrap are expected to merge automatically because they affect separate sections. `verify_ci_contract` remains blocking and requires:

- the hash-locked P1/P2 bootstrap exactly once;
- feature-branch push validation disabled;
- pull-request validation enabled;
- obsolete PR #48 and PR #54 helper jobs absent.

Any deviation blocks candidate creation.

## Protected execution design

Execution remains disabled until this exact reviewed policy and refreshed source manifest pass normal protected checks and merge to `main`. After that protected merge, the push-to-main job:

1. executes only code checked out from the exact protected-main merge commit;
2. requires repository identity `alex00Pirotskyi/kris.ai`;
3. requires the P1/P2 target to remain at `40b3b1002f37bc9c301bfb5faf9c0b32f5f9a18a`;
4. requires the protected control commit to descend from `950865fe363bf9556a5760faa06e1a4bff5cb177`;
5. merges the exact protected control commit into the exact target;
6. requires the observed conflict set to equal `SOURCE_MANIFEST.sha256` exactly;
7. applies only the reviewed `source_manifest` strategy;
8. commits `docs/progress/2026-08-05-pr14-current-main-reconciliation.md` with exact parents, conflict stages, resolution, validation, challenges, and claim boundary;
9. regenerates `SOURCE_MANIFEST.sha256` from the fully resolved tree;
10. runs the P2 source inventory, exact Python lock, integration-train, complete P1 exit, P0-003, P0-008, P0-010, benchmark, and Git whitespace gates;
11. verifies the final product-workflow trigger and bootstrap contract;
12. creates a two-parent merge commit with the P1/P2 target first and protected `main` second;
13. uploads a 90-day JSON receipt with the candidate, parents, observed conflict, stage identities, resolution, changed paths, run identity, result, and target-update state.

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

### Generated-manifest conflict

Discovery proved that the only conflict is generated inventory. The resolution regenerates it from the resolved tree rather than selecting or hand-merging stale parent hashes.

## Current claim boundary

This controller now authorizes the exact protected execution described above, but it does not claim that execution has already succeeded. It does not land P1/P2, complete P2 evidence closure, approve independent security, authorize public GA, authorize production release, or unblock P3.

## Next controlled steps

1. Regenerate `SOURCE_MANIFEST.sha256` for this ready controller state.
2. Pass protected product, P1A, branch-hygiene, and reconciliation checks.
3. Merge the controller and verify the protected execution receipt.
4. Verify the candidate has parent 1 `40b3b1002f37bc9c301bfb5faf9c0b32f5f9a18a`, parent 2 equal to the protected controller merge, and the exact observed manifest conflict.
5. Move the P1/P2 target only to the exact receipted candidate.
6. Require fresh protected PR #14 Windows, macOS, Ubuntu, P1A, P2, and native-release checks.
7. Merge P1/P2 only when all required checks are green.
8. Finalize owner-risk P2 evidence, clean temporary reconciliation/recovery refs, and select the first dependency-satisfied next task from `docs/roadmap/MASTER.md`.
