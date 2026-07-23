# Kristin P0-001 machine execution

Captured: **2026-07-23T11:13:19Z**

- Manifest mode: `verify`
- Evidence capture: **passed**
- Product gate status on this machine: **unavailable**

## Tool availability

| Tool | Status | Version / reason |
|---|---:|---|
| `python3` | unavailable | python3 is not available on PATH |
| `git` | passed | git version 2.39.0.windows.2 |
| `dart` | passed | Dart SDK version: 3.12.0 (stable) (Fri May 8 01:51:14 2026 -0700) on "windows_x64" |
| `flutter` | passed | Flutter 3.44.0 â€¢ channel stable â€¢ https://github.com/flutter/flutter.git
Framework â€¢ revision 559ffa3f75 (10 weeks ago) â€¢ 2026-05-15 14:13:13 -0700
Engine â€¢ hash fcf463a2242790d1fdcd9d044f533080f5022e18 (revision 4c525dac5e) (2 months ago) â€¢ 2026-05-15 19:00:04.000Z
Tools â€¢ Dart 3.12.0 â€¢ DevTools 2.57.0 |
| `node` | unavailable | node is not available on PATH |

## Source manifest verification

- Status: **passed**
- Reason: all manifest entries matched
- Verified: 255 / 255
- Missing: 0
- Mismatched: 0

## Gates

| Gate | Status | Exit | Reason |
|---|---:|---:|---|
| `offline_system_contracts` | not_run | — | --run-safe-gates was not selected |
| `durable_workflow_kernel` | not_run | — | --run-safe-gates was not selected |
| `source_release_validation` | not_run | — | --run-safe-gates was not selected |
| `dart_format` | not_run | — | P0-001 records SDK availability but does not mutate or build the product |
| `flutter_dependency_resolution` | not_run | — | P0-001 records SDK availability but does not mutate or build the product |
| `flutter_static_analysis` | not_run | — | P0-001 records SDK availability but does not mutate or build the product |
| `flutter_tests` | not_run | — | P0-001 records SDK availability but does not mutate or build the product |
| `native_release_build` | not_run | — | P0-001 records SDK availability but does not mutate or build the product |

## Local inspections

- `pubspec`: **passed** — pubspec version matched the observation snapshot
- `toolRegistry`: **passed** — file hash and JSON structure verified
- `ciWorkflow`: **passed** — workflow source hash matched

> captureStatus describes this evidence capture, not product readiness. A missing or unrun gate is never promoted to passed.
