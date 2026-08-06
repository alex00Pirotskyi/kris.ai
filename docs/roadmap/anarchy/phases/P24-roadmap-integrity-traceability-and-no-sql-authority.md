---
phase: P24
title: "Roadmap integrity, traceability, and no-SQL authority"
execution_view_status: READY_PARALLEL_P24_001
primary_workers: [J, B, I]
test_center_module: "Roadmap & Storage Integrity"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P24 — Roadmap integrity, traceability, and no-SQL authority

## Purpose

This is the bounded execution packet for P24. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `READY_PARALLEL_P24_001`
- Primary workers: Worker J, Worker B, Worker I
- Test Center module: `Roadmap & Storage Integrity`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P24-001` | Approve roadmap-as-data ADR | `P0-008` | Authority, file split, manifest, generation and supersession rules | No competing roadmap authority remains. |
| `P24-002` | Split master roadmap into bounded phase/task files | `P24-001` | Generated navigation and compatibility MASTER | Content hashes and cross-links prove no task loss. |
| `P24-003` | Implement roadmap manifest schema and validator | `P24-001` | IDs, dependencies, cycles, gates, status, evidence and supersession validation | Invalid fixture classes fail CI. |
| `P24-004` | Implement requirement/claim traceability | `P24-003,P23-006` | Promise→requirement→capability→test→evidence graph | Unsupported marketing claim cannot be generated. |
| `P24-005` | Approve no-SQL local authority ADR | `P1-001,P24-001` | Engine evaluation, journal/object/index architecture and migration | Human owner approves no-SQL target and rollback. |
| `P24-006` | Build embedded authority abstraction | `P24-005` | Transaction, query, watch, migration, backup and corruption interfaces | Reference implementation passes durability suite. |
| `P24-007` | Implement SQLite-to-object migration | `P24-006,P8-002` | Restartable migration, verification and rollback | Historical fixtures preserve IDs, events and content hashes. |
| `P24-008` | Replace core SQL-specific indexes | `P24-006,P4-013` | Rebuildable lexical and optional semantic/graph indexes | Full function survives index deletion and rebuild. |
| `P24-009` | Create vertical slice suite | `P24-003,P22-004,P23-019` | V1–V9 scenarios and evidence manifests | Every slice runs on all mandatory desktop OSs. |
| `P24-010` | Generate AI context packs | `P24-002,P24-003` | Bounded task bundles and freshness checks | Local model executes sampled tasks without whole-roadmap context. |
| `P24-011` | Implement documentation and acceptance lint | `P24-003` | Missing criteria, ambiguous verbs, stale links, uncited standards and duplicate authority checks | Seeded documentation defects fail CI. |
| `P24-012` | Roadmap integrity and storage release gate | `P24-001` through `P24-011` | Manifest, traceability, no-SQL migration, vertical slices and context-pack report | Gate V passes before final capability freeze. |

## Test Center deliverables

- `P24-TC-001` roadmap-authority/supersession checks
- `P24-TC-002` split-roadmap content preservation
- `P24-TC-003` manifest ID/dependency/cycle/gate validation
- `P24-TC-004` promise-to-evidence traceability
- `P24-TC-005` no-SQL ADR conformance
- `P24-TC-006` embedded authority durability
- `P24-TC-007` SQLite migration/restart/rollback
- `P24-TC-008` index deletion/rebuild
- `P24-TC-009` V1–V9 vertical slice suite
- `P24-TC-010` bounded AI context-pack freshness
- `P24-TC-011` documentation/acceptance lint
- `P24-TC-012` roadmap/storage certification

## Acceptance scenarios

- `P24-ACC-001` duplicate task ID fails CI
- `P24-ACC-002` dependency cycle fails CI
- `P24-ACC-003` unsupported public promise cannot be generated
- `P24-ACC-004` core runs after deleting/rebuilding derived indexes
- `P24-ACC-005` historical migration preserves IDs/events/hashes
- `P24-ACC-006` each vertical slice passes on Windows/macOS/Linux
- `P24-ACC-007` sampled local model executes task from bounded context pack

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- One human-readable master and one machine-readable manifest control execution.
- Older roadmaps are clearly superseded.
- Task dependencies and evidence are CI-validated.
- Every public promise is traceable to passing evidence.
- The core runs without a SQL database.
- Historical data migrates with verification and rollback.
- Vertical slices prove complete user outcomes across all desktop platforms.
- Local implementation models receive bounded context packs.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker J. Continue the highest-priority dependency-satisfied P24 task.
```
