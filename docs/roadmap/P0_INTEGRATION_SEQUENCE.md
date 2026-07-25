# P0-001 through P0-006 integration sequence

This repository uses a two-stage integration to preserve dependency truth.

## Stage A — repair and policy truth

Start from a clean checkout containing P0-001 and P0-002:

```bash
python /path/to/bundle/apply_stage_a.py --project . --apply --run-gates
```

Review, commit, push, and let the exact commit run all three CI lanes. Download the three `ci-environment-*.json` artifacts and record the matrix with `tool/record_p0_003_ci.py`.

## Stage B — immutable inputs and governance

After committing the reviewed P0-003 matrix:

```bash
python /path/to/bundle/apply_stage_b.py \
  --project . \
  --apply \
  --python-version X.Y.Z \
  --flutter-version X.Y.Z \
  --dart-version X.Y.Z
```

The command applies P0-004 and P0-006 source changes in dependency order. It does not silently activate GitHub rules.

## Remote governance activation

Invite a trusted reviewer, push the Stage B branch, and run:

```bash
export GITHUB_TOKEN='<fine-grained token>'
python tool/github_governance.py \
  --apply \
  --project . \
  --repository alex00Pirotskyi/kris.ai \
  --confirm-distinct-reviewer
```

Then create one deliberately blocked test PR and one green/approved test PR. Record their links in the P0-006 evidence manifest.
