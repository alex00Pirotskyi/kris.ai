import 'dart:io';

class ProcessLaunchTarget {
  const ProcessLaunchTarget({
    required this.executable,
    required this.runInShell,
  });

  final String executable;
  final bool runInShell;
}

bool requiresWindowsCommandShell(
  String executable, {
  bool? isWindows,
}) {
  final windows = isWindows ?? Platform.isWindows;
  if (!windows) {
    return false;
  }
  final lower = executable.trim().toLowerCase();
  return lower.endsWith('.bat') || lower.endsWith('.cmd');
}

Future<String?> resolveExecutableOnPath(String executable) async {
  final value = executable.trim();
  if (value.isEmpty) {
    return null;
  }

  final direct = File(value);
  if (direct.isAbsolute && await direct.exists()) {
    return direct.path;
  }

  final path = Platform.environment['PATH'] ?? '';
  final pathSeparator = Platform.isWindows ? ';' : ':';
  final extensions = Platform.isWindows
      ? (Platform.environment['PATHEXT'] ?? '.EXE;.CMD;.BAT;.COM')
          .split(';')
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false)
      : const <String>[''];

  for (final rawDirectory in path.split(pathSeparator)) {
    final directory = rawDirectory.trim();
    if (directory.isEmpty) {
      continue;
    }
    for (final extension in extensions) {
      final hasExtension = Platform.isWindows &&
          value.toLowerCase().endsWith(extension.toLowerCase());
      final candidate = File(
        '$directory${Platform.pathSeparator}$value${hasExtension ? '' : extension}',
      );
      if (await candidate.exists()) {
        return candidate.path;
      }
    }
  }
  return null;
}

Future<ProcessLaunchTarget> resolveProcessLaunchTarget(
  String executable,
) async {
  final resolved = await resolveExecutableOnPath(executable);
  final target = resolved ?? executable;
  return ProcessLaunchTarget(
    executable: target,
    runInShell: requiresWindowsCommandShell(target),
  );
}
