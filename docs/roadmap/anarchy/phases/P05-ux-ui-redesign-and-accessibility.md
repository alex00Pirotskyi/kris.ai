---
phase: P5
title: "UX/UI redesign and accessibility"
execution_view_status: READY_PARALLEL_P5_001
primary_workers: [F, B]
test_center_module: "User Experience & Accessibility"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P5 — UX/UI redesign and accessibility

## Purpose

This is the bounded execution packet for P5. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `READY_PARALLEL_P5_001`
- Primary workers: Worker F, Worker B
- Test Center module: `User Experience & Accessibility`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P5-001` | Information architecture and UX flows | `P0-008` | Specify navigation, workspaces, jobs-to-be-done, and state transitions. | Clickable or coded flow prototype covers primary scenarios. |
| `P5-002` | Design token system | `P5-001` | Define semantic color, type, spacing, elevation, focus, motion, status, and Owner Mode tokens. | Light, dark, high-contrast, and reduced-motion themes pass. |
| `P5-003` | Reusable component library | `P5-002` | Build buttons, fields, dialogs, split panes, tabs, cards, tables, timelines, badges, empty/error states. | Components have widget, golden, and semantics tests. |
| `P5-004` | Three-pane application shell | `P5-001,P5-003` | Implement resizable left rail, center workspace, right inspector, and bottom activity drawer. | Layouts persist and handle minimum window size. |
| `P5-005` | Global autonomy status and kill | `P2-011,P5-004` | Display profile, model, active sessions, takeover, network, pause, stop, and emergency kill. | Status remains visible across workspaces. |
| `P5-006` | Chat and task composer redesign | `P5-003,P5-004` | Add attachments, project/profile/model/access, plan-only, run, schedule, criteria, and budget. | Composer supports keyboard-only task launch. |
| `P5-007` | Plan review and permission UX | `P1-004,P5-006` | Show goals, files, commands, sites, side effects, verification, risk, and profile. | Owner approval policy `never` is represented accurately. |
| `P5-008` | Unified run timeline | `P5-004` | Render model, policy, file, terminal, browser, web, evidence, verification, retries, and rollback. | Timeline handles 10k events with filtering. |
| `P5-009` | Artifact, diff, and evidence viewers | `P5-003` | Add text/binary metadata, image, Markdown, JSON, table, diff, citation, and receipt views. | All supported evidence types reopen from a saved run. |
| `P5-010` | Command palette and keyboard system | `P5-004` | Add searchable commands, shortcuts, conflict handling, and discoverability. | Primary workflows are keyboard complete. |
| `P5-011` | Onboarding and capability doctor | `P2-001,P3-001,P4-001` | Guide model, Owner Mode, browser, terminal, search providers, storage, and diagnostics. | Fresh machine reaches a tested working state. |
| `P5-012` | Accessibility compliance program | `P5-003` | Add semantics, focus, contrast, scaling, reduced motion, target sizes, and manual checklist. | Applicable WCAG 2.2 AA checks pass. |
| `P5-013` | UI performance budgets | `P5-004` | Instrument startup, frame time, list virtualization, stream throttling, and memory. | Performance dashboard meets initial targets. |
| `P5-014` | UX regression suite | `P5-006,P5-008,P5-009,P5-012` | Add widget, golden, navigation, semantics, keyboard, and failure-state tests. | Critical flow change cannot merge without tests. |
| `P5-015` | Human usability review | `P5-011,P5-014` | Run scripted sessions with representative users; record findings and fixes. | No unresolved critical usability blocker before RC. |

## Test Center deliverables

- `P5-TC-001` navigation/state-transition scenarios
- `P5-TC-002` design-token golden and contrast tests
- `P5-TC-003` component widget/semantics tests
- `P5-TC-004` three-pane persistence and minimum-size tests
- `P5-TC-005` global autonomy/kill visibility tests
- `P5-TC-006` composer keyboard-only acceptance
- `P5-TC-007` plan/permission comprehension tests
- `P5-TC-008` 10k-event timeline performance tests
- `P5-TC-009` artifact/evidence reopen tests
- `P5-TC-010` command-palette and shortcut conflicts
- `P5-TC-011` onboarding/capability-doctor E2E
- `P5-TC-012` accessibility automated/manual program
- `P5-TC-013` startup/frame/memory budgets
- `P5-TC-014` UI regression suite
- `P5-TC-015` human usability evidence

## Acceptance scenarios

- `P5-ACC-001` complete primary task with keyboard only
- `P5-ACC-002` enable and disable Owner Mode with correct persistent status
- `P5-ACC-003` pause/stop from every workspace
- `P5-ACC-004` reopen run evidence after restart
- `P5-ACC-005` screen reader announces takeover and completion
- `P5-ACC-006` high-contrast and scaled-text layouts remain usable
- `P5-ACC-007` non-technical user understands one recovery message

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Primary workspaces are coherent, keyboard accessible, and measurable.
- Owner Mode and kill state are always visible.
- Run, browser, terminal, research, data, and evidence flows pass UI tests.
- Accessibility and performance gates pass.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker F. Continue the highest-priority dependency-satisfied P5 task.
```
