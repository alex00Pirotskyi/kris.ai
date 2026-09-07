# Kristin Self-Awareness + Autonomic Recovery — Corrective Implementation Handoff

Branch: `feat/kristin-self-awareness-autonomic-recovery`

Corrective pass started from: `a1d051f10ca0243b09507295fea7e512b6d2f6d6`.

This pass implements the architecture/code-review corrections identified after the v2 self-awareness increment. It remains an implementation-worker branch: analyzer/tests/CI/release qualification and merge/landing are intentionally not part of this pass.

## Corrections implemented

### 1. Terminal recovery is truly terminal

`FailureEvent` now defaults to `Recoverability.unspecified`, which is distinct from an explicitly terminal failure. `FailureClassifier` maps permission/unknown failures to a dedicated terminal level. `RecoveryPolicy` never maps a terminal failure to L0 retry: it requests known missing authority or asks for intervention when cause/authority is not established.

### 2. Live self-awareness is enforced inside the Universal Task Kernel

`KernelSelfModelRegistry` registers one live resolver for the production kernel. Both `UniversalTaskKernel.understand` and `UniversalTaskKernel.plan` consume it and intersect live capabilities with the caller/catalog set. The self-model can therefore remove unavailable/unhealthy capabilities but can never add capabilities or Runner tools.

The Studio also supplies a live `SelfModelPlanningContext` explicitly during initial understanding and semantic clarification.

### 3. ProductRuntime recovery is concretely composed

New `lib/product/recovery/product_runtime_recovery.dart` binds the recovery contracts to canonical runtime services:

- durable failure/attempt events through `ProductRuntime.events`;
- durable bounded recovery-experience replay;
- failure-to-project/model self-context resolution;
- recovery authority evaluation;
- bounded ProductRuntime actuator;
- deterministic verifier;
- Universal Task Kernel recovery-work router;
- original-run continuation;
- `run.failed` event supervision;
- direct-operation failure entrypoint from the production Chat gateway.

Recovery-generated child runs are excluded from recursive supervision; linked continuations remain visible so recurrence advances the bounded strategy ladder.

### 4. L4 is reachable only through staged, externally authorized self-repair

L4 is a real `selfRepair` decision, not an immediate quarantine return. It requires:

1. a healthy isolated Owner runtime;
2. an independently registered `RecoveryExternalAuthorityProvider` that proves `owner` / `owner.self_repair` for the concrete operation;
3. an independently registered `KristinRecoveryHost`;
4. a staged candidate identity;
5. pre-activation qualification;
6. activation;
7. post-activation verification;
8. automatic rollback through `StagedSelfRepairCoordinator` if verification fails.

Owner runtime presence never becomes an authority grant.

### 5. Capability prerequisites are explicit

Project requirements no longer depend on `availableWithoutTarget`. Modify/fix/analyze/test/build/run/stop/restart are explicitly project-required. Model-backed substantial work explicitly requires a selected model whose exact identity is present in fresh provider discovery.

### 6. Model/provider truth is explicit

`ProductRuntimeSnapshotProvider` tracks selected-model identity separately from live discovery and records `discovered: true/false`. Provider discovery is performed per configured provider with bounded timeout and explicit available/empty/failed status, latency and redacted failure detail.

### 7. Probe scheduling and propagation are corrected

The monitor determines which probes are due before taking an expensive snapshot. Probe health has its own TTL. A due probe set produces one post-probe self-model refresh, ensuring failures become model-visible instead of living only in an internal override cache.

Browser and Owner probes run continuously at runtime-global cadence. Selected-model probing is session-overlay aware and runs when that session participates in self-aware planning/querying.

### 8. Self-model changes are semantic

Application change detection uses semantic JSON/fingerprints that exclude capture timestamps and evidence observation/expiry timestamps. Re-observation alone therefore does not create a material `SelfModelChange`. Concrete changed application fields are recorded.

### 9. Global runtime state and conversation selection are separated

`ProductSelfAwarenessRuntime` owns only application-global observation/history. `SelfModelSessionOverlay` carries selected project/model per conversation/query. `KristinSelfModelService` serializes snapshot refreshes to prevent out-of-order cache/last-snapshot mutation.

### 10. Authority state uses the canonical policy and has explicit epistemic state

Chat capability descriptors derive permission requirements from `CapabilityAuthorityResolver`. Availability distinguishes `notRequired`, `notEvaluated`, `absent`, and `granted`. Snapshotting never reports a per-operation grant merely because a runtime is present.

The recovery gate proves canonical `PermissionScope` authority only from active governed-run grants. External authority vocabulary is delegated to an independent provider and otherwise stays `notEvaluated`.

### 11. Recovery progress is semantic

New evidence identifiers do not by themselves count as progress. Recovery records semantic before/after fingerprints and verifier results. The policy walks the bounded L0→L1→L2→L3 ladder and skips strategies already attempted or learned ineffective for the same normalized signature/environment.

L3 waits for terminal governed kernel recovery work before verification. Rollback is explicit where a deterministic actuator rollback exists. Continuation occurs only after recovery verification.

### 12. One Kristin Chat now queries the live self-model

Informational Chat intercepts self-awareness questions before model generation. Current capability, blocker/requirements, recent material changes, self-integrity and explicit self-probe questions are answered deterministically from the same live self-model used by the kernel.

## Safety boundaries preserved

- Self-knowledge does not grant authority.
- Availability does not grant authority.
- Health does not grant authority.
- Authority does not create Runner tools.
- The live self-model can narrow planner capability sets but never expand them.
- Coordinator capabilities still cannot become exact Runner tools.
- Recovery cannot expand the original governed run's permission envelope.
- User cancellation is never overridden by recovery continuation.
- L4 requires both an external authority provider and an independent recovery host.
- Recovery success requires verification before original-task continuation.

## Main files changed in this corrective pass

- `lib/product/self_awareness/capability_self_model.dart`
- `lib/product/self_awareness/operational_self_awareness.dart`
- `lib/product/product_runtime_self_awareness.dart`
- `lib/product/task_kernel/task_kernel.dart`
- `lib/product/recovery/failure_recovery.dart`
- `lib/product/recovery/product_runtime_recovery.dart` (new)
- `lib/product/chat_action_dispatcher.dart`
- `lib/product/chat_control_plane_studio.dart`
- `lib/product/chat_control_plane_streaming.dart`

## Deliberately unqualified

Per the implementation-worker assignment, this pass does **not** run or repair:

- Dart analyzer;
- unit/integration tests;
- CI workflows;
- release qualification;
- branch rebase/landing/merge.

Compilation and behavior therefore still require the separate qualification worker.

## Qualification focus

The qualification worker should concentrate on:

- Dart null-safety and interface compatibility across the new overlay/snapshot signatures;
- live kernel narrowing in initial planning, research/diagnostics families and semantic replans;
- permission-scope carry-forward and rejection of recovery scope expansion;
- durable recovery-experience replay;
- recovery-child recursion suppression and continuation recurrence handling;
- provider discovery timeout/caching behavior;
- Browser/Owner probe cadence and shutdown ordering;
- self-model refresh serialization under simultaneous event/probe/UI reads;
- Chat self-awareness query routing;
- independent Owner/self-repair authority provider and recovery-host packaging when those platform components are available.

## Landing warning

Do not merge directly on the strength of this handoff. This branch is implementation-complete for the reviewed corrective architecture, but deliberately unqualified. The next worker should qualify compilation/behavior against the current branch, correct qualification defects without weakening the safety boundaries above, and only then prepare a landing candidate.
