#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <libproc.h>
#include <mach-o/dyld.h>
#include <sandbox.h>
#include <sys/types.h>
#include <unistd.h>

#include "../../native/common/sha256_portable.hpp"
#include "../../native/common/validation.hpp"
#include "../../native/common/strict_json.hpp"

#include <array>
#include <filesystem>
#include <fstream>
#include <iostream>
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
std::string hash_file(const std::filesystem::path& path) { return kp::sha256_hex(read_file(path)); }
std::filesystem::path executable_path() {
  std::array<char, PATH_MAX> buffer{}; uint32_t size = static_cast<uint32_t>(buffer.size());
  if (_NSGetExecutablePath(buffer.data(), &size) != 0) throw std::runtime_error("launcher_identity_missing");
  return std::filesystem::weakly_canonical(buffer.data());
}
std::string own_cdhash() {
  SecCodeRef code = nullptr;
  if (SecCodeCopySelf(kSecCSDefaultFlags, &code) != errSecSuccess) throw std::runtime_error("worker_code_identity_missing");
  CFDictionaryRef info = nullptr;
  if (SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info) != errSecSuccess) {
    CFRelease(code); throw std::runtime_error("worker_signing_info_missing");
  }
  CFDataRef cd = static_cast<CFDataRef>(CFDictionaryGetValue(info, kSecCodeInfoUnique));
  const std::string result = cd ? kp::hex_bytes(CFDataGetBytePtr(cd), static_cast<std::size_t>(CFDataGetLength(cd))) : "";
  CFRelease(info); CFRelease(code);
  if (result.empty()) throw std::runtime_error("worker_cdhash_missing");
  return result;
}
void require_own_requirement(const std::string& requirement_text) {
  SecCodeRef code = nullptr; SecRequirementRef requirement = nullptr;
  if (SecCodeCopySelf(kSecCSDefaultFlags, &code) != errSecSuccess) throw std::runtime_error("worker_code_identity_missing");
  CFStringRef text = CFStringCreateWithCString(kCFAllocatorDefault, requirement_text.c_str(), kCFStringEncodingUTF8);
  const OSStatus parsed = SecRequirementCreateWithString(text, kSecCSDefaultFlags, &requirement);
  const OSStatus checked = parsed == errSecSuccess ? SecCodeCheckValidity(code, kSecCSStrictValidate, requirement) : parsed;
  if (requirement) CFRelease(requirement); if (text) CFRelease(text); if (code) CFRelease(code);
  if (checked != errSecSuccess) throw std::runtime_error("worker_signing_requirement_mismatch");
}
std::string process_start_token(pid_t pid) {
  proc_bsdinfo info{};
  const int expected_bytes = static_cast<int>(sizeof(info));
  const int observed_bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expected_bytes);
  if (observed_bytes != expected_bytes) throw std::runtime_error("worker_start_token_unavailable");
  return std::to_string(info.pbi_start_tvsec) + ":" + std::to_string(info.pbi_start_tvusec);
}
std::string xpc_denial_probe(const std::string& service, const std::string& session) {
  __block std::string result;
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  xpc_connection_t connection = xpc_connection_create_mach_service(service.c_str(), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), 0);
  if (!connection) throw std::runtime_error("worker_xpc_probe_create_failed");
  xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
    if (xpc_get_type(event) == XPC_TYPE_ERROR) {
      result = "worker_principal_denied";
      dispatch_semaphore_signal(semaphore);
    }
  });
  xpc_connection_activate(connection);
  xpc_object_t request = xpc_dictionary_create(nullptr, nullptr, 0);
  const auto body = j::canonical(j::value(j::value::object{{"schemaVersion",j::value("2.0.0")},{"operation",j::value("describe-authority-v2")},{"behaviorSessionId",j::value(session)}}));
  xpc_dictionary_set_data(request, "request", body.data(), body.size());
  xpc_connection_send_message_with_reply(connection, request, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^(xpc_object_t reply) {
    if (xpc_get_type(reply) == XPC_TYPE_ERROR) result = "worker_principal_denied";
    else {
      size_t size = 0; const void* bytes = xpc_dictionary_get_data(reply, "response", &size);
      if (bytes && size) {
        try {
          const auto value = j::parse(std::string_view(static_cast<const char*>(bytes), size));
          const auto& object = value.as_object();
          const auto status = j::required_string(object, "status");
          const auto code = j::required_string(object, "errorCode");
          if (status == "denied" && (code == "worker_sandbox_principal_denied" || code == "worker_principal_denied")) result = "worker_principal_denied";
        } catch (...) {}
      }
    }
    dispatch_semaphore_signal(semaphore);
  });
  if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC)) != 0) {
    xpc_connection_cancel(connection); throw std::runtime_error("worker_xpc_probe_timeout");
  }
  xpc_connection_cancel(connection);
  if (result != "worker_principal_denied") throw std::runtime_error("worker_xpc_probe_not_denied");
  return result;
}
}

int main(int argc, char** argv) {
  @autoreleasepool {
    try {
      if (argc == 2 && std::string(argv[1]) == "--source-self-test") {
        std::cout << "{\"status\":\"passed\",\"platform\":\"macos\",\"restrictedPrincipal\":\"signed-app-sandbox-helper\",\"completionEligible\":false}\n";
        return 0;
      }
      std::filesystem::path policy_path; std::string session;
      for (int i=1;i<argc;++i) {
        const std::string arg=argv[i];
        if(arg=="--policy" && ++i<argc) policy_path=argv[i];
        else if(arg=="--session" && ++i<argc) session=argv[i];
        else throw std::runtime_error("unknown_or_missing_argument");
      }
      const auto parsed=j::parse(read_file(policy_path)); const auto& policy=parsed.as_object();
      if(j::required_string(policy,"schemaVersion")!="2.0.0" || j::required_string(policy,"platform")!="macos" || !kp::valid_identifier(session)) throw std::runtime_error("worker_policy_invalid");
      const auto node=std::filesystem::path(j::required_string(policy,"nodeExecutable"));
      const auto host=std::filesystem::path(j::required_string(policy,"hostScript"));
      const auto cwd=std::filesystem::path(j::required_string(policy,"workingDirectory"));
      const auto authority=j::required_string(policy,"authorityAddress");
      if(hash_file(node)!=j::required_string(policy,"nodeSha256") || hash_file(host)!=j::required_string(policy,"hostScriptSha256")) throw std::runtime_error("worker_binary_digest_mismatch");
      const auto self=executable_path(); const auto launcher_hash=hash_file(self);
      if(launcher_hash!=j::required_string(policy,"launcherSha256")) throw std::runtime_error("launcher_digest_mismatch");
      require_own_requirement(j::required_string(policy,"expectedRequirement"));
      char* sandbox_error=nullptr;
      std::string sandbox_message;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      const int sandbox_result=sandbox_init(j::required_string(policy,"sandboxProfile").c_str(),SANDBOX_NAMED,&sandbox_error);
      if(sandbox_result!=0){
        sandbox_message=sandbox_error?sandbox_error:"sandbox_init_failed";
        if(sandbox_error)sandbox_free_error(sandbox_error);
      }
#pragma clang diagnostic pop
      if(sandbox_result!=0) throw std::runtime_error(sandbox_message);
      const auto denial=xpc_denial_probe(authority,session);
      const auto identity=j::value(j::value::object{
        {"type",j::value("launcher.identity")},{"schemaVersion",j::value("2.0.0")},{"platform",j::value("macos")},
        {"principalType",j::value("signed-app-sandbox-helper")},{"sessionId",j::value(session)},
        {"pid",j::value(static_cast<std::int64_t>(::getpid()))},{"startToken",j::value(process_start_token(::getpid()))},
        {"codeDirectoryHash",j::value(own_cdhash())},{"appSandbox",j::value(true)},{"authorityClientEntitlement",j::value(false)},
        {"authorityConnectionDenied",j::value(true)},{"authorityDenialCode",j::value(denial)},
        {"launcherSha256",j::value(launcher_hash)},{"nodeSha256",j::value(hash_file(node))},{"hostScriptSha256",j::value(hash_file(host))}});
      std::cout<<j::canonical(identity)<<'\n'<<std::flush;
      if(::chdir(cwd.c_str())!=0) throw std::runtime_error("worker_cwd_failed");
      const std::string node_s=node.string(), host_s=host.string();
      const std::string e1="KRISTIN_WORKER_SESSION_ID="+session, e2="KRISTIN_RESTRICTED_WORKER=1", e3="HOME=/nonexistent", e4="PATH=/usr/bin:/bin", e5="LANG=C.UTF-8";
      std::vector<char*> args{const_cast<char*>(node_s.c_str()),const_cast<char*>(host_s.c_str()),nullptr};
      std::vector<char*> env{const_cast<char*>(e1.c_str()),const_cast<char*>(e2.c_str()),const_cast<char*>(e3.c_str()),const_cast<char*>(e4.c_str()),const_cast<char*>(e5.c_str()),nullptr};
      ::execve(node_s.c_str(),args.data(),env.data());
      throw std::runtime_error("sandbox_worker_exec_failed");
    } catch(const std::exception& error) {
      std::cerr<<"P1A macOS worker launcher fatal: "<<error.what()<<'\n'; return 1;
    }
  }
}
