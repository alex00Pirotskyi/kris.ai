#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v dart >/dev/null 2>&1 || {
  echo "ERROR: Dart is required and must be available on PATH." >&2
  exit 2
}
dart run tool/prune_stale_legacy.dart
