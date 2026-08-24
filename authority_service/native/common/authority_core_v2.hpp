#pragma once

#include "sha256_portable.hpp"
#include "strict_json.hpp"
#include "validation.hpp"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <ctime>
#include <iomanip>
#include <sstream>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace kristin::p1a {

inline constexpr std::string_view kAuthorizeV2 = "authorize-effect-v2";
inline constexpr std::string_view kRecordOutcomeV2 = "record-effect-outcome-v2";
inline constexpr std::string_view kDescribeV2 = "describe-authority-v2";
inline constexpr std::string_view kRecordOwnerApprovalV2 = "record-owner-approval-v2";
inline constexpr std::string_view kBeginBehaviorV2 = "begin-behavior-session-v2";
inline constexpr std::string_view kFinalizeBehaviorV2 = "finalize-behavior-session-v2";
inline constexpr std::string_view kOwnerApprovalHmacPurpose = "kristin.owner-approval.v2";
inline constexpr std::string_view kCapabilityGrantHmacPurpose = "kristin.capability-grant.v2";
inline constexpr std::string_view kGrantConsumptionHmacPurpose = "kristin.grant-consumption.v1";

enum class hmac_secret_kind { owner_approval, grant };
inline hmac_secret_kind hmac_secret_for_purpose(std::string_view purpose) {
  if (purpose == kOwnerApprovalHmacPurpose) return hmac_secret_kind::owner_approval;
  if (purpose == kCapabilityGrantHmacPurpose || purpose == kGrantConsumptionHmacPurpose)
    return hmac_secret_kind::grant;
  throw std::runtime_error("authority_hmac_purpose_not_allowed");
}

struct peer_identity final {
  std::string platform;
  std::string principal;
  std::string executable_sha256;
  std::string code_identity;
  std::string session_identity;
  std::uint64_t pid = 0;
  bool desktop_authenticated = false;
  bool worker_principal = false;
};

struct signature_result final {
  std::string algorithm;
  std::string key_id;
  std::string signature_base64;
  std::string public_key_spki_base64;
  std::string provider;
  std::string provider_attestation_sha256;
  bool non_exportable = false;
  bool private_export_denied = false;
};

class crypto_backend {
 public:
  virtual ~crypto_backend() = default;
  virtual std::string hmac_sha256_hex(std::string_view purpose, std::string_view key_id,
                                      std::string_view message) = 0;
  virtual signature_result sign_effect_permit(std::string_view canonical_permit) = 0;
  virtual json::value public_description() const = 0;
};

class state_backend {
 public:
  virtual ~state_backend() = default;
  virtual std::uint64_t revocation_epoch() const = 0;
  virtual bool capability_revoked(std::string_view capability_id) const = 0;
  virtual bool nonce_consumed(std::string_view nonce) const = 0;
  virtual std::uint64_t grant_use_count(std::string_view grant_id) const = 0;
  virtual std::string audit_head_sha256() const = 0;
  virtual void commit_authorization(std::string_view nonce, std::string_view grant_id,
                                    std::uint64_t use_count, std::string_view permit_id,
                                    std::string_view audit_record_canonical,
                                    std::string_view audit_record_sha256) = 0;
  virtual bool permit_exists(std::string_view permit_id) const = 0;
  virtual json::value owner_approval(std::string_view approval_id) const = 0;
  virtual void commit_owner_approval(std::string_view approval_id,
                                     std::string_view approval_canonical) = 0;
  virtual void commit_outcome(std::string_view permit_id, std::string_view outcome_canonical,
                              std::string_view outcome_sha256) = 0;
  virtual std::uint64_t service_generation() const = 0;
  virtual void begin_behavior_session(std::string_view session_id,
                                      std::string_view exact_run_binding_sha256) = 0;
  virtual void record_behavior_event(std::string_view session_id, std::string_view event,
                                     std::string_view evidence_sha256) = 0;
  virtual json::value behavior_session(std::string_view session_id) const = 0;
};

struct authority_config final {
  std::string service_instance_id;
  std::string policy_revision;
  std::string policy_snapshot_sha256;
  std::string grant_hmac_key_id;
  std::string owner_approval_hmac_key_id;
  std::string service_build_sha256;
  std::string runtime_build_sha256;
  std::string source_commit;
  std::string source_tree;
  std::int64_t max_request_bytes = 1024 * 1024;
  std::int64_t max_deadline_seconds = 120;
  std::int64_t permit_ttl_seconds = 90;
  std::map<std::string, json::value, std::less<>> profiles;
  std::map<std::string, json::value, std::less<>> capabilities;
  json::value::array current_account_roots;
  json::value::array active_overlays;
  bool behavior_evidence_enabled = false;
};

inline std::int64_t unix_seconds_now() {
  return std::chrono::duration_cast<std::chrono::seconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
}
inline std::string iso8601_utc(std::int64_t epoch_seconds) {
  const std::time_t raw = static_cast<std::time_t>(epoch_seconds);
  std::tm tm{};
#if defined(_WIN32)
  if (gmtime_s(&tm, &raw) != 0) throw std::runtime_error("time_conversion_failed");
#else
  if (gmtime_r(&raw, &tm) == nullptr) throw std::runtime_error("time_conversion_failed");
#endif
  std::ostringstream out; out << std::put_time(&tm, "%Y-%m-%dT%H:%M:%SZ"); return out.str();
}


inline std::string read_text_file(const std::filesystem::path& path, std::size_t limit = 16 * 1024 * 1024) {
  std::ifstream input(path, std::ios::binary);
  if (!input) throw std::runtime_error("authority_required_file_missing:" + path.string());
  input.seekg(0, std::ios::end);
  const auto size = input.tellg();
  if (size < 0 || static_cast<std::uint64_t>(size) > limit) throw std::runtime_error("authority_file_size_invalid:" + path.string());
  input.seekg(0, std::ios::beg);
  std::string value(static_cast<std::size_t>(size), '\0');
  input.read(value.data(), static_cast<std::streamsize>(value.size()));
  if (!input && !value.empty()) throw std::runtime_error("authority_file_read_failed:" + path.string());
  return value;
}

inline authority_config load_authority_config(const std::filesystem::path& path) {
  const auto root = json::parse(read_text_file(path));
  const auto& obj = root.as_object();
  if (json::required_string(obj, "schemaVersion") != "2.0.0") throw std::runtime_error("authority_config_schema_invalid");
  authority_config cfg;
  cfg.service_instance_id = json::required_string(obj, "serviceInstanceId");
  cfg.policy_revision = json::required_string(obj, "policyRevision");
  cfg.policy_snapshot_sha256 = json::required_string(obj, "policySnapshotSha256");
  cfg.grant_hmac_key_id = json::required_string(obj, "grantHmacKeyId");
  cfg.owner_approval_hmac_key_id = json::required_string(obj, "ownerApprovalHmacKeyId");
  cfg.service_build_sha256 = json::required_string(obj, "serviceBuildSha256");
  cfg.runtime_build_sha256 = json::required_string(obj, "runtimeBuildSha256");
  cfg.source_commit = json::required_string(obj, "sourceCommit");
  cfg.source_tree = json::required_string(obj, "sourceTree");
  if (!valid_identifier(cfg.service_instance_id) || !valid_identifier(cfg.policy_revision) ||
      !valid_hex64(cfg.policy_snapshot_sha256) || !valid_identifier(cfg.grant_hmac_key_id) ||
      !valid_identifier(cfg.owner_approval_hmac_key_id) || !valid_hex64(cfg.service_build_sha256) ||
      !valid_hex64(cfg.runtime_build_sha256) || cfg.source_commit.size() != 40 || cfg.source_tree.size() != 40) throw std::runtime_error("authority_config_identity_invalid");
  if (const auto* v = root.find("maxRequestBytes")) cfg.max_request_bytes = v->as_int();
  if (const auto* v = root.find("maxDeadlineSeconds")) cfg.max_deadline_seconds = v->as_int();
  if (const auto* v = root.find("permitTtlSeconds")) cfg.permit_ttl_seconds = v->as_int();
  if (const auto* v = root.find("behaviorEvidenceEnabled")) cfg.behavior_evidence_enabled = v->as_bool();
  if (cfg.max_request_bytes < 65536 || cfg.max_request_bytes > 16 * 1024 * 1024 ||
      cfg.max_deadline_seconds < 5 || cfg.max_deadline_seconds > 300 ||
      cfg.permit_ttl_seconds < 5 || cfg.permit_ttl_seconds > cfg.max_deadline_seconds)
    throw std::runtime_error("authority_config_limits_invalid");
  for (const auto& [id, value] : json::required_object(obj, "profiles")) {
    if (!valid_identifier(id) || !value.is_object()) throw std::runtime_error("authority_profile_invalid");
    cfg.profiles.emplace(id, value);
  }
  for (const auto& [id, value] : json::required_object(obj, "capabilities")) {
    if (!valid_identifier(id) || !value.is_object()) throw std::runtime_error("authority_capability_invalid");
    cfg.capabilities.emplace(id, value);
  }
  cfg.current_account_roots = json::required_array(obj, "currentAccountRoots");
  cfg.active_overlays = json::required_array(obj, "activeOverlays");
  if (cfg.current_account_roots.empty()) throw std::runtime_error("authority_current_account_roots_required");
  if (!cfg.profiles.contains("owner") || !cfg.profiles.contains("owner_unattended") || cfg.capabilities.empty())
    throw std::runtime_error("authority_policy_snapshot_incomplete");
  auto copy = root;
  copy.as_object().erase("policySnapshotSha256");
  if (sha256_hex(json::canonical(copy)) != cfg.policy_snapshot_sha256)
    throw std::runtime_error("authority_policy_snapshot_digest_mismatch");
  return cfg;
}

inline bool array_contains_string(const json::value& value, std::string_view needle) {
  if (!value.is_array()) return false;
  return std::any_of(value.as_array().begin(), value.as_array().end(), [needle](const json::value& item) {
    return item.is_string() && item.as_string() == needle;
  });
}

inline bool normalize_policy_path(std::string_view raw, std::vector<std::string>& components) {
  if (raw.empty() || raw.find('\0') != std::string_view::npos) return false;
  std::string value(raw);
  std::replace(value.begin(), value.end(), '\\', '/');
  const bool drive_absolute = value.size() >= 3 && std::isalpha(static_cast<unsigned char>(value[0])) &&
                              value[1] == ':' && value[2] == '/';
  const bool slash_absolute = !value.empty() && value.front() == '/';
  if (!drive_absolute && !slash_absolute) return false;
#ifdef _WIN32
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
#endif
  std::size_t start = drive_absolute ? 3 : 1;
  if (drive_absolute) components.push_back(value.substr(0, 2));
  while (start <= value.size()) {
    const auto end = value.find('/', start);
    const auto part = value.substr(start, end == std::string::npos ? std::string::npos : end - start);
    if (part == "..") return false;
    if (!part.empty() && part != ".") components.push_back(part);
    if (end == std::string::npos) break;
    start = end + 1;
  }
  return true;
}

inline bool path_within(std::string_view path, std::string_view root) {
  if (root == "*") return true;
  std::vector<std::string> target_components;
  std::vector<std::string> root_components;
  if (!normalize_policy_path(path, target_components) ||
      !normalize_policy_path(root, root_components) ||
      root_components.size() > target_components.size()) return false;
  return std::equal(root_components.begin(), root_components.end(), target_components.begin());
}

inline json::value::object require_binding(const json::value::object& policy_request) {
  const auto& binding = json::required_object(policy_request, "binding");
  json::value::object out;
  for (const auto* key : {"runId","taskId","actorId","toolId","accessProfileId","capabilityId"}) {
    const auto value = json::required_string(binding, key);
    if (!valid_identifier(value)) throw std::runtime_error(std::string("authority_binding_invalid:") + key);
    out.emplace(key, json::value(value));
  }
  return out;
}

inline json::value evaluate_policy(const authority_config& cfg, const json::value& policy_request,
                                           crypto_backend& crypto, std::int64_t now) {
  const auto& request = policy_request.as_object();
  if (json::required_string(request, "schemaVersion") != "2.0.0") throw std::runtime_error("policy_request_schema_invalid");
  const auto binding = require_binding(request);
  const auto profile_id = binding.at("accessProfileId").as_string();
  const auto capability_id = binding.at("capabilityId").as_string();
  if (profile_id != "owner" && profile_id != "owner_unattended") throw std::runtime_error("owner_profile_required");
  const auto profile_it = cfg.profiles.find(profile_id);
  const auto capability_it = cfg.capabilities.find(capability_id);
  if (profile_it == cfg.profiles.end() || capability_it == cfg.capabilities.end()) throw std::runtime_error("policy_unknown_capability_or_profile");
  const auto& profile = profile_it->second.as_object();
  const auto& capability = capability_it->second.as_object();
  if (!array_contains_string(profile_it->second.at("capabilities"), capability_id)) throw std::runtime_error("policy_capability_outside_profile");
  const auto& effect = json::required_object(request, "effect");
  const auto domain = json::required_string(effect, "domain");
  const auto action = json::required_string(effect, "action");
  const auto target = json::required_string(effect, "target");
  if (domain != json::required_string(capability, "domain") || !array_contains_string(capability_it->second.at("actions"), action))
    throw std::runtime_error("policy_effect_not_registered");

  const auto& approval = json::required_object(request, "approval");
  const bool approved = json::required_bool(approval, "approved");
  const auto approval_source = json::required_string(approval, "source");
  const auto approval_id = json::required_string(approval, "approvalId");
  if (!approved || (approval_source != "owner" && approval_source != "organization_policy") || !valid_identifier(approval_id))
    throw std::runtime_error("policy_trusted_owner_approval_required");
  const auto approval_expiry = json::required_int(approval, "expiresAtEpochSeconds");
  const auto approval_scope = approval.contains("approvalScope")
      ? json::required_string(approval, "approvalScope") : std::string("effect");
  const auto approval_lifetime = approval_scope == "owner-session" ? 86400 : 900;
  if ((approval_scope != "effect" && approval_scope != "owner-session") ||
      approval_expiry <= now || approval_expiry > now + approval_lifetime)
    throw std::runtime_error("policy_owner_approval_expired");
  json::value approval_unsigned = approval;
  auto& approval_unsigned_obj = approval_unsigned.as_object();
  const auto auth_it = approval_unsigned_obj.find("auth");
  if (auth_it == approval_unsigned_obj.end() || !auth_it->second.is_object()) throw std::runtime_error("policy_owner_approval_auth_missing");
  auto auth = auth_it->second.as_object();
  const auto mac = json::required_string(auth, "mac");
  const auto key_id = json::required_string(auth, "keyId");
  if (key_id != cfg.owner_approval_hmac_key_id || !valid_hex64(mac)) throw std::runtime_error("policy_owner_approval_auth_invalid");
  auth.erase("mac");
  approval_unsigned_obj["auth"] = json::value(auth);
  const auto expected_approval_mac = crypto.hmac_sha256_hex(kOwnerApprovalHmacPurpose, key_id, json::canonical(approval_unsigned));
  if (!constant_time_equal(mac, expected_approval_mac)) throw std::runtime_error("policy_owner_approval_integrity_mismatch");

  if (domain == "filesystem") {
    const auto& context = json::required_object(request, "context");
    const auto& roots = json::required_array(context, "currentAccountRoots");
    bool allowed = false;
    for (const auto& root : roots) if (root.is_string() && path_within(target, root.as_string())) { allowed = true; break; }
    if (!allowed) throw std::runtime_error("policy_path_outside_current_account");
  }
  if (profile_id == "owner_unattended" && (action == "elevate" || action == "interactive-consent"))
    throw std::runtime_error("policy_unattended_elevation_forbidden");

  std::set<std::string> denied;
  std::vector<std::string> narrowed_roots;
  if (const auto* overlays_value = policy_request.find("overlays")) {
    if (!overlays_value->is_array()) throw std::runtime_error("policy_overlays_invalid");
    for (const auto& overlay_value : overlays_value->as_array()) {
      const auto& overlay = overlay_value.as_object();
      const auto source = json::required_string(overlay, "source");
      if (source != "organization" && source != "project" && source != "user") throw std::runtime_error("policy_overlay_source_invalid");
      if (const auto* values = overlay_value.find("denyCapabilities")) for (const auto& item : values->as_array()) if (item.is_string()) denied.insert(item.as_string());
      if (const auto* values = overlay_value.find("narrowPathPrefixes")) for (const auto& item : values->as_array()) if (item.is_string()) narrowed_roots.push_back(item.as_string());
    }
  }
  if (denied.contains(capability_id)) throw std::runtime_error("policy_capability_denied_by_overlay");
  if (domain == "filesystem" && !narrowed_roots.empty()) {
    bool allowed = false; for (const auto& root : narrowed_roots) if (path_within(target, root)) { allowed = true; break; }
    if (!allowed) throw std::runtime_error("policy_path_outside_overlay_scope");
  }

  const auto& requested_budgets = json::required_object(request, "requestedBudgets");
  const auto& ceiling = json::required_object(profile, "budgetCeiling");
  json::value::object budgets;
  for (const auto* key : {"wallClockMs","maxOutputBytes","maxNetworkBytes","maxCostMicros","maxMutations"}) {
    const auto requested = json::required_int(requested_budgets, key);
    const auto maximum = json::required_int(ceiling, key);
    if (requested < 0 || maximum < 0 || requested > maximum) throw std::runtime_error(std::string("policy_budget_exceeds_profile:") + key);
    budgets.emplace(key, json::value(requested));
  }
  const auto normalized_request = json::canonical(policy_request);
  const auto decision_id = "policy-" + sha256_hex(normalized_request + "|" + cfg.policy_revision).substr(0, 32);
  return json::value(json::value::object{
      {"schemaVersion", json::value("2.0.0")}, {"decisionId", json::value(decision_id)}, {"status", json::value("allow")},
      {"reasonCodes", json::value(json::value::array{})}, {"effectiveProfileId", json::value(profile_id)},
      {"effectiveScope", json::value(json::value::object{{"domain",json::value(domain)},{"action",json::value(action)},{"target",json::value(target)}})},
      {"effectiveBudgets", json::value(budgets)}, {"binding", json::value(binding)},
      {"ownerApprovalId",json::value(approval_id)}, {"policyRequestSha256",json::value(sha256_hex(normalized_request))}});
}

class authority_core final {
 public:
  authority_core(authority_config config, crypto_backend& crypto, state_backend& state)
      : config_(std::move(config)), crypto_(crypto), state_(state) {}

  json::value handle(const json::value& request_value, const peer_identity& peer) {
    if (!peer.desktop_authenticated || peer.worker_principal) throw std::runtime_error("authority_desktop_peer_required");
    const auto& request = request_value.as_object();
    if (json::required_string(request, "schemaVersion") != "2.0.0") throw std::runtime_error("authority_request_schema_invalid");
    const auto operation = json::required_string(request, "operation");
    if (operation == kAuthorizeV2) return authorize(request_value, peer);
    if (operation == kRecordOwnerApprovalV2) return record_owner_approval(request_value, peer);
    if (operation == kRecordOutcomeV2) return record_outcome(request_value, peer);
    if (operation == kBeginBehaviorV2) return begin_behavior_session(request_value, peer);
    if (operation == kFinalizeBehaviorV2) return finalize_behavior_session(request_value, peer);
    if (operation == kDescribeV2) return describe(peer);
    throw std::runtime_error("authority_typed_operation_not_allowed");
  }

  void note_worker_denial(std::string_view behavior_session_id, const peer_identity& peer,
                          std::string_view worker_identity_sha256) {
    if (!config_.behavior_evidence_enabled || !valid_identifier(behavior_session_id) ||
        !peer.worker_principal || !valid_hex64(worker_identity_sha256))
      throw std::runtime_error("behavior_worker_denial_event_invalid");
    const auto peer_evidence = sha256_hex(peer.platform + "|" + peer.principal + "|" + peer.executable_sha256 + "|" +
                                          peer.code_identity + "|" + peer.session_identity + "|" + std::to_string(peer.pid));
    const auto denial_binding = sha256_hex(std::string(worker_identity_sha256) + "|" + peer_evidence + "|" +
                                           std::string(behavior_session_id));
    state_.record_behavior_event(behavior_session_id, "worker-identity-claimed", worker_identity_sha256);
    state_.record_behavior_event(behavior_session_id, "worker-principal-denied", peer_evidence);
    state_.record_behavior_event(behavior_session_id, "worker-identity-denial-bound", denial_binding);
  }

 private:
  authority_config config_; crypto_backend& crypto_; state_backend& state_;

  std::string behavior_session_id(const json::value::object& request) const {
    const auto* raw = request.contains("behaviorSessionId") ? &request.at("behaviorSessionId") : nullptr;
    if (raw == nullptr || !raw->is_string()) return {};
    const auto value = raw->as_string();
    if (!valid_identifier(value)) throw std::runtime_error("behavior_session_id_invalid");
    return value;
  }
  void behavior_event(const json::value::object& request, std::string_view event, std::string_view evidence) {
    const auto session = behavior_session_id(request);
    if (session.empty()) return;
    if (!config_.behavior_evidence_enabled) throw std::runtime_error("behavior_evidence_disabled");
    const auto snapshot = state_.behavior_session(session).as_object();
    if (state_.service_generation() > static_cast<std::uint64_t>(json::required_int(snapshot, "startGeneration")))
      state_.record_behavior_event(session, "service-restarted", sha256_hex(std::to_string(state_.service_generation())));
    state_.record_behavior_event(session, event, sha256_hex(evidence));
  }

  json::value begin_behavior_session(const json::value& request_value, const peer_identity& peer) {
    if (!config_.behavior_evidence_enabled) throw std::runtime_error("behavior_evidence_disabled");
    const auto& request = request_value.as_object();
    const auto session = json::required_string(request, "behaviorSessionId");
    const auto binding = json::required_string(request, "exactRunBindingSha256");
    if (!valid_identifier(session) || !valid_hex64(binding)) throw std::runtime_error("behavior_session_request_invalid");
    state_.begin_behavior_session(session, binding);
    state_.record_behavior_event(session, "desktop-authenticated",
      sha256_hex(peer.platform + "|" + peer.principal + "|" + peer.executable_sha256 + "|" + std::to_string(peer.pid)));
    return json::value(json::value::object{{"schemaVersion",json::value("2.0.0")},{"status",json::value("started")},
      {"operation",json::value(std::string(kBeginBehaviorV2))},{"behaviorSession",state_.behavior_session(session)}});
  }

  json::value finalize_behavior_session(const json::value& request_value, const peer_identity& peer) {
    if (!config_.behavior_evidence_enabled) throw std::runtime_error("behavior_evidence_disabled");
    const auto& request = request_value.as_object();
    const auto session = json::required_string(request, "behaviorSessionId");
    const auto binding = json::required_string(request, "exactRunBindingSha256");
    if (!valid_identifier(session) || !valid_hex64(binding)) throw std::runtime_error("behavior_session_finalize_invalid");
    auto session_value = state_.behavior_session(session);
    const auto& session_object = session_value.as_object();
    if (json::required_string(session_object, "exactRunBindingSha256") != binding)
      throw std::runtime_error("behavior_session_binding_mismatch");
    std::set<std::string> observed;
    std::map<std::string, std::string, std::less<>> event_evidence;
    for (const auto& row : json::required_array(session_object, "events")) {
      const auto& event = row.as_object();
      const auto name = json::required_string(event, "event");
      const auto evidence = json::required_string(event, "evidenceSha256");
      observed.insert(name);
      event_evidence.insert_or_assign(name, evidence);
    }
    const std::set<std::string> required{"desktop-authenticated","worker-identity-claimed","worker-principal-denied",
      "worker-identity-denial-bound","owner-approval-recorded","effect-authorized","effect-outcome-recorded",
      "request-replay-denied","service-restarted"};
    for (const auto& item : required) if (!observed.contains(item)) throw std::runtime_error("behavior_session_required_event_missing:" + item);
    json::value::object body{{"schemaVersion",json::value("2.0.0")},{"receiptType",json::value("p1a-service-behavior-v2")},
      {"serviceInstanceId",json::value(config_.service_instance_id)},{"sourceCommit",json::value(config_.source_commit)},
      {"sourceTree",json::value(config_.source_tree)},{"serviceBuildSha256",json::value(config_.service_build_sha256)},
      {"runtimeBuildSha256",json::value(config_.runtime_build_sha256)},{"exactRunBindingSha256",json::value(binding)},
      {"behaviorSessionId",json::value(session)},{"serviceGeneration",json::value(static_cast<std::int64_t>(state_.service_generation()))},
      {"policySnapshotSha256",json::value(config_.policy_snapshot_sha256)},{"revocationEpoch",json::value(static_cast<std::int64_t>(state_.revocation_epoch()))},
      {"auditHeadSha256",json::value(state_.audit_head_sha256())},{"behaviorSession",session_value},
      {"callerPrincipal",json::value(peer.principal)},{"callerExecutableSha256",json::value(peer.executable_sha256)},
      {"typedOperationsOnly",json::value(true)},{"arbitraryMessageSigningApi",json::value(false)},
      {"policyValidatedInsideService",json::value(true)},{"grantIssuedInsideService",json::value(true)},
      {"grantValidatedInsideService",json::value(true)},{"useConsumedInsideService",json::value(true)},
      {"revocationCheckedInsideService",json::value(true)},{"auditAppendedInsideService",json::value(true)},
      {"workerPrincipalDeniedInsideService",json::value(true)},{"workerIdentityDenialBoundInsideService",json::value(true)},
      {"workerIdentitySha256",json::value(event_evidence.at("worker-identity-claimed"))},
      {"workerDenialPeerEvidenceSha256",json::value(event_evidence.at("worker-principal-denied"))},
      {"workerIdentityDenialBindingSha256",json::value(event_evidence.at("worker-identity-denial-bound"))},
      {"replayAfterRestartDenied",json::value(true)},{"nonExportableKey",json::value(true)},
      {"completionEligible",json::value(true)}};
    const auto signature = crypto_.sign_effect_permit(json::canonical(json::value(body)));
    if (!signature.non_exportable || !signature.private_export_denied) throw std::runtime_error("behavior_key_attestation_invalid");
    body.emplace("signature",json::value(json::value::object{{"algorithm",json::value(signature.algorithm)},
      {"keyId",json::value(signature.key_id)},{"signatureBase64",json::value(signature.signature_base64)},
      {"publicKeySpkiBase64",json::value(signature.public_key_spki_base64)},{"provider",json::value(signature.provider)},
      {"providerAttestationSha256",json::value(signature.provider_attestation_sha256)},
      {"nonExportable",json::value(true)},{"privateExportDenied",json::value(true)}}));
    return json::value(json::value::object{{"schemaVersion",json::value("2.0.0")},{"status",json::value("passed")},
      {"operation",json::value(std::string(kFinalizeBehaviorV2))},{"behaviorReceipt",json::value(body)}});
  }

  json::value describe(const peer_identity& peer) {
    return json::value(json::value::object{
        {"schemaVersion",json::value("2.0.0")},{"status",json::value("ok")},{"operation",json::value(std::string(kDescribeV2))},
        {"serviceInstanceId",json::value(config_.service_instance_id)},{"policyRevision",json::value(config_.policy_revision)},
        {"policySnapshotSha256",json::value(config_.policy_snapshot_sha256)},{"revocationEpoch",json::value(static_cast<std::int64_t>(state_.revocation_epoch()))},
        {"auditHeadSha256",json::value(state_.audit_head_sha256())},{"callerPrincipal",json::value(peer.principal)},
        {"keyProvider",crypto_.public_description()},{"arbitraryMessageSigningApi",json::value(false)},
        {"typedOperationsOnly",json::value(true)}});
  }


  json::value record_owner_approval(const json::value& request_value, const peer_identity& peer) {
    const auto& request = request_value.as_object();
    const auto request_id = json::required_string(request, "requestId");
    const auto approval_id = json::required_string(request, "approvalId");
    const auto interaction_nonce = json::required_string(request, "interactionNonce");
    const auto interaction_type = json::required_string(request, "interactionType");
    const auto expires_at = json::required_int(request, "expiresAtEpochSeconds");
    const auto payload_sha = json::required_string(request, "payloadSha256");
    const auto ui_sha = json::required_string(request, "uiSurfaceSha256");
    const auto confirmation_sha = json::required_string(request, "confirmationTextSha256");
    const bool user_present = json::required_bool(request, "userPresent");
    const auto approval_scope = request.contains("approvalScope")
        ? json::required_string(request, "approvalScope") : std::string("effect");
    const auto approval_policy = request.contains("approvalPolicy")
        ? json::required_string(request, "approvalPolicy") : std::string("boundedSession");
    const auto owner_session_id = request.contains("ownerSessionId")
        ? json::required_string(request, "ownerSessionId") : std::string();
    const auto& binding_value = request.at("binding");
    const auto binding = require_binding(binding_value.as_object().contains("schemaVersion") ? request : json::value::object{{"binding",binding_value}});
    const auto now = unix_seconds_now();
    const bool session_scope = approval_scope == "owner-session";
    const auto max_approval_lifetime = session_scope ? 86400 : 900;
    if (!valid_identifier(request_id) || !valid_identifier(approval_id) || !valid_identifier(interaction_nonce) ||
        (approval_scope != "effect" && approval_scope != "owner-session") ||
        (approval_policy != "everyHighRiskEffect" && approval_policy != "destructiveOnly" && approval_policy != "boundedSession") ||
        (session_scope && (!valid_identifier(owner_session_id) || owner_session_id.empty())) ||
        (!session_scope && !owner_session_id.empty()) ||
        interaction_type != "native-owner-confirmation" || !user_present || !valid_hex64(payload_sha) ||
        !valid_hex64(ui_sha) || !valid_hex64(confirmation_sha) || expires_at <= now ||
        expires_at > now + max_approval_lifetime)
      throw std::runtime_error("owner_approval_request_invalid");
    const auto profile = binding.at("accessProfileId").as_string();
    if (profile != "owner" && profile != "owner_unattended") throw std::runtime_error("owner_approval_profile_invalid");
    const auto operation = json::required_string(request, "effectOperation");
    if (!valid_identifier(operation) || (session_scope && operation != "owner-session"))
      throw std::runtime_error("owner_approval_operation_invalid");
    json::value::object approval{{"schemaVersion",json::value("2.0.0")},{"approvalId",json::value(approval_id)},
      {"requestId",json::value(request_id)},{"approved",json::value(true)},{"source",json::value("owner")},
      {"binding",json::value(binding)},
      {"effectOperation",json::value(operation)},{"payloadSha256",json::value(payload_sha)},
      {"approvalScope",json::value(approval_scope)},{"approvalPolicy",json::value(approval_policy)},
      {"ownerSessionId",session_scope ? json::value(owner_session_id) : json::value(nullptr)},
      {"expiresAtEpochSeconds",json::value(expires_at)},{"interaction",json::value(json::value::object{
        {"type",json::value(interaction_type)},{"interactionNonce",json::value(interaction_nonce)},
        {"uiSurfaceSha256",json::value(ui_sha)},{"confirmationTextSha256",json::value(confirmation_sha)},
        {"desktopPrincipal",json::value(peer.principal)},{"desktopExecutableSha256",json::value(peer.executable_sha256)},
        {"desktopPid",json::value(static_cast<std::int64_t>(peer.pid))},{"userPresent",json::value(true)}})},
      {"auth",json::value(json::value::object{{"algorithm",json::value("hmac-sha256")},
        {"keyId",json::value(config_.owner_approval_hmac_key_id)},{"mac",json::value("")}})}};
    auto unsigned_approval = json::value(approval);
    unsigned_approval.as_object().at("auth").as_object().erase("mac");
    approval.at("auth").as_object().at("mac") = json::value(
      crypto_.hmac_sha256_hex(kOwnerApprovalHmacPurpose, config_.owner_approval_hmac_key_id,
                              json::canonical(unsigned_approval)));
    const auto canonical = json::canonical(json::value(approval));
    state_.commit_owner_approval(approval_id, canonical);
    behavior_event(request, "owner-approval-recorded", canonical);
    return json::value(json::value::object{{"schemaVersion",json::value("2.0.0")},{"status",json::value("recorded")},
      {"operation",json::value(std::string(kRecordOwnerApprovalV2))},{"approval",json::value(approval)},
      {"approvalSha256",json::value(sha256_hex(canonical))}});
  }

  json::value authorize(const json::value& request_value, const peer_identity& peer) {
    const auto& request = request_value.as_object();
    const auto request_id = json::required_string(request, "requestId");
    const auto request_nonce = json::required_string(request, "requestNonce");
    const auto worker_session = json::required_string(request, "workerSessionId");
    const auto channel_id = json::required_string(request, "channelId");
    const auto& worker_identity = request.at("workerIdentity");
    const auto& worker_identity_object = worker_identity.as_object();
    const auto worker_identity_session = json::required_string(worker_identity_object, "sessionId");
    const auto worker_identity_platform = json::required_string(worker_identity_object, "platform");
    const auto worker_principal_type = json::required_string(worker_identity_object, "principalType");
    const auto worker_start_token = json::required_string(worker_identity_object, "startToken");
    const auto worker_pid = json::required_int(worker_identity_object, "pid");
    const auto worker_launcher_sha = json::required_string(worker_identity_object, "launcherSha256");
    const auto worker_node_sha = json::required_string(worker_identity_object, "nodeSha256");
    const auto worker_host_sha = json::required_string(worker_identity_object, "hostScriptSha256");
    auto worker_identity_unsigned = worker_identity;
    worker_identity_unsigned.as_object().erase("identitySha256");
    const auto worker_identity_sha = sha256_hex(json::canonical(worker_identity_unsigned));
    const auto supplied_worker_identity_sha = json::required_string(worker_identity_object, "identitySha256");
    if (json::required_string(worker_identity_object, "schemaVersion") != "2.0.0" ||
        supplied_worker_identity_sha != worker_identity_sha ||
        worker_identity_session != worker_session || worker_pid <= 0 || worker_start_token.empty() ||
        !valid_hex64(worker_launcher_sha) || !valid_hex64(worker_node_sha) || !valid_hex64(worker_host_sha) ||
        !((worker_identity_platform == "linux" && worker_principal_type == "dedicated-uid") ||
          (worker_identity_platform == "windows" && worker_principal_type == "appcontainer") ||
          (worker_identity_platform == "macos" && worker_principal_type == "signed-app-sandbox-helper")))
      throw std::runtime_error("authority_worker_identity_invalid");
    if (config_.behavior_evidence_enabled) {
      const auto session = behavior_session_id(request);
      if (session.empty()) throw std::runtime_error("authority_worker_denial_session_required");
      const auto behavior = state_.behavior_session(session).as_object();
      std::map<std::string, std::string, std::less<>> evidence;
      for (const auto& row : json::required_array(behavior, "events")) {
        const auto& event = row.as_object();
        evidence.insert_or_assign(json::required_string(event, "event"),
                                  json::required_string(event, "evidenceSha256"));
      }
      for (const auto* required_event : {"worker-identity-claimed", "worker-principal-denied",
                                         "worker-identity-denial-bound"})
        if (!evidence.contains(required_event))
          throw std::runtime_error(std::string("authority_worker_denial_event_missing:") + required_event);
      if (evidence.at("worker-identity-claimed") != worker_identity_sha)
        throw std::runtime_error("authority_worker_identity_denial_mismatch");
      const auto expected_binding = sha256_hex(worker_identity_sha + "|" +
        evidence.at("worker-principal-denied") + "|" + session);
      if (evidence.at("worker-identity-denial-bound") != expected_binding)
        throw std::runtime_error("authority_worker_denial_binding_invalid");
    }
    const auto operation = json::required_string(request, "effectOperation");
    const auto payload_sha = json::required_string(request, "payloadSha256");
    const auto& payload = request.at("payload");
    const auto deadline = json::required_int(request, "deadlineEpochSeconds");
    const auto expected_epoch = static_cast<std::uint64_t>(json::required_int(request, "expectedRevocationEpoch"));
    if (!valid_identifier(request_id) || !valid_identifier(request_nonce) || !valid_identifier(worker_session) ||
        !valid_identifier(channel_id) || !valid_identifier(operation) || !valid_hex64(payload_sha) ||
        sha256_hex(json::canonical(payload)) != payload_sha)
      throw std::runtime_error("authority_effect_request_identity_invalid");
    const auto now = unix_seconds_now();
    if (deadline <= now || deadline > now + config_.max_deadline_seconds) throw std::runtime_error("authority_effect_deadline_invalid");
    if (expected_epoch != state_.revocation_epoch()) throw std::runtime_error("authority_revocation_epoch_stale");
    if (state_.nonce_consumed(request_nonce)) {
      behavior_event(request, "request-replay-denied", request_nonce);
      throw std::runtime_error("authority_request_replay_detected");
    }
    const auto owner_approval_id = json::required_string(request, "ownerApprovalId");
    if (!valid_identifier(owner_approval_id)) throw std::runtime_error("authority_owner_approval_id_invalid");
    const auto approval = state_.owner_approval(owner_approval_id);
    const auto& approval_object = approval.as_object();
    if (json::required_string(approval_object, "schemaVersion") != "2.0.0" ||
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
    }
    const auto approval_source = json::required_string(approval_object, "source");
    if (approval_source == "owner") {
      const auto& interaction = json::required_object(approval_object, "interaction");
      if (!json::required_bool(interaction, "userPresent") ||
          json::required_string(interaction, "desktopPrincipal") != peer.principal ||
          json::required_string(interaction, "desktopExecutableSha256") != peer.executable_sha256)
        throw std::runtime_error("authority_owner_approval_peer_mismatch");
    }
    const auto approval_digest = sha256_hex(json::canonical(approval));
    json::value::object policy_request_obj{
      {"schemaVersion", json::value("2.0.0")},
      {"requestId", json::value(request_id)},
      {"binding", request.at("binding")},
      {"effect", request.at("policyEffect")},
      {"context", json::value(json::value::object{{"currentAccountRoots",json::value(config_.current_account_roots)}})},
      {"requestedBudgets", request.at("requestedBudgets")},
      {"overlays", json::value(config_.active_overlays)},
      {"approval", approval},
      {"explicitWidening", json::value(json::value::object{})}};
    const auto policy_request = json::value(policy_request_obj);
    const auto decision_obj = evaluate_policy(config_, policy_request, crypto_, now);
    const auto& decision = decision_obj.as_object();
    auto binding = json::required_object(decision, "binding");
    binding.emplace("operation", json::value(operation));
    const auto capability_id = json::required_string(binding, "capabilityId");
    if (state_.capability_revoked(capability_id)) throw std::runtime_error("authority_capability_revoked");

    const auto grant_id = "grant-" + sha256_hex(config_.service_instance_id + "|" + owner_approval_id + "|" +
      approval_digest + "|" + request_id).substr(0, 32);
    const auto grant_nonce = "nonce-" + sha256_hex(grant_id + "|" + approval_digest).substr(0, 32);
    const auto grant_expiry = std::min<std::int64_t>(deadline, now + config_.permit_ttl_seconds);
    json::value::object grant{
      {"schemaVersion",json::value("2.0.0")},{"grantId",json::value(grant_id)},
      {"issuer",json::value(json::value::object{{"actorId",json::value("desktop_host")},{"authority",json::value("p1-isolated-authority-service-v2")},{"serviceInstanceId",json::value(config_.service_instance_id)}})},
      {"binding",json::value(binding)},{"scope",decision.at("effectiveScope")},{"budgets",decision.at("effectiveBudgets")},
      {"validity",json::value(json::value::object{{"issuedAt",json::value(iso8601_utc(now))},{"notBefore",json::value(iso8601_utc(now))},{"expiresAt",json::value(iso8601_utc(grant_expiry))},{"maxUses",json::value(1)}})},
      {"nonce",json::value(grant_nonce)},{"policyDecisionId",decision.at("decisionId")},{"policyDecisionSha256",json::value(sha256_hex(json::canonical(decision_obj)))},
      {"revocationEpoch",json::value(static_cast<std::int64_t>(expected_epoch))},
      {"auth",json::value(json::value::object{{"algorithm",json::value("hmac-sha256")},{"keyId",json::value(config_.grant_hmac_key_id)},{"mac",json::value("")}})} };
    auto unsigned_grant = json::value(grant);
    auto& unsigned_auth = unsigned_grant.as_object().at("auth").as_object();
    unsigned_auth.erase("mac");
    const auto grant_mac = crypto_.hmac_sha256_hex(kCapabilityGrantHmacPurpose, config_.grant_hmac_key_id, json::canonical(unsigned_grant));
    grant.at("auth").as_object().at("mac") = json::value(grant_mac);
    auto verify_copy = json::value(grant); auto& verify_auth = verify_copy.as_object().at("auth").as_object(); const auto observed_mac = json::required_string(verify_auth,"mac"); verify_auth.erase("mac");
    if (!constant_time_equal(observed_mac, crypto_.hmac_sha256_hex(kCapabilityGrantHmacPurpose, config_.grant_hmac_key_id, json::canonical(verify_copy))))
      throw std::runtime_error("authority_grant_self_validation_failed");
    const auto current_use = state_.grant_use_count(grant_id);
    if (current_use >= 1) throw std::runtime_error("authority_grant_exhausted");

    const auto permit_id = "permit-" + sha256_hex(grant_id + "|" + request_id + "|" + std::to_string(current_use + 1)).substr(0, 32);
    json::value::object consumption{
      {"schemaVersion",json::value("1.0.0")},{"grantId",json::value(grant_id)},{"requestId",json::value(request_id)},
      {"useNumber",json::value(static_cast<std::int64_t>(current_use+1))},{"previousUseNumber",json::value(static_cast<std::int64_t>(current_use))},
      {"stateVersion",json::value(static_cast<std::int64_t>(current_use+1))},{"revocationEpoch",json::value(static_cast<std::int64_t>(expected_epoch))},
      {"consumedAt",json::value(iso8601_utc(now))},
      {"auth",json::value(json::value::object{{"algorithm",json::value("hmac-sha256")},{"keyId",json::value(config_.grant_hmac_key_id)},{"mac",json::value("")}})}};
    auto unsigned_consumption=json::value(consumption);unsigned_consumption.as_object().at("auth").as_object().erase("mac");
    consumption.at("auth").as_object().at("mac")=json::value(crypto_.hmac_sha256_hex(kGrantConsumptionHmacPurpose,config_.grant_hmac_key_id,json::canonical(unsigned_consumption)));
    const auto decision_digest=sha256_hex(json::canonical(decision_obj));
    const auto grant_value=json::value(grant);const auto grant_digest=sha256_hex(json::canonical(grant_value));
    const auto scope_digest=sha256_hex(json::canonical(grant.at("scope")));
    json::value::object ipc{{"schemaVersion",json::value("2.0.0")},{"peerId",json::value("desktop-host")},{"requestId",json::value(request_id)},{"channelId",json::value(channel_id)},{"workerIdentitySha256",json::value(worker_identity_sha)},{"workerCanIssue",json::value(false)},{"symmetricKeyMaterialTransferred",json::value(false)}};
    json::value::object authority{{"authorityKind",json::value("p1-isolated-authority-service-v2")},{"sharedP1ControlPlane",json::value(true)},{"p2CanIssueGrants",json::value(false)},{"workerCanIssue",json::value(false)},{"osEnforcedIsolation",json::value(true)},{"workerDeniedByOs",json::value(true)},{"workerIdentitySha256",json::value(worker_identity_sha)},{"workerIdentity",worker_identity},{"instanceId",json::value(config_.service_instance_id)},{"callerPrincipal",json::value(peer.principal)},{"callerExecutableSha256",json::value(peer.executable_sha256)},{"callerPid",json::value(static_cast<std::int64_t>(peer.pid))}};
    json::value::object authorization=binding;
    authorization.insert({"grantId",json::value(grant_id)});authorization.insert({"grantDigest",json::value(grant_digest)});
    authorization.insert({"policyDecisionId",decision.at("decisionId")});authorization.insert({"policyDecisionDigest",json::value(decision_digest)});
    authorization.insert({"scopeDigest",json::value(scope_digest)});authorization.insert({"notBefore",json::value(iso8601_utc(now))});authorization.insert({"expiresAt",json::value(iso8601_utc(grant_expiry))});
    authorization.insert({"useNumber",json::value(static_cast<std::int64_t>(current_use+1))});authorization.insert({"maxUses",json::value(1)});authorization.insert({"revocationEpoch",json::value(static_cast<std::int64_t>(expected_epoch))});
    authorization.insert({"consumptionReceipt",json::value(consumption)});authorization.insert({"capabilityGrant",grant_value});authorization.insert({"policyDecision",decision_obj});authorization.insert({"authenticatedIpc",json::value(ipc)});authorization.insert({"workerIdentity",worker_identity});authorization.insert({"workerIdentitySha256",json::value(worker_identity_sha)});authorization.insert({"authority",json::value(authority)});
    const auto authorization_pre_audit=json::value(authorization);
    const auto audit_record = json::value(json::value::object{{"schemaVersion",json::value("2.0.0")},{"event",json::value("effect-authorized")},{"permitId",json::value(permit_id)},{"requestId",json::value(request_id)},{"grantId",json::value(grant_id)},{"policyDecisionId",decision.at("decisionId")},{"useNumber",json::value(static_cast<std::int64_t>(current_use+1))},{"revocationEpoch",json::value(static_cast<std::int64_t>(expected_epoch))},{"workerIdentitySha256",json::value(worker_identity_sha)},{"predecessorSha256",json::value(state_.audit_head_sha256())},{"authorizationSha256",json::value(sha256_hex(json::canonical(authorization_pre_audit)))}});
    const auto audit_canonical=json::canonical(audit_record);const auto audit_sha=sha256_hex(audit_canonical);const auto audit_id="audit-"+audit_sha.substr(0,32);
    authorization.insert({"auditCheckpoint",json::value(json::value::object{{"id",json::value(audit_id)},{"digest",json::value(audit_sha)},{"predecessorSha256",json::value(state_.audit_head_sha256())}})});
    const auto authorization_value=json::value(authorization);const auto authorization_sha=sha256_hex(json::canonical(authorization_value));
    json::value::object permit{{"schemaVersion",json::value("2.0.0")},{"permitType",json::value("p1a-one-use-effect-permit-v2")},{"permitId",json::value(permit_id)},{"workerSessionId",json::value(worker_session)},{"channelId",json::value(channel_id)},{"workerIdentitySha256",json::value(worker_identity_sha)},{"peerId",json::value("desktop-host")},{"requestId",json::value(request_id)},{"operation",json::value(operation)},{"binding",json::value(binding)},{"authorizationSha256",json::value(authorization_sha)},{"payloadSha256",json::value(payload_sha)},{"grantId",json::value(grant_id)},{"grantDigest",json::value(grant_digest)},{"policyDecisionId",decision.at("decisionId")},{"policyDecisionDigest",json::value(decision_digest)},{"scopeDigest",json::value(scope_digest)},{"consumptionReceiptSha256",json::value(sha256_hex(json::canonical(json::value(consumption))))},{"useNumber",json::value(static_cast<std::int64_t>(current_use+1))},{"maxUses",json::value(1)},{"revocationEpoch",json::value(static_cast<std::int64_t>(expected_epoch))},{"authoritativeStateVersion",json::value(static_cast<std::int64_t>(current_use+1))},{"auditCheckpointId",json::value(audit_id)},{"auditCheckpointSha256",json::value(audit_sha)},{"sharedAuthorityInstanceId",json::value(config_.service_instance_id)},{"authorityImplementationSha256",json::value(config_.service_build_sha256)},{"runtimeBuildSha256",json::value(config_.runtime_build_sha256)},{"sourceCommit",json::value(config_.source_commit)},{"sourceTree",json::value(config_.source_tree)},{"issuedAt",json::value(iso8601_utc(now))},{"notBefore",json::value(iso8601_utc(now))},{"expiresAt",json::value(iso8601_utc(grant_expiry))},{"algorithm",json::value("ecdsa-p256-sha256")},{"signerKeyId",json::value("")}};
    auto unsigned_permit=json::value(permit);const auto signature=crypto_.sign_effect_permit(json::canonical(unsigned_permit));permit.at("signerKeyId")=json::value(signature.key_id);unsigned_permit=json::value(permit);const auto canonical_permit=json::canonical(unsigned_permit);const auto final_signature=crypto_.sign_effect_permit(canonical_permit);permit.insert({"signatureBase64",json::value(final_signature.signature_base64)});
    if(!final_signature.non_exportable||!final_signature.private_export_denied)throw std::runtime_error("authority_non_exportable_key_attestation_required");
    state_.commit_authorization(request_nonce,grant_id,current_use+1,permit_id,audit_canonical,audit_sha);
    behavior_event(request, "effect-authorized", permit_id + "|" + audit_sha);
    json::value::object envelope{{"schemaVersion",json::value("3.0.0")},{"requestId",json::value(request_id)},{"deadline",json::value(iso8601_utc(grant_expiry))},{"authorization",authorization_value},{"effectPermit",json::value(permit)},{"payload",payload}};
    return json::value(json::value::object{{"schemaVersion",json::value("2.0.0")},{"status",json::value("authorized")},{"operation",json::value(std::string(kAuthorizeV2))},{"envelope",json::value(envelope)},{"policyDecision",decision_obj},{"capabilityGrant",grant_value},{"authorityObservation",json::value(json::value::object{{"authorityType",json::value("p1-isolated-authority-service-v2")},{"typedOperation",json::value(std::string(kAuthorizeV2))},{"policyValidatedInsideService",json::value(true)},{"grantIssuedInsideService",json::value(true)},{"grantValidatedInsideService",json::value(true)},{"useConsumedInsideService",json::value(true)},{"revocationCheckedInsideService",json::value(true)},{"auditAppendedInsideService",json::value(true)},{"callerAuthenticatedByOs",json::value(true)},{"workerDeniedByOs",json::value(true)},{"nonExportableSigningKey",json::value(true)},{"keyProvider",json::value(final_signature.provider)},{"keyProviderAttestationSha256",json::value(final_signature.provider_attestation_sha256)}})},{"workerVerifierBootstrap",json::value(json::value::object{{"verificationMode",json::value("ecdsa-p256-public-only")},{"algorithm",json::value(final_signature.algorithm)},{"keyId",json::value(final_signature.key_id)},{"publicKeySpkiBase64",json::value(final_signature.public_key_spki_base64)},{"workerCanIssue",json::value(false)},{"privateSigningMaterialPresent",json::value(false)},{"symmetricSigningMaterialPresent",json::value(false)}})}});
  }

  json::value record_outcome(const json::value& request_value, const peer_identity& peer) {
    const auto& request = request_value.as_object();
    const auto permit_id = json::required_string(request,"permitId"); const auto request_id=json::required_string(request,"requestId");
    const auto status=json::required_string(request,"status"); const auto receipt_sha=json::required_string(request,"receiptSha256");
    if(!valid_identifier(permit_id)||!valid_identifier(request_id)||!valid_identifier(status)||!valid_hex64(receipt_sha)||!state_.permit_exists(permit_id))
      throw std::runtime_error("authority_outcome_invalid");
    const auto outcome=json::value(json::value::object{{"schemaVersion",json::value("2.0.0")},{"event",json::value("effect-outcome")},{"permitId",json::value(permit_id)},{"requestId",json::value(request_id)},{"status",json::value(status)},{"receiptSha256",json::value(receipt_sha)},{"peerPrincipal",json::value(peer.principal)},{"predecessorSha256",json::value(state_.audit_head_sha256())}});
    const auto canonical=json::canonical(outcome);const auto digest=sha256_hex(canonical);state_.commit_outcome(permit_id,canonical,digest);
    behavior_event(request, "effect-outcome-recorded", permit_id + "|" + digest);
    return json::value(json::value::object{{"schemaVersion",json::value("2.0.0")},{"status",json::value("recorded")},{"permitId",json::value(permit_id)},{"auditRecordSha256",json::value(digest)}});
  }
};

inline json::value denied_response(std::string_view code) {
  return json::value(json::value::object{{"schemaVersion",json::value("2.0.0")},{"status",json::value("denied")},{"errorCode",json::value(std::string(code))}});
}

}  // namespace kristin::p1a
