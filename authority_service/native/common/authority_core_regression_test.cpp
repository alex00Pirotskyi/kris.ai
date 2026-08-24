#include "authority_core_v2.hpp"

#include <iostream>
#include <map>
#include <set>
#include <stdexcept>
#include <string>

namespace kp = kristin::p1a;

namespace {
class mock_crypto final : public kp::crypto_backend {
 public:
  std::string hmac_sha256_hex(std::string_view purpose, std::string_view key_id,
                              std::string_view message) override {
    (void)kp::hmac_secret_for_purpose(purpose);
    if (!kp::valid_identifier(key_id)) throw std::runtime_error("mock_key_id_invalid");
    return kp::sha256_hex(std::string(purpose) + "|" + std::string(key_id) + "|" + std::string(message));
  }
  kp::signature_result sign_effect_permit(std::string_view canonical) override {
    return {"ecdsa-p256-sha256", "test-permit-key", kp::sha256_hex(canonical), "test-spki",
            "test-provider", std::string(64, 'a'), true, true};
  }
  kp::json::value public_description() const override {
    return kp::json::value(kp::json::value::object{{"provider", kp::json::value("test-provider")}});
  }
};

class mock_state final : public kp::state_backend {
 public:
  std::uint64_t revocation_epoch() const override { return 0; }
  bool capability_revoked(std::string_view) const override { return false; }
  bool nonce_consumed(std::string_view nonce) const override { return nonces.contains(std::string(nonce)); }
  std::uint64_t grant_use_count(std::string_view grant) const override {
    const auto it = uses.find(std::string(grant)); return it == uses.end() ? 0 : it->second;
  }
  std::string audit_head_sha256() const override { return audit_head; }
  void commit_authorization(std::string_view nonce, std::string_view grant, std::uint64_t use,
                            std::string_view permit, std::string_view, std::string_view audit) override {
    nonces.insert(std::string(nonce)); uses[std::string(grant)] = use;
    permits.insert(std::string(permit)); audit_head = std::string(audit);
  }
  bool permit_exists(std::string_view permit) const override { return permits.contains(std::string(permit)); }
  kp::json::value owner_approval(std::string_view approval) const override {
    const auto it = approvals.find(std::string(approval));
    if (it == approvals.end()) throw std::runtime_error("owner_approval_missing");
    return kp::json::parse(it->second);
  }
  void commit_owner_approval(std::string_view approval, std::string_view canonical) override {
    if (!approvals.emplace(std::string(approval), std::string(canonical)).second)
      throw std::runtime_error("owner_approval_replay");
  }
  void commit_outcome(std::string_view, std::string_view, std::string_view) override {}
  std::uint64_t service_generation() const override { return 1; }
  void begin_behavior_session(std::string_view, std::string_view) override { throw std::runtime_error("unused"); }
  void record_behavior_event(std::string_view, std::string_view, std::string_view) override { throw std::runtime_error("unused"); }
  kp::json::value behavior_session(std::string_view) const override { throw std::runtime_error("unused"); }
 private:
  std::set<std::string> nonces;
  std::set<std::string> permits;
  std::map<std::string, std::uint64_t> uses;
  std::map<std::string, std::string> approvals;
  std::string audit_head = std::string(64, '0');
};

kp::json::value::object binding() {
  return {{"runId", kp::json::value("run-1")}, {"taskId", kp::json::value("task-1")},
          {"actorId", kp::json::value("actor-1")}, {"toolId", kp::json::value("tool-1")},
          {"accessProfileId", kp::json::value("owner")}, {"capabilityId", kp::json::value("cap-files")}};
}

kp::authority_config config() {
  kp::authority_config cfg;
  cfg.service_instance_id = "service-1"; cfg.policy_revision = "policy-1";
  cfg.policy_snapshot_sha256 = std::string(64, '1'); cfg.grant_hmac_key_id = "grant-key";
  cfg.owner_approval_hmac_key_id = "approval-key"; cfg.service_build_sha256 = std::string(64, '2');
  cfg.runtime_build_sha256 = std::string(64, '3'); cfg.source_commit = std::string(40, '4');
  cfg.source_tree = std::string(40, '5'); cfg.max_deadline_seconds = 120; cfg.permit_ttl_seconds = 90;
  const auto ceiling = kp::json::value(kp::json::value::object{{"wallClockMs",kp::json::value(1000)},
    {"maxOutputBytes",kp::json::value(1000)},{"maxNetworkBytes",kp::json::value(1000)},
    {"maxCostMicros",kp::json::value(1000)},{"maxMutations",kp::json::value(10)}});
  const auto capabilities = kp::json::value(kp::json::value::array{kp::json::value("cap-files")});
  cfg.profiles.emplace("owner", kp::json::value(kp::json::value::object{{"capabilities",capabilities},{"budgetCeiling",ceiling}}));
  cfg.profiles.emplace("owner_unattended", kp::json::value(kp::json::value::object{{"capabilities",capabilities},{"budgetCeiling",ceiling}}));
  cfg.capabilities.emplace("cap-files", kp::json::value(kp::json::value::object{{"domain",kp::json::value("filesystem")},
    {"actions",kp::json::value(kp::json::value::array{kp::json::value("write")})}}));
  cfg.current_account_roots = {kp::json::value("/home/alex/work")};
  return cfg;
}

kp::peer_identity peer(std::string principal="desktop-user", std::string executable=std::string(64,'6')) {
  return {"linux", std::move(principal), std::move(executable), "desktop-code", "session-1", 42, true, false};
}

kp::json::value payload(std::string path="/home/alex/work/file.txt") {
  return kp::json::value(kp::json::value::object{{"path",kp::json::value(std::move(path))},{"contentSha256",kp::json::value(std::string(64,'7'))}});
}

kp::json::value approval_request(const kp::json::value& body, std::int64_t expires) {
  return kp::json::value(kp::json::value::object{{"schemaVersion",kp::json::value("2.0.0")},
    {"operation",kp::json::value(std::string(kp::kRecordOwnerApprovalV2))},{"requestId",kp::json::value("request-1")},
    {"approvalId",kp::json::value("approval-1")},{"interactionNonce",kp::json::value("interaction-1")},
    {"interactionType",kp::json::value("native-owner-confirmation")},{"binding",kp::json::value(binding())},
    {"effectOperation",kp::json::value("write")},{"payloadSha256",kp::json::value(kp::sha256_hex(kp::json::canonical(body)))},
    {"uiSurfaceSha256",kp::json::value(std::string(64,'8'))},{"confirmationTextSha256",kp::json::value(std::string(64,'9'))},
    {"userPresent",kp::json::value(true)},{"expiresAtEpochSeconds",kp::json::value(expires)}});
}

kp::json::value effect_request(const kp::json::value& body, std::string nonce, std::int64_t deadline,
                               kp::json::value::object requested_binding=binding(), std::string operation="write",
                               std::string target="/home/alex/work/file.txt") {
  kp::json::value::object worker{{"schemaVersion",kp::json::value("2.0.0")},{"sessionId",kp::json::value("worker-1")},
    {"platform",kp::json::value("linux")},{"principalType",kp::json::value("dedicated-uid")},
    {"startToken",kp::json::value("start-1")},{"pid",kp::json::value(123)},
    {"launcherSha256",kp::json::value(std::string(64,'a'))},{"nodeSha256",kp::json::value(std::string(64,'b'))},
    {"hostScriptSha256",kp::json::value(std::string(64,'c'))}};
  const auto unsigned_worker=kp::json::value(worker);
  worker.emplace("identitySha256",kp::json::value(kp::sha256_hex(kp::json::canonical(unsigned_worker))));
  return kp::json::value(kp::json::value::object{{"schemaVersion",kp::json::value("2.0.0")},
    {"operation",kp::json::value(std::string(kp::kAuthorizeV2))},{"requestId",kp::json::value("request-1")},
    {"requestNonce",kp::json::value(std::move(nonce))},{"workerSessionId",kp::json::value("worker-1")},
    {"channelId",kp::json::value("channel-1")},{"workerIdentity",kp::json::value(worker)},
    {"effectOperation",kp::json::value(std::move(operation))},{"binding",kp::json::value(std::move(requested_binding))},
    {"policyEffect",kp::json::value(kp::json::value::object{{"domain",kp::json::value("filesystem")},
      {"action",kp::json::value("write")},{"target",kp::json::value(std::move(target))}})},
    {"requestedBudgets",kp::json::value(kp::json::value::object{{"wallClockMs",kp::json::value(10)},
      {"maxOutputBytes",kp::json::value(10)},{"maxNetworkBytes",kp::json::value(0)},
      {"maxCostMicros",kp::json::value(0)},{"maxMutations",kp::json::value(1)}})},
    {"payload",body},{"payloadSha256",kp::json::value(kp::sha256_hex(kp::json::canonical(body)))},
    {"ownerApprovalId",kp::json::value("approval-1")},{"expectedRevocationEpoch",kp::json::value(0)},
    {"deadlineEpochSeconds",kp::json::value(deadline)}});
}

template <class F> void must_fail(F&& fn, std::string_view expected) {
  try { fn(); } catch (const std::exception& error) {
    if (std::string_view(error.what()) == expected) return;
    throw std::runtime_error("unexpected_failure:" + std::string(error.what()) + ":expected:" + std::string(expected));
  }
  throw std::runtime_error("expected_failure_missing:" + std::string(expected));
}
}

int main() try {
  if (!kp::json::value("2.0.0").is_string() || kp::json::canonical(kp::json::value("2.0.0")) != "\"2.0.0\"")
    throw std::runtime_error("json_literal_constructor_regression");
  if (!kp::path_within("/home/alex/work/file.txt", "/home/alex/work") ||
      kp::path_within("/home/alex/work/../outside", "/home/alex/work") ||
      kp::path_within("relative/file", "/home/alex/work"))
    throw std::runtime_error("path_containment_regression");
  mock_crypto crypto; mock_state state; kp::authority_core core(config(),crypto,state);
  const auto now=kp::unix_seconds_now(); const auto body=payload(); const auto desktop=peer();
  core.handle(approval_request(body,now+300),desktop);
  const auto authorized=core.handle(effect_request(body,"nonce-1",now+60),desktop);
  if (kp::json::required_string(authorized.as_object(),"status")!="authorized")
    throw std::runtime_error("authorization_not_completed");
  must_fail([&]{core.handle(effect_request(body,"nonce-2",now+60),desktop);},"authority_grant_exhausted");
  const auto changed_payload=payload("/home/alex/work/other.txt");
  must_fail([&]{core.handle(effect_request(changed_payload,"nonce-3",now+60),desktop);},"authority_owner_approval_payload_mismatch");
  auto changed_binding=binding(); changed_binding["taskId"]=kp::json::value("task-2");
  must_fail([&]{core.handle(effect_request(body,"nonce-4",now+60,changed_binding),desktop);},"authority_owner_approval_binding_mismatch");
  must_fail([&]{core.handle(effect_request(body,"nonce-5",now+60,binding(),"delete"),desktop);},"authority_owner_approval_operation_mismatch");
  must_fail([&]{core.handle(effect_request(body,"nonce-6",now+60),peer("other-user"));},"authority_owner_approval_peer_mismatch");
  must_fail([&]{core.handle(effect_request(body,"nonce-7",now+60,binding(),"write","/home/alex/work/../outside"),desktop);},"policy_path_outside_current_account");
  mock_state session_state; kp::authority_core session_core(config(),crypto,session_state);
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
  std::cout << "{\"status\":\"passed\",\"test\":\"p1a-authority-core-regression-v2\",\"jsonStringLiteral\":true,\"approvalExactBinding\":true,\"approvalOneUse\":true,\"ownerSessionReuse\":true,\"pathTraversalDenied\":true}\n";
  return 0;
} catch (const std::exception& error) {
  std::cerr << "P1A authority core regression failed: " << error.what() << "\n";
  return 1;
}
