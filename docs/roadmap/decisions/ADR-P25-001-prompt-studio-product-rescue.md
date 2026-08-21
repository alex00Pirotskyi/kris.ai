# ADR-P25-001 — Prompt Studio product rescue architecture

**Status:** `ACCEPTED`
**Date:** 2026-08-18
**Owner:** `P25`

## Context

Prompt Studio can spend tens of minutes on a simple local-model request while presenting no useful activity, no live clarification, confusing editing/version controls, and oversized plan generation. The repository also has two live Prompt Studio representations: `PromptStudioDraft` / `TaskPlanRecord` and `ProductSpecificationV2` / `TaskPlanV2`.

## Decision

1. Rescue speed, visibility, interaction, cancellation, and recovery before building an advanced graph.
2. Simple Mode is conversation-first; graph and execution economics live in Expert Mode.
3. Preserve the existing V2 dependency graph and compiler.
4. Converge the visible and V2 representations through deterministic, loss-checked adapters.
5. Prompt and plan generation are separate, user-authorized operations.
6. Plans start as compact skeletons; full worker packets are materialized only for ready tasks.
7. Shared context is stored once in content-addressed capsules.
8. Show streamed artifact text, questions, assumptions, concise decisions, validation, retries, and timing; never expose hidden chain-of-thought.
9. Preserve useful partial output on interruption or failure.
10. Retire the legacy surface only after parity, migration, accessibility, benchmark, and rollback proof.
11. Bind every claim to the canonical Test Center assurance hierarchy.

## Consequences

`P25-001` measures the real path before semantic optimization. Performance budgets are normative. Source and benchmark evidence cannot certify packaged desktop behavior or platform support.
