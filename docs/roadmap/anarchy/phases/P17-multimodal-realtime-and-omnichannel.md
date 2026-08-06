---
phase: P17
title: "Multimodal realtime and omnichannel"
execution_view_status: BLOCKED_BY_MODELS_CHANNELS_AND_CAPTURE
primary_workers: [G, F, H]
test_center_module: "Realtime & Channels"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P17 — Multimodal realtime and omnichannel

## Purpose

This is the bounded execution packet for P17. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_BY_MODELS_CHANNELS_AND_CAPTURE`
- Primary workers: Worker G, Worker F, Worker H
- Test Center module: `Realtime & Channels`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P17-001` | Multimodal message schema v2 | `P6-004,P14-001` | Text/audio/image/video/screen/file/data parts | Round-trip, redaction and retention tests pass. |
| `P17-002` | Realtime session engine | `P6-011,P17-001` | Duplex events, interruption, cancellation, tool progress | Network loss and barge-in fixtures pass. |
| `P17-003` | Speech recognition adapters | `P18-003` | Local/cloud streaming transcription | Accuracy/latency/privacy benchmark passes. |
| `P17-004` | Speech synthesis adapters | `P18-003,P14-011` | Streaming voices and consent metadata | Interrupt, device, consent and cache tests pass. |
| `P17-005` | Screen/camera live context | `P15-008,P17-001` | Visible capture, frame sampling, masks | Revocation and sensitive-region tests pass. |
| `P17-006` | Channel gateway SDK | `P12-012,P17-001` | Messages, threads, attachments, identity and receipts | Sample channel passes conformance. |
| `P17-007` | Work chat/email channels | `P17-006,P12-013` | Declared production connectors | Threading, retry, send policy and attachment tests pass. |
| `P17-008` | Customer-support workflows | `P17-006,P18-009` | Knowledge, ticket, handoff, SLA, QA | Human handoff and grounded answer corpus pass. |
| `P17-009` | Realtime/omnichannel UI | `P17-002,P17-005,P17-006` | Voice, live context, channel and takeover UX | Accessibility and hidden-capture checks pass. |
| `P17-010` | Realtime benchmark | `P17-003` through `P17-009` | Latency, quality, interruption and message reliability corpus | Category thresholds pass. |

## Test Center deliverables

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

## Acceptance scenarios

- `P17-ACC-001` user interrupts speech and tool work stops appropriately
- `P17-ACC-002` duplicate inbound channel event is deduplicated
- `P17-ACC-003` identity is linked explicitly, never guessed
- `P17-ACC-004` hidden camera/mic capture is impossible
- `P17-ACC-005` send action obeys transaction policy and returns provider receipt

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
Take the repo. You are Worker G. Continue the highest-priority dependency-satisfied P17 task.
```
