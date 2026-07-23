#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./tool/bootstrap_platforms.sh
./tool/verify.sh
case "$(uname -s)" in
  Linux*) flutter build linux --release ;;
  Darwin*) flutter build macos --release ;;
  MINGW*|MSYS*|CYGWIN*) flutter build windows --release ;;
  *) echo "Unsupported host; build a desktop target on its native host." >&2; exit 2 ;;
esac
