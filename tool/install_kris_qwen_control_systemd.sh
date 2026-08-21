#!/usr/bin/env bash
set -euo pipefail

PHONE_MODE=0
for arg in "$@"; do
  case "${arg}" in
    --phone)
      PHONE_MODE=1
      ;;
    --help|-h)
      cat <<'EOF'
Usage: install_kris_qwen_control_systemd.sh [--phone]

Installs the durable systemd supervisor for Qwen engineering worker 5.4.1 / controller 2.2.2.

  --phone   bind the controller to 0.0.0.0 with explicit remote-HTTP opt-in.
            Use only on a trusted LAN/VPN; never expose port 8090 publicly.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      exit 2
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
SERVICE_FILE="/etc/systemd/system/kris-qwen-control.service"
ENV_FILE="/etc/kris-qwen-control.env"
SERVICE_USER="${KRIS_QWEN_SERVICE_USER:-${SUDO_USER:-root}}"

if ! id "${SERVICE_USER}" >/dev/null 2>&1; then
  echo "Unknown KRIS Qwen service user: ${SERVICE_USER}" >&2
  exit 2
fi
SERVICE_GROUP="$(id -gn "${SERVICE_USER}")"
SERVICE_HOME="$(getent passwd "${SERVICE_USER}" | cut -d: -f6)"
if [[ -z "${SERVICE_HOME}" || ! -d "${SERVICE_HOME}" ]]; then
  echo "Cannot resolve home directory for ${SERVICE_USER}" >&2
  exit 2
fi

as_service_user() {
  if [[ "${SERVICE_USER}" == "root" ]]; then
    HOME="${SERVICE_HOME}" GH_CONFIG_DIR="${SERVICE_HOME}/.config/gh" "$@"
  else
    runuser -u "${SERVICE_USER}" -- env \
      HOME="${SERVICE_HOME}" \
      GH_CONFIG_DIR="${SERVICE_HOME}/.config/gh" \
      "$@"
  fi
}

if [[ -n "${KRIS_QWEN_CONTROL_PYTHON:-}" ]]; then
  PYTHON_BIN="${KRIS_QWEN_CONTROL_PYTHON}"
else
  PYTHON_BIN="$(as_service_user sh -c 'command -v python3')"
fi
CURRENT_BRANCH="$(git -C "${REPO_DIR}" branch --show-current)"

if [[ -z "${PYTHON_BIN}" || ! -x "${PYTHON_BIN}" ]]; then
  echo "python3 is required for service user ${SERVICE_USER}" >&2
  exit 2
fi
if [[ -z "${CURRENT_BRANCH}" ]]; then
  echo "The server checkout is detached. Check out the branch the controller should follow." >&2
  exit 2
fi

required=(
  "${REPO_DIR}/config/qwen_engineering_skills.v1.json"
  "${REPO_DIR}/tool/kris_qwen_control.py"
  "${REPO_DIR}/tool/kris_qwen_control.py.compat.py"
  "${REPO_DIR}/tool/kris_qwen_worker.py"
  "${REPO_DIR}/tool/kris_qwen_worker.py.compat.py"
  "${REPO_DIR}/tool/kris_qwen_worker_v53.py"
  "${REPO_DIR}/tool/kris_qwen_worker_v53_base.py"
  "${REPO_DIR}/tool/kris_qwen_worker_v531.py"
  "${REPO_DIR}/tool/kris_qwen_worker_v54.py"
  "${REPO_DIR}/tool/kris_qwen_worker_v541.py"
  "${REPO_DIR}/tool/kris_qwen_v53_policy.py"
  "${REPO_DIR}/tool/kris_qwen_v53_recovery.py"
  "${REPO_DIR}/tool/kris_qwen_v53_reconcile.py"
  "${REPO_DIR}/tool/kris_qwen_engineering_env.py"
  "${REPO_DIR}/tool/kris_qwen_v531_test.py"
  "${REPO_DIR}/tool/kris_qwen_engineering_env_test.py"
  "${REPO_DIR}/tool/kris_qwen_v541_test.py"
  "${REPO_DIR}/tool/kris_qwen_control_compat_test.py"
  "${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py"
  "${REPO_DIR}/tool/rotate_kris_qwen_control_token.sh"
)
for path in "${required[@]}"; do
  if [[ ! -f "${path}" ]]; then
    echo "Missing repo-owned Qwen engineering 5.4 file: ${path}" >&2
    exit 2
  fi
done

if ! as_service_user test -w "${REPO_DIR}" || ! as_service_user test -w "${REPO_DIR}/.git"; then
  echo "Service user ${SERVICE_USER} cannot write the Qwen repository checkout: ${REPO_DIR}" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI 'gh' is required for durable Qwen auto-update." >&2
  exit 2
fi
if ! as_service_user gh auth status --hostname github.com >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated for service user ${SERVICE_USER}." >&2
  echo "Run 'gh auth login' as that user before installing durable Qwen supervision." >&2
  exit 2
fi
as_service_user gh auth setup-git --hostname github.com >/dev/null
as_service_user git config --global --add safe.directory "${REPO_DIR}"

as_service_user "${PYTHON_BIN}" -m py_compile \
  "${REPO_DIR}/run_my_server.py" \
  "${REPO_DIR}/tool/kris_qwen_worker.py.compat.py" \
  "${REPO_DIR}/tool/kris_qwen_worker_v53.py" \
  "${REPO_DIR}/tool/kris_qwen_worker_v53_base.py" \
  "${REPO_DIR}/tool/kris_qwen_worker_v531.py" \
  "${REPO_DIR}/tool/kris_qwen_worker_v54.py" \
  "${REPO_DIR}/tool/kris_qwen_worker_v541.py" \
  "${REPO_DIR}/tool/kris_qwen_v53_policy.py" \
  "${REPO_DIR}/tool/kris_qwen_v53_recovery.py" \
  "${REPO_DIR}/tool/kris_qwen_v53_reconcile.py" \
  "${REPO_DIR}/tool/kris_qwen_engineering_env.py" \
  "${REPO_DIR}/tool/kris_qwen_control.py.compat.py" \
  "${REPO_DIR}/tool/kris_qwen_v531_test.py" \
  "${REPO_DIR}/tool/kris_qwen_engineering_env_test.py" \
  "${REPO_DIR}/tool/kris_qwen_v541_test.py" \
  "${REPO_DIR}/tool/kris_qwen_control_compat_test.py" \
  "${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py"

WORKER_VERSION="$(as_service_user "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_worker_v53.py" version)"
if ! grep -Fq '"scriptVersion": "5.4.1"' <<<"${WORKER_VERSION}"; then
  echo "Qwen worker 5.4.1 preflight failed: ${WORKER_VERSION}" >&2
  exit 2
fi
if ! as_service_user "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_v531_test.py" >/dev/null; then
  echo "Qwen worker 5.3.1 baseline regression preflight failed." >&2
  exit 2
fi
if ! as_service_user "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_engineering_env_test.py" >/dev/null; then
  echo "Qwen worker 5.4 engineering-environment regression preflight failed." >&2
  exit 2
fi
if ! as_service_user "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_v541_test.py" >/dev/null; then
  echo "Qwen worker 5.4.1 deployment regression preflight failed." >&2
  exit 2
fi
if ! as_service_user "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_control_compat_test.py" >/dev/null; then
  echo "Qwen controller durable-pause regression preflight failed." >&2
  exit 2
fi
if ! as_service_user "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py" >/dev/null; then
  echo "Qwen controller token-redaction regression preflight failed." >&2
  exit 2
fi
CONTROLLER_VERSION="$(as_service_user "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_control.py.compat.py" --version)"
if [[ "${CONTROLLER_VERSION}" != "2.2.2" ]]; then
  echo "Qwen controller 2.2.2 preflight failed: ${CONTROLLER_VERSION}" >&2
  exit 2
fi

export REPO_DIR CURRENT_BRANCH SERVICE_HOME PYTHON_BIN ENV_FILE PHONE_MODE
"${PYTHON_BIN}" - <<'PY'
from __future__ import annotations

import os
import pathlib
import re

path = pathlib.Path(os.environ["ENV_FILE"])
existing = path.read_text(encoding="utf-8") if path.is_file() else ""
lines = existing.splitlines()

mandatory = {
    "KRIS_QWEN_REPO_DIR": os.environ["REPO_DIR"],
    "KRIS_QWEN_REPO_BRANCH": os.environ["CURRENT_BRANCH"],
    "KRIS_QWEN_PYTHON": os.environ["PYTHON_BIN"],
    # Keep the stable v53 filename for controller/PID compatibility. It now
    # validates the engineering catalog and forwards to deterministic 5.4.1.
    "KRIS_QWEN_WORKER_SCRIPT": str(pathlib.Path(os.environ["REPO_DIR"]) / "tool/kris_qwen_worker_v53.py"),
    "KRIS_QWEN_AUTO_UPDATE": "1",
    "KRIS_QWEN_AUTO_UPDATE_SECONDS": "30",
    "KRIS_QWEN_CONTROLLER_SELF_RESTART": "1",
}
if os.environ.get("PHONE_MODE") == "1":
    mandatory["KRIS_QWEN_CONTROL_HOST"] = "0.0.0.0"
    mandatory["KRIS_QWEN_CONTROL_ALLOW_REMOTE_HTTP"] = "1"

defaults = {
    "KRIS_QWEN_ROOT": str(pathlib.Path(os.environ["SERVICE_HOME"]) / "kris-qwen-worker"),
    "KRIS_QWEN_CONTROL_HOST": "127.0.0.1",
    "KRIS_QWEN_CONTROL_PORT": "8090",
    "KRIS_QWEN_CONTROL_ALLOW_REMOTE_HTTP": "0",
    "KRIS_QWEN_STOP_TIMEOUT": "1800",
}

assign = re.compile(r"^([A-Z0-9_]+)=")
present: dict[str, int] = {}
for index, line in enumerate(lines):
    match = assign.match(line)
    if match:
        present[match.group(1)] = index

def quote(value: str) -> str:
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'

for key, value in mandatory.items():
    rendered = f"{key}={quote(value)}"
    if key in present:
        lines[present[key]] = rendered
    else:
        present[key] = len(lines)
        lines.append(rendered)

for key, value in defaults.items():
    if key not in present:
        present[key] = len(lines)
        lines.append(f"{key}={quote(value)}")

path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8", newline="\n")
PY
chown "${SERVICE_USER}:${SERVICE_GROUP}" "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

cat >"${SERVICE_FILE}" <<EOF
[Unit]
Description=KRIS Qwen always-on Product engineering controller
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
WorkingDirectory=${REPO_DIR}
EnvironmentFile=-${ENV_FILE}
Environment=PYTHONUNBUFFERED=1
Environment=HOME=${SERVICE_HOME}
Environment=GH_CONFIG_DIR=${SERVICE_HOME}/.config/gh
Environment=GIT_TERMINAL_PROMPT=0
ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_worker_v53.py version
ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_v531_test.py
ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_engineering_env_test.py
ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_v541_test.py
ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_control_compat_test.py
ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py
ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_control.py.compat.py --version
ExecStart=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_control.py.compat.py
Restart=always
RestartSec=2
KillMode=process
TimeoutStopSec=30
OOMPolicy=continue
UMask=0077

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "${SERVICE_FILE}"

systemctl daemon-reload
systemctl enable --now kris-qwen-control.service
if ! systemctl is-active --quiet kris-qwen-control.service; then
  systemctl status kris-qwen-control.service --no-pager || true
  echo "KRIS Qwen durable controller failed to become active." >&2
  exit 2
fi

QWEN_ROOT="$("${PYTHON_BIN}" - "${ENV_FILE}" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
match = re.search(r'^KRIS_QWEN_ROOT=(?:"([^"]*)"|(.*))$', text, flags=re.M)
print((match.group(1) if match and match.group(1) is not None else match.group(2)) if match else '')
PY
)"
TOKEN_FILE="${QWEN_ROOT}/controller/control-token"

echo
echo "KRIS Qwen durable always-on engineering control installed."
echo "Service user: ${SERVICE_USER}"
echo "Worker:       5.4.1"
echo "Controller:   2.2.2"
echo "Branch:       ${CURRENT_BRANCH}"
echo "Mode:         $([[ "${PHONE_MODE}" == "1" ]] && echo 'trusted-LAN/VPN phone' || echo 'loopback')"
echo "Status:       systemctl status kris-qwen-control --no-pager"
echo "Logs:         journalctl -u kris-qwen-control -f"
echo "Environment:  ${ENV_FILE}"
echo "Token file:   ${TOKEN_FILE}"
echo
echo "Controller crashes are restarted by systemd. Worker crashes/model-server failures"
echo "are recovered by controller 2.2.2 / worker 5.4.1, safe branch updates are automatic,"
echo "and the 5.4.1 engineering environment provides bounded skills/build/test recipes."
if [[ "${PHONE_MODE}" == "1" ]]; then
  echo
echo "Phone mode is enabled. Use only on a trusted LAN/VPN."
else
  echo
echo "For phone access on a trusted LAN/VPN rerun:"
  echo "  sudo ./tool/install_kris_qwen_control_systemd.sh --phone"
fi
echo
echo "Do not expose the plain-HTTP control port directly to the public Internet."
