# Kristin Local Agent v1.9.0+190 — Interoperability, Administration, and Release Operations

Kristin is a local-first desktop AI agent for discussing, researching, planning, changing, testing, running, and packaging work inside explicitly registered project folders.

Version **1.9.0+190** is the single canonical cumulative source line. It retains the typed tool contracts, durable SQLite kernel, Linux sandbox and brokers, Prompt Studio 2, Project Manager 2, execution intelligence, knowledge/memory admission policy, freshness-aware citations, governed skill publication, content-addressed object storage, and core file adapters; then adds roadmap-correct interoperability, administration, audit, and release-governance foundations:

- describe an idea in plain language;
- let the selected model generate a structured, editable prompt;
- improve, simplify, or expand individual prompt versions;
- generate an adaptive task plan containing from 1 to 100 tasks;
- review complexity, effort, risk, confidence, dependencies, tools, acceptance criteria, and verification;
- edit a task without overwriting the prior plan revision;
- run the entire plan or one selected task with all required dependencies;
- stop active runs, inspect progress, retry failures, and retain evidence and memory.



## Release classification, platform support, and security truth

Kristin **v1.9.0+190** is currently a **`source-release` preview**, not a signed installer or a validated compiled desktop release. The canonical release metadata still marks `compiled_release_validated` as `false`, and native installer signing plus platform updater execution remain out of scope for this source-only environment.

### Current support snapshot

| Area | Current v1.9.0+190 source truth |
|---|---|
| Supported artifact | Reviewed source tree plus documented source-only validation gates |
| Release channel | `preview` |
| Linux execution boundary | Linux reference namespace worker, HTTPS broker, and one-use secret broker are present in source and may run ordinary CLI project commands when available |
| Windows/macOS execution boundary | Native worker backends are **not** implemented; sandbox-dependent work must fail closed or remain unsupported |
| Owner Mode | **Roadmap target only.** Unrestricted full-computer authority is **not** implemented in this source release |
| Signed installers / updater | Not included |
| Signed-manifest trust | v1 envelope-supplied trust is disabled; Signed Manifest v2 is not yet implemented or enabled for production trust |

### Interoperability and update trust freeze

- **Do not treat v1 signed manifests as trusted.** P0-002 disables the envelope-supplied v1 trust path.
- **Do not treat Signed Manifest v2 as available yet.** It remains a later roadmap milestone.
- **Do not treat plugin, skill, MCP, A2A, or source-update manifests as production trust anchors** unless a later reviewed release says otherwise.

### Security and support documents

Read [`SECURITY.md`](SECURITY.md), [`docs/SECURITY_MODEL.md`](docs/SECURITY_MODEL.md), [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md), [`docs/PRIVACY.md`](docs/PRIVACY.md), and [`docs/SUPPORT_POLICY.md`](docs/SUPPORT_POLICY.md) before using Kristin with untrusted projects, third-party MCP servers, or sensitive data.

## v1.9 interoperability, administration, and release operations

The governed runtime now adds typed MCP lifecycle manifests, bounded A2A task contracts, signed plugin/skill/agent manifests, deterministic policy profiles, append-only audit verification, authenticated source-update manifests, and support compatibility policies. The workflow schema advances to **v6** with audit, interoperability, and update records. Native installer signing and platform-specific updater execution remain explicitly out of scope for this source-only environment.

Source-only gates:

```bash
python tool/interoperability_admin_v19_test.py
python tool/generate_v190_contracts.py --check
```

See [`docs/V1.9.0_INTEROPERABILITY_ADMIN_RELEASE_OPS.md`](docs/V1.9.0_INTEROPERABILITY_ADMIN_RELEASE_OPS.md) and [`docs/ROADMAP_IMPLEMENTATION_MATRIX.md`](docs/ROADMAP_IMPLEMENTATION_MATRIX.md).

## v1.8 knowledge, memory, skills, and file adapters

The governed runtime now adds memory admission with failed-memory quarantine by default, content-addressed object storage, freshness-aware research snapshots, governed skill candidate extraction and publication, and native plus sandboxed-core file adapters with reopen-and-validate behavior. The earlier v1.7 execution-intelligence and v1.6 Project Manager 2 layers remain part of the cumulative line.

Source-only gates:

```bash
python tool/execution_intelligence_test.py
python tool/project_manager_v2_test.py
python tool/workflow_kernel_test.py --project .
python tool/system_test.py --project .
python tool/validate_release.py --skip-sdk
```

See [`docs/CANONICAL_LINEAGE.md`](docs/CANONICAL_LINEAGE.md), [`docs/V1.6.0_PROJECT_MANAGER_2.md`](docs/V1.6.0_PROJECT_MANAGER_2.md), [`docs/V1.7.0_EXECUTION_INTELLIGENCE.md`](docs/V1.7.0_EXECUTION_INTELLIGENCE.md), and [`docs/ROADMAP_IMPLEMENTATION_MATRIX.md`](docs/ROADMAP_IMPLEMENTATION_MATRIX.md).

## v1.5.1 cumulative sandbox backfill on top of Prompt Studio 2

V1.5.0 adds a model-independent compilation boundary between proposed product intent and governed execution. Five versioned JSON contracts now define the structured product specification, hierarchical task plan, prompt evaluation dataset, capability catalog, and plan compilation report. The same reviewed contracts generate Dart source and drive the runtime service, authenticated loopback API, standard-library CLI, fixtures, and release gates.

The compiler validates 1–100 task graphs, derives required capabilities, maps them only to the 23 governed tools, detects dependency and parent-hierarchy cycles, enforces local-only/data/deployment/self-modification/human-workflow rules, checks artifact validators and acceptance evidence, preflights aggregate budgets, computes a stable topological schedule, and emits a dry run with `sideEffectsPerformed: false`. Canonical inputs produce stable input and output hashes.

The deterministic corpus includes 1-, 10-, 50-, and 100-task plans and currently passes **30/30** executable compiler/evaluation cases. Prompt revision impact is measured against a versioned dataset; the release fixture improves from 25.0 to 100.0. Plan revisions can be compared under the same specification and policy.

The roadmap places v1.4 OS sandboxing before v1.5. This cumulative source head backfills the Linux reference worker, HTTPS network broker, and one-use secret broker without pretending that the full cross-platform v1.4 milestone is complete. Ordinary CLI project commands now run through the Linux namespace worker when it is available; Windows and macOS native worker backends still fail closed.

Source-only commands:

```bash
python tool/generate_prompt_studio_contracts.py --check
python tool/generate_prompt_studio_fixtures.py --check
python tool/prompt_studio_v2_test.py
./kristin plan-compile --spec <spec.json> --plan <plan.json> --policy <policy.json> --output <report.json> --fail-on-errors
./kristin prompt-evaluate --baseline <prompt.json> --candidate <prompt.json> --dataset <dataset.json> --output <impact.json>
./kristin plan-compare --spec <spec.json> --baseline <plan.json> --candidate <plan.json> --policy <policy.json> --output <impact.json>
```

See [`docs/V1.5.1_SANDBOX_BACKFILL.md`](docs/V1.5.1_SANDBOX_BACKFILL.md), [`docs/V1.5.0_PROMPT_STUDIO_2_PLAN_COMPILER.md`](docs/V1.5.0_PROMPT_STUDIO_2_PLAN_COMPILER.md), and [`docs/ROADMAP_IMPLEMENTATION_MATRIX.md`](docs/ROADMAP_IMPLEMENTATION_MATRIX.md).

## v1.3.0 durable workflow kernel and SQLite

V1.3.0 moves mutable repositories, run snapshots, append-only run events, task attempts, checkpoints, run leases, tool idempotency, compensation records, and migration state into one SQLite authority. Run projections and snapshot events are committed transactionally; completed tool effects are replayed by stable idempotency key; file mutations are journaled before side effects; stale runs recover from durable checkpoints instead of process-local assumptions.

Legacy JSON state is imported with byte-exact backups and a hash-keyed import ledger. Existing databases are backed up before schema/import work and restored on any startup failure. A generated migration registry rejects SQL drift. The source-only workflow gate executes 14 crash, append-only, concurrency, migration, idempotency, recovery, and compensation cases.

Verify the complete foundation with:

```bash
python tool/generate_protocol_contracts.py --check
python tool/protocol_contract_test.py
python tool/generate_workflow_migrations.py --check
python tool/workflow_kernel_test.py --project .
python tool/replay_diagnostics.py
```

See [`docs/V1.3.0_DURABLE_WORKFLOW_KERNEL.md`](docs/V1.3.0_DURABLE_WORKFLOW_KERNEL.md), [`docs/MIGRATION.md`](docs/MIGRATION.md), and [`docs/ROADMAP_IMPLEMENTATION_MATRIX.md`](docs/ROADMAP_IMPLEMENTATION_MATRIX.md).

## v1.2.0 typed protocol and tool-schema foundation

V1.2.0 moves model-provider envelope recovery out of the coordinator and establishes one canonical `AgentDecision` protocol with five typed variants: tool, complete, fail, ask-user, and delegate. The current coordinator executes the first three through an explicit legacy bridge and fails closed for future waiting/delegation states.

All 23 governed tools now come from a versioned JSON Schema registry. The same source generates model, OpenAI-compatible, and MCP descriptors; required/optional arguments; compatibility aliases; repair examples; Dart runtime contracts; and coverage gates. Inputs are canonicalized and schema-validated before permission checks or handlers. Outputs are schema-validated before being trusted as evidence. Missing mutation authority, conflicting aliases, and undeclared working-directory or path overrides cannot reach a side effect.

The release adds deterministic compatibility coverage for Ollama, OpenAI-compatible, MCP, and recorded diagnostic envelopes, including 2,000 provider-envelope fuzz cases and missing-mutation-data fuzzing. The two v1.1.7 production replays remain blocking gates. See [`docs/V1.2.0_TYPED_PROTOCOL_FOUNDATION.md`](docs/V1.2.0_TYPED_PROTOCOL_FOUNDATION.md), [`docs/TOOL_PROTOCOL.md`](docs/TOOL_PROTOCOL.md), and [`docs/ROADMAP_IMPLEMENTATION_MATRIX.md`](docs/ROADMAP_IMPLEMENTATION_MATRIX.md).

Verify the source contracts with:

```bash
python tool/generate_protocol_contracts.py --check
python tool/protocol_contract_test.py
python tool/replay_diagnostics.py
```

## v1.1.7 stability freeze and golden replay baseline

The supplied v1.1.6 diagnostic exposed a different convergence failure from the prior zero-byte write. A model wrapped `docs/design/wireframes.md` in Markdown backticks; the runtime accepted those characters literally, created the wrong Windows path, bypassed canonical artifact matching, and spent 21 model requests plus all 12 repairs on repeated reads, copied coordinator metadata, and a no-op rewrite. Model latency reached 1,491,836 ms before `budget_repairs`.

V1.1.7 canonicalizes exact whole-scalar quote and one-to-three-backtick Markdown path wrappers before policy and artifact matching, redirects repeated read-only discovery to a bounded task-specific artifact mutation, protects that recovery with create-only or inspected-hash preconditions, reconstructs incomplete-artifact state across retries, automatically inspects and validates the exact affected artifact after writing, reserves repair capacity before retry, projects coordinator corrections into non-copyable compact history, and ships a golden replay corpus for both supplied production failures.

Run `kristin test --replay-all --project .` to execute the corpus. See [`docs/V1.1.7_STABILITY_REPLAY_BASELINE.md`](docs/V1.1.7_STABILITY_REPLAY_BASELINE.md) and [`docs/ROADMAP_IMPLEMENTATION_MATRIX.md`](docs/ROADMAP_IMPLEMENTATION_MATRIX.md).

## v1.1.6 execution-reliability redesign

The supplied v1.1.5 diagnostic exposed a protocol/coordinator failure, not merely weak model output. `phi4-mini:latest` returned a usable nested `write_file` action with complete calculator-wireframe content, but the protocol adapter preserved `filePath` while dropping the direct nested `content` field. The write tool then converted the missing field to an empty string and created a zero-byte Markdown file. Kristin inspected that same empty file repeatedly, used nine model requests and seven repairs, and spent 702,821 ms of model time before failing with `artifact_scope_mismatch`.

V1.1.6 preserves canonical fields from nested model envelopes, rejects `write_file` calls that omit content, publishes machine-readable required/optional/example tool arguments, tracks empty artifacts as mutation-required state, blocks repeated inspection until a correction is made, safely re-anchors invented external read paths to the selected project root, accepts correct pre-existing artifacts without pointless rewrites, and substantially compacts repeated execution prompts. Execution decoding is deterministic and the single-action output budget is reduced.

See [`docs/V1.1.6_EXECUTION_RELIABILITY_REDESIGN.md`](docs/V1.1.6_EXECUTION_RELIABILITY_REDESIGN.md).

## v1.1.4 deterministic release-test hotfix

The v1.1.3 application source passed Flutter analysis, all 88 direct Flutter tests, and the complete System Test on Windows. The immediately following Release Test failed only in the mock `tiny-model` cold-load fixture. That fixture allowed the successful retry just 40 milliseconds, so repeated validation load could turn a test race into a false product failure.

V1.1.4 replaces fixed millisecond sleeps with explicit local-server handshakes, gives the retry fixture a bounded two-second local deadline, runs Kristin-owned Flutter suites with one worker, and includes the failing test identity in CLI summaries. Production Ollama behavior and governed permissions are unchanged.

See [`docs/V1.1.4_DETERMINISTIC_RELEASE_TESTS_HOTFIX.md`](docs/V1.1.4_DETERMINISTIC_RELEASE_TESTS_HOTFIX.md).

## v1.1.3 workstation validation hotfix

The v1.1.2 Windows validation transcript reached Flutter analysis and tests but exposed one analyzer info and two brittle test contracts. V1.1.3 removes the unused cancellation-binding constructor parameter, makes Ollama progress verification formatter-independent and behaviorally ordered, and emits explicit local-only deployment prohibitions that match the generated-plan test.

See [`docs/V1.1.3_WORKSTATION_VALIDATION_HOTFIX.md`](docs/V1.1.3_WORKSTATION_VALIDATION_HOTFIX.md).

## v1.1.2 local-model resilience and plan capability repair

The supplied diagnostic run made one Ollama request, waited 180,138 ms for a cold `phi4-mini:latest` load, used zero tools or mutations, and failed while 79 model requests remained. V1.1.2 explicitly preloads the selected Ollama model, retries one transient cold-load failure inside the same model request, separates load/first-token/generation deadlines, connects Stop to provider HTTP cancellation, and records model-load progress in diagnostic exports.

The same plan contained an impossible local-only “recruit users and collect feedback” task. Prompt Studio now replaces unsupported human-study instructions with local automated interaction/accessibility checks and an inspectable manual usability checklist. Generated non-manual tasks receive at least two bounded attempts. External design-tool and public-hosting contradictions are replaced rather than appended.

See [`docs/V1.1.2_MODEL_RESILIENCE_HOTFIX.md`](docs/V1.1.2_MODEL_RESILIENCE_HOTFIX.md).

## v1.1.1 Windows compile hotfix

V1.1.0 added `ProjectDiagnosticsService.executionProfile`, which throws `ProductException` when a registered project folder is missing. The defining module, `storage_security.dart`, was not imported, so Flutter analysis and tests stopped with an undefined symbol on Windows. V1.1.1 adds the explicit import and independent Dart/Python regression gates for that exact linkage. No Project Manager behavior, tool permission, or project-boundary rule is broadened by this repair.

See [`docs/V1.1.1_PROJECT_MANAGER_COMPILE_HOTFIX.md`](docs/V1.1.1_PROJECT_MANAGER_COMPILE_HOTFIX.md).

## v1.1.0 Project Manager and capability-aligned execution

The new **Project Manager** tab gives the selected project one operational home for Doctor, Analyze, Test, Build, Run, Stop, recent agent runs, managed-process output, and diagnostic export. The desktop UI, authenticated loopback API, and CLI share the same detected Analyze/Test/Build/Run profile.

V1.1.0 also repairs diagnostic run `run_hkk9czt4wzMPTp3bsaqLnpNOx2`. Prompt Studio had labeled an implementation plan as `plan`, so the first task promised wireframe files while receiving only read-only tools. The selected local model inspected the one-file project for two attempts, recorded zero mutations, and stopped at its turn limit despite substantial run budget remaining.

The compiler now derives effective capability from each task's promised outputs. Artifact-producing tasks become governed build work and must record mutation evidence before completion; explicitly planning-only tasks remain read-only. Equivalent deployment tasks are deduplicated. See [`docs/V1.1.0_PROJECT_MANAGER_PREVIEW.md`](docs/V1.1.0_PROJECT_MANAGER_PREVIEW.md).

## v1.0.9 release-lineage contract hotfix

V1.0.9 fixes the single test failure reported after the v1.0.8 SDK environment repair. The Windows workstation successfully completed formatting, dependency resolution, and Flutter analysis, but `source_contract_test.dart` still required the v1.0.5 path-hygiene archive SHA-256. The v1.0.8 version-control ledger had accidentally omitted that transitive ancestor.

`VERSION_CONTROL.json` now carries a structured v1.0.5–v1.0.8 release lineage with exact hashes and an explicit preservation contract. Dart, offline system, and release validators parse and verify that structure, preventing future heads from silently truncating inherited provenance. The v1.0.8 SDK environment and `--no-pub` compile gates are unchanged. See [`docs/V1.0.9_LINEAGE_CONTRACT_HOTFIX.md`](docs/V1.0.9_LINEAGE_CONTRACT_HOTFIX.md).

## v1.0.8 Windows Flutter dependency-resolution hotfix

V1.0.8 fixed a workstation-only mismatch reported against v1.0.7: `flutter pub get`, `flutter analyze`, and all 78 Flutter tests passed when run directly, but `kristin test --system` failed with exit code 65 at **Flutter dependency resolution**. Kristin's reduced child-process environment omitted Windows Pub-cache locations and SDK network/certificate variables, so Flutter launched from Kristin did not receive the same environment as Flutter launched from the terminal.

Dart and Flutter commands now use a dedicated bounded SDK environment profile. It preserves `APPDATA`, `LOCALAPPDATA`, Pub cache/mirror settings, Flutter and Dart SDK locations, Android and Java locations, enterprise proxy variables, and certificate overrides without widening the environment used by ordinary project commands. After one explicit `flutter pub get`, analyzer and test gates use `--no-pub` to avoid repeated package resolution.

Release source validation now runs with `--skip-sdk`; the CLI performs the formatter, dependency, analyzer, and test gates exactly once. Captured SDK output is redacted before it is written to reports. See [`docs/V1.0.8_SDK_ENVIRONMENT_HOTFIX.md`](docs/V1.0.8_SDK_ENVIRONMENT_HOTFIX.md).

## v1.0.7 failed-run context and protocol recovery hotfix

V1.0.7 fixes a diagnostic run in which an ordinary calculator plan silently opted into failed-run memory because the request mentioned calculation **history**, **error handling**, and tests. Eight failed episodes then entered the model context, and a small local model copied the historical phrase `Inspect project and establish evidence baseline` into its `action` field until the repair budget was exhausted.

Unsuccessful episodes are now diagnostic-only: the caller must explicitly opt in, or the user must pin the episode. Query vocabulary can no longer broaden that scope. The protocol adapter recognizes the observed composite planning action and maps it to a safe, task-appropriate allowlisted tool; repair examples no longer choose the alphabetically first tool. Prompt Studio also aligns generated tasks with local-only mode and available tools, replacing unavailable external GUI/public-hosting claims with inspectable local design artifacts, bounded previews, packages, and honest manual steps.

Mutating plans now reject Kristin’s own source checkout as the target. Create or select a separate folder for the application being generated. Do not retry a plan produced by the older build; regenerate the prompt and task list after upgrading. See [`docs/V1.0.7_FAILED_RUN_RECOVERY_HOTFIX.md`](docs/V1.0.7_FAILED_RUN_RECOVERY_HOTFIX.md).

## v1.0.6 workspace-boundary canonicalization merge

v1.0.6 adopts the user-supplied Windows reparse-point fix as part of the canonical lineage while retaining all v1.0.5 path recovery and generated-tree hygiene changes. Extended Windows paths such as `\\?\C:\...` and `\\?\UNC\...` are normalized before project-boundary comparison, so a valid in-project absolute path is not rejected merely because the canonical project root crossed a junction, symlink, redirected profile, or other reparse point.

The exact parent and patch archive hashes are recorded in `VERSION_CONTROL.json`. See [`docs/V1.0.6_WORKSPACE_BOUNDARY_CANONICALIZATION.md`](docs/V1.0.6_WORKSPACE_BOUNDARY_CANONICALIZATION.md).

## v1.0.5 path and validation hygiene hotfix

v1.0.5 repairs two failures reported from a fully configured Windows Flutter workstation.

First, model-generated absolute paths outside the selected project no longer consume the complete repair budget when they are clearly compatibility paths. Kristin can safely rebase:

- common virtual roots such as `/workspace`, `/project`, and `/repo`;
- a stale absolute path that still contains the selected project's directory name;
- an existing project-relative suffix for bounded read-only inspection;
- arbitrary directory-listing and text-search scopes back to the selected project root.

Every recovery remains inside the canonical selected project, records only a hash of the original absolute path, and emits `tool.path_rebased_to_active_project`. Hidden or secret-like paths are not recovered automatically. Arbitrary external writes remain blocked and emit `tool.path_recovery_rejected` with an actionable project-selection message.

Second, `kristin test --system` and `kristin test --release` no longer treat Flutter's generated `windows/flutter/ephemeral/flutter_windows.dll` and `.pdb` files as source-release violations. Validation, secret scanning, and deterministic packaging now share one generated-state policy. Generated workstation files are ignored by source gates and omitted from release archives, while genuine oversized source files and symlinks still fail validation.

The diagnostic ZIP summary now includes a **Project path recovery** section so rebased and rejected paths can be traced without exposing the original absolute path.

## v1.0.4 Windows validation hotfix

v1.0.4 repairs the Dart source-contract interpolation failure reported by Flutter 3.44.0, removes the two remaining analyzer info findings, and separates deterministic source validation from native Flutter compilation. `scripts/validate_architecture.py` now runs source-only gates; `kristin test --full`, `--system`, and `--release` run formatter, analyzer, and Flutter tests in dedicated stages. Validator failures now print their exact gate and bounded detail instead of appearing only as a generic command exit.

## v1.0.3 repeated-tool loop recovery hotfix

This build repairs the failure:

```text
agent_stalled_repeated_tool_outcome:
The model repeated the same read-only tool call and received the same result 3 times.
```

The loop detector remains active, but an identical successful read is no longer executed three times and then treated as an immediate terminal failure. Within one work-item attempt Kristin now:

1. fingerprints the model-requested read-only tool and arguments;
2. reuses the already recorded result instead of spending another tool call;
3. records `agent.repeated_tool_call_blocked` with the cached outcome fingerprint;
4. substitutes one unused, allowlisted, bounded read-only evidence action when safe;
5. excludes hidden and secret-like paths from automatic file inspection;
6. completes only the dedicated read-only evidence-baseline item after a root listing, hashed file evidence, and independent structural evidence are recorded;
7. preserves the terminal loop stop when no safe unused progress action remains.

Typical recovery from a model that keeps requesting the project root is:

```text
list_directory .
        ↓ duplicate blocked
inspect_file README.md
        ↓ duplicate blocked again
index_project or a second safe hashed file
        ↓
read-only evidence baseline completed
```

General question-answering, implementation, verification, and mutation work cannot use this deterministic completion. They still require the selected model to provide a grounded `complete` action and continue to enforce the existing tool allowlist, permissions, project boundary, stale hashes, transactions, and budgets.

The diagnostic ZIP summary now has a dedicated **Agent loop recovery** section containing blocked duplicate requests, substituted actions, outcome fingerprints, and the final recovery or terminal decision.

## v1.0.2 budget and diagnostic-export hotfix

This build repairs the retry sequence in which one work item exhausted its per-attempt agent-turn limit and a later attempt immediately failed with:

```text
budget_model_requests: Model-request budget exhausted.
```

The coordinator now assigns a bounded turn allowance from the remaining run budget, reserves every model request before dispatch, records request timing and outcomes, and decides whether a retry has enough capacity before scheduling it. Repeated identical read-only tool outcomes are stopped as a model-stagnation loop. A failed run cannot be executed again with spent counters; **Retry** creates a fresh linked run with reset attempts and a plan-scaled budget.

The Logs workspace now has **Save all logs**. It creates a redacted diagnostic ZIP containing retained run state, a readable run-diagnostic summary, budget counters, retry decisions, events, audit records, evidence metadata, and bounded managed-process output. Source-like payload fields are replaced by hashes and recognized secrets are redacted. The archive can still contain project names, request text, URLs, relative paths, errors, and model-response previews, so review it before sharing.

CLI equivalent:

```powershell
.\kristin.cmd logs --export --run-id RUN_ID
```

## v1.0.1 model-protocol hotfix

This build repairs the run failure:

```text
work_item_failed: model_action_invalid:
The model must return action=tool, complete, or fail.
```

Kristin now accepts a wider set of bounded local-model response shapes—including nested chat-completion content, snake-case `function_call`, `tool_calls`, double-encoded JSON, safe tool/argument aliases, and ReAct-style action blocks—then resolves every proposed tool against the current work item’s allowlist. Repeated malformed responses receive two consecutive repair attempts, and evidence-baseline work may use one deterministic read-only project listing before failing. Model evidence now includes a redacted bounded response preview for debugging.

No parser normalization can grant a new permission, select an unapproved tool, escape the active project, bypass stale-file checks, start an unapproved process, or use the network without the existing governed approval path.

v1.0 also fixes the reported runtime failure:

```text
path_absolute_rejected: Tool paths must be relative to the active project.
```

An absolute path that resolves **inside the selected project** is now converted to a project-relative path. Paths outside the project, parent traversal, unsafe URI schemes, and symbolic-link escapes remain blocked. Recoverable path and tool-argument mistakes receive bounded correction attempts instead of immediately failing the work item.

> **Release classification:** source product preview. This ZIP is not a signed installer or a precompiled desktop application. A compatible Flutter workstation is required to resolve dependencies, analyze, test, and build the desktop app.

## Main experience

### Chat-first project work

- A central ChatGPT/Claude-style composer.
- Inline plans, grouped permission requests, progress, results, citations, and evidence.
- Primary navigation for **Chats** and the operational **Project Manager**.
- A collapsible **Build & Debug** submenu for **Runs, Prompt Studio, Knowledge, Skills, and Logs**.
- A pan-and-zoom run graph with node details and cancellation controls.
- Project **Doctor** and **Quick Test** actions that do not require an AI model.

### AI Prompt Studio

Enter a simple goal such as:

```text
Build a modern calculator application with standard and scientific functions.
```

Kristin asks the selected model for a schema-validated prompt draft containing:

- purpose and system instructions;
- editable user-prompt template;
- variables, assumptions, and clarifying questions;
- measurable acceptance criteria;
- output expectations;
- guardrails and stop conditions;
- evaluation cases and recommended task mode.

Prompt actions include **Generate**, **Improve**, **Simplify**, and **Add detail**. Every accepted change is saved as an immutable prompt version with a model identity, content hash, action, creator, and timestamp.

### Adaptive task planning

An approved prompt can become an appropriately sized plan. One atomic request can remain one task; large work can use phases and up to 100 executable tasks.

Each task can include:

- phase, objective, instructions, and dependencies;
- acceptance criteria, verification steps, and expected artifacts;
- proposed governed tools;
- complexity from 1–10 and effort points;
- uncertainty, risk, and confidence;
- expected model turns, tool calls, and retry limit;
- enabled or manual status.

Unknown tools are removed. The deterministic compiler derives permissions from Kristin’s governed tool registry. Plans with cycles, missing dependencies, invalid disabled dependencies, or more than 100 tasks are rejected.

Editing a plan creates a new revision and retains `previousPlanId`; an approved or historical plan is never silently overwritten.

### Run and stop controls

Prompt Studio supports:

- **Run all tasks**;
- review the compiled execution plan before approval;
- run one task with its transitive prerequisites;
- edit a task and save a new plan revision;
- stop active generated-plan runs through the governed cancellation path.

The existing coordinator continues to own permissions, tool execution, managed processes, evidence, checkpoints, rollback, logs, audit records, and terminal run memory.

### Knowledge and memory

- Immutable research provenance for fetched sources and search snapshots.
- Content-addressed raw and extracted objects under the local Kristin data root.
- Project notes, research sources, search snapshots, and terminal-run memory.
- Local hybrid ranking using lexical relevance, deterministic semantic features, recency, trust, and pinning.
- Inspectable `[K1]` citation markers.
- Automatic context excludes failed/interrupted episodes unless the task concerns debugging or the user explicitly includes or pins them.
- Local reindexing and portable project knowledge ZIP export.

### Files, diagnostics, and logs

- Governed text and bounded binary inspection/writing as a foundation for format adapters.
- Automatic project profiles for Flutter/Dart, Node.js, Python, Go, Rust, .NET, Maven, Gradle, CMake, and static sites.
- Simple, technical, and raw local logs.
- Deterministic source validation, SBOM generation, bounded secret scanning, and release manifests.

See [`docs/V1.0_PRODUCT_PREVIEW.md`](docs/V1.0_PRODUCT_PREVIEW.md) for the precise v1.0 behavior and security boundary.

## First use

### 1. Diagnose the source checkout

Windows PowerShell:

```powershell
.\kristin.cmd doctor --project .
.\kristin.cmd test --quick --project .
```

macOS or Linux:

```bash
./kristin doctor --project .
./kristin test --quick --project .
```

PowerShell does not execute commands from the current directory without `./` or `.\`. Running `dart format` without a path only prints usage; use `dart format .` to format the project or the non-mutating release check shown below.

### 2. Run the complete verification ladder

```powershell
.\kristin.cmd test --full --project .
.\kristin.cmd test --system --project .
.\kristin.cmd test --release --project .
```

The levels are:

| Command | Coverage |
|---|---|
| `test --quick` | Offline grammar, Python, architecture, security, and secret checks |
| `test --full` | Quick checks plus non-mutating format verification, dependency resolution, analysis, and Flutter tests |
| `test --system` | Full checks plus Prompt-to-Task, path, dependency, recovery, API, and CLI fixtures |
| `test --release` | System checks plus complete source validation and two byte-identical ZIP builds |

Each test invocation writes JSON, Markdown, and raw log reports under `reports/` unless an output JSON path is supplied.

### 3. Launch with Flutter

Windows:

```powershell
.\RUN_WINDOWS.bat
```

macOS:

```bash
./RUN_MAC.command
```

Linux:

```bash
./RUN_LINUX.sh
```

The launchers generate missing platform runners where supported, resolve packages, validate source, and start Flutter. Review the first terminal error when launch stops before the UI appears.

### 4. Open a project and begin

1. Open **Project Manager**.
2. Choose, register, or create a project folder.
3. Run **Doctor**, then use **Analyze**, **Test**, **Build**, **Run**, or **Stop** as needed.
4. Return to **New chat** for a normal conversation, or open **Prompt Studio** for the Prompt-to-Task workflow.
5. Review the generated prompt and task plan.
6. Approve only the access the run requires.
7. Follow progress in chat or **Runs**.

A model is required for prompt generation and agent conversations. Project diagnostics, local knowledge inspection, and Quick Test do not require one.

## Command-line reference

```text
kristin doctor [--project PATH] [--json] [--output REPORT.json]
kristin test --quick [--project PATH]
kristin test --full [--project PATH]
kristin test --system [--project PATH]
kristin test --release [--project PATH]
kristin analyze [--project PATH]
kristin build [--project PATH]
kristin run [--project PATH] [--execute]
kristin logs [--tail 50] [--data-root PATH]
kristin knowledge --data-root PATH --project-id ID [--query TEXT]
kristin knowledge --data-root PATH --project-id ID --archive
kristin knowledge --data-root PATH --project-id ID --memory
kristin report [--project PATH] [--output REPORT.json]
```

`kristin run` is a dry run by default and starts the detected command only with `--execute`. See [`docs/CLI.md`](docs/CLI.md).

## Prompt and task-plan API

The authenticated loopback API adds:

```text
GET  /v1/prompts
POST /v1/prompts/generate
POST /v1/prompts/versions
GET  /v1/prompts/{promptId}/versions
POST /v1/task-plans/generate
GET  /v1/task-plans
GET  /v1/task-plans/{planId}
PUT  /v1/task-plans/{planId}
POST /v1/task-plans/{planId}/compile
```

Plan updates create new immutable revisions. Compilation can target the full enabled plan or selected tasks plus dependencies. See [`docs/API.md`](docs/API.md).

## Project profiles

Override automatic detection with `kristin.project.json`:

```json
{
  "type": "Custom service",
  "test": {
    "executable": "python3",
    "arguments": ["-m", "pytest", "-q"]
  },
  "build": {
    "executable": "python3",
    "arguments": ["-m", "build"]
  },
  "run": {
    "executable": "python3",
    "arguments": ["app.py"]
  }
}
```

Commands are argument arrays and are launched without a command shell. See [`docs/PROJECT_PROFILES.md`](docs/PROJECT_PROFILES.md).

## Local data layout

The exact base directory is platform-dependent. V1.3 uses:

```text
state/workflow.sqlite3
support/migration-backups/
checkpoints/<run-id>/
research-archive/<project>/records/<archive-id>.json
research-archive/<project>/objects/<prefix>/<sha256>.<extension>
cache/knowledge-index/<project>.json
knowledge-exports/kristin-knowledge-<project>-<timestamp>.zip
```

Legacy `state/*.json` collections are imported by source hash with byte-exact backups and remain available for operator rollback; they are not the runtime authority once SQLite exists. Generated prompt and plan metadata cannot grant permissions or mutate project files by itself.

## File-format boundary

The governed tools inspect common text/source formats and bounded binary files, report type and SHA-256 information, and write bounded base64-decoded binary content transactionally.

This is not universal conversion. Reliable PDF, DOCX, XLSX, PPTX, audio, video, CAD, database, and specialist output still require dedicated sandboxed adapters, producers, and validators.

## Security and production boundary

This source preview does **not** complete every production-hardening item, and the currently supported security boundary is narrower than the long-term roadmap:

- Governed project tools remain the primary supported authority model. **Owner Mode is a roadmap target and is not implemented in v1.9.0+190.**
- The Linux reference namespace worker, HTTPS broker, and one-use secret broker are present in source, but **Windows and macOS native worker backends still fail closed**.
- Approved processes, interpreters, MCP servers, and file workers still run with the desktop user's operating-system privileges; this source line must not be described as hostile-code isolation.
- SQLite provides transactional mutable state and durable run recovery, but it does not provide distributed replication or OS-level execution isolation.
- File mutations are compensation-journaled and hash-reconciled; non-compensatable external effects still fail closed after ambiguous process failure rather than being automatically repeated.
- Research host validation still needs connection-time address pinning to completely close DNS-rebinding risk.
- The audit chain is tamper-evident, not externally signed or anchored.
- Support and knowledge exports can contain project-confidential data and require review.
- No signed installer, platform notarization, or authenticated updater is included.
- **Signed-manifest v1 trust is disabled, and Signed Manifest v2 is not yet available.** Do not rely on signed plugin, skill, MCP, A2A, or source-update manifests as production trust anchors in this release.

Read [`SECURITY.md`](SECURITY.md), [`docs/SECURITY_MODEL.md`](docs/SECURITY_MODEL.md), [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md), [`docs/PRIVACY.md`](docs/PRIVACY.md), [`docs/SUPPORT_POLICY.md`](docs/SUPPORT_POLICY.md), and [`docs/V1.0_PRODUCT_PREVIEW.md`](docs/V1.0_PRODUCT_PREVIEW.md) before using Kristin with untrusted projects or sensitive data.

## Upgrade compatibility

Use a clean extraction of the v1.5 source ZIP. The source folder and Kristin application-data folder are separate, so existing projects and archived research remain separate; mutable JSON state is migrated into SQLite with verified backups. v0.8 research snapshots and prior terminal runs retain the v0.9 migration and reconciliation behavior.

See [`docs/MIGRATION.md`](docs/MIGRATION.md).

## Validation boundary

`tool/validate_release.py` checks the allowlisted Dart tree, Dart grammar when the optional parser is present, imports, architecture, security invariants, chat UX, research/memory wiring, v1 Prompt-to-Task behavior, release hygiene, SBOM generation, and bounded secret scanning.

A package is not a compiled desktop release unless formatting, Flutter dependency resolution, analysis, tests, and target-platform builds pass on a suitable workstation.
