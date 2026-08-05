---
phase: P19
title: "Web/mobile companions, headless nodes, and ecosystem"
execution_view_status: BLOCKED_BY_FLEET_AND_REALTIME
primary_workers: [H, F, E]
test_center_module: "Companions & Ecosystem"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P19 — Web/mobile companions, headless nodes, and ecosystem

## Purpose

This is the bounded execution packet for P19. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_BY_FLEET_AND_REALTIME`
- Primary workers: Worker H, Worker F, Worker E
- Test Center module: `Companions & Ecosystem`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P19-001` | Web control plane | `P5-004,P16-009` | Chat, runs, evidence, approvals, remote tools | Browser security and session tests pass. |
| `P19-002` | Android companion | `P17-009,P16-009` | Chat, capture/share, approvals, notifications, local/remote tools | Device/emulator lifecycle and permission tests pass. |
| `P19-003` | iOS/iPadOS companion | `P17-009,P16-009` | Chat, capture/share, approvals, notifications, local/remote tools | Simulator/device and OS-permission tests pass. |
| `P19-004` | Headless node packages | `P16-009,P9-003` | Windows/Linux/macOS service packages | Install/update/revoke/kill tests pass. |
| `P19-005` | Capability/plugin SDK v3 | `P7-009,P11-002,P12-006,P13-002,P14-002,P18-001` | Native, connector, content, model and recipe extension points | One extension of each class passes without core changes. |
| `P19-006` | MCP version adapters | `P7-001,P19-005` | Stable pinned adapter plus 2026-07-28 adapter after final publication | Conformance suites pass without draft lock-in. |
| `P19-007` | A2A 1.0 production adapter | `P7-005,P19-005` | Version negotiation, tasks, artifacts, auth, delegation | Official conformance and adversarial tests pass. |
| `P19-008` | Extension registry and marketplace | `P19-005,P1-006` | Trust, permissions, install/update/revoke and review | Modified/revoked extensions stop loading. |
| `P19-009` | Multi-device continuity | `P19-001,P19-002,P19-003` | Encrypted sync of allowed conversation/run state | Conflict, revoke and cross-account leakage tests pass. |
| `P19-010` | Ecosystem conformance lab | `P19-005` through `P19-009` | Public fixtures and certification reports | Third-party implementations can reproduce results. |

## Test Center deliverables

- `P19-TC-001` web control-plane session/security
- `P19-TC-002` Android permission/lifecycle
- `P19-TC-003` iOS permission/lifecycle
- `P19-TC-004` headless package install/update/revoke
- `P19-TC-005` extension SDK classes
- `P19-TC-006` MCP version adapters
- `P19-TC-007` A2A production conformance
- `P19-TC-008` marketplace revoke/update
- `P19-TC-009` encrypted continuity/conflict/revoke
- `P19-TC-010` public conformance lab

## Acceptance scenarios

- `P19-ACC-001` web/mobile claims never imply desktop authority
- `P19-ACC-002` revoked device loses continuity access
- `P19-ACC-003` headless node kill/update works
- `P19-ACC-004` third-party extension reproduces conformance result

## Exit gate

- Complete all task-specific acceptance, platform, evidence, and Test Center requirements.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker H. Continue the highest-priority dependency-satisfied P19 task.
```
