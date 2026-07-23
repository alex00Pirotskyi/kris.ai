# Kristin Test --Release Report

- Version: `1.1.3+113`
- Project: `C:\dev\flutter\kris_studio_ai_2`
- Profile: `Flutter`
- Generated: `2026-07-20T17:06:32.177307+00:00`

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
| FAIL | Flutter tests | Command exited with code 1: model_load_timeout: Ollama could not finish loading tiny-model after 2 bounded attempts. Keep Ollama running, free enough memory for the model, or increase the cold-load timeout in Settings. | `flutter test --no-pub` |

## Result

8 passed, 1 warning/skipped, 1 failed.
