# P0-003 local repair execution

- Status: **failed**
- Platform: `Windows-10-10.0.26200-SP0`
- Changed files before generators/formatting: 23
- Source-manifest entries: 271

> This is local evidence. P0-003 remains REVIEW until the same commit passes Ubuntu, Windows, and macOS CI through native release build.

## Gates

| Command | Status | Exit |
|---|---|---:|
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/v1_trust_disablement_test.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/generate_v170_contracts.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/generate_v180_contracts.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/generate_v190_contracts.py` | passed | 0 |
| `flutter pub get` | passed | 0 |
| `dart format lib test tool/prune_stale_legacy.dart` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe -m py_compile tool/sandbox_worker.py tool/dart_string_literal.py tool/p0_003_repair_test.py tool/capture_ci_environment.py tool/generate_v170_contracts.py tool/generate_v180_contracts.py tool/generate_v190_contracts.py tool/project_manager_v2.py tool/project_manager_v2_test.py tool/kristin_cli.py tool/system_test.py tool/validate_release.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/v1_trust_disablement_test.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/generate_v170_contracts.py --check` | failed | 1 |

## Next gate

Push the exact repair commit, populate `ci_matrix.json` with all three passing job URLs, then activate P0-004.
