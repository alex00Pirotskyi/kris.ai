#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"; OUT="$ROOT/release/evidence/P1A/platforms/macos"; rm -rf "$OUT"; mkdir -p "$OUT/artifacts"
for v in KRISTIN_P1A_PACKAGE_SHA256 KRISTIN_P1A_RUNNER_ATTESTATION_PROVIDER KRISTIN_P1A_EVIDENCE_TRUST KRISTIN_P1A_EVIDENCE_SIGNER KRISTIN_P1A_MACOS_SIGNING_IDENTITY GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_JOB GITHUB_SHA; do [[ -n "${!v:-}" ]] || { echo "missing $v" >&2; exit 1; }; done
python "$ROOT/tool/p1a_behavioral_orchestrator.py" --project "$ROOT" --platform macos --service-binary "$ROOT/.p1a-build-macos/kristin_p1_authority_service_macos" --connector "$ROOT/.p1a-connector-macos/kristin_p1a_connector_cli" --worker-launcher "$ROOT/.p1a-worker-macos/kristin_p2_worker_launcher" --installer "$ROOT/authority_service/install/macos/install_macos.sh" --uninstaller "$ROOT/authority_service/install/macos/uninstall.sh" --output "$OUT"
