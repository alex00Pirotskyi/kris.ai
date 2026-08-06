# Worker A — P2-004 measurement-contract repair

## Classification

- `MISSION-001_DEPENDENCY_SAFE_SOURCE_REPAIR`
- `P2-004_MEASUREMENT_RECEIPT_BRIDGE_REPAIRED`
- `P2-004_REMAINS_BLOCKED_BY_MISSING_TRI_PLATFORM_MEASUREMENTS`
- `NO_TECHNOLOGY_SELECTED`
- `NO_P2_BEHAVIORAL_PROMOTION`
- `NO_P3_AUTHORIZATION`
- `NO_SUPPORT_PROMOTION`

## Exact base

This focused child branch starts from the frozen Worker A reviewed candidate:

- commit: `89a15332019c73675a19cdacd7021fae2199d75e`
- tree: `2ea1f8a718a69dba0120a4f98acb78053d6cebfb`
- parent PR: `#64`
- parent review decision: canonical source integration `PASS`

The parent branch and reviewed SHA are not modified by this repair.

## Proven source defect

`tool/p2_platform_ci.py` forwards the controlled runner environment into
`tool/p2_task_platform_assertions.py`. P2-004 then invokes
`tool/p2_technology_spike.py`, whose governed inputs are the three exact receipt
paths:

- `KRISTIN_P2_TECH_NODE_RECEIPT`
- `KRISTIN_P2_TECH_NATIVE_RECEIPT`
- `KRISTIN_P2_TECH_DART_RECEIPT`

The task runner's sanitized environment omitted all three names. Therefore a
fully provisioned runner could not deliver valid candidate receipts to the
technology-spike validator; P2-004 was structurally forced to remain blocked.

The committed receipt template also contained only one round even though the
validator requires exactly three machine-observed rounds per candidate.

## Repair

1. Allow only the three explicit, non-secret candidate-receipt path variables
   through the task runner's sanitized environment.
2. Expand the canonical candidate receipt template to rounds 1, 2, and 3.
3. Add an end-to-end regression that:
   - proves a missing receipt fails closed;
   - supplies three independently hashed candidate receipts;
   - traverses the real P2-004 task runner;
   - validates exact backlog and process-tree proof structure;
   - verifies deterministic measured selection while retaining the tri-OS
     aggregation requirement.
4. Bind the task runner, technology validator, regression, template, governed
   P2 workflow, and focused workflow into the existing canonical
   `tc.p2.acceptance-contract` Test Center profile.
5. Add a read-only Ubuntu/Windows/macOS source workflow.

## Boundary

This repair makes the measurement path executable when exact receipts are
externally provisioned. It does not create those receipts, select a production
automation-host technology, complete P2-004, complete P2 behavior, or authorize
P3/P11 work. ADR-0012 remains provisional until real exact-SHA tri-platform
measurements and independent review close the decision.
