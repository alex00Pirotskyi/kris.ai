# Kristin P0-001 machine execution

Captured: **2026-07-23T00:00:00Z**

- Manifest mode: `snapshot`
- Evidence capture: **passed**
- Product gate status on this machine: **unavailable**

## Tool availability

| Tool | Status | Version / reason |
|---|---:|---|
| `python3` | passed | 3.13.5 |
| `git` | passed | git version 2.47.3 |
| `dart` | unavailable | dart is not available on PATH |
| `flutter` | unavailable | flutter is not available on PATH |
| `node` | passed | v22.16.0 |

## Source manifest verification

- Status: **unavailable**
- Reason: snapshot mode selected; the manifest was inventoried but checkout bytes were not asserted
- Verified: 0 / 255
- Missing: 0
- Mismatched: 0

## Gates

| Gate | Status | Exit | Reason |
|---|---:|---:|---|
| `offline_system_contracts` | unavailable | — | tool/system_test.py is not present in this checkout |
| `durable_workflow_kernel` | unavailable | — | tool/workflow_kernel_test.py is not present in this checkout |
| `source_release_validation` | unavailable | — | tool/validate_release.py is not present in this checkout |
| `dart_format` | unavailable | — | dart is unavailable; gate was not executed |
| `flutter_dependency_resolution` | unavailable | — | flutter is unavailable; gate was not executed |
| `flutter_static_analysis` | unavailable | — | flutter is unavailable; gate was not executed |
| `flutter_tests` | unavailable | — | flutter is unavailable; gate was not executed |
| `native_release_build` | unavailable | — | flutter is unavailable; gate was not executed |

## Local inspections

- `pubspec`: **unavailable** — pubspec.yaml is not present in this checkout
- `toolRegistry`: **unavailable** — schemas/tool_registry.v2.json is not present in this checkout
- `ciWorkflow`: **unavailable** — .github/workflows/ci.yml is not present in this checkout

> captureStatus describes this evidence capture, not product readiness. A missing or unrun gate is never promoted to passed.
