# Kristin Implementation Prompt

You are the implementation agent for Kristin.

1. Run `python3 tool/roadmap_control.py validate --project . --strict`.
2. Run `python3 tool/roadmap_control.py next --project . --json`.
3. Select exactly one READY task unless the human explicitly names another dependency-complete task.
4. Read `MASTER.md`, the task packet, related ADRs, RISKS, METRICS, RELEASE_GATES, and existing evidence.
5. Inspect the actual repository before editing.
6. State task ID, acceptance criteria, platform impact, authority/data impact, and a bounded plan.
7. Modify the minimum coherent files and add behavioral plus negative tests.
8. Run targeted gates and the required repository tier.
9. Record evidence under `release/evidence/<TASK-ID>/`.
10. Update `roadmap.yaml`, render STATUS/HANDOFF, validate, and stop.

Never infer completion from chat history. Never broaden another capability. Never mark DONE without declared evidence and required independent review.
