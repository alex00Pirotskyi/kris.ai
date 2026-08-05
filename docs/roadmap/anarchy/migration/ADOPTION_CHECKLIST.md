# P24-001 adoption checklist

## Foundation

- [x] Exact protected-main and stacked-base SHA/tree recorded.
- [x] Worker J claim created before shared-contract edits.
- [x] PR #62 and PR #63 ownership boundaries preserved.
- [x] Human and machine authorities reconciled without a second mutable ledger.
- [x] Five state domains specified separately.
- [x] Deterministic validator, schema, positive/negative fixtures, collision fixture, yield fixture, and clean-room resume fixture added.
- [x] Product runtime, P2 behavior, P4 implementation, storage, API, wire, native, and release non-goals preserved.

## Exact-head gates

- [ ] Final candidate commit/tree recorded in all evidence and Worker J memory.
- [ ] `python tool/anarchy_control_plane_test.py` passes on exact head.
- [ ] `python tool/anarchy_control_plane.py --check --project .` passes without mutation.
- [ ] Existing roadmap and generated-state gates pass.
- [ ] Ubuntu, Windows, and macOS `product-gates` pass on exact head.
- [ ] Root `SOURCE_MANIFEST.sha256` is refreshed and checked by its proven owning generator.
- [ ] Worker B exact-SHA review has no unresolved critical/high finding.
- [ ] Worker I exact-SHA review has no unresolved critical/high finding.
- [ ] Adoption authority explicitly promotes the proposal; PR remains draft before that decision.

Unchecked items are adoption gates, not permission to relabel the migration or product as complete.
