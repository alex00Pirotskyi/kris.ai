# Migration from the current roadmap to ANARCHY Execution OS

## Objective

Adopt repository-native ten-worker execution without destabilizing active P2 closure, Worker C’s P4-001 branch, current P0/P1 evidence, or the existing roadmap authority.

## Stage 0 — documentation-only proposal

This branch adds the ANARCHY overlay, phase packets, worker memories, templates, and the v3.2 source identity and normalized P00–P24 phase packets. It does not overwrite `docs/roadmap/MASTER.md`, modify `roadmap.yaml`, change product code, or relabel task status.

## Stage 1 — reconcile authority

Worker J compares:

```text
current docs/roadmap/MASTER.md
current docs/roadmap/roadmap.yaml
v3.2 reference
ANARCHY execution constitution
live P2/P4/Test Center state
```

Output: one bounded reconciliation ADR and an exact list of accepted, rejected, and deferred directives.

## Stage 2 — autonomous approval model

Replace routine human-development approvals with:

```text
repository policy
independent AI review
exact-SHA CI
platform certification
automated protected merge
```

External credentials and identities remain environment capabilities; absence becomes a precise blocker, not a routine approval pause.

## Stage 3 — split status domains

Create separate machine schemas for roadmap task status, worker runtime status, test result, certification status, capability support, and runtime health. Preserve old evidence immutably through compatibility readers.

## Stage 4 — promote phase and worker packets

Validate all P00–P24 and Worker A–J files, generate indexes, and make the worker files the durable resumption memory. Shared phase files remain integration-owned to reduce merge conflicts.

## Stage 5 — Project Test Profile and Test Center

Land the versioned Project Test Profile, non-mutating runner, Test Center registry, exact-commit evidence, and affected-test selection. Register existing tests rather than replacing them.

## Stage 6 — machine-readable all-task graph

Extend `roadmap.yaml` from P0/P1 bootstrap scope to the accepted full task graph. CI rejects duplicate IDs, cycles, missing evidence, stale worker claims, and conflicting authority.

## Stage 7 — adoption

Only after validation passes:

1. link ANARCHY from the live `MASTER.md`;
2. mark the execution overlay normative;
3. generate the dashboard from machine state;
4. require worker-file freshness on active-task PRs;
5. retain the v3.2 reference as an immutable source document.

## Active-work protection

During migration:

- Worker A continues PR #14/P2 closure.
- Worker B continues independent PR #14 review and Test Center foundation.
- Worker C continues P4-001 only.
- No migration commit force-resets or rebases those branches.
- No current source-only evidence is promoted to behavioral evidence.

## Rollback

Because Stage 0 is additive documentation, rollback is deletion of the ANARCHY directory and entry point. Later stages require their own migrations and rollback plans.
