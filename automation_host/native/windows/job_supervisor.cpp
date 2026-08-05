#include <windows.h>
#include <atomic>
#include <cstring>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>
#include <stdexcept>
#include <vector>

static constexpr const char* kControlKill = "KRISTIN_CONTROL kill\n";
static constexpr const char* kControlClose = "KRISTIN_CONTROL close\n";
static constexpr const char* kControlBeat = "KRISTIN_CONTROL beat\n";
static constexpr const char* kControlDisarm = "KRISTIN_CONTROL disarm\n";
static constexpr const char* kControlArmPrefix = "KRISTIN_CONTROL arm ";

static void emit_error(const wchar_t* message, DWORD code = GetLastError()) {
  std::wcerr << L"KRISTIN_SUPERVISOR {\"status\":\"error\",\"message\":\""
             << message << L"\",\"win32\":" << code << L"}\n" << std::flush;
}

static std::wstring quote(const std::wstring& value) {
  std::wstring out = L"\"";
  unsigned slashes = 0;
  for (wchar_t ch : value) {
    if (ch == L'\\') {
      ++slashes;
      continue;
    }
    if (ch == L'\"') {
      out.append(slashes * 2 + 1, L'\\');
      out.push_back(ch);
      slashes = 0;
      continue;
    }
    out.append(slashes, L'\\');
    slashes = 0;
    out.push_back(ch);
  }
  out.append(slashes * 2, L'\\');
  out.push_back(L'\"');
  return out;
}

static std::wstring identity_token(HANDLE process, DWORD pid) {
  FILETIME created{}, exited{}, kernel{}, user{};
  if (!GetProcessTimes(process, &created, &exited, &kernel, &user)) return L"";
  ULARGE_INTEGER value{};
  value.LowPart = created.dwLowDateTime;
  value.HighPart = created.dwHighDateTime;
  std::wstringstream stream;
  stream << L"windows:" << pid << L":" << value.QuadPart;
  return stream.str();
}

static HANDLE configured_job() {
  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  if (!job) return nullptr;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags =
      JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE |
      JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION;
  if (!SetInformationJobObject(
          job,
          JobObjectExtendedLimitInformation,
          &limits,
          sizeof(limits))) {
    CloseHandle(job);
    return nullptr;
  }
  return job;
}

static bool query_active(HANDLE job, DWORD* active) {
  JOBOBJECT_BASIC_ACCOUNTING_INFORMATION info{};
  if (!QueryInformationJobObject(
          job,
          JobObjectBasicAccountingInformation,
          &info,
          sizeof(info),
          nullptr)) {
    return false;
  }
  *active = info.ActiveProcesses;
  return true;
}

static bool write_all(HANDLE target, const char* bytes, DWORD size) {
  DWORD offset = 0;
  while (offset < size) {
    DWORD written = 0;
    if (!WriteFile(target, bytes + offset, size - offset, &written, nullptr)) {
      return false;
    }
    if (written == 0) return false;
    offset += written;
  }
  return true;
}

int wmain(int argc, wchar_t** argv) {
  if (argc != 4 ||
      (std::wstring(argv[1]) != L"--launch-broker" &&
       std::wstring(argv[1]) != L"--launch-broker-nested-test")) {
    std::wcerr << L"Usage: kristin_job_supervisor.exe "
                  L"(--launch-broker|--launch-broker-nested-test) NODE BROKER_SCRIPT\n";
    return 2;
  }
  const bool nested_self_test =
      std::wstring(argv[1]) == L"--launch-broker-nested-test";
  HANDLE outer_job = nullptr;
  if (nested_self_test) {
    outer_job = CreateJobObjectW(nullptr, nullptr);
    if (!outer_job || !AssignProcessToJobObject(outer_job, GetCurrentProcess())) {
      emit_error(L"nested Job Object self-test assignment");
      if (outer_job) CloseHandle(outer_job);
      return 1;
    }
  }

  HANDLE job = configured_job();
  if (!job) {
    emit_error(L"Create/configure Job Object");
    if (outer_job) CloseHandle(outer_job);
    return 1;
  }

  SECURITY_ATTRIBUTES security{};
  security.nLength = sizeof(security);
  security.bInheritHandle = TRUE;
  HANDLE broker_stdin_read = nullptr;
  HANDLE broker_stdin_write = nullptr;
  if (!CreatePipe(&broker_stdin_read, &broker_stdin_write, &security, 0) ||
      !SetHandleInformation(broker_stdin_write, HANDLE_FLAG_INHERIT, 0)) {
    emit_error(L"Create broker stdin pipe");
    if (broker_stdin_read) CloseHandle(broker_stdin_read);
    if (broker_stdin_write) CloseHandle(broker_stdin_write);
    CloseHandle(job);
    if (outer_job) CloseHandle(outer_job);
    return 1;
  }

  std::wstring command = quote(argv[2]) + L" " + quote(argv[3]);
  std::vector<wchar_t> mutable_command(command.begin(), command.end());
  mutable_command.push_back(L'\0');
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = broker_stdin_read;
  startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
  startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  PROCESS_INFORMATION child{};
  if (!CreateProcessW(
          nullptr,
          mutable_command.data(),
          nullptr,
          nullptr,
          TRUE,
          CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_PROCESS_GROUP,
          nullptr,
          nullptr,
          &startup,
          &child)) {
    emit_error(L"CreateProcessW");
    CloseHandle(broker_stdin_read);
    CloseHandle(broker_stdin_write);
    CloseHandle(job);
    if (outer_job) CloseHandle(outer_job);
    return 1;
  }
  CloseHandle(broker_stdin_read);

  if (!AssignProcessToJobObject(job, child.hProcess)) {
    emit_error(L"AssignProcessToJobObject");
    TerminateProcess(child.hProcess, 126);
    CloseHandle(child.hThread);
    CloseHandle(child.hProcess);
    CloseHandle(broker_stdin_write);
    CloseHandle(job);
    if (outer_job) CloseHandle(outer_job);
    return 1;
  }

  const std::wstring token = identity_token(child.hProcess, child.dwProcessId);
  if (token.empty() || ResumeThread(child.hThread) == static_cast<DWORD>(-1)) {
    emit_error(L"ResumeThread/GetProcessTimes");
    TerminateJobObject(job, 126);
    CloseHandle(child.hThread);
    CloseHandle(child.hProcess);
    CloseHandle(broker_stdin_write);
    CloseHandle(job);
    if (outer_job) CloseHandle(outer_job);
    return 1;
  }
  CloseHandle(child.hThread);
  std::wcerr << L"KRISTIN_SUPERVISOR {\"status\":\"launched\",\"pid\":"
             << child.dwProcessId << L",\"startToken\":\"" << token
             << L"\",\"jobId\":\"job:" << GetCurrentProcessId()
             << L"\",\"assignedBeforeResume\":true,\"nestedJobSelfTest\":"
             << (nested_self_test ? L"true" : L"false") << L"}\n" << std::flush;

  HANDLE controller_input = GetStdHandle(STD_INPUT_HANDLE);
  if (!controller_input || controller_input == INVALID_HANDLE_VALUE) {
    emit_error(L"supervisor_stdin_missing", ERROR_INVALID_HANDLE);
    TerminateJobObject(job, 126);
    CloseHandle(child.hProcess);
    CloseHandle(broker_stdin_write);
    CloseHandle(job);
    if (outer_job) CloseHandle(outer_job);
    return 1;
  }

  std::atomic<bool> kill_requested{false};
  std::atomic<bool> control_failed{false};
  std::atomic<DWORD> active_before_termination{0};
  std::atomic<bool> controller_stop{false};
  std::atomic<int> kill_reason{0};  // 1 explicit, 2 timeout, 3 control pipe closed
  std::atomic<unsigned long long> watchdog_timeout_ms{0};
  std::atomic<unsigned long long> watchdog_deadline_ms{0};
  std::thread controller([&]() {
    const auto observe_active_before_termination = [&]() {
      DWORD active = 0;
      if (query_active(job, &active)) active_before_termination.store(active);
    };
    char buffer[4096];
    std::string pending;
    while (!controller_stop.load()) {
      DWORD available = 0;
      if (!PeekNamedPipe(controller_input, nullptr, 0, nullptr, &available, nullptr)) {
        const DWORD error = GetLastError();
        if (error == ERROR_BROKEN_PIPE) {
          kill_reason.store(3);
          kill_requested.store(true);
          observe_active_before_termination();
        TerminateJobObject(job, 137);
          return;
        }
        control_failed.store(true);
        kill_reason.store(3);
        kill_requested.store(true);
        observe_active_before_termination();
        TerminateJobObject(job, 137);
        return;
      }
      if (available > 0) {
        DWORD read = 0;
        const DWORD requested = available < sizeof(buffer)
            ? available
            : static_cast<DWORD>(sizeof(buffer));
        if (!ReadFile(controller_input, buffer, requested, &read, nullptr)) {
          control_failed.store(true);
          kill_reason.store(3);
          kill_requested.store(true);
          observe_active_before_termination();
        TerminateJobObject(job, 137);
          return;
        }
        pending.append(buffer, buffer + read);
        for (;;) {
          const auto newline = pending.find('\n');
          if (newline == std::string::npos) break;
          std::string line = pending.substr(0, newline + 1);
          pending.erase(0, newline + 1);
          if (line == kControlKill) {
            kill_reason.store(1);
            kill_requested.store(true);
            observe_active_before_termination();
            if (!TerminateJobObject(job, 137)) control_failed.store(true);
            if (broker_stdin_write) {
              CloseHandle(broker_stdin_write);
              broker_stdin_write = nullptr;
            }
            return;
          }
          if (line == kControlClose) {
            watchdog_timeout_ms.store(0);
            watchdog_deadline_ms.store(0);
            if (broker_stdin_write) {
              CloseHandle(broker_stdin_write);
              broker_stdin_write = nullptr;
            }
            return;
          }
          if (line == kControlBeat) {
            const auto timeout = watchdog_timeout_ms.load();
            if (timeout > 0) watchdog_deadline_ms.store(GetTickCount64() + timeout);
            continue;
          }
          if (line == kControlDisarm) {
            watchdog_timeout_ms.store(0);
            watchdog_deadline_ms.store(0);
            continue;
          }
          if (line.rfind(kControlArmPrefix, 0) == 0) {
            try {
              const std::string raw = line.substr(strlen(kControlArmPrefix));
              const auto timeout = std::stoull(raw);
              if (timeout < 100 || timeout > 3600000) {
                throw std::out_of_range("watchdog timeout");
              }
              watchdog_timeout_ms.store(timeout);
              watchdog_deadline_ms.store(GetTickCount64() + timeout);
            } catch (...) {
              control_failed.store(true);
              kill_reason.store(2);
              kill_requested.store(true);
              observe_active_before_termination();
        TerminateJobObject(job, 137);
              return;
            }
            continue;
          }
          if (!broker_stdin_write ||
              !write_all(
                  broker_stdin_write,
                  line.data(),
                  static_cast<DWORD>(line.size()))) {
            control_failed.store(true);
            return;
          }
        }
      }
      const auto deadline = watchdog_deadline_ms.load();
      if (deadline > 0 && GetTickCount64() >= deadline) {
        kill_reason.store(2);
        kill_requested.store(true);
        observe_active_before_termination();
        if (!TerminateJobObject(job, 137)) control_failed.store(true);
        if (broker_stdin_write) {
          CloseHandle(broker_stdin_write);
          broker_stdin_write = nullptr;
        }
        return;
      }
      Sleep(25);
    }
  });

  WaitForSingleObject(child.hProcess, INFINITE);
  controller_stop.store(true);
  if (controller.joinable()) controller.join();
  if (broker_stdin_write) CloseHandle(broker_stdin_write);

  DWORD exit_code = 0;
  GetExitCodeProcess(child.hProcess, &exit_code);
  DWORD active = MAXDWORD;
  for (int i = 0; i < 100; ++i) {
    if (!query_active(job, &active)) {
      emit_error(L"QueryInformationJobObject");
      control_failed.store(true);
      break;
    }
    if (active == 0) break;
    Sleep(25);
  }
  const std::wstring current = identity_token(child.hProcess, child.dwProcessId);
  const bool identity_ok = current.empty() || current == token;
  const bool success =
      !control_failed.load() &&
      (!kill_requested.load() || (active == 0 && identity_ok));
  const wchar_t* status = kill_requested.load()
      ? (success ? L"killed" : L"error")
      : (success ? L"exited" : L"error");
  const wchar_t* reason = kill_reason.load() == 2
      ? L"watchdog_timeout"
      : kill_reason.load() == 1
          ? L"explicit_kill"
          : kill_reason.load() == 3 ? L"control_pipe_closed" : L"process_exit";
  std::wcerr << L"KRISTIN_SUPERVISOR {\"status\":\"" << status
             << L"\",\"pid\":" << child.dwProcessId
             << L",\"startToken\":\"" << token
             << L"\",\"activeProcessesBeforeKill\":"
             << active_before_termination.load()
             << L",\"activeProcesses\":" << active
             << L",\"exitCode\":" << exit_code
             << L",\"identityVerified\":" << (identity_ok ? L"true" : L"false")
             << L",\"controlProtocolOk\":" << (!control_failed.load() ? L"true" : L"false")
             << L",\"reason\":\"" << reason << L"\""
             << L"}\n" << std::flush;

  CloseHandle(child.hProcess);
  CloseHandle(job);
  if (outer_job) CloseHandle(outer_job);
  return success ? 0 : 1;
}
