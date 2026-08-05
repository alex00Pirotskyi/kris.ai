---
phase: P23
title: "Tool, Skill and Capability Operating System"
execution_view_status: BLOCKED_BY_CAPABILITY_PROVIDER_AND_SKILL_FOUNDATIONS
primary_workers: [H, G, B]
test_center_module: "Tools, Skills & Capabilities"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P23 — Tool, Skill and Capability Operating System

## Purpose

This is the bounded execution packet for P23. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_BY_CAPABILITY_PROVIDER_AND_SKILL_FOUNDATIONS`
- Primary workers: Worker H, Worker G, Worker B
- Test Center module: `Tools, Skills & Capabilities`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P23-001` | Approve execution ontology ADR | `P1-001,P7-009,P19-005` | Tool/capability/skill/recipe/plugin/connector/agent/workflow definitions | Every subsystem maps without overlap. |
| `P23-002` | Adopt Agent Skills compatibility profile | `P23-001` | Portable SKILL.md import/export, progressive disclosure and compatibility tests | Reference packages round-trip without Kristin lock-in. |
| `P23-003` | Define signed Skill Manifest v3 and lock | `P1-006,P23-002` | Digest tree, publisher, permissions, capabilities, dependencies, evals and revocation | Mutation, downgrade and signer-substitution tests fail. |
| `P23-004` | Define Capability Descriptor v4 | `P23-001,P11-002,P12-006,P21-004` | Extended semantics, effects, resources, transactions, health and quality | All built-in capability classes validate. |
| `P23-005` | Define Tool Contract Standard v1 | `P23-004,P8-003` | Shared action/effect/idempotency/cancel/reconcile/evidence contract | Dart and workers pass golden and fuzz vectors. |
| `P23-006` | Build capability graph and deterministic resolver | `P23-004,P23-005,P21-007` | Goal→skill→capability→tool/provider graph and route receipts | Explicit constraints and policy property tests pass. |
| `P23-007` | Implement token-efficient discovery | `P23-006,P18-009` | Progressive metadata retrieval and bounded model tool catalogs | Recall/precision and local-model context budgets pass. |
| `P23-008` | Implement skill parser and validator | `P23-002,P23-003` | YAML/Markdown/resources/scripts validator and safe path rules | Malformed, recursive and path-escape packages fail. |
| `P23-009` | Implement skill compiler IR | `P23-006,P23-008` | Deterministic DAG, grants, locks, checkpoints, takeover, verification and rollback | Same locked skill compiles reproducibly. |
| `P23-010` | Implement durable skill runtime | `P23-009,P6-011,P8-003` | Start/pause/resume/cancel/restart/migrate/reconcile | Crash and unknown-effect fixtures pass. |
| `P23-011` | Implement safe skill composition | `P23-009,P23-010` | Subskill schemas, budget, state, recursion and transaction rules | Cycle, confused-deputy and budget tests pass. |
| `P23-012` | Implement tool/skill health service | `P23-004,P19-010,P21-016` | Canaries, health states, last-known-good, disable and repair | Broken capability stops routing before user impact threshold. |
| `P23-013` | Implement multi-tool transaction and resource locks | `P23-005,P8-003` | Prepare/commit/compensate/reconcile and lock manager | Duplicate booking/send/deploy/edit fixtures produce no duplicate effects. |
| `P23-014` | Build Skill Studio basic | `P5-004,P23-008,P23-009` | Conversational creation, import, edit, simulate, install and export | User creates a private tested skill without editing raw files. |
| `P23-015` | Build Skill Studio advanced | `P23-014` | Visual DAG, permission, provider, test, version and manifest editors | Developer can diagnose compile/runtime failures. |
| `P23-016` | Implement verified-run-to-skill proposal | `P23-014,P23-010` | Parameterization, subskill discovery, fixture generation and human approval | Untrusted content cannot auto-install or publish. |
| `P23-017` | Implement permission and update-diff UX | `P23-003,P5-007` | Install/update capability, destination, credential and egress preview | New authority cannot activate silently. |
| `P23-018` | Build skill evaluation harness | `P23-010,P8-015` | Positive, negative, crash, provider, platform, cost, security and accessibility suites | Skill quality reports are reproducible. |
| `P23-019` | Build Gold Skill Pack — communication/travel | `P23-018,P12-014,P3-018` | Gmail/calendar and hotel/travel skills with fixtures | Real and fixture beta meets thresholds. |
| `P23-020` | Build Gold Skill Pack — coding/research | `P23-018,P13-014,P4-021` | App, repository, research and dataset skills | Supported recipes meet task and false-completion gates. |
| `P23-021` | Build Gold Skill Pack — content/computer/productivity | `P23-018,P14-014,P15-010` | Content, desktop and personal productivity skills | Tri-OS and artifact correctness gates pass. |
| `P23-022` | Build registry and marketplace governance | `P19-008,P23-003,P23-018` | Official/private/public registries, review, quality, revoke and rollback | Modified or revoked skills stop loading. |
| `P23-023` | Run tool/skill security assessment | `P23-011` through `P23-022` | Supply-chain, injection, confused-deputy and authority review | Zero unresolved critical/high findings. |
| `P23-024` | Tool/Skill/Capability OS release gate | `P23-001` through `P23-023` | Discovery, compilation, runtime, marketplace, Gold Skill and consumer permission evidence | Gate U passes on all mandatory desktop OSs and medium hardware. |

## Test Center deliverables

- `P23-TC-001` ontology consistency
- `P23-TC-002` portable Agent Skills round-trip
- `P23-TC-003` signed skill manifest/lock
- `P23-TC-004` capability descriptor validation
- `P23-TC-005` tool contract golden/fuzz
- `P23-TC-006` capability graph/resolver
- `P23-TC-007` token-efficient discovery benchmark
- `P23-TC-008` skill parser/path safety
- `P23-TC-009` deterministic compiler
- `P23-TC-010` durable runtime crash/restart
- `P23-TC-011` composition cycles/confused deputy
- `P23-TC-012` health and last-known-good
- `P23-TC-013` multi-tool transaction/locks
- `P23-TC-014` Skill Studio basic E2E
- `P23-TC-015` Skill Studio advanced
- `P23-TC-016` verified-run proposal safety
- `P23-TC-017` permission/update-diff UX
- `P23-TC-018` skill evaluation harness
- `P23-TC-019` communication/travel Gold Skills
- `P23-TC-020` coding/research Gold Skills
- `P23-TC-021` content/computer/productivity Gold Skills
- `P23-TC-022` registry/marketplace governance
- `P23-TC-023` security assessment regressions
- `P23-TC-024` Tool/Skill OS certification

## Acceptance scenarios

- `P23-ACC-001` portable skill imports/exports without lock-in
- `P23-ACC-002` skill cannot grant itself authority
- `P23-ACC-003` new permission in update remains disabled until approved
- `P23-ACC-004` crash during multi-tool booking/send/deploy does not duplicate effect
- `P23-ACC-005` user creates a private tested skill without editing files
- `P23-ACC-006` revoked skill stops routing

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- One ontology and registry covers all tools, capabilities, skills, recipes, connectors, plugins and agents.
- Portable Agent Skills packages import and export with progressive disclosure.
- Signed sidecars add authority and evidence without breaking portability.
- Local models discover a bounded, relevant tool set within context budgets.
- Skills compile deterministically into durable, resumable task graphs.
- Multi-tool transactions do not duplicate unknown external effects.
- Users can create, test, install, inspect, update, revoke and share skills.
- Gold Skills cover core consumer outcomes.
- Broken, malicious, changed or revoked skills stop routing.
- No skill can grant itself authority.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker H. Continue the highest-priority dependency-satisfied P23 task.
```
