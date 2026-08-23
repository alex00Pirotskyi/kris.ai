import 'dart:convert';
import 'dart:io';

import 'crypto_utils.dart';
import 'domain.dart';
import 'execution_intelligence.dart';
import 'retry_policy.dart';

class RunnerAttemptLedgerPolicy {
  const RunnerAttemptLedgerPolicy();

  static const Set<String> _ignoredWorkspaceSegments = <String>{
    '.git',
    '.dart_tool',
    'build',
    'node_modules',
    '.venv',
    'venv',
    '__pycache__',
    '.pytest_cache',
    '.idea',
    '.vscode',
    '.kristin',
    'coverage',
    'dist',
    'target',
  };

  AgentAction? deterministicAction(WorkItem item) {
    if (!item.allowedTools.contains('run_command')) {
      return null;
    }
    final command = _explicitCommand(item.description);
    if (command == null || command.length > 512 || _hasShellControl(command)) {
      return null;
    }
    final tokens = _tokenize(command);
    if (tokens == null || tokens.isEmpty) {
      return null;
    }
    final executable = tokens.first;
    if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(executable)) {
      return null;
    }
    return AgentAction(
      kind: 'tool',
      tool: 'run_command',
      arguments: <String, dynamic>{
        'executable': executable,
        'args': tokens.skip(1).toList(growable: false),
      },
      reason:
          'Deterministic coordinator action parsed from an explicit work-item command instruction.',
    );
  }

  String? _explicitCommand(String description) {
    final normalized = description.trim();
    final patterns = <RegExp>[
      RegExp(
        r"^run\s+(?:the\s+)?command\s+'([^'\r\n]+)'\.?\s*$",
        caseSensitive: false,
      ),
      RegExp(
        r'^run\s+(?:the\s+)?command\s+"([^"\r\n]+)"\.?\s*$',
        caseSensitive: false,
      ),
      RegExp(
        r'^run\s+(?:the\s+)?command\s+`([^`\r\n]+)`\.?\s*$',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(normalized);
      final command = match?.group(1)?.trim() ?? '';
      if (command.isNotEmpty) {
        return command;
      }
    }
    return null;
  }

  bool _hasShellControl(String command) {
    if (command.contains('\n') || command.contains('\r')) {
      return true;
    }
    return const <String>['&&', '||', ';', '|', '>', '<', '`', r'$(', r'${']
        .any(command.contains);
  }

  List<String>? _tokenize(String command) {
    final tokens = <String>[];
    final current = StringBuffer();
    String? quote;
    var escaping = false;

    void flush() {
      if (current.length == 0) {
        return;
      }
      tokens.add(current.toString());
      current.clear();
    }

    for (var index = 0; index < command.length; index++) {
      final character = command[index];
      if (escaping) {
        current.write(character);
        escaping = false;
        continue;
      }
      if (character == '\\') {
        escaping = true;
        continue;
      }
      if (quote != null) {
        if (character == quote) {
          quote = null;
        } else {
          current.write(character);
        }
        continue;
      }
      if (character == "'" || character == '"') {
        quote = character;
        continue;
      }
      if (RegExp(r'\s').hasMatch(character)) {
        flush();
        continue;
      }
      current.write(character);
    }
    if (quote != null || escaping) {
      return null;
    }
    flush();
    return tokens;
  }

  Map<String, dynamic> actionJson(AgentAction action) => <String, dynamic>{
        'action': action.kind,
        if (action.tool != null) 'tool': action.tool,
        if (action.arguments.isNotEmpty) 'arguments': action.arguments,
        if (action.reason.trim().isNotEmpty) 'reason': action.reason,
        if (action.summary.trim().isNotEmpty) 'summary': action.summary,
      };

  String actionSha256(AgentAction action) => Sha256.text(
        canonicalJson(<String, dynamic>{
          'action': action.kind,
          if (action.tool != null) 'tool': action.tool,
          if (action.arguments.isNotEmpty) 'arguments': action.arguments,
          if (action.kind != 'tool' && action.summary.trim().isNotEmpty)
            'summary': action.summary.trim(),
        }),
      );

  String decisionSha256(String text) {
    var candidate = text.trim();
    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(candidate);
    if (fenced != null) {
      candidate = fenced.group(1)?.trim() ?? candidate;
    }
    try {
      final decoded = jsonDecode(candidate);
      return Sha256.text(canonicalJson(decoded));
    } catch (_) {
      return Sha256.text(candidate.replaceAll(RegExp(r'\s+'), ' ').trim());
    }
  }

  Future<String> workspaceSha256(
    Directory root, {
    int maxFiles = 25000,
    int maxFileBytes = 2 * 1024 * 1024,
  }) async {
    final absoluteRoot = root.absolute;
    if (!await absoluteRoot.exists()) {
      throw ProductException(
        'attempt_ledger_workspace_missing',
        'The active project root is unavailable for state fingerprinting.',
      );
    }
    final entries = <String>[];
    var fileCount = 0;

    Future<void> visit(Directory directory, String prefix) async {
      await for (final entity in directory.list(followLinks: false)) {
        final name = entity.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last;
        final relative = prefix.isEmpty ? name : '$prefix/$name';
        if (entity is Directory) {
          if (_ignoredWorkspaceSegments.contains(name)) {
            continue;
          }
          await visit(entity, relative);
          continue;
        }
        if (entity is! File) {
          continue;
        }
        if (++fileCount > maxFiles) {
          throw ProductException(
            'attempt_ledger_workspace_limit',
            'The project exceeds the bounded runner state fingerprint limit.',
            details: <String, dynamic>{'limit': maxFiles},
          );
        }
        final stat = await entity.stat();
        if (stat.size > maxFileBytes) {
          entries.add('$relative:oversize:${stat.size}');
          continue;
        }
        final bytes = await entity.readAsBytes();
        entries.add('$relative:${Sha256.hex(bytes)}');
      }
    }

    await visit(absoluteRoot, '');
    entries.sort();
    return Sha256.text(canonicalJson(entries));
  }

  Iterable<Map<String, dynamic>> _prunableBranches(
    Iterable<Map<String, dynamic>> branches,
  ) sync* {
    const taxonomy = WorkflowRetryTaxonomy();
    for (final branch in branches) {
      final outcome = branch['outcome']?.toString() ?? '';
      if (outcome == 'tool_error' || outcome == 'deterministic_error') {
        final errorCode = branch['errorCode']?.toString() ?? '';
        final retryability = taxonomy.classify(errorCode).retryability;
        if (retryability == 'transient' ||
            retryability == 'resource' ||
            retryability == 'state_conflict') {
          continue;
        }
      }
      yield branch;
    }
  }

  Set<String> closedActionHashes(Iterable<Map<String, dynamic>> branches) =>
      _prunableBranches(branches)
          .map((branch) => branch['actionSha256']?.toString() ?? '')
          .where((hash) => hash.length == 64)
          .toSet();

  Set<String> closedDecisionHashes(Iterable<Map<String, dynamic>> branches) =>
      _prunableBranches(branches)
          .map((branch) => branch['decisionSha256']?.toString() ?? '')
          .where((hash) => hash.length == 64)
          .toSet();

  String closedBranchPrompt(Iterable<Map<String, dynamic>> branches) {
    final rows = _prunableBranches(branches).take(5).toList(growable: false);
    if (rows.isEmpty) {
      return '';
    }
    final lines = <String>[];
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final action = row['action'];
      final outcome = row['outcome']?.toString() ?? 'rejected';
      final errorCode = row['errorCode']?.toString() ?? '';
      final label = action is Map && action.isNotEmpty
          ? jsonEncode(action)
          : 'invalid model decision ${row['decisionSha256']}';
      lines.add(
        '${index + 1}. $label -> $outcome${errorCode.isEmpty ? '' : ' ($errorCode)'}',
      );
    }
    return lines.join('\n');
  }

  String worldStateSha256(
    SemanticProgressSnapshot snapshot, {
    required int mutationEpoch,
    String workspaceSha256 = '',
  }) {
    final artifacts = snapshot.artifacts.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final satisfiedCriteria = snapshot.satisfiedCriteria.toList()..sort();
    final externalState = snapshot.externalState.toList()..sort();
    return Sha256.text(
      canonicalJson(<String, dynamic>{
        'workspaceSha256': workspaceSha256,
        'artifacts': <String, String>{
          for (final entry in artifacts) entry.key: entry.value,
        },
        'satisfiedCriteria': satisfiedCriteria,
        'externalState': externalState,
        'planHash': snapshot.planHash,
        'mutationEpoch': mutationEpoch,
      }),
    );
  }

  bool hasMaterialProgress(SemanticProgressDelta delta) =>
      delta.newArtifacts.isNotEmpty ||
      delta.changedArtifactHashes.isNotEmpty ||
      delta.resolvedErrors.isNotEmpty ||
      delta.criteriaSatisfied.isNotEmpty ||
      delta.newExternalState.isNotEmpty ||
      delta.planRevised;
}
