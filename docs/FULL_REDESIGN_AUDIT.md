# Kristin Local Agent v0.3.14 — Full Redesign Audit

## Decision

Kristin needs a redesign of the agent core. It does **not** require throwing away every part of the application, but the current planning, orchestration, model-runtime, build queue, verification, and storage architecture should not be extended further with patches.

The current implementation cannot reliably become a general system that creates 100+ genuinely different applications because core behavior is selected by keyword branches and deterministic domain code. The strongest example is that the desktop UI contains a complete hardcoded Telegram bridge generator.

## Immediate correction

`./chat 1 + 1 =` must call the configured model. It is a model-health test, not an opportunity for Kristin to calculate locally.

Current behavior is wrong in three places:

- `lib/services/chat_fallback.dart` implements local arithmetic, greetings, thanks, and small-talk responses.
- `lib/services/agent_engine.dart` calls `ChatFallback.tryImmediateResponse()` before invoking the model.
- `lib/services/init_service.dart` requires the local arithmetic shortcut to pass initialization.

This masks the actual failure. When phi4-mini cannot answer `1 + 1`, Kristin currently reports success without exercising phi4-mini.

## Why initialization takes about 255 seconds

The reported duration is explained by nested retry logic:

1. The first warm-up probe waits 30 seconds for response headers.
2. `ModelClient._postOllamaTextStream()` silently retries with a 65-second header window.
3. `InitService` then attempts an unload, waits, and starts a second probe.
4. The second probe waits 60 seconds, then the model client silently retries with a 95-second window.

That is roughly 30 + 65 + unload/delay + 60 + 95 seconds, which closely matches the reported 255.6 seconds.

The report says “one safe unload/retry,” but the implementation can make four generation attempts. This is not a controlled runtime state machine; it is nested retry behavior split across two classes.

“No response headers” means Ollama accepted or held the HTTP connection but did not begin the response. There is no partial output to recover. The system must diagnose model loading/runtime state instead of retrying the same request with larger timeouts.

## Confirmed hardcoded architecture

### 1. A complete Telegram application is embedded in the UI

`lib/screens/home_screen.dart` contains:

- `_isTelegramKristinBridgeQueue()`
- `_executeDeterministicTelegramBridgeStage()`
- hardcoded `requirements.txt`
- hardcoded `.env.example`
- hardcoded `.gitignore`
- hardcoded `.kristin-run.json`
- hardcoded `config.py`
- hardcoded `kristin_client.py`
- hardcoded `session_manager.py`
- hardcoded `message_utils.py`
- hardcoded `handlers.py`
- hardcoded `bot.py`
- hardcoded unit tests
- hardcoded README content
- token extraction and environment generation

This is exactly the architecture that must be removed. The UI should never contain generated application source code or domain build logic.

### 2. The planner is a keyword classifier

`lib/services/task_queue_planner.dart` chooses project type using prompt text such as:

- `telegram`, `fastapi`, or `python` → Python
- `flutter` → Flutter
- `node` or `npm` → Node
- `dart` → Dart
- `web page`, `website`, `landing page`, or `html` → static HTML

It then supplies deterministic project names and deterministic stage lists for Telegram, Flutter, static HTML, and Python.

The project type is restricted to a fixed enum:

- `static-html`
- `python`
- `flutter`
- `node`
- `dart`
- `generic`

This prevents open-ended technology discovery and makes new stacks require core-code changes.

### 3. Workflow requirements are inferred from regexes

`lib/services/agent_engine.dart` decides whether a task requires inspection, mutation, verification, process start, API inspection, or web research using English/Russian keyword regexes.

It also has hardcoded rules such as:

- Telegram/API tasks require at least six files.
- “project structure” requests require at least four files.
- Python/Telegram keywords control verification tool availability.
- Telegram and local API terms control research requirements.

File count is not evidence of completeness. A correct one-file program may be rejected, while a six-file placeholder may pass the structural gate.

### 4. Scaffolding generates canned projects

`lib/services/tool_registry.dart` exposes `create_project` with fixed templates:

- blank
- html
- python
- flutter
- node

The HTML, Python, and Node templates include canned Hello World content. This creates the wrong mental model: the core agent knows application forms and fills templates instead of deriving a project from a task contract.

### 5. Verification is hardcoded by project type

`lib/screens/home_screen.dart` contains direct branches for:

- static HTML → `verify_project`
- Python → `compileall`, pytest/unittest
- Flutter → `flutter analyze`, `flutter test`
- Dart → `dart analyze`, `dart test`
- Node → package scripts or selected JavaScript entry files

Technology-specific verification is necessary somewhere, but it should live in replaceable capability plugins, not in the UI or central orchestration code.

### 6. Run detection contains special cases

`lib/services/tool_registry.dart` directly detects Flutter, Dart, Node, static HTML, FastAPI, Flask, Python scripts, and Telegram bots. It also contains Telegram-specific dependency and environment recovery.

Run adapters are useful, but they must be isolated behind plugin interfaces and discovered from project manifests. Domain logic such as Telegram token extraction does not belong in the generic tool registry.

### 7. Storage does not satisfy the intended local knowledge architecture

Current storage is mainly whole-file JSON:

- `settings.json`
- `memory.json`
- `prompts.json`
- `capabilities.json`
- `task_queues.json`

`MemoryStore` loads all entries into one in-memory list and rewrites the entire JSON file. There is no embedded object database, project knowledge graph, chunk store, embedding index, retrieval layer, event journal, migration framework, or transactional update model.

This is local, but it is not the requested scalable local-first, non-SQL memory architecture.

### 8. The main screen is an orchestration monolith

`lib/screens/home_screen.dart` is over 5,000 lines and contains UI, task queue execution, project discovery, web research, model analysis, repair logic, verification, deterministic code generation, secret extraction, and process launching.

The UI cannot remain the execution engine.

## What should be kept

The following concepts are reusable after interface cleanup:

- Native Flutter desktop shell and visual components
- Workspace path validation and symlink protections
- Generic file read/write/replace/delete tools
- Finite command execution and managed long-running processes
- Loopback proxy bypass logic
- Local authenticated HTTP API concept
- Cancellation and streamed token events
- Capability reporting concept
- Local-only default behavior

These should be retained behind new interfaces rather than copied unchanged into another monolith.

## Required v1 architecture

### A. Model Runtime Supervisor

One component owns all model lifecycle behavior.

Responsibilities:

- provider discovery
- endpoint health
- model inventory
- model load state
- one bounded warm-up operation
- generation queue
- cancellation
- circuit breaker
- telemetry for every request
- diagnostic collection from Ollama process state and logs

Required runtime states:

- `serverUnavailable`
- `serverReady`
- `modelNotInstalled`
- `modelLoading`
- `modelReady`
- `modelBusy`
- `modelFailed`

There must be no hidden retry inside the transport plus another retry in initialization. Retry policy belongs only in the supervisor and every attempt must be visible.

`./chat` always calls the selected model. If it fails, Kristin returns a model failure. It must not answer the requested content with deterministic local logic.

### B. Task Contract Compiler

Convert the user request into a typed, model-authored task contract.

The contract should contain:

- objective
- constraints
- target platform
- required capabilities
- expected user-visible behavior
- artifacts
- acceptance criteria
- security/privacy rules
- runtime expectations
- unknowns that require discovery

The compiler may validate and normalize the contract, but it must not replace it with a domain template.

If the model is unavailable, building stops with a clear error. A hardcoded generic application must not be generated as a substitute.

### C. Capability Plugin Registry

Technology support should be supplied by local plugins/manifests rather than core conditionals.

Each capability plugin defines:

- capability ID
- detection rules based on files/manifests, not user keywords
- optional official scaffold command
- dependency discovery
- finite verification commands
- run command discovery
- ignored paths
- safety policy
- environment requirements

Examples may include Flutter, Dart, Python, Node, static web, Rust, CMake, or future stacks, but the orchestrator only knows the plugin interface.

The project type becomes an open capability identifier, not a fixed enum.

### D. General Build Planner

The planner receives:

- task contract
- workspace inspection
- installed capabilities
- available tools
- project history
- research evidence

It returns a validated DAG of stages with:

- dependencies
- expected artifacts
- allowed tools
- completion evidence
- verification command or acceptance check
- retry budget

There should be no Telegram branch, calculator branch, website branch, fixed file-count rule, or deterministic project stage list.

### E. Artifact Executor

The executor applies one plan node at a time.

For each node:

1. inspect relevant current files
2. ask the model for a bounded change set
3. generate or patch files
4. record exact diffs/artifacts
5. run declared finite checks
6. store evidence
7. send failures back to the model for repair

`create_project` should create an empty workspace or invoke a capability plugin’s official scaffold command. It should not inject Hello World business content.

### F. Evidence-Based Verifier

Verification should evaluate the task contract, not file count.

Evidence types:

- command exit codes
- test results
- analyzer/compiler output
- file existence and content assertions
- API contract checks
- screenshots or UI probes where available
- run health
- acceptance criteria mapping

A project is complete only when each required acceptance criterion is linked to evidence or explicitly marked unproven.

### G. Local Object Knowledge Store

Use an embedded local NoSQL/object store plus local files.

Suggested logical collections:

- conversations
- messages
- memories
- memory revisions
- projects
- project files metadata
- task contracts
- build plans
- task runs
- tool events
- model requests
- artifacts
- verification evidence
- capabilities
- document chunks
- embeddings metadata

Large source files, logs, binary artifacts, and vector indexes remain local files referenced by object records.

Required behavior:

- schema migrations
- atomic object updates
- append-only execution journal
- crash recovery
- per-project indexes
- selective retrieval instead of loading all memory into prompts
- complete local deletion/export

### H. Thin UI

The Flutter UI should:

- submit commands
- display model/runtime status
- stream events
- show plans, diffs, evidence, and failures
- allow cancellation and approval where required

It must not contain domain generators, verification branches, process commands, or application source strings.

## Proposed module boundaries

```text
lib/
  app/
    ui/
    state/
  core/
    contracts/
    events/
    errors/
  model_runtime/
    model_runtime_supervisor.dart
    provider_adapter.dart
    ollama_adapter.dart
    openai_compatible_adapter.dart
    runtime_diagnostics.dart
  orchestration/
    task_contract_compiler.dart
    build_planner.dart
    build_executor.dart
    repair_engine.dart
    acceptance_auditor.dart
  capabilities/
    capability_plugin.dart
    capability_registry.dart
    manifests/
  tools/
    tool.dart
    tool_registry.dart
    file_tools.dart
    command_tools.dart
    process_tools.dart
    research_tools.dart
  workspace/
    workspace_inspector.dart
    project_indexer.dart
    artifact_store.dart
  persistence/
    object_store.dart
    repositories/
    migrations/
    local_file_store.dart
  api/
    local_api_server.dart
  diagnostics/
    doctor_service.dart
    initialization_service.dart
```

## Initialization redesign

Split the current `./init` into explicit levels.

### Fast startup

Runs automatically and should complete quickly:

- open object store
- validate workspace
- load settings
- register tools/plugins
- check Ollama HTTP server
- inspect installed models

It does not perform long generation retries.

### Model test

A separate visible operation:

- send one minimal generation request
- show model state transitions
- collect `api/ps`, model metadata, process/log diagnostics
- no nested retry
- one optional user-visible recovery action

The test prompt can be `Reply with exactly READY`, but success requires real model output.

### Full doctor

Runs file, command, process, API, plugin, storage, and model diagnostics. Independent subsystem results remain independent. A model failure should not imply workspace failure, and a passing arithmetic shortcut should never imply model health.

## Mandatory acceptance tests for the redesign

1. `./chat 1 + 1 =` produces a model request event and the final answer comes from the selected model.
2. With Ollama stopped, `./chat 1 + 1 =` reports model unavailability and does not calculate locally.
3. The repository contains no Telegram application source outside example/test fixtures or optional external capability packs.
4. `home_screen.dart` contains no build execution, verification, project detection, or generated source code.
5. The core planner contains no domain keywords such as Telegram, calculator, landing page, FastAPI, or Flutter.
6. No completion rule uses a minimum number of files.
7. Project capability IDs are open strings resolved by plugins, not a fixed project-type enum.
8. One warm-up operation has one visible timeout and at most one visible recovery action.
9. Every model request records provider, model, endpoint, start time, first-token time, finish time, result, and failure class.
10. A failed build maps each failed acceptance criterion to concrete evidence.
11. At least 100 diverse prompt fixtures can be planned without adding prompt-specific branches.
12. All conversations, plans, events, memories, indexes, and reports remain local by default.
13. No SQL database is used as the core store.
14. Restarting during a build recovers the task journal without corrupting the queue.
15. Adding a new technology requires a capability plugin/manifest, not editing the central planner or UI.

## Migration sequence

### Phase 0 — Stop masking model failure

- Remove immediate chat answers from the execution path.
- Remove the arithmetic shortcut from initialization.
- Add model request tracing.
- Replace nested retry logic with one runtime supervisor.
- Prove phi4-mini can answer through the exact endpoint Kristin uses.

### Phase 1 — Extract orchestration from UI

- Move queue execution, verification, research, analysis, and repair out of `home_screen.dart`.
- Delete the deterministic Telegram generator and all embedded source strings.
- Make the UI consume orchestration events only.

### Phase 2 — Introduce contracts and plugins

- Add typed task contracts.
- Add capability plugin interface and registry.
- Move technology detection, verify, and run behavior into plugins.
- Remove fixed project type enum and keyword project selection.

### Phase 3 — Replace planner/executor

- Replace deterministic fallback stages with a model-authored validated DAG.
- Replace regex workflow classification with explicit contract fields.
- Replace minimum-file gates with artifact and acceptance evidence.

### Phase 4 — Replace JSON-list persistence

- Introduce embedded object storage and repositories.
- Add event journal, migrations, project index, retrieval, and local embeddings metadata.
- Migrate existing JSON data once, preserving user data.

### Phase 5 — Generalization test suite

- Build a corpus of at least 100 different requests.
- Measure planning validity, artifact diversity, verification success, repair success, and absence of domain-specific branches.
- Treat any new request-specific core branch as an architecture regression.

## Final conclusion

A full redesign is justified, but it should target the core rather than restart the entire product. Keep the native shell, generic tools, path safety, local API concept, process management, and useful UI components. Replace the model-runtime handling, planner, executor, queue engine, verification architecture, storage layer, and all domain-specific generation logic.

Do not add another fallback template to v0.3.14. The next implementation should begin as a v1 core migration with Phase 0 model-runtime proof as the first gate.
