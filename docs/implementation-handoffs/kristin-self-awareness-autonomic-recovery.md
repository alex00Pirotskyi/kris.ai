# Kristin Self-Awareness + Autonomic Recovery — implementation handoff

## Status

Implementation branch: `feat/kristin-self-awareness-autonomic-recovery`

Base: `bbb8cbdb52844f868abf9916c9bb77446c2809cf` (`feat/one-kristin-convergence` at implementation start)

This worker intentionally did **not** perform repository qualification. See the final commit SHA in the branch history / implementation-worker response.

## Architecture implemented

### Self-model

`lib/product/self_awareness/capability_self_model.dart`

- Adds immutable `CapabilityDescriptor`, `CapabilityAvailability`, `KnownCapability`, `ApplicationSnapshot`, `KristinSelfSnapshot` and `SelfModelPlanningContext`.
- Adds `KristinSelfModelService` with bounded summary rendering, machine-readable rendering, focused capability lookup, availability explanation and focused planning-context projection.
- Keeps knowledge separate from availability and authority: descriptors say what exists, availability says what currently works, and neither object grants a permission.
- `SelfModelPlanningContext` explicitly carries capability knowledge and current-authority description while documenting that Runner tools remain a separate allow-list.

### Capabilities

- Adds provider-owned `KristinCapabilityProvider` and dynamic `KristinCapabilityRegistry`.
- Adapts the legacy `kKristinCapabilities` registry through `ChatCapabilityProvider` instead of replacing it.
- Adds runtime-owned Browser and Owner recovery providers in `product_runtime_self_awareness.dart`.
- Browser availability is derived from the real `P3ProductRuntimeBrowserHandle`.
- Owner recovery availability is derived from the real `P2ProductRuntimeOwnerModeHandle`, including completion eligibility and secure-isolation state.
- Owner capability existence is never interpreted as a run grant.

### Runtime state

`lib/product/product_runtime_self_awareness.dart`

- Adds `ProductRuntimeSnapshotProvider`, which reads bounded project/run state from canonical repositories and Browser/Owner state from their canonical runtime handles.
- Session-owned selected project/model are injected by the caller rather than guessed from global/UI state.
- Snapshot size is bounded (`maxProjects`, `maxRuns`); it does not dump the database or history.
- Platform is reported from the current Dart runtime.

### Universal Task Kernel

`lib/product/task_kernel/task_kernel.dart`

- `KernelRequestContext` now accepts optional `SelfModelPlanningContext`.
- `liveAvailableCapabilityIds` intersects the legacy catalog with the live self-model. A capability that is known but currently blocked is not advertised to understanding/planning as usable.
- `availableToolNames` remains independent and unchanged; self-awareness cannot add Runner tools.
- Adds `planWithRequestContext` to make the self-aware path explicit for callers holding full kernel context.
- The existing compiler/authority validation is preserved: capability requirements still must be represented by the compiled permission contract.

### Failure model

`lib/product/recovery/failure_recovery.dart`

- Adds first-class `FailureEvent` with stable identity, timestamp, severity/category, subsystem/operation, run/task/work-item/project/process identities, error code, stack/evidence references, expected/observed state, before/after state, recent actions/changes, capability/authority information, recoverability, parent/root failure identity and normalized recurrence signature.
- Adds `FailureClassifier` and explicit `Recoverability`.
- Adds normalized failure signatures that suppress volatile addresses/numbers/paths for progress comparison.

### Operational checkpoints

- Adds `OperationalCheckpoint` and `OperationTransition` for lightweight before/after state, source identity, process/model/capability state, configuration fingerprints and evidence references.
- Designed to reuse existing git/process/evidence observations rather than snapshotting the filesystem.

### Recovery

- Adds explicit recovery levels L0–L4, decisions and strategies.
- Adds `RecoveryPolicy` with bounded total attempts and same-signature attempt budget.
- Same strategy + same normalized failure state is explicitly treated as no progress and escalated or returned to the user.
- Adds `RecoveryObjective` carrying the live self-model context and original run/task parentage.
- Adds `FailureSupervisor`: classify -> gather self-model -> choose policy -> run bounded recovery -> verify original failure -> resume original task only after verification.
- L3 code repair is routed through the `RecoveryTaskRouter` abstraction whose contract requires creating work through the existing Universal Task Kernel; no second planner exists.
- Recovery success is impossible without `RecoveryVerifier` returning a passing `RecoveryVerification`.

### Owner Mode

- Adds `owner.recovery.actuate` as a self-model capability supplied by the real Owner runtime provider.
- It reports unavailable/additional-authority/approval-required states from real Owner runtime state.
- It is not a Runner tool and is not automatically authorized.
- `RecoveryDecision` carries required authority so the actuator boundary can request/deny approval rather than silently escalating.

### Recovery host / self-repair seam

`lib/product/recovery/recovery_host.dart`

- Adds current, last-known-good and candidate version identities, health, startup attempts, crash-loop detection, candidate lifecycle and preserved failure evidence.
- Adds independent `KristinRecoveryHost` contract: stage -> qualify -> activate -> post-activation verify -> rollback.
- `StagedSelfRepairCoordinator` automatically rolls back a candidate that fails pre-activation qualification or post-activation health.
- The contract explicitly forbids blind in-place overwrite of the currently executing primary process.

### Chat / self-awareness

`lib/product/chat_action_dispatcher.dart`

- Adds optional read-only `ChatSelfAwarenessGateway` so existing action-gateway fakes remain source-compatible.
- Production `ProductRuntimeChatGateway` implements it from `buildProductSelfModel`.
- `ChatActionDispatcher.selfAwareness` returns the live bounded model.
- `explainCapabilityAvailability` gives a truthful, live reason for blocked/unavailable capabilities.
- The self-awareness read path does not call effect authorization because it performs no effect; authority in the result is descriptive only.

### Persistence and observability

- `FailureJournal` is the durable persistence contract for significant failures/recovery attempts.
- `RecoveryEventSink` is the observability contract for failure detected/classified, recovery strategy/start/escalation/verification/failure and task-resumed events.
- These are deliberately adapters to the existing workflow/evidence/event infrastructure rather than a second telemetry architecture. The landing worker should bind/verify the concrete repository adapters against the latest integration branch, because those repository/event contracts are active integration surfaces and were intentionally not qualified in this implementation worker.

## Runtime flows

### Normal task flow

User -> One Kristin Chat -> understanding -> task specification -> complexity router -> Universal Task Kernel. Chat/runtime builds a live self-model for the session. `KernelRequestContext` intersects catalog knowledge with live availability before understanding/planning. The plan compiler then derives the exact permission/tool contract. Authority remains downstream of planning.

### Self-awareness query flow

Chat -> `ChatActionDispatcher.selfAwareness` -> production `ChatSelfAwarenessGateway` -> `buildProductSelfModel` -> authoritative `ProductRuntimeSnapshotProvider` + registered subsystem capability providers -> `KristinSelfSnapshot` -> bounded model/user rendering.

Focused questions such as “Why is Browser unavailable?” use the same snapshot and availability reason rather than model training knowledge.

### Failure flow

Runtime producer creates a structured, redacted `FailureEvent` and supplies available evidence/checkpoint references -> `FailureSupervisor` persists it -> classifies -> captures live self-model -> chooses a bounded recovery decision -> emits structured recovery events.

### Recovery flow

L0/L1/L2 use a governed `RecoveryActuator`. L3 creates a `RecoveryObjective` through `RecoveryTaskRouter`, which is required to use the existing Universal Task Kernel and preserve original run/task parentage. L4 crosses the independent `KristinRecoveryHost` seam. Every path must verify the original failure condition. Only passing verification permits original-task resumption.

## Authority boundary

1. **Knowledge** — `CapabilityDescriptor`: what Kristin/application capabilities exist.
2. **Availability** — `CapabilityAvailability`: whether each known capability can work in the current runtime and why not.
3. **Authority** — existing permission/Owner authority systems plus the self-model’s descriptive required/current-authority projection. Self-model state never grants authority.
4. **Execution tools** — `availableToolNames` / compiled work-item tools. Coordinator capabilities such as create-project, Browser coordination and Owner recovery are not converted into Runner tools.

The model may know more than a work item may execute.

## Files changed

### Self-model / capabilities / runtime state
- `lib/product/self_awareness/capability_self_model.dart`
- `lib/product/product_runtime_self_awareness.dart`

### Task kernel
- `lib/product/task_kernel/task_kernel.dart`

### Failures / recovery / checkpoints
- `lib/product/recovery/failure_recovery.dart`

### Recovery-host / self-repair seam
- `lib/product/recovery/recovery_host.dart`

### Chat/UI-facing application service
- `lib/product/chat_action_dispatcher.dart`

### Persistence / observability
- Contracts live in `failure_recovery.dart`; concrete binding to the latest workflow/event repositories is a landing-stage integration item, not a new persistence subsystem.

## Intentionally not run

Per worker strategy, this worker did not spend the task on qualification. Specifically not run:

- full Flutter test suite;
- full Dart/Flutter analyzer qualification;
- platform CI;
- source-manifest/governance receipt repair;
- generated qualification artifacts;
- migration compatibility qualification;
- integration-branch reconciliation;
- release/landing gates.

No merge to `main` or the One-Kristin integration branch was performed.

## Focused tests expected from landing worker

- Provider registration rejects duplicate provider IDs and duplicate capability IDs.
- Capability descriptor serialization remains deterministic and bounded.
- Browser unavailable/available truth follows real P3 handle state.
- Owner availability distinguishes missing runtime, non-eligible authority service and approval-required state.
- No selected project blocks project-scoped capabilities with a truthful reason.
- No selected model blocks substantial model-backed capabilities.
- Kernel live capability intersection removes blocked capabilities without adding Runner tools.
- Coordinator capabilities remain absent from Runner tool contracts.
- Failure signature normalization collapses volatile-only differences.
- Recovery policy stops identical ineffective attempts and escalates materially.
- Attempt budget prevents infinite repair loops.
- L3 recovery preserves original run/task parentage.
- Recovery cannot report success before verification.
- Failed verification does not resume the original task.
- Successful verification resumes the original task exactly once.
- Owner recovery never runs without the required real authority/approval.
- Recovery host rolls back failed candidate qualification and failed post-activation health.
- Chat self-awareness uses runtime state and does not authorize effects.
- Snapshot bounds prevent unbounded project/run/failure history injection.
- Redaction remains effective on failure messages, stack/evidence and emitted events.

## Compatibility / landing risks

- The convergence branch is active; repository/run/event/authority APIs may have moved by landing time. Reconcile concrete persistence/event adapters against the live target.
- `ProductRuntimeSnapshotProvider` deliberately uses canonical project/run repositories and public Browser/Owner handles; analyzer qualification should confirm current field names and enum shapes after reconciliation.
- `chat_action_dispatcher.dart` gained imports and an optional production-only self-awareness interface. Verify all downstream package/source manifests if the repository governs Dart source lists.
- No schema migration is introduced by these files. If durable FailureEvent/RecoveryAttempt storage cannot map cleanly onto the existing workflow/evidence repository, add a migration during landing rather than creating a parallel store.
- Verify platform-specific Browser/process/Owner availability logic on Windows/macOS/Linux packaging; the model must report unsupported/degraded truth rather than generic support.
- The landing worker should wire the concrete `FailureJournal`, `RecoveryEventSink`, `RecoveryTaskRouter`, `RecoveryActuator`, and `RecoveryVerifier` adapters at the latest runtime failure boundaries and add focused tests there before qualification.

## Landing warning

**Implementation is complete but unqualified. Do not merge directly. A dedicated landing worker must review, test, repair, qualify and integrate this branch.**
