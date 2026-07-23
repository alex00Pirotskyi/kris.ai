# Kristin Test --System Report

- Version: `1.1.3+113`
- Project: `C:\dev\flutter\kris_studio_ai_2`
- Profile: `Flutter`
- Generated: `2026-07-20T17:05:56.541076+00:00`

| Status | Check | Detail | Command |
|---|---|---|---|
| SKIP | Dart grammar parse | Optional tree-sitter Dart parser is unavailable; Flutter analysis remains the authoritative compiler gate. | `` |
| PASS | Python source compilation | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe -m compileall -q tool scripts` |
| PASS | Governed source validation | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe scripts/validate_architecture.py --skip-tests` |
| PASS | Bounded secret scan | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe tool/secret_scan.py` |
| PASS | Offline system contract fixtures | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe tool/system_test.py --project .` |
| PASS | Dart formatting | Command completed successfully. | `dart format --output=none --set-exit-if-changed .` |
| PASS | Flutter dependency resolution | Command completed successfully. | `flutter pub get` |
| PASS | Flutter analysis | Command completed successfully. | `flutter analyze --no-pub` |
| PASS | Flutter tests | Command completed successfully. | `flutter test --no-pub` |
| PASS | V1 Prompt-to-Task system fixtures | Command completed successfully. | `flutter test --no-pub test/product/v1_product_preview_test.dart test/product/budget_diagnostics_test.dart` |

## Result

9 passed, 1 warning/skipped, 0 failed.
