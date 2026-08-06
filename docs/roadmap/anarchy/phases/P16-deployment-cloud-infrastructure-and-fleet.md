---
phase: P16
title: "Deployment, cloud, infrastructure, and fleet"
execution_view_status: BLOCKED_BY_CONNECTORS_AND_APP_FACTORY
primary_workers: [H, I, J]
test_center_module: "Deployment & Fleet"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P16 — Deployment, cloud, infrastructure, and fleet

## Purpose

This is the bounded execution packet for P16. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_BY_CONNECTORS_AND_APP_FACTORY`
- Primary workers: Worker H, Worker I, Worker J
- Test Center module: `Deployment & Fleet`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P16-001` | Deployment target contracts | `P12-006,P13-012` | Environment, plan, apply, health, rollback schemas | Golden vectors pass across adapters. |
| `P16-002` | OCI/container pipeline | `P16-001` | Build, scan, SBOM, run, publish | Reproducible image fixture passes. |
| `P16-003` | Infrastructure-as-code adapters | `P16-001,P12-013` | Terraform/OpenTofu and one additional adapter | Plan/destroy/change parsing and policy tests pass. |
| `P16-004` | Cloud provider foundation | `P12-012,P16-001` | Account/resource/role session adapters | Sandbox accounts pass create/update/delete/reconcile. |
| `P16-005` | Preview environment service | `P13-012,P16-002,P16-004` | Ephemeral URL/data/expiry/teardown | Leak and orphan-resource tests pass. |
| `P16-006` | Database deployment and backup | `P12-011,P16-004` | Provision, migrate, backup, restore | Restore verification passes after injected failure. |
| `P16-007` | DNS/TLS and edge delivery | `P16-004` | DNS plan, certificate, CDN/cache adapters | Propagation/reconciliation and rollback tests pass. |
| `P16-008` | Cost/quota engine | `P12-013,P16-004` | Estimate, reserve, actual cost and halt | Budget overrun fixtures stop before new effects. |
| `P16-009` | Node identity and enrollment | `P12-001,P1-006` | Signed enrollment, capability manifest, revoke | Unknown/revoked nodes cannot receive work. |
| `P16-010` | Fleet scheduler | `P16-009,P6-011` | Platform/GPU/locality/data-boundary scheduling | Jobs route to compatible nodes and recover. |
| `P16-011` | Remote Owner Mode | `P15-009,P16-009,P12-013` | Broad/scoped remote grants and local kill | Disconnect/revoke/unknown-effect tests pass. |
| `P16-012` | Deployment/fleet benchmark | `P16-002` through `P16-011` | Preview→production→rollback and multi-node corpus | Reliability, cost, security and evidence targets pass. |

## Test Center deliverables

- `P16-TC-001` deployment-contract vectors
- `P16-TC-002` reproducible OCI build
- `P16-TC-003` IaC plan/destroy parsing
- `P16-TC-004` cloud sandbox-account fixtures
- `P16-TC-005` preview lifecycle and teardown
- `P16-TC-006` database backup/restore
- `P16-TC-007` DNS/TLS reconciliation
- `P16-TC-008` cost/quota halt
- `P16-TC-009` node enrollment/revocation
- `P16-TC-010` fleet scheduling compatibility
- `P16-TC-011` remote Owner Mode recovery
- `P16-TC-012` deployment/fleet benchmark

## Acceptance scenarios

- `P16-ACC-001` create preview, verify health, destroy without orphan
- `P16-ACC-002` parse and block unintended destroy
- `P16-ACC-003` restore database after injected migration failure
- `P16-ACC-004` revoke node and prevent further work
- `P16-ACC-005` hard budget stops before new paid effect

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
Take the repo. You are Worker H. Continue the highest-priority dependency-satisfied P16 task.
```
