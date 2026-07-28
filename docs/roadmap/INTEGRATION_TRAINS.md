# Twelve governed integration trains

The canonical task graph and every task acceptance criterion remain unchanged. What changes is merge cadence: many dependency-ordered tasks may be completed in one guarded branch, one review, one tri-OS branch CI run and one protected-main merge.

1. P1 trust and policy closure.
2. P2 Owner Mode, filesystem and terminal.
3. P3 browser and Web Studio.
4. P4 research, citations and data.
5. P5 UX/UI redesign.
6. P6 agent intelligence and model layer.
7. P7 MCP/A2A and extensions.
8. P8 reliability, security and evaluation.
9. P9 release engineering, installers and updates.
10. P10 tri-platform internal alpha.
11. P10 private beta, audit closeout and RC soak.
12. P10 go/no-go, staged rollout and operations.

Each train still creates task-level evidence, runs internal dependency gates in topological order and fails before merge on any incomplete task. Bundling reduces PR/integration overhead; it does not reduce assurance.
