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

for value in "${REPO_DIR}" "${PYTHON_BIN}"; do
  if [[ "${value}" =~ [[:space:]] ]]; then
    echo "Refusing paths with whitespace in generated systemd unit: ${value}" >&2
    exit 2
  fi
done

if [[ ! -f "${REPO_DIR}/tool/kris_qwen_control.py" ]]; then
  echo "Missing ${REPO_DIR}/tool/kris_qwen_control.py" >&2
  exit 2
fi
if [[ ! -f "${REPO_DIR}/tool/kris_qwen_worker.py" ]]; then
  echo "Missing ${REPO_DIR}/tool/kris_qwen_worker.py" >&2
  exit 2
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cat >"${ENV_FILE}" <<EOF
KRIS_QWEN_REPO_DIR=${REPO_DIR}
KRIS_QWEN_REPO_BRANCH=main
KRIS_QWEN_ROOT=/root/kris-qwen-worker
KRIS_QWEN_CONTROL_HOST=127.0.0.1
KRIS_QWEN_CONTROL_PORT=8090
KRIS_QWEN_STOP_TIMEOUT=1800
# Optional overrides:
# KRIS_QWEN_PYTHON=/path/to/python3
# KRIS_QWEN_WORKER_ARGS=--model-sandbox required
# QWEN_GGUF_MODEL=/models/Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf
EOF
  chmod 600 "${ENV_FILE}"
fi

cat >"${SERVICE_FILE}" <<EOF
[Unit]
Description=KRIS Qwen worker localhost control panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${REPO_DIR}
EnvironmentFile=-${ENV_FILE}
Environment=PYTHONUNBUFFERED=1
ExecStart=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_control.py
Restart=always
RestartSec=2
# The controller owns a worker child that has its own graceful-stop protocol.
# Do not let a controller service restart hard-signal the worker/model process.
KillMode=process
TimeoutStopSec=30
UMask=0077

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now kris-qwen-control.service

echo
echo "KRIS Qwen control installed."
echo "Status:  systemctl status kris-qwen-control --no-pager"
echo "Logs:    journalctl -u kris-qwen-control -f"
echo "Browser: http://127.0.0.1:8090"
echo "Remote:  ssh -L 8090:127.0.0.1:8090 root@YOUR_SERVER"
echo
echo "Important: stop any old manually launched '... serve' process once before using Start."
