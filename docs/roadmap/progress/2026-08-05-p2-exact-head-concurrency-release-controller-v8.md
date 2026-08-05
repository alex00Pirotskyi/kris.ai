# P2 exact-head concurrency release controller v8

**Recorded:** 2026-08-05
**Worker:** A
**Roadmap authority:** `docs/roadmap/MASTER.md`
**Controller parent:** `45573334cf803c2d2ebdb4105389bd3aa3dfadac`
**Obsolete run:** `30991734270` / `227f1cbfe1c044c4eb4310e872d3aff5b5721615`
**Current run:** `30992084248` / `2cb15db0898fb0337b821bbce17bbf60092d3c66`

The strict P2 workflow serializes runs on the PR branch. After the repository owner added a zero-file, tree-identical handoff commit so protected checks would run under owner identity, the exact-current-head P2 source workflow remained pending behind the superseded parent attempt. Linux and macOS source lanes on the parent had passed, while its Windows lane continued occupying the concurrency slot. The task mandate forbids reusing another commit's evidence, so this disposable controller cancels only that exact superseded run after verifying its run ID, SHA, branch, workflow path, event, and PR number. It separately verifies the queued run is exact head `2cb15db…`, waits for the obsolete run to terminate and the current run to leave `pending`, and uploads a durable receipt. No PR source, main, ruleset, mandatory check, Worker C branch, P3, or P4 scope is modified, waived, or marked passed by this action.
