#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v flutter >/dev/null 2>&1 || { echo "ERROR: Flutter is required and must be available on PATH." >&2; exit 2; }
command -v dart >/dev/null 2>&1 || { echo "ERROR: Dart is required and must be available on PATH." >&2; exit 2; }
./tool/prune_stale_legacy.sh
command -v python3 >/dev/null 2>&1 || { echo "ERROR: Python 3 is required for generated protocol validation." >&2; exit 2; }
python3 tool/protocol_contract_test.py
python3 tool/v1_trust_disablement_test.py
python3 tool/generate_v170_contracts.py --check
python3 tool/generate_v180_contracts.py --check
python3 tool/generate_v190_contracts.py --check
python3 tool/p0_003_repair_test.py
python3 tool/v1_trust_disablement_test.py
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool/prune_stale_legacy.dart
flutter analyze --no-pub --fatal-warnings --fatal-infos
flutter test --no-pub --concurrency=1 --reporter expanded
if command -v python3 >/dev/null 2>&1; then
  python3 tool/validate_release.py --skip-tests
else
  echo "WARNING: Python 3 unavailable; supplemental source gate skipped." >&2
fi
