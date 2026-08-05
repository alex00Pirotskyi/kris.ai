# PR #14 source-contract repair controller v2

**Recorded:** 2026-08-05  
**Worker:** A  
**Roadmap authority:** `docs/roadmap/MASTER.md`  
**Controller branch:** `ci/pr14-source-contract-repair-20260805`  
**Controller base:** `de8dc3bcde31356b490c32b7d60bb373d9fa68ed`  
**Exact authorized target:** `bdfec2232cc1718e8b160e7e2fe5c4374fd4b42b`

## What changed

This significant control-plane commit adds one disposable, exact-SHA GitHub Actions controller. The runtime available to Worker A cannot clone GitHub directly, while the repository's governed Actions environment can execute the locked Flutter, Python, Node, source-manifest, and repository checks. The controller therefore constructs and validates the smallest PR #14 repair without using direct writes to `main`.

## Why this is roadmap-authorized

`MASTER.md` requires P2 integration to preserve deterministic, non-mutating verification and truthful separation between source evidence and behavioral evidence. Current product and P2 source runs fail only because two assertions still encode the retired fixed-literal stale-source implementation. Repairing those assertions is necessary to reach the protected P2 landing gates; it does not expand P2 scope or begin P3.

## Exact safeguards

The controller:

1. checks that PR #14 is still exactly `bdfec2232cc1718e8b160e7e2fe5c4374fd4b42b` with tree `98855292814eb94e452cceb6205869b60ff07268` before editing;
2. patches only `test/product/source_contract_test.dart` and creates one target progress document;
3. refreshes `SOURCE_MANIFEST.sha256` through the canonical P2 command;
4. runs the affected test, full Flutter suite, generator checks, P1/P2 gates, automation-host tests, roadmap, governance, generated-state, and whitespace validation;
5. compares before/after worktree state to prove verification is non-mutating;
6. commits only the exact three authorized target paths;
7. rechecks the remote target immediately before commit and push;
8. updates the PR branch only by non-force fast-forward;
9. retains per-command exit codes, SHA-256 output hashes, full logs, exact candidate identity, and changed paths as a 90-day Actions artifact.

Any target movement, missing anchor, unexpected path, validation failure, source mutation, or push mismatch fails closed.

## Challenges and resolution

The prior protected alignment controller was intentionally bound to historical head `cec0a2d431edc9b972934fcc5898a30a7a1942f8` and correctly refused to patch later concurrent work. Rather than weakening that guard or resetting PR #14, this controller is bound to the newly verified live head and preserves all legitimate intervening commits.

## Compatibility and parallel merge considerations

No product API, persistence schema, wire format, generated contract, runtime composition, or platform adapter is changed by this control commit. Worker C branch `agent/p4-001-search-provider-foundation` is outside the controller trigger, target, authorized paths, and validation scope. Future branches should rebase only after the protected P2 landing and should not import this disposable controller.

## Remaining risks and claim boundary

This controller can close the source-stage regression and publish a candidate. It cannot itself establish P2 completion. Exact-commit protected checks, protected landing, tri-OS controlled behavioral certification, acceptance and cleanup receipts, evidence aggregation, independent AI review, and truthful roadmap/status/handoff updates remain mandatory. No P3 or P4 implementation is authorized here.

## Next dependency-controlled action

Run the controller, verify its receipt and exact candidate, inspect all commit-specific PR checks, repair any genuine remaining failure, merge only through protected policy, and then execute P2 behavioral certification against the exact protected landing commit.
