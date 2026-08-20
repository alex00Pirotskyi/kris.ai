#!/usr/bin/env bash
set -euo pipefail

SERVICE="kris-qwen-control.service"
ENV_FILE="${KRIS_QWEN_CONTROL_ENV_FILE:-/etc/kris-qwen-control.env}"

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "KRIS Qwen controller environment is missing: ${ENV_FILE}" >&2
  exit 2
fi

QWEN_ROOT="$(python3 - "${ENV_FILE}" <<'PY'
from __future__ import annotations
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
match = re.search(r'^KRIS_QWEN_ROOT=(?:"([^"]*)"|(.*))$', text, flags=re.M)
if not match:
    raise SystemExit(2)
print(match.group(1) if match.group(1) is not None else match.group(2))
PY
)"

if [[ -z "${QWEN_ROOT}" || "${QWEN_ROOT}" != /* ]]; then
  echo "KRIS_QWEN_ROOT must be an absolute path in ${ENV_FILE}" >&2
  exit 2
fi

TOKEN_FILE="${QWEN_ROOT}/controller/control-token"
systemctl stop "${SERVICE}"
rm -f -- "${TOKEN_FILE}"
systemctl start "${SERVICE}"

if ! systemctl is-active --quiet "${SERVICE}"; then
  systemctl status "${SERVICE}" --no-pager || true
  echo "KRIS Qwen controller did not recover after token rotation." >&2
  exit 2
fi
if [[ ! -f "${TOKEN_FILE}" ]]; then
  echo "KRIS Qwen controller did not create a replacement token file." >&2
  exit 2
fi
chmod 600 "${TOKEN_FILE}"

echo "KRIS Qwen control token rotated."
echo "Token value was not printed."
echo "Token file: ${TOKEN_FILE}"
echo "Read it locally only when you need to enter it into the trusted phone session."
