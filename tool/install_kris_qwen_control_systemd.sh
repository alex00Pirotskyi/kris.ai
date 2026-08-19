#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
PYTHON_BIN="${KRIS_QWEN_CONTROL_PYTHON:-$(command -v python3)}"
SERVICE_FILE="/etc/systemd/system/kris-qwen-control.service"
ENV_FILE="/etc/kris-qwen-control.env"
CURRENT_BRANCH="$(git -C "${REPO_DIR}" branch --show-current)"

if [[ -z "${PYTHON_BIN}" || ! -x "${PYTHON_BIN}" ]]; then
  echo "python3 is required" >&2
  exit 2
fi
if [[ -z "${CURRENT_BRANCH}" ]]; then
  echo "The server checkout is detached. Check out the branch the controller should follow." >&2
  exit 2
fi
if [[ ! -f "${REPO_DIR}/tool/kris_qwen_control.py" || ! -f "${REPO_DIR}/tool/kris_qwen_worker.py" ]]; then
  echo "Missing repo-owned Qwen controller/worker files in ${REPO_DIR}/tool" >&2
  exit 2
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cat >"${ENV_FILE}" <<EOF
KRIS_QWEN_REPO_DIR=${REPO_DIR}
KRIS_QWEN_REPO_BRANCH=${CURRENT_BRANCH}
KRIS_QWEN_ROOT=/root/kris-qwen-worker
KRIS_QWEN_CONTROL_HOST=127.0.0.1
KRIS_QWEN_CONTROL_PORT=8090
KRIS_QWEN_CONTROL_ALLOW_REMOTE_HTTP=0
KRIS_QWEN_STOP_TIMEOUT=1800
# Optional:
# KRIS_QWEN_PYTHON=/path/to/python3
# KRIS_QWEN_WORKER_ARGS=--model-sandbox required
# QWEN_GGUF_MODEL=/models/Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf
EOF
  chmod 600 "${ENV_FILE}"
fi

cat >"${SERVICE_FILE}" <<EOF
[Unit]
Description=KRIS Qwen HTTP control panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${REPO_DIR}
EnvironmentFile=-${ENV_FILE}
Environment=PYTHONUNBUFFERED=1
Environment=HOME=/root
Environment=GH_CONFIG_DIR=/root/.config/gh
Environment=GIT_TERMINAL_PROMPT=0
ExecStart=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_control.py
Restart=always
RestartSec=2
KillMode=process
TimeoutStopSec=30
UMask=0077

[Install]
WantedBy=multi-user.target
EOF

if command -v gh >/dev/null 2>&1 && HOME=/root GH_CONFIG_DIR=/root/.config/gh gh auth status --hostname github.com >/dev/null 2>&1; then
  HOME=/root GH_CONFIG_DIR=/root/.config/gh gh auth setup-git --hostname github.com >/dev/null
fi

systemctl daemon-reload
systemctl enable --now kris-qwen-control.service

echo
echo "KRIS Qwen control installed."
echo "Status: systemctl status kris-qwen-control --no-pager"
echo "Logs:   journalctl -u kris-qwen-control -f"
echo "Local:  http://127.0.0.1:8090"
echo
echo "For phone access on a trusted LAN/VPN set these in ${ENV_FILE}:"
echo "  KRIS_QWEN_CONTROL_HOST=0.0.0.0"
echo "  KRIS_QWEN_CONTROL_ALLOW_REMOTE_HTTP=1"
echo "Then run: systemctl restart kris-qwen-control"
echo
echo "Do not expose the plain-HTTP control port directly to the public Internet."
