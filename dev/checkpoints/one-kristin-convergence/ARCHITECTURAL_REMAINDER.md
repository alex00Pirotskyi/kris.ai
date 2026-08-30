# Architectural remainder after the 20-slice development bundle

The recovered worker plan is now represented almost entirely as guarded source implementation. What remains is predominantly composition verification and dogfooding in a real checkout.

## Implemented architecture

The bundle now covers:

- one canonical Kristin conversation/session across Simple and the Advanced route opened from it;
- durable planning/understanding/request/run/permission/deferred-input projections;
- semantic slash payloads and structured blocking clarification;
- collision-safe target resolution;
- truthful ordinary provider streaming;
- deterministic `utility.time`;
- canonical project-free Research graph execution, durable Research progress/evidence, startup reconciliation, explicit retry, and optional-project archive guards for graph and direct Research, including audited archive-store degradation that preserves grounded answers;
- durable semantic steering;
- topology-changing steering replan/reconciliation through linked continuation runs, including the awaiting-approval idle case;
- absolute timestamp wait with restart scheduling;
- bounded one-level model-only delegation plus repeat/failure/restart convergence;
- continuation handoff in One-Kristin Chat;
- concise live activity projection with raw model deltas excluded from activity history;
- authority-neutrality qualification against the existing P1/P2/ordinary permission boundaries;
- friendly failure summaries with separately inspectable redacted technical detail.

PR #290's Runner correctness changes were already present on the recovered head and are not duplicated.

## 1. Real-checkout compile/test verification — required

The source slices touch overlapping runtime/storage/UI seams. The bundle now passes a synthetic cross-slice anchor-composition validator and an end-to-end synthetic orchestrator smoke run, including the overlapping `product_runtime.dart`, `planning_runtime.dart`, steering, Research, and canonical session/UI seams. That caught and fixed a real ambiguous steering-signal anchor. What remains unproven is **Dart/Flutter semantic compilation on the complete repository**, not basic bundle ordering.

Required gates:

- apply all slices to a clean `dd2f46...` checkout;
- run the repository's normal toolchain-lock runtime gate before dependency resolution;
- run `flutter pub get`, require the tracked `pubspec.lock` to resolve `timezone` as direct main `0.10.1`, and fail if any pre-existing locked package version changes;
- update the governed `pubspec.lock` SHA in `config/toolchains.lock.json`, recompute its canonical `declaredInputFingerprint`, and rerun the toolchain-lock gate before analyzer/tests;
- format changed Dart files;
- run the repository's local generator/workflow/Prompt-Studio source gates;
- `flutter analyze --no-pub --fatal-infos --fatal-warnings`;
- focused tests plus the full Flutter suite;
- `validate_release --skip-tests`;
- refresh `SOURCE_MANIFEST.sha256` only after all requested local gates pass;
- inspect the generated diff for semantic mistakes that lexical/synthetic checks cannot detect.

`qualify_real_checkout.py` automates that sequence, records the pre-Pub toolchain receipt outside the checkout, verifies the exact timezone lock plus pre-existing-version stability contract, and emits JSON/Markdown qualification reports outside the checkout. Even `--format` alone proves the locked installed toolchain before rewriting Dart source bytes. The repository's `v71r12_exact_source_gate.py` is **not** a dirty-worktree development gate: it explicitly requires a clean tracked tree, so it moves to the later Git/checkpoint-commit phase.

## 2. Provider/model dogfooding — bounded

The bounded delegate role policy is deliberately narrow (`reviewer`, `planner`, `analyst`). Run it against the actually supported Ollama and OpenAI-compatible model configurations and verify:

- role prompts produce useful bounded guidance;
- repeated identical delegations replay instead of consuming turns;
- terminal failures do not loop;
- restart-interrupted child deliberation retries only within its bound;
- no provider wrapper turns child output into tool/authority instructions.

Do not expand the role registry until these roles demonstrate a concrete missing capability.

## 3. Steering continuation integration scenarios — bounded/test-heavy

Dogfood both continuation entry points:

- scope changes before initial approval;
- scope changes during a long run after one or more verified work items;
- constraint-only steering while a work item is active;
- continuation requiring a different permission set;
- source project removed before continuation materialization;
- restart between source interruption and continuation creation;
- Chat automatically following the durable source → continuation link.

The important invariant is that the continuation starts with fresh contract-derived approval and `authorityInherited: false`.
Preserved completed tasks are disabled by reconciliation and therefore excluded by compilation. A zero-remaining-work replan uses a hidden read-only verification bridge so deterministic final verification still runs; the final steering boundary itself now occurs after the source run's deterministic verification and before commit.

## 4. Research integration scenarios — bounded/test-heavy

Qualify:

- project-free multi-subgoal Research;
- direct single-fact Research;
- app restart mid-Research;
- explicit retry from persisted plan snapshot;
- selected project deleted while search/fetch is in flight;
- verify audited archive-degradation warnings are visible enough in diagnostics without cluttering the normal answer;
- evidence URL/hash/fetch timestamp preservation;
- direct and graph model synthesis preserve the untrusted web-data envelope / `authorityBearing: false` boundary under prompt-injection-style retrieved content.

## 5. Advanced/activity roundtrip — bounded UI qualification

Verify Simple → Advanced → Simple with:

- transcript, selected project/model, current/continuation run and approval state intact;
- pending deferred user input intact;
- settings selections projecting back to the canonical session;
- recent activity remaining concise and model token deltas hidden from the activity list;
- friendly error summary plus expandable redacted technical detail;
- no stale async project-process status after the round trip.

## 6. Final product/platform qualification

After source qualification:

- package the final qualified development checkpoint;
- only then begin the separate Git branch/commit/push/merge phase;
- after the checkpoint commit exists, run the clean-tree exact V71-R12 source gate and normal tri-platform product gates;
- diagnose the previously observed Windows P1–P8 source-gate failure only if it still reproduces on the newly committed candidate.
