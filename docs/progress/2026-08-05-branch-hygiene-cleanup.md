# Repository branch-hygiene cleanup — 2026-08-05

## Roadmap authority

This cleanup is governed by [`docs/roadmap/MASTER.md`](../roadmap/MASTER.md). It changes repository maintenance only. It does not alter product behavior, APIs, messages, access profiles, capability scope, roadmap task completion, evidence classification, public-GA eligibility, or production-release eligibility.

## Why this cleanup is required

The repository accumulated 38 live branches while completing P0, P1, the P1A authority-service train, and the V71-R12 P1/P2 integration recovery. Most of those refs are no longer active work. They are one-shot CI triggers, failed validation snapshots, superseded repair attempts, or intermediate integration branches whose durable evidence is already identified by commit SHA, pull request, workflow run, or committed roadmap record.

Leaving all of those refs live creates four practical problems:

1. branch selection becomes noisy and error-prone;
2. stale one-shot trigger names look active even after their workflows were retired;
3. future automation can accidentally target an obsolete integration head;
4. reviewers cannot quickly distinguish current roadmap work from historical recovery machinery.

This change converts the cleanup from an informal manual deletion into an exact, reviewed, machine-receipted operation.

## Audit snapshot

- Repository: `alex00Pirotskyi/kris.ai`
- Audit time: `2026-08-05T04:13:10Z`
- Protected default branch: `main`
- Audited main SHA: `16459d2fee29e0b6a41b5e4e5da9fc4dcdb93309`
- Branches before cleanup: `38`
- Branches explicitly retained: `6`
- Branches proposed for deletion: `32`

The exact branch names, expected SHAs, cleanup classes, and reasons are committed in `config/branch_hygiene.json`.

## Branches retained

| Branch | Why it remains |
|---|---|
| `main` | Protected default branch and current roadmap authority. |
| `ci/direct-pr14-repair-trigger` | Active draft PR #48 and exact trigger for the protected PR14 repair controller. |
| `integration/p2-owner-risk-v71r12` | P2 integration and evidence lineage retained until owner-risk closure lands. |
| `merge/p1-p2-owner-risk-qa-preview` | Governed P1/P2 landing target retained until protected landing completes. |
| `validated/v71r12-p1-p2-final` | Exact tri-platform validated application candidate anchor. |
| `validation/v71r12-repair-success-30913519385` | Successful repair evidence anchor for run `30913519385`. |

The last five non-default refs are intentionally temporary or evidence-bearing. They will be reviewed again after P1/P2 lands and P2 closure is committed.

## Branches removed by class

### Disposable CI branches

Nine closed, one-shot dispatcher, observer, export, refresh, execution, and reconciliation branches are removed. Their PRs are closed, their exact SHAs are in the cleanup policy, and their durable outcome is already recorded in merged control-plane commits and progress records.

### Superseded repair branches

Four `fix/v71r12-*` refs are removed. They represent intermediate hosted-gate, tri-platform, or hidden-artifact repair attempts superseded by the retained validated and integration lineages.

### Completed or superseded P0/P1 integration branches

Ten P0/P1 refs are removed. Completed P0 state is on protected `main`; early P1A iterations were superseded by the V63-R15 source landing. Commit SHAs and historical PR records remain available after ref deletion.

### Failed validation snapshots

Nine failed V71-R12 integration or repair refs are removed. Failure evidence remains identified by immutable workflow run ID, commit SHA, PR discussion, and committed progress records. The successful validation anchors are not deleted.

## Safety model

`tool/branch_hygiene.py` performs a full read-only preflight before the first deletion:

1. repository identity and default branch must match the committed policy;
2. `main` must exist and remain protected;
3. all six retained branches must still exist;
4. every deletion candidate must either already be absent or point to its exact reviewed SHA;
5. no candidate may be protected;
6. no candidate may be the default branch;
7. no candidate may be the head of an open same-repository pull request;
8. keep and delete sets must be disjoint;
9. every candidate must use a recognized cleanup class and include a human reason.

If any check fails, no branch is deleted. After deletion, the tool re-lists the repository and fails unless every reviewed candidate is absent.

## Automation and receipt

`.github/workflows/branch-hygiene.yml` provides three controlled jobs:

- `branch-hygiene-validate` compiles and self-tests the tool, then validates the live remote plan without mutation;
- `branch-hygiene-source-manifest` regenerates `SOURCE_MANIFEST.sha256` on the exact cleanup PR branch;
- `branch-hygiene-execute` runs only after the protected cleanup change reaches `main`, deletes exact reviewed refs with a `contents: write` token, and uploads a 90-day JSON receipt.

The receipt records the before/after branch counts, open PR heads, full plan, exact deletion results, branches already absent, retained refs, executing run identity, and final remaining branch list.

## Challenges passed

### 1. Branch deletion is destructive

A broad prefix deletion such as `ci/*` or `validation/*` was rejected because one active CI trigger and one successful validation anchor must remain. The adopted policy is an exact branch-and-SHA allowlist.

### 2. Closed PR does not automatically mean safe deletion

Some closed branches preserve currently needed integration or evidence lineage. Open/closed PR state is therefore only one input. The keep set explicitly preserves the active P1/P2 target, integration source, validated candidate, and successful repair anchor.

### 3. Squash merges do not preserve simple ancestry

Several repair branches were merged by squash or superseded by a later repair, so ancestry alone cannot classify them. Each deletion entry includes a cleanup class, immutable SHA, and written reason; historical PR and run identities remain in durable records.

### 4. Source-manifest governance

Adding the cleanup workflow, tool, policy, and progress record changes governed source inventory. A dedicated same-repository PR job regenerates the manifest and permits only `SOURCE_MANIFEST.sha256` as its follow-up diff.

### 5. Avoiding another permanent one-shot mechanism

The cleanup implementation is reusable rather than a hidden ad hoc command. Future cleanup changes must update the reviewed policy, pass the same exact preflight, and produce another receipt.

## Redundant PR cleanup

PR #11 is a superseded duplicate of the governed P1/P2 landing path. It may be closed without deleting `integration/p2-owner-risk-v71r12`; the integration branch remains retained until P2 closure is complete. Draft PR #48 remains open only long enough to execute the exact protected repair handoff.

## Claim boundary

Deleting a branch does not delete the underlying Git commit immediately, invalidate PR history, or erase workflow artifacts. This cleanup does not claim that P1/P2 is landed or that P3 is unblocked. Those transitions remain governed by the exact protected landing, evidence closure, and dependency state in `docs/roadmap/MASTER.md`.

## Next controlled steps

1. Complete the exact PR #48 protected repair handoff.
2. Publish or apply its exact documented candidate to `merge/p1-p2-owner-risk-qa-preview`.
3. Reopen and validate the authoritative P1/P2 landing PR.
4. Close superseded PR #11 while retaining its integration branch until closure.
5. Land P1/P2, finalize owner-risk P2 evidence, and only then review the remaining five non-default refs for a second cleanup.
