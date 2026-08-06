# MISSION-010 — Native Platform, Device Automation, Isolation, and Remote Operation

**Default executor:** Worker E
**Priority:** `HIGH`
**Roadmap phases:** `P11`, `P15`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Deliver capability-parity native helpers for Windows, macOS, and Linux, device and peripheral automation, isolation tiers, native application control, remote operation, and honest platform evidence.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- Worker: `E`
- Branch: `agent/e/native-parity-readiness`
- Draft PR: `#71`
- Observed head: `825769f639edb5db22b27a222cd5c1c57f4ed775`
- Observed tree: `4fd309a006ff4b88c2293b7962c130b5998426ac`
- Current work: P11 native parity inventory and conformance readiness; P11-001 blocked by P2-004 and native transport evidence
- These are discovery anchors, not permission to skip live-state discovery.

## P11 — Omni-platform native parity and desktop control

**Packet:** `docs/roadmap/anarchy/phases/P11-omni-platform-native-parity-and-desktop-control.md`
**Current execution view:** `BLOCKED_BY_P2_004_AND_NATIVE_ADRS`
**Test Center module:** `Native Platform & Isolation`

### Purpose

This is the bounded execution packet for P11. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P11-001` | Approve omni-platform ADR set | `P1-001`, `P2-004` | ADRs for native hosts, platform adapters, parity semantics, mobile/web truth, architecture matrix | No implementation-critical ambiguity remains and no mandatory desktop OS is deferred. |
| `P11-002` | Create platform support manifest | `P11-001` | Schema, generator, UI, release integration | Manifest is generated from tests for Windows, macOS, and Linux. |
| `P11-003` | Implement Windows native host v1 | `P1-012`, `P11-001` | ConPTY, Job Objects, UIA, credential, window, service, screen baseline | Windows conformance and hostile lifecycle fixtures pass. |
| `P11-004` | Implement macOS native host v1 | `P1-012`, `P11-001` | PTY, process lifecycle, AX, Keychain, NSWorkspace, TCC baseline | Signed helper passes macOS fixtures and consent recovery. |
| `P11-005` | Implement Linux native host v1 | `P1-012`, `P11-001` | PTY, cgroup/systemd, AT-SPI, portals, Secret Service baseline | GNOME/KDE and Wayland/X11 declared fixtures pass. |
| `P11-006` | Shared native conformance runner | `P11-003`, `P11-004`, `P11-005` | One suite against all platform adapters | Semantic result and error compatibility report is green. |
| `P11-007` | Native desktop observation v2 | `P11-006` | Window/accessibility/screen observations and hashes | Deterministic fixture observations pass on all three. |
| `P11-008` | Native desktop action v2 | `P11-007` | Structured actions plus fallback ladder | Actions verify postconditions and reject stale targets. |
| `P11-009` | Peripheral/device foundation | `P11-006` | Printers, scanner/camera/mic/device inventory contracts | Permission, unplug, and data-direction fixtures pass. |
| `P11-010` | Synchronized native parity gate | `P11-008`, `P11-009`, `P2-013` | Cross-platform evidence report | No critical parity gap remains for declared Owner Mode capabilities. |
| `P11-011` | Windows isolated-untrusted backend | `P11-003`, `P1-003`, `P1-004` | Restricted/AppContainer tiers plus disposable VM or attested remote-node path | Hostile containment fixtures pass at each advertised Windows assurance tier. |
| `P11-012` | macOS isolated-untrusted backend | `P11-004`, `P1-003`, `P1-004` | Virtualization-framework disposable worker plus lower-tier process restriction | Hostile containment, teardown, network, mount and consent fixtures pass. |
| `P11-013` | Linux isolated-untrusted backend | `P11-005`, `P1-003`, `P1-004` | Namespaces, cgroups, seccomp, Landlock/LSM and microVM/remote high-assurance path | Runtime-detected tiers and hostile containment fixtures pass. |
| `P11-014` | Shared isolation conformance and escape suite | `P11-011`, `P11-012`, `P11-013` | One cross-platform containment corpus and assurance report | Filesystem, process, network, credential, IPC, device, resource and kill boundaries pass on all three OSs. |
| `P11-015` | Synchronized Owner-plus-isolation platform gate | `P11-010`, `P11-014` | Combined platform capability and assurance manifest | Windows, macOS and Linux each pass Owner Mode parity and the highest declared isolated-untrusted tier with no silent downgrade. |

### Test Center deliverables

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

### Acceptance scenarios

- `P11-ACC-001` equivalent process-tree kill outcome on all desktop OSs
- `P11-ACC-002` equivalent structured desktop action on native fixture apps
- `P11-ACC-003` hostile isolated run cannot access undeclared host secret/file/network/device
- `P11-ACC-004` requested assurance tier never silently downgrades

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Windows, macOS, and Linux native hosts pass one shared semantic suite.
- Desktop observation/action, PTY, lifecycle, credentials, elevation, and kill work on all three.
- Each desktop OS exposes a tested `isolated_untrusted` backend with an explicit assurance tier and a high-assurance VM/microVM or attested remote-node path.
- Hostile-workload fixtures cannot access undeclared host files, credentials, network destinations, IPC endpoints, devices, clipboard, camera, or microphone.
- Platform and containment matrices are generated from evidence, not hand-authored.

## P15 — Native application/device automation and remote operation

**Packet:** `docs/roadmap/anarchy/phases/P15-native-application-device-automation-and-remote-operation.md`
**Current execution view:** `BLOCKED_BY_NATIVE_PARITY`
**Test Center module:** `Desktop Automation & Devices`

### Purpose

This is the bounded execution packet for P15. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P15-001` | Desktop observation/action v3 schemas | `P11-008` | Cross-platform semantic tree and target signatures | Golden vectors and stale-target tests pass. |
| `P15-002` | Windows advanced automation | `P15-001` | UIA events, menus, virtualized controls, multi-display | Native fixture suite passes. |
| `P15-003` | macOS advanced automation | `P15-001` | AX events, menus, Spaces/display/TCC states | Native fixture suite passes. |
| `P15-004` | Linux advanced automation | `P15-001` | AT-SPI events, portal/Wayland/X11 strategies | GNOME/KDE fixture suite passes. |
| `P15-005` | Visual fallback engine | `P15-002`, `P15-003`, `P15-004` | Confidence, display scaling, region tracking and postconditions | Low-confidence and changed-layout actions pause. |
| `P15-006` | Application adapter SDK | `P12-012`, `P15-001` | Plugins for app-specific structured actions | Sample IDE/office adapter passes conformance. |
| `P15-007` | Device and peripheral service | `P11-009` | Print/scan/camera/mic/serial/USB inventory and actions | Permission, disconnect and data evidence pass. |
| `P15-008` | Screen/audio recording service | `P11-010` | Visible capture state, regions, devices, privacy masks | Hidden capture and revoked-permission tests fail safely. |
| `P15-009` | Remote desktop trusted-node protocol | `P1-012`, `P12-001`, `P15-001` | Encrypted session, screen/input/file policy, receipts | Node substitution, disconnect and revoke tests pass. |
| `P15-010` | Native automation benchmark | `P15-005`, `P15-006`, `P15-007`, `P15-009` | Cross-OS real-app and fixture corpus | Target success and zero unintended-action threshold pass. |

### Test Center deliverables

- `P15-TC-001` target-signature schema
- `P15-TC-002` Windows advanced automation
- `P15-TC-003` macOS advanced automation
- `P15-TC-004` Linux advanced automation
- `P15-TC-005` visual-fallback confidence
- `P15-TC-006` application-adapter SDK
- `P15-TC-007` device/peripheral service
- `P15-TC-008` visible screen/audio capture
- `P15-TC-009` trusted remote desktop protocol
- `P15-TC-010` native automation benchmark

### Acceptance scenarios

- `P15-ACC-001` structured action beats synthetic input
- `P15-ACC-002` stale/ambiguous visual target pauses
- `P15-ACC-003` capture state is always visible
- `P15-ACC-004` remote node revocation stops new actions
- `P15-ACC-005` unplugged device returns honest state

### Exit gate

- Complete all task-specific acceptance, platform, evidence, and Test Center requirements.

## Cross-mission task interlocks

- `P11-001` waits for `P1-001` from `MISSION-001`.
- `P11-001` waits for `P2-004` from `MISSION-001`.
- `P11-003` waits for `P1-012` from `MISSION-001`.
- `P11-004` waits for `P1-012` from `MISSION-001`.
- `P11-005` waits for `P1-012` from `MISSION-001`.
- `P11-010` waits for `P2-013` from `MISSION-001`.
- `P11-011` waits for `P1-003` from `MISSION-001`.
- `P11-011` waits for `P1-004` from `MISSION-001`.
- `P11-012` waits for `P1-003` from `MISSION-001`.
- `P11-012` waits for `P1-004` from `MISSION-001`.
- `P11-013` waits for `P1-003` from `MISSION-001`.
- `P11-013` waits for `P1-004` from `MISSION-001`.
- `P15-006` waits for `P12-012` from `MISSION-011`.
- `P15-009` waits for `P1-012` from `MISSION-001`.
- `P15-009` waits for `P12-001` from `MISSION-011`.

## Git, collision, and merge contract

- One active claim per mission. A replacement worker must receive a recorded yield or transfer.
- Do not edit another active mission's exclusive paths or shared authority without an explicit coordination packet.
- Workers may commit, push, update their draft PR, and iterate CI inside their bounded claim.
- No blanket right to bypass branch protection, required checks, security review, dependency gates, or roadmap authority.
- A materially changed exact candidate invalidates commit-bound reviews and evidence.
- Every significant push updates mission state and creates or supersedes a checkpoint.

## Mission definition of done

The mission is complete only when every assigned roadmap task is truthfully complete; applicable unit, contract, component, integration, negative, regression, platform, recovery, performance, acceptance, certification, and release gates pass; evidence and documentation are durable; required independent reviews bind the final exact commit/tree; and the integrated product capability works on every mandatory platform claimed by the roadmap.

## Resume command

```text
Take the repo. You are Worker E. Take MISSION-010 and continue autonomously.
```
