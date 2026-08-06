---
phase: P8
title: "Reliability, security, observability, and evaluation"
execution_view_status: READY_PARALLEL_SECURITY_WORK
primary_workers: [I, B]
test_center_module: "Reliability, Security & Diagnostics"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P8 — Reliability, security, observability, and evaluation

## Purpose

This is the bounded execution packet for P8. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `READY_PARALLEL_SECURITY_WORK`
- Primary workers: Worker I, Worker B
- Test Center module: `Reliability, Security & Diagnostics`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P8-001` | Formal test hierarchy | `P0-007` | Separate architecture lint, unit, component, integration, platform, adversarial, benchmark, and release tests. | Reports identify assurance level. |
| `P8-002` | Workflow chaos expansion | `P2-010,P4-012` | Inject disk full, corruption, WAL loss, clock jumps, duplicate completion, cancellation races, and interrupted migrations. | Every case recovers or becomes explicit unknown. |
| `P8-003` | External-effect state machine | `P1-003` | Implement planned, authorized, started, observed, committed, compensated, unknown, and reconciliation-required. | Unknown external effects are never blindly retried. |
| `P8-004` | Terminal fault-injection suite | `P2-006` | Test hung prompts, binary output, output floods, fork bombs, process escapes, and abrupt worker death. | Kill and recovery targets pass. |
| `P8-005` | Browser fault-injection suite | `P3-017` | Test navigation races, stale DOM, popups, downloads, crashes, storage leaks, and worker death. | No false completion or profile leakage. |
| `P8-006` | Research adversarial suite | `P4-021,P6-006` | Test poisoned pages, malicious metadata, SSRF, rebinding, giant pages, extraction traps, and citation drift. | No unauthorized effect or unsupported citation. |
| `P8-007` | Secret scanning v2 | `P0-010` | Add Git-history scan, entropy, provider detectors, archives, binary metadata, pre-commit, CI, and safe fingerprints. | Seeded secrets are detected without printing values. |
| `P8-008` | Dependency and license policy | `P0-004` | Add vulnerability, lockfile, provenance, license, and abandoned-package gates. | Unapproved dependency cannot reach release. |
| `P8-009` | OpenTelemetry instrumentation | `P1-001` | Add correlated traces, metrics, and logs for model, policy, tools, terminal, browser, web, and update. | One run is traceable end to end without project content by default. |
| `P8-010` | Privacy and telemetry controls | `P8-009` | Make telemetry opt-in, redact content, expose preview/export/delete, and document retention. | Privacy tests and data inventory pass. |
| `P8-011` | Performance and soak suite | `P5-013,P8-009` | Measure startup, memory, event throughput, large repos, long terminal/browser sessions, search, datasets, and 24h runs. | Budgets and leak thresholds pass. |
| `P8-012` | Agentic security mapping | `P1-011` | Map tests and controls to OWASP Agentic Top 10 and AI Agent Security guidance. | Every applicable risk has evidence or explicit accepted gap. |
| `P8-013` | NIST AI RMF evidence map | `P6-015,P8-012` | Map Govern, Map, Measure, Manage outcomes to product artifacts and owners. | Release package includes current risk register and measurement report. |
| `P8-014` | Independent penetration test | `P2-013,P3-017,P7-011` | Commission review of full-host execution, browser, IPC, signing, updater, MCP/A2A, and prompt injection. | No unresolved critical/high finding. |
| `P8-015` | Failure replay corpus | `P8-002,P8-004,P8-005,P8-006` | Minimize every production failure into a permanent deterministic fixture. | Regression replay runs in release CI. |

## Test Center deliverables

- `P8-TC-001` formal hierarchy enforcement
- `P8-TC-002` workflow chaos suite
- `P8-TC-003` external-effect state-machine tests
- `P8-TC-004` terminal fault injection
- `P8-TC-005` browser fault injection
- `P8-TC-006` research adversarial suite
- `P8-TC-007` secret-scan seeded fixtures
- `P8-TC-008` dependency/license policy tests
- `P8-TC-009` end-to-end trace correlation
- `P8-TC-010` privacy/telemetry controls
- `P8-TC-011` performance and 24h soak
- `P8-TC-012` agentic-security evidence map
- `P8-TC-013` NIST evidence map
- `P8-TC-014` penetration-test finding regressions
- `P8-TC-015` permanent failure replay corpus

## Acceptance scenarios

- `P8-ACC-001` crash after external commit becomes reconciled or unknown
- `P8-ACC-002` disk full during object write preserves prior authority
- `P8-ACC-003` seeded secret detected without printing value
- `P8-ACC-004` one run is traceable end to end without content telemetry
- `P8-ACC-005` production failure fixture remains permanently executable

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Assurance levels are reported separately.
- Chaos, browser, terminal, research, prompt-injection, and replay suites pass.
- OpenTelemetry and privacy controls are production ready.
- Independent penetration test has no unresolved critical/high issue.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker I. Continue the highest-priority dependency-satisfied P8 task.
```
