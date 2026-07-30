#!/usr/bin/env bash
set -euo pipefail
: "${P1A_SMAPP_MANAGER:?}"; "$P1A_SMAPP_MANAGER" unregister com.kristin.p1authority.plist || true
[[ "${1:-}" == "--purge-test-state" ]] && rm -rf /Library/PrivilegedHelperTools/KristinP1Authority /Library/Application\ Support/Kristin/P1Authority
