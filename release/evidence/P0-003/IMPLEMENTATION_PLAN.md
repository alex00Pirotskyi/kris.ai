# P0-003 implementation plan

This packet implements the first P0-003 correction slice and then drives the existing pipeline to reveal any remaining failures.

## Root causes addressed

1. Built-in deterministic packaging was incorrectly blocked by sandbox availability even though it launches no project code.
2. Two offline system tests invoked `run_bounded` through its default sandbox path even though they are fixed, synthetic plumbing probes.
3. The Project Manager behavioral suite treated sandbox execution as mandatory on every OS, contradicting the product's honest platform capability matrix.
4. Verification formatted source in place instead of checking a clean tree.

## Safety decision

No production Project Manager command receives a host fallback. Analyze, Test, Build, and Run remain blocked when the real sandbox is unavailable. Windows/macOS native execution is intentionally deferred to the Owner Mode/native-host phases.

## Completion boundary

The applicator can patch and run local gates. Only real three-OS CI can close the milestone.
