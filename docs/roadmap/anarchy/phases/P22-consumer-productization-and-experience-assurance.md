---
phase: P22
title: "Consumer productization and experience assurance"
execution_view_status: BLOCKED_BY_CORE_UX_AND_PROVIDER_FOUNDATIONS
primary_workers: [F, B, I]
test_center_module: "Consumer Readiness"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P22 — Consumer productization and experience assurance

## Purpose

This is the bounded execution packet for P22. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_BY_CORE_UX_AND_PROVIDER_FOUNDATIONS`
- Primary workers: Worker F, Worker B, Worker I
- Test Center module: `Consumer Readiness`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P22-001` | Approve consumer product contract ADR | `P5-001,P21-001` | Promises, exclusions, Simple/Advanced/Developer modes, support and evidence rules | No marketing or UX ambiguity remains. |
| `P22-002` | Define consumer metrics and telemetry | `P22-001,P8-010` | Privacy-preserving funnel, success, recovery, hardware and comprehension metrics | Metrics can be measured without collecting task content by default. |
| `P22-003` | Implement resumable first-run state machine | `P5-011,P22-001` | Cross-platform onboarding, resume, reset and failure recovery | Clean fixtures complete without terminal or developer runtime. |
| `P22-004` | Implement Simple Mode | `P5-006,P21-007,P23-006` | One-composer experience with intelligent defaults and concise route disclosure | Representative tasks complete without exposing internal architecture. |
| `P22-005` | Implement Advanced and Developer modes | `P22-004,P5-010` | Progressive controls, searchable settings, safe mode switching | Explicit provider/tool/profile choices remain hard constraints. |
| `P22-006` | Build hardware certification harness | `P18-002,P8-011` | Minimum/recommended/creator tri-OS images and resource tests | Published hardware claims match passing evidence. |
| `P22-007` | Build consumer failure translation layer | `P22-001,P8-003` | Stable consumer states mapped from subsystem errors | User studies meet comprehension target. |
| `P22-008` | Implement Repair Mode | `P22-003,P22-007,P9-009` | Detect, explain, repair, verify and rollback known installation/runtime failures | Injected failures recover at target rate. |
| `P22-009` | Implement cost and quota center | `P21-009,P22-004` | Estimates, hard budgets, reconciled use, browser-subscription qualification | No route is represented as free without evidence. |
| `P22-010` | Implement data and account control center | `P12-004,P21-005,P8-010` | Export, delete, revoke, clear profiles, disclosure history and reset | Deletion/export fixtures pass and secrets are not reproduced. |
| `P22-011` | Implement Owner Mode comprehension UX | `P2-001,P5-005,P22-001` | First-enable education, persistent status, action summaries, kill and disable | Non-technical study meets comprehension threshold. |
| `P22-012` | Complete localization foundation | `P5-012,P22-004` | Locale architecture, string extraction, date/currency, RTL readiness and language matrix | Declared language smoke and layout tests pass. |
| `P22-013` | Complete accessibility consumer gate | `P5-012,P22-004,P22-003` | Keyboard, screen reader, scaling, contrast, motion, captions and takeover flows | Critical flows pass automated and human audit. |
| `P22-014` | Implement support and diagnostic bundle | `P8-009,P22-007,P22-008` | Previewable redacted bundle, support code, known issues and status integration | Seeded secrets and private content are excluded by default. |
| `P22-015` | Run non-technical tri-OS beta | `P22-003` through `P22-014` | Balanced cohort, task recordings with consent, findings and fixes | Primary task, recovery and trust metrics meet targets. |
| `P22-016` | Implement uninstall and local-data removal verification | `P9-005,P9-006,P9-007,P22-010` | Process, helper, cache, profile, model and credential cleanup matrix | Clean-machine before/after tests pass. |
| `P22-017` | Consumer claim generator | `P22-002,P24-004` | User-facing capability, hardware, privacy and limitation text from evidence | Handwritten unsupported claims fail CI. |
| `P22-018` | Consumer productization release gate | `P22-001` through `P22-017` | Tri-OS report, hardware certification, usability, support, privacy and accessibility evidence | Gate T passes with no critical experience, safety or support blocker. |

## Test Center deliverables

- `P22-TC-001` product-promise contract
- `P22-TC-002` privacy-preserving metrics
- `P22-TC-003` resumable first-run E2E
- `P22-TC-004` Simple Mode user-outcome tests
- `P22-TC-005` Advanced/Developer constraint preservation
- `P22-TC-006` hardware certification harness
- `P22-TC-007` failure-message comprehension
- `P22-TC-008` Repair Mode injected failures
- `P22-TC-009` cost/quota transparency
- `P22-TC-010` export/delete/revoke/reset
- `P22-TC-011` Owner Mode comprehension
- `P22-TC-012` localization/RTL foundation
- `P22-TC-013` accessibility consumer gate
- `P22-TC-014` support-bundle privacy
- `P22-TC-015` non-technical tri-OS beta
- `P22-TC-016` uninstall/data-removal verification
- `P22-TC-017` claim-generation lint
- `P22-TC-018` consumer release certification

## Acceptance scenarios

- `P22-ACC-001` clean non-developer machine reaches first verified task
- `P22-ACC-002` one provider connects without terminal/manual runtime
- `P22-ACC-003` known broken sidecar is repaired and verified
- `P22-ACC-004` user exports and deletes selected data
- `P22-ACC-005` Owner Mode comprehension questions meet threshold
- `P22-ACC-006` uninstall leaves no undeclared process, secret, profile or cache

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- A clean supported machine reaches a verified first task without a developer toolchain.
- Simple Mode hides internal complexity while respecting explicit constraints.
- Hardware claims are measured on Windows, macOS and Linux.
- Owner Mode risk and current authority are understood by representative users.
- Common failures have understandable, actionable, verified recovery.
- Cost, provider, account and outbound data are visible.
- Export, deletion, revoke, repair, update, rollback and uninstall pass.
- Accessibility, localization foundation and support readiness pass.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker F. Continue the highest-priority dependency-satisfied P22 task.
```
