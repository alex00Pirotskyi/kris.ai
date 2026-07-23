# Changelog

## 1.7.0+170 — unified Project Manager and execution intelligence

- Re-established one canonical package lineage from the reproducible v1.5.1 source archive.
- Extended the SQLite workflow schema to version 5 with Project Manager, route-decision, circuit-breaker, semantic-progress, and verification records.
- Rebuilt Project Manager 2 with strict profiles, live sandbox readiness, retained snapshots, managed Run/Stop, bounded artifact validation, and deterministic packaging.
- Added role-based model routing with local-first data-boundary and approval enforcement.
- Added durable provider circuit breakers and append-only route-decision records.
- Added a semantic-progress ledger that rejects repeated reads, duplicate errors, identical decisions, and no-op writes as progress.
- Added deterministic strategy escalation, criterion-scoped independent objective verification, coordinator-enforced phase budgets, and context compaction.
- Rejected executor prose and broad generic evidence flags as completion proof; each criterion now requires a current type-appropriate hash or validator result.
- Made plan-split, awaiting-user, and stronger-model approval stages explicit durable outcomes instead of silent fall-through behavior.
- Closed the managed-process lifecycle leak with PID-reuse-safe process identities, complete descendant-tree termination, Linux parent-death signaling, and `unshare --kill-child`; both ordinary Stop and abrupt launcher death are now blocking Project Manager assertions.
- Added 40 execution-intelligence and 16 Project Manager executable cases while retaining all prior protocol, workflow, Prompt Studio, sandbox, broker, and replay gates.

## 1.5.1+151 — Linux sandbox backfill on the Prompt Studio 2 source line

- added a real Linux namespace worker for bounded project commands with read-only and snapshot-writable workspace modes;
- added an HTTPS-only public network broker and one-use secret broker;
- routed CLI Analyze/Test/Build/Run commands through the sandbox when available;
- kept sandbox self-tests in trusted host mode to avoid nested-userns false failures;
- preserved the durable SQLite kernel and Prompt Studio 2 foundations without claiming the full cross-platform v1.4 exit gate.

## 1.5.0+150 — Prompt Studio 2 and deterministic plan compiler

### Added

- Versioned `product_specification.v2`, `task_plan.v2`, `prompt_evaluation_dataset.v1`, `plan_capability_catalog.v1`, and `plan_compilation_report.v1` JSON contracts.
- Deterministic standard-library Python compiler and matching Dart runtime service.
- Generated Prompt Studio contract registry with a release-blocking source digest.
- Hierarchical 1–100-task planning with stable IDs, parent and dependency graphs, capability declarations, governed tools, artifacts, validators, acceptance evidence, budgets, retries, and stop policies.
- Capability derivation and coverage checks over all 23 governed tools.
- Side-effect-free dry-run simulation with stable topological order, batches, approvals, budget totals, output paths, and canonical input/output hashes.
- Prompt evaluation datasets, weighted baseline/candidate scoring, and plan-revision impact comparison.
- Runtime and loopback API routes for contract discovery, compilation, and evaluation.
- Source-only CLI commands: `plan-compile`, `prompt-evaluate`, and `plan-compare`.
- Deterministically generated 1-, 10-, 50-, and 100-task fixtures.
- A 30-case executable Prompt Studio 2 release gate and Dart behavioral source contracts.

### Safety and policy

- Local-only plans cannot claim network research or external deployment without an approved policy.
- Missing capabilities, unknown tools, duplicate IDs, dangling references, dependency cycles, hierarchy cycles, conflicting artifact producers, unsupported human workflows, and unapproved self-modification fail closed.
- Required artifacts must declare validators, and acceptance criteria must link to resolvable requirement and validator evidence.
- V1.4 sandboxing is explicitly not claimed. Sandbox-dependent tasks compile as blocked unless an explicit, warned, approval-bearing legacy dry-run override is supplied.
- The Python compiler is standard-library-only; source diagnostics do not depend on `jsonschema`, Dart, or Flutter.

### Retained

- The exact v1.3 schema-v4 SQLite authority, four checksum-verified migrations, append-only events, durable idempotency records, leases, checkpoints, compensation, migration rollback, and 14-case crash/recovery gate.
- Typed provider decisions and 23 generated tool contracts from v1.2.
- Both supplied production diagnostic replays from v1.1.7.

### Known limits

- Full visual Prompt Studio 2 editing, diff, dataset, simulation, and impact dashboards remain future UI work.
- The scale fixtures prove compilation and simulation, not 161 real project mutations.
- Existing child processes remain unsandboxed and retain the desktop user's privileges.
- Native Dart/Flutter and platform integration gates require a configured workstation.

## 1.3.0+130 — Durable workflow kernel and SQLite

- Replaced mutable whole-collection JSON runtime authority with SQLite repositories for projects, prompts, plans, permissions, evidence, knowledge metadata, runs, settings, and related records.
- Added four reviewed generated migrations, WAL/FULL durability configuration, checksum drift detection, integrity verification, and projection rebuild from append-only run history.
- Persisted run leases, task attempts, checkpoints, retry classification, operation idempotency, compensation records, migration imports, and recovery decisions.
- Made run snapshot projection and `run.snapshot` event append transactional.
- Added stable tool idempotency keys and durable result replay; ambiguous non-compensatable operations fail closed.
- Journaled file mutation intent before side effects and reconciled prepared/applied/committed/rollback states by content hash.
- Added byte-exact legacy JSON backups, idempotent import ledgers, pre-startup SQLite backups, full-startup rollback, and cleanup of failed first-time databases.
- Added SQLite-authoritative CLI diagnostics and `kristin test --workflow-kernel`.
- Added 14 executable crash/recovery/concurrency/migration contracts while preserving the protocol fuzz and production diagnostic replay gates.

## 1.2.0+120 — Typed protocol and tool-schema foundation

- Added versioned `AgentDecision` schema 1.0.0 with tool, complete, fail, ask-user, and delegate variants.
- Moved provider-envelope compatibility from the coordinator into dedicated Ollama, OpenAI-compatible, MCP, and recorded-response adapters.
- Added canonical JSON Schema tool registry 2.0.0 for all 23 governed tools.
- Added deterministic generation of Dart contracts, descriptors, repair examples, and contract digests from the canonical schemas.
- Enforced tool input validation before authorization and handlers, preventing missing mutation content or undeclared authority fields from reaching side effects.
- Enforced tool output validation before result envelopes are accepted as evidence, with representative contract cases for all 23 governed tools and a negative incomplete-mutation-result case.
- Preserved canonical failure code, retryability, summary, and reason across direct and recorded provider envelopes.
- Added typed retryability and schema issue records for protocol/tool failures.
- Added exact registry/handler coverage, 2,000 deterministic provider-envelope fuzz cases, and missing-mutation-data fuzzing.
- Preserved both v1.1.7 diagnostic replays, guarded artifact convergence, Project Manager behavior, and complete release lineage.
- Added protocol generation and validation to CI, quick tests, system tests, verification scripts, and release validation.

## 1.1.7+117 — Stability freeze and golden replay baseline

- Added compact redacted golden replay fixtures for the v1.1.5 nested-content loss and v1.1.6 Markdown-path convergence failure.
- Added `kristin test --replay-all`; ordinary quick and release gates execute the compact replay corpus.
- Canonicalized exactly matched whole-scalar quote and one-to-three-backtick Markdown wrappers before path policy, provider alias normalization, artifact matching, and mutation evidence reconstruction; mismatched or four-backtick values remain literal.
- Redirected repeated read-only discovery on explicit bounded artifacts to a task-specific deterministic mutation without widening permissions.
- Made deterministic recovery create-only for unobserved targets and existence-plus-hash guarded for inspected targets; stale state fails closed as `stale_existence` or `stale_content`.
- Reconstructed incomplete non-empty artifact state from prior evidence before each retry.
- Added automatic post-mutation inspection and objective artifact completion.
- Reserved four repair credits before starting another work-item attempt.
- Projected coordinator corrections into compact model history with discriminator, turn, and repair-counter fields removed, plus an explicit anti-copy instruction.
- Recorded the v1.1.6 diagnostic, failure taxonomy, recovery procedure, roadmap matrix, and parent-release provenance.

## 1.1.6+116 — Execution reliability and utilization redesign

- Reconstructed diagnostic run `run_hklsywuyo4NMJgt9ijIxWPhBDr` and identified the exact zero-byte artifact causal chain.
- Preserved canonical fields placed directly inside nested model action objects, including `content`, `path`, `query`, `url`, `executable`, and `args`.
- Made omitted `write_file.content` a hard `argument_required` error instead of silently writing an empty file.
- Added machine-readable tool argument schemas with required fields, optional fields, and canonical examples.
- Added coordinator-owned mutation-required artifact state; a known empty or incomplete artifact cannot be inspected repeatedly before correction.
- Added safe read-only external-path fallback to a bounded listing of the selected project root while retaining strict cross-project write rejection.
- Allowed deterministic desired-state completion for correct pre-existing artifacts without unnecessary rewrites or mutation charges.
- Expanded calculator artifact validation for symbolic operators, touchscreen input, editable/copyable real-time results, history, undo, and redo.
- Replaced full repeated contract/plan serialization with compact execution context, bounded evidence payloads, a 24,000-character history ceiling, deterministic temperature, and a 2,048-token action budget.
- Added diagnostic-derived regression tests for the exact nested write envelope, canonical nested path recovery, idempotent artifact completion, and tool schemas.

## 1.1.5+115 — Execution convergence and product-specific artifact recovery

- Reconstructed diagnostic run `run_hklfhuqkrwdoQ11swy34hvARke` from its full saved log archive and fixed the complete causal chain rather than only the terminal `argument_required` error.
- Preserved nested command arrays across domain and protocol normalization; generic vectors become `executable` plus `args`, while allowlisted Git status/diff vectors are replaced by project-scoped tools.
- Added bounded repair for missing required tool arguments, external process paths, and Git repository-root overrides without broadening project permissions.
- Made byte-identical writes true no-op operations: no backup, journal record, mutation counter, or rollback record is created; audit and run diagnostics retain the no-op hashes.
- Added repeated no-op write recovery that redirects to one artifact inspection.
- Carried bounded prior-attempt evidence into retry prompts and stopped historical no-op evidence from inflating material mutation counts.
- Added product-specific artifact validation for generated wireframes and usability checklists; calculator designs must cover operations, keyboard input, history, immediate feedback, responsive/interaction/accessibility states, and exclude unrelated commerce flows.
- Added deterministic completion for a valid inspected artifact and bounded `artifact_scope_mismatch` correction for an irrelevant artifact.
- Propagated approved product context into generated tasks and reduced design/setup tasks to least-privilege tool allowlists.
- Rewrote system-install/sibling-project setup tasks to initialize the selected project root.
- Replaced unnecessary Express/REST backend tasks with a client-side calculation engine and browser-session history when the approved product has no server requirement.
- Preserved testing tasks that merely mention backend references unless they explicitly request backend implementation.
- Made non-repository Git status/diff an honest successful observation instead of a misleading tool failure.
- Separated work-item attempts, tool-repair attempts, and model-load attempts in events and diagnostic exports.

## 1.1.4+114 — Deterministic repeated release validation

- Replaced the 40 ms / 90 ms Ollama retry timing race with an explicit first-attempt/retry server handshake.
- Increased the local retry-fixture deadline to two seconds without changing production model-load defaults.
- Synchronized the cancellation fixture on receipt of the preload request instead of a fixed 50 ms sleep.
- Run Kristin-controlled Flutter tests with `--concurrency=1` for stable System and Release gates.
- Preserve the failing Flutter test identity in CLI failure summaries.
- Added Dart, offline-system, and release-validator regressions for the reported Windows-only flake.

## 1.1.3+113 — Workstation validation and contract hardening

- Removed the unused optional subscription constructor parameter reported by Flutter analysis while preserving cancellation disposal.
- Replaced the formatter-sensitive `stage: 'load_started'` source assertion with token checks and an ordered behavioral progress-stage test.
- Clarified local-only deployment normalization with separate `Do not deploy` and `Do not claim a public URL` sentences.
- Added independent offline and release-validator regressions for all three workstation failures.
- Preserved v1.1.2 Ollama preloading, cancellation, task capability alignment, Project Manager behavior, and transitive release lineage.

## 1.1.2+112 — Local-model resilience and capability-safe planning

- Fixed diagnostic run `run_hkkkbh7q3rNkIqtjzJuPYvsiiy`, which failed after one 180-second Ollama HTTP-response wait with 79 model requests, all tool calls, and all mutations still available.
- Added exact-model Ollama preloading, an eight-minute default cold-load deadline, one bounded internal retry, and configurable keep-alive.
- Separated cold-load, first-token, and complete-generation deadlines and recorded stage-specific progress and provider details.
- Connected run Stop/cancellation to in-flight Ollama and OpenAI-compatible HTTP clients.
- Added behavioral tests for transient cold-load retry and cancellation of an in-flight load.
- Raised generated non-manual task attempts to a bounded minimum of two.
- Replaced unsupported recruitment, interviews, surveys, focus groups, and external user-feedback tasks with local objective checks and an inspectable usability checklist.
- Replaced contradictory external design-tool and public-hosting instructions instead of appending incompatible constraints.
- Preserved the v1.1 Project Manager, ProductException import repair, governed tools, project boundaries, diagnostics, SDK environment, and complete v1.0.5–v1.1.1 release lineage.

## 1.1.1+111 — Project Manager compile hotfix

- Import `storage_security.dart` from `project_diagnostics.dart` so `ProductException` resolves during Flutter analysis and test compilation.
- Add exact source-contract, offline-system, and release-validation checks for the cross-file exception linkage.
- Preserve all v1.1.0 Project Manager, Prompt-to-Task, permissions, process controls, diagnostics, and release-lineage behavior.
- Record the supplied Windows compile failure and v1.1.0 parent archive in the structured version-control ledger.

## 1.1.0+110 — Project Manager preview and capability-aligned execution

- Added a dedicated Project Manager workspace with Doctor, Analyze, Test, Build, Run, Stop, recent runs, managed-process output, and Save logs.
- Added one shared project execution profile across the desktop runtime, loopback API, and CLI.
- Added managed project processes with bounded output, safe stop, process status, and audit/event records.
- Added `kristin analyze` and `kristin build`; retained dry-run-by-default `kristin run`.
- Fixed diagnostic run `run_hkk9czt4wzMPTp3bsaqLnpNOx2`: artifact-producing tasks no longer inherit a read-only tool set merely because the model labels the plan as `plan`.
- Promoted file-, feature-, design-, implementation-, package-, and deployment-producing tasks to governed build mode while preserving explicitly planning-only tasks as read-only.
- Required mutation evidence before implementation tasks can complete and added `implementation_stalled_read_only` for bounded non-progress.
- Normalized wireframe/user-flow output to project-local artifacts and deduplicated equivalent deployment tasks.
- Preserved the complete v1.0.5-v1.0.9 release lineage and latest diagnostic provenance.

## 1.0.9+109 — Release-lineage contract hotfix

- Fixed the only v1.0.8 Windows test failure: `source_contract_test.dart` expected the retained v1.0.5 path-hygiene SHA-256, but the v1.0.8 `VERSION_CONTROL.json` ledger had omitted that ancestor.
- Restored the exact v1.0.5+105 archive hash and preserved the complete v1.0.5–v1.0.8 chain in `transitiveReleaseLineage`.
- Added an explicit `lineageContract` with ordered required ancestor versions and preservation across future heads.
- Changed Dart lineage checks from unscoped substring matching to structured JSON parsing with exact version, role, and SHA-256 assertions.
- Added independent structured lineage checks to the offline system fixture and deterministic release validator.
- Recorded the actual v1.0.8 workstation result: formatting, dependency resolution, and analysis passed; only the stale lineage assertion failed.
- Preserved the v1.0.8 bounded SDK environment and single-pass `pub get` → `analyze --no-pub` → `test --no-pub` sequence.

## 1.0.8+108 — SDK environment and single-pass validation hotfix

- Fixed `flutter pub get` exit code 65 when launched through `kristin test` even though the same command succeeded in the user's Windows terminal.
- Added a bounded SDK subprocess profile that preserves Windows Pub-cache locations, Flutter/Dart/Android/Java paths, package mirrors, proxies, certificate overrides, and related Git/XDG settings only for Dart and Flutter commands.
- Kept the narrower default environment for ordinary project commands.
- Added automatic Dart/Flutter SDK-profile inference for detected and custom project commands.
- Changed release source validation to `--skip-tests --skip-sdk`, preventing a duplicate nested dependency/analyzer pass.
- Added `--no-pub` to analyzer and test gates after the explicit dependency-resolution step.
- Redacted common secret values and credentials embedded in proxy URLs from captured command output.
- Added deterministic offline regression fixtures for SDK environment propagation, command-profile inference, and single-pass release validation.

## 1.0.7+107 — Failed-run context and protocol recovery hotfix

- Fixed automatic knowledge retrieval that treated ordinary application words such as “error handling”, “history”, and testing language as permission to inject failed-run episodes. Unsuccessful memory is now an explicit diagnostic opt-in only, unless an episode is pinned.
- Normalized the exact observed local-model action `inspect_project_and_establish_evidence_baseline` into a task-appropriate, allowlisted evidence tool rather than spending the full protocol-repair budget.
- Replaced alphabetic protocol examples with task-aware examples and added an anti-copy rule for work-item titles, task IDs, `[K#]` citations, and historical action text.
- Aligned generated task tools and acceptance criteria with runtime capabilities, local-only mode, local design artifacts, and local deployment packages.
- Added a guard that rejects mutating plans when Kristin’s own source checkout is accidentally selected as the target project.
- Added diagnostic summaries for automatic memory policy and model-protocol recovery.
- Added regression coverage derived from diagnostic run `run_hkjnl5dagrldsloYB4qnRQTS3h`.

## 1.0.6+106 — Workspace boundary canonicalization merge

- Forward-ported the user-supplied Windows workspace-boundary fix onto v1.0.5 rather than replacing newer path recovery and generated-tree hygiene work with an older v1.0.4 tree.
- Normalized Windows extended-length `\\?\` drive and `\\?\UNC\` paths before project-boundary comparison, preventing false `path_outside_project` failures when a selected project crosses a reparse point.
- Added Windows-gated reparse-point regression coverage.
- Added `VERSION_CONTROL.json` with parent and user-patch SHA-256 lineage.
- Regenerated release integrity metadata because the submitted patch ZIP retained pre-patch manifest hashes for its three edited files.

## 1.0.5+105 — Path and validation hygiene hotfix

- Added bounded external-path recovery for recognized `/workspace`, `/project`, and `/repo` aliases.
- Added stale same-project absolute-path rebasing through the selected project directory name.
- Added read-only existing-suffix recovery and safe project-root fallback for directory listing and text search.
- Preserved strict rejection for arbitrary external writes, parent traversal, schemes, symlink escapes, and sensitive automatic-recovery candidates.
- Added `tool.path_rebased_to_active_project` and `tool.path_recovery_rejected` diagnostics with hashed path provenance.
- Added a **Project path recovery** section to exported diagnostic summaries.
- Added a shared generated-source policy used by validation, secret scanning, and release packaging.
- Excluded Flutter/native ephemeral state such as `windows/flutter/ephemeral/flutter_windows.dll` and `.pdb` from source hygiene checks and release ZIPs.
- Added behavioral and offline regression coverage for virtual-root recovery, stale-project recovery, arbitrary external-write blocking, sensitive-path exclusion, root fallback, and generated-state filtering.

## 1.0.4+104 — Windows validation hotfix

- Fixed the undefined `$candidate` interpolation in `source_contract_test.dart` by using a literal raw-string marker.
- Removed the remaining single-cascade and unnecessary-`this` analyzer info findings.
- Split deterministic governed-source validation from Flutter SDK compilation to avoid duplicate, opaque analyzer failures.
- Made source-contract token checks whitespace-normalized so formatter layout changes do not break validation.
- Added exact validator failure output to the console and CLI report detail.
- Added offline regression coverage for the Windows compile and validation path.

## 1.0.3+103 — Repeated-tool loop recovery hotfix

- Fixed the failure where a local model repeatedly requested the same successful `list_directory` action and Kristin terminated the second attempt with `agent_stalled_repeated_tool_outcome` despite ample remaining run budget.
- Added exact read-only action fingerprints scoped to the current mutation epoch.
- Reuses an already recorded successful result instead of dispatching and charging the same static tool again.
- Added `agent.repeated_tool_call_blocked` with action fingerprint, outcome fingerprint, cached summary, repetition count, recovery decision, and budget snapshot.
- Added bounded, allowlist-preserving `agent.loop_recovery_redirected` actions that collect different objective evidence rather than repeating the same read.
- Prioritizes project descriptors and entry points such as `README.md`, `pubspec.yaml`, `package.json`, and `pyproject.toml` for recovery inspection.
- Excludes hidden files and secret-, credential-, password-, token-, private-key-, and `.env`-like paths from deterministic inspection.
- Added deterministic completion only for the dedicated read-only evidence-baseline node after a root listing, at least one SHA-256-backed file inspection, and independent structural evidence are present.
- Explicitly prevents this deterministic completion from answering general grounded questions or completing implementation and verification nodes.
- Preserved terminal repeated-loop protection when no unused safe recovery action remains.
- Added an **Agent loop recovery** section to saved diagnostic summaries.
- Added behavioral and offline source-contract coverage for safe redirection, evidence sufficiency, secret-path exclusion, and non-baseline completion rejection.

## 1.0.2+102 — Budget-aware retry and all-logs diagnostics hotfix

- Fixed the failure sequence where an agent-turn-limit retry reused the same nearly exhausted global model-request budget and immediately failed with `budget_model_requests`.
- Replaced the fixed 40-turn attempt loop with a plan- and remaining-budget-aware per-attempt allowance capped at 24 turns by default.
- Added plan-scaled autonomy budgets for 1–100 task execution, with bounded API deserialization limits.
- Reserved model-request budget before provider dispatch so timeouts and failed requests are counted accurately.
- Added `model.request_started`, `model.request_completed`, and `model.request_failed` events with request number, duration, model identity, response hash, and budget snapshot.
- Added explicit retry decisions through `work_item.retry_scheduled` and `work_item.retry_skipped`, including cause code, remaining capacity, and reason.
- Added repeated identical read-only outcome detection to stop stagnant model/tool loops before they consume the run budget.
- Enforced tool and mutation quotas only when another governed tool is dispatched, so the model can still return a final completion after the last permitted operation.
- Added remaining-turn guidance to the model so it completes or fails explicitly instead of continuing unbounded exploration.
- Changed Retry to create a fresh linked run with reset attempts and counters; failed runs now return `run_retry_required` rather than reusing spent state.
- Added `sourceRunId` provenance to linked retries and exposed a retry route through the authenticated loopback API.
- Added **Save all logs** in the Logs workspace and advanced diagnostics UI.
- Expanded diagnostic ZIPs to include redacted run records, evidence metadata, retained events, audit records, bounded managed-process logs, platform/settings fingerprints, and a per-entry hash manifest.
- Added `kristin logs --export [--run-id ID] [--output FILE]` for command-line diagnostic export.
- Added behavioral and offline regression coverage for 100-task budget scaling, budget clamps, fresh linked retries, failed-run rejection, diagnostic content, and secret/source redaction.

## 1.0.1+101 — Model protocol compatibility and diagnostics hotfix

- Fixed repeated `model_action_invalid` failures caused by local-model response envelopes, nonstandard action verbs, tool aliases, and argument aliases that were structurally safe but not recognized.
- Added a bounded `AgentProtocolAdapter` that unwraps common chat-completion, `function_call`, `tool_calls`, double-encoded JSON, and ReAct-style action responses.
- Added safe, allowlist-aware normalization for common tool names such as `inspect_project`, `list_files`, `open_file`, `run_tests`, and related argument keys such as `tool_input`, `action_input`, and `file_path`.
- Kept tool authorization deterministic: normalized calls must still resolve to exactly one tool already allowed by the current work item, and all permission, path, stale-hash, process, and transaction checks remain active.
- Reset protocol and tool repair streaks after a valid action so intermittent malformed responses do not incorrectly exhaust the entire work item’s repair allowance.
- Added a one-time bounded read-only inspection fallback after repeated malformed actions on evidence-baseline work items; it cannot mutate files, run processes, use the network, or broaden permissions.
- Added `model.protocol_fallback_applied` and `model.protocol_exhausted` diagnostics with model identity, response hash, response length, candidate keys, and repair counts.
- Added a redacted 2,000-character `responsePreview` to model evidence so invalid local-model output can be inspected without relying only on a hash.
- Replaced the generic terminal error with `model_protocol_exhausted`, which points the user to the latest evidence preview and selected-model compatibility.
- Added behavioral and offline regression coverage for snake-case function calls, nested/double-encoded envelopes, explicit-tool recovery, safe aliases, completion signals, ReAct actions, and disallowed-tool rejection.

## 1.0.0+100 — Prompt-to-Task product preview

- Added a goal-first AI Prompt Composer that generates structured, editable prompt drafts from plain-language ideas.
- Added bounded schema repair for invalid prompt and task-plan model responses.
- Added immutable prompt versions with provenance, model identity, content hashes, comparison, and restore-ready history.
- Added adaptive hierarchical task planning from 1 to 100 executable tasks with phases, dependencies, parent relationships, complexity, effort, uncertainty, risk, confidence, tools, acceptance criteria, verification steps, and expected artifacts.
- Added deterministic validation for duplicate IDs, missing or cyclic dependencies, missing or cyclic parent hierarchies, disabled prerequisites, manual tasks, and maximum plan size.
- Added immutable task-plan revisions; edits create a new plan ID linked to the previous revision rather than overwriting approved plans.
- Added deterministic compilation of approved prompts and plans into the existing governed `TaskContract`, `ExecutionPlan`, permission, evidence, transaction, and audit runtime.
- Added full-plan execution, selected-task execution with all transitive prerequisites, plan review, task editing, and stop controls in Prompt Studio.
- Added authenticated loopback API routes for prompt generation/versioning and task-plan generation, revision, inspection, and compilation.
- Fixed `path_absolute_rejected` for safe in-project paths: absolute paths and local `file:` URIs inside the canonical active project are normalized to project-relative paths, while outside paths, traversal, schemes, and symlink escapes remain blocked.
- Added bounded model recovery for correctable path and tool-argument errors so one malformed call does not immediately terminate the work item.
- Added `kristin test --system` for Prompt-to-Task, boundary, recovery, API, persistence, and behavioral fixtures.
- Added `kristin test --release` for the system suite plus release validation and independent deterministic ZIP comparison.
- Added v1 behavioral, source-contract, offline system, packaging, manifest, and release-identity gates.
- Kept the package explicitly classified as a source/product preview when native Flutter analysis, tests, and builds have not run.

## 0.9.3+93 — Memory relevance and agent-action recovery hotfix

- Removed deterministic work-item titles from automatic knowledge queries; retrieval now starts from the original user request.
- Excluded failed, cancelled, and interrupted run episodes from normal agent context unless the request explicitly asks for diagnostic history or the episode is pinned.
- Added outcome-aware episode ranking, result diversity, index schema 3, and de-duplicated episode citation text.
- Added normalization for common local-model action aliases and function-call argument shapes.
- Added bounded schema-feedback correction turns before reporting `model_action_invalid`.
- Added a conversational fast path for greetings and capability questions, with no project inspection tools.
- Updated Auto mode to classify greetings as Ask and start their no-tools plan immediately instead of generating a build plan.
- Allowed the two-character greeting `hi` through request validation.
- Accepted bounded plain-text model replies only for that no-tools conversational work item, preventing harmless greetings from failing solely on JSON formatting.
- Bumped prepared task contracts to revision 2 so stale v0.9.2 plans are not reused.
- Increased local-model cold-start and response deadlines and reduced per-action output to 4,096 tokens.
- Added behavioral and offline regression gates for memory safety, action parsing, and conversational planning.

## 0.9.2+92 — Windows compile and knowledge API hotfix

- Replaced the analyzer-invalid inline `(?m)` regular-expression flag with Dart's supported `multiLine: true` option.
- Removed the unused `dart:math` and `storage_security.dart` imports from project diagnostics.
- Added the missing project-scoped `KnowledgeService.list(projectId)` API used by the v0.9 migration tests.
- Routed `ProductRuntime.listKnowledge` through the same service API to avoid duplicate listing behavior.
- Added a behavioral test for project isolation and newest-first knowledge ordering.
- Extended the offline validator and source-contract tests to reject unsupported inline RegExp flags and service/test API drift.
- Documented that `dart format` requires a path, such as `dart format .`.

## 0.9.1+91 — Windows startup and analyzer hotfix

- Fixed the missing direct `crypto_utils.dart` import for `SecretRedactor` in project diagnostics.
- Replaced the trailing-separator regular expression that Flutter 3.44 reported as invalid.
- Added a mounted guard before opening the Quick Test confirmation dialog.
- Replaced deprecated `Matrix4.scale` usage with `scaleByDouble`.
- Removed the single-use cascade reported by the analyzer.
- Escaped the `&` metacharacter in `RUN_WINDOWS.bat`.
- Fixed stale-source pruning so `knowledge_memory_test.dart` remains active.
- Made `--project` accept an omitted value as the current directory and added friendly no-command onboarding.
- Added source and offline-validator regression gates for every reported failure.

## 0.9.0+90 — Knowledge & Memory preview

- Added immutable project-scoped research provenance records for fetched sources and search-result snapshots.
- Added content-addressed storage for raw fetched content, extracted text, and archived search JSON.
- Added local hybrid retrieval over notes, archived research, search snapshots, and terminal-run memory using lexical relevance, deterministic semantic vectors, recency, trust, and pinning.
- Added inspectable `[K1]` citation records and citation-aware prompt context; retrieved external content remains explicitly untrusted data.
- Added episodic memory for succeeded, failed, cancelled, and interrupted governed runs, including outcomes, lessons, changed-file references, evidence hashes, and budget usage.
- Added bounded, idempotent migration of v0.8 source/search snapshot files into content-addressed v0.9 records, recovery provenance for orphaned research entries, and startup reconciliation for historical terminal runs.
- Expanded the Knowledge UI with Overview, Research sources, Notes, and Run memory views, local search, pinning, reindexing, provenance inspection, and portable export.
- Added knowledge/archive/memory loopback API endpoints and OpenAPI metadata.
- Added `kristin knowledge` CLI inspection for stats, archive records, run memory, and diagnostic search.
- Added governed `knowledge_search` results containing citations, source identifiers, scores, hashes, and trust labels.
- Added behavioral knowledge/archive/export/migration tests and v0.9 release-validator contracts.
- Preserved the v0.8 chat-first workspace, Prompt Studio, project Doctor, Quick Test, visual run graph, and governed runtime.
- Kept the release explicitly source-only when Flutter analysis, tests, and native builds are unavailable.

## 0.8.0+80 — Chat Workspace preview

- Replaced the default Simple Studio landing experience with a chat-first project workspace.
- Reduced primary navigation to Chats and Projects, with Runs, Prompt Studio, Knowledge, Skills, and Logs under a collapsible Build & Debug menu.
- Added inline plans, grouped access approval, task start, live work-item progress, results, and artifact/evidence links in the conversation.
- Added a pan-and-zoom visual run graph with node inspection and pause, resume, cancel, and retry controls.
- Added model-independent project Doctor and Quick Test services with automatic profiles for common project stacks and optional `kristin.project.json` overrides.
- Added cross-platform `kristin` / `kristin.cmd` commands for doctor, quick/full tests, run-command detection, log tails, and combined reports.
- Added persistent Prompt Studio records with variables, modes, tags, versions, previews, and chat insertion.
- Added local research source and search-result snapshots with fetched content, hashes, response metadata, and redirects.
- Added project-scoped Knowledge and built-in Skills surfaces.
- Added governed `inspect_file` and `write_binary_file` tools as a bounded binary-file foundation.
- Changed persistent collection writes to lock-scoped read-modify-write updates to reduce cross-run lost updates.
- Updated product, API, MCP, deployment, SBOM, validation, tests, and release packaging metadata to v0.8.0+80.
- Preserved the governed v0.7 runtime and legacy migration compatibility.

## 0.7.0+71 — Event ordering compatibility hotfix

- Fixed two Windows analyzer errors caused by calling the list-only `reversed` getter on `Iterable<EventEnvelope>` in the Conversation and Logs views.
- Materialized run-event filters as fixed-length `List<EventEnvelope>` values before reverse traversal.
- Added Flutter source-contract and deterministic release-validator guards for the exact regression.
- Rebuilt clean-install and in-place-upgrade source archives from the immutable v0.7.0+70 release baseline.

## 0.7.0+70 — Simple Studio

- Replaced the eight-destination engineering console with four normal destinations: New task, Activity, Projects, and Templates.
- Added a single natural-language composer with automatic internal mode selection.
- Added six first-run templates for websites, Telegram bots, applications, repairs, improvements, and code questions.
- Added a friendly plan card with job size, short steps, safety summary, and grouped access request.
- Added one primary **Allow once and start** action while retaining granular permission controls behind progressive disclosure.
- Added five-phase progress: Understand, Plan, Build, Test, Ready.
- Added a conversation-and-output execution workspace with Preview, Files, Changes, Tests, and Flow views.
- Added Activity inspection with Summary, Steps, Changes, Tests, Sources, and Simple/Technical/Raw logs.
- Moved models, knowledge, security, API, MCP, audit, and diagnostics into Advanced Settings without removing functionality.
- Added accessibility-oriented labels, empty states, recovery actions, responsive navigation, and keyboard-friendly Material controls.
- Added source-contract and release-validator gates for exactly four primary destinations, automatic mode inference, templates, progress phases, progressive disclosure, and continued access to governed capabilities.
- Preserved the v0.6.1 governed execution runtime, project boundaries, checkpoints, rollback, evidence, permissions, secrets, research, API, and audit behavior.

## 0.6.1+64

- Repaired formatter-sensitive source-contract assertions after a clean Flutter analyzer run.
- Preserved all build-63 governed-source and Windows launcher fixes.

## 0.6.1+63

- Quarantined stale legacy source safely before analysis.
- Tightened analyzer and release gates.

## 0.6.1+62

- Repaired Windows compilation compatibility regressions.

## 0.6.1+61

- Introduced the governed product runtime and production-hardening foundations.
