---
phase: P15
title: "Native application/device automation and remote operation"
execution_view_status: BLOCKED_BY_NATIVE_PARITY
primary_workers: [E, D, I]
test_center_module: "Desktop Automation & Devices"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P15 — Native application/device automation and remote operation

## Purpose

This is the bounded execution packet for P15. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_BY_NATIVE_PARITY`
- Primary workers: Worker E, Worker D, Worker I
- Test Center module: `Desktop Automation & Devices`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P15-001` | Desktop observation/action v3 schemas | `P11-008` | Cross-platform semantic tree and target signatures | Golden vectors and stale-target tests pass. |
| `P15-002` | Windows advanced automation | `P15-001` | UIA events, menus, virtualized controls, multi-display | Native fixture suite passes. |
| `P15-003` | macOS advanced automation | `P15-001` | AX events, menus, Spaces/display/TCC states | Native fixture suite passes. |
| `P15-004` | Linux advanced automation | `P15-001` | AT-SPI events, portal/Wayland/X11 strategies | GNOME/KDE fixture suite passes. |
| `P15-005` | Visual fallback engine | `P15-002,P15-003,P15-004` | Confidence, display scaling, region tracking and postconditions | Low-confidence and changed-layout actions pause. |
| `P15-006` | Application adapter SDK | `P12-012,P15-001` | Plugins for app-specific structured actions | Sample IDE/office adapter passes conformance. |
| `P15-007` | Device and peripheral service | `P11-009` | Print/scan/camera/mic/serial/USB inventory and actions | Permission, disconnect and data evidence pass. |
| `P15-008` | Screen/audio recording service | `P11-010` | Visible capture state, regions, devices, privacy masks | Hidden capture and revoked-permission tests fail safely. |
| `P15-009` | Remote desktop trusted-node protocol | `P1-012,P12-001,P15-001` | Encrypted session, screen/input/file policy, receipts | Node substitution, disconnect and revoke tests pass. |
| `P15-010` | Native automation benchmark | `P15-005,P15-006,P15-007,P15-009` | Cross-OS real-app and fixture corpus | Target success and zero unintended-action threshold pass. |

## Test Center deliverables

- `P15-TC-001` target-signature schema
- `P15-TC-002` Windows advanced automation
- `P15-TC-003` macOS advanced automation
- `P15-TC-004` Linux advanced automation
- `P15-TC-005` visual-fallback confidence
- `P15-TC-006` application-adapter SDK
- `P15-TC-007` device/peripheral service
- `P15-TC-008` visible screen/audio capture
- `P15-TC-009` trusted remote desktop protocol
- `P15-TC-010` native automation benchmark

## Acceptance scenarios

- `P15-ACC-001` structured action beats synthetic input
- `P15-ACC-002` stale/ambiguous visual target pauses
- `P15-ACC-003` capture state is always visible
- `P15-ACC-004` remote node revocation stops new actions
- `P15-ACC-005` unplugged device returns honest state

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
Take the repo. You are Worker E. Continue the highest-priority dependency-satisfied P15 task.
```
