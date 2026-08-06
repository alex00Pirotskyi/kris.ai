---
phase: P9
title: "Release engineering, installers, signing, and updates"
execution_view_status: BLOCKED_BY_P8_AND_PLATFORM_ARTIFACTS
primary_workers: [I, J, B]
test_center_module: "Release & Update Certification"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P9 — Release engineering, installers, signing, and updates

## Purpose

This is the bounded execution packet for P9. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_BY_P8_AND_PLATFORM_ARTIFACTS`
- Primary workers: Worker I, Worker J, Worker B
- Test Center module: `Release & Update Certification`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P9-001` | Redesign CI pipeline | `P0-003,P8-001` | Split PR, nightly, platform, adversarial, benchmark, and release workflows with artifact retention. | Failures do not hide downstream evidence and required gates are enforced. |
| `P9-002` | Extend generated-state policy | `P3-001,P4-011` | Exclude Playwright, Node, browser profiles, traces, downloads, dataset intermediates, and native build state. | Validator, scanner, and packager use one tested policy. |
| `P9-003` | Reproducible dependency and browser lock | `P3-001,P8-008` | Lock Flutter/Dart, Python, automation host, browser binaries, native tools, and checksums. | Clean builders resolve identical inputs. |
| `P9-004` | SBOM and provenance | `P9-001,P9-003` | Generate source/build SBOMs, GitHub artifact attestations, checksums, and SLSA-aligned provenance. | Consumer can verify artifact to source/workflow. |
| `P9-005` | Windows installer and signing | `P9-003` | Build installer, code sign, timestamp, verify, install, upgrade, rollback, and uninstall on clean images. | All Windows release tests pass. |
| `P9-006` | macOS signing and notarization | `P9-003` | Sign nested binaries/helpers, hardened runtime, notarize, staple, verify, install, upgrade, rollback, uninstall. | All macOS release tests pass. |
| `P9-007` | Linux packages | `P9-003` | Produce supported signed package/bundle, dependency declarations, install/upgrade/rollback/uninstall tests. | Supported distributions pass. |
| `P9-008` | TUF repository and channels | `P1-008,P9-004` | Create offline root, delegated nightly/alpha/beta/stable/emergency targets, snapshot, timestamp, and publication. | Metadata expiry, rollback, freeze, mix-and-match, and compromise tests pass. |
| `P9-009` | Updater and rollback engine | `P9-008` | Download, verify, stage, stop workers, backup state, install, health-check, rollback, and report. | Injected failure at every stage returns to working version. |
| `P9-010` | Database upgrade compatibility | `P8-002,P9-009` | Test N-2 upgrade, N-1 rollback where supported, forward-only declarations, and backups. | No unsupported migration path is offered. |
| `P9-011` | Reproducible unsigned payload comparison | `P9-003,P9-004` | Build twice on clean builders and compare unsigned payloads; isolate intended signature/timestamp differences. | Payloads match or documented nondeterminism blocks release. |
| `P9-012` | Release command and evidence bundle | `P9-001,P9-004` | Create one release orchestrator that refuses missing gates and exports reports, SBOM, provenance, hashes, and notes. | A release cannot be labeled compiled/stable without all evidence. |
| `P9-013` | Support, privacy, license, and EULA documents | `P5-011,P8-010` | Finalize support matrix, privacy, retention, third-party notices, license, terms, and Owner Mode disclosure. | Human legal review recorded. |
| `P9-014` | Release website and verification guide | `P9-004,P9-012` | Publish checksums, signatures, provenance verification, install, update, rollback, and known limits. | Fresh user can verify an artifact independently. |
| `P9-015` | Key compromise drill | `P9-008,P9-012` | Simulate targets/timestamp/root compromise, rotate/revoke, issue emergency metadata, and block old artifacts. | Runbook succeeds from offline root. |
| `P9-016` | Bad update drill | `P9-009` | Publish faulty beta fixture, detect, halt rollout, rollback, and preserve state. | Staged rollout stops automatically. |

## Test Center deliverables

- `P9-TC-001` CI lane and artifact-retention verification
- `P9-TC-002` generated-state packaging policy
- `P9-TC-003` reproducible dependency/browser locks
- `P9-TC-004` SBOM/provenance verification
- `P9-TC-005` Windows install/update/rollback/uninstall
- `P9-TC-006` macOS sign/notarize/install/update/rollback
- `P9-TC-007` Linux package install/update/rollback
- `P9-TC-008` TUF attack suite
- `P9-TC-009` updater injected-failure matrix
- `P9-TC-010` state/database compatibility
- `P9-TC-011` two-clean-build payload comparison
- `P9-TC-012` release-command refusal tests
- `P9-TC-013` document/legal checklist coverage
- `P9-TC-014` consumer artifact verification scenario
- `P9-TC-015` key compromise drill
- `P9-TC-016` bad update drill

## Acceptance scenarios

- Add one criterion-scoped acceptance scenario for every user-visible outcome.

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Signed installers/packages pass clean-machine install, upgrade, rollback, and uninstall.
- TUF metadata and updater tests pass.
- SBOM, SLSA-aligned provenance, attestations, hashes, and verification guide exist.
- Release command refuses incomplete evidence.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker I. Continue the highest-priority dependency-satisfied P9 task.
```
