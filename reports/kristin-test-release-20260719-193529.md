# Kristin Test --Release Report

- Version: `1.0.4+104`
- Project: `C:\dev\flutter\kris_studio_ai_2`
- Profile: `Flutter`
- Generated: `2026-07-19T16:35:27.807721+00:00`

| Status | Check | Detail | Command |
|---|---|---|---|
| SKIP | Dart grammar parse | Optional tree-sitter Dart parser is unavailable; Flutter analysis remains the authoritative compiler gate. | `` |
| PASS | Python source compilation | Command completed successfully. | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe -m compileall -q tool scripts` |
| FAIL | Governed source validation | Command exited with code 1: - release tree hygiene: windows\flutter\ephemeral\flutter_windows.dll; windows\flutter\ephemeral\flutter_windows.dll.pdb | `C:\Users\alex.p\AppData\Local\Programs\Python\Python313\python.exe scripts/validate_architecture.py --skip-tests` |

## Result

1 passed, 1 warning/skipped, 1 failed.
