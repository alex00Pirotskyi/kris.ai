# Kristin production roadmap status

Last updated: 2026-07-23
Roadmap version: 3.1.2-p0-006-governance-integration
Current phase: P0 — Stabilize, contain, and establish truth
Current baseline commit: `f230fff336d2c7921a987e624fac96ca7d0030bc`
Current reviewed repository head: `08e7d37`
Current release classification: source preview / source release

## Ready

- `P0-004` remains blocked until P0-003 has passing three-OS evidence.

## In progress

- `P0-003` — Green the current three-OS CI. The local correction slice is applied; Ubuntu, Windows, and macOS evidence remains required.

## Review

- `P0-001` — Capture reproducible baseline. The repository additions and two follow-up compatibility/hash corrections were independently reviewed and are structurally correct. Formal acceptance remains open because the committed `execution.json` still records `manifestMode: snapshot` and source-manifest integrity as `unavailable`; rerun from the complete checkout with `--manifest-mode verify --run-safe-gates --strict`.
- `P0-002` — Disable insecure v1 trust decisions. The fail-closed implementation and eight-case attacker-forgery gate are complete in the delivery patch. Repository application, full-checkout execution, and independent post-application review remain required.

## Blocked

- Full P0 exit gate remains blocked by `P0-003` through `P0-010` and by formal closure of P0-001/P0-002 evidence.

## Done

- None; tasks enter Done only after repository application, required clean-checkout execution, and independent evidence review.

## Current blockers

- Three operating-system CI jobs fail at `dart format` before analyzer, tests, validation, and native builds.
- The committed P0-001 machine report is still a snapshot-only run, not a complete-checkout verification receipt.
- The insecure v1 helper remains active on the reviewed GitHub head until the P0-002 patch is applied.
- Flutter/Dart were unavailable in the environment used to prepare P0-001 and P0-002 delivery evidence.

## Latest evidence

- `release/evidence/baseline/baseline.json`
- `release/evidence/baseline/BASELINE.md`
- `release/evidence/baseline/execution.json`
- `release/evidence/baseline/EXECUTION.md`
- `release/evidence/P0-001/manifest.json`
- `release/evidence/P0-002/manifest.json`
- `release/evidence/P0-002/V1_TRUST_DISABLEMENT_RESULTS.json`
- `release/evidence/P0-002/ATTACK_REPRODUCTION.json`
- `release/evidence/P0-002/P0_001_REVIEW.md`

## Next recommended AI session

Run the P0-003 targeted gates, format source explicitly, push a review branch, inspect every downstream Ubuntu/Windows/macOS failure, and keep P0-003 in REVIEW until all three jobs pass.

