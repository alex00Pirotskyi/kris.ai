---
phase: P0
title: "Stabilize, contain, and establish truth"
execution_view_status: DONE_LIVE_AUTHORITY
primary_workers: [J, I, B]
test_center_module: "Repository Truth"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P0 — Stabilize, contain, and establish truth

## Purpose

This is the bounded execution packet for P0. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `DONE_LIVE_AUTHORITY`
- Primary workers: Worker J, Worker I, Worker B
- Test Center module: `Repository Truth`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P0-001` | Capture reproducible baseline | `none` | Inventory tree, schemas, tool registry, tests, CI, current failures, and hashes; write `release/evidence/baseline/`. | A clean checkout can reproduce the baseline report and every unavailable gate is explicitly marked. |
| `P0-002` | Disable insecure v1 trust decisions | `P0-001` | Remove or hard-disable authorization and update decisions that use `tool/interoperability_v19.py` envelope-supplied HMAC material. | Forgery test is rejected; no runtime path accepts v1 envelope trust. |
| `P0-003` | Green the current three-OS CI | `P0-001` | Fix formatting and any downstream analyzer, test, validator, and native-build failures. | Ubuntu, Windows, and macOS reach every workflow step and pass. |
| `P0-004` | Pin toolchains and GitHub Actions | `P0-003` | Pin Flutter/Dart, Python, Actions by commit SHA, and cache keys; record versions in a toolchain manifest. | Two CI reruns use identical declared inputs. |
| `P0-005` | Rewrite security and support policy | `P0-001,P0-002` | Update supported version, platform matrix, Owner Mode intent, sandbox truth, interop freeze, and disclosure procedure. | README, SECURITY, UI, and release classification agree. |
| `P0-006` | Protect repository governance | `P0-003` | Add CODEOWNERS, branch protection requirements, PR template, security review labels, and merge policy. | Protected main cannot merge without required checks/review. |
| `P0-007` | Split source lint from behavioral assurance | `P0-001` | Reclassify `system_test.py` and validator token checks; create separate report categories. | Dashboard never reports source-marker checks as behavioral proof. |
| `P0-008` | Create roadmap control files | `P0-001` | Add STATUS, ADR, risk, metric, prompt, evidence, and handoff structure. | A new AI session can find the next ready task without oral context. |
| `P0-009` | Establish initial benchmark corpus | `P0-001` | Record current results for coding, analysis, path safety, crash recovery, browser-absent, and research tasks. | Baseline is versioned and reproducible. |
| `P0-010` | Remove committed generated state | `P0-001` | Apply source-tree policy, remove caches such as `__pycache__`, and update ignore rules. | Clean checkout stays clean after standard tests except declared reports. |

## Test Center deliverables

- `P0-TC-001` Test hierarchy and result taxonomy
- `P0-TC-002` Test registry schema and validator
- `P0-TC-003` Baseline runner and machine-readable report
- `P0-TC-004` Evidence manifest and content-addressed output storage
- `P0-TC-005` Source-marker versus behavioral-proof separation
- `P0-TC-006` Generated-state cleanliness checks
- `P0-TC-007` Three-OS CI result aggregation
- `P0-TC-008` Regression-corpus directory and naming rules
- `P0-TC-009` Roadmap-task-to-test coverage report
- `P0-TC-010` Minimal Verification Center status screen or CLI report
- `P0-TC-011` Project Test Profile schema and resolver
- `P0-TC-012` Non-mutating development fast-check runner
- `P0-TC-013` Change-impact report and affected-test selector
- `P0-TC-014` Configurable pre-commit/pre-push verification policy
- `P0-TC-015` Development Verification CLI and initial Flutter profile

## Acceptance scenarios

- `P0-ACC-001` clean checkout reproduces baseline report
- `P0-ACC-002` test report distinguishes static checks from behavior
- `P0-ACC-003` repeated CI inputs produce equivalent declared environment
- `P0-ACC-004` generated files do not dirty the source tree
- `P0-ACC-005` insecure v1 trust fixture is rejected
- `P0-ACC-006` changing a Flutter source file selects and runs affected fast checks
- `P0-ACC-007` required pre-commit verification blocks a known failing test
- `P0-ACC-008` automatic verification does not modify source or dependency locks

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Current trust flaw is disabled.
- Current three-platform CI is green from formatting through native build.
- Toolchains and Actions are pinned.
- Security documentation is accurate.
- Roadmap status/evidence files exist.
- Baseline benchmark is reproducible.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker J. Continue the highest-priority dependency-satisfied P0 task.
```
