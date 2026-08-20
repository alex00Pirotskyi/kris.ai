import 'dart:convert';

import 'p2_automation_host.dart';
import 'p2_effect_boundary.dart';
import 'p2_effect_journal.dart';
import 'p2_finite_command_service.dart';
import 'p2_process_tree.dart';

P2EffectBinding _commandBinding(P2EffectBinding source, String operation) =>
    P2EffectBinding(
      runId: source.runId,
      taskId: source.taskId,
      actorId: source.actorId,
      toolId: source.toolId,
      accessProfileId: source.accessProfileId,
      capabilityId: source.capabilityId,
      operation: operation,
    );

/// Production finite-command adapter for Owner Mode.
///
/// The desktop authority issues the P1 policy/grant/consumption/IPC envelope;
/// the supervised worker starts the process under the platform lifecycle
/// supervisor and returns bounded output plus a structured effect receipt.
final class P2AutomationFiniteCommandService implements P2FiniteCommandService {
  P2AutomationFiniteCommandService({
    required this.host,
    required this.authority,
    required this.journal,
  });

  final P2AutomationHostClient host;
  final P2AutomationEnvelopeAuthority authority;
  final P2EffectJournal journal;
  P2EffectReceipt? _lastReceipt;

  P2EffectReceipt? get lastReceipt => _lastReceipt;

  @override
  Future<P2CommandResult> run(
    P2CommandSpec spec, {
    required P2EffectBinding binding,
  }) async {
    _validate(spec);
    const operation = 'command.run';
    final envelope = await authority.issue(
      binding: _commandBinding(binding, operation),
      operation: operation,
      payload: <String, Object?>{
        'operation': operation,
        'executable': spec.executable,
        'arguments': List<String>.unmodifiable(spec.arguments),
        'cwd': spec.cwd,
        'environmentDelta': Map<String, String?>.unmodifiable(
          spec.environmentDelta,
        ),
        'stdinBase64': base64Encode(spec.stdin ?? const <int>[]),
        'deadlineMs': spec.deadline.inMilliseconds,
        'maxStdoutBytes': spec.maxStdoutBytes,
        'maxStderrBytes': spec.maxStderrBytes,
        'runInShell': false,
      },
      deadline: spec.deadline + const Duration(seconds: 15),
    );
    final response = await host.invoke(envelope);
    final rawReceipt = response['receipt'];
    final rawOutput = response['output'];
    if (rawReceipt is! Map || rawOutput is! Map) {
      final code = response['code']?.toString() ?? 'unknown';
      final message = response['message']?.toString() ?? '';
      throw StateError(
        'command_worker_response_invalid:$code'
        '${message.isEmpty ? '' : ':$message'}',
      );
    }
    final receipt = P2EffectReceipt.fromJson(
      Map<String, Object?>.from(rawReceipt),
    );
    if (receipt.operation != operation ||
        receipt.runId != binding.runId ||
        receipt.taskId != binding.taskId) {
      throw StateError('command_receipt_binding_invalid');
    }
    _lastReceipt = receipt;
    await journal.append(receipt);
    final output = Map<String, Object?>.from(rawOutput);
    final rawIdentity = output['processIdentity'];
    if (rawIdentity is! Map ||
        output['stdoutBase64'] is! String ||
        output['stderrBase64'] is! String) {
      throw StateError('command_worker_output_invalid');
    }
    final stdout = base64Decode(output['stdoutBase64']! as String);
    final stderr = base64Decode(output['stderrBase64']! as String);
    if (stdout.length > spec.maxStdoutBytes ||
        stderr.length > spec.maxStderrBytes) {
      throw StateError('command_worker_output_budget_invalid');
    }
    final exitCode = output['exitCode'];
    if (exitCode != null && exitCode is! int) {
      throw StateError('command_worker_exit_code_invalid');
    }
    return P2CommandResult(
      status: receipt.status,
      exitCode: exitCode as int?,
      stdout: List<int>.unmodifiable(stdout),
      stderr: List<int>.unmodifiable(stderr),
      outputTruncated: output['outputTruncated'] == true,
      processIdentity: P2ProcessIdentity.fromJson(
        Map<String, Object?>.from(rawIdentity),
      ),
    );
  }

  void _validate(P2CommandSpec spec) {
    if (spec.runInShell) {
      throw StateError('shell_requires_explicit_shell_operation');
    }
    if (spec.executable.trim().isEmpty ||
        spec.executable.contains('\u0000') ||
        spec.cwd.trim().isEmpty ||
        spec.cwd.contains('\u0000')) {
      throw StateError('command_path_invalid');
    }
    if (spec.arguments.length > 256 ||
        spec.arguments.any((String value) => value.contains('\u0000'))) {
      throw StateError('command_arguments_invalid');
    }
    if (spec.deadline <= Duration.zero ||
        spec.deadline > const Duration(hours: 24) ||
        spec.maxStdoutBytes < 0 ||
        spec.maxStdoutBytes > 64 * 1024 * 1024 ||
        spec.maxStderrBytes < 0 ||
        spec.maxStderrBytes > 64 * 1024 * 1024 ||
        (spec.stdin?.length ?? 0) > 4 * 1024 * 1024) {
      throw StateError('command_budget_invalid');
    }
    for (final entry in spec.environmentDelta.entries) {
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,127}$').hasMatch(entry.key) ||
          RegExp(
            r'(secret|token|password|credential|api.?key|private.?key)',
            caseSensitive: false,
          ).hasMatch(entry.key) ||
          (entry.value?.contains('\u0000') ?? false)) {
        throw StateError('command_environment_invalid');
      }
    }
  }
}
