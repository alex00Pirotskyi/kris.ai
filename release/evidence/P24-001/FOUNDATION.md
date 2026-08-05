# P24-001 deterministic control-plane foundation

**Classification:** `SOURCE_FOUNDATION` / `ADOPTION_REVIEW`

This evidence packet records the bounded Worker J implementation only. It does not promote `docs/roadmap/roadmap.yaml`, adopt PR #63, complete P2 behavior, certify product support, merge the stacked PR, or claim release/GA readiness.

## Canonical commands

```text
python -m unittest -v tool/anarchy_control_plane_test.py
python tool/anarchy_control_plane.py --write --project .
python tool/anarchy_control_plane.py --check --project .
python tool/anarchy_control_plane.py --resume-worker J --project .
python tool/p1a_refresh_source_manifest.py .
```

`--check` is read-only. `--write` is bounded to the declared generated P24 navigation index. `SOURCE_MANIFEST.sha256` remains generated only by `tool/p1a_refresh_source_manifest.py`.

Exact-head CI reports and independent Worker B/Worker I review artifacts are separate evidence and must bind to the final pushed commit/tree.
