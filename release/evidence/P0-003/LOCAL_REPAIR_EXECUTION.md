# P0-003 local repair execution

- Status: **passed_local**
- Platform: `Windows-10-10.0.26200-SP0`
- Changed files before generators/formatting: 25
- Source-manifest entries: 270

> This is local evidence. P0-003 remains REVIEW until the same commit passes Ubuntu, Windows, and macOS CI through native release build.

## Gates

| Command | Status | Exit |
|---|---|---:|
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/v1_trust_disablement_test.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/generate_v170_contracts.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/generate_v180_contracts.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/generate_v190_contracts.py` | passed | 0 |
| `flutter pub get` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/dart_format_scope.py --write` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe -m py_compile tool/sandbox_worker.py tool/dart_string_literal.py tool/dart_format_scope.py tool/dart_format_scope_test.py tool/p0_003_repair_test.py tool/capture_ci_environment.py tool/generate_v170_contracts.py tool/generate_v180_contracts.py tool/generate_v190_contracts.py tool/project_manager_v2.py tool/project_manager_v2_test.py tool/kristin_cli.py tool/system_test.py tool/validate_release.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/v1_trust_disablement_test.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/dart_format_scope_test.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/generate_v170_contracts.py --check` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/generate_v180_contracts.py --check` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/generate_v190_contracts.py --check` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/p0_003_repair_test.py --json-output release/evidence/P0-003/repair_results.json` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/project_manager_v2_test.py --json-output release/PROJECT_MANAGER_V2_RESULTS.json` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/system_test.py --project . --json` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/workflow_kernel_test.py --project . --json` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/secret_scan.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/validate_release.py --skip-sdk` | passed | 0 |
| `bash -n tool/verify.sh` | passed | 0 |
| `git diff --check` | passed | 0 |

## Next gate

Push the exact repair commit, populate `ci_matrix.json` with all three passing job URLs, then activate P0-004.
