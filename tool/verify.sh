#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v flutter >/dev/null 2>&1 || { echo "ERROR: Flutter is required and must be available on PATH." >&2; exit 2; }
command -v dart >/dev/null 2>&1 || { echo "ERROR: Dart is required and must be available on PATH." >&2; exit 2; }
./tool/prune_stale_legacy.sh
command -v python3 >/dev/null 2>&1 || { echo "ERROR: Python 3 is required for generated protocol validation." >&2; exit 2; }
python3 tool/protocol_contract_test.py
python3 tool/benchmark_runner_test.py
python3 tool/p0_009_benchmark_test.py --project .
python3 tool/benchmark_runner.py check --project .
python3 tool/source_tree_policy_test.py
python3 tool/generated_state_guard_test.py
python3 tool/p0_010_generated_state_test.py --project .
python3 tool/generated_state_guard.py audit --project . --strict
python3 tool/assurance_model_test.py
python3 tool/p0_007_assurance_test.py --project .
python3 tool/roadmap_control_test.py
python3 tool/p0_008_roadmap_test.py --project .
python3 tool/roadmap_control.py validate --project . --strict
python3 tool/architecture_contract_test.py --project .
python3 tool/v1_trust_disablement_test.py
python3 tool/generate_v170_contracts.py --check
python3 tool/generate_v180_contracts.py --check
python3 tool/generate_v190_contracts.py --check
python3 tool/p0_003_repair_test.py
python3 tool/toolchain_lock_test.py
python3 tool/policy_support_test.py
python3 tool/repository_governance_test.py --json-output release/evidence/P0-006/local_governance_results.json
python3 -m unittest -v tool/github_governance_client_test.py
python3 tool/v1_trust_disablement_test.py
flutter pub get
python3 tool/dart_format_scope.py --check
flutter analyze --no-pub --fatal-warnings --fatal-infos
flutter test --no-pub --concurrency=1 --reporter expanded
if command -v python3 >/dev/null 2>&1; then
  python3 tool/validate_release.py --skip-tests
else
  echo "WARNING: Python 3 unavailable; supplemental source gate skipped." >&2
fi

python3 tool/assurance_dashboard.py --project . --strict

# P1-001 runtime-boundary architecture gate
"${PYTHON:-python}" tool/p1_001_runtime_boundary_test.py --project .

# P1-002 Access Profile v2 gates
"${PYTHON:-python}" tool/access_profile_v2_test.py
"${PYTHON:-python}" tool/p1_002_access_profile_test.py --project .
