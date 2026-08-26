import 'dart:async';
import 'dart:io';

/// A project's git state as of the moment it was probed. `null` fields mean
/// "not a git repository" or "could not be determined", never a guess.
class GitStateSnapshot {
  const GitStateSnapshot({
    required this.isRepository,
    required this.capturedAt,
    this.branch,
    this.headSha,
    this.clean,
  });

  final bool isRepository;
  final DateTime capturedAt;
  final String? branch;
  final String? headSha;
  final bool? clean;
}

const Set<String> _allowedGitProbeEnvironmentKeys = <String>{
  'PATH',
  'Path',
  'HOME',
  'USERPROFILE',
  'TMP',
  'TEMP',
  'TMPDIR',
  'SystemRoot',
  'WINDIR',
  'COMSPEC',
  'PATHEXT',
  'LANG',
  'LC_ALL',
  'XDG_CACHE_HOME',
  'XDG_CONFIG_HOME',
  'LOCALAPPDATA',
  'APPDATA',
};

Map<String, String> _restrictedEnvironment() => <String, String>{
      for (final entry in Platform.environment.entries)
        if (_allowedGitProbeEnvironmentKeys.contains(entry.key)) entry.key: entry.value,
    };

/// Runs a single bounded, read-only `git` probe against [rootPath] — never
/// spawned from a hot UI path (a project card, a per-frame status refresh);
/// callers are responsible for caching the result (see
/// `ProjectControlService`'s TTL cache) and only calling this from an
/// explicit refresh, a first-open of a project's detail view, or a genuine
/// state-changing action (e.g. recording a quality result). A 5-second
/// timeout and a restricted environment keep this a safe, self-contained
/// probe distinct from the agent tool-call path
/// (`ToolRegistry._gitStatus`/`_gitDiff`), which carries sandboxing and
/// cancellation machinery this lightweight status read does not need.
Future<GitStateSnapshot> probeGitState(String rootPath) async {
  final now = DateTime.now().toUtc();
  final root = Directory(rootPath);
  if (!await root.exists()) {
    return GitStateSnapshot(isRepository: false, capturedAt: now);
  }
  try {
    final branchResult = await Process.run(
      'git',
      const <String>['rev-parse', '--abbrev-ref', 'HEAD'],
      workingDirectory: rootPath,
      environment: _restrictedEnvironment(),
      runInShell: false,
    ).timeout(const Duration(seconds: 5));
    if (branchResult.exitCode != 0) {
      return GitStateSnapshot(isRepository: false, capturedAt: now);
    }
    final headResult = await Process.run(
      'git',
      const <String>['rev-parse', 'HEAD'],
      workingDirectory: rootPath,
      environment: _restrictedEnvironment(),
      runInShell: false,
    ).timeout(const Duration(seconds: 5));
    final statusResult = await Process.run(
      'git',
      const <String>['status', '--porcelain=v1', '--untracked-files=normal'],
      workingDirectory: rootPath,
      environment: _restrictedEnvironment(),
      runInShell: false,
    ).timeout(const Duration(seconds: 5));
    return GitStateSnapshot(
      isRepository: true,
      capturedAt: now,
      branch: (branchResult.stdout as String).trim(),
      headSha: headResult.exitCode == 0
          ? (headResult.stdout as String).trim()
          : null,
      clean: statusResult.exitCode == 0
          ? (statusResult.stdout as String).trim().isEmpty
          : null,
    );
  } on ProcessException {
    return GitStateSnapshot(isRepository: false, capturedAt: now);
  } on TimeoutException {
    return GitStateSnapshot(isRepository: false, capturedAt: now);
  }
}
