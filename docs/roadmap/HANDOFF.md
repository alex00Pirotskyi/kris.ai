# Kristin Roadmap Handoff

**Roadmap authority:** `DERIVED`
**Roadmap version:** `3.1.6-p0-010-generated-state-hygiene`

## Startup sequence for a new AI session

1. Read `docs/roadmap/MASTER.md`.
2. Run `python3 tool/roadmap_control.py validate --project . --strict`.
3. Run `python3 tool/roadmap_control.py next --project . --json`.
4. Read the selected task packet, relevant ADRs, current risks, metrics, and evidence.
5. Execute one task only and stop after writing evidence and updating the manifest.

## Current review work

- None.

## Next ready tasks

- `P1-003` — Define capability grant v2 (`tasks/active/P1-003.md`)
- `P1-005` — Specify Signed Manifest v2 (`tasks/active/P1-005.md`)

## Non-negotiable handoff rules

- Never infer task completion from chat history.
- Never mark `DONE` without the task's declared evidence and an independent review where required.
- Never treat `STATUS.md` as independently editable authority; it must match `roadmap.yaml`.
- Never begin P1 implementation while P0-008 remains `REVIEW`.
- P24, not P0-008, owns the future all-task split, claim traceability, and bounded context-pack system.
