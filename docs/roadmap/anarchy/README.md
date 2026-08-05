# ANARCHY autonomous execution workspace

This directory turns the Kristin roadmap into a parallel, restartable, repository-native execution system for ten AI workers.

## Read order

1. [`../MASTER.md`](../MASTER.md) — current live human authority.
2. [`ANARCHY_GOD_TIER_EXECUTION.md`](ANARCHY_GOD_TIER_EXECUTION.md) — autonomous multi-worker protocol.
3. [`DASHBOARD.md`](DASHBOARD.md) — current execution snapshot.
4. Your worker file under [`workers/`](workers/).
5. The active phase file under [`phases/`](phases/).
6. Current task packet, evidence, PR, and CI logs.

## Directory contract

```text
anarchy/
  ANARCHY_GOD_TIER_EXECUTION.md
  START_HERE.md
  DASHBOARD.md
  MIGRATION_FROM_CURRENT.md
  phases/P00...P24.md
  workers/WORKER_A...WORKER_J.md
  templates/
  claims/
  reviews/
  reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
```

## Core idea

Workers do not depend on chat history. The repository is the memory.

Each worker owns one worker file and one task branch. It can be stopped, replaced, or resumed by another model without losing state. Shared phase and authority files are updated only through explicit ownership or integration review.

## Non-authority warning

This overlay does not automatically supersede `docs/roadmap/MASTER.md` or `docs/roadmap/roadmap.yaml`. The migration document defines how to promote it safely.
