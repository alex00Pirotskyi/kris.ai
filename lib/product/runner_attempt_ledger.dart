import 'dart:convert';

import 'crypto_utils.dart';
import 'domain.dart';
import 'execution_intelligence.dart';

class RunnerAttemptLedgerPolicy {
  const RunnerAttemptLedgerPolicy();

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
    final patterns = <RegExp>[
      RegExp(
        r"\brun\s+(?:the\s+)?command\s+'([^'\r\n]+)'",
        caseSensitive: false,
      ),
      RegExp(
        r'\brun\s+(?:the\s+)?command\s+"([^"\r\n]+)"',
        caseSensitive: false,
      ),
      RegExp(
        r'\brun\s+(?:the\s+)?command\s+`([^`\r\n]+)`',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(description);
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
      if (current.isEmpty) {
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
      if (character == r'\') {
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

  Set<String> closedActionHashes(Iterable<Map<String, dynamic>> branches) =>
      branches
          .map((branch) => branch['actionSha256']?.toString() ?? '')
          .where((hash) => hash.length == 64)
          .toSet();

  Set<String> closedDecisionHashes(Iterable<Map<String, dynamic>> branches) =>
      branches
          .map((branch) => branch['decisionSha256']?.toString() ?? '')
          .where((hash) => hash.length == 64)
          .toSet();

  String closedBranchPrompt(Iterable<Map<String, dynamic>> branches) {
    final rows = branches.take(5).toList(growable: false);
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
  }) {
    final artifacts = snapshot.artifacts.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final satisfiedCriteria = snapshot.satisfiedCriteria.toList()..sort();
    final externalState = snapshot.externalState.toList()..sort();
    return Sha256.text(
      canonicalJson(<String, dynamic>{
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
