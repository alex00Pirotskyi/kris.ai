# Branch hygiene cleanup — 2026-08-14

## Decision

The repository has real branch debris, but branch count is not itself proof that a ref is disposable. This cleanup therefore remains fail-closed and exact-SHA bound.

The first executable deletion tranche contains **17 currently live refs**:

- 5 exact legacy snapshots already proven superseded by the existing hygiene review;
- 7 short-lived P2/P3 helper and finalizer refs whose outputs are already consumed by protected main;
- 5 Qwen P4 manifest refs attached to terminal `LANDED` Work Orders.

No wildcard, prefix-wide, age-only, or “looks duplicated” deletion is permitted.

## Explicitly retained

`integration/p2-owner-risk-v71r12` is retained. It is old and diverged, but it still contains unique Owner Mode QA lineage that has not yet been ported to current protected main. The correct sequence is port, validate, land, prove redundancy, then delete the old ref.

`ci/direct-pr14-repair-trigger` is also retained because its later diverged history has not yet been proven redundant.

Mission Runtime, the Mission Execution 1.5 control plane, and the delivery enforcement branch are explicit retained anchors.

## Tranche 1 proof classes

### Superseded exact ancestors

Four Worker A backup refs point to the same exact historical commit `345847cb06b3123f2841bdface68a6615cd5de42`. The canonical Worker A lineage continued beyond that ancestor.

`should-not-call` remains an obsolete runtime probe at `0e082868fb91cd9d0e57626e4ba0a0ae2ef895d9`.

### Landed P2/P3 helper refs

The seven `agent/h/*` candidates are bounded manifest, lock-repair, or shared-authority helper branches. Their source has already been consumed by the P3 and P2-004 protected-main landings, and no open pull request uses them.

Three of the P3/P2 helpers intentionally share exact head `ba8833bdb309397142d3b48af340ea33380fa5b1`; retaining three names for one consumed tree provides no product value.

### Landed Qwen manifest refs

The Qwen branches map to either:

- `WO-P4-001-CLEAN-MANIFEST-4D82C7FA`, status `LANDED`; or
- `WO-P4-001-SOURCE-MANIFEST-5A09-7C51A2E4`, status `LANDED`.

They are execution transport debris, not independent product lines.

## Execution contract

`tool/branch_hygiene.py` must still re-read the live repository immediately before deletion and reject the entire operation when any candidate:

- moved from its reviewed SHA;
- became protected;
- became an open pull-request head;
- overlaps the keep set;
- or when any retained anchor is missing.

The cleanup workflow executes only after this policy lands on protected main. The exact deletion receipt remains the durable record.

## Remaining audit

The other live branches are not declared safe by omission. They stay untouched until an exact report proves one of:

1. the branch is an ancestor of a retained canonical lineage;
2. its effective product diff is already contained in protected main;
3. its Work Order is terminal and its helper output was consumed;
4. it is an exact duplicate tree with no independent review/evidence role;
5. it has no open PR, no active semaphore, no canonical Product mapping, and no retained evidence purpose.

This second-pass audit is where the repository can approach the larger “zero-unmerged-product” deletion estimate without converting an estimate into a destructive command.

## Generator debt

The repeated Qwen and finalizer refs confirm a lifecycle defect: helper creation is durable, while helper reclamation is mostly manual. A follow-up runtime hygiene change must make terminal helper cleanup an explicit post-consumption state transition:

`helper consumed → Work Order terminal → no open PR / active semaphore → exact ref deletion candidate`

That mechanism must continue to fail closed and must never infer deletion merely from age or branch naming.
