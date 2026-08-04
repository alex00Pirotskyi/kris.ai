import 'dart:async';
import 'dart:io';

import 'p2_effect_boundary.dart';
import 'p2_effect_journal.dart';
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

abstract interface class P2CommandAuthorizer {
  Future<Map<String, Object?>> authorize(
    P2EffectBinding binding,
    P2CommandSpec spec,
  );
}

class P2FiniteCommandService {
  P2FiniteCommandService({
    required this.authorizer,
    required this.processTrees,
    required this.journal,
  });

  final P2CommandAuthorizer authorizer;
  final P2ProcessTreeManager processTrees;
  final P2EffectJournal journal;

  Future<P2CommandResult> run(
    P2CommandSpec spec, {
    required P2EffectBinding binding,
  }) async {
    await authorizer.authorize(binding, spec);
    if (spec.runInShell) {
      throw StateError('shell_requires_explicit_shell_operation');
    }
    if (!File(spec.executable).isAbsolute &&
        !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(spec.executable)) {
      throw StateError('invalid_executable');
    }
    if (!Directory(spec.cwd).isAbsolute) {
      throw StateError('absolute_cwd_required');
    }
    if (spec.deadline <= Duration.zero ||
        spec.deadline > const Duration(hours: 24)) {
      throw StateError('invalid_deadline');
    }
    if (spec.maxStdoutBytes < 0 || spec.maxStderrBytes < 0) {
      throw StateError('invalid_output_budget');
    }

    final environment = <String, String>{};
    for (final key in spec.inheritEnvironmentKeys) {
      final value = Platform.environment[key];
      if (value != null) {
        environment[key] = value;
      }
    }
    for (final entry in spec.environmentDelta.entries) {
      if (entry.key.contains('=') || entry.key.contains('\u0000')) {
        throw StateError('invalid_environment_key');
      }
      if (_sensitiveEnvironmentKey(entry.key)) {
        throw StateError('sensitive_environment_key_requires_secret_handle');
      }
      if (entry.value?.contains('\u0000') ?? false) {
        throw StateError('invalid_environment_value');
      }
      if (entry.value == null) {
        environment.remove(entry.key);
      } else {
        environment[entry.key] = entry.value!;
      }
    }

    final startedAt = DateTime.now().toUtc();
    final process = await Process.start(
      spec.executable,
      spec.arguments,
      workingDirectory: spec.cwd,
      environment: environment,
      includeParentEnvironment: false,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );

    P2ProcessIdentity identity;
    try {
      identity = await processTrees.register(process.pid);
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
      rethrow;
    }

    if (spec.stdin != null) {
      process.stdin.add(spec.stdin!);
    }
    await process.stdin.close();

    final stdout = <int>[];
    final stderr = <int>[];
    var truncated = false;
    final outSub = process.stdout.listen((chunk) {
      final room = spec.maxStdoutBytes - stdout.length;
      if (room > 0) {
        stdout.addAll(chunk.take(room));
      }
      if (chunk.length > room) {
        truncated = true;
      }
    });
    final errSub = process.stderr.listen((chunk) {
      final room = spec.maxStderrBytes - stderr.length;
      if (room > 0) {
        stderr.addAll(chunk.take(room));
      }
      if (chunk.length > room) {
        truncated = true;
      }
    });

    int? exitCode;
    var status = P2EffectStatus.unknown;
    try {
      exitCode = await process.exitCode.timeout(spec.deadline);
      if (truncated) {
        await processTrees.kill(identity);
        status = P2EffectStatus.killed;
      } else {
        status =
            exitCode == 0 ? P2EffectStatus.succeeded : P2EffectStatus.failed;
      }
    } on TimeoutException {
      await processTrees.kill(identity);
      status = P2EffectStatus.killed;
    } finally {
      await outSub.cancel();
      await errSub.cancel();
    }

    final completedAt = DateTime.now().toUtc();
    final receipt = P2EffectReceipt(
      effectId: 'cmd-${completedAt.microsecondsSinceEpoch}',
      runId: binding.runId,
      taskId: binding.taskId,
      operation: 'execute',
      status: status,
      reversibility: P2Reversibility.irreversible,
      startedAt: startedAt,
      completedAt: completedAt,
      details: <String, Object?>{
        'executable': spec.executable,
        'cwd': spec.cwd,
        'argumentCount': spec.arguments.length,
        'environmentKeys': spec.environmentDelta.keys.toList(growable: false),
        'inheritedEnvironmentKeys': environment.keys.toList(growable: false),
        'exitCode': exitCode,
        'stdoutBytes': stdout.length,
        'stderrBytes': stderr.length,
        'outputTruncated': truncated,
        'processIdentity': identity.toJson(),
      },
    );
    await journal.append(receipt);
    return P2CommandResult(
      status: status,
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      outputTruncated: truncated,
      processIdentity: identity,
    );
  }

  bool _sensitiveEnvironmentKey(String key) => RegExp(
        r'(secret|token|password|credential|api.?key|private.?key)',
        caseSensitive: false,
      ).hasMatch(key);
}
