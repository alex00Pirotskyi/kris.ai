---
phase: P13
title: "Application Factory and advanced vibe coding"
execution_view_status: BLOCKED_BY_REPOSITORY_AND_PLATFORM_FOUNDATIONS
primary_workers: [F, G, H]
test_center_module: "Application Factory"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P13 — Application Factory and advanced vibe coding

## Purpose

This is the bounded execution packet for P13. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_BY_REPOSITORY_AND_PLATFORM_FOUNDATIONS`
- Primary workers: Worker F, Worker G, Worker H
- Test Center module: `Application Factory`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P13-001` | Application project/spec schemas | `P6-004,P5-006` | Requirements, architecture, acceptance and lineage model | Requirement-to-code/test links survive round trips. |
| `P13-002` | Recipe registry v2 | `P12-006` | Signed application recipe manifests | Changed recipes are detected and versioned upgrades work. |
| `P13-003` | Repository intelligence v2 | `P3-012,P6-003` | Symbols, dependencies, tests, generated files, impact map | Multi-language fixture repos produce correct maps. |
| `P13-004` | Code editing transaction engine | `P13-003,P2-010` | Multi-file patch, checkpoint, conflict, restore | Injected failure restores or marks exact partial state. |
| `P13-005` | Web full-stack golden recipes | `P13-002,P13-004,P3-013` | Static, modern frontend, API+database recipes | Clean creation/change/test/preview/deploy fixtures pass. |
| `P13-006` | Service/API golden recipes | `P13-002,P13-004,P12-011` | TypeScript, Python, Go, Rust, Java/.NET declared recipes | Build/test/package/health/upgrade fixtures pass. |
| `P13-007` | Flutter cross-platform app recipe | `P13-002,P11-010` | Windows/macOS/Linux/web/mobile project recipe | Shared app builds and smoke tests on declared targets. |
| `P13-008` | Native/mobile recipes | `P13-002` | SwiftUI, Kotlin/Compose, optional React Native recipes | Platform CI builds, tests, and emulator/device smoke pass. |
| `P13-009` | Desktop/CLI/extension recipes | `P13-002,P11-010` | Tauri/Electron/CLI/browser extension recipes | Package and behavior fixtures pass. |
| `P13-010` | Design-to-code loop | `P3-015,P13-004` | Tokens, components, screenshot/semantic diff, repair | Responsive and accessibility fixtures converge. |
| `P13-011` | Automated debug and repair | `P13-003,P8-009` | Correlated error/trace/test/source repair loop | Hidden bug corpus improves without repeated-loop failure. |
| `P13-012` | Application deployment handoff | `P13-005,P13-006` | Preview, docs, runbook, rollback bundle | Generated apps reach verified preview from clean checkout. |
| `P13-013` | Vibe Coding workspace v2 | `P5-004,P13-003,P13-010` | Integrated editor/runtime/test/evidence UX | End-to-end keyboard workflow passes. |
| `P13-014` | Application Factory benchmark | `P13-005` through `P13-013` | Hidden/public multi-stack corpus | Success, regression, cost, latency, and false-completion targets pass. |

## Test Center deliverables

- `P13-TC-001` project/spec round-trip
- `P13-TC-002` signed recipe versioning
- `P13-TC-003` repository intelligence corpus
- `P13-TC-004` transactional multi-file editing
- `P13-TC-005` web full-stack recipe certification
- `P13-TC-006` API/service recipe certification
- `P13-TC-007` Flutter cross-platform recipe
- `P13-TC-008` native/mobile recipe lanes
- `P13-TC-009` desktop/CLI/extension recipes
- `P13-TC-010` design-to-code convergence
- `P13-TC-011` automated debug/repair corpus
- `P13-TC-012` deployment handoff
- `P13-TC-013` workbench E2E
- `P13-TC-014` Application Factory benchmark

## Acceptance scenarios

- `P13-ACC-001` create app from brief on clean machine
- `P13-ACC-002` make one feature change and verify runtime
- `P13-ACC-003` inject compiler/runtime defect and repair
- `P13-ACC-004` package/deploy preview and reopen evidence
- `P13-ACC-005` upgrade recipe from previous version

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- At least six materially different application recipes pass full lifecycle tests.
- Windows/macOS/Linux Flutter recipe has synchronized evidence.
- Generated apps are tested, previewed, packaged/deployed, and documented.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker F. Continue the highest-priority dependency-satisfied P13 task.
```
