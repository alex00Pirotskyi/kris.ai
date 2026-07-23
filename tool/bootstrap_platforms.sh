#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v flutter >/dev/null 2>&1 || { echo "Flutter is required and must be available on PATH." >&2; exit 2; }

case "$(uname -s)" in
  Linux*) platform=linux; flutter config --enable-linux-desktop >/dev/null ;;
  Darwin*) platform=macos; flutter config --enable-macos-desktop >/dev/null ;;
  MINGW*|MSYS*|CYGWIN*) platform=windows; flutter config --enable-windows-desktop >/dev/null ;;
  *) echo "Unsupported host. Generate desktop runners on Windows, macOS, or Linux." >&2; exit 2 ;;
esac

flutter --version
if [[ ! -f "$platform/CMakeLists.txt" ]]; then
  flutter create --project-name kristin_local_agent --org local.kristin --platforms="$platform" .
fi
flutter pub get
