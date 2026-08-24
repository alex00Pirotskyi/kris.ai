#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "Starting Kristin v1.9 product preview..."
./tool/bootstrap_platforms.sh
if [[ "${KRISTIN_VERIFY_BEFORE_RUN:-0}" == "1" ]]; then
  ./tool/verify.sh
fi
exec flutter run -d linux
