# PR #14 reconciliation staged-whitespace fix — 2026-08-05

## Roadmap authority

This corrective step is governed by `docs/roadmap/MASTER.md`. It normalizes four legacy Markdown trailing-space occurrences that block the governed reconciliation commit. It does not change product behavior, APIs, runtime message formats or sizes, access profiles, capability authority, policy semantics, roadmap completion claims, public-GA eligibility, or production-release eligibility.

## Exact source and failure state

- Protected reconciliation controller with full-history fix: `ab20ea0212a766fe36bcce297c3701c89b82e278`
- Protected reconciliation execution run: `30979605237`, attempt `1`
- Execution job: `92221001053`
- Reconciliation receipt artifact: `8919605747`
- Artifact digest: `sha256:b2bde0e61c068dadf88296b585642a9d2dc5ea0e9d73b75368204c462bafc73f`
- Governed target branch: `merge/p1-p2-owner-risk-qa-preview`
- Unchanged target head: `40b3b1002f37bc9c301bfb5faf9c0b32f5f9a18a`
- Protected-main parent attempted: `ab20ea0212a766fe36bcce297c3701c89b82e278`
- Observed exact conflict: `SOURCE_MANIFEST.sha256`
- Applied reviewed resolution: `source_manifest`

The failed execution produced no candidate commit and did not move the governed target.

## What passed before failure

The full-history correction succeeded. The protected execution then passed:

1. exact protected-main and target checkout verification;
2. immutable main-ancestry proof from `950865fe363bf9556a5760faa06e1a4bff5cb177`;
3. exact remote target-head verification;
4. exact manifest-only conflict observation;
5. the reviewed `source_manifest` resolution;
6. governed source-manifest regeneration with `1087` entries;
7. P2 exact source inventory;
8. wheel-only, hash-locked Python dependency installation and verification;
9. integration-train gate;
10. complete P1 exit gate, `12/12` passed;
11. P0-003 repair gate, `13/13` passed;
12. P0-008 roadmap tests and strict roadmap validation;
13. P0-010 generated-state gate;
14. portable benchmark reproducibility;
15. unstaged Git whitespace validation.

The failure occurred only after the full resolved tree was staged for the final two-parent commit.

## Root cause

Two protected-main progress records used Markdown's trailing-two-space hard-break syntax on their first two metadata lines:

- `docs/progress/2026-08-05-pr14-explicit-comment-trigger.md`;
- `docs/progress/2026-08-05-pr14-run-attempt-pinning.md`.

The exact four lines were:

```text
**Recorded:** 2026-08-05··
**Human roadmap authority:** `docs/roadmap/MASTER.md`··
```

where `·` represents a trailing space.

Those files merged automatically from protected `main` into the target index. The earlier `git diff --check` inspected unstaged changes and therefore did not report already-staged merge content. The final blocking command:

```text
git diff --cached --check
```

correctly rejected all four occurrences.

This was not a P1/P2 product, source-manifest, roadmap, native-build, or reconciliation-conflict failure.

## Exact correction

`tool/normalize_pr14_progress_whitespace.py`:

1. targets only the two exact durable progress paths;
2. requires exactly one `Recorded` hard break and one roadmap-authority hard break in each file;
3. removes only those four trailing-space occurrences;
4. preserves all other text byte-for-byte;
5. fails if either file or expected line has drifted;
6. emits a machine-readable normalization receipt;
7. includes deterministic positive and negative self-tests.

The reconciliation workflow's same-repository source-manifest job runs that normalizer before regenerating `SOURCE_MANIFEST.sha256`. Its allowlist requires exactly:

1. `SOURCE_MANIFEST.sha256`;
2. `docs/progress/2026-08-05-pr14-explicit-comment-trigger.md`;
3. `docs/progress/2026-08-05-pr14-run-attempt-pinning.md`.

It then commits those exact three follow-up changes to this review branch. No wildcard whitespace rewrite is performed.

## Validation retained

Before this correction can merge, the repository still requires:

- whitespace-normalizer compile and self-test;
- reconciliation controller compile and self-test;
- repeated read-only discovery proving the exact manifest-only conflict;
- governed source-manifest regeneration;
- branch-hygiene validation;
- complete Windows, macOS, and Ubuntu product gates;
- complete P1A source and native builds.

After protected merge, reconciliation still must repeat every exact target, ancestry, conflict, manifest, P0, P1, P2, benchmark, workflow-contract, parent, and receipt check.

## Challenges passed

### Preserving historical documentation meaning

The removed spaces existed only to force Markdown line breaks. Each metadata field already occupies its own physical line, so removing the hard-break syntax does not merge, delete, or reinterpret the information.

### Avoiding a broad formatter

A repository-wide trailing-whitespace rewrite was rejected because it could introduce unrelated changes. The normalizer recognizes four exact occurrences in two exact files and fails on drift.

### Distinguishing staged from unstaged checks

The receipt demonstrates why the unstaged check passed while the cached check failed. The final cached whitespace gate remains unchanged and blocking.

### Preserving reconciliation evidence

The observed manifest conflict, stage identities, reviewed resolution, and passed validation sequence remain unchanged. The target branch remains at its receipted repaired head.

### Maintaining branch hygiene

This work uses one purpose-specific review branch and does not recreate any of the 32 redundant refs removed by protected branch-hygiene run `30975239926`.

## Claim boundary

This fix removes four legacy whitespace violations only. It does not claim the two-parent reconciliation candidate exists, P1/P2 has landed, P2 evidence closure is complete, independent security review passed, public GA is authorized, production release is authorized, or P3 is unblocked.

## Next controlled steps

1. Pass all protected checks and merge this exact normalization change.
2. Verify the next protected reconciliation receipt and candidate.
3. Verify exact parents, manifest-only conflict, regenerated inventory, product workflow, and changed paths.
4. Move the governed target only to the exact receipted candidate when workflow-file permissions require connected authority.
5. Require fresh protected PR #14 checks and merge P1/P2 only when every required lane is green.
6. Finalize owner-risk P2 evidence, remove completed temporary reconciliation/recovery refs, and select the first dependency-satisfied next task from `docs/roadmap/MASTER.md`.
