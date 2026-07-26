# Kristin repository governance

**Milestone:** P0-006 — Protect repository governance
**Roadmap line:** 3.1.2-p0-006-governance-integration
**Applies to:** `alex00Pirotskyi/kris.ai`
**Protected target:** the GitHub default branch, currently `main`

## Objective

No production or trust-sensitive change reaches the default branch through an unreviewed direct push. A merge must come from a pull request, pass the three mandatory desktop CI lanes, carry a durable solo-maintainer self-review attestation, resolve review conversations, preserve linear history, and leave force-push/deletion protections active.

This document is the human-readable policy. `config/repository_governance.json` is the machine-readable desired state, and `tool/github_governance.py` applies or verifies that state through the GitHub REST API.

## Dependency gate

P0-006 depends on P0-003. Do not activate the remote ruleset until one same-commit GitHub Actions run has passed:

- `validate-ubuntu` through the native Linux release build;
- `validate-windows` through the native Windows release build;
- `validate-macos` through the native macOS release build.

The evidence lives in `release/evidence/P0-003/ci_matrix.json`. A local pass, a partial matrix, a different commit, or a skipped native build does not satisfy the dependency.

P0-004 can pin the exact passing toolchains afterward. P0-005 may be integrated in parallel because it depends only on P0-001 and P0-002.

## Required GitHub rules

The active repository ruleset must:

1. target the default branch;
2. require a pull request;
3. require the documented solo-maintainer review attestation in the pull request;
4. require all three mandatory status checks with no bypass actor;
5. keep review conversations resolved before merge;
6. require review conversations to be resolved;
7. require the three P0-003 lane checks and require the branch to be current;
8. allow only squash and rebase merges;
9. require linear history;
10. block deletion and non-fast-forward updates;
11. define no silent bypass actor.

`requireCodeOwnerReview` is initially false because a personal repository with one maintainer can otherwise deadlock every pull request authored by its only code owner. CODEOWNERS still requests the owner automatically. Enable code-owner review after a second trusted maintainer is present and listed.

## Solo-maintainer review prerequisite

This repository has one maintainer. Requiring another approval would permanently deadlock every pull request and would be a false representation of the project. `tool/github_governance.py --apply` therefore requires `--confirm-solo-maintainer`, a committed self-review attestation, and the three mandatory green CI checks. No bypass actors are configured.

## Security-critical paths

CODEOWNERS covers the entire repository and calls out these boundaries explicitly:

- `.github/` — CI and governance;
- `tool/` — execution, release, and security tooling;
- `schemas/` — typed authority and interoperability contracts;
- `migrations/` — durable state transitions;
- `lib/product/` — desktop runtime;
- `release/` — evidence and release claims;
- `docs/roadmap/` — execution authority;
- `SECURITY.md`, `RELEASE.json`, and `SOURCE_MANIFEST.sha256`.

A future organization migration should replace the personal CODEOWNER with at least two teams, such as platform and security/release owners.

## Pull-request evidence

Every pull request must identify:

- one roadmap task or a bounded emergency fix;
- task dependencies and current evidence;
- Windows, macOS, and Linux impact;
- authority, privacy, credential, network, browser, and external-effect changes;
- exact tests and evidence paths/hashes;
- generated or migrated files;
- solo-maintainer self-review attestation;
- release and rollback impact.

AI-generated implementation is not accepted merely because it was generated. The sole maintainer must inspect the exact diff and evidence in a separate documented self-review step, while mandatory tri-OS CI remains non-bypassable.

## Merge policy

- Direct pushes to `main` are prohibited once the ruleset is active.
- Force pushes and deletion are prohibited.
- Squash or rebase merge is allowed; merge commits are disabled.
- Branches are deleted after merge.
- All review threads must be resolved.
- A new reviewable push dismisses prior approval.
- An administrator emergency change must still use a PR unless a separately documented incident process temporarily changes the ruleset. The change and restoration must be evidenced.

## Labels

The governance tool creates or updates:

- `security-review:required`
- `security-review:passed`
- `security-review:blocked`
- `release:blocker`
- `risk:critical`
- `risk:high`
- `roadmap:p0`
- `ai-generated-change`

Labels help routing and reporting; they do not replace required reviews or CI.

## Activation

Source preparation:

```bash
python tool/repository_governance_test.py
python tool/github_governance.py --plan --project .
```

After P0-003 is closed and the solo-maintainer attestation is committed:

```bash
export GITHUB_TOKEN='<fine-grained token with Administration: write and Issues: write>'
python tool/github_governance.py \
  --apply \
  --project . \
  --repository alex00Pirotskyi/kris.ai \
  --confirm-solo-maintainer
```

The token is read only from the environment. It is never written to the evidence receipt or printed.

Verification:

```bash
python tool/github_governance.py \
  --verify \
  --project . \
  --repository alex00Pirotskyi/kris.ai
```

## Completion evidence

P0-006 becomes `DONE` only when all of the following exist:

- local governance contract test: passed;
- `release/evidence/P0-003/ci_matrix.json`: same-commit three-OS pass;
- GitHub ruleset receipt: active and verified;
- all required labels: present;
- a test pull request demonstrates that a missing approval or failed required check blocks merge;
- a second test demonstrates that an approved, green, up-to-date PR can merge;
- the sole maintainer signs the durable self-review evidence manifest.

Until then, P0-006 remains `REVIEW`, even if the files are committed.
