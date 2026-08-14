# Branch hygiene cleanup — expanded legacy salvage — 2026-08-14

## Decision

The owner pushed a larger set of legacy local branches after the original 17-ref cleanup candidate was prepared. The old tranche is therefore superseded by this expanded, fail-closed policy.

This candidate records **76 exact deletion refs**:

- 17 refs already proven by the first cleanup audit;
- 59 newly pushed legacy refs audited against protected `main` at `67e6e0314877d4ff3233d3e11e0743dd7562de55`, tree `c8326296186720b3f8554574b87eddb859f70109`.

The live audit observed 146 remote branches before cleanup. Branch count is context only; it is not deletion authority.

## Newly pushed legacy tranche

The 59 new candidates are exactly:

- 19 `backup/**` snapshots;
- 22 historical P0 integration refs;
- 7 historical P1 Authority Service revisions;
- 1 quarantined P2 consolidated-foundation ref;
- 1 early P3 full-train WIP ref;
- 5 root-level P0 staging refs;
- 2 rescue stash refs;
- 1 P0-002 security ref;
- 1 no-op Worker F ref.

Every candidate is bound to its current live SHA in `config/branch_hygiene.json`. No wildcard, prefix-wide, age-only, or branch-name-only deletion is authorized.

## Reusable source preservation

### P0 source

The legacy P0 branches are retained in Git history and their executable security/support gates are already preserved or superseded on protected main.

The P0-002 v1 trust-disablement gate remains byte-identical to the legacy security lineage. The P0-005 security/support policy gate is also preserved on protected main. Historical backup and staging refs therefore provide no independent Product continuation after their exact bytes and ancestry are bound in this policy.

### P1 Authority Service

`integration/p1-authority-service-v63r7` through `v63r15` are historical revisions. Protected main contains the later merged authority-service runtime and subsequent security/runtime corrections. The old refs are retained only by Git object history after deletion; no current Product or open pull request depends on their names.

### P2 consolidated foundation

`integration/p2-consolidated-foundation-v1` is a quarantined source-foundation archive rather than a completed Product candidate. Its task-reduction matrix and reference package already exist on protected main under `experiments/p2_consolidated_foundation/**`. Deleting the branch name does not delete that retained source or imply P2 completion.

### P3 WIP

`integration/p3-full-train-wip` points to an early P0-era baseline and is superseded by the later P3 browser-runtime source already landed on protected main. It is not the canonical P3 Product branch.

### P5 no-op ref

`temp-worker-f-noop-discard` has an empty effective tree diff against retained canonical P5 branch `agent/f/P5-001-information-architecture`. The canonical P5 branch remains explicitly retained.

## Explicitly retained

The following are not part of the deletion set:

- `main` — protected source authority;
- `agent/mission-runtime` — mutable Mission Execution authority;
- `agent/mission-execution-v15-gold` — active control-plane candidate;
- `agent/mission-delivery-enforcement-v1` — retained control-plane lineage and open PR head;
- `integration/p2-owner-risk-v71r12` — unique Owner Mode QA/recovery lineage still being ported;
- `ci/direct-pr14-repair-trigger` — unique diverged PR14 repair history pending a separate decision;
- `agent/f/P5-001-information-architecture` — canonical P5 Product branch.

Open pull-request heads, protected refs, current runtime/control authority, canonical Product branches, and any ref that moved from its reviewed SHA must fail the entire cleanup before the first deletion.

## Execution contract

After this policy lands on protected main, `.github/workflows/branch-hygiene.yml` must re-read:

1. all live branch refs and their exact SHAs;
2. the protected-branch list;
3. every open pull-request head;
4. the keep set;
5. the exact 76-candidate policy.

The workflow must stop before deleting anything when:

- a candidate is absent or moved;
- a candidate became protected;
- a candidate became an open PR head;
- a candidate overlaps the keep set;
- a retained anchor is missing;
- the policy does not parse or contains duplicate names;
- the live plan is not `READY`.

Only after all checks pass may the exact refs be deleted and a durable receipt emitted.

## Product continuation

This cleanup removes delivery-capacity debris. It does not replace Product work. After the cleanup candidate reaches exact validation, the next product-first sequence is:

1. re-resolve the Owner Mode recovery lineage and preserve the bounded current-main repair for `merged_p1a_service_unavailable`;
2. re-resolve P5 UX/UI candidates and retain only runtime-reachable, current-main-compatible source;
3. run exact-head Product CI;
4. obtain the required review authority or preserve review debt truthfully;
5. land verified source through protected-main policy;
6. reclaim consumed helper refs through the same exact fail-closed lifecycle.

## Truth boundary

This is repository hygiene and source-preservation work only.

It does not claim:

- P2-005 or P2-006 behavioral certification;
- independent R1/R2 approval for unrelated Product candidates;
- platform or release support;
- production readiness;
- release or GA.
