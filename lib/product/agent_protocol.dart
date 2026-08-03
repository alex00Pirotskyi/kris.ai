import 'dart:convert';

import 'agent_decision.dart';
import 'domain.dart';
import 'protocol_types.dart';
import 'storage_security.dart';
import 'tool_schema.dart';
import 'workspace_tools.dart';

enum AgentProviderProtocol { auto, ollama, openAiCompatible, mcp, recorded }

abstract interface class AgentProviderAdapter {
  AgentProviderProtocol get protocol;

  Iterable<Object?> unwrap(Object? envelope);
}

class OllamaAgentProviderAdapter implements AgentProviderAdapter {
  const OllamaAgentProviderAdapter();

  @override
  AgentProviderProtocol get protocol => AgentProviderProtocol.ollama;

  @override
  Iterable<Object?> unwrap(Object? envelope) sync* {
    final root = _providerMap(envelope);
    if (root.isEmpty) return;
    final message = _providerMap(root['message']);
    if (message.isNotEmpty) {
      yield message;
      yield message['content'];
      yield message['tool_calls'];
    }
    yield root['response'];
    yield root['output'];
  }
}

class OpenAiCompatibleAgentProviderAdapter implements AgentProviderAdapter {
  const OpenAiCompatibleAgentProviderAdapter();

  @override
  AgentProviderProtocol get protocol => AgentProviderProtocol.openAiCompatible;

  @override
  Iterable<Object?> unwrap(Object? envelope) sync* {
    final root = _providerMap(envelope);
    if (root.isEmpty) return;
    final choices = root['choices'];
    if (choices is List) {
      for (final choice in choices.take(8)) {
        final mapped = _providerMap(choice);
        yield mapped['message'];
        yield mapped['delta'];
        yield mapped['text'];
      }
    }
    yield root['message'];
    yield root['output'];
    yield root['response'];
  }
}

class McpAgentProviderAdapter implements AgentProviderAdapter {
  const McpAgentProviderAdapter();

  @override
  AgentProviderProtocol get protocol => AgentProviderProtocol.mcp;

  @override
  Iterable<Object?> unwrap(Object? envelope) sync* {
    final root = _providerMap(envelope);
    if (root.isEmpty) return;
    yield root['structuredContent'];
    yield root['structured_content'];
    yield root['result'];
    final content = root['content'];
    if (content is List) {
      for (final part in content.take(16)) {
        final mapped = _providerMap(part);
        yield mapped['text'];
        yield mapped['json'];
        yield mapped['data'];
      }
    } else {
      yield content;
    }
  }
}

class RecordedAgentProviderAdapter implements AgentProviderAdapter {
  const RecordedAgentProviderAdapter();

  @override
  AgentProviderProtocol get protocol => AgentProviderProtocol.recorded;

  @override
  Iterable<Object?> unwrap(Object? envelope) sync* {
    final root = _providerMap(envelope);
    if (root.isEmpty) return;
    for (final key in const <String>[
      'normalizedAction',
      'normalized_action',
      'decision',
      'modelResponse',
      'model_response',
      'response',
      'output',
      'result',
    ]) {
      yield root[key];
    }
  }
}

const List<AgentProviderAdapter> _allProviderAdapters = <AgentProviderAdapter>[
  OllamaAgentProviderAdapter(),
  OpenAiCompatibleAgentProviderAdapter(),
  McpAgentProviderAdapter(),
  RecordedAgentProviderAdapter(),
];

Iterable<AgentProviderAdapter> providerAdapters(
  AgentProviderProtocol provider,
) => provider == AgentProviderProtocol.auto
    ? _allProviderAdapters
    : _allProviderAdapters.where((adapter) => adapter.protocol == provider);

Map<String, dynamic> _providerMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

class AgentProtocolAdapter {
  const AgentProtocolAdapter({
    this.toolSchemas = const ToolSchemaRegistry(),
    this.decisionCodec = const AgentDecisionCodec(),
  });

  final ToolSchemaRegistry toolSchemas;
  final AgentDecisionCodec decisionCodec;

  static const Map<String, List<String>> _toolAliases = <String, List<String>>{
    'browse_url': <String>['research_fetch'],
    'build_and_test': <String>['verify_project'],
    'create_file': <String>['write_file'],
    'delete': <String>['delete_file'],
    'delete_path': <String>['delete_file'],
    'diff': <String>['git_diff'],
    'edit': <String>['replace_text'],
    'edit_file': <String>['replace_text'],
    'execute': <String>['run_command'],
    'execute_command': <String>['run_command'],
    'explore': <String>['list_directory'],
    'explore_project': <String>['list_directory'],
    'fetch': <String>['research_fetch'],
    'fetch_url': <String>['research_fetch'],
    'file_info': <String>['inspect_file'],
    'find_text': <String>['search_text', 'index_search'],
    'grep': <String>['search_text'],
    'index': <String>['index_project'],
    'inspect': <String>['list_directory'],
    'inspect_directory': <String>['list_directory'],
    'inspect_path': <String>['inspect_file'],
    'inspect_project': <String>['list_directory'],
    'inspect_workspace': <String>['list_directory'],
    'internet_search': <String>['research_search'],
    'kill_process': <String>['stop_process'],
    'launch': <String>['start_process'],
    'list': <String>['list_directory'],
    'list_dir': <String>['list_directory'],
    'list_files': <String>['list_directory'],
    'list_project': <String>['list_directory'],
    'list_project_files': <String>['list_directory'],
    'list_folder': <String>['list_directory'],
    'ls': <String>['list_directory'],
    'memory_search': <String>['knowledge_search'],
    'modify_file': <String>['replace_text'],
    'open': <String>['read_file'],
    'open_file': <String>['read_file'],
    'patch': <String>['apply_patch'],
    'patch_file': <String>['apply_patch'],
    'process_info': <String>['process_status'],
    'project_inspection': <String>['list_directory'],
    'read': <String>['read_file'],
    'read_text': <String>['read_file'],
    'read_project_file': <String>['read_file'],
    'read_text_file': <String>['read_file'],
    'remove_file': <String>['delete_file'],
    'replace': <String>['replace_text'],
    'replace_file': <String>['replace_text'],
    'retrieve_knowledge': <String>['knowledge_search'],
    'run': <String>['run_command'],
    'run_process': <String>['run_command'],
    'run_tests': <String>['verify_project'],
    'save_file': <String>['write_file'],
    'scan_directory': <String>['list_directory'],
    'scan_project': <String>['index_project'],
    'search': <String>['search_text', 'index_search'],
    'search_files': <String>['search_text'],
    'search_knowledge': <String>['knowledge_search'],
    'search_project': <String>['search_text', 'index_search'],
    'search_web': <String>['research_search'],
    'start': <String>['start_process'],
    'start_server': <String>['start_process'],
    'status_process': <String>['process_status'],
    'stop': <String>['stop_process'],
    'terminate_process': <String>['stop_process'],
    'test': <String>['verify_project'],
    'validate_project': <String>['verify_project'],
    'verify': <String>['verify_project'],
    'view_file': <String>['read_file'],
    'web_fetch': <String>['research_fetch'],
    'web_search': <String>['research_search'],
    'write': <String>['write_file'],
    'write_text': <String>['write_file'],
  };

  static const Set<String> _pathTools = <String>{
    'list_directory',
    'read_file',
    'inspect_file',
    'search_text',
    'write_file',
    'write_binary_file',
    'replace_text',
    'apply_patch',
    'delete_file',
  };

  AgentAction parse(
    String text, {
    required WorkItem item,
    required bool allowPlainCompletion,
    AgentProviderProtocol provider = AgentProviderProtocol.auto,
  }) => parseDecision(
    text,
    item: item,
    allowPlainCompletion: allowPlainCompletion,
    provider: provider,
    allowedKinds: const <AgentDecisionKind>{
      AgentDecisionKind.tool,
      AgentDecisionKind.complete,
      AgentDecisionKind.fail,
    },
  ).toLegacyAction();

  AgentDecision parseDecision(
    String text, {
    required WorkItem item,
    required bool allowPlainCompletion,
    AgentProviderProtocol provider = AgentProviderProtocol.auto,
    Set<AgentDecisionKind> allowedKinds = const <AgentDecisionKind>{
      AgentDecisionKind.tool,
      AgentDecisionKind.complete,
      AgentDecisionKind.fail,
      AgentDecisionKind.askUser,
      AgentDecisionKind.delegate,
    },
  }) {
    final trimmed = text.trim();
    final direct = _directJsonMap(trimmed);
    final canonicalCandidates = <Map<String, dynamic>>[
      if (direct != null) direct,
      ..._jsonCandidates(trimmed, provider: provider),
    ];
    final seenCanonicalCandidates = <String>{};
    AgentDecision? typedDecision;
    AgentDecisionException? canonicalDecisionError;
    for (final candidate in canonicalCandidates) {
      final fingerprint = jsonEncode(candidate);
      if (!seenCanonicalCandidates.add(fingerprint)) {
        continue;
      }
      final action = candidate['action']?.toString() ?? '';
      if (!const <String>{
        'complete',
        'fail',
        'ask_user',
        'delegate',
      }.contains(action)) {
        continue;
      }
      try {
        typedDecision = decisionCodec.decodeCanonical(candidate);
        break;
      } on AgentDecisionException catch (error) {
        // Canonical complete/fail decisions may still be legacy-compatible
        // (for example, `answer` instead of `summary`). Future-only
        // ask_user/delegate decisions have no safe legacy representation, so
        // retain their precise schema error if compatibility parsing fails.
        if (const <String>{'ask_user', 'delegate'}.contains(action)) {
          canonicalDecisionError ??= error;
        }
      }
    }

    AgentDecision decision;
    if (typedDecision != null) {
      decision = typedDecision;
    } else {
      try {
        final legacy = _parseLegacyAction(
          text,
          item: item,
          allowPlainCompletion: allowPlainCompletion,
          provider: provider,
        );
        decision = AgentDecision.fromLegacy(legacy);
      } on ProductException {
        if (canonicalDecisionError != null) {
          throw canonicalDecisionError;
        }
        rethrow;
      }
    }
    if (!allowedKinds.contains(decision.kind)) {
      throw AgentDecisionException(
        code: 'model_decision_not_supported',
        message:
            'Decision ${decision.kind.wireName} is not supported in this workflow phase.',
        retryability: Retryability.modelCorrection,
        details: <String, dynamic>{
          'receivedAction': decision.kind.wireName,
          'allowedDecisionKinds':
              allowedKinds.map((kind) => kind.wireName).toList()..sort(),
        },
      );
    }
    if (decision case ToolDecision toolDecision) {
      if (!item.allowedTools.contains(toolDecision.tool)) {
        throw AgentDecisionException(
          code: 'model_tool_not_allowed',
          message: 'The requested tool is not allowed for this work item.',
          retryability: Retryability.modelCorrection,
          details: <String, dynamic>{
            'requestedTool': toolDecision.tool,
            'allowedTools': item.allowedTools.toList()..sort(),
          },
        );
      }
      final normalized = toolSchemas.normalizeAndValidate(
        toolDecision.tool,
        toolDecision.arguments,
      );
      final compatibilityReason = normalized.changed
          ? <String>[
              toolDecision.reason.trim(),
              'Schema compatibility normalization: '
                  '${normalized.changes.map((change) => '${change.kind}:${change.source ?? '-'}->${change.target}').join(', ')}.',
            ].where((value) => value.isNotEmpty).join(' ')
          : toolDecision.reason;
      decision = toolDecision.copyWith(
        arguments: normalized.arguments,
        reason: compatibilityReason,
      );
    }
    return decisionCodec.decodeCanonical(decision.toJson());
  }

  AgentAction _parseLegacyAction(
    String text, {
    required WorkItem item,
    required bool allowPlainCompletion,
    required AgentProviderProtocol provider,
  }) {
    final trimmed = text.trim();
    final direct = _directJsonMap(trimmed);
    if (direct != null && _hasDirectDecision(direct)) {
      final parsed = AgentAction.fromJson(direct);
      final normalized = _normalizeAction(parsed, direct, item);
      return _validate(normalized, item);
    }

    final candidates = _jsonCandidates(trimmed, provider: provider);
    ProductException? bestError;
    for (final candidate in candidates) {
      try {
        final parsed = AgentAction.fromJson(candidate);
        final normalized = _normalizeAction(parsed, candidate, item);
        return _validate(normalized, item);
      } on ProductException catch (error) {
        bestError = _preferError(bestError, error);
      }
    }

    final legacy = _legacyAction(trimmed, item);
    if (legacy != null) {
      try {
        return _validate(legacy, item);
      } on ProductException catch (error) {
        bestError = _preferError(bestError, error);
      }
    }

    if (allowPlainCompletion &&
        trimmed.isNotEmpty &&
        !trimmed.startsWith('{') &&
        !trimmed.startsWith('[')) {
      return AgentAction(kind: 'complete', summary: trimmed);
    }

    if (bestError != null) {
      throw ProductException(
        bestError.code,
        bestError.message,
        details: <String, dynamic>{
          ...bestError.details,
          'candidateCount': candidates.length,
          'candidateKeys': candidates
              .take(5)
              .map((candidate) => candidate.keys.take(12).toList())
              .toList(),
        },
      );
    }
    throw ProductException(
      'model_json_invalid',
      'The model did not return a valid JSON action.',
      details: <String, dynamic>{'candidateCount': candidates.length},
    );
  }

  Map<String, dynamic>? _directJsonMap(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? mapValue(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  bool _hasDirectDecision(Map<String, dynamic> value) {
    if (value.keys.any(
      const <String>{
        'action',
        'kind',
        'operation',
        'act',
        'tool',
        'toolName',
        'tool_name',
        'tool_calls',
        'toolCalls',
        'tool_call',
        'toolCall',
        'function_call',
        'functionCall',
        'function',
      }.contains,
    )) {
      return true;
    }
    final type = _token(value['type']?.toString() ?? '');
    if (const <String>{
      'tool',
      'tool_call',
      'function',
      'function_call',
      'complete',
      'completed',
      'final',
      'final_answer',
      'fail',
      'failed',
      'error',
    }.contains(type)) {
      return true;
    }
    return value.containsKey('name') &&
        value.keys.any(
          const <String>{
            'arguments',
            'args',
            'parameters',
            'params',
            'input',
            'tool_input',
            'action_input',
          }.contains,
        );
  }

  AgentAction _validate(AgentAction action, WorkItem item) {
    if (action.kind == 'tool') {
      final tool = action.tool?.trim() ?? '';
      if (tool.isEmpty) {
        throw ProductException(
          'model_action_invalid',
          'A tool action requires a tool name.',
        );
      }
      if (!item.allowedTools.contains(tool)) {
        throw ProductException(
          'model_tool_not_allowed',
          'The requested tool is not allowed for this work item.',
          details: <String, dynamic>{
            'requestedTool': tool,
            'allowedTools': item.allowedTools.toList()..sort(),
          },
        );
      }
      return action;
    }
    if (action.kind == 'complete') {
      if (action.summary.trim().isEmpty) {
        throw ProductException(
          'model_completion_invalid',
          'A completion action requires a non-empty summary.',
        );
      }
      return action;
    }
    if (action.kind == 'fail') {
      if (action.summary.trim().isEmpty && action.reason.trim().isEmpty) {
        throw ProductException(
          'model_action_invalid',
          'A failure action requires a summary or reason.',
        );
      }
      return action;
    }
    throw ProductException(
      'model_action_invalid',
      'The model must return action=tool, complete, or fail.',
      details: <String, dynamic>{'receivedAction': action.kind},
    );
  }

  AgentAction _normalizeAction(
    AgentAction action,
    Map<String, dynamic> candidate,
    WorkItem item,
  ) {
    final allowedTools = item.allowedTools;
    var kind = _token(action.kind);
    var tool = action.tool?.trim();

    final kindAsTool = _resolveTool(kind, allowedTools);
    final explicitTool = _resolveTool(tool ?? '', allowedTools);
    final taskIntentTool = _resolveTaskIntent(kind, item);
    if (kind != 'complete' && kind != 'fail' && explicitTool != null) {
      tool = explicitTool;
      kind = 'tool';
    } else if (kind != 'tool' &&
        kind != 'complete' &&
        kind != 'fail' &&
        kindAsTool != null) {
      tool = kindAsTool;
      kind = 'tool';
    } else if (kind != 'tool' &&
        kind != 'complete' &&
        kind != 'fail' &&
        taskIntentTool != null) {
      tool = taskIntentTool;
      kind = 'tool';
    }
    if (kind == 'tool') {
      tool = _resolveTool(tool ?? '', allowedTools) ?? tool;
    } else if (kind != 'complete' &&
        kind != 'fail' &&
        action.summary.trim().isNotEmpty &&
        _hasCompletionSignal(candidate)) {
      kind = 'complete';
    }

    var arguments = _normalizeArguments(
      tool,
      action.arguments,
      candidate,
      item,
    );
    final specialization = _specializeCommandTool(tool, arguments, item);
    tool = specialization.tool;
    arguments = specialization.arguments;
    final baseCompatibilityReason =
        action.reason.trim().isEmpty &&
            kind == 'tool' &&
            taskIntentTool != null &&
            tool == taskIntentTool
        ? 'Compatibility normalization: interpreted a noncanonical planning action as the safest allowlisted evidence tool for this work item.'
        : action.reason;
    final compatibilityReason = <String>[
      baseCompatibilityReason.trim(),
      specialization.reason.trim(),
    ].where((value) => value.isNotEmpty).join(' ');
    return AgentAction(
      kind: kind,
      tool: tool,
      arguments: arguments,
      reason: compatibilityReason,
      summary: action.summary,
    );
  }

  String? _resolveTaskIntent(String value, WorkItem item) {
    final normalized = _token(value);
    if (!RegExp(
      r'^(?:inspect|gather|collect|research|search|review|analy[sz]e|establish|explore|prepare|plan)(?:_|$)',
    ).hasMatch(normalized)) {
      return null;
    }
    final label = '${item.title} ${item.description}'.toLowerCase();
    final informationTask = RegExp(
      r'\b(?:research|online|web|documentation|information|requirements?|specifications?|frameworks?|libraries|tools)\b',
    ).hasMatch(label);
    if (informationTask && item.allowedTools.contains('knowledge_search')) {
      return 'knowledge_search';
    }
    if ((normalized.contains('inspect_project') ||
            normalized.contains('evidence_baseline') ||
            normalized.startsWith('explore')) &&
        item.allowedTools.contains('list_directory')) {
      return 'list_directory';
    }
    if (item.allowedTools.contains('knowledge_search') &&
        RegExp(
          r'^(?:gather|collect|research|review|analy[sz]e)',
        ).hasMatch(normalized)) {
      return 'knowledge_search';
    }
    if (item.allowedTools.contains('list_directory') &&
        RegExp(r'^(?:inspect|explore|establish)').hasMatch(normalized)) {
      return 'list_directory';
    }
    return null;
  }

  String? _resolveTool(String value, Set<String> allowedTools) {
    final normalized = _token(value);
    if (normalized.isEmpty) {
      return null;
    }
    final exact = <String, String>{
      for (final tool in allowedTools) _token(tool): tool,
    };
    if (exact.containsKey(normalized)) {
      return exact[normalized];
    }
    for (final prefix in const <String>[
      'function_',
      'functions_',
      'tool_',
      'tools_',
      'call_',
      'invoke_',
      'use_',
    ]) {
      if (normalized.startsWith(prefix)) {
        final stripped = normalized.substring(prefix.length);
        if (exact.containsKey(stripped)) {
          return exact[stripped];
        }
      }
    }
    for (final suffix in const <String>['_function', '_tool', '_call']) {
      if (normalized.endsWith(suffix)) {
        final stripped = normalized.substring(
          0,
          normalized.length - suffix.length,
        );
        if (exact.containsKey(stripped)) {
          return exact[stripped];
        }
      }
    }
    final embedded = exact.entries
        .where(
          (entry) =>
              normalized.startsWith('${entry.key}_') ||
              normalized.endsWith('_${entry.key}'),
        )
        .map((entry) => entry.value)
        .toSet();
    if (embedded.length == 1) {
      return embedded.single;
    }
    final aliases = _toolAliases[normalized] ?? const <String>[];
    final matches = aliases.where(allowedTools.contains).toSet();
    if (matches.length == 1) {
      return matches.single;
    }
    return null;
  }

  bool _hasCompletionSignal(Map<String, dynamic> candidate) {
    if (candidate['done'] == true ||
        candidate['completed'] == true ||
        candidate['success'] == true ||
        candidate['finished'] == true) {
      return true;
    }
    final status = _token(candidate['status']?.toString() ?? '');
    return const <String>{
      'complete',
      'completed',
      'done',
      'finished',
      'success',
      'succeeded',
      'ok',
    }.contains(status);
  }

  Map<String, dynamic> _normalizeArguments(
    String? tool,
    Map<String, dynamic> original,
    Map<String, dynamic> candidate,
    WorkItem item,
  ) {
    final arguments = Map<String, dynamic>.from(original);
    final toolCalls = candidate['tool_calls'] is List
        ? candidate['tool_calls'] as List
        : candidate['toolCalls'] is List
        ? candidate['toolCalls'] as List
        : const <Object>[];
    final firstToolCall = toolCalls.whereType<Map>().firstOrNull;
    final containers = <Map<String, dynamic>>[
      candidate,
      mapValue(candidate['action']),
      mapValue(candidate['tool']),
      mapValue(candidate['function']),
      mapValue(candidate['function_call']),
      mapValue(candidate['functionCall']),
      mapValue(candidate['tool_call']),
      mapValue(candidate['toolCall']),
      mapValue(firstToolCall),
      mapValue(mapValue(firstToolCall)['function']),
    ];
    for (final container in containers) {
      for (final key in const <String>[
        'arguments',
        'args',
        'parameters',
        'params',
        'input',
        'toolInput',
        'tool_input',
        'actionInput',
        'action_input',
        'payload',
      ]) {
        final value = container[key];
        if (value is Map) {
          for (final entry in mapValue(value).entries) {
            arguments.putIfAbsent(entry.key, () => entry.value);
          }
        }
      }
    }

    Object? firstValue(Iterable<String> keys) {
      for (final key in keys) {
        final direct = arguments[key];
        if (direct != null && direct.toString().trim().isNotEmpty) {
          return direct;
        }
        Object? value;
        for (final container in containers) {
          final candidateValue = container[key];
          if (candidateValue != null &&
              candidateValue.toString().trim().isNotEmpty) {
            value = candidateValue;
            break;
          }
        }
        if (value != null && value.toString().trim().isNotEmpty) {
          return value;
        }
      }
      return null;
    }

    void alias(String target, Iterable<String> keys) {
      if (arguments[target] != null &&
          arguments[target].toString().trim().isNotEmpty) {
        return;
      }
      final value = firstValue(keys);
      if (value != null) {
        arguments[target] = value;
      }
    }

    if (tool != null && _pathTools.contains(tool)) {
      alias('path', const <String>[
        'path',
        'file',
        'filePath',
        'file_path',
        'filepath',
        'filename',
        'target',
        'targetPath',
        'target_path',
        'directory',
        'dir',
        'folder',
      ]);
      final scalarInput = firstValue(const <String>[
        'actionInput',
        'action_input',
        'toolInput',
        'tool_input',
        'input',
      ]);
      if ((arguments['path'] == null ||
              arguments['path'].toString().trim().isEmpty) &&
          scalarInput is! Map &&
          scalarInput is! List &&
          scalarInput != null) {
        arguments['path'] = scalarInput.toString();
      }
      final path = arguments['path'];
      if (path != null && path is! Map && path is! List) {
        arguments['path'] = canonicalModelPathToken(path.toString());
      }
    }

    if (const <String>{
      'search_text',
      'index_search',
      'knowledge_search',
      'research_search',
    }.contains(tool)) {
      alias('query', const <String>[
        'query',
        'search',
        'searchQuery',
        'search_query',
        'term',
        'pattern',
      ]);
    }
    if (tool == 'research_fetch') {
      alias('url', const <String>[
        'url',
        'uri',
        'link',
        'sourceUrl',
        'source_url',
      ]);
    }
    if (tool == 'write_file') {
      alias('content', const <String>[
        'content',
        'text',
        'body',
        'fileContent',
        'file_content',
        'newContent',
        'new_content',
      ]);
    }
    if (tool == 'write_binary_file') {
      alias('base64', const <String>[
        'base64',
        'contentBase64',
        'content_base64',
        'data',
        'body',
      ]);
    }
    if (const <String>{'replace_text', 'apply_patch'}.contains(tool)) {
      alias('old', const <String>['old', 'oldText', 'old_text', 'find']);
      alias('replacement', const <String>[
        'replacement',
        'new',
        'newText',
        'new_text',
        'replaceWith',
        'replace_with',
      ]);
    }
    if (const <String>{
      'write_file',
      'write_binary_file',
      'replace_text',
      'apply_patch',
      'delete_file',
    }.contains(tool)) {
      alias('expectedSha256', const <String>[
        'expectedSha256',
        'expected_sha256',
        'expectedHash',
        'expected_hash',
        'sha256',
      ]);
    }
    if (const <String>{'run_command', 'start_process'}.contains(tool)) {
      alias('executable', const <String>['executable', 'program', 'binary']);
      alias('args', const <String>[
        'args',
        'argv',
        'commandArgs',
        'command_args',
      ]);
      final command = firstValue(const <String>['command']);
      var consumedCommandCompatibility = false;
      if ((arguments['executable'] == null ||
              arguments['executable'].toString().trim().isEmpty) &&
          command is List &&
          command.isNotEmpty) {
        arguments['executable'] = command.first.toString();
        arguments['args'] = command.skip(1).map((item) => '$item').toList();
        consumedCommandCompatibility = true;
      } else if ((arguments['executable'] == null ||
              arguments['executable'].toString().trim().isEmpty) &&
          command is String &&
          command.trim().isNotEmpty &&
          !RegExp(r'\s').hasMatch(command.trim())) {
        arguments['executable'] = command.trim();
        consumedCommandCompatibility = true;
      }
      if (consumedCommandCompatibility) {
        arguments.remove('command');
      }
    }
    if (const <String>{'process_status', 'stop_process'}.contains(tool)) {
      alias('processId', const <String>['processId', 'process_id', 'id']);
    }
    if (tool == 'research_search') {
      alias('secretReferenceId', const <String>[
        'secretReferenceId',
        'secret_reference_id',
        'secretRef',
        'secret_ref',
        'apiKeyReferenceId',
        'api_key_reference_id',
      ]);
    }
    if (tool == 'list_directory' &&
        (arguments['path'] == null ||
            arguments['path'].toString().trim().isEmpty)) {
      arguments['path'] = '.';
    }
    if (const <String>{'knowledge_search', 'research_search'}.contains(tool) &&
        (arguments['query'] == null ||
            arguments['query'].toString().trim().isEmpty)) {
      arguments['query'] = _taskQuery(item);
    }
    if (tool == 'knowledge_search') {
      arguments.putIfAbsent('includeEpisodes', () => true);
      arguments.putIfAbsent('includeUnsuccessfulEpisodes', () => false);
    }
    return arguments;
  }

  ({String? tool, Map<String, dynamic> arguments, String reason})
  _specializeCommandTool(
    String? tool,
    Map<String, dynamic> arguments,
    WorkItem item,
  ) {
    if (!const <String>{'run_command', 'start_process'}.contains(tool)) {
      return (tool: tool, arguments: arguments, reason: '');
    }
    final executable = arguments['executable']?.toString().trim() ?? '';
    final basename = executable
        .replaceAll('\\', '/')
        .split('/')
        .last
        .toLowerCase();
    final commandArguments = stringList(arguments['args'])
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (basename == 'git' || basename == 'git.exe') {
      final tokens = commandArguments.map(_token).toSet();
      if (tokens.contains('status') &&
          item.allowedTools.contains('git_status')) {
        return (
          tool: 'git_status',
          arguments: <String, dynamic>{},
          reason:
              'Compatibility normalization: replaced a model-generated git status process command with the project-scoped git_status tool. Any model-supplied working-directory override was ignored.',
        );
      }
      if (tokens.contains('diff') && item.allowedTools.contains('git_diff')) {
        return (
          tool: 'git_diff',
          arguments: <String, dynamic>{},
          reason:
              'Compatibility normalization: replaced a model-generated git diff process command with the project-scoped git_diff tool. Any model-supplied working-directory override was ignored.',
        );
      }
    }
    return (tool: tool, arguments: arguments, reason: '');
  }

  String _taskQuery(WorkItem item) {
    final normalized = '${item.title}. ${item.description}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized.length <= 800 ? normalized : normalized.substring(0, 800);
  }

  AgentAction? _legacyAction(String text, WorkItem item) {
    final allowedTools = item.allowedTools;
    final finalAnswer = RegExp(
      r'(?:^|\n)\s*(?:final answer|final response|answer)\s*:\s*(.+)$',
      caseSensitive: false,
      multiLine: true,
      dotAll: true,
    ).firstMatch(text);
    if (finalAnswer != null && finalAnswer.group(1)!.trim().isNotEmpty) {
      return AgentAction(
        kind: 'complete',
        summary: finalAnswer.group(1)!.trim(),
      );
    }

    final actionMatch = RegExp(
      r'(?:^|\n)\s*(?:action|tool|function)\s*:\s*([A-Za-z0-9_.-]+)',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(text);
    if (actionMatch == null) {
      return null;
    }
    final requested = actionMatch.group(1) ?? '';
    final tool = _resolveTool(requested, allowedTools) ?? requested;
    final inputMatch = RegExp(
      r'(?:^|\n)\s*(?:action input|tool input|arguments?|parameters?)\s*:\s*(.+)$',
      caseSensitive: false,
      multiLine: true,
      dotAll: true,
    ).firstMatch(text);
    final input = inputMatch?.group(1)?.trim() ?? '';
    Map<String, dynamic> arguments = <String, dynamic>{};
    if (input.isNotEmpty) {
      try {
        final decoded = jsonDecode(input);
        if (decoded is Map) {
          arguments = mapValue(decoded);
        }
      } catch (_) {
        arguments = <String, dynamic>{'action_input': input};
      }
    }
    return _normalizeAction(
      AgentAction(kind: 'tool', tool: tool, arguments: arguments),
      <String, dynamic>{'action_input': input},
      item,
    );
  }

  List<Map<String, dynamic>> _jsonCandidates(
    String text, {
    required AgentProviderProtocol provider,
  }) {
    final candidates = <Map<String, dynamic>>[];
    final fingerprints = <String>{};

    void addMap(Map<String, dynamic> value) {
      if (candidates.length >= 24) {
        return;
      }
      final score = _candidateScore(value);
      if (score <= 0) {
        return;
      }
      final fingerprint = jsonEncode(value);
      if (fingerprints.add(fingerprint)) {
        candidates.add(value);
      }
    }

    void addValue(Object? value, int depth) {
      if (depth > 6 || candidates.length >= 24) {
        return;
      }
      if (value is Map) {
        final mapped = mapValue(value);
        for (final key in const <String>[
          'choices',
          'message',
          'response',
          'output',
          'result',
          'data',
          'decision',
          'assistant',
          'content',
          'tool_calls',
          'toolCalls',
          'tool_call',
          'toolCall',
          'function_call',
          'functionCall',
          'function',
        ]) {
          if (mapped.containsKey(key)) {
            addValue(mapped[key], depth + 1);
          }
        }
        if (mapped.length == 1) {
          addValue(mapped.values.first, depth + 1);
        }
        addMap(mapped);
        return;
      }
      if (value is List) {
        for (final item in value.take(8)) {
          addValue(item, depth + 1);
        }
        return;
      }
      if (value is String) {
        final nested = value.trim();
        if (nested.isEmpty || nested.length > 2 * 1024 * 1024) {
          return;
        }
        if (nested.startsWith('{') ||
            nested.startsWith('[') ||
            nested.startsWith('"')) {
          try {
            addValue(jsonDecode(nested), depth + 1);
          } catch (_) {
            // The string is ordinary model output, not an encoded envelope.
          }
        }
      }
    }

    try {
      final decoded = jsonDecode(text);
      for (final adapter in providerAdapters(provider)) {
        for (final value in adapter.unwrap(decoded)) {
          addValue(value, 0);
        }
      }
      addValue(decoded, 0);
    } catch (_) {
      // Continue with bounded extraction from prose or code fences.
    }

    var start = -1;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = 0; index < text.length; index++) {
      final code = text.codeUnitAt(index);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5c) {
          escaped = true;
        } else if (code == 0x22) {
          inString = false;
        }
        continue;
      }
      if (code == 0x22) {
        inString = true;
      } else if (code == 0x7b) {
        if (depth == 0) {
          start = index;
        }
        depth++;
      } else if (code == 0x7d && depth > 0) {
        depth--;
        if (depth == 0 && start >= 0) {
          final candidate = text.substring(start, index + 1);
          try {
            addValue(jsonDecode(candidate), 0);
          } catch (_) {
            // Keep scanning in case a later bounded object is valid.
          }
          start = -1;
        }
      }
    }

    final ranked = candidates.asMap().entries.toList();
    ranked.sort((left, right) {
      final score = _candidateScore(
        right.value,
      ).compareTo(_candidateScore(left.value));
      return score != 0 ? score : left.key.compareTo(right.key);
    });
    return ranked.map((candidate) => candidate.value).toList();
  }

  int _candidateScore(Map<String, dynamic> value) {
    var score = 0;
    if (value.keys.any(
      const <String>{'action', 'kind', 'type', 'status', 'operation'}.contains,
    )) {
      score += 80;
    }
    if (value.keys.any(
      const <String>{
        'tool',
        'toolName',
        'tool_name',
        'tool_calls',
        'toolCalls',
        'tool_call',
        'toolCall',
        'function_call',
        'functionCall',
        'function',
      }.contains,
    )) {
      score += 90;
    }
    if (value.containsKey('name') &&
        value.keys.any(
          const <String>{
            'arguments',
            'args',
            'parameters',
            'params',
            'input',
          }.contains,
        )) {
      score += 70;
    }
    if (value.keys.any(
      const <String>{
        'summary',
        'answer',
        'final_answer',
        'finalAnswer',
        'final_response',
        'finalResponse',
        'response',
        'result',
        'final',
        'content',
        'text',
        'error',
      }.contains,
    )) {
      score += 45;
    }
    final action = AgentAction.fromJson(value);
    if (const <String>{'tool', 'complete', 'fail'}.contains(action.kind)) {
      score += 120;
    } else if (action.kind.isNotEmpty) {
      score += 20;
    }
    return score;
  }

  ProductException _preferError(
    ProductException? current,
    ProductException candidate,
  ) {
    if (current == null) {
      return candidate;
    }
    const priority = <String, int>{
      'model_tool_not_allowed': 5,
      'model_completion_invalid': 4,
      'model_action_invalid': 3,
      'model_json_invalid': 2,
    };
    return (priority[candidate.code] ?? 1) > (priority[current.code] ?? 1)
        ? candidate
        : current;
  }

  String _token(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}
