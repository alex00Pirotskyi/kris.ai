# Apply and verify P0-002

## Expected base

Apply to the reviewed GitHub head ending in `08e7d37`. Before applying, verify that these current files have the expected SHA-256 values:

```text
611793523f57c5013752caecbd2982ab6615b40bb68551fbbf351e73c3cf84b4  tool/interoperability_v19.py
a55cb44b428d89271bfc4de5c7b80a0ec45d955be7db5df0cf7231835aa5e82b  tool/system_test.py
b55407b06901c64c2681c3dd95cc2624e0a0fc6fd1ae33a00be16645f6214387  tool/validate_release.py
449d960b476f62551644366969aed19e2e01ff580636848be2f99d7f52981c10  tool/verify.sh
d6d5feda03d1b98afa0a4cb73f95fe08639e110d5e285343d05e3ee5ac3e9041  docs/roadmap/STATUS.md
```

## Close P0-001 before changing product behavior

From the unmodified reviewed head, run:

```bash
python3 tool/capture_baseline.py \
  --project . \
  --manifest-mode verify \
  --run-safe-gates \
  --strict
```

Confirm that the generated execution receipt records `sourceManifestIntegrity.status: passed`. Commit the P0-001 closure evidence before applying this security patch. This preserves the baseline as a record of the pre-containment repository.

## Apply P0-002

```bash
git switch -c security/p0-002-disable-v1-trust
git apply --check KRISTIN_P0-002.patch
git apply KRISTIN_P0-002.patch
```

The bundle also contains `repository_overlay/`; it is a review aid and fallback for copying the complete post-patch versions of changed/new files.

## Verify the security milestone

```bash
python3 tool/v1_trust_disablement_test.py \
  --json-output release/V1_TRUST_DISABLEMENT_RESULTS.json

python3 -m py_compile \
  tool/interoperability_v19.py \
  tool/v1_trust_disablement_test.py \
  tool/system_test.py \
  tool/validate_release.py

bash -n tool/verify.sh
python3 tool/system_test.py --project .
python3 tool/validate_release.py --skip-sdk --skip-tests
```

Expected security-gate result:

```text
caseCount=8
passedCount=8
failedCount=0
trustStatus.enabled=false
trustStatus.errorCode=v1_trust_disabled
```

## Commit

```bash
git add \
  SOURCE_MANIFEST.sha256 \
  docs/roadmap/STATUS.md \
  tasks/active/P0-002.md \
  tool/interoperability_v19.py \
  tool/v1_trust_disablement_test.py \
  tool/system_test.py \
  tool/validate_release.py \
  tool/verify.sh \
  release/evidence/P0-002

git commit -m "Disable insecure v1 signed-manifest trust"
```
