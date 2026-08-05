# P24-001 compatibility and rollback

## Compatibility contract

1. `tool/roadmap_control.py validate --project . --strict` remains authoritative for the current bootstrap scope.
2. `tool/anarchy_control_plane.py --check --project .` is additive and network-free.
3. The canonical machine file remains the JSON subset of YAML 1.2.
4. Unknown proposal fields are not written into `roadmap.yaml` in P24-001.
5. Existing generated views retain their owning generator until an adoption commit changes ownership explicitly.
6. P2 `source_only` and P4-001 `SOURCE_FOUNDATION` classifications are preserved.
7. No product or storage format changes are part of rollback or migration.

## Rollback procedure

1. Close the stacked migration PR without merging, or revert its focused commits if already adopted.
2. Restore the pre-adoption `roadmap.yaml`, workflow, and generated views from the protected-main anchor recorded in `BASELINE.json`.
3. Remove the P24 validation invocation and schema only if no adopted consumer references them.
4. Retain the ADR, baseline, directive matrix, claims, review findings, and evidence as historical records; mark them `REVOKED` or `SUPERSEDED` rather than deleting them.
5. Run the existing roadmap validator and full `product-gates` matrix.
6. Verify the source manifest with its owning generator. Never hand-edit hashes.

Rollback does not rewrite PR #62, PR #63 history, P2 evidence, or accepted task IDs.
