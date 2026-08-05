---
phase: P11
title: "Omni-platform native parity and desktop control"
execution_view_status: BLOCKED_BY_P2_004_AND_NATIVE_ADRS
primary_workers: [E, I, B]
test_center_module: "Native Platform & Isolation"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P11 — Omni-platform native parity and desktop control

## Purpose

This is the bounded execution packet for P11. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_BY_P2_004_AND_NATIVE_ADRS`
- Primary workers: Worker E, Worker I, Worker B
- Test Center module: `Native Platform & Isolation`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P11-001` | Approve omni-platform ADR set | `P1-001,P2-004` | ADRs for native hosts, platform adapters, parity semantics, mobile/web truth, architecture matrix | No implementation-critical ambiguity remains and no mandatory desktop OS is deferred. |
| `P11-002` | Create platform support manifest | `P11-001` | Schema, generator, UI, release integration | Manifest is generated from tests for Windows, macOS, and Linux. |
| `P11-003` | Implement Windows native host v1 | `P1-012,P11-001` | ConPTY, Job Objects, UIA, credential, window, service, screen baseline | Windows conformance and hostile lifecycle fixtures pass. |
| `P11-004` | Implement macOS native host v1 | `P1-012,P11-001` | PTY, process lifecycle, AX, Keychain, NSWorkspace, TCC baseline | Signed helper passes macOS fixtures and consent recovery. |
| `P11-005` | Implement Linux native host v1 | `P1-012,P11-001` | PTY, cgroup/systemd, AT-SPI, portals, Secret Service baseline | GNOME/KDE and Wayland/X11 declared fixtures pass. |
| `P11-006` | Shared native conformance runner | `P11-003,P11-004,P11-005` | One suite against all platform adapters | Semantic result and error compatibility report is green. |
| `P11-007` | Native desktop observation v2 | `P11-006` | Window/accessibility/screen observations and hashes | Deterministic fixture observations pass on all three. |
| `P11-008` | Native desktop action v2 | `P11-007` | Structured actions plus fallback ladder | Actions verify postconditions and reject stale targets. |
| `P11-009` | Peripheral/device foundation | `P11-006` | Printers, scanner/camera/mic/device inventory contracts | Permission, unplug, and data-direction fixtures pass. |
| `P11-010` | Synchronized native parity gate | `P11-008,P11-009,P2-013` | Cross-platform evidence report | No critical parity gap remains for declared Owner Mode capabilities. |
| `P11-011` | Windows isolated-untrusted backend | `P11-003,P1-003,P1-004` | Restricted/AppContainer tiers plus disposable VM or attested remote-node path | Hostile containment fixtures pass at each advertised Windows assurance tier. |
| `P11-012` | macOS isolated-untrusted backend | `P11-004,P1-003,P1-004` | Virtualization-framework disposable worker plus lower-tier process restriction | Hostile containment, teardown, network, mount and consent fixtures pass. |
| `P11-013` | Linux isolated-untrusted backend | `P11-005,P1-003,P1-004` | Namespaces, cgroups, seccomp, Landlock/LSM and microVM/remote high-assurance path | Runtime-detected tiers and hostile containment fixtures pass. |
| `P11-014` | Shared isolation conformance and escape suite | `P11-011,P11-012,P11-013` | One cross-platform containment corpus and assurance report | Filesystem, process, network, credential, IPC, device, resource and kill boundaries pass on all three OSs. |
| `P11-015` | Synchronized Owner-plus-isolation platform gate | `P11-010,P11-014` | Combined platform capability and assurance manifest | Windows, macOS and Linux each pass Owner Mode parity and the highest declared isolated-untrusted tier with no silent downgrade. |

## Test Center deliverables

- `P11-TC-001` platform ADR conformance
- `P11-TC-002` generated support manifest validation
- `P11-TC-003` Windows native-host suite
- `P11-TC-004` macOS native-host suite
- `P11-TC-005` Linux native-host suite
- `P11-TC-006` shared semantic conformance
- `P11-TC-007` desktop observation stability
- `P11-TC-008` desktop action and stale-target tests
- `P11-TC-009` device/peripheral foundation
- `P11-TC-010` native parity certification
- `P11-TC-011` Windows isolation tiers
- `P11-TC-012` macOS isolation tiers
- `P11-TC-013` Linux isolation tiers
- `P11-TC-014` cross-platform escape suite
- `P11-TC-015` combined Owner/isolation certification

## Acceptance scenarios

- `P11-ACC-001` equivalent process-tree kill outcome on all desktop OSs
- `P11-ACC-002` equivalent structured desktop action on native fixture apps
- `P11-ACC-003` hostile isolated run cannot access undeclared host secret/file/network/device
- `P11-ACC-004` requested assurance tier never silently downgrades

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Windows, macOS, and Linux native hosts pass one shared semantic suite.
- Desktop observation/action, PTY, lifecycle, credentials, elevation, and kill work on all three.
- Each desktop OS exposes a tested `isolated_untrusted` backend with an explicit assurance tier and a high-assurance VM/microVM or attested remote-node path.
- Hostile-workload fixtures cannot access undeclared host files, credentials, network destinations, IPC endpoints, devices, clipboard, camera, or microphone.
- Platform and containment matrices are generated from evidence, not hand-authored.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker E. Continue the highest-priority dependency-satisfied P11 task.
```
