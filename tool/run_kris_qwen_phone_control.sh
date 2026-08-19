#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
PYTHON_BIN="${KRIS_QWEN_CONTROL_PYTHON:-$(command -v python3)}"
PORT="${KRIS_QWEN_CONTROL_PORT:-8090}"

if [[ -z "${PYTHON_BIN}" ]]; then
  echo "python3 is required" >&2
  exit 2
fi

if [[ ! -d "${REPO_DIR}/.git" ]]; then
  echo "Not a Git checkout: ${REPO_DIR}" >&2
  exit 2
fi

BRANCH="${KRIS_QWEN_REPO_BRANCH:-$(git -C "${REPO_DIR}" branch --show-current)}"
if [[ -z "${BRANCH}" ]]; then
  echo "The server checkout is detached. Check out the branch you want Fetch latest to follow." >&2
  exit 2
fi

if [[ ! -f "${REPO_DIR}/tool/kris_qwen_control.py" || ! -f "${REPO_DIR}/tool/kris_qwen_worker.py" ]]; then
  echo "Qwen controller/worker files are missing from ${REPO_DIR}" >&2
  exit 2
fi

if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet kris-qwen-control.service 2>/dev/null; then
  echo "kris-qwen-control.service is already active and may own port ${PORT}." >&2
  echo "Stop it first with: sudo systemctl stop kris-qwen-control" >&2
  exit 2
fi

export KRIS_QWEN_REPO_DIR="${REPO_DIR}"
export KRIS_QWEN_REPO_BRANCH="${BRANCH}"
export KRIS_QWEN_CONTROL_PORT="${PORT}"
export KRIS_QWEN_CONTROL_ALLOW_REMOTE_HTTP=1

echo "Starting KRIS Qwen phone control from:"
echo "  repo:   ${REPO_DIR}"
echo "  branch: ${BRANCH}"
echo "  port:   ${PORT}"
echo
echo "The controller will print a phone URL and a one-session control token."
echo "Use only on a trusted LAN/VPN (for example Tailscale); do not publish this HTTP port to the Internet."
echo

exec "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_control.py" --phone --port "${PORT}"
