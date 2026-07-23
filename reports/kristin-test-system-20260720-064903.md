# Kristin Test --System Report

- Version: `1.0.7+107`
- Project: `C:\dev\flutter\kris_studio_ai_2`
- Profile: `Flutter`
- Generated: `2026-07-20T03:49:00.053754+00:00`

| Status | Check | Detail | Command |
|---|---|---|---|
| SKIP | Dart grammar parse | Optional tree-sitter Dart parser is unavailable; Flutter analysis remains the authoritative compiler gate. | `` |
| PASS | Python source compilation | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe -m compileall -q tool scripts` |
| PASS | Governed source validation | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe scripts/validate_architecture.py --skip-tests` |
| PASS | Bounded secret scan | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe tool/secret_scan.py` |
| PASS | Offline system contract fixtures | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe tool/system_test.py --project .` |
| PASS | Dart formatting | Command completed successfully. | `dart format --output=none --set-exit-if-changed .` |
| FAIL | Flutter dependency resolution | Command exited with code 65: Failed to update packages. | `flutter pub get` |

## Result

5 passed, 1 warning/skipped, 1 failed.
