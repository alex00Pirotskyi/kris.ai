#!/usr/bin/env bash
set -euo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || exit 1
systemctl disable --now kristin-p1-authority.service 2>/dev/null || true
rm -f /etc/systemd/system/kristin-p1-authority.service
systemctl daemon-reload
rm -rf /opt/kristin/p1a /run/kristin-p1a
# State, audit, credentials and provider key are retained unless explicit purge is approved.
[[ "${1:-}" == "--purge-test-state" ]] && rm -rf /var/lib/kristin-p1a /var/log/kristin-p1a /etc/kristin-p1a
