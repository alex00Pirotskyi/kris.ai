# P0-003 repair plan

This repair supersedes the first P0-003 starter attempt while retaining its capability-truth design.

## Ordered repair

1. Apply the original P0-003 capability-aware Project Manager and non-mutating verification changes.
2. Repair the Windows import boundary without introducing host execution.
3. Repair the shared Dart source-generation boundary and regenerate all affected outputs.
4. Repair the durable-workflow JSONPath literal.
5. Repair CI step insertion so every added command remains inside `jobs.validate.steps`; reject malformed indentation in the repair gate.
6. Resolve packages before formatting and use `--no-pub` downstream.
7. Run one explicit canonical formatter pass.
8. Rebuild the complete source manifest from current bytes.
9. Execute source, trust, durability, Flutter, release, and native-build gates.
10. Push the exact commit and collect all three CI lane receipts.

## Non-negotiable safety constraints

- Windows/macOS remain honest `sandbox_unavailable` platforms for project-selected code until native backends exist.
- No project command is executed on the host as a compatibility fallback.
- P0-002 cannot be weakened or bypassed.
- A formatting check may not modify source.
- P0-004 cannot apply until the three-lane P0-003 evidence is complete.
