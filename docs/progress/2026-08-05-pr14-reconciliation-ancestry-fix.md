# PR #14 reconciliation ancestry transport fix — 2026-08-05

## Roadmap authority

This corrective step is governed by `docs/roadmap/MASTER.md`. It changes reconciliation transport only. It does not change product behavior, APIs, runtime message formats or sizes, access profiles, capability authority, policy semantics, roadmap completion claims, public-GA eligibility, or production-release eligibility.

## Exact source and failure state

- Protected reconciliation controller merge: `86abac9f1ace98908404d88a69a00e838abb0b97`
- Protected reconciliation execution run: `30978928032`, attempt `1`
- Execution job: `92218977139`
- Reconciliation receipt artifact: `8919359589`
- Artifact digest: `sha256:abcc016f72f478fa1322789e85e7525f033bbc9cb83b31d914d731c7a2fceb82`
- Governed target branch: `merge/p1-p2-owner-risk-qa-preview`
- Unchanged target head: `40b3b1002f37bc9c301bfb5faf9c0b32f5f9a18a`
- Pinned minimum protected-main ancestor: `950865fe363bf9556a5760faa06e1a4bff5cb177`
- Reviewed exact conflict: `SOURCE_MANIFEST.sha256`
- Reviewed resolution: `source_manifest`

The failed execution produced no reconciliation candidate and did not move the governed target.

## Root cause

The protected-main control checkout used:

```yaml
fetch-depth: 1
```

The reconciliation helper correctly required the executing protected-main commit to descend from the pinned controller baseline:

```text
git merge-base --is-ancestor \
  950865fe363bf9556a5760faa06e1a4bff5cb177 \
  86abac9f1ace98908404d88a69a00e838abb0b97
```

Because the control checkout contained only the tip commit, Git could not resolve the pinned ancestor and returned:

```text
fatal: Not a valid commit name 950865fe363bf9556a5760faa06e1a4bff5cb177
```

The helper then failed closed with:

```text
ReconciliationError: control main does not descend from minimumMainAncestor
```

This was not evidence that ancestry was wrong. The commit object required to prove ancestry was absent from the shallow checkout.

## Exact correction

The protected control checkout now uses:

```yaml
fetch-depth: 0
```

This makes the complete protected-main ancestry available before the existing `merge-base --is-ancestor` gate. The ancestry assertion itself is unchanged and remains blocking.

No conflict policy, expected target SHA, reviewed resolution, validation command, product workflow contract, candidate parent rule, workflow-write restriction, or receipt schema changes.

## Why full protected history is appropriate

1. The checkout is trusted protected-main control code, not untrusted pull-request source.
2. The helper must prove ancestry against an immutable full SHA rather than infer it from dates, PR numbers, or branch names.
3. Fetching all history avoids a second network-dependent special case inside the helper and keeps the receipt transcript straightforward.
4. Repository size is acceptable for this one-shot governed integration controller.
5. The target checkout already uses full history because it must create and verify a two-parent merge commit.

## Validation retained

Before this correction can merge, the repository still requires:

- reconciliation controller compile and self-test;
- repeated read-only discovery with exact manifest-only conflict;
- governed source-manifest regeneration;
- branch-hygiene validation;
- complete Windows, macOS, and Ubuntu product gates;
- complete P1A source and native builds.

After protected merge, execution still must:

1. verify the exact target and remote target SHA;
2. prove protected-main ancestry from `950865fe363bf9556a5760faa06e1a4bff5cb177`;
3. observe exactly one conflict, `SOURCE_MANIFEST.sha256`;
4. regenerate the source manifest from the resolved tree;
5. create the durable final reconciliation record;
6. pass P2 inventory, exact Python lock, integration-train, complete P1 exit, P0-003, P0-008, P0-010, benchmark, and whitespace gates;
7. verify the final product workflow and exact P1/P2 bootstrap;
8. create a two-parent candidate with target first and protected main second;
9. upload a 90-day exact receipt.

## Challenges passed

### Distinguishing missing history from invalid ancestry

The receipt preserved the exact Git error and showed that the failure occurred before any merge attempt. The correction restores the data necessary for the existing ancestry proof rather than weakening or deleting the proof.

### Avoiding target mutation after a control failure

The execution wrapper captured the nonzero result, uploaded the receipt, and failed the enforcing step. No candidate SHA was present and the target remained unchanged.

### Preserving exact conflict authorization

The prior read-only discovery artifact remains authoritative for the conflict stage identities. This change does not add a conflict, resolution strategy, or fallback.

### Maintaining branch hygiene

The correction uses one purpose-specific review branch. It does not recreate any of the 32 redundant branches deleted by protected branch-hygiene run `30975239926`.

## Claim boundary

This fix proves only that protected reconciliation execution can access the history needed for its immutable ancestry gate. It does not claim the reconciliation candidate has been created, P1/P2 has landed, P2 evidence closure is complete, independent security review has passed, public GA is authorized, production release is authorized, or P3 is unblocked.

## Next controlled steps

1. Pass all protected checks and merge this exact transport correction.
2. Verify the next protected reconciliation receipt.
3. Verify the candidate parents, conflict set, manifest regeneration, changed paths, and product-workflow contract.
4. Move the governed target only to the exact receipted candidate when required by workflow-file permissions.
5. Require fresh protected PR #14 checks and merge P1/P2 only when every required lane is green.
6. Finalize owner-risk P2 evidence, remove completed temporary reconciliation/recovery refs, and select the first dependency-satisfied next task from `docs/roadmap/MASTER.md`.
