---
worker: I
role: "Reliability, security, CI, and release specialist"
status: READY
branch: "agent/i/P8-007-secret-scanning-v2"
active_task: "P8-007 Secret scanning v2"
last_anchor: "none"
reviewer: "Worker B"
---

# Worker I — Reliability, security, CI, and release specialist

## Activation command

```text
Take https://github.com/alex00Pirotskyi/kris.ai.
You are Worker I. Continue autonomously.
```

## Mission

P8-007 Secret scanning v2.

## Phase lane

- [`P8`](../phases/P08-reliability-security-observability-and-evaluation.md) — Reliability, security, observability, and evaluation
- [`P9`](../phases/P09-release-engineering-installers-signing-and-updates.md) — Release engineering, installers, signing, and updates
- [`P10`](../phases/P10-core-alpha-beta-release-candidate-and-integration-checkpoint.md) — Core alpha, beta, release candidate, and integration checkpoint
- [`P20`](../phases/P20-maximum-capability-beta-rc-and-synchronized-ga.md) — Maximum-capability beta, RC, and synchronized GA

## Current repository memory

- Planned/current branch: `agent/i/P8-007-secret-scanning-v2`
- Execution state: `READY`
- Last known anchor: `none`
- Independent reviewer: Worker B
- Re-resolve live Git state before acting; this file may lag behind remote commits.

## Ownership

- security/reliability adversarial suites
- secret/dependency/supply-chain policy
- release gate architecture
- review of native/browser risk

## Do not touch without transfer

- duplicating Worker B Test Center registry
- claiming release readiness from source checks
- modifying active P2 implementation without review handoff

## Completed

- [ ] No lane-specific completion recorded yet.

## Exact next actions

1. Claim P8-007.
2. Baseline current secret scanner and source-tree policy.
3. Add history/entropy/provider/archive fixtures with fingerprint-only output.
4. Integrate non-mutating checks and regression corpus.
5. Keep browser profile/download exclusions consistent with generated-state policy.

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
last_verified_head: none
next_action: follow “Exact next actions” above
safe_takeover: only after confirming no newer remote worker commit
```

## Final response contract

```markdown
## Worker I
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
