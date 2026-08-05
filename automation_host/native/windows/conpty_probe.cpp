#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace {

void close_if_valid(HANDLE* handle) {
  if (*handle != nullptr && *handle != INVALID_HANDLE_VALUE) {
    CloseHandle(*handle);
    *handle = nullptr;
  }
}

bool write_all(HANDLE handle, const char* bytes, std::size_t size) {
  std::size_t offset = 0;
  while (offset < size) {
    const auto remaining = size - offset;
    const DWORD request = static_cast<DWORD>(
        std::min<std::size_t>(remaining, static_cast<std::size_t>(0x7fffffff)));
    DWORD written = 0;
    if (!WriteFile(handle, bytes + offset, request, &written, nullptr) ||
        written == 0) {
      return false;
    }
    offset += static_cast<std::size_t>(written);
  }
  return true;
}

bool write_all(HANDLE handle, const std::string& value) {
  return write_all(handle, value.data(), value.size());
}

bool query_active_processes(HANDLE job, DWORD* active) {
  JOBOBJECT_BASIC_ACCOUNTING_INFORMATION info{};
  if (!QueryInformationJobObject(job, JobObjectBasicAccountingInformation,
                                 &info, sizeof(info), nullptr)) {
    return false;
  }
  *active = info.ActiveProcesses;
  return true;
}

bool read_until(HANDLE source, const std::string& marker,
                std::chrono::milliseconds timeout, std::string* output) {
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  while (std::chrono::steady_clock::now() < deadline &&
         output->size() < 1024U * 1024U) {
    DWORD available = 0;
    if (!PeekNamedPipe(source, nullptr, 0, nullptr, &available, nullptr)) {
      return false;
    }
    if (available == 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
      continue;
    }
    std::vector<char> buffer(
        static_cast<std::size_t>(std::min<DWORD>(available, 8192U)));
    DWORD read = 0;
    if (!ReadFile(source, buffer.data(), static_cast<DWORD>(buffer.size()),
                  &read, nullptr)) {
      return false;
    }
    output->append(buffer.data(), static_cast<std::size_t>(read));
    if (output->find(marker) != std::string::npos) return true;
  }
  return output->find(marker) != std::string::npos;
}

bool append_file(HANDLE file, const std::string& bytes) {
  LARGE_INTEGER end{};
  if (!SetFilePointerEx(file, end, nullptr, FILE_END)) return false;
  return write_all(file, bytes);
}

bool read_file_from_cursor(const std::wstring& path, std::uint64_t cursor,
                           std::string* bytes) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
                            FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER offset{};
  offset.QuadPart = static_cast<LONGLONG>(cursor);
  if (!SetFilePointerEx(file, offset, nullptr, FILE_BEGIN)) {
    CloseHandle(file);
    return false;
  }
  char buffer[8192];
  for (;;) {
    DWORD read = 0;
    if (!ReadFile(file, buffer, static_cast<DWORD>(sizeof(buffer)), &read,
                  nullptr)) {
      CloseHandle(file);
      return false;
    }
    if (read == 0) break;
    bytes->append(buffer, static_cast<std::size_t>(read));
  }
  CloseHandle(file);
  return true;
}

std::uint64_t file_size(HANDLE file) {
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(file, &size) || size.QuadPart < 0) return 0;
  return static_cast<std::uint64_t>(size.QuadPart);
}

HANDLE configured_job() {
  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  if (job == nullptr) return nullptr;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags =
      JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE |
      JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits,
                               sizeof(limits))) {
    CloseHandle(job);
    return nullptr;
  }
  return job;
}

}  // namespace

int wmain() {
  const auto started = std::chrono::steady_clock::now();
  HANDLE input_read = nullptr;
  HANDLE input_write = nullptr;
  HANDLE output_read = nullptr;
  HANDLE output_write = nullptr;
  HANDLE job = nullptr;
  HANDLE transcript = INVALID_HANDLE_VALUE;
  HPCON console = nullptr;
  LPPROC_THREAD_ATTRIBUTE_LIST attribute_list = nullptr;
  PROCESS_INFORMATION process{};
  wchar_t transcript_path[MAX_PATH]{};
  bool transcript_created = false;
  int failure = 0;

  if (!CreatePipe(&input_read, &input_write, nullptr, 0) ||
      !CreatePipe(&output_read, &output_write, nullptr, 0)) {
    failure = 2;
  }

  COORD size{80, 24};
  if (failure == 0 &&
      FAILED(CreatePseudoConsole(size, input_read, output_write, 0, &console))) {
    failure = 3;
  }
  close_if_valid(&input_read);
  close_if_valid(&output_write);

  SIZE_T attribute_bytes = 0;
  std::vector<unsigned char> attributes;
  if (failure == 0) {
    InitializeProcThreadAttributeList(nullptr, 1, 0, &attribute_bytes);
    if (attribute_bytes == 0) {
      failure = 4;
    } else {
      attributes.resize(attribute_bytes);
      attribute_list = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(
          attributes.data());
      if (!InitializeProcThreadAttributeList(attribute_list, 1, 0,
                                             &attribute_bytes) ||
          !UpdateProcThreadAttribute(attribute_list, 0,
                                     PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                     console, sizeof(console), nullptr,
                                     nullptr)) {
        failure = 4;
      }
    }
  }

  STARTUPINFOEXW startup{};
  startup.StartupInfo.cb = sizeof(startup);
  startup.lpAttributeList = attribute_list;
  std::wstring command = L"cmd.exe /d /q";
  std::vector<wchar_t> mutable_command(command.begin(), command.end());
  mutable_command.push_back(L'\0');
  if (failure == 0) {
    job = configured_job();
    if (job == nullptr) {
      failure = 5;
    } else if (!CreateProcessW(
                   nullptr, mutable_command.data(), nullptr, nullptr, FALSE,
                   EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT |
                       CREATE_NEW_PROCESS_GROUP | CREATE_SUSPENDED,
                   nullptr, nullptr, &startup.StartupInfo, &process)) {
      failure = 6;
    } else if (!AssignProcessToJobObject(job, process.hProcess)) {
      failure = 7;
      TerminateProcess(process.hProcess, 126);
    } else if (ResumeThread(process.hThread) == static_cast<DWORD>(-1)) {
      failure = 8;
      TerminateJobObject(job, 126);
    }
  }
  if (attribute_list != nullptr) DeleteProcThreadAttributeList(attribute_list);
  close_if_valid(&process.hThread);

  wchar_t temp_directory[MAX_PATH]{};
  if (failure == 0) {
    const DWORD temp_length = GetTempPathW(MAX_PATH, temp_directory);
    if (temp_length == 0 || temp_length >= MAX_PATH ||
        GetTempFileNameW(temp_directory, L"KPT", 0, transcript_path) == 0) {
      failure = 9;
    } else {
      transcript_created = true;
      transcript = CreateFileW(
          transcript_path, GENERIC_READ | GENERIC_WRITE,
          FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, CREATE_ALWAYS,
          FILE_ATTRIBUTE_TEMPORARY, nullptr);
      if (transcript == INVALID_HANDLE_VALUE) failure = 9;
    }
  }

  COORD resized{123, 41};
  const bool resize_ok =
      failure == 0 && SUCCEEDED(ResizePseudoConsole(console, resized));
  const std::string initial_command =
      "chcp 65001 >nul\r\n"
      "echo KRISTIN_NATIVE_ANSI KRISTIN_NATIVE_UNICODE_TEST\r\n";
  const bool input_ok = failure == 0 && write_all(input_write, initial_command);
  std::string initial_output;
  const bool initial_observed =
      failure == 0 &&
      read_until(output_read, "KRISTIN_NATIVE_UNICODE_TEST",
                 std::chrono::seconds(8), &initial_output);
  const bool initial_persisted =
      initial_observed && append_file(transcript, initial_output);
  const std::uint64_t reconnect_cursor =
      initial_persisted ? file_size(transcript) : 0;

  const std::string detached_command =
      "start \"\" /b powershell.exe -NoLogo -NoProfile -NonInteractive "
      "-Command \"Start-Sleep -Seconds 30\"\r\n"
      "powershell.exe -NoLogo -NoProfile -NonInteractive -Command "
      "\"Start-Sleep -Milliseconds 250; Write-Output "
      "KRISTIN_DETACHED_OUTPUT\"\r\n";
  const bool detached_command_written =
      failure == 0 && write_all(input_write, detached_command);
  const auto detached_started = std::chrono::steady_clock::now();
  std::this_thread::sleep_for(std::chrono::milliseconds(700));
  const auto detached_elapsed =
      std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now() - detached_started)
          .count();

  DWORD active_before_kill = 0;
  const bool active_before_observed =
      failure == 0 && query_active_processes(job, &active_before_kill);
  std::string detached_output;
  const bool detached_output_observed =
      failure == 0 &&
      read_until(output_read, "KRISTIN_DETACHED_OUTPUT",
                 std::chrono::seconds(8), &detached_output);
  const bool detached_persisted =
      detached_output_observed && append_file(transcript, detached_output);
  if (transcript != INVALID_HANDLE_VALUE) {
    FlushFileBuffers(transcript);
    CloseHandle(transcript);
    transcript = INVALID_HANDLE_VALUE;
  }

  std::string replayed_backlog;
  const bool replay_read =
      detached_persisted &&
      read_file_from_cursor(transcript_path, reconnect_cursor,
                            &replayed_backlog);
  const bool backlog_exact = replay_read && replayed_backlog == detached_output;
  const bool no_loss_or_duplication =
      backlog_exact && !replayed_backlog.empty() &&
      replayed_backlog.find("KRISTIN_DETACHED_OUTPUT") != std::string::npos;

  const bool terminate_requested = failure == 0 && TerminateJobObject(job, 137);
  if (process.hProcess != nullptr) {
    WaitForSingleObject(process.hProcess, 5000);
  }
  DWORD active_after_kill = 0xffffffffU;
  bool active_after_observed = false;
  if (job != nullptr) {
    const auto deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(5);
    do {
      active_after_observed = query_active_processes(job, &active_after_kill);
      if (active_after_observed && active_after_kill == 0) break;
      std::this_thread::sleep_for(std::chrono::milliseconds(40));
    } while (std::chrono::steady_clock::now() < deadline);
  }

  const bool ansi = initial_output.find("KRISTIN_NATIVE_ANSI") !=
                    std::string::npos;
  const bool unicode = initial_output.find("KRISTIN_NATIVE_UNICODE_TEST") !=
                       std::string::npos;
  const bool consumer_detached = detached_elapsed >= 650;
  const bool output_while_detached =
      consumer_detached && detached_command_written &&
      detached_output.find("KRISTIN_DETACHED_OUTPUT") != std::string::npos;
  const bool cursor_observed = reconnect_cursor > 0;
  const bool descendant_created =
      active_before_observed && active_before_kill >= 2;
  const bool descendant_terminated =
      terminate_requested && active_after_observed && active_after_kill == 0;
  const bool zero_survivors = descendant_terminated;

  const bool passed = failure == 0 && input_ok && resize_ok && ansi && unicode &&
                      consumer_detached && output_while_detached &&
                      cursor_observed && backlog_exact &&
                      no_loss_or_duplication && descendant_created &&
                      descendant_terminated && zero_survivors;
  const auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
                            std::chrono::steady_clock::now() - started)
                            .count();

  std::cout
      << "{\"schemaVersion\":\"3.0.0\","
      << "\"receiptType\":\"p2-native-supplementary-smoke-v1\","
      << "\"completionEligible\":false,"
      << "\"status\":\"" << (passed ? "passed" : "failed") << "\","
      << "\"coldStartMs\":" << duration << ','
      << "\"failureCode\":" << failure << ','
      << "\"observed\":{"
      << "\"interactiveInput\":" << (input_ok ? "true" : "false") << ','
      << "\"resize\":" << (resize_ok ? "true" : "false") << ','
      << "\"ansi\":" << (ansi ? "true" : "false") << ','
      << "\"unicode\":" << (unicode ? "true" : "false") << ','
      << "\"sameTransportDelayedOutput\":" << (output_while_detached ? "true" : "false") << ','
      << "\"processTreeTermination\":" << (zero_survivors ? "true" : "false") << "},"
      << "\"notMeasured\":[\"consumer-detach\",\"durable-cursor-reconnect\",\"exact-backlog-replay\"],"
      << "\"activeProcessesBeforeKill\":" << active_before_kill << ','
      << "\"activeProcessesAfterKill\":" << active_after_kill << ','
      << "\"childPid\":" << process.dwProcessId << ','
      << "\"outputBytes\":" << (initial_output.size() + detached_output.size()) << "}\n";

  close_if_valid(&process.hProcess);
  close_if_valid(&input_write);
  close_if_valid(&output_read);
  close_if_valid(&job);
  if (console != nullptr) ClosePseudoConsole(console);
  if (transcript != INVALID_HANDLE_VALUE) CloseHandle(transcript);
  if (transcript_created) DeleteFileW(transcript_path);
  return passed ? 0 : 1;
}
