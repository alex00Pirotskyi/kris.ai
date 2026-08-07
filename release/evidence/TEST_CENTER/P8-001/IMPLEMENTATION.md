# P8-001 review-repair implementation evidence

This packet addresses the exact Worker A review of commit `22a8ac34cbf9601100f60c4929198f15f3c60e52` / tree `ef5d5ae584b1d823502bf6f2191ecf4285d36845`.

## P8-A-001

A closed `AssuranceExecutionReport` schema now wraps and validates a real canonical `TestExecutionResult`. The validator binds test, module, roadmap task, commit, tree, hierarchy level, proof kind, result state, and support ceiling. Thirty-two regressions include missing, unknown, mismatched, cross-candidate, source-only promotion, unexecuted promotion, above-ceiling, unknown-test, missing-canonical-field, and additional-field cases.

## P8-A-002

The dedicated workflow now regenerates the root source manifest through the canonical P1A owner and fails closed on a diff. The first repair run uploads the generated manifest so it can be committed without reproducing the repository outside the canonical generator. Exact implementation CI identities are added to `manifest.json` after that run settles.

## P8-A-003

The hierarchy records the exact eleven reviewed Worker A bindings from PR #64 commit `89a15332019c73675a19cdacd7021fae2199d75e` / tree `2ea1f8a718a69dba0120a4f98acb78053d6cebfb` and review comment `5203350863`. They block integration until promoted to active bindings. `tc.p1a.exit-gate` remains source-only `architecture_lint`; a platform claim requires a separate stable ID and actual platform evidence.

## Non-claims

This is source-contract and deterministic fixture evidence only. It does not close controlled P2 behavior, authorize P3, prove native parity, promote support, certify a release, or authorize merge.

The semantic validation implementation is isolated in `tool/test_center_assurance_semantics.py`; the CLI remains read-only in `tool/test_center_assurance_hierarchy.py`.

## First published repair run

Implementation candidate `788af8db5891518a2b405d25e8d5b50cb89e8871` / tree `fe2bd4068d83b652ef988fd11d0de86a0fc9bffd` ran as workflow `31104232582`. Ubuntu and macOS passed the canonical contracts, actual assurance report, regressions, and byte-identical double manifest generation before failing on the intentionally stale committed manifest. Windows found a repository-relative path separator defect before manifest generation. The follow-up uses `Path.as_posix()` and checks out the exact PR head instead of the synthetic merge commit. Artifact `8968803777` has archive SHA-256 `77091700bce0e9e704bbe9a593d4340326f3826e24c8ecbc15e7ab5e7f1fcbf5` and contains two byte-identical 1,125-entry manifests with SHA-256 `1656ae06aba143cf83a85c5a48bc2bae3f01fbfe9ed21c53ac1b7a78a77cc2a7`.
