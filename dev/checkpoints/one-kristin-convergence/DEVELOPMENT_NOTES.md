# Development notes — recovered head dd2f46ba6df3fb25adc2c8c927e807147b8f16f2

## Strategy

Development-first remains the hard boundary. The bundle mutates only a supplied local source worktree. No helper script stages, commits, creates branches, pushes, edits PRs, merges, or changes remote GitHub state.

## Repository findings that shaped the implementation

- `TaskContract` and Runner are genuinely project-bound, so Research received a task-family-specific executor instead of a fake project.
- `ResearchTaskFamilyPlanner` already existed; execution/restart/archive semantics were the missing pieces.
- Search itself is project-free. Both graph Research and direct Research now treat a selected project only as optional archive context, re-check that context at write time, and preserve grounded answers when optional archive storage fails while auditing the warning.
- Provider delta support already existed; ordinary Chat previously failed to project it truthfully.
- Protocol v3 already parsed user takeover, wait, and delegate; the bundle adds durable coordinator semantics rather than another parser.
- Raw run steering was memory-only. It is now semantic/durable, and topology-changing direction reconciles the canonical plan rather than being injected as prose.
- An awaiting-approval run has no Runner transaction, so it needs a separate idle continuation path; an executing run continues to use the between-work-item transaction boundary.
- The existing `PlanReconciler` is reused for continuation: completed still-valid work is preserved, contradicted work is explicitly invalidated, and new work is added.
- New Research/wait/delegate/steering paths remain authority-neutral. P1/P2/ordinary contract approval remain the effect-authority boundaries.
- PR #290's protocol/recovery correctness work was already present and was removed from the remainder rather than reimplemented.
- `pubspec.lock` is tracked and currently has no timezone package entry. Real qualification first proves the installed toolchain with `tool/toolchain_lock_test.py`, then runs `flutter pub get`, and fails closed unless `timezone` resolves as direct main `0.10.1`.
- The exact V71-R12 source gate is intentionally deferred to the Git phase because its own contract requires `git diff --exit-code` and a clean tracked working tree before the SDK gate.

## Bounded delegate policy

Protocol-v3 `delegate` is implemented only as one-level model-only child deliberation for `reviewer`, `planner`, and `analyst`. Children have no tools, no permission grants, no nested delegation, share cancellation, count against the parent model-request budget, and return coordinator guidance only. Successful identical calls replay; terminal identical failures also converge instead of burning repeated budget.

## Failure presentation

`ProductErrorNormalizer.userMessage` remains the human-facing summary. The latest UI slice keeps the separately redacted technical exception string only for an explicit expandable Details surface, so useful diagnostics are not lost but raw implementation wording is not the primary message.

## Qualification improvements

The bundle now includes `validate_anchor_composition.py`, which runs the real transformer functions against a synthetic recovered-head surface in exact slice order; `validate_orchestrator_smoke.py`, which permanently executes the actual 20-step orchestrator in an isolated temporary Git checkout; `validate_generated_dart_sources.py`, which checks full generated Dart units for balanced lexical structure, duplicate top-level declarations, and direct imports for non-transitive dependencies such as `Sha256`, `EntityRepository`, live-run signals, and timezone APIs; and `qualify_real_checkout.py` plus a fail-closed self-test for real-checkout gate sequencing.

Qualification found several real packaging/contract defects: scope-changing steering targeted a generic `authorityBearing` tail that occurs twice; a later repack accidentally regressed the all-slices orchestrator back to only 8 entries; and the bundle manifest no longer covered the full checkpoint. The steering anchor is now specific, the orchestrator is restored to an AST-validated literal 20-slice order, and the manifest validator requires exact bundle file scope and SHA-256 digests. The same pass fixed a deterministic-time leak where device-local time bypassed the injected clock and aligned bare `/time` with its declared device-local behavior.

The generated-test qualification layer then caught an extra parenthesis in the truthful-streaming test, a stale/nonexistent `run_steering_semantic_test.dart` handoff between steering slices, and a timestamp-wait assertion that contradicted the later bounded-delegate implementation. Those are repaired, all 19 complete generated tests pass lexical/source-shape checks, and high-risk final composed source contracts are now validated explicitly.

## Verification limitation

This environment lacks the full checkout and Dart/Flutter SDK. Python transformer syntax, bundle structure/order/static contracts, synthetic anchor composition, generated-Dart lexical shape, and the no-project-Git-write rule are validated here. Dart formatting/analyzer/tests on the complete repository remain mandatory before the Git phase.

`SOURCE_MANIFEST.sha256` remains intentionally untouched until exact formatted/tested source bytes exist.
## Latest pre-analyzer closure

The final pre-analyzer audit closed several repository-level integration edges that lexical checks alone would miss:

- `test/product/source_contract_test.dart` is an exhaustive analyzer-visible `lib/` inventory, so the `utility.time` slice now registers `lib/product/utility_time.dart` explicitly alongside the other new production units.
- `config/toolchains.lock.json` pins the SHA-256 of `pubspec.lock` and includes that declaration in `declaredInputFingerprint`. Real-checkout qualification now validates the old locked toolchain first, runs Pub, verifies direct `timezone 0.10.1`, updates the governed lockfile hash plus canonical fingerprint, and re-runs the toolchain-lock gate before analyzer/tests.
- generated `run_steering.dart` and the final steering/Research restart tests had imports that became unused after later slices rewrote their semantics; those dead imports are removed so `flutter analyze --fatal-warnings` does not fail on bundle-owned hygiene.
- the final scope-steering boundary now runs after deterministic project verification and immediately before the normal transaction commit. Between-item boundaries remain available for earlier scope changes. If reconciliation leaves no enabled implementation work, the continuation receives one hidden read-only verification bridge so the normal Runner final-verification path still executes instead of compiling an empty plan or redoing preserved work.
- beginning a new Chat operation now clears any previous expandable technical-error projection, preventing diagnostic details from one failure from leaking into a later operation.

The synthetic composition fixture now preserves the recovered final-verification region, and the generated-test validator asserts the ordering `deterministic verification -> final steering boundary -> normal commit` directly.
## Checkpoint integrity/type-closure repair — 2026-08-30

A fresh-from-bytes rerun caught tooling drift that had reappeared in the portable checkpoint: the orchestrator and top-level validator had reverted to older forms, and the real-checkout qualifier had lost the toolchain/Pub/governed-lock steps even though its self-test still described them. The current checkpoint restores the literal 20-slice orchestrator, AST-based order validation, exact 34-payload manifest validation, and the qualifier sequence `locked toolchain -> Pub -> timezone 0.10.1 -> governed lock/fingerprint sync -> locked toolchain recheck`.

The synthetic worktree fixture now distinguishes new whole-file artifacts from recovered-head files that a slice replaces wholesale, so it no longer pre-creates `semantic_durable_steering_test.dart` or incorrectly omits the pre-existing `run_steering.dart`. A direct API/import audit also found that the steering-continuation code in `product_runtime.dart` uses `CompletedTaskRecord`, `PlanningRoute`, and `UniversalTask` directly; the slice now imports `task_kernel/plan_reconciliation.dart` and `task_kernel/universal_task_plan.dart` explicitly rather than relying on non-existent transitive Dart imports.

## Final qualification hardening — 2026-08-30

- Real-checkout qualification now treats Dart formatting as toolchain-sensitive: even a `--format`-only run executes the repository's locked Python/Flutter/Dart preflight before changing source bytes. Pub/analyzer/tests remain opt-in and are not run for format-only qualification.
- After `flutter pub get`, every package that already existed in `pubspec.lock` must keep the same resolved version. The only permitted solver delta is the dependency closure required by the newly pinned direct `timezone 0.10.1`; unrelated upgrades/downgrades fail closed before the governed toolchain lock or source manifest is refreshed.
- Both Research synthesis paths now use the existing `AgentPromptInjectionGuard` with `AgentContextSource.web`. Retrieved snippets/excerpts are rendered as untrusted web-data envelopes with `authorityBearing: false`; source URL/hash/timestamp metadata is retained where available, and retrieved text is never presented as coordinator authority.

## Recovered-head first-touch/API closure — 2026-08-30

The final offline pass compared the guarded first-touch anchors for the highest-risk transformed files against exact recovered head `dd2f46ba6df3fb25adc2c8c927e807147b8f16f2`, not only against synthetic maximal anchors. ProductRuntime, RunCoordinator, Chat Studio/actions, storage wiring, task-kernel/understanding, deferred interaction, Pub dependency, and exhaustive source-inventory anchors were all found on the recovered source.

External call surfaces were also checked directly: project-free `searchWeb(query:, count:)`, the `ResearchSource` evidence fields, model cancellation/text-delta callbacks, `CancellationSignal`, and the agent-context prompt-injection guard match the names/types used by the bundle. During this pass the direct single-fact Research path was corrected to actually use the same untrusted-web envelope already documented for graph Research, so the implementation and qualification report now agree.
