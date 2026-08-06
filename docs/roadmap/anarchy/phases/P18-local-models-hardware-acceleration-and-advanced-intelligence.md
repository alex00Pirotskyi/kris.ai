---
phase: P18
title: "Local models, hardware acceleration, and advanced intelligence"
execution_view_status: BLOCKED_BY_P6_MODEL_REGISTRY
primary_workers: [G, I]
test_center_module: "Models & Hardware"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P18 — Local models, hardware acceleration, and advanced intelligence

## Purpose

This is the bounded execution packet for P18. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_BY_P6_MODEL_REGISTRY`
- Primary workers: Worker G, Worker I
- Test Center module: `Models & Hardware`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P18-001` | Model descriptor v3 | `P6-001` | Multimodal/local/cloud/hardware/license fields | Invalid and changed descriptors are rejected. |
| `P18-002` | Hardware capability detector | `P11-002` | CPU/GPU/NPU/memory/storage benchmark inventory | Results match native probes on all three desktop OSs. |
| `P18-003` | Local runtime adapter interface | `P18-001,P18-002` | Load/generate/stream/cancel/metrics contract | CPU reference runtime passes shared suite. |
| `P18-004` | ONNX Runtime adapter | `P18-003` | Execution-provider discovery and fallback | CPU plus available accelerator fixtures pass. |
| `P18-005` | Local LLM runtime adapters | `P18-003` | At least two plugin runtime adapters | Model load, tool/JSON, cancel and memory limits pass. |
| `P18-006` | Local speech/vision adapters | `P18-003,P17-001` | Offline transcription/vision baseline | Data-boundary and quality tests pass. |
| `P18-007` | Model artifact manager | `P18-001` | License, digest, resume, storage, revoke | Corrupt/changed/unlicensed artifacts fail. |
| `P18-008` | Advanced model router | `P18-001,P6-014` | Cost/latency/privacy/hardware/health routing | Failure and boundary fallback tests pass. |
| `P18-009` | Context compiler v3 | `P6-005,P4-013,P6-010` | Provenance labels, retrieval, compression and audit | Injection and secret exclusion fixtures pass. |
| `P18-010` | Model adaptation pipeline | `P18-007` | Dataset/model card/eval/promotion/rollback | Adapted model cannot promote without benchmark. |
| `P18-011` | Multimodal model benchmark | `P18-004` through `P18-010` | Code/browser/desktop/research/content/realtime corpus | Supported role matrix is generated from results. |

## Test Center deliverables

- `P18-TC-001` model descriptor validation
- `P18-TC-002` hardware detector accuracy
- `P18-TC-003` local runtime shared protocol
- `P18-TC-004` ONNX execution-provider fallback
- `P18-TC-005` local LLM adapters
- `P18-TC-006` local speech/vision privacy
- `P18-TC-007` artifact digest/license/download
- `P18-TC-008` advanced routing
- `P18-TC-009` context compiler provenance/secret exclusion
- `P18-TC-010` adaptation promotion gate
- `P18-TC-011` multimodal model benchmark

## Acceptance scenarios

- `P18-ACC-001` unsupported accelerator falls back honestly
- `P18-ACC-002` corrupt model artifact is rejected
- `P18-ACC-003` no automatic large model download
- `P18-ACC-004` adapted model cannot promote without benchmark
- `P18-ACC-005` stricter data boundary is never crossed by fallback

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
Take the repo. You are Worker G. Continue the highest-priority dependency-satisfied P18 task.
```
