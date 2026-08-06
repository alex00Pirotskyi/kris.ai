# MISSION-006 — Agent Intelligence, Model Routing, Local Models, and Hardware Acceleration

**Default executor:** Worker G
**Priority:** `HIGH`
**Roadmap phases:** `P6`, `P18`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Deliver the agent loop, planning, memory, model/provider routing, safe autonomy, local model execution, hardware acceleration, evaluation, fallback, and medium-machine operating profile.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- Worker: `G`
- Branch: `agent/g/mission-006-model-routing`
- Draft PR: `#76`
- Observed head: `0aa6203e89a9b825c575954af54a0c108c79b67a`
- Observed tree: `4b262889edb61ec0c705b289aa29fd0df7c8456c`
- Current work: P6-001 exact candidate repaired the governed Dart source inventory; focused model-registry and source-contract tests pass; full tri-platform product gates, Worker B Test Center review, and an independent exact-commit/tree review remain pending.
- These are discovery anchors, not permission to skip live-state discovery.

## P6 — Agent intelligence, model routing, and safe autonomy

**Packet:** `docs/roadmap/anarchy/phases/P06-agent-intelligence-model-routing-and-safe-autonomy.md`
**Current execution view:** `READY_PARALLEL_P6_001`
**Test Center module:** `Agent Quality & Model Routing`

### Purpose

This is the bounded execution packet for P6. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P6-001` | Model registry v2 | `P1-001` | Record provider/model identity, limits, tool profile, data boundary, cost, benchmark, and approved task classes. | Unknown models start evaluation-only. |
| `P6-002` | Role-based model routing | `P6-001` | Separate planner, executor, verifier, browser observer, extractor, and reviewer roles. | Routing decisions are durable and policy constrained. |
| `P6-003` | Planner/executor/verifier separation | `P6-002`, `P1-004` | Prevent executor from granting scope or self-certifying acceptance criteria. | Adversarial model cannot convert prose into authority. |
| `P6-004` | Unified action protocol v3 | `P1-003` | Add terminal, browser, research, data, user takeover, wait, delegate, complete, and fail decisions. | Cross-provider golden and fuzz tests pass. |
| `P6-005` | Context provenance labels | `P6-003` | Label user, system, project, web, memory, terminal, MCP, A2A, and tool output. | Injection text cannot impersonate system authority. |
| `P6-006` | Prompt-injection containment | `P6-005` | Add untrusted-content wrappers, tool-policy separation, destination checks, and exfiltration controls. | Direct/indirect injection corpus has zero unauthorized effects. |
| `P6-007` | Browser planning policy | `P3-010`, `P6-004` | Require observe-action-verify, bounded retries, takeover, and stale-target handling. | Dynamic-page fixtures converge without blind clicking. |
| `P6-008` | Terminal planning policy | `P2-006`, `P6-004` | Distinguish finite/interactive/background commands, readiness, destructive scope, and recovery. | Agent stops loops and verifies command outcomes. |
| `P6-009` | Research answer policy | `P4-010`, `P6-005` | Require fetched evidence, citation coverage, freshness, disagreement, and source type. | Snippet-only or uncited claims fail verification. |
| `P6-010` | Memory admission v2 | `P6-005` | Quarantine failed/adversarial runs, preserve provenance, add expiry and user pinning. | Poisoned memory does not enter normal context. |
| `P6-011` | Long-running task handles | `P1-012`, `P6-004` | Support durable wait, resume, polling, mid-flight input, pause, and cancellation. | Desktop restart can resume supported tasks. |
| `P6-012` | Strategy escalation and convergence | `P6-003` | Use semantic progress, repeated-outcome detection, split, replan, stronger model, user takeover, or fail. | Long tasks do not loop indefinitely. |
| `P6-013` | Independent acceptance engine | `P6-003` | Map every criterion to current objective evidence and validator. | Generic evidence cannot satisfy unrelated criteria. |
| `P6-014` | Model compatibility test matrix | `P6-001`, `P6-004` | Run every supported model through protocol, coding, browser, research, and safety suites. | Support matrix is generated from results. |
| `P6-015` | Agent benchmark dashboard | `P6-013`, `P6-014` | Report task success, false completion, unauthorized attempts/effects, cost, latency, and recovery. | Release comparison is reproducible and signed. |

### Test Center deliverables

- `P6-TC-001` model registry validation
- `P6-TC-002` role-routing determinism
- `P6-TC-003` planner/executor/verifier separation
- `P6-TC-004` action-protocol golden/fuzz suite
- `P6-TC-005` context provenance labels
- `P6-TC-006` prompt-injection containment corpus
- `P6-TC-007` browser planning convergence
- `P6-TC-008` terminal planning convergence
- `P6-TC-009` research-answer citation policy
- `P6-TC-010` memory-admission poisoning tests
- `P6-TC-011` durable wait/resume/cancel tests
- `P6-TC-012` loop detection and escalation
- `P6-TC-013` criterion-scoped acceptance engine
- `P6-TC-014` model compatibility matrix
- `P6-TC-015` benchmark dashboard

### Acceptance scenarios

- `P6-ACC-001` malicious README cannot widen authority
- `P6-ACC-002` web page instruction remains untrusted
- `P6-ACC-003` executor cannot certify unrelated acceptance criterion
- `P6-ACC-004` unsupported model begins evaluation-only
- `P6-ACC-005` repeated no-progress outcomes trigger replan or fail
- `P6-ACC-006` desktop restart resumes supported durable task
- `P6-ACC-007` local-only routing produces zero external dispatches

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Planner, executor, policy, and verifier responsibilities are separate.
- Browser, terminal, research, and user takeover are typed decisions.
- Prompt injection cannot grant authority or exfiltrate through tools.
- Every supported model has a measured compatibility profile.

## P18 — Local models, hardware acceleration, and advanced intelligence

**Packet:** `docs/roadmap/anarchy/phases/P18-local-models-hardware-acceleration-and-advanced-intelligence.md`
**Current execution view:** `BLOCKED_BY_P6_MODEL_REGISTRY`
**Test Center module:** `Models & Hardware`

### Purpose

This is the bounded execution packet for P18. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P18-001` | Model descriptor v3 | `P6-001` | Multimodal/local/cloud/hardware/license fields | Invalid and changed descriptors are rejected. |
| `P18-002` | Hardware capability detector | `P11-002` | CPU/GPU/NPU/memory/storage benchmark inventory | Results match native probes on all three desktop OSs. |
| `P18-003` | Local runtime adapter interface | `P18-001`, `P18-002` | Load/generate/stream/cancel/metrics contract | CPU reference runtime passes shared suite. |
| `P18-004` | ONNX Runtime adapter | `P18-003` | Execution-provider discovery and fallback | CPU plus available accelerator fixtures pass. |
| `P18-005` | Local LLM runtime adapters | `P18-003` | At least two plugin runtime adapters | Model load, tool/JSON, cancel and memory limits pass. |
| `P18-006` | Local speech/vision adapters | `P18-003`, `P17-001` | Offline transcription/vision baseline | Data-boundary and quality tests pass. |
| `P18-007` | Model artifact manager | `P18-001` | License, digest, resume, storage, revoke | Corrupt/changed/unlicensed artifacts fail. |
| `P18-008` | Advanced model router | `P18-001`, `P6-014` | Cost/latency/privacy/hardware/health routing | Failure and boundary fallback tests pass. |
| `P18-009` | Context compiler v3 | `P6-005`, `P4-013`, `P6-010` | Provenance labels, retrieval, compression and audit | Injection and secret exclusion fixtures pass. |
| `P18-010` | Model adaptation pipeline | `P18-007` | Dataset/model card/eval/promotion/rollback | Adapted model cannot promote without benchmark. |
| `P18-011` | Multimodal model benchmark | `P18-004`, `P18-010` | Code/browser/desktop/research/content/realtime corpus | Supported role matrix is generated from results. |

### Test Center deliverables

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

### Acceptance scenarios

- `P18-ACC-001` unsupported accelerator falls back honestly
- `P18-ACC-002` corrupt model artifact is rejected
- `P18-ACC-003` no automatic large model download
- `P18-ACC-004` adapted model cannot promote without benchmark
- `P18-ACC-005` stricter data boundary is never crossed by fallback

### Exit gate

- Complete all task-specific acceptance, platform, evidence, and Test Center requirements.

## Cross-mission task interlocks

- `P18-002` waits for `P11-002` from `MISSION-010`.
- `P18-006` waits for `P17-001` from `MISSION-014`.
- `P18-009` waits for `P4-013` from `MISSION-004`.
- `P6-001` waits for `P1-001` from `MISSION-001`.
- `P6-003` waits for `P1-004` from `MISSION-001`.
- `P6-004` waits for `P1-003` from `MISSION-001`.
- `P6-007` waits for `P3-010` from `MISSION-003`.
- `P6-008` waits for `P2-006` from `MISSION-001`.
- `P6-009` waits for `P4-010` from `MISSION-004`.
- `P6-011` waits for `P1-012` from `MISSION-001`.

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
Take the repo. You are Worker G. Take MISSION-006 and continue autonomously.
```
