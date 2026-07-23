# Authenticated loopback API

Kristin's governed API is intended for local automation. It binds to loopback, accepts bounded JSON requests, returns JSON errors with correlation identifiers, and exposes a resumable server-sent event stream.

## Authentication and project scope

Send `Authorization: Bearer <token>`. Tokens are shown once, hashed at rest, scoped, expiring, revocable, and optionally bound to one project. Do not place tokens in URLs, repositories, browser local storage, prompts, or logs.

A project-bound token cannot inspect, plan, compile, or execute against another project. Prompt and plan generation can propose tools, but only the governed registry, permission service, and active project boundary can authorize execution.

## Governed request lifecycle

1. Register or select a project.
2. List exact model identities and select one.
3. Generate or choose an immutable prompt version.
4. Generate and review a task-plan revision.
5. Compile the complete plan or selected tasks plus transitive prerequisites.
6. Review the resulting task contract, execution plan, and requested scopes.
7. Grant only the required scopes for that prepared command.
8. Execute with the preparation identity/idempotency key.
9. Observe runs, work items, evidence, citations, events, and audit records.
10. Pause, resume, cancel, stop managed processes, or retry through governed controls.

## v1.1 Project Manager routes

The Project Manager uses one shared detected execution profile for the desktop, API, and CLI:

```text
GET  /v1/projects/{projectId}/manager
POST /v1/projects/{projectId}/analyze
POST /v1/projects/{projectId}/test
POST /v1/projects/{projectId}/build
POST /v1/projects/{projectId}/run
POST /v1/projects/{projectId}/stop
```

The manager response includes the project, detected Analyze/Test/Build/Run commands, diagnostic checks, current managed process, and recent agent runs. Operational routes require `projects:execute`. Run starts one tracked managed process; Stop terminates that tracked process with the runtime's bounded process controls.

## Prompt Studio 2 compiler routes

V1.5 adds a canonical, side-effect-free compilation and evaluation boundary. These routes do not execute tools or grant permissions:

```text
GET  /v1/prompt-studio/v2/contracts
POST /v1/prompt-studio/v2/compile
POST /v1/prompt-studio/v2/evaluate
```

`GET /v1/prompt-studio/v2/contracts` requires `schema:read` and returns the generated contract digest, compiler version, product-specification schema, task-plan schema, evaluation-dataset schema, compilation-report schema, and capability catalog.

`POST /v1/prompt-studio/v2/compile` requires `plans:generate` and accepts complete canonical `specification` and `plan` maps plus an optional project ID and policy:

```json
{
  "projectId": "optional-project-scope",
  "specification": {"schemaVersion": "2.0.0"},
  "plan": {"schemaVersion": "2.0.0"},
  "policy": {
    "sandboxAvailable": false,
    "allowLegacyUnsandboxedDryRun": false
  }
}
```

The abbreviated objects above are illustrative only. The response contains one `plan_compilation_report.v1` document under `report`, including blocking issues, deterministic task states, topological order, execution batches, quality, input/output hashes, and a simulation with `dryRun: true` and `sideEffectsPerformed: false`.

A compilation report is not permission or execution authority. Process-, network-, MCP-, deployment-, and other sandbox-dependent tasks are blocked when `sandboxAvailable` is false. The legacy unsandboxed dry-run override must be explicit and appears as a warning and required approval.

`POST /v1/prompt-studio/v2/evaluate` requires `prompts:read` and accepts complete `baseline`, `candidate`, and `dataset` maps. It returns deterministic weighted prompt-impact results. Static evaluation checks declared variables, terms, forbidden terms, criterion language, and mode cues; it does not call a model or claim end-to-end artifact quality.

The older v1 prompt/task-plan routes remain available for the current UI. V2 documents are compiled independently before any future conversion into governed runtime commands.

## v1 Prompt Studio routes

The generated OpenAPI document is the source of exact request and response schemas. The v1 surface includes:

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

### Generate a prompt draft

`POST /v1/prompts/generate` accepts a plain-language goal, exact model identity, generation action, and optional current draft. Supported actions are Generate, Improve, Simplify, and Add detail.

The response is an editable `PromptStudioDraft`. It is not automatically saved, approved, or executed. The service validates the model's structured JSON and provides bounded repair prompts for malformed output.

### Save an immutable prompt version

`POST /v1/prompts/versions` stores a reviewed draft as a `PromptVersionRecord` containing its prompt ID, version number, source goal, generation action, exact model identity, creator, content hash, and timestamp. Existing versions are never overwritten.

`GET /v1/prompts/{promptId}/versions` returns the version history in version order.

### Generate a task plan

`POST /v1/task-plans/generate` accepts one saved prompt version, project ID, exact model identity, planning depth, and a leaf-task limit from 1 through 100.

The response is a `TaskPlanRecord` with phases, optional parent relationships, dependencies, acceptance criteria, verification steps, expected artifacts, proposed tools, complexity, effort points, uncertainty, risk, confidence, model/tool-call estimates, retry limits, and enable/manual flags.

Model-proposed tool names are intersected with the governed registry. Unknown tools cannot become executable capabilities.

### Inspect and revise plans

`GET /v1/task-plans` supports project and prompt filtering. `GET /v1/task-plans/{planId}` retrieves one revision.

`PUT /v1/task-plans/{planId}` never overwrites the referenced plan. It validates the edited tasks and creates a new immutable revision with:

```text
new plan ID
revision = prior revision + 1
previousPlanId = prior plan ID
new content hash and timestamps
```

Validation rejects duplicate IDs, missing or cyclic dependencies, missing or cyclic parent hierarchies, enabled tasks with disabled prerequisites, unresolved manual tasks at compile time, and plans beyond the configured maximum.

### Compile a governed command

`POST /v1/task-plans/{planId}/compile` converts an approved prompt version and plan revision into the existing `TaskContract`, `ExecutionPlan`, permission request, and idempotent `PreparedCommand`.

The caller may select task IDs. Kristin expands the selection to include all transitive dependencies, preserves plan order, and refuses empty or unresolved manual selections. Compilation does not itself grant permissions or execute the plan.

## Retry and diagnostic routes

```text
POST /v1/runs/{runId}/retry
POST /v1/support-bundles
```

A failed run cannot be executed again with spent counters. `POST /v1/runs/{runId}/retry` creates a fresh linked run in `awaitingApproval` state, records `sourceRunId`, resets attempts and counters, and calculates a bounded budget from the compiled plan. The new run still requires ordinary permission approval and execution.

`POST /v1/support-bundles` accepts optional `projectId`, `runId`, and `includeAllLogs`. With `includeAllLogs=true`, Kristin retains bounded all-log coverage, run records, evidence metadata, events, audit records, and managed-process output in a redacted ZIP. Source-like payload fields are replaced by hashes. Review the output before sharing.

Run events include `work_item.turn_budget_assigned`, model-request lifecycle events, retry decisions, stagnant-loop detection, and `run.retry_created`.

## Path compatibility and errors

Tool paths should normally be `.` or project-relative. For compatibility with local models, an absolute path or local `file:` URI is accepted only when it resolves inside the canonical active project. Kristin normalizes it to a relative path and audits the normalization. Outside paths, traversal, URI schemes, NUL bytes, and symlink escapes remain blocked.

Correctable path and argument failures can be returned to the model for up to three bounded repair attempts. The API and event stream expose `tool.repair_requested` so clients can explain the retry instead of showing an unexplained terminal failure.

## Knowledge and memory routes

```text
GET  /v1/projects/{projectId}/knowledge/search
GET  /v1/projects/{projectId}/knowledge/stats
POST /v1/projects/{projectId}/knowledge/reindex
POST /v1/projects/{projectId}/knowledge/export
GET  /v1/projects/{projectId}/research-archive
GET  /v1/projects/{projectId}/memory
```

Knowledge search returns response-local citation markers such as `[K1]`, source/provenance identifiers, hashes, snippets, trust labels, capture times, and ranking diagnostics. Failed, interrupted, and cancelled episodes remain diagnostic data and are excluded from normal automatic context unless explicitly requested or pinned.

## Other endpoint groups

- Health and generated OpenAPI metadata
- Projects and active-project selection
- Exact model/provider readiness
- Command preparation and execution
- Permission approval
- Runs, work-item controls, evidence, and audit verification
- Project knowledge and research archive management
- Named secret references without secret values
- API token issuance and revocation
- Diagnostics and support-bundle generation
- Event stream with replay cursor

Browser origins are accepted only when they exactly match configured origins. The server does not support remote binding.
