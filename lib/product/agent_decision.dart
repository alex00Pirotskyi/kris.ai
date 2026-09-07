import 'domain.dart';
import 'generated/protocol_contracts.g.dart';
import 'protocol_types.dart';
import 'storage_security.dart';
import 'tool_schema.dart';

enum AgentDecisionKind { tool, complete, fail, askUser, delegate }

extension AgentDecisionKindWireName on AgentDecisionKind {
  String get wireName => switch (this) {
        AgentDecisionKind.tool => 'tool',
        AgentDecisionKind.complete => 'complete',
        AgentDecisionKind.fail => 'fail',
        AgentDecisionKind.askUser => 'ask_user',
        AgentDecisionKind.delegate => 'delegate',
      };
}

class AgentDecisionException extends ProductException {
  AgentDecisionException({
    required String code,
    required String message,
    required this.retryability,
    this.issues = const <SchemaIssue>[],
    Map<String, dynamic> details = const <String, dynamic>{},
  }) : super(
          code,
          message,
          details: <String, dynamic>{
            ...details,
            'schemaVersion': generatedAgentDecisionSchemaVersion,
            'contractDigest': generatedProtocolContractDigest,
            'retryability': retryability.wireName,
            if (issues.isNotEmpty)
              'issues': issues.map((issue) => issue.toJson()).toList(),
          },
        );

  final Retryability retryability;
  final List<SchemaIssue> issues;
}

sealed class AgentDecision {
  const AgentDecision({this.protocolVersion = '1.0.0', this.reason = ''});

  final String protocolVersion;
  final String reason;

  AgentDecisionKind get kind;

  Map<String, dynamic> toJson();

  AgentAction toLegacyAction() {
    return switch (this) {
      ToolDecision decision => AgentAction(
          kind: 'tool',
          tool: decision.tool,
          arguments: decision.arguments,
          reason: decision.reason,
        ),
      CompleteDecision decision => AgentAction(
          kind: 'complete',
          reason: decision.reason,
          summary: decision.summary,
        ),
      FailDecision decision => AgentAction(
          kind: 'fail',
          reason: decision.reason,
          summary: decision.summary,
        ),
      AskUserDecision _ => throw AgentDecisionException(
          code: 'agent_decision_legacy_bridge_unsupported',
          message:
              'This decision kind requires the durable V2 workflow kernel and cannot be represented by the v1 coordinator bridge.',
          retryability: Retryability.never,
          details: <String, dynamic>{'decisionKind': kind.wireName},
        ),
      DelegateDecision _ => throw AgentDecisionException(
          code: 'agent_decision_legacy_bridge_unsupported',
          message:
              'This decision kind requires the durable V2 workflow kernel and cannot be represented by the v1 coordinator bridge.',
          retryability: Retryability.never,
          details: <String, dynamic>{'decisionKind': kind.wireName},
        ),
    };
  }

  static AgentDecision fromLegacy(AgentAction action) {
    return switch (action.kind) {
      'tool' => ToolDecision(
          tool: action.tool ?? '',
          arguments: Map<String, dynamic>.from(action.arguments),
          reason: action.reason,
        ),
      'complete' => CompleteDecision(
          summary: action.summary,
          reason: action.reason,
        ),
      'fail' => FailDecision(summary: action.summary, reason: action.reason),
      _ => throw AgentDecisionException(
          code: 'model_action_invalid',
          message: 'Unsupported legacy agent action kind: ${action.kind}',
          retryability: Retryability.modelCorrection,
          details: <String, dynamic>{'receivedAction': action.kind},
        ),
    };
  }
}

class ToolDecision extends AgentDecision {
  const ToolDecision({
    required this.tool,
    required this.arguments,
    super.protocolVersion,
    super.reason,
  });

  final String tool;
  final Map<String, dynamic> arguments;

  @override
  AgentDecisionKind get kind => AgentDecisionKind.tool;

  ToolDecision copyWith({
    String? tool,
    Map<String, dynamic>? arguments,
    String? protocolVersion,
    String? reason,
  }) =>
      ToolDecision(
        tool: tool ?? this.tool,
        arguments: arguments ?? this.arguments,
        protocolVersion: protocolVersion ?? this.protocolVersion,
        reason: reason ?? this.reason,
      );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'protocolVersion': protocolVersion,
        'action': kind.wireName,
        'tool': tool,
        'arguments': arguments,
        if (reason.trim().isNotEmpty) 'reason': reason,
      };
}

class CompleteDecision extends AgentDecision {
  const CompleteDecision({
    required this.summary,
    super.protocolVersion,
    super.reason,
  });

  final String summary;

  @override
  AgentDecisionKind get kind => AgentDecisionKind.complete;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'protocolVersion': protocolVersion,
        'action': kind.wireName,
        'summary': summary,
        if (reason.trim().isNotEmpty) 'reason': reason,
      };
}

class FailDecision extends AgentDecision {
  const FailDecision({
    this.summary = '',
    this.code = '',
    this.retryable = false,
    super.protocolVersion,
    super.reason,
  });

  final String summary;
  final String code;
  final bool retryable;

  @override
  AgentDecisionKind get kind => AgentDecisionKind.fail;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'protocolVersion': protocolVersion,
        'action': kind.wireName,
        if (summary.trim().isNotEmpty) 'summary': summary,
        if (reason.trim().isNotEmpty) 'reason': reason,
        if (code.trim().isNotEmpty) 'code': code,
        'retryable': retryable,
      };
}

class AskUserDecision extends AgentDecision {
  const AskUserDecision({
    required this.question,
    this.choices = const <String>[],
    super.protocolVersion,
    super.reason,
  });

  final String question;
  final List<String> choices;

  @override
  AgentDecisionKind get kind => AgentDecisionKind.askUser;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'protocolVersion': protocolVersion,
        'action': kind.wireName,
        'question': question,
        if (choices.isNotEmpty) 'choices': choices,
        if (reason.trim().isNotEmpty) 'reason': reason,
      };
}

class DelegateDecision extends AgentDecision {
  const DelegateDecision({
    required this.delegateTo,
    required this.task,
    this.inputs = const <String, dynamic>{},
    super.protocolVersion,
    super.reason,
  });

  final String delegateTo;
  final String task;
  final Map<String, dynamic> inputs;

  @override
  AgentDecisionKind get kind => AgentDecisionKind.delegate;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'protocolVersion': protocolVersion,
        'action': kind.wireName,
        'delegateTo': delegateTo,
        'task': task,
        if (inputs.isNotEmpty) 'inputs': inputs,
        if (reason.trim().isNotEmpty) 'reason': reason,
      };
}

class AgentDecisionCodec {
  const AgentDecisionCodec();

  AgentDecision decodeCanonical(Map<String, dynamic> json) {
    final action = json['action']?.toString() ?? '';
    final definitionName = switch (action) {
      'tool' => 'toolDecision',
      'complete' => 'completeDecision',
      'fail' => 'failDecision',
      'ask_user' => 'askUserDecision',
      'delegate' => 'delegateDecision',
      _ => '',
    };
    if (definitionName.isEmpty) {
      throw AgentDecisionException(
        code: 'model_action_invalid',
        message:
            'The model must return action=tool, complete, fail, ask_user, or delegate.',
        retryability: Retryability.modelCorrection,
        details: <String, dynamic>{'receivedAction': action},
      );
    }
    final definitions = Map<String, dynamic>.from(
      generatedAgentDecisionSchema[r'$defs'] as Map,
    );
    final schema = Map<String, dynamic>.from(
      definitions[definitionName] as Map,
    );
    final normalized = <String, dynamic>{'protocolVersion': '1.0.0', ...json};
    final issues = JsonSchemaValidator.validate(normalized, schema);
    if (issues.isNotEmpty) {
      throw AgentDecisionException(
        code: 'agent_decision_schema_invalid',
        message:
            'The model decision does not satisfy AgentDecision schema 1.0.0.',
        retryability: Retryability.modelCorrection,
        issues: issues,
        details: <String, dynamic>{'receivedAction': action},
      );
    }
    return switch (action) {
      'tool' => ToolDecision(
          tool: normalized['tool'].toString(),
          arguments: Map<String, dynamic>.from(normalized['arguments'] as Map),
          protocolVersion: normalized['protocolVersion'].toString(),
          reason: normalized['reason']?.toString() ?? '',
        ),
      'complete' => CompleteDecision(
          summary: normalized['summary'].toString(),
          protocolVersion: normalized['protocolVersion'].toString(),
          reason: normalized['reason']?.toString() ?? '',
        ),
      'fail' => FailDecision(
          summary: normalized['summary']?.toString() ?? '',
          code: normalized['code']?.toString() ?? '',
          retryable: normalized['retryable'] == true,
          protocolVersion: normalized['protocolVersion'].toString(),
          reason: normalized['reason']?.toString() ?? '',
        ),
      'ask_user' => AskUserDecision(
          question: normalized['question'].toString(),
          choices: normalized['choices'] is List
              ? (normalized['choices'] as List)
                  .map((choice) => choice.toString())
                  .toList(growable: false)
              : const <String>[],
          protocolVersion: normalized['protocolVersion'].toString(),
          reason: normalized['reason']?.toString() ?? '',
        ),
      'delegate' => DelegateDecision(
          delegateTo: normalized['delegateTo'].toString(),
          task: normalized['task'].toString(),
          inputs: normalized['inputs'] is Map
              ? Map<String, dynamic>.from(normalized['inputs'] as Map)
              : const <String, dynamic>{},
          protocolVersion: normalized['protocolVersion'].toString(),
          reason: normalized['reason']?.toString() ?? '',
        ),
      _ => throw StateError('unreachable AgentDecision action: $action'),
    };
  }
}
