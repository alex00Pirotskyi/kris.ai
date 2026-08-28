import 'dart:io';

/// A PID-reuse-safe Linux process identity, derived from `/proc/<pid>/stat`.
///
/// This mirrors `tool/sandbox_worker.py`'s `_proc_identity`/
/// `process_identity_alive` exactly: the executable name in `/proc/<pid>/stat`
/// is wrapped in parentheses and may itself contain spaces or parentheses, so
/// parsing splits after the *final* closing parenthesis to read the
/// remaining fields (state, ppid, ..., start-time ticks) from stable
/// positions. The start-time-ticks value (field 22 in `man proc`, i.e. index
/// 19 counting from the field right after the executable name) is what makes
/// this safe against PID reuse: an unrelated process that happens to reuse a
/// terminated process's PID will almost certainly have a different start
/// time.
class LinuxProcessIdentity {
  const LinuxProcessIdentity({
    required this.pid,
    required this.state,
    required this.startTimeTicks,
  });

  final int pid;
  final String state;
  final int startTimeTicks;

  bool get isZombie => state == 'Z';

  String get token => 'linux:$pid:$startTimeTicks';
}

/// Reads the current identity of [pid] from `/proc/<pid>/stat`, or returns
/// null if this is not Linux, [pid] is not a real process id, or the
/// process cannot be inspected (already gone, permission denied, malformed
/// stat contents). Never throws.
Future<LinuxProcessIdentity?> readLinuxProcessIdentity(int pid) async {
  if (pid <= 1 || !Platform.isLinux) {
    return null;
  }
  String text;
  try {
    text = await File('/proc/$pid/stat').readAsString();
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
  final close = text.lastIndexOf(')');
  if (close < 0 || close + 2 > text.length) {
    return null;
  }
  final fields = text
      .substring(close + 2)
      .split(RegExp(r'\s+'))
      .where((field) => field.isNotEmpty)
      .toList(growable: false);
  if (fields.length <= 19) {
    return null;
  }
  final startTimeTicks = int.tryParse(fields[19]);
  if (startTimeTicks == null) {
    return null;
  }
  return LinuxProcessIdentity(
    pid: pid,
    state: fields[0],
    startTimeTicks: startTimeTicks,
  );
}
