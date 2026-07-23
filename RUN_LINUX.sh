#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "Starting Kristin v1.0 Prompt-to-Task Product Preview..."
./tool/bootstrap_platforms.sh
./tool/verify.sh
exec flutter run -d linux
