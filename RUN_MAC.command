#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
echo "Starting Kristin..."
exec python3 dev.py run macos
