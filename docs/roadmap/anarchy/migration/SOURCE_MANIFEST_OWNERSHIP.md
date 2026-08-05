# P24-001 source-manifest ownership resolution

**Classification:** `MACHINE_OBSERVED_OWNERSHIP_DECISION`

The canonical repository-wide source-manifest writer is:

```text
tool/p1a_refresh_source_manifest.py
```

Canonical write command:

```text
python tool/p1a_refresh_source_manifest.py .
```

The script enumerates Git tracked and non-ignored untracked source paths, excludes `SOURCE_MANIFEST.sha256` and paths classified as disposable generated state by `tool/source_tree_policy.py`, sorts paths, hashes file bytes with SHA-256, and writes LF-terminated output.

`tool/p1a_source_inventory_test.py`, `tool/p2_refresh_source_manifest.py`, and `tool/p2_source_inventory_test.py` have narrower P1A/P2 inventory responsibilities. They do not replace the repository-wide owner.

P24-001 does not introduce a second manifest generator. `tool/anarchy_control_plane.py` independently computes the expected bytes in read-only validation to detect drift; only the canonical owner writes the root manifest. The dedicated CI workflow runs the owner only in an isolated clone and compares the result with the checked-in manifest.
