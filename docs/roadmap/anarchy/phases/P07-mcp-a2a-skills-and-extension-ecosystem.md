---
phase: P7
title: "MCP, A2A, skills, and extension ecosystem"
execution_view_status: READY_PARALLEL_P7_001
primary_workers: [H, I, B]
test_center_module: "Interoperability & Extensions"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P7 — MCP, A2A, skills, and extension ecosystem

## Purpose

This is the bounded execution packet for P7. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `READY_PARALLEL_P7_001`
- Primary workers: Worker H, Worker I, Worker B
- Test Center module: `Interoperability & Extensions`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P7-001` | MCP version adapter architecture | `P1-001` | Support current stable MCP and isolate upcoming/spec-draft changes behind adapters; pin negotiated versions. | Protocol upgrade cannot silently remove capabilities. |
| `P7-002` | MCP server descriptor and registry | `P1-005,P7-001` | Record publisher, digest, version, transport, tools, resources, prompts, roots, network, secrets, and retention. | Unregistered or changed server fails trust policy. |
| `P7-003` | MCP lifecycle manager | `P7-002,P1-004` | Install, enable, start, health-check, stop, update, revoke, and remove servers. | Lifecycle and process cleanup tests pass. |
| `P7-004` | MCP execution isolation | `P7-003` | Run untrusted servers in isolated workers; Owner Mode may opt into host execution with clear status. | Mode selection is explicit and auditable. |
| `P7-005` | A2A 1.0 protocol adapter | `P1-005` | Implement Agent Cards, discovery, task/messages/artifacts, version header, auth schemes, streaming, and async tasks. | Conformance fixtures pass for supported subset. |
| `P7-006` | A2A trust and delegation grants | `P7-005,P1-003` | Bind remote agent identity, task, inputs, outputs, network, secrets, deadline, and downstream delegation. | Remote agent cannot widen authority. |
| `P7-007` | Replace environment-selected A2A executable | `P7-006` | Change bridge to resolve a registered agent/worker descriptor instead of raw executable JSON. | Environment control alone cannot execute an arbitrary program. |
| `P7-008` | A2A evidence and reconciliation | `P7-006` | Validate artifacts, progress, cancellation, idempotency, and unknown outcomes. | Forged completion and duplicate effect fixtures fail. |
| `P7-009` | Skill and plugin manifest v2 | `P1-006` | Define signed publisher identity, code digest, permissions, compatibility, entry point, tests, and revocation. | Unsigned or modified production extension is rejected. |
| `P7-010` | Extension marketplace/local registry | `P7-009` | Build install, inspect, enable, update, disable, revoke, and trust UI. | User sees exact requested capabilities. |
| `P7-011` | Interop adversarial suite | `P7-003,P7-008,P7-010` | Test prompt injection, lookalike tools, signer substitution, confused deputy, replay, and cascading failure. | No unresolved critical/high finding. |
| `P7-012` | Interop operator documentation | `P7-011` | Document MCP/A2A versions, trust, isolation, Owner Mode, data retention, and revocation. | Docs match conformance and UI. |

## Test Center deliverables

- `P7-TC-001` MCP version negotiation
- `P7-TC-002` descriptor identity/digest tests
- `P7-TC-003` lifecycle and process cleanup
- `P7-TC-004` isolated versus host execution truth
- `P7-TC-005` A2A conformance
- `P7-TC-006` delegation-grant containment
- `P7-TC-007` environment-selected executable removal regression
- `P7-TC-008` forged completion/idempotency/reconciliation
- `P7-TC-009` signed extension manifest
- `P7-TC-010` install/update/revoke UX
- `P7-TC-011` interop adversarial suite
- `P7-TC-012` operator documentation scenario

## Acceptance scenarios

- `P7-ACC-001` unregistered MCP server is rejected
- `P7-ACC-002` changed server digest requires review
- `P7-ACC-003` remote agent cannot widen grant
- `P7-ACC-004` revoked extension stops loading
- `P7-ACC-005` malicious tool description cannot impersonate policy

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- MCP and A2A versions are pinned and negotiated.
- External servers/agents/extensions have trusted identities and scoped grants.
- Raw environment data cannot select an arbitrary A2A executable.
- Adversarial interoperability suite has no open critical/high issue.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker H. Continue the highest-priority dependency-satisfied P7 task.
```
