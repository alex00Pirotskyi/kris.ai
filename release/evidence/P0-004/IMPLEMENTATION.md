# P0-004 immutable toolchain implementation

## Status

REVIEW — implementation applied; two same-source workflow reruns remain required.

## P0-003 dependency

- Commit: `53a7d661cda1f714bbe3ff83c8e06d99cb433a20`
- Workflow: `https://github.com/alex00Pirotskyi/kris.ai/actions/runs/30197992227`
- Ubuntu, Windows, and macOS: passed through native release build.

## Locked inputs

- Python: `3.12.10`
- Flutter: `3.44.8` (`stable`)
- Dart: `3.12.2`
- Ubuntu runner: `ubuntu-24.04`
- Windows runner: `windows-2025`
- macOS runner: `macos-15`
- Declared-input fingerprint: `532f73ad316f6887ce1fdf3f7252ee371ad1d4e98062b1e3e3a9673c1da64818`

## Immutable Actions

| Action | Release | Commit |
|---|---|---|
| `actions/checkout` | `v7.0.1` | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/setup-python` | `v7.0.0` | `5fda3b95a4ea91299a34e894583c3862153e4b97` |
| `actions/upload-artifact` | `v7.0.1` | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| `subosito/flutter-action` | `v2.23.0` | `1a449444c387b1966244ae4d4f8c696479add0b2` |

## Remaining closure work

1. Push the P0-004 commit.
2. Run the complete Ubuntu/Windows/macOS workflow twice for the same source commit.
3. Download or preserve each lane's `toolchain-<OS>.json` receipt.
4. Compare the two receipt sets with `tool/compare_toolchain_runs.py`.
5. Commit `first-run.json`, `second-run.json`, `comparison.json`, and independent review.
6. Mark P0-004 DONE only when every lane has an identical declared-input fingerprint and P0-003 stays green.
