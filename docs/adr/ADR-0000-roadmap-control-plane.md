# ADR-0000 — Bootstrap Roadmap Control Plane

**Status:** ACCEPTED
**Decision task:** `P0-008`
**Date:** 2026-07-24

## Context

Kristin's roadmap spans hundreds of dependent tasks. Markdown, chat history, task files, GitHub issues, and evidence can drift. P0-008 needs a dependency-free control plane before P24 builds the complete all-task traceability system.

## Decision

- `docs/roadmap/MASTER.md` is the human engineering constitution.
- `docs/roadmap/roadmap.yaml` is the machine authority for P0/P1 task IDs, dependencies, statuses, packets, and evidence.
- The bootstrap manifest uses the JSON subset of YAML 1.2 so validation needs only Python's standard library.
- `STATUS.md` and `HANDOFF.md` are generated views.
- Strict validation rejects duplicate IDs, missing dependencies, cycles, invalid status transitions, missing packets/evidence, stale derived files, and competing human authority.
- P24 may migrate the representation but must preserve IDs, status history, evidence links, and compatibility.

## Consequences

A fresh AI can select READY work without this conversation. Status updates become reviewed repository changes. The bootstrap does not yet provide all-task claim traceability or context packs.
