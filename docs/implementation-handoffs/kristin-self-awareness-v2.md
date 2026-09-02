# Kristin Self-Awareness v2 — Implementation Handoff

Branch: `feat/kristin-self-awareness-autonomic-recovery`

V2 started from branch head: `98bf52a8a2902feff90ed5f9699a0efec827bef7`.

This worker extends the first self-awareness/autonomic-recovery architecture with the ten follow-on improvements requested after the initial implementation. The branch remains isolated and must not be merged without the separate qualification/landing worker.

## What changed

### 1. Epistemic provenance and confidence

`lib/product/self_awareness/capability_self_model.dart` now models how Kristin knows an operational fact instead of only storing the fact:

- `KnowledgeEvidenceKind`: observed/configured/inferred/cached/unknown.
- `ObservationConfidence`: certain/high/medium/low/unknown.
- `KnowledgeEvidence`: source, observation time, expiry, confidence and detail.
- `ApplicationSnapshot.knowledgeEvidence` records authoritative sources for platform, projects, runs, models, Browser, Owner Mode and the authority projection.

This makes stale/inferred knowledge mechanically distinguishable from fresh observation.

### 2. Event-driven self-model changes

`KristinSelfModelService` now owns a bounded live change stream and retains recent `SelfModelChange` records. `ProductSelfAwarenessRuntime` subscribes to the canonical `ProductRuntime.eventStream`, debounces durable events and refreshes the self-model after meaningful runtime transitions.

`CapabilityStateChange` records availability/health transitions without turning the event stream into an execution path.

### 3. Causal operational graph

New file `lib/product/self_awareness/operational_self_awareness.dart` adds the bounded `CausalStateGraph` with typed nodes and evidence-bearing edges for actions, state changes, observations, failures and recoveries.

`ProductRuntimeChatGateway` wraps canonical runtime calls through `ProductSelfAwarenessRuntime.observeOperation` only after the existing `ChatActionDispatcher` authority decision. The graph is observational: it does not authorize or execute effects by itself.

### 4. Counterfactual capability satisfaction paths

`CapabilityAvailability` now carries a structured `satisfactionPath`. `CapabilitySatisfactionStep` describes the minimum condition that would make a blocked capability usable, including explicit authority requirements without implying that authority has been granted.

Concrete ProductRuntime bindings cover project selection, model/provider discovery, Browser provisioning/probing and Owner Mode readiness plus explicit authority.

### 5. Self-integrity invariants

`SelfIntegrityMonitor` evaluates explicit invariants over a live snapshot. The default set protects:

- coordinator capability != direct Runner tool;
- Owner capability != self-granted Owner authority;
- Browser-required capability truthfulness;
- selected project membership in the current project snapshot;
- failing capability health != planner usability.

The shared ProductRuntime self-awareness runtime evaluates these invariants on snapshots and runtime-event refreshes and exposes a read-only integrity report through Chat.

### 6. Recovery experience memory

`lib/product/recovery/failure_recovery.dart` now includes:

- `RecoveryExperience`;
- `RecoveryExperienceOutcome`;
- `RecoveryExperienceStore`;
- bounded `InMemoryRecoveryExperienceStore`;
- an environment fingerprint derived from the current self-model.

`RecoveryPolicy` consults prior same-signature/same-environment experience and escalates instead of blindly repeating a strategy that previously failed without material progress. `FailureSupervisor` records blocked, actuation-failed, verification-failed and verified outcomes.

Recovery memory never converts historical success into authority.

### 7. Health separated from availability

`CapabilityHealth` and `CapabilityHealthState` are separate from `CapabilityAvailability`. `KnownCapability.operationallyUsable` requires both usable availability and acceptable health. A provisioned facility may therefore be known/available while degraded or failing.

Browser and Owner runtime providers expose health independently from availability/authority.

### 8. Freshness budgets

Every `CapabilityDescriptor` now declares a `freshnessBudget` and `probeInterval`. Availability and health caches honor those budgets. Owner-sensitive capability truth uses `Duration.zero`, forcing execution-time re-observation rather than trusting cached authority-sensitive state.

`SelfModelPlanningContext` surfaces bounded freshness warnings.

### 9. Dedicated self-awareness reasoning API

`SelfAwarenessQueryService` provides deterministic read-only queries over the same self-model:

- capability explanation;
- structured requirements / why blocked;
- minimum satisfaction path;
- capability relevance for an objective;
- what changed since a timestamp.

`ChatSelfAwarenessGateway` / `ChatActionDispatcher` expose these queries plus planning context, integrity and explicit probe execution. This is not a second planner and grants no authority.

### 10. Continuous self-consistency probes

`SelfConsistencyMonitor` and callback probes continuously re-check operational truth after the shared self-aware Chat gateway becomes active. The ProductRuntime composition currently probes:

- real Browser runtime startup/shutdown health;
- Owner runtime readiness/isolation/completion eligibility;
- selected model presence in fresh provider discovery.

The monitor writes probe observations back as capability health and records causal observations. It has no recovery actuator or authority-granting API.

## ProductRuntime binding

`lib/product/product_runtime_self_awareness.dart` now provides one shared `ProductSelfAwarenessRuntime` per `ProductRuntime` using an `Expando`. This is important because Chat constructs lightweight gateway wrappers repeatedly; the shared runtime preserves change history, causal history, health observations and probe schedules across those wrappers.

The adapter also corrects the first implementation's run-state projection from the invalid `run.status` access to the actual `RunRecord.state` field.

## Boundaries preserved

The following architectural constraints remain explicit:

1. Capability knowledge is not capability availability.
2. Availability is not health.
3. Availability/health are not authority.
4. Authority is not the Runner tool allow-list.
5. Coordinator capabilities remain orchestration semantics and are not exposed as direct Runner tools.
6. Owner runtime presence never implies an Owner grant.
7. Recovery still requires verification before original-task continuation.
8. L4 self-repair remains behind the staged recovery-host boundary.

## Files added/modified in this v2 increment

Added:

- `lib/product/self_awareness/operational_self_awareness.dart`
- `docs/implementation-handoffs/kristin-self-awareness-v2.md`

Modified:

- `lib/product/self_awareness/capability_self_model.dart`
- `lib/product/product_runtime_self_awareness.dart`
- `lib/product/chat_action_dispatcher.dart`
- `lib/product/recovery/failure_recovery.dart`

## Qualification intentionally not performed

Per the implementation-worker assignment, this increment does **not** run or repair:

- Dart analyzer;
- unit/integration tests;
- CI workflows;
- release qualification;
- merge/rebase/landing work.

The branch is implementation-complete for these ten improvements but remains unqualified until a separate qualification worker proves compilation, behavior and integration against the current repository head.

## Landing risks / follow-up integration

The original v1 handoff remains authoritative for the pre-existing landing risk: concrete application-wide `FailureJournal`, `RecoveryEventSink`, `RecoveryTaskRouter`, `RecoveryActuator` and `RecoveryVerifier` adapters still need to be bound at the final runtime failure boundaries and qualified end-to-end.

Likewise, the task-kernel type already accepts `SelfModelPlanningContext`, and Chat now exposes a live planning-context query, but existing large ProductRuntime/Studio planning call sites should be qualified to ensure every production planning path supplies that live context rather than reconstructing static capability availability. This worker did not rewrite unrelated large UI/runtime files merely to hide that integration boundary.

A qualification worker should pay special attention to:

- Dart null-safety/signature compatibility for the expanded optional Chat self-awareness interface;
- provider discovery latency and probe cadence;
- shutdown ordering for the self-consistency timer versus `EventJournal` close;
- capability freshness behavior under rapid Browser/Owner transitions;
- recovery-experience persistence choice if strategy memory must survive application restarts;
- end-to-end task-kernel population of the live self-model.

## Landing warning

Do not merge this branch directly to the landing branch on the strength of this implementation handoff alone. Run the repository's qualification workflow in a separate worker, fix compile/test/integration defects there, and land only after authority, Runner-tool separation, recovery verification and rollback behavior are proven.