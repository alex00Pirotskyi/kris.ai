# Kristin Test --Release Report

- Version: `1.0.9+109`
- Project: `C:\dev\flutter\kris_studio_ai_2`
- Profile: `Flutter`
- Generated: `2026-07-20T05:44:38.824399+00:00`

| Status | Check | Detail | Command |
|---|---|---|---|
| SKIP | Dart grammar parse | Optional tree-sitter Dart parser is unavailable; Flutter analysis remains the authoritative compiler gate. | `` |
| PASS | Python source compilation | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe -m compileall -q tool scripts` |
| PASS | Governed source validation | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe scripts/validate_architecture.py --skip-tests` |
| PASS | Bounded secret scan | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe tool/secret_scan.py` |
| PASS | Offline system contract fixtures | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe tool/system_test.py --project .` |
| PASS | Release source validation | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe tool/validate_release.py --skip-tests --skip-sdk` |
| PASS | Dart formatting | Command completed successfully. | `dart format --output=none --set-exit-if-changed .` |
| PASS | Flutter dependency resolution | Command completed successfully. | `flutter pub get` |
| PASS | Flutter analysis | Command completed successfully. | `flutter analyze --no-pub` |
| PASS | Flutter tests | Command completed successfully. | `flutter test --no-pub` |
| PASS | V1 Prompt-to-Task system fixtures | Command completed successfully. | `flutter test --no-pub test/product/v1_product_preview_test.dart test/product/budget_diagnostics_test.dart` |
| PASS | Deterministic release packaging | Two clean packages were byte-identical (242 members, SHA-256 49ab545d9df495934bed0c1be02e5ccee370790e50fc3c6d3317cd913ec49548). | `` |

## Result

11 passed, 1 warning/skipped, 0 failed.
