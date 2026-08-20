import 'p2_effect_boundary.dart';
import 'p2_effect_receipt.dart';
import 'p2_process_tree.dart';

class P2CommandSpec {
  const P2CommandSpec({
    required this.executable,
    required this.cwd,
    this.arguments = const <String>[],
    this.environmentDelta = const <String, String?>{},
    this.inheritEnvironmentKeys = const <String>{
      'PATH',
      'Path',
      'SystemRoot',
      'WINDIR',
      'HOME',
      'USERPROFILE',
      'TMP',
      'TEMP',
      'LANG',
      'LC_ALL',
      'TERM',
    },
    this.stdin,
    this.deadline = const Duration(minutes: 5),
    this.maxStdoutBytes = 1048576,
    this.maxStderrBytes = 1048576,
    this.runInShell = false,
  });

  final String executable;
  final String cwd;
  final List<String> arguments;
  final Map<String, String?> environmentDelta;
  final Set<String> inheritEnvironmentKeys;
  final List<int>? stdin;
  final Duration deadline;
  final int maxStdoutBytes;
  final int maxStderrBytes;
  final bool runInShell;
}

class P2CommandResult {
  const P2CommandResult({
    required this.status,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.outputTruncated,
    required this.processIdentity,
  });

  final P2EffectStatus status;
  final int? exitCode;
  final List<int> stdout;
  final List<int> stderr;
  final bool outputTruncated;
  final P2ProcessIdentity processIdentity;
}

abstract interface class P2FiniteCommandService {
  Future<P2CommandResult> run(
    P2CommandSpec spec, {
    required P2EffectBinding binding,
  });
}
