# Architecture

## Active path in v1.5

```text
Desktop Chat / Project Manager / authenticated loopback API / CLI
                              │
                              ▼
                        ProductRuntime
            ┌─────────────────┼────────────────────┐
            │                 │                    │
       project profile   prompt/plan services   governed RunCoordinator
                                                   │
                                  typed AgentDecision + Tool Schema Registry
                                                   │
                                      policy + workspace boundary
                                                   │
                  ┌────────────────────────────────┴─────────────────────────┐
                  │                                                          │
          read/project services                                      governed tools
                  │                                                          │
                  └──────────────────────┬───────────────────────────────────┘
                                         ▼
                             DurableWorkflowStore
                  SQLite events · runs · leases · idempotency
                  checkpoints · attempts · compensation · migration
                                         │
             ┌───────────────────────────┴────────────────────────────┐
             │                                                        │
     project filesystem/checkpoints                     immutable object/archive store
```

`main.dart` creates one `ProductRuntime`. The desktop UI and loopback API call that facade. UI code does not open project files, execute commands, perform research, or mutate persistence directly.

## V1.5 specification-to-execution boundary

Prompt Studio 2 introduces a pure compilation boundary before governed execution:

```text
model/user proposal
  → product_specification.v2 + task_plan.v2
  → strict schema validation and canonicalization
  → stable-ID/reference and graph validation
  → capability derivation and 23-tool coverage
  → local-only/data/deployment/human/self-modification policy
  → artifact, validator, acceptance-evidence, and budget checks
  → deterministic topological order and batches
  → plan_compilation_report.v1
  → explicit review/approval
  → existing typed tool gateway and durable v1.3 kernel
```

Compilation is side-effect free and records `sideEffectsPerformed: false`. The report contains canonical hashes, blocking issues, warnings, required approvals, task states, ordering, batches, quality, and simulation. A model cannot make a plan executable by asserting that a tool, permission, sandbox, external service, artifact validator, or human workflow exists.

`PromptStudioV2Service` is shared by the runtime, authenticated loopback API, and source CLI. Provider parsing remains outside this compiler, and tool dispatch remains behind the v1.2 typed schema gateway. This avoids adding another policy branch to the coordinator monolith.

### V1.4 sandbox prerequisite

The roadmap places OS sandboxing before Prompt Studio 2. V1.5 does not claim that skipped milestone. The capability catalog marks process execution, process management, command-backed verification, network research, deployment packaging, and MCP as sandbox-dependent. With `sandboxAvailable: false`, compilation emits `sandbox_required` and is non-executable. A legacy unsandboxed dry-run override must be explicit, creates a warning and approval requirement, and does not change the actual OS boundary.

## Probabilistic decision, deterministic shell

Provider-native responses are translated by dedicated adapters into one versioned `AgentDecision`:

```text
provider response
  → Ollama/OpenAI-compatible/MCP/recorded adapter
  → ToolDecision | CompleteDecision | FailDecision
    | AskUserDecision | DelegateDecision
  → generated tool input contract
  → compatibility canonicalization
  → schema validation
  → permission and path authorization
  → governed handler
  → generated output validation
  → evidence + durable event
```

Provider compatibility belongs in `agent_protocol.dart`, not the coordinator. `tool_schema.dart` and `schemas/tool_registry.v2.json` define the 23 governed tools. Canonicalization may preserve equivalent safe representations, but cannot invent missing authority.

## Durable workflow boundary

`DurableWorkflowStore` is the authority for mutable product and execution state. It uses SQLite with foreign keys, WAL, `synchronous=FULL`, bounded busy waits, and immediate write transactions.

Core durable records include:

- generic entity and JSON-document repositories;
- materialized runs and immutable `run_events`;
- task attempts and checkpoints;
- run leases;
- idempotency records and completed tool results;
- compensation records and recovery decisions;
- migration-import ledgers and workflow metadata.

A run projection and its `run.snapshot` event are committed together. The event stream is append-only through SQL triggers. The projection can be rebuilt from history and is checked against the latest snapshot during integrity verification.

Reviewed SQL under `migrations/workflow/` generates `workflow_migrations.g.dart`. Applied migration hashes are persisted and compared at startup; source drift fails closed.

## Side-effect boundary

Every governed tool call receives an idempotency key derived from the run, work item, attempt, logical operation, and canonical argument hash. A durable completed result is replayed after restart instead of executing the side effect again.

Workspace mutations use a separate compensation journal:

```text
prepared → filesystem effect → applied → workspace commit
                               ↘ rollback / recovery decision
```

Intent is durable before mutation. Before/after hashes and backups allow deterministic recovery. Ambiguous state produces `transaction_recovery_required`; Kristin does not guess or silently repeat a write.

Commands, process starts, deployment, and MCP calls are classified as non-compensatable when their external effect cannot be proven. An expired record does not grant permission to repeat such an action automatically.

## Run ownership and restart recovery

One coordinator owns a short durable run lease. Persisted state changes renew it. A second process cannot execute the same live run.

On startup, stale active runs are reconciled from durable facts:

- `workspace_committed` plus every work item succeeded → recover as succeeded;
- otherwise → recover as interrupted with an explicit recovery record;
- a live lease → do not take ownership;
- lease loss during execution → fail closed.

Checkpoint and task-attempt records are independent of model context and survive process exit.

## Persistence layout

```text
state/workflow.sqlite3            mutable application and run authority
support/migration-backups/        verified SQLite and legacy JSON backups
checkpoints/<run-id>/             project-file rollback material
research-archive/.../objects/     content-addressed immutable objects
cache/knowledge-index/            disposable derived indexes
logs/events.jsonl                 best-effort compatibility mirror
```

Legacy whole-collection JSON is imported by source hash with byte-exact backup and ledger records, then retained for operator rollback. The JSONL event mirror is not authoritative once SQLite exists.

Project source files remain canonical project truth. Model summaries, memory, retrieved passages, and indexes are evidence only. A persisted record never grants a permission.

## Knowledge and memory

Knowledge, prompt, plan, permission, evidence, and memory metadata use the SQLite repository abstraction. Large research bodies and immutable snapshots remain content-addressed objects. The local semantic index remains derived cache and can be rebuilt.

Research is marked untrusted. Failed/interrupted episodes remain diagnostic-only unless explicitly requested or pinned. Retrieval provenance is recorded as evidence.

## Project execution profile

`ProjectDiagnosticsService` detects bounded Analyze, Test, Build, and Run commands. Foreground commands capture bounded output. Preview processes use `ManagedProcessService` and support Stop, but still execute with the desktop user’s privileges.

V1.3 durability does not equal OS isolation. Sandboxed workers, network broker, secret broker, and cross-restart orphan-process reconciliation are v1.4 concerns.

## Presentation and application services

`ChatStudio` is the default home. Project Manager, Runs, Prompt Studio, Knowledge, Skills, Logs, and advanced settings all use `ProductRuntime` services. Runtime services share the same repositories, policies, diagnostics, and event authority.

## Extension boundary

Built-in skills declare capability needs but cannot create permissions. MCP servers require explicit trust records and tool allowlists. Until v1.4, agent-controlled commands, MCP servers, and format adapters are not protected by a production OS sandbox and must be treated as privileged local execution.
