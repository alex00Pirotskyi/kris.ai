# P24-001 compatibility and rollback

## Compatibility contract

1. `python tool/roadmap_control.py validate --project . --strict` remains authoritative for the current P0/P1 bootstrap scope.
2. `python tool/anarchy_control_plane.py --check --project .` is additive, network-free, and read-only.
3. P24-001 does not extend or rewrite `docs/roadmap/roadmap.yaml`.
4. The scoped P24 schema does not replace Worker B Test Center or certification contracts.
5. Existing generated views retain their owners; P24 adds one bounded generated navigation index only.
6. P2 source-only and P4-001 source-foundation classifications are preserved.
7. `SOURCE_MANIFEST.sha256` is written only by `python tool/p1a_refresh_source_manifest.py .`.
8. No product, storage, API, native, wire, support, release, or GA behavior changes.

## Rollback procedure

1. Close the stacked migration PR without merging, or revert its focused commits if a later authorized adoption merged them.
2. Remove `.github/workflows/p24-adoption-review.yml`, the scoped validator/schema/fixtures, and the generated P24 navigation index when no adopted consumer references them.
3. Do not modify `MASTER.md`, `roadmap.yaml`, `STATUS.md`, `HANDOFF.md`, or `GENERATED_STATE.md`; P24-001 never promoted them.
4. Retain the ADR, baseline, directive matrix, claims, review findings, artifact reconciliation, and evidence as historical records; mark later disposition without deletion.
5. Run the existing bootstrap roadmap validator and applicable product gates.
6. Regenerate the root manifest only through `python tool/p1a_refresh_source_manifest.py .`, then verify read-only with the P24 validator or the repository's then-current manifest check.

Rollback never rewrites PR #62/PR #63 history, P2 evidence, accepted task IDs, or product state.
