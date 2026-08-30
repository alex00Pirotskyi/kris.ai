# One-Kristin development bundle

Guarded source-development checkpoint for `alex00Pirotskyi/kris.ai`.

Recovered source head: `dd2f46ba6df3fb25adc2c8c927e807147b8f16f2` (`feat/one-kristin-convergence`, PR #291).

This bundle performs **local source-worktree changes only**. It does not stage, commit, create branches, push, merge, edit PRs, or modify GitHub.

## Current implementation slices

`apply_all_development_slices.py` applies these 20 slices in reviewed order:

1. `apply_one_kristin_state_convergence.py` — remaining One-Kristin planning/understanding/active-request/project-process ownership convergence.
2. `apply_advanced_same_conversation.py` — Advanced opened from Kristin projects the same conversation and returns with `Back to Kristin` instead of owning a second normal-user composer.
3. `apply_semantic_slash_understanding.py` — free-text slash payload Understanding while the explicit slash capability remains deterministic.
4. `apply_blocking_clarification_loop.py` — blocking clarification stays on the same task specification and normal composer.
5. `apply_collision_safe_target_resolution.py` — exact target collisions fail closed instead of first-provider-wins.
6. `apply_truthful_conversation_streaming.py` — real provider deltas are projected when available; no fake post-completion typing animation.
7. `apply_deterministic_utility_time.py` — deterministic IANA timezone utility with one injected clock for both named-zone and device-local answers, plus an SDK-compatible timezone dependency.
8. `apply_project_free_research_execution.py` — canonical Research graphs execute outside the project-bound Runner with durable task/evidence records.
9. `apply_semantic_durable_steering.py` — in-flight user direction becomes durable semantic `TaskSpecificationPatch` state rather than memory-only raw prose.
10. `apply_protocol_v3_timestamp_wait.py` — bounded absolute timestamp waits persist, restart, and resume; opaque wait handles remain disabled.
11. `apply_bounded_protocol_v3_delegate.py` — one-level model-only reviewer/planner/analyst delegation with no child tools or new authority.
12. `apply_scope_changing_steering_continuation.py` — topology-changing steering replans/reconciles at verified work-item boundaries into a linked continuation run with fresh approval.
13. `apply_idle_steering_continuation.py` — scope changes before an awaiting-approval run starts retire that source immediately and materialize the same reconciled continuation without creating a workspace transaction.
14. `apply_research_restart_reconciliation.py` — interrupted Research task-family executions reconcile on startup and can be explicitly retried from persisted plan snapshots; optional archive context is revalidated.
15. `apply_research_optional_archive_guard.py` — direct single-fact Research also re-checks optional project archive context after the network request.
16. `apply_research_archive_degradation.py` — optional project knowledge archiving degrades to audited warnings instead of invalidating grounded direct or graph Research answers.
17. `apply_delegate_recovery_qualification.py` — repeated identical delegation converges; terminal child failures replay rather than repeatedly burning parent model budget; restart-interrupted model-only children get bounded recovery semantics.
18. `apply_continuation_handoff_activity_projection.py` — One-Kristin Chat follows linked continuation runs and Details shows concise canonical live activity while raw token deltas remain hidden from the activity list.
19. `apply_authority_convergence_qualification.py` — cross-boundary tests pin the existing P1/P2/ordinary permission services as the only authority surfaces for the new paths.
20. `apply_human_readable_failure_projection.py` — Chat shows normalized human failure summaries with separately expandable redacted technical detail.

PR #290's Runner/protocol correctness work is already present on the recovered head and is intentionally not duplicated.

## Apply to a real checkout

Inspect any individual diff first if desired:

```bash
python3 apply_scope_changing_steering_continuation.py /path/to/kris.ai --diff
python3 apply_idle_steering_continuation.py /path/to/kris.ai --diff
python3 apply_research_restart_reconciliation.py /path/to/kris.ai --diff
python3 apply_human_readable_failure_projection.py /path/to/kris.ai --diff
```

Then apply the complete checkpoint:

```bash
python3 apply_all_development_slices.py /path/to/kris.ai --apply
```

The orchestrator verifies the recovered Git head and refuses an already-dirty checkout through the first guarded slice unless explicitly overridden. The scripts make source-worktree edits only; they never stage/commit/branch/push.

## Real verification required after apply

Use the development-only qualifier. It writes its reports **outside** the checkout by default and never stages/commits/branches/pushes:

```bash
python3 qualify_real_checkout.py /path/to/kris.ai \
  --apply \
  --format \
  --repo-gates \
  --focused \
  --full-flutter \
  --refresh-source-manifest
```

Before dependency resolution **or Dart formatting**, the qualifier runs the repository's normal `tool/toolchain_lock_test.py` runtime check and writes its receipt outside the checkout. Only after the installed Python/Flutter/Dart toolchain is proven does it permit source formatting or, when Flutter qualification is requested, run `flutter pub get`. Pub must resolve `timezone` as a direct dependency at exactly `0.10.1`, and every package that already existed in `pubspec.lock` must retain its prior resolved version; unrelated solver churn fails closed. The qualifier then synchronizes the governed Pub-lock SHA/fingerprint, rechecks the toolchain lock, formats only changed Dart files, runs the reviewed local generator/workflow/Prompt-Studio source gates, `flutter analyze --no-pub --fatal-warnings --fatal-infos`, focused One-Kristin tests, the full Flutter suite, `validate_release --skip-tests`, and only then runs the repository's canonical `tool/p2_refresh_source_manifest.py`. If any earlier gate fails, the manifest is not refreshed. A checkout where the bundle was applied separately can use `--already-applied` instead of `--apply`; required source markers are verified first.

The focused set covers session convergence, Advanced continuity, semantic slash Understanding, clarification, target collisions, truthful streaming, deterministic time, Research execution/restart/archive behavior, durable steering/continuation, wait/delegate/recovery, authority convergence, activity projection, and error-detail presentation.

Both graph and direct model-backed Research pass retrieved web text through the existing `AgentPromptInjectionGuard` as `AgentContextSource.web` with `authorityBearing: false`. Graph evidence retains URL/content-hash/fetch-time metadata; direct search snippets retain title/URL metadata. The model receives these as untrusted evidence envelopes, never as coordinator instructions or authority.

## Source manifest

Do **not** hand-edit or guess `SOURCE_MANIFEST.sha256`. Regenerate it only from the exact formatted/tested checkout using the repository's canonical procedure.

## Verification boundary

This sandbox has neither the real full checkout nor Dart/Flutter. The bundle validator now proves Python transformer syntax, the exact AST-parsed 20-slice application order, static slice contracts, absence of Git writes in the **user-facing** development/qualification tools, an exact file-scope/digest bundle manifest, **synthetic cross-slice anchor composition across the overlapping touched files**, lexical and direct-import sanity for the full Dart source units generated by the bundle, lexical/source-shape validation for all 19 complete generated Dart tests plus high-risk final cross-slice source-contract checks, a permanent actual-orchestrator synthetic smoke, and fail-closed self-tests for the real-checkout qualifier. Synthetic validator fixtures may create throwaway local Git repositories to exercise guards; they never touch the user checkout or a remote. These checks still do **not** prove the generated Dart compiles or that Flutter tests pass.

During qualification the synthetic composition check found and fixed an overly broad scope-steering signal anchor. A later checkpoint audit also caught a more basic packaging regression: `apply_all_development_slices.py` had drifted back to an 8-slice list while the docs still described 20. The orchestrator is restored to the exact 20-slice order, and the validator now parses its `SLICES` literal structurally so this cannot hide behind textual matches again. The bundle manifest is also verified for exact file scope and digests before packaging. The generated-test pass additionally fixed a malformed truthful-streaming assertion, the steering continuation's stale/nonexistent test filename, and a wait test that still assumed delegation was disabled after the bounded-delegate slice. The remaining work is therefore primarily real-checkout compile/test qualification and provider/platform dogfooding, not another large architecture migration. See `ARCHITECTURAL_REMAINDER.md` and `QUALIFICATION_REPORT.md`.

## Git phase

There is intentionally no Git mutation step in this bundle. Branch creation, commits, push, PR/merge work, and clean-commit-only gates begin only after the real checkout has applied and qualified the development bundle. In particular, `tool/v71r12_exact_source_gate.py` requires a clean tracked tree, so it belongs after the checkpoint commit rather than on the intentionally dirty development worktree.
The checkpoint tooling is itself guarded: the top-level validator AST-parses the literal 20-slice order, verifies the exact 34 payload files and their SHA-256 digests, and the synthetic worktree smoke distinguishes genuinely new files from recovered-head files that are replaced wholesale. The latest type-closure audit also pins direct imports required by steering continuation (`plan_reconciliation.dart` and `universal_task_plan.dart`) so Dart does not depend on transitive imports.

