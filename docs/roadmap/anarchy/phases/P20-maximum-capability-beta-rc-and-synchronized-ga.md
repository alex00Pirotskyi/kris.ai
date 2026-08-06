---
phase: P20
title: "Maximum-capability beta, RC, and synchronized GA"
execution_view_status: FINAL_AGGREGATION_BLOCKED
primary_workers: [J, I, B]
test_center_module: "Maximum-Capability Certification"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P20 — Maximum-capability beta, RC, and synchronized GA

## Purpose

This is the bounded execution packet for P20. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `FINAL_AGGREGATION_BLOCKED`
- Primary workers: Worker J, Worker I, Worker B
- Test Center module: `Maximum-Capability Certification`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P20-001` | Capability freeze and inventory | `P11-015,P12-014,P13-014,P14-014,P15-010,P16-012,P17-010,P18-011,P19-010,P21-024,P22-018,P23-024,P24-012` | Generated support matrix and exact exclusions, including provider/API/browser/local route, consumer experience, tool/skill/capability, roadmap-integrity, and no-SQL storage evidence | No claimed capability, provider route, Gold Skill, consumer promise, or platform behavior lacks evidence. |
| `P20-002` | Tri-platform private beta | `P20-001,P9-005,P9-006,P9-007` | Equal Windows/macOS/Linux cohort and support | SLOs hold independently on each OS. |
| `P20-003` | Mobile/web/headless beta | `P19-001,P19-002,P19-003,P19-004` | Companion/node cohort | Capability truth and remote revoke SLOs hold. |
| `P20-004` | Full external security assessment | `P20-002,P20-003,P8-014` | Owner, credentials, connectors, desktop, content, cloud, fleet audit | Zero unresolved critical/high findings. |
| `P20-005` | Cross-platform parity closeout | `P20-002` | Per-capability parity report | No mandatory desktop capability is missing or silently degraded. |
| `P20-006` | Maximum-capability RC freeze | `P20-004,P20-005` | Immutable versions, models, connectors, recipes, docs | Only blocker fixes may enter. |
| `P20-007` | Thirty-day synchronized RC soak | `P20-006` | Continuous tri-OS, mobile/web, node, update and benchmark evidence | Every mandatory SLO passes per platform. |
| `P20-008` | Disaster and compromise drills | `P20-006` | Key, connector, model, plugin, cloud, profile, node, data and bad-update drills | Runbooks succeed and evidence is retained. |
| `P20-009` | Final legal/privacy/accessibility/support closeout | `P20-007` | Human approvals and support readiness | Required sign-offs are recorded. |
| `P20-010` | Maximum-capability GA decision | `P20-007,P20-008,P20-009` | Signed owner/release-auditor decision | Windows, macOS, and Linux all pass; no partial desktop GA. |
| `P20-011` | Staged synchronized rollout | `P20-010` | Platform-balanced cohorts and automatic halt | Any platform halt pauses the common rollout. |
| `P20-012` | Continuous capability evolution | `P20-011` | Monthly provider/platform/model review and quarterly drills | New capability enters only through descriptor, tests, and evidence. |

## Test Center deliverables

- `P20-TC-001` capability/evidence freeze
- `P20-TC-002` private-beta tri-OS dashboard
- `P20-TC-003` companion/headless beta dashboard
- `P20-TC-004` external-security finding closure
- `P20-TC-005` cross-platform parity report
- `P20-TC-006` immutable RC certification manifest
- `P20-TC-007` thirty-day synchronized soak
- `P20-TC-008` disaster/compromise drills
- `P20-TC-009` legal/privacy/accessibility/support closeout
- `P20-TC-010` signed GA decision
- `P20-TC-011` staged global halt verification
- `P20-TC-012` continuous revalidation schedule

## Acceptance scenarios

- Add one criterion-scoped acceptance scenario for every user-visible outcome.

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Windows, macOS, and Linux pass the same applicable capability and release gates.
- Owner Mode, credentials, connectors, application generation, content manufacturing, native automation, deployment/fleet, realtime chat, local models, web/mobile companions, ecosystem extensions, Gold Skills, Skill Studio, consumer onboarding, repair, support, and the no-SQL local authority have production evidence.
- All artifacts are signed, installable, updateable, rollbackable, attributable, and verified on the declared minimum and recommended hardware profiles.
- Final product claims are generated from the capability registry, skill registry, roadmap manifest, and evidence store.
- A representative non-technical user can complete primary workflows in Simple Mode without viewing logs, schemas, terminals, provider internals, or implementation architecture.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker J. Continue the highest-priority dependency-satisfied P20 task.
```
