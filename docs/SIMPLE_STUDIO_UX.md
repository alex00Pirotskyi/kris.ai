# Chat Workspace and Prompt Studio UX

Kristin v1.0 keeps the normal experience chat-first while adding a guided Prompt → Plan → Execute → Verify workflow for larger work.

## Product promise

The default journey is:

> Choose or create a project → describe the outcome → optionally improve the prompt → review the task plan → approve access → run or stop work → inspect the result.

A normal question should still require only the central chat composer. Prompt Studio, the task graph, Knowledge, Skills, and Logs live under **Build & Debug** rather than blocking the first conversation.

## Primary navigation

- **New chat** and conversation history
- **Projects**
- **Build & Debug**
  - Runs
  - Prompt Studio
  - Knowledge
  - Skills
  - Logs
- Settings

Templates are suggestions in chat and reusable Prompt Studio records rather than a mandatory top-level workflow.

## Chat journey

### Ask or describe an outcome

The central composer contains a text field, attachment action, project selector, and Send action. Auto mode routes ordinary greetings and questions to a no-tools conversational work item rather than project inspection.

### Review plans inline

Read/write or execution requests can show an inline plan with plain-language steps, required access, model identity, and Start/Edit/Advanced actions. The full contract, acceptance criteria, scopes, budgets, and DAG remain available through progressive disclosure.

### Follow execution

The conversation shows a simple timeline. **View run** opens the pan-and-zoom graph with node status, retries, evidence, logs, artifacts, files, and controls.

## Goal-first Prompt Studio

Prompt Studio begins with one field:

```text
Build me a modern calculator with standard and scientific functions.
```

The selected model generates a structured draft with title, purpose, system instructions, editable user prompt, variables, assumptions, clarifying questions, acceptance criteria, expected outputs, guardrails, stop conditions, evaluations, and task mode.

Available actions:

- Generate prompt
- Improve
- Simplify
- Add detail
- Save immutable version
- Generate task list

Model output is never silently accepted or executed. The user can edit every field before saving.

## Adaptive task planning

An approved prompt can produce one task or as many as 100 executable tasks. Larger work is organized into phases and optional parent/child groups. Each task shows:

- dependencies and hierarchy;
- complexity, effort, uncertainty, risk, and confidence;
- expected model turns and tool calls;
- tools and permissions;
- acceptance criteria, verification, and artifacts.

The plan editor supports new immutable revisions. Running or previously approved revisions are not overwritten.

## Execution controls

The Prompt Studio plan card supports:

- Review execution plan
- Run all tasks
- Run selected task plus dependencies
- Edit task and save a new revision
- Stop all running generated-plan tasks

The Runs view retains pause, resume, cancel, retry, and inspection controls. A selected task cannot run without transitive prerequisites. Manual tasks must be completed or disabled before compilation.

## Progressive disclosure

- **Simple** — conversation, plan summary, access, progress, result.
- **Technical** — tools, files, commands, prompts, plan revision, sources, durations, retries, and tests.
- **Raw** — redacted events, correlation IDs, evidence hashes, budgets, provider identity, and audit data.

All levels inspect the same governed run. There is no weaker beginner execution path.

## Accessibility and failure UX

- Status uses text and icons, not color alone.
- Important controls have labels and tooltips.
- Long plans are searchable and grouped by phase.
- Model-schema repairs and tool-input repairs appear as understandable retries.
- Failure cards show the failing task, error code, preserved evidence, and direct actions to retry, edit the task, inspect logs, or stop descendants.
- The reported absolute-path issue is shown as recoverable when the path is inside the selected project; outside paths remain explicit security failures.

## Implementation modules

```text
lib/product/chat_studio.dart
  chat-first shell, Prompt Studio composer, plan cards, task editing,
  run/stop controls, Knowledge, Skills, and Logs

lib/product/prompt_planning.dart
  prompt generation, versioning, adaptive planning, validation,
  immutable revisions, and deterministic compilation

lib/product/product_runtime.dart
  application-service boundary for UI and API

lib/product/planning_runtime.dart
  governed execution, retries, evidence, cancellation, and memory
```

## Acceptance gates

- A greeting starts no project inspection.
- A plain-language goal can become an editable prompt draft.
- Saving creates an immutable prompt version.
- Planning supports valid 1-task and 100-task plans.
- Dependencies and parent hierarchies are complete and acyclic.
- Plan edits create immutable revisions.
- Selected execution includes all prerequisites.
- Run and stop controls remain visible at plan and run levels.
- Every mutation and process still passes through project boundaries, permissions, checkpoints, evidence, and audit.
