---
phase: P10
title: "Core alpha, beta, release candidate, and integration checkpoint"
execution_view_status: BLOCKED_RELEASE_CHECKPOINT
primary_workers: [I, J, B]
test_center_module: "Core Release Readiness"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P10 — Core alpha, beta, release candidate, and integration checkpoint

## Purpose

This is the bounded execution packet for P10. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_RELEASE_CHECKPOINT`
- Primary workers: Worker I, Worker J, Worker B
- Test Center module: `Core Release Readiness`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P10-001` | Tri-platform internal alpha | `P2-013,P3-017,P4-021,P5-014,P6-015` | Ship equal Windows, macOS, and Linux internal builds with Owner Mode, terminal, browser, research, and data; capture failures. | Every mandatory desktop OS is represented, no P0 issue remains, and the replay corpus grows per platform. |
| `P10-002` | Tri-platform private beta | `P9-005,P9-006,P9-007,P9-009,P10-001` | Equal Windows, macOS, and Linux opt-in cohorts, staged updates, support intake, privacy telemetry, and weekly quality review. | SLOs and update targets hold independently on all three desktop OSs. |
| `P10-003` | External security audit closeout | `P8-014,P10-002` | Fix audit findings, add regressions, and publish scope/summary. | Zero unresolved critical/high. |
| `P10-004` | Release candidate freeze | `P10-003` | Feature freeze, exact versions, docs, translations, support, and release evidence. | RC artifact is immutable except blocker fixes. |
| `P10-005` | Thirty-day synchronized core RC soak | `P10-004` | Run continuous Windows, macOS, and Linux long-session, update, rollback, benchmark, and support monitoring. | Crash, quality, security, and parity thresholds pass independently on every mandatory desktop OS. |
| `P10-006` | Incident-response exercises | `P9-015,P9-016,P10-004` | Exercise leaked key, malicious extension, browser profile leak, sandbox escape, data corruption, and bad model. | Owners execute runbooks successfully. |
| `P10-007` | Core integration go/no-go review | `P10-005,P10-006` | Review every gate, accepted risk, cross-platform parity, evidence, support, and rollback. | Signed decision includes Windows, macOS, and Linux; no mandatory desktop OS is removed from the core integration scope. |
| `P10-008` | Staged core preview rollout | `P10-007` | Release internal→1%→5%→25%→50%→100% with automatic halt criteria. | No halt threshold is breached. |
| `P10-009` | Post-preview operations | `P10-008` | Monthly dependency/model review, quarterly drills, benchmark trend, vulnerability response, and deprecation policy. | Operational calendar has owners and evidence. |
| `P10-010` | Federated ecosystem checkpoint | `P7-011,P10-009` | Promote MCP/A2A/plugins only after dedicated soak and revocation testing. | Interop is independently gated from core GA. |

## Test Center deliverables

- `P10-TC-001` internal-alpha acceptance bundle
- `P10-TC-002` private-beta SLO dashboard
- `P10-TC-003` security-audit closeout regressions
- `P10-TC-004` immutable RC manifest
- `P10-TC-005` thirty-day soak aggregation
- `P10-TC-006` incident-response exercise runner
- `P10-TC-007` signed go/no-go report
- `P10-TC-008` staged-rollout halt criteria tests
- `P10-TC-009` operational calendar verification
- `P10-TC-010` federated ecosystem checkpoint

## Acceptance scenarios

- Add one criterion-scoped acceptance scenario for every user-visible outcome.

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Private beta and RC soak meet SLOs.
- Security and incident exercises pass.
- The core preview includes Windows, macOS, and Linux; each claimed mode is enabled only where its gate passed, and unresolved parity gaps remain release blockers for P20.
- Staged rollout and automatic halt/rollback are operational.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker I. Continue the highest-priority dependency-satisfied P10 task.
```
