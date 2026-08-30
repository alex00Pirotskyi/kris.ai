# Development qualification report

Checkpoint basis: recovered head `dd2f46ba6df3fb25adc2c8c927e807147b8f16f2`.

## Checks completed in this sandbox

- Python compilation of every transformer/validator.
- Guarded 20-slice application order validation.
- Static architecture-contract checks for Research, steering, wait/delegate, continuation, authority and failure projection.
- No Git write subprocesses in the development bundle.
- Synthetic cross-slice anchor composition across every modeled overlapping source file.
- Full generated Dart-unit lexical checks for Research execution records/executor, steering records/service, delegation record, command planning context, and `utility.time`.
- Lexical/source-shape checks for all 19 complete Dart test artifacts created by the bundle, plus high-risk final cross-slice source-contract checks.
- Permanent end-to-end smoke of the real 20-step orchestrator against a temporary synthetic recovered-head worktree; all slices apply successfully.
- Real-checkout qualifier self-test proving locked-toolchain-before-Pub ordering, exact timezone lock verification, external report placement, scoped formatting, full/focused Flutter invocation, and manifest-last behavior.
- Fail-closed qualifier test proving an earlier repository-gate failure leaves `SOURCE_MANIFEST.sha256` unchanged.

## Defects found and fixed during qualification

A checkpoint audit found that `apply_all_development_slices.py` had drifted back to an 8-slice `SLICES` list even though the bundle documentation and smoke test described 20. The orchestrator has been restored to the exact 20-slice order. `validate_development_bundle.py` now parses the literal `SLICES` assignment with Python AST and compares the exact ordered list, instead of relying on brittle raw-text positions.

The same audit found `BUNDLE_MANIFEST.sha256` was stale and omitted the newer qualification/recovery files. The standard bundle validator now requires an exact one-to-one file set (excluding the manifest itself) and exact SHA-256 digests before a checkpoint can pass.

`apply_scope_changing_steering_continuation.py` originally replaced a generic steering live-signal tail containing only `authorityBearing: false`. The generated `run_steering.dart` contains that tail in both the queued and applied signal blocks, so the guarded transformer correctly failed with two matches. The slice now anchors the queued signal through the adjacent `patch: instruction.patch.toJson()` line and changes only that event.

`utility.time` also had one determinism leak: named-zone conversion used the injected UTC clock, but the device-local answer called `DateTime.now()` directly. It now uses `_nowUtc().toLocal()`, and the generated test suite contains a regression asserting that the device-local path uses the injected instant too.

A second time-utility contract mismatch was also fixed: the capability declares bare `/time` as device-local time, while the parser previously recognized only `/time <zone>`. Bare `/time` now resolves to the local-device path and is covered by the parser regression test.

The real-checkout qualifier now runs `tool/toolchain_lock_test.py` before `flutter pub get`, writes that receipt outside the checkout, then requires Pub to lock `timezone` as a direct main dependency at exactly `0.10.1`. This prevents an arbitrary local Flutter/Dart SDK from silently rewriting the lockfile before qualification establishes the repository's supported toolchain.

The generated-test audit found and fixed three additional integration defects that would have escaped Python syntax checks: the truthful-streaming test had an extra closing parenthesis; the scope-continuation slice targeted a nonexistent `run_steering_semantic_test.dart` instead of the `semantic_durable_steering_test.dart` created by the earlier steering slice; and the timestamp-wait test still asserted that delegation was disabled even after the bounded-delegate slice enabled it. The final steering test now expects persisted `pendingReplan` semantics, the wait test owns only wait behavior, and the focused-test inventory uses the canonical steering filename.

A subsequent source-contract sweep also replaced stale textual assertions with strings actually owned by the final composed implementation (the steering replan boundary event/failure, nullable awaiting-approval source check, bounded delegate no-tool/no-authority prompt, and delegated-guidance authority warning). `validate_generated_dart_tests.py` now pins those high-risk final cross-slice contracts so later slices cannot silently invalidate earlier tests.

A final pre-analyzer type/state audit closed additional issues: `utility_time.dart` is now present in the repository's exhaustive analyzer-visible source inventory; the qualifier updates the governed `pubspec.lock` hash and recomputes `config/toolchains.lock.json`'s canonical `declaredInputFingerprint` after resolving `timezone 0.10.1`, then revalidates the toolchain lock; dead imports introduced or made stale by later steering/Research rewrites were removed; and Chat clears prior technical failure detail at the start of each new visible operation.

The steering continuation boundary was also corrected so the post-items scope check occurs only after deterministic project verification and before the normal commit. Reconciliation already disables preserved completed tasks, and the compiler executes enabled tasks only. When reconciliation therefore leaves zero enabled implementation tasks, the runtime now adds one hidden read-only verification bridge so the continuation still traverses the standard governed final-verification path without redoing preserved work. The synthetic fixture now contains the untouched recovered verification block and asserts this ordering explicitly.

## Still not proven here

- Dart formatting on the complete repository.
- `flutter analyze --fatal-infos --fatal-warnings`.
- Focused and full Flutter/product tests.
- Provider/model dogfooding.
- Tri-platform product gates and the prior Windows source-gate reproduction.
- Real `flutter pub get` / tracked lockfile resolution for the new timezone dependency.
- Canonical regeneration of `SOURCE_MANIFEST.sha256` after those local gates.
- The clean-tree `v71r12_exact_source_gate.py`; by repository contract this belongs after the later checkpoint commit, because it rejects any tracked diff before its SDK gate.

Those remain the final development qualification boundary before the separate Git phase.
## Latest checkpoint repair

A clean rerun of the checkpoint itself exposed three tool regressions before packaging: the orchestrator had fallen back to 8 slices, the top-level validator had fallen back to brittle text-order checks, and the real-checkout qualifier had lost its locked-toolchain/Pub/governed-lock closure. Those are restored and are now cross-checked by the orchestrator smoke and qualifier success/fail-closed tests.

The same pass corrected the synthetic fixture so files created by a slice remain absent until that slice runs, while recovered-head files replaced wholesale are still present. Finally, a direct Dart import audit against the recovered `product_runtime.dart` and Universal Task APIs found a real likely analyzer error: continuation code directly uses `CompletedTaskRecord`, `PlanningRoute`, and `UniversalTask` without direct imports. `apply_scope_changing_steering_continuation.py` now adds both `task_kernel/plan_reconciliation.dart` and `task_kernel/universal_task_plan.dart`, and the final composed-source validator requires those imports.

## Latest hardening checks

- PASS: format-only qualification proves the locked installed Python/Flutter/Dart toolchain before invoking Dart formatting and does not run Pub/analyzer/tests or refresh `SOURCE_MANIFEST.sha256`.
- PASS: qualifier rejects unrelated pre-existing `pubspec.lock` version churn after `flutter pub get`; governed toolchain-lock synchronization and source-manifest refresh do not occur on that failure.
- PASS: graph Research fetched evidence is wrapped through `AgentPromptInjectionGuard` / `AgentContextSource.web` with non-authoritative metadata before model synthesis.
- PASS: direct single-fact Research search snippets use the same untrusted-web envelope instead of raw snippet prose.
- PASS: standalone Python compilation, 20-slice synthetic orchestrator smoke, generated production-Dart shape, all 19 generated test shapes, and qualifier success/fail-closed self-tests remain green after these changes.

## Recovered-head anchor and API audit — 2026-08-30

A read-only audit against recovered head `dd2f46ba6df3fb25adc2c8c927e807147b8f16f2` verified the highest-risk first-touch anchors used by the guarded transformers in `product_runtime.dart`, `planning_runtime.dart`, Chat Studio/actions, `storage_security.dart`, `task_kernel`, `task_understanding.dart`, `agent_deferred_interaction.dart`, `pubspec.yaml`, and the exhaustive `source_contract_test.dart` inventory. The semantic steering queue/take-pending anchors and the storage repository-constructor/collection anchors are present on the recovered source rather than existing only in the synthetic fixture.

The same audit checked external method/type surfaces used by the new code. `ProductRuntime.searchWeb` is project-free and accepts `count`; `ResearchSource` exposes `url`, `title`, `contentHash`, `fetchedAt`, and `content`; `ModelGenerationRequest` exposes cancellation, cancellation-state, and text-delta callbacks; `CancellationSignal` exposes both `isCancelled` and a cancellation future; and `AgentPromptInjectionGuard` exposes the web/untrusted envelope used by both Research synthesis paths. This materially reduces first-apply and analyzer-signature risk, but it still does not substitute for Dart analysis on the complete checkout.
