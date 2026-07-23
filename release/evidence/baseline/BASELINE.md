# Kristin P0-001 reproducible baseline

Generated from committed inputs at **2026-07-23T00:00:00Z**.

> This is a deterministic observation report, not a claim that the product passes all gates. Machine-specific availability and execution status are recorded in `execution.json`.

## Milestone contract

- ID: `P0-001`
- Scope: Inventory and evidence only; no product behavior changes.
- Acceptance: A clean checkout reproduces the deterministic report and every unavailable machine gate is explicit in execution.json.

## Repository snapshot

- Repository: `https://github.com/alex00Pirotskyi/kris.ai`
- Branch: `main`
- Commit: `f230fff336d2c7921a987e624fac96ca7d0030bc`
- Commit message: Replace repository with new project
- Imported files/additions: 449 files / 111498 additions

## Release snapshot

- Version: `1.9.0+190`
- Classification: `source-release`
- Source gate reported by existing release metadata: `True`
- Compiled desktop release validated: `False`

## Source inventory

- Manifest entries: **255**
- Schemas: **40**
- Tests and executable gate files: **45**
- Tool sources: **54**
- Documentation files: **53**
- Workflow migrations: **6**
- Source manifest SHA-256: `1c7403c04bc06631e8dc2fc26c4d1826aac224636453d873ccc2418455f26eab`
- Normalized source-set SHA-256: `1c7403c04bc06631e8dc2fc26c4d1826aac224636453d873ccc2418455f26eab`

### Top-level source counts

| Path | Count |
|---|---:|
| `.github` | 1 |
| `<root>` | 17 |
| `docs` | 53 |
| `lib` | 38 |
| `migrations` | 6 |
| `release` | 6 |
| `schemas` | 40 |
| `scripts` | 7 |
| `tasks` | 1 |
| `test` | 32 |
| `tool` | 54 |

## Tool registry

- Registry version: `2.0.0`
- Canonical tool contracts: **23**
- Registry source SHA-256: `47f0716f1139655ccc195f5fb4f98969717f6eff905f0381ef0c46a17d3eb587`
- Full per-tool local inspection: `execution.json#localInspection.toolRegistry`

## Current CI observation

- Workflow: `product-gates`
- Matrix: `ubuntu-latest, windows-latest, macos-latest`
- Latest run: `29976661586` — **failure**
- Failing step: `dart format`
- Failing command: `dart format --output=none --set-exit-if-changed lib test`

| Platform | Result | Job |
|---|---:|---:|
| `ubuntu-latest` | failure | `89109769941` |
| `windows-latest` | failure | `89109769934` |
| `macos-latest` | failure | `89109769950` |

## Known blockers

- **high — Three-platform CI stops at formatting**: Ubuntu, Windows, and macOS all exit at the same dart format check, so downstream analyzer, tests, validator, and native-build claims do not have current CI evidence. Next task: `P0-003`.
- **critical — v1 envelope trust path is frozen pending removal**: The roadmap records an envelope-supplied HMAC trust-anchor flaw in tool/interoperability_v19.py. P0-001 inventories it but intentionally does not change product behavior. Next task: `P0-002`.
- **high — Toolchains and CI Actions are not immutable**: The workflow selects Flutter channel stable and major-version Action tags, so repeated runs do not prove identical declared build inputs. Next task: `P0-004`.
- **high — Current artifact is a source release, not a validated desktop release**: Existing release metadata marks compiled_release_validated false and records SDK gates as unavailable. Next task: `P0-003`.
- **medium — Imported root commit limits historical review**: The current source lineage begins with one root replacement commit, which limits external blame, regression, and review provenance. Next task: `P0-006`.

## Reproduction

From a clean checkout of the recorded commit:

```bash
python3 tool/capture_baseline.py --project . --manifest-mode verify --run-safe-gates
```

The deterministic outputs are `baseline.json` and `BASELINE.md`. The execution outputs intentionally record host-specific availability.

Stable fingerprint: `6770c5d5190ea13c28c51e542b1e12113f3de189b0fecbe63b05ea81b2d2cdef`
