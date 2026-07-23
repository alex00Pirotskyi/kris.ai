# P0-003 local application result

- Status: **failed**
- Project: `<PROJECT>`
- Platform: `Windows-10-10.0.26200-SP0`
- Applied at: `2026-07-23T11:13:25.984468+00:00`
- Changed files: 11

> This is local evidence only. P0-003 remains open until Ubuntu, Windows, and macOS CI all pass every workflow step.

## Changed files

- `.github/workflows/ci.yml`
- `docs/roadmap/MASTER.md`
- `docs/roadmap/STATUS.md`
- `docs/roadmap/V3_1_RECONCILIATION.md`
- `release/evidence/P0-003/IMPLEMENTATION_PLAN.md`
- `tasks/active/P0-003.md`
- `tool/project_manager_v2.py`
- `tool/project_manager_v2_test.py`
- `tool/system_test.py`
- `tool/validate_release.py`
- `tool/verify.sh`

## Gates

| Command | Status | Exit |
|---|---|---:|
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/v1_trust_disablement_test.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe -m py_compile tool/project_manager_v2.py tool/project_manager_v2_test.py tool/kristin_cli.py tool/system_test.py tool/validate_release.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/v1_trust_disablement_test.py` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/project_manager_v2_test.py --json-output release/PROJECT_MANAGER_V2_RESULTS.json` | failed | 1 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/system_test.py --project . --json` | failed | 1 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/workflow_kernel_test.py --project . --json` | passed | 0 |
| `C:\Users\alex.p\AppData\Local\Programs\Python\Python311\python.exe tool/secret_scan.py` | passed | 0 |
| `dart format --output=none --set-exit-if-changed lib test tool/prune_stale_legacy.dart` | failed | 1 |

## Remaining closure requirement

Push a review branch and require a completely green current CI run on Ubuntu, Windows, and macOS. Record run URLs and artifact hashes before moving the task to DONE.
