# Kristin Combined Convergence + Self-Awareness — Authoritative Qualification & Main Landing Contract

Status: **READY FOR QWEN QUALIFICATION / REPAIR / INTEGRATION / MAIN LANDING**

Authority: **GPT Landing Worker**

Execution worker: **Qwen**

This document is the authoritative landing contract for the complete product state currently ready for qualification. It is intentionally written after implementation work finished and before qualification/landing work begins.

## 1. Exact immutable source

Qwen MUST treat the following branch/SHA as the immutable source input:

- Source candidate branch: `candidate/kristin-self-awareness-landing-source`
- Exact source SHA: `81091cdf615c8fe4a0e8382ec402b977ea2ea8c6`
- Source tree is a frozen snapshot of `feat/kristin-self-awareness-autonomic-recovery` at that exact SHA.
- Do not qualify a later moving implementation-branch head by accident.
- Do not modify the frozen source candidate branch.

Expected `main` at contract creation:

- `main`: `74515b89dd16a1084b40760bd482524cca5e1b2c`
- Commit: `fix(runner): harden coordinator-to-executor protocol boundary (#290)`

Before any final landing, Qwen MUST re-read the live `main` head. If `main` moved, Qwen must rebuild/rebase/reconcile the integration candidate against the new `main` and repeat final qualification. A SHA qualified against an old base is not automatically valid for a changed base.

## 2. What this candidate contains

This is a **combined product candidate**, not a self-awareness patch in isolation.

The frozen source contains the full One-Kristin convergence line plus the Self-Awareness / Autonomic-Recovery implementation layered on top.

Treat the candidate as one product state for qualification and landing.

Do NOT first land the stale One-Kristin draft PRs and then separately land self-awareness.

Historical draft PRs are reference/evidence only and are NOT authorized landing vehicles:

- PR #291 — `Converge Chat state and deferred protocol control flow`
- PR #300 — `Draft: qualified One-Kristin convergence candidate`
- PR #301 — `Draft: integrate qualified One-Kristin convergence`

Do not merge those PRs as part of this contract. After this combined candidate is successfully landed and verified on `main`, they may be closed as superseded with an explanatory note.

## 3. Required reading before edits

Qwen MUST read these files before changing source:

1. `docs/implementation-handoffs/kristin-self-awareness-autonomic-recovery.md`
2. `docs/implementation-handoffs/kristin-self-awareness-v2.md`
3. this authoritative landing contract

Also inspect the exact frozen candidate diff against live `main` before planning repairs.

Repository source and runtime truth override prose when they disagree. If a handoff is stale, record the discrepancy and use the actual source/runtime behavior.

## 4. Qwen's role

Qwen owns **all work from qualification through safe main landing**.

Qwen is allowed and expected to:

- create a fresh qualification/integration branch from the immutable source candidate;
- inspect the complete candidate versus live `main`;
- compile/analyze/test the candidate;
- run repository-native architecture/security/release/source-manifest/governance gates;
- run native/platform builds and E2E/smoke gates required by the repository;
- dispatch and validate hosted CI on the exact candidate SHA;
- repair compile, analyzer, test, integration, runtime-wiring, source-manifest, qualification, CI and compatibility defects discovered during landing work;
- add or repair focused tests where necessary to prove behavior;
- finish incomplete production wiring called out in the implementation handoffs where the architecture already requires that wiring;
- re-run qualification after material repairs;
- create/update a clean landing PR to `main` only from the final qualified integration branch;
- land the exact qualified SHA to `main` only when all mandatory gates are green;
- verify `main` after merge/landing;
- write a final landing report with evidence.

Qwen is NOT allowed to waive failures, redefine acceptance downward, or merge an unqualified SHA.

## 5. Required branch strategy

Qwen MUST NOT perform repair work directly on `main`.

Qwen MUST NOT modify the immutable source branch.

Recommended flow:

1. Fetch live refs.
2. Verify `candidate/kristin-self-awareness-landing-source` still points to `81091cdf615c8fe4a0e8382ec402b977ea2ea8c6`.
3. Verify live `main`.
4. Create a fresh working branch, suggested name:
   `integration/kristin-combined-qualified`
5. Start from the immutable source candidate and reconcile it against the current `main` using the repository's safe integration strategy.
6. Perform all qualification repairs only on that integration branch.
7. Every material repair creates a new candidate SHA and invalidates qualification evidence tied to an older SHA where relevant.
8. Final qualification must bind to one exact final SHA.
9. Only that exact final SHA may be landed.

No force-push to protected/shared landing refs unless repository policy explicitly requires and authorizes it. Prefer normal fast-forward/rebase/merge mechanics with exact-head guards.

## 6. Architectural invariants that MUST survive landing

The following are hard product invariants, not optional style preferences.

### 6.1 Knowledge / availability / health / authority / tools remain separate

Self-awareness must preserve the explicit hierarchy:

- capability knowledge != capability availability;
- availability != health;
- health != authority;
- authority != Runner tool allow-list;
- knowing a capability exists never grants permission to execute it.

### 6.2 USER CAPABILITY != EXECUTION TOOL

The coordinator-to-executor protocol fix on `main` must remain intact.

Coordinator capabilities such as project creation/modification/fix semantics must not leak into Runner as phantom executable tools.

The Runner may know enough task context to execute its compiled work, but its concrete executable tools remain the governed subset granted for that work item.

Any regression where a semantic/coordinator capability appears as an executable Runner tool is a hard stop.

### 6.3 Owner Mode never self-grants authority

Owner runtime presence/readiness may be known.

That does not imply Owner authority has been granted.

Self-awareness, recovery, historical recovery success, capability availability, or health observations must never manufacture an Owner grant.

### 6.4 Browser truthfulness

Browser-required capabilities must report real provisioning/health/availability state.

Do not claim Browser support merely because a descriptor exists.

### 6.5 Recovery requires verification

A repair is not successful because source changed or an actuator returned success.

The original failure condition must be objectively disproven or the intended acceptance condition must be re-established before recovery is marked successful and the parent/original task resumes.

### 6.6 Recovery is bounded and progress-aware

Do not allow repeated identical ineffective recovery attempts to consume unbounded model/runtime turns.

Materially unchanged evidence must cause strategy change, escalation, rollback, or user escalation rather than blind repetition.

### 6.7 L4 self-repair remains staged

Kristin must not blindly overwrite its currently executing installation/process with no independent rollback boundary.

Self-repair remains behind the staged recovery-host / last-known-good / candidate-health / rollback seam.

### 6.8 One authoritative Kristin session state remains intact

Do not regress the One-Kristin conversation/session convergence, durable takeover/steering behavior, continuation planning context, or truthful execution/activity projection that the combined branch inherits.

## 7. Self-awareness architecture that must be verified

Qualification must prove the implementation is real product wiring, not disconnected classes.

Verify at minimum:

- canonical capability descriptors are runtime/model readable;
- subsystem-owned capability providers participate in the self-model rather than requiring a parallel static catalog;
- capability availability includes truthful blockers/reasons;
- capability health is separate from availability;
- freshness budgets/probe intervals are honored;
- authority-sensitive state is re-observed rather than trusted indefinitely from cache;
- `ApplicationSnapshot`/equivalent uses authoritative domain/runtime state, not fragile UI-only state;
- epistemic provenance/confidence distinguishes observed/configured/inferred/cached/unknown information;
- `KristinSelfModelService`/equivalent maintains bounded live changes;
- the causal operational graph is observational and does not become an authority path;
- capability satisfaction paths explain prerequisites without implying they are granted;
- self-integrity invariants are actually evaluated and surfaced;
- recovery experience memory influences strategy without becoming authority;
- deterministic self-awareness queries use the same canonical self-model;
- continuous self-consistency probes publish durable truthful health/state observations;
- shared self-awareness runtime identity/lifetime is correct across lightweight gateway wrappers;
- shutdown/disposal ordering does not leave timers/listeners writing into closed journals/services.

## 8. Universal Task Kernel / planning integration — mandatory production check

The Task Kernel already accepts self-model planning context, but the implementation handoff explicitly warns that large production planning call sites may still reconstruct static capability state.

Qwen MUST inspect all real production planning entry paths.

The final landed product must not have a split where:

- Chat can answer self-awareness queries from the live self-model,
- but actual production planning still reasons from stale/static capability availability.

Every production planning path that needs capability state must consume the canonical live self-model planning context, or an explicitly equivalent bounded projection derived from it.

If any production planning path bypasses the live model, repair it and add coverage.

This is a hard landing requirement.

## 9. Failure/recovery runtime binding — mandatory production check

The implementation handoff calls out remaining application-wide adapter/binding risk around equivalents of:

- `FailureJournal`
- `RecoveryEventSink`
- `RecoveryTaskRouter`
- `RecoveryActuator`
- `RecoveryVerifier`

Qwen MUST determine from current source which of these remain abstract/unbound at real runtime failure boundaries.

Do not mark the feature landed merely because recovery domain classes compile.

At minimum, meaningful product/runtime failures must be able to enter structured recovery flow through the actual runtime composition where automatic recovery is intended.

Verify the real flow conceptually behaves as:

failure evidence
→ structured failure event
→ relevant live self-model snapshot
→ bounded recovery policy
→ Universal Task Kernel / existing repair architecture
→ governed authority/actuation
→ verification
→ original-task continuation OR rollback/escalation.

If the source intentionally leaves a capability staged/not-yet-enabled, it must be truthful and safe. Do not fabricate automatic recovery for unsupported boundaries.

## 10. Operational state/probe checks

Pay special attention to the follow-up commits after the v2 handoff, including durable self-state/probe publication.

Verify:

- probe observations update the authoritative self-state projection expected by planning/query consumers;
- stale probe state expires according to freshness rules;
- rapid Browser/Owner transitions do not leave contradictory availability/health/authority state;
- model/provider discovery state does not remain falsely available after provider changes;
- event-driven refresh does not recurse into execution or cause feedback loops;
- self-consistency monitoring is bounded and can shut down cleanly;
- capability state changes are observable without becoming hidden authority grants.

## 11. Qualification requirements

Use repository-native authoritative commands/workflows rather than inventing a parallel test recipe.

The final candidate must pass every mandatory gate that applies to `main` landing, including all gates currently enforced by the repository and CI configuration.

At minimum, Qwen must establish evidence for the following categories.

### Local / deterministic qualification

- canonical formatting checks;
- Dart/Flutter analyzer with repository-required fatal warning/info behavior;
- full Flutter/Dart test suite, not only focused new tests;
- focused new/changed self-awareness and recovery tests;
- One-Kristin session/takeover/continuation tests;
- Runner coordinator/executor protocol-boundary tests;
- architecture contract gates;
- security/threat/permission/authority gates;
- source manifest / deterministic inventory gates;
- release validator / release-source gates;
- migration/schema checks if schema changed;
- relevant Python/tool tests for repository qualification tooling;
- native/platform build checks required by the repo;
- E2E/smoke checks required by the repo.

### Hosted exact-SHA qualification

Final hosted qualification must run against the **exact final integration SHA**.

Require all repository-required hosted checks and all required operating systems. The previous repository standard has included Ubuntu, Windows, and macOS; use the current live workflow as authority.

Do not treat checks from an ancestor SHA as evidence for a repaired descendant SHA.

If a workflow mutates/generated source or advances the branch, the resulting new exact head must itself be the final qualified SHA or must be requalified according to repository policy.

## 12. Tests Qwen should add/repair where coverage is missing

Do not add tests mechanically if equivalent coverage already exists. Inspect first.

Coverage should mechanically protect at least:

- capability knowledge vs availability vs health vs authority separation;
- coordinator capability never exposed as Runner tool;
- Owner readiness never becomes Owner grant;
- unavailable capability explains blocker and minimum satisfaction path;
- stale knowledge/freshness budget behavior;
- provider/model/browser/owner availability transitions;
- self-model event refresh and bounded change history;
- integrity invariant violations;
- self-awareness deterministic query answers from live state;
- self-consistency probe success/failure publication;
- structured FailureEvent creation/redaction;
- repeated recovery signature/no-progress escalation;
- recovery history does not grant authority;
- recovery verification required before success;
- original-task continuation after verified recovery;
- rollback/escalation after unverified/failed recovery;
- shutdown ordering / monitor disposal;
- all production Task Kernel planning paths receive live self-model context;
- real runtime failure boundaries route into recovery where intended.

## 13. Integration-repair policy

Qwen may repair defects discovered during qualification.

Repairs should preserve architecture and be as small as practical, but correctness beats artificially tiny diffs.

Allowed repair categories include:

- compile/null-safety/signature breakage;
- stale interface implementations;
- missing runtime composition bindings;
- missing self-model planning context propagation;
- incorrect lifecycle/disposal behavior;
- race/freshness/probe defects;
- failing or missing focused tests;
- source manifest/inventory updates required by real source changes;
- analyzer/formatter issues;
- platform compatibility defects;
- CI workflow compatibility required to prove the candidate;
- deterministic release/governance artifacts required by repository policy.

Do NOT use qualification as an excuse to add unrelated product features.

If a large unrelated defect is discovered, record it separately unless it blocks the candidate's safe landing.

## 14. Exact-SHA rule

This rule is absolute:

> The SHA merged to `main` must be the exact SHA that passed final required qualification.

If Qwen changes any product/test/qualification-relevant file after final evidence was collected, final qualification is stale.

Re-run the required gates against the new exact SHA.

If `main` moves after qualification but before merge, re-integrate/rebase/reconcile and requalify the new exact candidate SHA.

Never use “the previous SHA was green and this change is small” as a waiver.

## 15. Main landing rule

Qwen may land to `main` only after all of the following are true:

1. Frozen source identity was verified.
2. Live `main` was resolved.
3. Integration candidate is cleanly based/reconciled against live `main`.
4. Required runtime/planning/recovery wiring gaps are resolved or truthfully proven not applicable.
5. Local qualification is green.
6. Hosted required-platform qualification is green on the exact final SHA.
7. No unresolved required review/check remains.
8. No authority/Runner boundary regression exists.
9. No known failing mandatory test/gate is waived.
10. The final PR head equals the exact qualified SHA.
11. `main` has not changed since the final integration/qualification basis, or the candidate was rebuilt and requalified after the change.

Then Qwen may merge/land using the repository-approved method.

## 16. Hard-stop conditions

Qwen MUST NOT land when any of these is true:

- compile/analyzer failure;
- mandatory test failure;
- security/authority/architecture gate failure;
- required source-manifest/release-validator failure;
- missing required hosted OS/platform result;
- candidate head differs from qualified SHA;
- `main` moved after qualification and candidate was not requalified;
- coordinator capability leaks into Runner tools;
- Owner capability/state self-grants authority;
- recovery can mark success without verification;
- self-repair can overwrite the running product without staged rollback boundary;
- production planning bypasses the canonical live self-model where self-awareness is required;
- recovery is advertised as automatic at a runtime boundary that is not actually wired;
- unresolved merge conflict is hidden by dropping behavior;
- qualification evidence belongs only to an older/stale candidate;
- a failure is being ignored merely to finish the landing.

If blocked, stop landing, preserve evidence, state the exact blocker, and continue repair only when it can be done safely on the integration branch.

## 17. Post-landing verification

After merge/landing, Qwen MUST verify the actual `main` state rather than assuming the merge completed correctly.

Record:

- final qualified integration SHA;
- resulting `main` SHA;
- merge method / PR number;
- exact hosted workflow run IDs/URLs or equivalent evidence;
- required OS/platform conclusions;
- analyzer/test/release/source-manifest evidence;
- key repairs made during qualification;
- confirmation that the source candidate branch was not modified;
- confirmation that old PRs #291/#300/#301 were not used as landing vehicles;
- post-merge smoke/health result;
- any intentionally deferred non-blocking follow-up.

If post-merge verification fails, treat it as a real landing incident and repair/revert according to repository policy. Do not declare success until `main` is healthy.

## 18. Historical PR cleanup

Only after the combined candidate is successfully verified on `main`:

- PR #291 may be closed as superseded by the combined qualified landing;
- PR #300 may be closed as superseded checkpoint/audit history;
- PR #301 may be closed as superseded stale candidate.

Preserve their historical evidence/comments. Do not rewrite history merely for cosmetic cleanup.

## 19. Required final report

Qwen's final response/report must include:

- source frozen SHA;
- initial and final `main` SHA;
- integration branch and final candidate SHA;
- all source/test/runtime repairs made after the frozen input;
- tests run locally and their result;
- hosted qualification evidence and exact SHA binding;
- runtime self-model/planning-context wiring conclusion;
- failure/recovery runtime-binding conclusion;
- authority/Runner boundary conclusion;
- PR number and merge method;
- post-landing verification result;
- disposition of historical PRs;
- remaining non-blocking follow-ups, if any.

## 20. Definition of done

This assignment is complete only when:

- the complete One-Kristin + Self-Awareness/Autonomic-Recovery product state has been qualified as one candidate;
- defects discovered during qualification have been repaired on the integration branch;
- final required local and hosted gates pass on one exact final SHA;
- that exact SHA is safely landed to `main`;
- `main` is verified healthy afterward;
- no safety/authority boundary was weakened to make qualification pass;
- a durable final landing report exists.

If these conditions cannot be satisfied, the correct result is **BLOCKED / NOT LANDED with exact evidence**, not a partial or waived merge.
