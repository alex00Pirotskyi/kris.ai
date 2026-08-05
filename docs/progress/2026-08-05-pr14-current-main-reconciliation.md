# PR #14 reconciliation with protected main — 2026-08-05

## Roadmap authority

`docs/roadmap/MASTER.md` is the human implementation authority. `docs/roadmap/roadmap.yaml` remains the machine dependency ledger.

## Exact parents

- P1/P2 target parent: `40b3b1002f37bc9c301bfb5faf9c0b32f5f9a18a`
- Protected-main parent: `5794dffa6fd8f1c16d6c004c9f75aca0e7b8b961`
- Target branch: `merge/p1-p2-owner-risk-qa-preview`

The resulting candidate must be a two-parent merge commit in that order.

## Why reconciliation was required

After the documented P1/P2 repair was produced and receipted, protected `main` advanced through repository branch hygiene, the protected recovery handoff, and the recovery bookkeeping correction. GitHub therefore reported PR #14 as `mergeable_state: dirty`. Landing without an explicit merge would either discard protected-main controls or overwrite the repaired P1/P2 source.

## Conflict discovery and resolution

The conflict set was discovered read-only on the reconciliation controller PR, including Git index stage identities, before any resolution was authorized.

| Path | Reviewed resolution |
|---|---|
| `SOURCE_MANIFEST.sha256` | `source_manifest` |

`compose_ci` means the current protected-main product workflow is retained, the existing hash-locked P1/P2 bootstrap is inserted exactly once, push validation is restricted to `main`, pull-request validation remains enabled, and the completed PR #48/PR #54 one-shot jobs remain retired. `source_manifest` means the conflicted manifest is not selected from either parent; it is regenerated after the full merged tree and this record exist.

## Significant changes preserved from protected main

- exact SHA-pinned branch-hygiene automation and its durable cleanup record;
- the completed protected PR #14 recovery handoff and bookkeeping correction;
- current roadmap authority and execution documentation policy;
- product-gate push hygiene, preventing duplicate required contexts on feature branches;
- removal of obsolete PR #48 and PR #54 one-shot jobs from the permanent product workflow.

## Significant changes preserved from the P1/P2 target

- complete P1/P2 owner-risk QA-preview source and native authority-service integration;
- the repaired owner-risk P1A source-lane contract;
- the wheel-only, hash-locked Python dependency bootstrap before full P1 closure;
- the durable PR #14 recovery record and governed P2 source inventory.

## Validation before candidate creation

The reconciliation controller requires the exact parents and conflict set, resolves only the reviewed paths, regenerates `SOURCE_MANIFEST.sha256`, then runs:

- P2 source inventory;
- exact hosted-Python lock validation and installation;
- integration-train gate;
- complete P1 exit gate;
- P0-003 repair gate;
- P0-008 roadmap tests and strict roadmap validation;
- P0-010 generated-state gate;
- portable benchmark check;
- Git whitespace checks;
- exact product-workflow assertions.

Fresh protected Windows, macOS, Ubuntu, P1A, P2, and native-release checks remain required on PR #14 after the branch moves to the reconciliation candidate.

## Challenges passed

1. **Dirty PR state:** merge conflicts are treated as an explicit governed change, not bypassed through a force push or direct main merge.
2. **Workflow divergence:** the final product workflow is composed from protected main plus the exact P1/P2 bootstrap instead of blindly selecting either side.
3. **Generated inventory conflict:** the source manifest is regenerated from the resolved tree rather than manually merged.
4. **Duplicate status contexts:** feature-branch pushes no longer produce a second product matrix with the same required names; pull requests still receive the complete matrix and `main` still receives post-merge validation.
5. **Workflow-write restriction:** if the Actions token cannot move a ref containing workflow changes, the exact candidate object and receipt are retained for a separately authenticated fast-forward after verification.
6. **Documentation durability:** the exact parents, conflicts, resolutions, validation, and claim boundary are committed with the candidate.

## Claim boundary

This is still an **owner-risk QA preview**. Reconciliation does not claim independent security review, public-GA eligibility, production-release eligibility, signed-installer readiness, or unrestricted consumer release. It does not by itself complete P2 evidence closure or unblock P3.

## Next controlled steps

1. Verify the reconciliation receipt, candidate parents, conflict set, and product-workflow assertions.
2. Move the target only to the exact receipted candidate.
3. Require fresh protected PR #14 checks against current `main`.
4. Merge P1/P2 only when all required checks are green.
5. Finalize owner-risk P2 evidence and clean temporary reconciliation/recovery refs.
6. Select the first dependency-satisfied next task from `docs/roadmap/MASTER.md`.
