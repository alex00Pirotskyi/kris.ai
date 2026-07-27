# P0-007 implementation evidence

## Change

P0-007 introduces an assurance taxonomy and report firewall. It reclassifies legacy source-marker checks as source inspection, identifies mixed source/execution checks, recognizes pure executable behavior separately, and prevents source or mixed results from being counted as behavioral proof.

## Product behavior

No Kristin runtime, permission, filesystem, terminal, browser, model, MCP, A2A, updater, or Owner Mode behavior is changed by this milestone.

## New evidence outputs

```text
release/ARCHITECTURE_CONTRACT_RESULTS.json
release/ARCHITECTURE_CONTRACT_RESULTS.md
release/ASSURANCE_REPORT.json
release/ASSURANCE_REPORT.md
release/evidence/P0-007/test-results.json
release/evidence/P0-007/manifest.json
```

## Security invariant

```text
proof_kind in {source_inspection, mixed, unclassified}
  => behavioral_proof must be false
```

Strict reporting fails if the invariant is violated.

## Local delivery validation

The delivery bundle is validated against synthetic P0-002-only and cumulative-aware fixtures. Complete Flutter, native-build, and platform execution remains required in the real checkout.

## Completion state

`REVIEW`. The milestone becomes `DONE` only after complete-checkout execution against the exact committed source and an independent assurance review.
