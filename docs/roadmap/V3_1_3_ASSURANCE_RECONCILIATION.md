# Roadmap V3.1.3 assurance reconciliation

## Decision

P0-007 is the next dependency-safe milestone after the P0-001 through P0-006 integration package. It depends only on P0-001 and may therefore be applied while P0-003, P0-004, P0-005, and P0-006 remain in review.

## Corrected assurance order

```text
source tree and marker checks
  -> architecture_lint / source_contract

legacy check containing both source markers and a command
  -> mixed, excluded from pure behavioral totals

standalone executable harness
  -> behavioral

native OS, installer, update, rollback, or containment lane
  -> platform

signed promotion transaction and independently verified artifact
  -> release
```

## Compatibility

P0-007 is cumulative-aware:

- it preserves the active P0-002 trust-disablement gate;
- it does not require P0-003 to be complete;
- it recognizes P0-003's non-mutating verification ladder when present;
- it preserves P0-005 policy checks when present;
- it does not modify P0-004 toolchain pins or P0-006 governance settings;
- it may be applied to the P0-002-only branch or after the cumulative P0-006 package.

## Roadmap impact

No task dependencies change. P8-001 remains the later milestone that completes the full unit/component/integration/platform/adversarial/benchmark/release hierarchy. P0-007 establishes the non-overclaiming report model that P8-001 will expand.
