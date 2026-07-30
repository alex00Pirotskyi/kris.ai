#include "../../native/common/sha256_portable.hpp"
#include "../../native/common/validation.hpp"
#include "../../native/common/strict_json.hpp"

#include <windows.h>
#include <userenv.h>
#include <sddl.h>

#include <array>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace kp = kristin::p1a;
namespace j = kristin::p1a::json;

namespace {
struct handle final {
  HANDLE value = nullptr;
  handle() = default;
  explicit handle(HANDLE v) : value(v) {}
  ~handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
  handle(const handle&) = delete;
  handle& operator=(const handle&) = delete;
};

std::string read_file(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  if (!input) throw std::runtime_error("worker_policy_open_failed");
  return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}
std::string hash_file(const std::filesystem::path& path) { return kp::sha256_hex(read_file(path)); }
std::wstring widen(std::string_view text) {
  if (text.empty()) return {};
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (count <= 0) throw std::runtime_error("utf8_invalid");
  std::wstring result(static_cast<std::size_t>(count), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), result.data(), count);
  return result;
}
std::string narrow(std::wstring_view text) {
  if (text.empty()) return {};
  const int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  if (count <= 0) throw std::runtime_error("utf16_invalid");
  std::string result(static_cast<std::size_t>(count), '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), result.data(), count, nullptr, nullptr);
  return result;
}
std::wstring quote(const std::wstring& value) {
  std::wstring out = L"\"";
  unsigned slashes = 0;
  for (const wchar_t c : value) {
    if (c == L'\\') { ++slashes; continue; }
    if (c == L'\"') { out.append(slashes * 2 + 1, L'\\'); out.push_back(c); slashes = 0; continue; }
    out.append(slashes, L'\\'); slashes = 0; out.push_back(c);
  }
  out.append(slashes * 2, L'\\'); out.push_back(L'\"');
  return out;
}
std::wstring appcontainer_sid(PSID sid) {
  LPWSTR text = nullptr;
  if (!ConvertSidToStringSidW(sid, &text)) throw std::runtime_error("appcontainer_sid_string_failed");
  std::wstring result(text); LocalFree(text); return result;
}
std::string creation_token(HANDLE process) {
  FILETIME created{}, exited{}, kernel{}, user{};
  if (!GetProcessTimes(process, &created, &exited, &kernel, &user)) throw std::runtime_error("worker_creation_time_unavailable");
  ULARGE_INTEGER value{}; value.LowPart = created.dwLowDateTime; value.HighPart = created.dwHighDateTime;
  return std::to_string(value.QuadPart);
}
std::wstring env_value(const wchar_t* name) {
  const DWORD size = GetEnvironmentVariableW(name, nullptr, 0);
  if (size == 0) return {};
  std::wstring value(size, L'\0');
  const DWORD written = GetEnvironmentVariableW(name, value.data(), size);
  if (written == 0 || written >= size) return {};
  value.resize(written); return value;
}
void add_env(std::vector<wchar_t>& block, const std::wstring& key, const std::wstring& value) {
  if (value.empty()) return;
  const std::wstring row = key + L"=" + value;
  block.insert(block.end(), row.begin(), row.end()); block.push_back(L'\0');
}

int provision_appcontainer(const std::wstring& name) {
  PSID sid = nullptr;
  HRESULT result = CreateAppContainerProfile(name.c_str(), name.c_str(),
      L"Kristin restricted automation worker", nullptr, 0, &sid);
  if (result == HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS)) {
    result = DeriveAppContainerSidFromAppContainerName(name.c_str(), &sid);
  }
  if (FAILED(result) || sid == nullptr) throw std::runtime_error("appcontainer_profile_provision_failed");
  struct guard { PSID value; ~guard(){ if(value) FreeSid(value); } } owner{sid};
  std::wcout << appcontainer_sid(sid) << L'\n';
  return 0;
}
std::vector<wchar_t> worker_environment(const std::string& session, const std::string& authority) {
  std::vector<wchar_t> block;
  add_env(block, L"SystemRoot", env_value(L"SystemRoot"));
  add_env(block, L"WINDIR", env_value(L"WINDIR"));
  add_env(block, L"TEMP", env_value(L"TEMP"));
  add_env(block, L"TMP", env_value(L"TMP"));
  add_env(block, L"KRISTIN_WORKER_SESSION_ID", widen(session));
  add_env(block, L"KRISTIN_RESTRICTED_WORKER", L"1");
  add_env(block, L"KRISTIN_P1A_DENIAL_PROBE_REQUIRED", L"1");
  add_env(block, L"KRISTIN_P1A_AUTHORITY_ADDRESS", widen(authority));
  add_env(block, L"KRISTIN_P1A_BEHAVIOR_SESSION_ID", widen(session));
  block.push_back(L'\0');
  return block;
}
}

int wmain(int argc, wchar_t** argv) {
  try {
    if (argc == 3 && std::wstring(argv[1]) == L"--provision-appcontainer") {
      return provision_appcontainer(argv[2]);
    }
    if (argc == 2 && std::wstring(argv[1]) == L"--source-self-test") {
      std::cout << "{\"status\":\"passed\",\"platform\":\"windows\",\"restrictedPrincipal\":\"appcontainer\",\"completionEligible\":false}\n";
      return 0;
    }
    std::filesystem::path policy_path;
    std::string session;
    for (int i = 1; i < argc; ++i) {
      const std::wstring arg = argv[i];
      if (arg == L"--policy" && ++i < argc) policy_path = argv[i];
      else if (arg == L"--session" && ++i < argc) session = narrow(argv[i]);
      else throw std::runtime_error("unknown_or_missing_argument");
    }
    const auto parsed = j::parse(read_file(policy_path));
    const auto& policy = parsed.as_object();
    if (j::required_string(policy, "schemaVersion") != "2.0.0" ||
        j::required_string(policy, "platform") != "windows" || !kp::valid_identifier(session)) {
      throw std::runtime_error("worker_policy_invalid");
    }
    const auto node = std::filesystem::path(widen(j::required_string(policy, "nodeExecutable")));
    const auto host = std::filesystem::path(widen(j::required_string(policy, "hostScript")));
    const auto cwd = std::filesystem::path(widen(j::required_string(policy, "workingDirectory")));
    const auto authority = j::required_string(policy, "authorityAddress");
    if (hash_file(node) != j::required_string(policy, "nodeSha256") ||
        hash_file(host) != j::required_string(policy, "hostScriptSha256")) {
      throw std::runtime_error("worker_binary_digest_mismatch");
    }
    wchar_t self_buffer[32768]{};
    const DWORD self_size = GetModuleFileNameW(nullptr, self_buffer, static_cast<DWORD>(std::size(self_buffer)));
    if (self_size == 0 || self_size >= std::size(self_buffer)) throw std::runtime_error("launcher_identity_failed");
    const std::filesystem::path self(self_buffer);
    const auto launcher_hash = hash_file(self);
    if (launcher_hash != j::required_string(policy, "launcherSha256")) throw std::runtime_error("launcher_digest_mismatch");

    const std::wstring appcontainer_name = widen(j::required_string(policy, "appContainerName"));
    PSID raw_sid = nullptr;
    if (FAILED(DeriveAppContainerSidFromAppContainerName(appcontainer_name.c_str(), &raw_sid))) {
      throw std::runtime_error("appcontainer_profile_missing");
    }
    struct sid_guard { PSID value; ~sid_guard(){ if(value) FreeSid(value); } } sid{raw_sid};
    SECURITY_CAPABILITIES capabilities{}; capabilities.AppContainerSid = raw_sid;
    SIZE_T attribute_bytes = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &attribute_bytes);
    std::vector<unsigned char> attribute_storage(attribute_bytes);
    auto* attributes = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(attribute_storage.data());
    if (!InitializeProcThreadAttributeList(attributes, 1, 0, &attribute_bytes) ||
        !UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES,
                                   &capabilities, sizeof(capabilities), nullptr, nullptr)) {
      throw std::runtime_error("appcontainer_attributes_failed");
    }
    struct attrs_guard { LPPROC_THREAD_ATTRIBUTE_LIST value; ~attrs_guard(){ if(value) DeleteProcThreadAttributeList(value); } } attrs{attributes};

    handle job(CreateJobObjectW(nullptr, nullptr));
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!job.value || !SetInformationJobObject(job.value, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) {
      throw std::runtime_error("worker_job_create_failed");
    }
    STARTUPINFOEXW startup{}; startup.StartupInfo.cb = sizeof(startup); startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startup.StartupInfo.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    startup.StartupInfo.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    startup.lpAttributeList = attributes;
    std::wstring command = quote(node.wstring()) + L" " + quote(host.wstring());
    std::vector<wchar_t> mutable_command(command.begin(), command.end()); mutable_command.push_back(L'\0');
    auto environment = worker_environment(session, authority);
    PROCESS_INFORMATION pi{};
    if (!CreateProcessW(node.c_str(), mutable_command.data(), nullptr, nullptr, TRUE,
                        EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
                        environment.data(), cwd.c_str(), &startup.StartupInfo, &pi)) {
      throw std::runtime_error("appcontainer_worker_create_failed:" + std::to_string(GetLastError()));
    }
    handle process(pi.hProcess), thread(pi.hThread);
    if (!AssignProcessToJobObject(job.value, process.value)) {
      TerminateProcess(process.value, 1); throw std::runtime_error("worker_job_assignment_failed");
    }
    const auto identity = j::value(j::value::object{
        {"type",j::value("launcher.identity")},{"schemaVersion",j::value("2.0.0")},
        {"platform",j::value("windows")},{"principalType",j::value("appcontainer")},
        {"sessionId",j::value(session)},{"pid",j::value(static_cast<std::int64_t>(pi.dwProcessId))},
        {"startToken",j::value(creation_token(process.value))},{"workerSid",j::value(narrow(appcontainer_sid(raw_sid)))},
        {"jobObjectBound",j::value(true)},{"authorityDenialProbeRequired",j::value(true)},
        {"launcherSha256",j::value(launcher_hash)},{"nodeSha256",j::value(hash_file(node))},
        {"hostScriptSha256",j::value(hash_file(host))}});
    std::cout << j::canonical(identity) << '\n' << std::flush;
    if (ResumeThread(thread.value) == DWORD(-1)) {
      TerminateProcess(process.value, 1); throw std::runtime_error("worker_resume_failed");
    }
    WaitForSingleObject(process.value, INFINITE);
    DWORD exit_code = 1; GetExitCodeProcess(process.value, &exit_code);
    return static_cast<int>(exit_code);
  } catch (const std::exception& error) {
    std::cerr << "P1A Windows worker launcher fatal: " << error.what() << '\n';
    return 1;
  }
}
