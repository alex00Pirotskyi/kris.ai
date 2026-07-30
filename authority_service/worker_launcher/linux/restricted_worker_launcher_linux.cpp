#include "../../native/common/sha256_portable.hpp"
#include "../../native/common/validation.hpp"
#include "../../native/common/strict_json.hpp"

#include <signal.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sched.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <grp.h>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace kp = kristin::p1a;
namespace j = kristin::p1a::json;

namespace {

std::string read_file(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  if (!input) throw std::runtime_error("worker_policy_open_failed");
  return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}

std::string hash_file(const std::filesystem::path& path) {
  return kp::sha256_hex(read_file(path));
}

void require_secure_root_file(const std::filesystem::path& path, bool executable = false) {
  struct stat st {};
  if (::lstat(path.c_str(), &st) != 0 || !S_ISREG(st.st_mode) || S_ISLNK(st.st_mode) ||
      st.st_uid != 0 || (st.st_mode & (S_IWGRP | S_IWOTH)) != 0 ||
      (executable && (st.st_mode & S_IXUSR) == 0)) {
    throw std::runtime_error("worker_policy_file_security_invalid:" + path.string());
  }
}


void require_secure_invoker_policy(const std::filesystem::path& path, uid_t invoker_uid) {
  struct stat st {};
  if (::lstat(path.c_str(), &st) != 0 || !S_ISREG(st.st_mode) || S_ISLNK(st.st_mode) ||
      (st.st_uid != invoker_uid && !(invoker_uid == 0 && st.st_uid == 0)) ||
      (st.st_mode & (S_IWGRP | S_IWOTH | S_IRGRP | S_IROTH)) != 0) {
    throw std::runtime_error("worker_policy_file_security_invalid:" + path.string());
  }
}


void require_secure_invoker_runtime_file(const std::filesystem::path& path, uid_t invoker_uid,
                                         bool executable = false) {
  struct stat st {};
  if (::lstat(path.c_str(), &st) != 0 || !S_ISREG(st.st_mode) || S_ISLNK(st.st_mode) ||
      (st.st_uid != invoker_uid && st.st_uid != 0) ||
      (st.st_mode & (S_IWGRP | S_IWOTH)) != 0 ||
      (executable && (st.st_mode & S_IXUSR) == 0)) {
    throw std::runtime_error("worker_runtime_file_security_invalid:" + path.string());
  }
}

std::string process_start_token() {
  std::ifstream input("/proc/self/stat");
  std::string line;
  std::getline(input, line);
  const auto close = line.rfind(')');
  if (close == std::string::npos) throw std::runtime_error("worker_start_token_unavailable");
  std::istringstream fields(line.substr(close + 2));
  std::string field;
  for (int index = 3; index <= 22; ++index) {
    if (!(fields >> field)) throw std::runtime_error("worker_start_token_unavailable");
  }
  return field;
}

void send_all(int fd, const void* data, std::size_t size) {
  auto* cursor = static_cast<const char*>(data);
  while (size != 0) {
    const auto written = ::send(fd, cursor, size, MSG_NOSIGNAL);
    if (written < 0) {
      if (errno == EINTR) continue;
      throw std::runtime_error("worker_probe_send_failed");
    }
    cursor += written;
    size -= static_cast<std::size_t>(written);
  }
}

void receive_all(int fd, void* data, std::size_t size) {
  auto* cursor = static_cast<char*>(data);
  while (size != 0) {
    const auto received = ::recv(fd, cursor, size, 0);
    if (received <= 0) {
      if (received < 0 && errno == EINTR) continue;
      throw std::runtime_error("worker_probe_reply_failed");
    }
    cursor += received;
    size -= static_cast<std::size_t>(received);
  }
}

std::string authority_denial_probe(const std::string& socket_path, const std::string& behavior_session_id) {
  const int raw = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (raw < 0) throw std::runtime_error("worker_probe_socket_failed");
  struct socket_guard final {
    int fd;
    ~socket_guard() { if (fd >= 0) ::close(fd); }
  } guard{raw};

  sockaddr_un address {};
  address.sun_family = AF_UNIX;
  if (socket_path.size() >= sizeof(address.sun_path)) throw std::runtime_error("worker_probe_address_invalid");
  std::memcpy(address.sun_path, socket_path.c_str(), socket_path.size() + 1);
  if (::connect(raw, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
    throw std::runtime_error("worker_probe_transport_unavailable:" + std::string(std::strerror(errno)));
  }

  const auto request = j::canonical(j::value(j::value::object{
      {"schemaVersion", j::value("2.0.0")},
      {"operation", j::value("describe-authority-v2")},
      {"behaviorSessionId", j::value(behavior_session_id)},
  }));
  if (request.size() > 65536) throw std::runtime_error("worker_probe_request_too_large");
  const std::array<unsigned char, 4> header{
      static_cast<unsigned char>((request.size() >> 24) & 0xff),
      static_cast<unsigned char>((request.size() >> 16) & 0xff),
      static_cast<unsigned char>((request.size() >> 8) & 0xff),
      static_cast<unsigned char>(request.size() & 0xff),
  };
  send_all(raw, header.data(), header.size());
  send_all(raw, request.data(), request.size());

  std::array<unsigned char, 4> reply_header{};
  receive_all(raw, reply_header.data(), reply_header.size());
  const std::uint32_t reply_size = (std::uint32_t(reply_header[0]) << 24) |
                                   (std::uint32_t(reply_header[1]) << 16) |
                                   (std::uint32_t(reply_header[2]) << 8) |
                                   std::uint32_t(reply_header[3]);
  if (reply_size == 0 || reply_size > 65536) throw std::runtime_error("worker_probe_reply_size_invalid");
  std::string body(reply_size, '\0');
  receive_all(raw, body.data(), body.size());
  const auto response = j::parse(body);
  const auto& object = response.as_object();
  if (j::required_string(object, "status") != "denied") throw std::runtime_error("worker_probe_not_denied");
  const auto error_code = j::required_string(object, "errorCode");
  if (error_code != "worker_principal_denied") throw std::runtime_error("worker_probe_wrong_denial:" + error_code);
  return error_code;
}

}  // namespace

int main(int argc, char** argv) {
  try {
    if (argc == 2 && std::string(argv[1]) == "--source-self-test") {
      std::cout << "{\"status\":\"passed\",\"platform\":\"linux\","
                   "\"restrictedPrincipal\":\"dedicated-uid\",\"completionEligible\":false}\n";
      return 0;
    }

    std::filesystem::path policy_path;
    std::filesystem::path principal_config_path = "/opt/kristin/p1a/config/worker-principal.json";
    std::string session_id;
    for (int index = 1; index < argc; ++index) {
      const std::string argument = argv[index];
      auto take = [&]() -> std::string {
        if (++index >= argc) throw std::runtime_error("argument_value_missing");
        return argv[index];
      };
      if (argument == "--policy") policy_path = take();
      else if (argument == "--session") session_id = take();
      else if (argument == "--principal-config") {
        if (::getuid() != 0) throw std::runtime_error("worker_principal_config_override_forbidden");
        principal_config_path = take();
      }
      else throw std::runtime_error("unknown_argument:" + argument);
    }

    const auto invoker_uid = ::getuid();
    if (::geteuid() != 0 || policy_path.empty() || !kp::valid_identifier(session_id)) {
      throw std::runtime_error("worker_launcher_setuid_policy_session_required");
    }
    require_secure_invoker_policy(policy_path, invoker_uid);
    require_secure_root_file(principal_config_path);
    const auto parsed = j::parse(read_file(policy_path));
    const auto& policy = parsed.as_object();
    if (j::required_string(policy, "schemaVersion") != "2.0.0" ||
        j::required_string(policy, "platform") != "linux") {
      throw std::runtime_error("worker_policy_identity_invalid");
    }

    const auto node_path = std::filesystem::path(j::required_string(policy, "nodeExecutable"));
    const auto host_path = std::filesystem::path(j::required_string(policy, "hostScript"));
    const auto working_directory = std::filesystem::path(j::required_string(policy, "workingDirectory"));
    const auto requested_authority_address = j::required_string(policy, "authorityAddress");
    const auto principal_parsed = j::parse(read_file(principal_config_path));
    const auto& principal = principal_parsed.as_object();
    if (j::required_string(principal, "schemaVersion") != "1.0.0") {
      throw std::runtime_error("worker_principal_config_identity_invalid");
    }
    const auto worker_uid = static_cast<uid_t>(j::required_int(principal, "workerUid"));
    const auto worker_gid = static_cast<gid_t>(j::required_int(principal, "workerGid"));
    const auto authority_address = j::required_string(principal, "authorityAddress");
    if (worker_uid == 0 || worker_gid == 0 || worker_uid == invoker_uid ||
        authority_address != requested_authority_address) {
      throw std::runtime_error("worker_identity_or_authority_invalid");
    }

    require_secure_invoker_runtime_file(node_path, invoker_uid, true);
    require_secure_invoker_runtime_file(host_path, invoker_uid);
    if (hash_file(node_path) != j::required_string(policy, "nodeSha256") ||
        hash_file(host_path) != j::required_string(policy, "hostScriptSha256")) {
      throw std::runtime_error("worker_binary_digest_mismatch");
    }

    std::array<char, 4096> self_path{};
    const auto self_size = ::readlink("/proc/self/exe", self_path.data(), self_path.size() - 1);
    if (self_size <= 0) throw std::runtime_error("worker_launcher_identity_unavailable");
    self_path[static_cast<std::size_t>(self_size)] = '\0';
    const auto launcher_sha256 = hash_file(self_path.data());
    if (launcher_sha256 != j::required_string(policy, "launcherSha256")) {
      throw std::runtime_error("worker_launcher_digest_mismatch");
    }
    if (launcher_sha256 != j::required_string(principal, "launcherSha256")) {
      throw std::runtime_error("worker_principal_launcher_digest_mismatch");
    }
    if (!std::filesystem::is_directory(working_directory)) throw std::runtime_error("worker_cwd_missing");

    if (::setgroups(0, nullptr) != 0 ||
        ::unshare(CLONE_NEWNS | CLONE_NEWIPC | CLONE_NEWUTS) != 0 ||
        ::mount(nullptr, "/", nullptr, MS_REC | MS_PRIVATE, nullptr) != 0 ||
        ::setresgid(worker_gid, worker_gid, worker_gid) != 0 ||
        ::setresuid(worker_uid, worker_uid, worker_uid) != 0 ||
        ::prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0 ||
        ::prctl(PR_SET_PDEATHSIG, SIGKILL) != 0) {
      throw std::runtime_error("worker_identity_transition_failed:" + std::string(std::strerror(errno)));
    }
    if (::chdir(working_directory.c_str()) != 0) throw std::runtime_error("worker_cwd_failed");

    const auto denial_code = authority_denial_probe(authority_address, session_id);
    const auto identity = j::value(j::value::object{
        {"type", j::value("launcher.identity")},
        {"schemaVersion", j::value("2.0.0")},
        {"platform", j::value("linux")},
        {"principalType", j::value("dedicated-uid")},
        {"sessionId", j::value(session_id)},
        {"pid", j::value(static_cast<std::int64_t>(::getpid()))},
        {"startToken", j::value(process_start_token())},
        {"workerUid", j::value(static_cast<std::int64_t>(::getuid()))},
        {"workerGid", j::value(static_cast<std::int64_t>(::getgid()))},
        {"noNewPrivileges", j::value(true)},
        {"namespaceIsolation", j::value(true)},
        {"authorityConnectionDenied", j::value(true)},
        {"authorityDenialCode", j::value(denial_code)},
        {"launcherSha256", j::value(launcher_sha256)},
        {"nodeSha256", j::value(hash_file(node_path))},
        {"hostScriptSha256", j::value(hash_file(host_path))},
    });
    std::cout << j::canonical(identity) << '\n' << std::flush;

    const std::string session_environment = "KRISTIN_WORKER_SESSION_ID=" + session_id;
    const std::string restricted_environment = "KRISTIN_RESTRICTED_WORKER=1";
    const std::string path_environment = "PATH=/usr/bin:/bin";
    const std::string home_environment = "HOME=/nonexistent";
    const std::string lang_environment = "LANG=C.UTF-8";
    std::vector<char*> environment{
        const_cast<char*>(session_environment.c_str()),
        const_cast<char*>(restricted_environment.c_str()),
        const_cast<char*>(path_environment.c_str()),
        const_cast<char*>(home_environment.c_str()),
        const_cast<char*>(lang_environment.c_str()),
        nullptr,
    };
    const std::string node = node_path.string();
    const std::string host = host_path.string();
    std::vector<char*> arguments{
        const_cast<char*>(node.c_str()),
        const_cast<char*>(host.c_str()),
        nullptr,
    };
    ::execve(node.c_str(), arguments.data(), environment.data());
    throw std::runtime_error("worker_exec_failed:" + std::string(std::strerror(errno)));
  } catch (const std::exception& error) {
    std::cerr << "P1A Linux worker launcher fatal: " << error.what() << '\n';
    return 1;
  }
}
