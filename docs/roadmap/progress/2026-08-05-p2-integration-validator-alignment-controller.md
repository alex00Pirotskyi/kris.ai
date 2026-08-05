# P2 integration validator alignment controller

**Recorded:** 2026-08-05
**Worker:** A
**Human roadmap authority:** `docs/roadmap/MASTER.md`
**Protected base:** `5794dffa6fd8f1c16d6c004c9f75aca0e7b8b961`
**Exact P1/P2 target:** `cec0a2d431edc9b972934fcc5898a30a7a1942f8`

## What changed

This significant control-plane commit adds one exact-SHA integration helper, one narrowly triggered workflow, and one immutable configuration. The controller is authorized to construct a candidate changing only:

1. `.github/workflows/p2-owner-mode.yml`;
2. `SOURCE_MANIFEST.sha256`;
3. `docs/roadmap/progress/2026-08-05-p2-integration-validator-alignment.md`;
4. `tool/validate_release.py`.

It does not change P2 product code on `main`. It operates on the existing PR #14 landing branch only after the controller itself is reviewed, protected, and merged.

## Why this is roadmap-authorized

`docs/roadmap/MASTER.md` requires P2 to land as a complete vertical slice, with deterministic tri-OS evidence and without weakening CI. The reconciled PR #14 head passed formatting, analysis, Flutter tests, P1 closure, and security contracts on all three hosted operating systems, but two stale integration assumptions blocked the final gates:

- the release allowlist did not include five intentional P2 Dart files and still expected the pre-P2 direct `ChatStudio` root;
- the P2 source workflow formatted generator-owned Dart rather than using the repository’s governed handwritten scope.

Correcting those integration contracts is required to evaluate P2 as implemented. It does not authorize P3.

## Validation performed

Before protected execution, the workflow requires:

- Python compilation and deterministic self-tests;
- exact repository, target SHA, authorized path list, and `MASTER.md` authority assertions;
- governed source-manifest regeneration;
- Git whitespace validation;
- normal protected product, P1A, branch-hygiene, and repository checks on the control PR.

During protected execution, the helper additionally requires exact protected-main ancestry, an unchanged remote target, exact one-time patch anchors, P2 source inventory, application composition, runtime-resource contracts, P0-003, strict roadmap validation, release validation, and an exact four-path commit.

## Challenges encountered

The connector can safely create small reviewed control files, but it cannot reliably retrieve and rewrite the complete large release validator byte-for-byte. Direct partial replacement would risk truncation or unrelated changes. The protected controller performs the replacements inside a complete checkout and fails on any source drift.

The candidate modifies a workflow file. GitHub may correctly block the Actions token from moving the target ref without workflow-write authority. The helper accepts only that known rejection, preserves the exact candidate object, and emits a 90-day machine receipt for a separately authenticated, receipt-bound fast-forward.

## Resolutions

The controller uses exact anchors and exact path authorization rather than broad regex rewriting. It never executes code from a future-phase branch. It runs from protected `main`, checks out the P1/P2 target as data, and validates all resulting source before candidate creation.

## Compatibility impact

No P1/P2 runtime interface, native service contract, command schema, evidence schema, stored data format, or future P3 interface is changed. Parallel workers can rebase without adapting product code. The only shared contract clarified is that `P2KristinShell` is the current application composition point and `ChatStudio` remains its primary chat page.

## Remaining risks

This controller does not close P2 and does not create controlled-runner behavioral evidence. Even after PR #14 becomes mergeable, P2 owner-risk evidence must be generated on the exact protected landing commit and finalized without upgrading public-GA, production, signed-installer, or independent-security claims.

## Merge considerations for parallel branches

Parallel future branches should not copy the obsolete direct-root `ChatStudio` assumption or broad generator-mutating format command. No future-phase files are modified. If a parallel branch also touches the release validator or P2 workflow, rebase after this control path lands and retain the stricter composed-shell and governed-format assertions.

## Next dependency-controlled action

Merge this controller only after its protected checks pass. Verify the emitted candidate receipt, fast-forward PR #14 only to that exact candidate, require fresh commit-specific protected checks, and merge PR #14 only when every applicable gate is green. Then execute and finalize protected P2 behavioral evidence before identifying—but not implementing—the first dependency-satisfied P3 task.
