# P25 — Prompt Studio Product Rescue and Token-Efficient Planning Engine

**Status:** `READY`
**Roadmap authority:** `HUMAN_CONSTITUTION_EXTENSION`
**Machine extension:** `docs/roadmap/p25/manifest.v1.json`
**Decision:** `docs/roadmap/decisions/ADR-P25-001-prompt-studio-product-rescue.md`

## Mission

Prompt Studio must become a fast, live, conversational workspace where the user can watch a prompt appear, answer material questions, interrupt or cancel safely, edit naturally, recover partial work, approve a compact plan, and give each worker only the context needed for its next task.

The triggering user evidence is concrete: a simple request using a small local Phi model can take about thirty minutes on an Intel i7 with 32 GB RAM while the interface remains silent, confusing, non-interactive, and error-prone.

## Product failures to remove

1. **Oversized work before value.** A simple request can generate a large structured draft and a large detailed plan before the user sees a useful result.
2. **Silent model lifecycle.** Discovery, loading, first-token wait, generation, validation, repair, and persistence are not visible as one understandable operation.
3. **No real dialogue.** The system cannot pause with a durable “A or B?” question and continue from the answer.
4. **Confusing editing and versions.** Users are exposed to implementation records rather than direct editing, auto-save, history, and restore.
5. **Late and destructive errors.** Useful partial work is not the default recovery surface.
6. **Expensive roadmaps.** Global context and detailed task instructions are repeated too early and across too many workers.

## Non-negotiable outcomes

- UI acknowledgement p95 below 100 ms.
- Durable operation creation p95 below 250 ms.
- First visible activity p95 below 500 ms.
- No invisible activity gap longer than 3 seconds.
- Cancel acknowledgement p95 below 250 ms.
- Provider cancellation p95 below 2 seconds.
- Warm simple-prompt p50 at or below 20 seconds.
- Warm simple-prompt p95 at or below 45 seconds.
- Cold simple-prompt p95 at or below 90 seconds.
- One full generation request normally and no more than one bounded repair.
- Prompt generation never starts task-plan generation without a user action.
- User-visible activity shows streamed artifact text, current stage, assumptions, questions, concise decision summaries, validation, retries, token counts, and timing.
- Hidden chain-of-thought is never requested, stored, or displayed.

## Simple-mode flow

```text
Describe
→ Answer material questions
→ Watch the draft appear
→ Adjust directly
→ Build a compact plan
→ Review
→ Run
```

Expert Mode may expose the graph, critical path, execution batches, scope and artifact inspection, analyzer findings, cost deltas, revision diffs, and worker packets. It is not the default first-use experience.

## Target architecture

```text
PromptStudioWorkspace
        │
PromptStudioSessionController
        │
PromptStudioOperationService
        ├── durable operation state
        ├── ordered events and artifact deltas
        ├── cancellation and interruption
        ├── structured questions and answers
        ├── validation and bounded repair
        └── timing and token telemetry
        │
PromptStudioCanonicalAdapter
        │
Existing V2 contracts and deterministic compiler
        │
Token-Efficient Plan Optimizer
        │
On-demand Task Packet Materializer
        │
Governed runner
```

The existing V2 dependency graph and compiler remain the foundation. P25 must converge the visible `PromptStudioDraft` / `TaskPlanRecord` path with the stricter `ProductSpecificationV2` / `TaskPlanV2` path rather than introducing a third meaning of “plan.”

## Fast-path rules

1. Understand intent and ask only questions that materially change output.
2. Show at most one question at a time; at most three per round.
3. Produce a compact prompt draft before a plan.
4. Generate a compact plan skeleton before detailed task instructions.
5. Default task counts: 1–3 simple, 3–7 normal, 7–15 complex.
6. More than 15 tasks requires explicit user selection or compiler justification.
7. Prefer provider-supported structured output and local normalization.
8. Repair only invalid fields, once; do not blindly regenerate the full response three times.
9. Cache model discovery with explicit invalidation and retain the selected exact model identity.
10. Preserve partial work across cancellation, timeout, validation failure, provider disconnect, and restart.

## Token-efficient runner design

Shared architecture, global constraints, security rules, source summaries, acceptance defaults, and tool contracts are stored once as content-addressed context capsules.

A task references:

```text
objective
dependencies
read hints
write intentions
consumed and produced artifacts
acceptance criteria
verification commands
risk and stop policy
context capsule IDs
token and call budget
```

Deterministic optimization passes hoist repeated constraints, deduplicate criteria, hoist shared prerequisites, merge tiny adjacent work with one write boundary, split context-overflow tasks, cluster by locality, serialize overlapping writes, parallelize independent clusters, and materialize full instructions only for the ready frontier.

## Governed execution order

| Task | Deliverable |
|---|---|
| `P25-001` | End-to-end latency instrumentation and real benchmark harness |
| `P25-002` | Durable operation state, ordered events, streaming, cancellation, and partial recovery |
| `P25-003` | Adaptive intent interview, compact prompt schema, warm-session reuse, and bounded repair |
| `P25-004` | Conversation-first Prompt Studio workspace |
| `P25-005` | Live questions, user interruption, and compact resume |
| `P25-006` | Direct editing, auto-save, history, and recovery |
| `P25-007` | Canonical contract convergence |
| `P25-008` | Compact plan skeleton and lazy task packet materialization |
| `P25-009` | Context capsules and token-efficient roadmap optimizer |
| `P25-010` | Expert graph and execution-economics inspector |
| `P25-011` | Atomic migration and legacy retirement |

Only `P25-001` is initially `READY`. All later tasks are dependency-blocked.

## Test Station

Every P25 worker must use the repository-owned suite:

```bash
python3 tool/p25_prompt_studio_roadmap_test.py --project .
python3 tool/p25_prompt_studio_test_station.py --project . --list
python3 tool/p25_prompt_studio_test_station.py --project . --profile contract --check
```

Future deterministic, owner-model, and packaged-product profiles remain explicitly `BLOCKED_NOT_IMPLEMENTED` or `BLOCKED_ENVIRONMENT` until their product source and environment exist. They are never silently skipped or counted as passing.

## Truth boundary

Source, unit, component, benchmark, native-platform, and release evidence are separate. P25 source landing does not certify packaged behavior, platform support, release support, production readiness, release, or GA.

## Prohibited shortcuts

Never begin with the graph canvas, delete the legacy path before replacement parity, expose hidden chain-of-thought, discard partial output on failure, require manual version saving before continuing, generate 25 detailed tasks for a simple prompt, send every worker the complete roadmap, or relax a performance budget merely because an implementation misses it.
