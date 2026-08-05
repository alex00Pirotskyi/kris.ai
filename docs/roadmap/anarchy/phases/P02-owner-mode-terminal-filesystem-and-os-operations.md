---
phase: P2
title: "Owner Mode, terminal, filesystem, and OS operations"
execution_view_status: ACTIVE_CRITICAL_PATH
primary_workers: [A, E, B]
test_center_module: "Owner Mode & Host Operations"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P2 — Owner Mode, terminal, filesystem, and OS operations

## Purpose

This is the bounded execution packet for P2. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `ACTIVE_CRITICAL_PATH`
- Primary workers: Worker A, Worker E, Worker B
- Test Center module: `Owner Mode & Host Operations`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P2-001` | Owner Mode onboarding and settings | `P1-002,P1-004` | Build explicit enablement, persistent indicator, approval policy, data boundary, and disable/reset controls. | User can choose full access and UI never mislabels it as sandboxed. |
| `P2-002` | Full filesystem service | `P1-003,P1-012` | Support absolute paths, drives, shares, hidden files, metadata, search, copy, move, delete, and transactions in Owner Mode. | Cross-platform fixtures pass, including symlinks/reparse points and long paths. |
| `P2-003` | Owner finite command execution | `P1-003,P1-012` | Execute arbitrary direct processes with cwd/env, output limits, cancellation, and effect records. | Commands run outside projects only in Owner Mode and are fully journaled. |
| `P2-004` | Automation host technology spike | `P1-001,P1-012` | Compare TypeScript/node-pty+Playwright, native/Rust PTY+Playwright, and other viable packaging options. | ADR selects a solution using measured startup, memory, packaging, and reliability. |
| `P2-005` | Interactive PTY service | `P2-004` | Implement shell sessions, input, resize, ANSI, attach, detach, reconnect, and transcript. | Interactive fixtures pass on Windows, macOS, and Linux. |
| `P2-006` | Process-tree lifecycle manager | `P2-003,P2-005` | Track stable process identity, descendants, readiness, stop, kill, parent death, and PID reuse. | No child remains after kill/timeout in adversarial tests. |
| `P2-007` | Package and SDK operations | `P2-003` | Add package install/remove/update and SDK discovery with structured receipts. | Fixture installers and dry-run policies pass; real smoke tests run on target images. |
| `P2-008` | Service and application control | `P2-003` | Add service status/start/stop and app open/close adapters with platform-specific implementations. | Supported operations return honest status and rollback notes. |
| `P2-009` | Clipboard and screen capabilities | `P1-003,P1-012` | Add clipboard read/write, screen capture, active-window metadata, and redaction policy. | Capabilities obey profile and do not leak content into logs. |
| `P2-010` | Best-effort host snapshots and undo | `P2-002,P2-003` | Add file backups, Git checkpoints, restore points where available, and operation receipts. | Injected failures restore supported file changes and mark non-restorable effects. |
| `P2-011` | Emergency pause and kill watchdog | `P2-005,P2-006` | Add UI, tray, keyboard shortcut, and worker watchdog kill paths. | Kill works with frozen UI, runaway output, and descendant processes. |
| `P2-012` | Terminal UX | `P2-005,P2-006` | Build tabs, shell/cwd selector, search, save, copy, interrupt, terminate, attach, and run linkage. | Keyboard and screen-reader terminal scenarios pass. |
| `P2-013` | Owner Mode adversarial suite | `P2-002,P2-003,P2-006,P2-011` | Test destructive commands, path races, output floods, fork bombs, crashes, and restart. | Effects are intended, bounded by OS account, observable, cancellable, and recoverable where claimed. |
| `P2-014` | Owner Mode operator guide | `P2-001,P2-013` | Document privileges, risk, backups, unattended mode, secrets, kill, and recovery. | Guide matches UI and tested behavior. |

## Test Center deliverables

- `P2-TC-001` owner-onboarding UI tests
- `P2-TC-002` full-filesystem conformance suite
- `P2-TC-003` finite command execution suite
- `P2-TC-004` automation-host technology benchmark report
- `P2-TC-005` interactive PTY suite
- `P2-TC-006` process-tree lifecycle and escape suite
- `P2-TC-007` package/SDK operation fixtures
- `P2-TC-008` service/application-control fixtures
- `P2-TC-009` clipboard/screen privacy tests
- `P2-TC-010` snapshot/undo and partial-failure suite
- `P2-TC-011` emergency kill independent-path suite
- `P2-TC-012` terminal accessibility and UX tests
- `P2-TC-013` Owner Mode adversarial certification
- `P2-TC-014` consumer acceptance pack

## Acceptance scenarios

- `P2-ACC-001` — Create Desktop hello file
- `P2-ACC-002` create folder, rename file, move file, verify result
- `P2-ACC-003` delete then restore supported snapshot
- `P2-ACC-004` open Notepad/TextEdit/editor with created file
- `P2-ACC-005` open interactive shell, run command, interrupt, close
- `P2-ACC-006` start long-running server, verify readiness, stop complete tree
- `P2-ACC-007` freeze UI simulation and trigger independent emergency kill
- `P2-ACC-008` denied elevation is reported honestly
- `P2-ACC-009` unattended limits stop a long-running task
- `P2-ACC-010` clipboard and screenshot respect profile and redaction

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Owner Mode can access the full host available to the OS account.
- Interactive terminals work on Windows, macOS, and Linux, with platform-specific shell and lifecycle evidence.
- Process trees can be killed reliably.
- Full-host effects are observable, journaled, and recoverable where claimed.
- Owner Mode is clearly distinguished from isolation.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker A. Continue the highest-priority dependency-satisfied P2 task.
```
