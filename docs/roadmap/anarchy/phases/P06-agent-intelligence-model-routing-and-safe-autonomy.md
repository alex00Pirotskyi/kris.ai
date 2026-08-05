---
phase: P6
title: "Agent intelligence, model routing, and safe autonomy"
execution_view_status: READY_PARALLEL_P6_001
primary_workers: [G, B]
test_center_module: "Agent Quality & Model Routing"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P6 — Agent intelligence, model routing, and safe autonomy

## Purpose

This is the bounded execution packet for P6. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `READY_PARALLEL_P6_001`
- Primary workers: Worker G, Worker B
- Test Center module: `Agent Quality & Model Routing`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P6-001` | Model registry v2 | `P1-001` | Record provider/model identity, limits, tool profile, data boundary, cost, benchmark, and approved task classes. | Unknown models start evaluation-only. |
| `P6-002` | Role-based model routing | `P6-001` | Separate planner, executor, verifier, browser observer, extractor, and reviewer roles. | Routing decisions are durable and policy constrained. |
| `P6-003` | Planner/executor/verifier separation | `P6-002,P1-004` | Prevent executor from granting scope or self-certifying acceptance criteria. | Adversarial model cannot convert prose into authority. |
| `P6-004` | Unified action protocol v3 | `P1-003` | Add terminal, browser, research, data, user takeover, wait, delegate, complete, and fail decisions. | Cross-provider golden and fuzz tests pass. |
| `P6-005` | Context provenance labels | `P6-003` | Label user, system, project, web, memory, terminal, MCP, A2A, and tool output. | Injection text cannot impersonate system authority. |
| `P6-006` | Prompt-injection containment | `P6-005` | Add untrusted-content wrappers, tool-policy separation, destination checks, and exfiltration controls. | Direct/indirect injection corpus has zero unauthorized effects. |
| `P6-007` | Browser planning policy | `P3-010,P6-004` | Require observe-action-verify, bounded retries, takeover, and stale-target handling. | Dynamic-page fixtures converge without blind clicking. |
| `P6-008` | Terminal planning policy | `P2-006,P6-004` | Distinguish finite/interactive/background commands, readiness, destructive scope, and recovery. | Agent stops loops and verifies command outcomes. |
| `P6-009` | Research answer policy | `P4-010,P6-005` | Require fetched evidence, citation coverage, freshness, disagreement, and source type. | Snippet-only or uncited claims fail verification. |
| `P6-010` | Memory admission v2 | `P6-005` | Quarantine failed/adversarial runs, preserve provenance, add expiry and user pinning. | Poisoned memory does not enter normal context. |
| `P6-011` | Long-running task handles | `P1-012,P6-004` | Support durable wait, resume, polling, mid-flight input, pause, and cancellation. | Desktop restart can resume supported tasks. |
| `P6-012` | Strategy escalation and convergence | `P6-003` | Use semantic progress, repeated-outcome detection, split, replan, stronger model, user takeover, or fail. | Long tasks do not loop indefinitely. |
| `P6-013` | Independent acceptance engine | `P6-003` | Map every criterion to current objective evidence and validator. | Generic evidence cannot satisfy unrelated criteria. |
| `P6-014` | Model compatibility test matrix | `P6-001,P6-004` | Run every supported model through protocol, coding, browser, research, and safety suites. | Support matrix is generated from results. |
| `P6-015` | Agent benchmark dashboard | `P6-013,P6-014` | Report task success, false completion, unauthorized attempts/effects, cost, latency, and recovery. | Release comparison is reproducible and signed. |

## Test Center deliverables

- `P6-TC-001` model registry validation
- `P6-TC-002` role-routing determinism
- `P6-TC-003` planner/executor/verifier separation
- `P6-TC-004` action-protocol golden/fuzz suite
- `P6-TC-005` context provenance labels
- `P6-TC-006` prompt-injection containment corpus
- `P6-TC-007` browser planning convergence
- `P6-TC-008` terminal planning convergence
- `P6-TC-009` research-answer citation policy
- `P6-TC-010` memory-admission poisoning tests
- `P6-TC-011` durable wait/resume/cancel tests
- `P6-TC-012` loop detection and escalation
- `P6-TC-013` criterion-scoped acceptance engine
- `P6-TC-014` model compatibility matrix
- `P6-TC-015` benchmark dashboard

## Acceptance scenarios

- `P6-ACC-001` malicious README cannot widen authority
- `P6-ACC-002` web page instruction remains untrusted
- `P6-ACC-003` executor cannot certify unrelated acceptance criterion
- `P6-ACC-004` unsupported model begins evaluation-only
- `P6-ACC-005` repeated no-progress outcomes trigger replan or fail
- `P6-ACC-006` desktop restart resumes supported durable task
- `P6-ACC-007` local-only routing produces zero external dispatches

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Planner, executor, policy, and verifier responsibilities are separate.
- Browser, terminal, research, and user takeover are typed decisions.
- Prompt injection cannot grant authority or exfiltrate through tools.
- Every supported model has a measured compatibility profile.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker G. Continue the highest-priority dependency-satisfied P6 task.
```
