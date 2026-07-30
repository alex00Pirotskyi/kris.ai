#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"; OUT="$ROOT/release/evidence/P1A/platforms/linux"; rm -rf "$OUT"; mkdir -p "$OUT/artifacts"
for v in KRISTIN_P1A_PACKAGE_SHA256 KRISTIN_P1A_RUNNER_ATTESTATION_PROVIDER KRISTIN_P1A_EVIDENCE_TRUST KRISTIN_P1A_EVIDENCE_SIGNER KRISTIN_P1A_LINUX_PERMIT_KEY_URI GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_JOB GITHUB_SHA; do [[ -n "${!v:-}" ]] || { echo "missing $v" >&2; exit 1; }; done
python "$ROOT/tool/p1a_behavioral_orchestrator.py" --project "$ROOT" --platform linux --service-binary "$ROOT/.p1a-build-linux/kristin_p1_authority_service" --connector "$ROOT/.p1a-connector-linux/kristin_p1a_connector_cli" --worker-launcher "$ROOT/.p1a-worker-linux/kristin_p2_worker_launcher" --installer "$ROOT/authority_service/install/linux/install_linux.sh" --uninstaller "$ROOT/authority_service/install/linux/uninstall.sh" --output "$OUT"
