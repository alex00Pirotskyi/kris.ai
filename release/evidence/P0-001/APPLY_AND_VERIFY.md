# Apply and verify P0-001

The patch targets commit:

```text
f230fff336d2c7921a987e624fac96ca7d0030bc
```

## Apply

```bash
git checkout main
git status --short
git rev-parse HEAD
# The result must be the commit above, or the patch must be reviewed/rebased.
git apply --check KRISTIN_P0-001.patch
git apply KRISTIN_P0-001.patch
```

## Run the milestone tests

```bash
python3 -m unittest -v tool/capture_baseline_test.py
python3 tool/capture_baseline.py \
  --project . \
  --manifest-mode verify \
  --run-safe-gates \
  --strict
```

## Acceptance review

Confirm all of the following:

- `release/evidence/baseline/baseline.json` has the expected stable fingerprint.
- `sourceManifestIntegrity.status` is `passed` in `execution.json`.
- Every unavailable or unrun SDK gate has an explicit reason.
- Existing safe source gates either pass or have a recorded blocking failure.
- `git diff --check` passes.
- `python3 tool/secret_scan.py` passes.
- A second capture produces byte-identical `baseline.json` and `BASELINE.md`.
- An independent reviewer updates `docs/roadmap/STATUS.md` from REVIEW to DONE only after checking the evidence.

## Do not do during this milestone

- Do not fix formatting in the same patch; that is `P0-003`.
- Do not modify the v1 trust path in the same patch; that is `P0-002`.
- Do not claim compiled-release readiness from snapshot mode.
