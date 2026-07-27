# Roadmap V3.1.2 — integrated P0 execution reconciliation

## Authority

This amendment advances the active master roadmap from `3.1.1-p0-003-integration-repair` to `3.1.2-p0-006-governance-integration` without changing task IDs or the long-term Kristin 4.x product target.

## Verified starting point

The cumulative delivery starts from the repository state in which P0-001 and P0-002 are integrated and the v1 signed-manifest trust path fails closed.

## Dependency-correct execution

```text
Stage A
  P0-003 repair + P0-005 policy truth
  → commit and push one exact source revision
  → one GitHub workflow passes validate-ubuntu/windows/macos through native build
  → record P0-003 ci_matrix.json

Stage B
  P0-004 immutable toolchains + P0-006 governance source
  → commit and push
  → run the pinned workflow twice
  → compare toolchain receipts
  → activate/verify GitHub ruleset with a distinct reviewer
```

P0-005 is allowed in Stage A because it depends only on P0-001 and P0-002. P0-004 and P0-006 remain fail-closed until P0-003 evidence exists.

## Integration conflict resolved

The standalone P0-005 bundle contained an older `tool/verify.sh` that used a mutating formatter and omitted P0-003 gates. V3.1.2 does not stack that file. It merges the policy gate into P0-003's non-mutating verification ladder.

## Stable required checks

P0-003 now gives each matrix lane a stable job name:

```text
validate-ubuntu
validate-windows
validate-macos
```

Runner labels can later be pinned by P0-004 without changing the branch-protection contexts.

## Completion truth

- P0-003 is `REVIEW` until the same-commit three-OS run is recorded.
- P0-004 is `REVIEW` until two pinned same-source reruns compare equal.
- P0-005 is `REVIEW` until the policy gate and independent review pass.
- P0-006 is `REVIEW` until remote enforcement and merge-behavior tests pass.
