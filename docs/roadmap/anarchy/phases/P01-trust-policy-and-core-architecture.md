---
phase: P1
title: "Trust, policy, and core architecture"
execution_view_status: DONE_LIVE_AUTHORITY
primary_workers: [A, B, I]
test_center_module: "Trust, Policy & IPC"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P1 — Trust, policy, and core architecture

## Purpose

This is the bounded execution packet for P1. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `DONE_LIVE_AUTHORITY`
- Primary workers: Worker A, Worker B, Worker I
- Test Center module: `Trust, Policy & IPC`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P1-001` | Approve runtime-boundary ADRs | `P0-008` | Define desktop, owner executor, automation host, research worker, sandbox worker, IPC, and storage boundaries. | ADRs resolve ownership and do not leave implementation-critical ambiguity. |
| `P1-002` | Define access profile v2 | `P1-001` | Create schema and domain model for chat, project, owner, owner_unattended, and isolated_untrusted modes. | Round-trip and invalid-policy tests pass in Dart and worker languages. |
| `P1-003` | Define capability grant v2 | `P1-001,P1-002` | Bind grants to run, task, actor, tool, paths, process, network, browser profile, secrets, budgets, expiry, and use count. | Worker rejects modified, expired, replayed, and wrong-run grants. |
| `P1-004` | Build deterministic policy engine | `P1-002,P1-003` | Implement mode resolution, organization/project/user overlays, and explicit widening rules. | Policy property tests prove deny-by-default and Owner Mode’s intended authority. |
| `P1-005` | Specify Signed Manifest v2 | `P0-002,P1-001` | Adopt Ed25519, RFC 8785 canonical JSON, external keyring, key IDs, intended use, expiry, trust domain, and revocation. | Language-neutral spec and negative vectors approved. |
| `P1-006` | Implement cross-language signing | `P1-005` | Implement Dart/Python signing and verification against shared golden vectors. | Both languages produce and verify identical vectors and reject mutations. |
| `P1-007` | Migrate or reject v1 envelopes | `P1-006` | Add explicit compatibility policy; v1 never authorizes production trust. | Downgrade and mixed-format tests pass. |
| `P1-008` | Design TUF update trust | `P1-005` | Define offline root, targets, snapshot, timestamp, delegations, thresholds, rotation, and recovery. | ADR and key ceremony runbook approved. |
| `P1-009` | Implement key storage and revocation | `P1-005` | Use OS keychain or external protected store; separate signing, API, browser, and secret-broker keys. | No private key is stored in repository or unencrypted settings. |
| `P1-010` | Create append-only signed audit checkpoints | `P1-006,P1-009` | Anchor audit heads with trusted keys and export verification receipts. | Tampering, truncation, reordering, and signer substitution are detected. |
| `P1-011` | Create threat model v2 | `P1-001,P1-004` | Map trust boundaries and OWASP agentic risks across model, tools, web, memory, MCP/A2A, terminal, and updater. | Every high-risk boundary has an owner and planned test. |
| `P1-012` | Create local authenticated IPC | `P1-001,P1-003` | Use named pipes/Unix sockets or loopback with mutual authentication, peer identity, request IDs, limits, and versioning. | Unprivileged unrelated local process cannot invoke a worker. |

## Test Center deliverables

- `P1-TC-001` access-profile round-trip and invalid-policy suite
- `P1-TC-002` capability-grant mutation, replay, expiry and wrong-run suite
- `P1-TC-003` deterministic policy property suite
- `P1-TC-004` Signed Manifest v2 cross-language vectors
- `P1-TC-005` downgrade and mixed-format rejection suite
- `P1-TC-006` key storage and revocation fixtures
- `P1-TC-007` audit tamper/truncation/reordering suite
- `P1-TC-008` local authenticated IPC adversarial suite
- `P1-TC-009` threat-model control coverage dashboard
- `P1-TC-010` Test Center trust certification panel

## Acceptance scenarios

- `P1-ACC-001` project profile denies unrelated absolute path
- `P1-ACC-002` owner profile authorizes intended broad path only after explicit enablement
- `P1-ACC-003` modified grant is rejected by worker
- `P1-ACC-004` unrelated local process cannot call privileged IPC
- `P1-ACC-005` audit export detects one changed event

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- One policy model covers safe, project, Owner, unattended, and isolated modes.
- One Signed Manifest v2 passes cross-language positive and adversarial vectors.
- Trust roots are external to envelopes.
- Local IPC rejects unauthorized callers.
- Threat model and TUF design are approved.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker A. Continue the highest-priority dependency-satisfied P1 task.
```
