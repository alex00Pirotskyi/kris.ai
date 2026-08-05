---
phase: P12
title: "Identity, credentials, and universal connectors"
execution_view_status: BLOCKED_BY_P11_IDENTITY_FOUNDATIONS
primary_workers: [H, G, I]
test_center_module: "Accounts, Credentials & Connectors"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P12 — Identity, credentials, and universal connectors

## Purpose

This is the bounded execution packet for P12. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_BY_P11_IDENTITY_FOUNDATIONS`
- Primary workers: Worker H, Worker G, Worker I
- Test Center module: `Accounts, Credentials & Connectors`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P12-001` | Identity domain v3 | `P1-005,P11-002` | Human, node, account, publisher, model, connector, signer identities | Identity substitution and revocation fixtures pass. |
| `P12-002` | OS-native credential vault adapters | `P1-009,P11-003,P11-004,P11-005` | Windows DPAPI/Credential, macOS Keychain, Linux Secret Service adapters | Secret CRUD, locked vault, migration, and redaction tests pass. |
| `P12-003` | Credential lease service | `P12-001,P12-002,P1-003` | Short-lived operation-bound handles | Wrong run/destination/scope/use/expiry is rejected. |
| `P12-004` | Owner break-glass reveal | `P12-002,P2-001` | Local interactive reauth flow | Value never reaches model/log/telemetry and unattended calls fail. |
| `P12-005` | OAuth account connection framework | `P12-003` | PKCE, device, service account, refresh, revoke, multi-account | Provider fixtures cover mix-up, redirect, state, rotation, expiry. |
| `P12-006` | Connector IR and manifest v2 | `P1-006,P12-001` | Signed schema and registry | Modified or untrusted connector fails registration. |
| `P12-007` | OpenAPI 3.x importer | `P12-006,P12-005` | 3.0/3.1/3.2 parsing, generated operations and fixtures | Reference, auth, callback, upload, and malformed specs pass. |
| `P12-008` | GraphQL connector | `P12-006,P12-005` | Schema import, approved operations, limits | Query/mutation, custom scalar, complexity and auth fixtures pass. |
| `P12-009` | gRPC/Protobuf connector | `P12-006,P12-005` | Descriptor/reflection import, unary/streaming | Deadlines, metadata, status, and binary artifacts pass. |
| `P12-010` | Generic protocol adapters | `P12-006` | JSON-RPC, SOAP/WSDL, WebSocket, SSE, webhook, SFTP/SSH baseline | Shared reliability and security fixtures pass. |
| `P12-011` | Database connector foundation | `P12-003,P12-006` | SQL introspection, typed query, transaction and migration contracts | PostgreSQL/MySQL/SQLite/SQL Server fixtures pass. |
| `P12-012` | Connector SDK and conformance kit | `P12-007,P12-008,P12-009,P12-010` | Scaffolder, mock server, record/replay, sign/package | A third-party sample connector passes without core changes. |
| `P12-013` | Transaction policy service | `P12-003,P1-004` | Publish/send/purchase/deploy/delete policy | Limits, step-up, idempotency and reconciliation tests pass. |
| `P12-014` | Connector workspace UI | `P12-005,P12-012` | Accounts, scopes, operations, health, logs, revoke | User can inspect exact account and permission for every call. |

## Test Center deliverables

- `P12-TC-001` identity substitution/revocation
- `P12-TC-002` OS-native vault adapter matrix
- `P12-TC-003` credential-lease boundary tests
- `P12-TC-004` break-glass reveal isolation
- `P12-TC-005` OAuth attack and lifecycle suite
- `P12-TC-006` signed connector registry
- `P12-TC-007` OpenAPI importer corpus
- `P12-TC-008` GraphQL limits/auth suite
- `P12-TC-009` gRPC unary/streaming suite
- `P12-TC-010` generic protocol adapters
- `P12-TC-011` database connector transactions/migrations
- `P12-TC-012` third-party SDK conformance
- `P12-TC-013` consequential transaction policy
- `P12-TC-014` connector workspace acceptance

## Acceptance scenarios

- `P12-ACC-001` use credential without exposing value to model/log
- `P12-ACC-002` wrong account/destination lease is rejected
- `P12-ACC-003` OAuth mix-up/replay/redirect attacks fail
- `P12-ACC-004` timeout-after-commit reconciles provider state
- `P12-ACC-005` user can inspect exact account, scopes and last use

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Credentials are used through leases on all three desktop OSs.
- OpenAPI, GraphQL, gRPC, generic HTTP/webhook, and SQL connectors work.
- One external connector can be built and signed without coordinator modification.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker H. Continue the highest-priority dependency-satisfied P12 task.
```
