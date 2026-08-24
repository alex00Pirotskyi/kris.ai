#!/usr/bin/env python3
from __future__ import annotations
import pathlib
R=pathlib.Path(__file__).resolve().parents[1]
def rd(p): return (R/p).read_text(encoding='utf-8')
def wr(p,s): (R/p).write_text(s,encoding='utf-8',newline='\n')
def rep(p,a,b):
 s=rd(p);n=s.count(a)
 if n!=1: raise SystemExit(f'{p}: target count {n}: {a[:80]!r}')
 wr(p,s.replace(a,b,1))

p='authority_service/native/common/authority_core_v2.hpp'
rep(p,
'''  const auto approval_expiry = json::required_int(approval, "expiresAtEpochSeconds");
  if (approval_expiry <= now || approval_expiry > now + 900) throw std::runtime_error("policy_owner_approval_expired");''',
'''  const auto approval_expiry = json::required_int(approval, "expiresAtEpochSeconds");
  const auto approval_scope = approval.contains("approvalScope")
      ? json::required_string(approval, "approvalScope") : std::string("effect");
  const auto approval_lifetime = approval_scope == "owner-session" ? 86400 : 900;
  if ((approval_scope != "effect" && approval_scope != "owner-session") ||
      approval_expiry <= now || approval_expiry > now + approval_lifetime)
    throw std::runtime_error("policy_owner_approval_expired");''')
rep(p,
'''    const auto confirmation_sha = json::required_string(request, "confirmationTextSha256");
    const bool user_present = json::required_bool(request, "userPresent");
    const auto& binding_value = request.at("binding");''',
'''    const auto confirmation_sha = json::required_string(request, "confirmationTextSha256");
    const bool user_present = json::required_bool(request, "userPresent");
    const auto approval_scope = request.contains("approvalScope")
        ? json::required_string(request, "approvalScope") : std::string("effect");
    const auto approval_policy = request.contains("approvalPolicy")
        ? json::required_string(request, "approvalPolicy") : std::string("boundedSession");
    const auto owner_session_id = request.contains("ownerSessionId")
        ? json::required_string(request, "ownerSessionId") : std::string();
    const auto& binding_value = request.at("binding");''')
rep(p,
'''    if (!valid_identifier(request_id) || !valid_identifier(approval_id) || !valid_identifier(interaction_nonce) ||
        interaction_type != "native-owner-confirmation" || !user_present || !valid_hex64(payload_sha) ||
        !valid_hex64(ui_sha) || !valid_hex64(confirmation_sha) || expires_at <= now || expires_at > now + 900)
      throw std::runtime_error("owner_approval_request_invalid");''',
'''    const bool session_scope = approval_scope == "owner-session";
    const auto max_approval_lifetime = session_scope ? 86400 : 900;
    if (!valid_identifier(request_id) || !valid_identifier(approval_id) || !valid_identifier(interaction_nonce) ||
        (approval_scope != "effect" && approval_scope != "owner-session") ||
        (approval_policy != "everyHighRiskEffect" && approval_policy != "destructiveOnly" && approval_policy != "boundedSession") ||
        (session_scope && (!valid_identifier(owner_session_id) || owner_session_id.empty())) ||
        (!session_scope && !owner_session_id.empty()) ||
        interaction_type != "native-owner-confirmation" || !user_present || !valid_hex64(payload_sha) ||
        !valid_hex64(ui_sha) || !valid_hex64(confirmation_sha) || expires_at <= now ||
        expires_at > now + max_approval_lifetime)
      throw std::runtime_error("owner_approval_request_invalid");''')
rep(p,
'''    const auto operation = json::required_string(request, "effectOperation");
    if (!valid_identifier(operation)) throw std::runtime_error("owner_approval_operation_invalid");
    json::value::object approval{{"schemaVersion",json::value("2.0.0")},{"approvalId",json::value(approval_id)},''',
'''    const auto operation = json::required_string(request, "effectOperation");
    if (!valid_identifier(operation) || (session_scope && operation != "owner-session"))
      throw std::runtime_error("owner_approval_operation_invalid");
    json::value::object approval{{"schemaVersion",json::value("2.0.0")},{"approvalId",json::value(approval_id)},''')
rep(p,
'''      {"binding",json::value(binding)},
      {"effectOperation",json::value(operation)},{"payloadSha256",json::value(payload_sha)},
      {"expiresAtEpochSeconds",json::value(expires_at)},{"interaction",json::value(json::value::object{''',
'''      {"binding",json::value(binding)},
      {"effectOperation",json::value(operation)},{"payloadSha256",json::value(payload_sha)},
      {"approvalScope",json::value(approval_scope)},{"approvalPolicy",json::value(approval_policy)},
      {"ownerSessionId",session_scope ? json::value(owner_session_id) : json::value(nullptr)},
      {"expiresAtEpochSeconds",json::value(expires_at)},{"interaction",json::value(json::value::object{''')
rep(p,
'''    if (json::required_string(approval_object, "schemaVersion") != "2.0.0" ||
        json::required_string(approval_object, "approvalId") != owner_approval_id ||
        json::required_string(approval_object, "requestId") != request_id)
      throw std::runtime_error("authority_owner_approval_request_mismatch");
    if (json::required_string(approval_object, "effectOperation") != operation)
      throw std::runtime_error("authority_owner_approval_operation_mismatch");
    if (json::required_string(approval_object, "payloadSha256") != payload_sha)
      throw std::runtime_error("authority_owner_approval_payload_mismatch");
    if (json::canonical(approval.at("binding")) != json::canonical(request.at("binding")))
      throw std::runtime_error("authority_owner_approval_binding_mismatch");''',
'''    if (json::required_string(approval_object, "schemaVersion") != "2.0.0" ||
        json::required_string(approval_object, "approvalId") != owner_approval_id)
      throw std::runtime_error("authority_owner_approval_request_mismatch");
    const auto approval_scope = approval_object.contains("approvalScope")
        ? json::required_string(approval_object, "approvalScope") : std::string("effect");
    if (approval_scope == "effect") {
      if (json::required_string(approval_object, "requestId") != request_id)
        throw std::runtime_error("authority_owner_approval_request_mismatch");
      if (json::required_string(approval_object, "effectOperation") != operation)
        throw std::runtime_error("authority_owner_approval_operation_mismatch");
      if (json::required_string(approval_object, "payloadSha256") != payload_sha)
        throw std::runtime_error("authority_owner_approval_payload_mismatch");
      if (json::canonical(approval.at("binding")) != json::canonical(request.at("binding")))
        throw std::runtime_error("authority_owner_approval_binding_mismatch");
    } else if (approval_scope == "owner-session") {
      const auto owner_session_id = request.contains("ownerSessionId")
          ? json::required_string(request, "ownerSessionId") : std::string();
      const auto approved_session_id = approval_object.contains("ownerSessionId") &&
          !approval_object.at("ownerSessionId").is_null()
          ? json::required_string(approval_object, "ownerSessionId") : std::string();
      if (!valid_identifier(owner_session_id) || owner_session_id != approved_session_id)
        throw std::runtime_error("authority_owner_session_mismatch");
      const auto& approval_binding = json::required_object(approval_object, "binding");
      const auto& request_binding = json::required_object(request, "binding");
      if (json::required_string(approval_binding, "accessProfileId") !=
          json::required_string(request_binding, "accessProfileId"))
        throw std::runtime_error("authority_owner_approval_binding_mismatch");
    } else {
      throw std::runtime_error("authority_owner_approval_scope_invalid");
    }''')
rep(p,
'''    const auto grant_id = "grant-" + sha256_hex(config_.service_instance_id + "|" + owner_approval_id + "|" + approval_digest).substr(0, 32);''',
'''    const auto grant_id = "grant-" + sha256_hex(config_.service_instance_id + "|" + owner_approval_id + "|" +
      approval_digest + "|" + request_id).substr(0, 32);''')

p='authority_service/native/common/authority_core_regression_test.cpp'
session='''  mock_state session_state; kp::authority_core session_core(config(),crypto,session_state);
  auto session_approval=approval_request(body,now+3600);
  auto& session_approval_obj=session_approval.as_object();
  session_approval_obj["requestId"]=kp::json::value("session-approval-request");
  session_approval_obj["approvalId"]=kp::json::value("session-approval-1");
  session_approval_obj["approvalScope"]=kp::json::value("owner-session");
  session_approval_obj["approvalPolicy"]=kp::json::value("boundedSession");
  session_approval_obj["ownerSessionId"]=kp::json::value("owner-session-1");
  session_approval_obj["effectOperation"]=kp::json::value("owner-session");
  session_core.handle(session_approval,desktop);
  auto session_effect_1=effect_request(body,"session-nonce-1",now+60);
  auto& session_effect_1_obj=session_effect_1.as_object();
  session_effect_1_obj["requestId"]=kp::json::value("session-effect-1");
  session_effect_1_obj["ownerApprovalId"]=kp::json::value("session-approval-1");
  session_effect_1_obj["ownerSessionId"]=kp::json::value("owner-session-1");
  const auto session_authorized_1=session_core.handle(session_effect_1,desktop);
  if (kp::json::required_string(session_authorized_1.as_object(),"status")!="authorized")
    throw std::runtime_error("session_authorization_first_failed");
  const auto session_body_2=payload("/home/alex/work/other.txt");
  auto session_effect_2=effect_request(session_body_2,"session-nonce-2",now+60,binding(),"write","/home/alex/work/other.txt");
  auto& session_effect_2_obj=session_effect_2.as_object();
  session_effect_2_obj["requestId"]=kp::json::value("session-effect-2");
  session_effect_2_obj["ownerApprovalId"]=kp::json::value("session-approval-1");
  session_effect_2_obj["ownerSessionId"]=kp::json::value("owner-session-1");
  const auto session_authorized_2=session_core.handle(session_effect_2,desktop);
  if (kp::json::required_string(session_authorized_2.as_object(),"status")!="authorized")
    throw std::runtime_error("session_authorization_second_failed");
  auto bad_session_effect=effect_request(body,"session-nonce-3",now+60);
  auto& bad_session_obj=bad_session_effect.as_object();
  bad_session_obj["requestId"]=kp::json::value("session-effect-3");
  bad_session_obj["ownerApprovalId"]=kp::json::value("session-approval-1");
  bad_session_obj["ownerSessionId"]=kp::json::value("owner-session-wrong");
  must_fail([&]{session_core.handle(bad_session_effect,desktop);},"authority_owner_session_mismatch");
'''
rep(p,
'''  must_fail([&]{core.handle(effect_request(body,"nonce-7",now+60,binding(),"write","/home/alex/work/../outside"),desktop);},"policy_path_outside_current_account");
  std::cout << "{\\"status\\":\\"passed\\",\\"test\\":\\"p1a-authority-core-regression-v1\\",\\"jsonStringLiteral\\":true,\\"approvalExactBinding\\":true,\\"approvalOneUse\\":true,\\"pathTraversalDenied\\":true}\\n";''',
'''  must_fail([&]{core.handle(effect_request(body,"nonce-7",now+60,binding(),"write","/home/alex/work/../outside"),desktop);},"policy_path_outside_current_account");
'''+session+'''  std::cout << "{\\"status\\":\\"passed\\",\\"test\\":\\"p1a-authority-core-regression-v2\\",\\"jsonStringLiteral\\":true,\\"approvalExactBinding\\":true,\\"approvalOneUse\\":true,\\"ownerSessionReuse\\":true,\\"pathTraversalDenied\\":true}\\n";''')

p='authority_service/install/windows/Install-KristinP1Authority.ps1'
rep(p,"provenance=@{authorityType='p1-isolated-authority-service-v2';p1AmendmentMerged=$false;",
      "provenance=@{authorityType='p1-isolated-authority-service-v2';runtimeEligible=$true;securityIsolationActive=$true;privateAuthorityMaterialPresent=$false;arbitraryMessageSigningApi=$false;p1AmendmentMerged=$false;")
p='authority_service/install/linux/install_linux.sh'
rep(p,'"provenance":{"authorityType":"p1-isolated-authority-service-v2","p1AmendmentMerged":false',
      '"provenance":{"authorityType":"p1-isolated-authority-service-v2","runtimeEligible":true,"securityIsolationActive":true,"privateAuthorityMaterialPresent":false,"arbitraryMessageSigningApi":false,"p1AmendmentMerged":false')

p='authority_service/install/macos/install_macos.sh'
rep(p,'  "$KRISTIN_P1A_MANAGER" register "$PLIST"\n  ;;','''  "$KRISTIN_P1A_MANAGER" register "$PLIST"
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
  ;;''')

rep('tool/p1a_activate_merged_installation.py','''        "authorityType": "p1-isolated-authority-service-v2",
        "activationType": "merged-p1a-v63-signed-evidence-activation",''','''        "authorityType": "p1-isolated-authority-service-v2",
        "runtimeEligible": True,
        "securityIsolationActive": True,
        "activationType": "merged-p1a-v63-signed-evidence-activation",''')
print('P1A_NATIVE_V2_OK')
