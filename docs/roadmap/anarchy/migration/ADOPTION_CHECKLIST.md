# P24-001 adoption checklist

**Classification:** `ADOPTION_REVIEW`

## Reconciled foundation

- [x] Exact protected-main and stacked-base SHA/tree recorded.
- [x] Worker J claim created before shared-contract edits.
- [x] PR #62 and PR #63 ownership boundaries preserved.
- [x] Human and machine authorities reconciled without a second mutable ledger.
- [x] Five state domains specified separately.
- [x] Previously inaccurate validator/schema/fixture claims reconciled in `ARTIFACT_RECONCILIATION.json`.
- [x] Deterministic validator committed in the current candidate.
- [x] Validator unit/integration tests committed in the current candidate.
- [x] Worker-J-scoped schema committed without taking Worker B Test Center ownership.
- [x] Positive and negative fixtures committed.
- [x] Claim-collision and shared-contract-collision fixtures committed.
- [x] Yield/takeover fixtures committed.
- [x] Clean-room Worker J resume fixture committed.
- [x] Bounded dedicated tri-OS adoption-review workflow committed.
- [x] Canonical root source-manifest owner resolved as `tool/p1a_refresh_source_manifest.py`.
- [x] Product runtime, P2 behavior, P4 implementation, storage, API, wire, native, and release non-goals preserved.

## Exact-head gates

- [ ] Generated P24 navigation index committed from deterministic `--write` output.
- [ ] Root `SOURCE_MANIFEST.sha256` refreshed only through `tool/p1a_refresh_source_manifest.py`.
- [ ] Final candidate commit/tree recorded in evidence and Worker J memory.
- [ ] Stacked draft PR opened against `agent/anarchy-execution-os`.
- [ ] Exact-head Ubuntu P24 adoption-review CI passes.
- [ ] Exact-head Windows P24 adoption-review CI passes.
- [ ] Exact-head macOS P24 adoption-review CI passes.
- [ ] Full declared-scope `--check` byte/mtime non-mutation passes on pushed state.
- [x] Atomic write interruption regression passes locally.
- [x] Deterministic second-write idempotence regression passes locally.
- [x] Canonical source-manifest second-generation idempotence regression passes locally.
- [ ] Worker B exact-head review artifact has decision `PASS` with no unresolved critical/high finding.
- [ ] Worker I exact-head review artifact has decision `PASS` with no unresolved critical/high finding.
- [ ] Clean-room Worker J resume passes from the final pushed state and is exact-head recorded.
- [ ] Explicit later adoption action promotes authority; Worker J does not perform that promotion in this run.

Unchecked items remain adoption gates. A green source workflow does not convert this migration, P2, or the product into behavioral, platform, release, production, normative, merged, or GA completion.
