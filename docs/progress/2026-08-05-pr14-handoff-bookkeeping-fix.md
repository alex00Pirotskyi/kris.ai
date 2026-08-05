# PR #14 protected-main handoff bookkeeping fix — 2026-08-05

## Roadmap authority

This corrective step is governed by `docs/roadmap/MASTER.md`. It repairs recovery bookkeeping only. It does not change product behavior, APIs, message formats or sizes, access profiles, capability authority, policy semantics, roadmap completion claims, public-GA eligibility, or production-release eligibility.

## Exact source state

- Protected main entering the fix: `5ea818fdc7e50ad644e75aac3467a5d929abec46`
- Failed protected execution: workflow run `30976062209`
- Failed execution job: `92210171562`
- Trigger PR: `#48`
- Trigger branch/head: `ci/direct-pr14-repair-trigger` at `61037b13e71d8b0e6b47feaa9922d476c5666347`
- Governed target branch/head: `merge/p1-p2-owner-risk-qa-preview` at `0b91e02f2d7413c40dcfa81176877cd3a0daf87e`
- Authorizing source product run: `30974509667`, attempt `1`

The failed execution did not create a candidate commit and did not move the target branch.

## What passed before failure

Run `30976062209` successfully verified and executed all substantive authorization and validation work before reaching bookkeeping:

1. exact protected-main control checkout;
2. exact open draft PR #48, same-repository provenance, branch, and head;
3. exact completed source product run `30974509667` and its PR association;
4. exactly one successful `validate-ubuntu`, `validate-windows`, and `validate-macos` job;
5. exact clean target and unchanged remote target head;
6. P2 governed source inventory;
7. owner-risk P1A dependency contract;
8. wheel-only, hash-locked Python dependency bootstrap;
9. integration-train gate;
10. complete P1 exit gate, `12/12` passed;
11. P0-003 repair gate, `13/13` passed;
12. P0-008 roadmap gate and strict roadmap validation;
13. P0-010 generated-state gate;
14. Git whitespace validation.

The installed lock remained explicit and verified: `cryptography 50.0.0`, `cffi 2.1.0`, and `pycparser 3.0`. No test was skipped or weakened to reach this point.

## Root cause 1: untracked documentation was omitted from scope enumeration

The helper created the required durable progress record at:

`docs/progress/2026-08-05-pr14-ci-recovery.md`

That path did not exist in the target, so it was an untracked file. The scope check used only:

```text
git diff --name-only
```

Git does not include untracked files in that command. The helper therefore observed only `.github/workflows/ci.yml` and `SOURCE_MANIFEST.sha256`, then correctly failed because the authorized scope requires the documentation path as well.

The source was not over-broad; the enumerator was incomplete.

## Root cause 2: the durable transcript is intentionally ignored

The status branch’s source-tree policy ignores general `*.log` files. The receipt publisher wrote the exact durable pair:

- `repair.log`
- `repair-status.json`

but staged them with ordinary `git add`. Git rejected `repair.log` because it is ignored. This prevented the failure receipt itself from reaching the status branch.

The ignore policy is correct for general logs. The recovery publisher needs an explicit, narrow exception for the exact reviewed receipt pair.

## Exact correction

### Candidate-path enumeration

`tool/pr14_main_push_repair_v2.py` combines:

```text
git diff --name-only
git ls-files --others --exclude-standard
```

It deduplicates and sorts both sets, then still requires exact equality with the existing three-path allowlist. Ignored files remain excluded, and no wildcard path is introduced.

### Receipt staging

The corrected publisher writes the same two receipt files, then uses:

```text
git add -f -- repair.log repair-status.json
```

The force flag applies only to those two literal paths. It does not disable `.gitignore`, stage other ignored state, or broaden source inventory. The publisher then runs cached whitespace validation, commits the exact receipt, pushes to the exact status branch, and verifies the remote SHA.

### Transport

`.github/workflows/pr14-protected-main-repair.yml` now compiles and self-tests both the reviewed base handoff and the bookkeeping-corrected wrapper. Candidate execution remains limited to a push of the reviewed change to protected `main`.

## Tests added

The corrected self-test initializes a temporary Git repository and proves:

1. two tracked modifications plus one untracked documentation file resolve to the exact authorized three-path tuple;
2. a general `*.log` ignore remains active;
3. only `repair.log` and `repair-status.json` are staged by the narrow force-add operation;
4. the reviewed base handoff self-test still passes unchanged.

The repository’s normal protected product and P1A matrices remain blocking for this change.

## Challenges passed

### Preserving fail-closed behavior

The fix does not relax the expected path set from three files to two. It corrects observation so the new durable document participates in the exact allowlist as originally designed.

### Preserving generated-state policy

The general log ignore remains unchanged. Only the explicitly named recovery transcript and JSON receipt can bypass it, and they live on the temporary status branch rather than becoming ordinary product source.

### Avoiding unnecessary revalidation changes

The exact PR, source run, target head, platform-job set, dependency lock, and validation sequence are unchanged. The failed run already demonstrated that these stages pass; the corrected protected execution will repeat them before candidate creation.

### Maintaining branch hygiene

The repository remains at the cleaned six-branch state plus this single purpose-specific review branch. The review branch is expected to be deleted automatically after protected merge. No historical repair branch is recreated.

## Claim boundary

This correction proves only that the protected recovery handoff can accurately enumerate its exact candidate and durably publish its receipt. It does not by itself land P1/P2, complete independent security review, authorize public GA, authorize production release, or unblock P3.

## Next controlled steps

1. Merge this correction only after its self-test, source-manifest, product, P1A, and branch-hygiene checks pass.
2. Verify the new protected-main execution and its status-branch receipt.
3. Verify the candidate is exactly one child of `0b91e02f2d7413c40dcfa81176877cd3a0daf87e` and changes exactly the three authorized paths.
4. Apply the candidate through authenticated GitHub authority only when the receipt records the expected workflow-write restriction.
5. Close PR #48, reconcile the repaired target with current protected `main`, document that significant merge, and require fresh protected Windows, macOS, Ubuntu, P1A, P2, and product checks.
6. Land P1/P2, finalize owner-risk P2 evidence, clean remaining temporary refs, and select the next dependency-satisfied task from `docs/roadmap/MASTER.md`.
