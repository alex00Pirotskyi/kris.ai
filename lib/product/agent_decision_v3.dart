import 'agent_decision.dart';

enum AgentDecisionV3Kind {
  terminal,
  browser,
  research,
  data,
  userTakeover,
  wait,
  delegate,
  complete,
  fail,
}

extension AgentDecisionV3KindWire on AgentDecisionV3Kind {
  String get wireName => switch (this) {
        AgentDecisionV3Kind.terminal => 'terminal',
        AgentDecisionV3Kind.browser => 'browser',
        AgentDecisionV3Kind.research => 'research',
        AgentDecisionV3Kind.data => 'data',
        AgentDecisionV3Kind.userTakeover => 'user_takeover',
        AgentDecisionV3Kind.wait => 'wait',
        AgentDecisionV3Kind.delegate => 'delegate',
        AgentDecisionV3Kind.complete => 'complete',
        AgentDecisionV3Kind.fail => 'fail',
      };
}

class AgentDecisionV3 {
  AgentDecisionV3({
    required this.kind,
    this.operation,
    Map<String, Object?> arguments = const <String, Object?>{},
    this.expectedPostcondition,
    this.idempotencyKey,
    this.summary,
    this.code,
    this.retryable = false,
    this.question,
    this.delegateTo,
    this.task,
    this.waitUntil,
    this.waitHandle,
    this.reason = '',
  }) : arguments = Map<String, Object?>.unmodifiable(arguments) {
    _validate();
  }

  static const String protocolVersion = '3.0.0';

  final AgentDecisionV3Kind kind;
  final String? operation;
  final Map<String, Object?> arguments;
  final String? expectedPostcondition;
  final String? idempotencyKey;
  final String? summary;
  final String? code;
  final bool retryable;
  final String? question;
  final String? delegateTo;
  final String? task;
  final DateTime? waitUntil;
  final String? waitHandle;
  final String reason;

  bool get requiresObjectivePostcondition => switch (kind) {
        AgentDecisionV3Kind.terminal ||
        AgentDecisionV3Kind.browser ||
        AgentDecisionV3Kind.research ||
        AgentDecisionV3Kind.data =>
          true,
        _ => false,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'protocolVersion': protocolVersion,
        'action': kind.wireName,
        if (operation != null) 'operation': operation,
        if (arguments.isNotEmpty) 'arguments': arguments,
        if (expectedPostcondition != null)
          'expectedPostcondition': expectedPostcondition,
        if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
        if (summary != null) 'summary': summary,
        if (code != null) 'code': code,
        if (retryable) 'retryable': true,
        if (question != null) 'question': question,
        if (delegateTo != null) 'delegateTo': delegateTo,
        if (task != null) 'task': task,
        if (waitUntil != null)
          'waitUntil': waitUntil!.toUtc().toIso8601String(),
        if (waitHandle != null) 'waitHandle': waitHandle,
        if (reason.trim().isNotEmpty) 'reason': reason,
      };

  static AgentDecisionV3 fromJson(Map<String, Object?> json) {
    if (json['protocolVersion'] != protocolVersion) {
      throw const FormatException('agent_decision_v3_protocol_version_invalid');
    }
    final action = json['action']?.toString() ?? '';
    final kind = AgentDecisionV3Kind.values
        .where((candidate) => candidate.wireName == action)
        .firstOrNull;
    if (kind == null) {
      throw const FormatException('agent_decision_v3_action_invalid');
    }
    final rawArguments = json['arguments'];
    if (rawArguments != null && rawArguments is! Map) {
      throw const FormatException('agent_decision_v3_arguments_invalid');
    }
    return AgentDecisionV3(
      kind: kind,
      operation: _nonEmpty(json['operation']),
      arguments: rawArguments is Map
          ? rawArguments.map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : const <String, Object?>{},
      expectedPostcondition: _nonEmpty(json['expectedPostcondition']),
      idempotencyKey: _nonEmpty(json['idempotencyKey']),
      summary: _nonEmpty(json['summary']),
      code: _nonEmpty(json['code']),
      retryable: json['retryable'] == true,
      question: _nonEmpty(json['question']),
      delegateTo: _nonEmpty(json['delegateTo']),
      task: _nonEmpty(json['task']),
      waitUntil: _parseDate(json['waitUntil']),
      waitHandle: _nonEmpty(json['waitHandle']),
      reason: json['reason']?.toString() ?? '',
    );
  }

  static AgentDecisionV3 fromV1(AgentDecision decision) {
    return switch (decision) {
      ToolDecision tool => AgentDecisionV3(
          kind: _domainForTool(tool.tool),
          operation: tool.tool,
          arguments: tool.arguments,
          expectedPostcondition:
              'Observe the tool-specific postcondition before completion.',
          reason: tool.reason,
        ),
      CompleteDecision complete => AgentDecisionV3(
          kind: AgentDecisionV3Kind.complete,
          summary: complete.summary,
          reason: complete.reason,
        ),
      FailDecision fail => AgentDecisionV3(
          kind: AgentDecisionV3Kind.fail,
          summary: fail.summary,
          code: fail.code,
          retryable: fail.retryable,
          reason: fail.reason,
        ),
      AskUserDecision ask => AgentDecisionV3(
          kind: AgentDecisionV3Kind.userTakeover,
          question: ask.question,
          reason: ask.reason,
        ),
      DelegateDecision delegate => AgentDecisionV3(
          kind: AgentDecisionV3Kind.delegate,
          delegateTo: delegate.delegateTo,
          task: delegate.task,
          arguments: delegate.inputs,
          reason: delegate.reason,
        ),
    };
  }

  void _validate() {
    final effectful = kind == AgentDecisionV3Kind.terminal ||
        kind == AgentDecisionV3Kind.browser ||
        kind == AgentDecisionV3Kind.research ||
        kind == AgentDecisionV3Kind.data;
    if (effectful) {
      if (operation == null || operation!.trim().isEmpty) {
        throw const FormatException('agent_decision_v3_operation_required');
      }
      if (expectedPostcondition == null ||
          expectedPostcondition!.trim().isEmpty) {
        throw const FormatException('agent_decision_v3_postcondition_required');
      }
      return;
    }
    if (kind == AgentDecisionV3Kind.userTakeover) {
      if (question == null || question!.trim().isEmpty) {
        throw const FormatException('agent_decision_v3_question_required');
      }
      return;
    }
    if (kind == AgentDecisionV3Kind.wait) {
      if (waitUntil == null && (waitHandle == null || waitHandle!.isEmpty)) {
        throw const FormatException('agent_decision_v3_wait_target_required');
      }
      return;
    }
    if (kind == AgentDecisionV3Kind.delegate) {
      if (delegateTo == null ||
          delegateTo!.isEmpty ||
          task == null ||
          task!.isEmpty) {
        throw const FormatException(
            'agent_decision_v3_delegate_target_required');
      }
      return;
    }
    if (kind == AgentDecisionV3Kind.complete) {
      if (summary == null || summary!.trim().isEmpty) {
        throw const FormatException('agent_decision_v3_summary_required');
      }
      return;
    }
    if ((summary == null || summary!.trim().isEmpty) &&
        (code == null || code!.trim().isEmpty)) {
      throw const FormatException('agent_decision_v3_failure_detail_required');
    }
  }

  static AgentDecisionV3Kind _domainForTool(String tool) {
    final normalized = tool.toLowerCase();
    if (normalized.startsWith('browser.') ||
        normalized.startsWith('browser_')) {
      return AgentDecisionV3Kind.browser;
    }
    if (normalized.startsWith('terminal.') ||
        normalized.startsWith('terminal_') ||
        normalized == 'run_command') {
      return AgentDecisionV3Kind.terminal;
    }
    if (normalized.startsWith('research.') ||
        normalized.startsWith('web_') ||
        normalized.startsWith('search_')) {
      return AgentDecisionV3Kind.research;
    }
    return AgentDecisionV3Kind.data;
  }

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) {
      throw const FormatException('agent_decision_v3_wait_until_invalid');
    }
    return parsed.toUtc();
  }
}
