#!/usr/bin/env bash
set -euo pipefail
umask 077
MODE=${1:-}
[[ $EUID -eq 0 ]] || { echo 'ERROR: root required' >&2; exit 2; }
: "${KRISTIN_P1A_SERVICE_BINARY:=}"
: "${KRISTIN_P1A_CONNECTOR_LIBRARY:=}"
: "${KRISTIN_P1A_WORKER_LAUNCHER:=}"
: "${KRISTIN_P1A_POLICY_SNAPSHOT:=}"
: "${KRISTIN_P1A_REVOCATIONS:=}"
: "${KRISTIN_P1A_APPROVALS:=}"
: "${KRISTIN_P1A_PERMIT_KEY_URI:=}"
: "${KRISTIN_P1A_GRANT_CREDENTIAL:=}"
: "${KRISTIN_P1A_OWNER_CREDENTIAL:=}"
: "${KRISTIN_P1A_DESKTOP_UID:=}"
: "${KRISTIN_P1A_DESKTOP_EXE_SHA256:=}"
SERVICE_USER=kristin-authority
WORKER_USER=kristin-worker
SERVICE_GROUP=kristin-authority
ROOT=/opt/kristin/p1a
STATE=/var/lib/kristin/p1a
RUNTIME=/run/kristin-p1a
UNIT=/etc/systemd/system/kristin-p1-authority.service
CONNECTOR_CONFIG="$(getent passwd "$KRISTIN_P1A_DESKTOP_UID" | cut -d: -f6)/.local/share/kristin/authority-service/connector-v2.json"
need_file(){ [[ -f $1 && ! -L $1 ]] || { echo "ERROR: required file missing: $1" >&2; exit 2; }; }
sha(){ sha256sum "$1" | awk '{print $1}'; }
case "$MODE" in
 install)
  for x in "$KRISTIN_P1A_SERVICE_BINARY" "$KRISTIN_P1A_CONNECTOR_LIBRARY" "$KRISTIN_P1A_WORKER_LAUNCHER" "$KRISTIN_P1A_POLICY_SNAPSHOT" "$KRISTIN_P1A_REVOCATIONS" "$KRISTIN_P1A_APPROVALS" "$KRISTIN_P1A_GRANT_CREDENTIAL" "$KRISTIN_P1A_OWNER_CREDENTIAL";do need_file "$x";done
  [[ $KRISTIN_P1A_PERMIT_KEY_URI == pkcs11:* || $KRISTIN_P1A_PERMIT_KEY_URI == tpm2:* ]] || { echo 'ERROR: TPM2/PKCS#11 provider URI required' >&2; exit 2; }
  [[ $KRISTIN_P1A_DESKTOP_UID =~ ^[0-9]+$ && $KRISTIN_P1A_DESKTOP_EXE_SHA256 =~ ^[0-9a-f]{64}$ ]] || { echo 'ERROR: desktop identity invalid' >&2; exit 2; }
  getent group "$SERVICE_GROUP" >/dev/null || groupadd --system "$SERVICE_GROUP"
  id "$SERVICE_USER" >/dev/null 2>&1 || useradd --system --gid "$SERVICE_GROUP" --home-dir "$STATE" --shell /usr/sbin/nologin "$SERVICE_USER"
  id "$WORKER_USER" >/dev/null 2>&1 || useradd --system --home-dir /var/empty/kristin-worker --create-home --shell /usr/sbin/nologin "$WORKER_USER"
  SERVICE_UID=$(id -u "$SERVICE_USER"); SERVICE_GID=$(id -g "$SERVICE_USER"); WORKER_UID=$(id -u "$WORKER_USER"); WORKER_GID=$(id -g "$WORKER_USER")
  [[ $SERVICE_UID != "$WORKER_UID" && $SERVICE_UID != "$KRISTIN_P1A_DESKTOP_UID" && $WORKER_UID != "$KRISTIN_P1A_DESKTOP_UID" ]] || { echo 'ERROR: identities must be distinct' >&2; exit 2; }
  install -d -o root -g "$SERVICE_GROUP" -m 0750 "$ROOT" "$ROOT/bin" "$ROOT/lib" "$ROOT/config"
  install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0700 "$STATE"
  install -o root -g root -m 0755 "$KRISTIN_P1A_SERVICE_BINARY" "$ROOT/bin/kristin_p1_authority_service"
  install -o root -g root -m 0755 "$KRISTIN_P1A_CONNECTOR_LIBRARY" "$ROOT/lib/libkristin_p1a_connector.so"
  install -o root -g root -m 4755 "$KRISTIN_P1A_WORKER_LAUNCHER" "$ROOT/bin/kristin_p2_worker_launcher"
  cat > "$ROOT/config/worker-principal.json" <<EOF
{"schemaVersion":"1.0.0","workerUid":$WORKER_UID,"workerGid":$WORKER_GID,"authorityAddress":"$RUNTIME/authority.sock","launcherSha256":"$(sha "$ROOT/bin/kristin_p2_worker_launcher")"}
EOF
  chown root:root "$ROOT/config/worker-principal.json"; chmod 0400 "$ROOT/config/worker-principal.json"
  install -o root -g "$SERVICE_GROUP" -m 0640 "$KRISTIN_P1A_POLICY_SNAPSHOT" "$ROOT/config/policy.json"
  install -o root -g "$SERVICE_GROUP" -m 0640 "$KRISTIN_P1A_REVOCATIONS" "$ROOT/config/revocations.json"
  install -o root -g "$SERVICE_GROUP" -m 0640 "$KRISTIN_P1A_APPROVALS" "$ROOT/config/approvals.json"
  install -o root -g root -m 0400 "$KRISTIN_P1A_GRANT_CREDENTIAL" "$ROOT/config/grant.credential"
  install -o root -g root -m 0400 "$KRISTIN_P1A_OWNER_CREDENTIAL" "$ROOT/config/owner.credential"
  cat > "$UNIT" <<EOF
[Unit]
Description=Kristin P1 isolated authority service
After=local-fs.target
[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
RuntimeDirectory=kristin-p1a
RuntimeDirectoryMode=0711
StateDirectory=kristin/p1a
StateDirectoryMode=0700
LoadCredential=grant.hmac:$ROOT/config/grant.credential
LoadCredential=owner.hmac:$ROOT/config/owner.credential
ExecStart=$ROOT/bin/kristin_p1_authority_service --socket $RUNTIME/authority.sock --config $ROOT/config/policy.json --state $STATE/state.log --audit $STATE/audit.log --revocations $ROOT/config/revocations.json --approvals $ROOT/config/approvals.json --permit-key-uri '$KRISTIN_P1A_PERMIT_KEY_URI' --grant-hmac-credential \\${CREDENTIALS_DIRECTORY}/grant.hmac --owner-hmac-credential \\${CREDENTIALS_DIRECTORY}/owner.hmac --desktop-uid $KRISTIN_P1A_DESKTOP_UID --worker-uid $WORKER_UID --worker-gid $WORKER_GID --service-uid $SERVICE_UID --service-gid $SERVICE_GID --desktop-exe-sha256 $KRISTIN_P1A_DESKTOP_EXE_SHA256
Restart=on-failure
RestartSec=1s
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=read-only
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_UNIX
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
CapabilityBoundingSet=CAP_CHOWN
AmbientCapabilities=CAP_CHOWN
UMask=0077
[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$UNIT"
  desktop_home=$(getent passwd "$KRISTIN_P1A_DESKTOP_UID" | cut -d: -f6)
  [[ -n $desktop_home ]] || { echo 'ERROR: desktop home missing' >&2; exit 2; }
  install -d -o "$KRISTIN_P1A_DESKTOP_UID" -g "$KRISTIN_P1A_DESKTOP_UID" -m 0700 "$(dirname "$CONNECTOR_CONFIG")"
  cat > "$CONNECTOR_CONFIG" <<EOF
{"schemaVersion":"2.0.0","connectorLibraryPath":"$ROOT/lib/libkristin_p1a_connector.so","maxResponseBytes":4194304,"completionEligible":false,"endpoint":{"platform":"linux","transport":"linux-af-unix","address":"$RUNTIME/authority.sock","serviceInstanceId":"p1a-linux-v63","serviceBuildSha256":"$(sha "$ROOT/bin/kristin_p1_authority_service")","connectorLibrarySha256":"$(sha "$ROOT/lib/libkristin_p1a_connector.so")","installerSha256":"$(sha "$0")","serverIdentity":{"serviceUid":$SERVICE_UID,"desktopUid":$KRISTIN_P1A_DESKTOP_UID,"workerUid":$WORKER_UID,"workerGid":$WORKER_GID},"osEnforcedIsolation":true,"workerPrincipalSeparated":true,"typedOperationsOnly":true,"nonExportableKeys":true},"provenance":{"authorityType":"p1-isolated-authority-service-v2","p1AmendmentMerged":false,"p1AmendmentSchemaVersion":"3.0.0","independentP1aSecurityReviewApproved":false,"workerDenialTriPlatformPassed":false,"behavioralWindowsPassed":false,"behavioralMacosPassed":false,"behavioralLinuxPassed":false,"mergedCommit":"0000000000000000000000000000000000000000","mergedTree":"0000000000000000000000000000000000000000","aggregateManifestSha256":"0000000000000000000000000000000000000000000000000000000000000000","policySnapshotSha256":"$(sha "$ROOT/config/policy.json")"}}
EOF
  chown "$KRISTIN_P1A_DESKTOP_UID:$KRISTIN_P1A_DESKTOP_UID" "$CONNECTOR_CONFIG"; chmod 0600 "$CONNECTOR_CONFIG"
  systemctl daemon-reload; systemctl enable --now kristin-p1-authority.service
  systemctl is-active --quiet kristin-p1-authority.service
  ;;
 uninstall)
  systemctl disable --now kristin-p1-authority.service 2>/dev/null || true
  rm -f "$UNIT" "$CONNECTOR_CONFIG"; systemctl daemon-reload
  rm -rf "$ROOT" "$RUNTIME" "$STATE"
  ;;
 status) systemctl status --no-pager kristin-p1-authority.service ;;
 *) echo 'usage: install_linux.sh install|uninstall|status' >&2; exit 2;;
esac
