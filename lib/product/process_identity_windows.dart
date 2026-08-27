import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// A PID-reuse-safe Windows process identity: the process creation time
/// (as a raw `FILETIME`, 100ns intervals since 1601-01-01 UTC) combined
/// with the pid.
///
/// This ports the exact technique already reviewed and shipping in
/// `automation_host/native/windows/job_supervisor.cpp`'s `identity_token()`
/// (`OpenProcess` + `GetProcessTimes`, creation `FILETIME` combined with the
/// pid) — that C++ supervisor is scoped to the automation host's own
/// sandboxed workers, so this is a small, focused Dart FFI port of the same
/// idea for Project Manager's own launched processes.
class WindowsProcessIdentity {
  const WindowsProcessIdentity({
    required this.pid,
    required this.creationFileTime,
  });

  final int pid;
  final int creationFileTime;

  String get token => 'windows:$pid:$creationFileTime';
}

const int _kProcessQueryLimitedInformation = 0x1000;

final class _FileTime extends Struct {
  @Uint32()
  external int dwLowDateTime;

  @Uint32()
  external int dwHighDateTime;
}

typedef _OpenProcessNative = IntPtr Function(
  Uint32 desiredAccess,
  Int32 inheritHandle,
  Uint32 processId,
);
typedef _OpenProcessDart = int Function(
  int desiredAccess,
  int inheritHandle,
  int processId,
);

typedef _GetProcessTimesNative = Int32 Function(
  IntPtr process,
  Pointer<_FileTime> creationTime,
  Pointer<_FileTime> exitTime,
  Pointer<_FileTime> kernelTime,
  Pointer<_FileTime> userTime,
);
typedef _GetProcessTimesDart = int Function(
  int process,
  Pointer<_FileTime> creationTime,
  Pointer<_FileTime> exitTime,
  Pointer<_FileTime> kernelTime,
  Pointer<_FileTime> userTime,
);

typedef _CloseHandleNative = Int32 Function(IntPtr object);
typedef _CloseHandleDart = int Function(int object);

DynamicLibrary? _kernel32;

DynamicLibrary? _loadKernel32() {
  if (!Platform.isWindows) {
    return null;
  }
  final cached = _kernel32;
  if (cached != null) {
    return cached;
  }
  try {
    return _kernel32 = DynamicLibrary.open('kernel32.dll');
  } on ArgumentError {
    return null;
  }
}

/// Reads the current identity of [pid] via `kernel32.dll`, or returns null
/// if this is not Windows, [pid] is not a real process id, or the process
/// cannot be inspected (already gone, access denied). Never throws.
WindowsProcessIdentity? readWindowsProcessIdentity(int pid) {
  if (pid <= 0 || !Platform.isWindows) {
    return null;
  }
  final kernel32 = _loadKernel32();
  if (kernel32 == null) {
    return null;
  }

  final int Function(int, int, int) openProcess;
  final int Function(int, Pointer<_FileTime>, Pointer<_FileTime>,
      Pointer<_FileTime>, Pointer<_FileTime>) getProcessTimes;
  final int Function(int) closeHandle;
  try {
    openProcess = kernel32
        .lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess');
    getProcessTimes =
        kernel32.lookupFunction<_GetProcessTimesNative, _GetProcessTimesDart>(
            'GetProcessTimes');
    closeHandle = kernel32
        .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  } on ArgumentError {
    return null;
  }

  final handle =
      openProcess(_kProcessQueryLimitedInformation, 0 /* FALSE */, pid);
  if (handle == 0) {
    return null;
  }
  try {
    final creation = calloc<_FileTime>();
    final exit = calloc<_FileTime>();
    final kernelTime = calloc<_FileTime>();
    final userTime = calloc<_FileTime>();
    try {
      final ok = getProcessTimes(handle, creation, exit, kernelTime, userTime);
      if (ok == 0) {
        return null;
      }
      final combined =
          (creation.ref.dwHighDateTime << 32) | creation.ref.dwLowDateTime;
      return WindowsProcessIdentity(pid: pid, creationFileTime: combined);
    } finally {
      calloc.free(creation);
      calloc.free(exit);
      calloc.free(kernelTime);
      calloc.free(userTime);
    }
  } finally {
    closeHandle(handle);
  }
}
