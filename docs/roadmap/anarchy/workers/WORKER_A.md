---
worker: A
role: "Critical-path product implementer"
status: ACTIVE_REQUEST_CHANGES
branch: "merge/p1-p2-owner-risk-qa-preview"
active_task: "PR #14 regression repair, protected landing, and truthful P2 closure"
last_anchor: "bdfec2232cc1718e8b160e7e2fe5c4374fd4b42b"
reviewer: "Worker B / review 4862421298"
---

# Worker A — Critical-path product implementer

## Activation command

```text
Take https://github.com/alex00Pirotskyi/kris.ai.
You are Worker A. Continue autonomously.
```

## Mission

PR #14 regression repair, protected landing, and truthful P2 closure.

## Phase lane

- [`P2`](../phases/P02-owner-mode-terminal-filesystem-and-os-operations.md) — Owner Mode, terminal, filesystem, and OS operations
- [`P3`](../phases/P03-browser-automation-and-web-studio.md) — Browser automation and Web Studio

## Current repository memory

- Planned/current branch: `merge/p1-p2-owner-risk-qa-preview`
- Execution state: `ACTIVE_REQUEST_CHANGES`
- Last known anchor: `bdfec2232cc1718e8b160e7e2fe5c4374fd4b42b`
- Independent reviewer: Worker B / review 4862421298
- Re-resolve live Git state before acting; this file may lag behind remote commits.

## Ownership

- PR #14 implementation branch
- P2 source and behavioral closure
- exact-head CI repair loop
- P2 evidence finalization

## Do not touch without transfer

- Worker C P4 branch
- Test Center foundation branch
- P3 implementation before P2 closure

## Completed

- [x] P0/P1 foundations present
- [x] P2 integration-control governance merged through PR #61
- [x] inventory and formatter alignment commits preserved

## Exact next actions

1. Read review 4862421298 against the exact current head.
2. Repair only the stale Owner Mode shell/navigation regression or the real product defect it reveals.
3. Run affected Flutter tests and full exact-head gates.
4. Push a new head for Worker B review.
5. Land PR #14 only after fresh tri-platform checks and review.
6. Execute protected-landing P2 behavioral evidence and close status truthfully.

## Autonomous startup checklist

- [ ] Fetch/prune and resolve current `main`, branch, PR, head and tree.
- [ ] Read live `MASTER.md`, `roadmap.yaml`, this file, and linked phase packets.
- [ ] Inspect current task evidence, reviews and CI.
- [ ] Confirm dependencies and file ownership.
- [ ] Baseline the affected subsystem before editing.
- [ ] Implement the smallest coherent in-scope change.
- [ ] Run non-mutating fast checks, affected tests and regressions.
- [ ] Update evidence, docs and this worker memory.
- [ ] Commit, push and inspect exact-head CI.
- [ ] Obtain a fresh independent review for the exact final SHA.

## Progress journal

Use only significant events:

| Event | Commit/run | Result | Evidence / next action |
|---|---|---|---|
| ACTIVATED | — | pending | Resolve live state. |

## Remaining-work ledger

- [ ] Current task reaches its exact acceptance criteria.
- [ ] Required tests and evidence are exact-commit bound.
- [ ] Independent review has no critical/high finding.
- [ ] Worker memory is updated after merge or yield.

## Yield / takeover record

```text
status: ACTIVE
last_verified_head: bdfec2232cc1718e8b160e7e2fe5c4374fd4b42b
next_action: follow “Exact next actions” above
safe_takeover: only after confirming no newer remote worker commit
```

## Final response contract

```markdown
## Worker A
## Task
## Result: DONE | REVIEW | BLOCKED | YIELDED
## Exact repository state
## Changed
## Verification
## Evidence
## Review
## Remaining
## Next task
```
