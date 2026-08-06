# MISSION-014 — Cloud, Fleet, Realtime Multimodal, Omnichannel, Companions, and Headless Nodes

**Default executor:** Worker H
**Priority:** `MEDIUM`
**Roadmap phases:** `P16`, `P17`, `P19`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Deliver deployment, cloud infrastructure, fleet and remote nodes, realtime multimodal chat, voice/image/screen/file/browser/terminal/data channels, web/mobile companions, headless nodes, and ecosystem integrations.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- No active claim. The mission is available only when its entry dependencies and ownership checks pass.

## P16 — Deployment, cloud, infrastructure, and fleet

**Packet:** `docs/roadmap/anarchy/phases/P16-deployment-cloud-infrastructure-and-fleet.md`
**Current execution view:** `BLOCKED_BY_CONNECTORS_AND_APP_FACTORY`
**Test Center module:** `Deployment & Fleet`

### Purpose

This is the bounded execution packet for P16. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P16-001` | Deployment target contracts | `P12-006`, `P13-012` | Environment, plan, apply, health, rollback schemas | Golden vectors pass across adapters. |
| `P16-002` | OCI/container pipeline | `P16-001` | Build, scan, SBOM, run, publish | Reproducible image fixture passes. |
| `P16-003` | Infrastructure-as-code adapters | `P16-001`, `P12-013` | Terraform/OpenTofu and one additional adapter | Plan/destroy/change parsing and policy tests pass. |
| `P16-004` | Cloud provider foundation | `P12-012`, `P16-001` | Account/resource/role session adapters | Sandbox accounts pass create/update/delete/reconcile. |
| `P16-005` | Preview environment service | `P13-012`, `P16-002`, `P16-004` | Ephemeral URL/data/expiry/teardown | Leak and orphan-resource tests pass. |
| `P16-006` | Database deployment and backup | `P12-011`, `P16-004` | Provision, migrate, backup, restore | Restore verification passes after injected failure. |
| `P16-007` | DNS/TLS and edge delivery | `P16-004` | DNS plan, certificate, CDN/cache adapters | Propagation/reconciliation and rollback tests pass. |
| `P16-008` | Cost/quota engine | `P12-013`, `P16-004` | Estimate, reserve, actual cost and halt | Budget overrun fixtures stop before new effects. |
| `P16-009` | Node identity and enrollment | `P12-001`, `P1-006` | Signed enrollment, capability manifest, revoke | Unknown/revoked nodes cannot receive work. |
| `P16-010` | Fleet scheduler | `P16-009`, `P6-011` | Platform/GPU/locality/data-boundary scheduling | Jobs route to compatible nodes and recover. |
| `P16-011` | Remote Owner Mode | `P15-009`, `P16-009`, `P12-013` | Broad/scoped remote grants and local kill | Disconnect/revoke/unknown-effect tests pass. |
| `P16-012` | Deployment/fleet benchmark | `P16-002`, `P16-011` | Preview→production→rollback and multi-node corpus | Reliability, cost, security and evidence targets pass. |

### Test Center deliverables

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

### Acceptance scenarios

- `P16-ACC-001` create preview, verify health, destroy without orphan
- `P16-ACC-002` parse and block unintended destroy
- `P16-ACC-003` restore database after injected migration failure
- `P16-ACC-004` revoke node and prevent further work
- `P16-ACC-005` hard budget stops before new paid effect

### Exit gate

- Complete all task-specific acceptance, platform, evidence, and Test Center requirements.

## P17 — Multimodal realtime and omnichannel

**Packet:** `docs/roadmap/anarchy/phases/P17-multimodal-realtime-and-omnichannel.md`
**Current execution view:** `BLOCKED_BY_MODELS_CHANNELS_AND_CAPTURE`
**Test Center module:** `Realtime & Channels`

### Purpose

This is the bounded execution packet for P17. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P17-001` | Multimodal message schema v2 | `P6-004`, `P14-001` | Text/audio/image/video/screen/file/data parts | Round-trip, redaction and retention tests pass. |
| `P17-002` | Realtime session engine | `P6-011`, `P17-001` | Duplex events, interruption, cancellation, tool progress | Network loss and barge-in fixtures pass. |
| `P17-003` | Speech recognition adapters | `P18-003` | Local/cloud streaming transcription | Accuracy/latency/privacy benchmark passes. |
| `P17-004` | Speech synthesis adapters | `P18-003`, `P14-011` | Streaming voices and consent metadata | Interrupt, device, consent and cache tests pass. |
| `P17-005` | Screen/camera live context | `P15-008`, `P17-001` | Visible capture, frame sampling, masks | Revocation and sensitive-region tests pass. |
| `P17-006` | Channel gateway SDK | `P12-012`, `P17-001` | Messages, threads, attachments, identity and receipts | Sample channel passes conformance. |
| `P17-007` | Work chat/email channels | `P17-006`, `P12-013` | Declared production connectors | Threading, retry, send policy and attachment tests pass. |
| `P17-008` | Customer-support workflows | `P17-006`, `P18-009` | Knowledge, ticket, handoff, SLA, QA | Human handoff and grounded answer corpus pass. |
| `P17-009` | Realtime/omnichannel UI | `P17-002`, `P17-005`, `P17-006` | Voice, live context, channel and takeover UX | Accessibility and hidden-capture checks pass. |
| `P17-010` | Realtime benchmark | `P17-003`, `P17-009` | Latency, quality, interruption and message reliability corpus | Category thresholds pass. |

### Test Center deliverables

- `P17-TC-001` multimodal message round-trip
- `P17-TC-002` duplex interruption/cancellation
- `P17-TC-003` speech recognition benchmark
- `P17-TC-004` speech synthesis/consent
- `P17-TC-005` visible screen/camera context
- `P17-TC-006` channel SDK conformance
- `P17-TC-007` work-chat/email delivery
- `P17-TC-008` human-handoff workflow
- `P17-TC-009` realtime UI accessibility
- `P17-TC-010` realtime benchmark

### Acceptance scenarios

- `P17-ACC-001` user interrupts speech and tool work stops appropriately
- `P17-ACC-002` duplicate inbound channel event is deduplicated
- `P17-ACC-003` identity is linked explicitly, never guessed
- `P17-ACC-004` hidden camera/mic capture is impossible
- `P17-ACC-005` send action obeys transaction policy and returns provider receipt

### Exit gate

- Complete all task-specific acceptance, platform, evidence, and Test Center requirements.

## P19 — Web/mobile companions, headless nodes, and ecosystem

**Packet:** `docs/roadmap/anarchy/phases/P19-web-mobile-companions-headless-nodes-and-ecosystem.md`
**Current execution view:** `BLOCKED_BY_FLEET_AND_REALTIME`
**Test Center module:** `Companions & Ecosystem`

### Purpose

This is the bounded execution packet for P19. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P19-001` | Web control plane | `P5-004`, `P16-009` | Chat, runs, evidence, approvals, remote tools | Browser security and session tests pass. |
| `P19-002` | Android companion | `P17-009`, `P16-009` | Chat, capture/share, approvals, notifications, local/remote tools | Device/emulator lifecycle and permission tests pass. |
| `P19-003` | iOS/iPadOS companion | `P17-009`, `P16-009` | Chat, capture/share, approvals, notifications, local/remote tools | Simulator/device and OS-permission tests pass. |
| `P19-004` | Headless node packages | `P16-009`, `P9-003` | Windows/Linux/macOS service packages | Install/update/revoke/kill tests pass. |
| `P19-005` | Capability/plugin SDK v3 | `P7-009`, `P11-002`, `P12-006`, `P13-002`, `P14-002`, `P18-001` | Native, connector, content, model and recipe extension points | One extension of each class passes without core changes. |
| `P19-006` | MCP version adapters | `P7-001`, `P19-005` | Stable pinned adapter plus 2026-07-28 adapter after final publication | Conformance suites pass without draft lock-in. |
| `P19-007` | A2A 1.0 production adapter | `P7-005`, `P19-005` | Version negotiation, tasks, artifacts, auth, delegation | Official conformance and adversarial tests pass. |
| `P19-008` | Extension registry and marketplace | `P19-005`, `P1-006` | Trust, permissions, install/update/revoke and review | Modified/revoked extensions stop loading. |
| `P19-009` | Multi-device continuity | `P19-001`, `P19-002`, `P19-003` | Encrypted sync of allowed conversation/run state | Conflict, revoke and cross-account leakage tests pass. |
| `P19-010` | Ecosystem conformance lab | `P19-005`, `P19-009` | Public fixtures and certification reports | Third-party implementations can reproduce results. |

### Test Center deliverables

- `P19-TC-001` web control-plane session/security
- `P19-TC-002` Android permission/lifecycle
- `P19-TC-003` iOS permission/lifecycle
- `P19-TC-004` headless package install/update/revoke
- `P19-TC-005` extension SDK classes
- `P19-TC-006` MCP version adapters
- `P19-TC-007` A2A production conformance
- `P19-TC-008` marketplace revoke/update
- `P19-TC-009` encrypted continuity/conflict/revoke
- `P19-TC-010` public conformance lab

### Acceptance scenarios

- `P19-ACC-001` web/mobile claims never imply desktop authority
- `P19-ACC-002` revoked device loses continuity access
- `P19-ACC-003` headless node kill/update works
- `P19-ACC-004` third-party extension reproduces conformance result

### Exit gate

- Complete all task-specific acceptance, platform, evidence, and Test Center requirements.

## Cross-mission task interlocks

- `P16-001` waits for `P12-006` from `MISSION-011`.
- `P16-001` waits for `P13-012` from `MISSION-012`.
- `P16-003` waits for `P12-013` from `MISSION-011`.
- `P16-004` waits for `P12-012` from `MISSION-011`.
- `P16-005` waits for `P13-012` from `MISSION-012`.
- `P16-006` waits for `P12-011` from `MISSION-011`.
- `P16-008` waits for `P12-013` from `MISSION-011`.
- `P16-009` waits for `P1-006` from `MISSION-001`.
- `P16-009` waits for `P12-001` from `MISSION-011`.
- `P16-010` waits for `P6-011` from `MISSION-006`.
- `P16-011` waits for `P12-013` from `MISSION-011`.
- `P16-011` waits for `P15-009` from `MISSION-010`.
- `P17-001` waits for `P14-001` from `MISSION-013`.
- `P17-001` waits for `P6-004` from `MISSION-006`.
- `P17-002` waits for `P6-011` from `MISSION-006`.
- `P17-003` waits for `P18-003` from `MISSION-006`.
- `P17-004` waits for `P14-011` from `MISSION-013`.
- `P17-004` waits for `P18-003` from `MISSION-006`.
- `P17-005` waits for `P15-008` from `MISSION-010`.
- `P17-006` waits for `P12-012` from `MISSION-011`.
- `P17-007` waits for `P12-013` from `MISSION-011`.
- `P17-008` waits for `P18-009` from `MISSION-006`.
- `P19-001` waits for `P5-004` from `MISSION-005`.
- `P19-004` waits for `P9-003` from `MISSION-008`.
- `P19-005` waits for `P11-002` from `MISSION-010`.
- `P19-005` waits for `P12-006` from `MISSION-011`.
- `P19-005` waits for `P13-002` from `MISSION-012`.
- `P19-005` waits for `P14-002` from `MISSION-013`.
- `P19-005` waits for `P18-001` from `MISSION-006`.
- `P19-005` waits for `P7-009` from `MISSION-007`.
- `P19-006` waits for `P7-001` from `MISSION-007`.
- `P19-007` waits for `P7-005` from `MISSION-007`.
- `P19-008` waits for `P1-006` from `MISSION-001`.

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
Take the repo. You are Worker H. Take MISSION-014 and continue autonomously.
```
