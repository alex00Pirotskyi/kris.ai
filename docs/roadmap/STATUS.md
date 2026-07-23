# Kristin production roadmap status

Last updated: 2026-07-23
Roadmap version: 1.0.0
Current phase: P0 — Stabilize, contain, and establish truth
Current stable commit: `f230fff336d2c7921a987e624fac96ca7d0030bc`
Current release classification: source preview / source release

## Ready

- `P0-002` — Disable insecure v1 trust decisions, after this patch is applied and reviewed.
- `P0-003` — Green the current three-OS CI, after this patch is applied and reviewed.

## In progress

- None.

## Review

- `P0-001` — Capture reproducible baseline. Implementation, unit tests, deterministic reports, and patch evidence are complete. Repository application and independent review remain required.

## Blocked

- Full P0 exit gate remains blocked by `P0-002` through `P0-010`.

## Done

- None; tasks enter Done only after repository application and an independent evidence review.

## Current blockers

- Three operating-system CI jobs fail at `dart format` before analyzer, tests, validation, and native builds.
- The insecure v1 trust path is scheduled for hard disablement in `P0-002`.
- Flutter/Dart were unavailable in the execution environment used to prepare the P0-001 patch.
- The full repository checkout was unavailable in that environment; source-byte verification is therefore explicitly `unavailable` in the attached machine report.

## Latest evidence

- `release/evidence/baseline/baseline.json`
- `release/evidence/baseline/BASELINE.md`
- `release/evidence/baseline/execution.json`
- `release/evidence/baseline/EXECUTION.md`
- `release/evidence/baseline/capture_manifest.json`
- `release/evidence/P0-001/manifest.json`

## Next recommended AI session

Apply and independently review `P0-001`, reproduce it from a clean checkout with `--manifest-mode verify --run-safe-gates`, then execute `P0-002`.
