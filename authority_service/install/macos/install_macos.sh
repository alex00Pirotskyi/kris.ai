#!/usr/bin/env bash
set -euo pipefail
MODE=${1:-};: "${KRISTIN_P1A_APP_BUNDLE:=}";: "${KRISTIN_P1A_SIGNING_IDENTITY:=}";: "${KRISTIN_P1A_SERVICE_BINARY:=}";: "${KRISTIN_P1A_CONNECTOR_LIBRARY:=}";: "${KRISTIN_P1A_WORKER_LAUNCHER:=}";: "${KRISTIN_P1A_MANAGER:=}";: "${KRISTIN_P1A_CONFIG:=}";: "${KRISTIN_P1A_DAEMON_PLIST:=}";: "${KRISTIN_P1A_GRANT_SECRET_HEX:=}";: "${KRISTIN_P1A_OWNER_SECRET_HEX:=}"
PLIST=com.kristin.p1authority.plist
case "$MODE" in
 install)
  [[ -d $KRISTIN_P1A_APP_BUNDLE && -n $KRISTIN_P1A_SIGNING_IDENTITY ]] || { echo 'ERROR: signed host app bundle required' >&2;exit 2; }
  [[ -f $KRISTIN_P1A_CONFIG && -f $KRISTIN_P1A_DAEMON_PLIST ]] || { echo 'ERROR: config and embedded daemon plist required' >&2;exit 2; }
  helper="$KRISTIN_P1A_APP_BUNDLE/Contents/Library/LaunchDaemons/com.kristin.p1authority";worker="$KRISTIN_P1A_APP_BUNDLE/Contents/Helpers/kristin_p2_worker_launcher";connector="$KRISTIN_P1A_APP_BUNDLE/Contents/Frameworks/libkristin_p1a_connector.dylib";plist="$KRISTIN_P1A_APP_BUNDLE/Contents/Library/LaunchDaemons/$PLIST";config="$KRISTIN_P1A_APP_BUNDLE/Contents/Resources/p1-authority-service-v63.json"
  install -d -m 0755 "$(dirname "$helper")" "$(dirname "$worker")" "$(dirname "$connector")" "$(dirname "$config")"
  install -m 0755 "$KRISTIN_P1A_SERVICE_BINARY" "$helper";install -m 0755 "$KRISTIN_P1A_WORKER_LAUNCHER" "$worker";install -m 0755 "$KRISTIN_P1A_CONNECTOR_LIBRARY" "$connector";install -m 0644 "$KRISTIN_P1A_DAEMON_PLIST" "$plist";install -m 0600 "$KRISTIN_P1A_CONFIG" "$config"
  codesign --force --options runtime --sign "$KRISTIN_P1A_SIGNING_IDENTITY" "$helper"
  codesign --force --options runtime --entitlements "$(dirname "$0")/../../worker_launcher/macos/KristinWorker.entitlements" --sign "$KRISTIN_P1A_SIGNING_IDENTITY" "$worker"
  codesign --force --options runtime --sign "$KRISTIN_P1A_SIGNING_IDENTITY" "$connector"
  printf '%s\n%s\n' "$KRISTIN_P1A_GRANT_SECRET_HEX" "$KRISTIN_P1A_OWNER_SECRET_HEX" | "$helper" "$config" --provision-stdin
  "$KRISTIN_P1A_MANAGER" register "$PLIST"
  desktop_home="${KRISTIN_P1A_DESKTOP_HOME:-$HOME}"
  connector_root="$desktop_home/Library/Application Support/Kristin/authority-service"
  connector_config="$connector_root/connector-v2.json"
  mach_service=$(/usr/bin/plutil -extract machServiceName raw -o - "$config")
  service_instance=$(/usr/bin/plutil -extract serviceInstanceId raw -o - "$config")
  policy_path=$(/usr/bin/plutil -extract policySnapshotPath raw -o - "$config")
  [[ -n $mach_service && -n $service_instance && -f $policy_path ]] || { echo 'ERROR: installed authority identity invalid' >&2;exit 2; }
  sha(){ /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'; }
  install -d -m 0700 "$connector_root"
  cat > "$connector_config" <<EOF
{"schemaVersion":"2.0.0","connectorLibraryPath":"$connector","maxResponseBytes":4194304,"completionEligible":false,"endpoint":{"platform":"macos","transport":"macos-xpc","address":"$mach_service","serviceInstanceId":"$service_instance","serviceBuildSha256":"$(sha "$helper")","connectorLibrarySha256":"$(sha "$connector")","installerSha256":"$(sha "$0")","serverIdentity":{"machServiceName":"$mach_service"},"osEnforcedIsolation":true,"workerPrincipalSeparated":true,"typedOperationsOnly":true,"nonExportableKeys":true},"provenance":{"authorityType":"p1-isolated-authority-service-v2","runtimeEligible":true,"securityIsolationActive":true,"privateAuthorityMaterialPresent":false,"arbitraryMessageSigningApi":false,"p1AmendmentMerged":false,"p1AmendmentSchemaVersion":"3.0.0","independentP1aSecurityReviewApproved":false,"workerDenialTriPlatformPassed":false,"behavioralWindowsPassed":false,"behavioralMacosPassed":false,"behavioralLinuxPassed":false,"mergedCommit":"0000000000000000000000000000000000000000","mergedTree":"0000000000000000000000000000000000000000","aggregateManifestSha256":"0000000000000000000000000000000000000000000000000000000000000000","policySnapshotSha256":"$(sha "$policy_path")"}}
EOF
  chmod 0600 "$connector_config"
  ;;
 uninstall) "$KRISTIN_P1A_MANAGER" unregister "$PLIST" || true ;;
 status) "$KRISTIN_P1A_MANAGER" status "$PLIST" ;;
 *) echo 'usage: install_macos.sh install|uninstall|status' >&2;exit 2;;
esac
