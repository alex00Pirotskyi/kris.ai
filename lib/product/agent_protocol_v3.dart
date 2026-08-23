import 'dart:convert';

import 'agent_decision.dart';
import 'agent_decision_v3.dart';
import 'agent_protocol.dart';
import 'domain.dart';
import 'storage_security.dart';

class AgentProtocolV3Adapter {
  const AgentProtocolV3Adapter();

  AgentDecisionV3 parseDecision(
    String text, {
    required WorkItem item,
    required bool allowPlainCompletion,
    AgentProviderProtocol provider = AgentProviderProtocol.auto,
  }) {
    final v3 = _v3Candidate(text, provider: provider);
    if (v3 != null) {
      final decision = AgentDecisionV3.fromJson(v3);
      _validateScope(decision, item);
      return decision;
    }
    final legacy = const AgentProtocolAdapter().parseDecision(
      text,
      item: item,
      allowPlainCompletion: allowPlainCompletion,
      provider: provider,
    );
    return AgentDecisionV3.fromV1(legacy);
  }

  AgentAction parseLegacyCompatibleAction(
    String text, {
    required WorkItem item,
    required bool allowPlainCompletion,
    AgentProviderProtocol provider = AgentProviderProtocol.auto,
  }) {
    final decision = parseDecision(
      text,
      item: item,
      allowPlainCompletion: allowPlainCompletion,
      provider: provider,
    );
    return switch (decision.kind) {
      AgentDecisionV3Kind.terminal ||
      AgentDecisionV3Kind.browser ||
      AgentDecisionV3Kind.research ||
      AgentDecisionV3Kind.data => AgentAction(
          kind: 'tool',
          tool: _resolveTool(decision, item),
          arguments: Map<String, dynamic>.from(decision.arguments),
          reason: <String>[
            decision.reason.trim(),
            'Protocol v3 postcondition: ${decision.expectedPostcondition}.',
          ].where((value) => value.isNotEmpty).join(' '),
        ),
      AgentDecisionV3Kind.complete => AgentAction(
          kind: 'complete',
          summary: decision.summary ?? '',
          reason: decision.reason,
        ),
      AgentDecisionV3Kind.fail => AgentAction(
          kind: 'fail',
          summary: decision.summary ?? decision.code ?? 'Agent declared failure.',
          reason: decision.reason,
        ),
      AgentDecisionV3Kind.wait ||
      AgentDecisionV3Kind.userTakeover ||
      AgentDecisionV3Kind.delegate => throw ProductException(
          'agent_decision_v3_deferred_action',
          'Protocol v3 decision ${decision.kind.wireName} requires the durable deferred-action coordinator and cannot be collapsed into a synchronous tool action.',
          details: <String, dynamic>{
            'decisionKind': decision.kind.wireName,
            'protocolVersion': AgentDecisionV3.protocolVersion,
          },
        ),
    };
  }

  Map<String, Object?>? _v3Candidate(
    String text, {
    required AgentProviderProtocol provider,
  }) {
    final trimmed = text.trim();
    final roots = <Object?>[];
    try {
      roots.add(jsonDecode(trimmed));
    } catch (_) {
      // Existing v1 compatibility parsing remains authoritative for non-JSON
      // provider prose and fenced legacy responses.
    }
    final candidates = <Map<String, Object?>>[];
    final seen = <String>{};

    void inspect(Object? value, int depth) {
      if (depth > 5 || value == null) return;
      if (value is String) {
        final candidate = value.trim();
        if (candidate.startsWith('{') && candidate.endsWith('}')) {
          try {
            inspect(jsonDecode(candidate), depth + 1);
          } catch (_) {}
        }
        return;
      }
      if (value is List) {
        for (final item in value.take(32)) {
          inspect(item, depth + 1);
        }
        return;
      }
      if (value is! Map) return;
      final mapped = <String, Object?>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
      final fingerprint = jsonEncode(mapped);
      if (!seen.add(fingerprint)) return;
      if (mapped['protocolVersion']?.toString() == AgentDecisionV3.protocolVersion &&
          mapped['action'] != null) {
        candidates.add(mapped);
      }
      for (final adapter in providerAdapters(provider)) {
        for (final child in adapter.unwrap(mapped)) {
          inspect(child, depth + 1);
        }
      }
      for (final child in mapped.values) {
        inspect(child, depth + 1);
      }
    }

    for (final root in roots) {
      inspect(root, 0);
    }
    if (candidates.length > 1) {
      final distinct = candidates.map(jsonEncode).toSet();
      if (distinct.length > 1) {
        throw ProductException(
          'agent_decision_v3_ambiguous',
          'The provider envelope contains multiple conflicting protocol v3 decisions.',
        );
      }
    }
    return candidates.firstOrNull;
  }

  void _validateScope(AgentDecisionV3 decision, WorkItem item) {
    if (!decision.requiresObjectivePostcondition) return;
    _resolveTool(decision, item);
  }

  String _resolveTool(AgentDecisionV3 decision, WorkItem item) {
    final operation = decision.operation?.trim() ?? '';
    final aliases = <String>{
      operation,
      operation.replaceAll('.', '_'),
      ..._knownAliases(operation),
    }..removeWhere((value) => value.isEmpty);
    final matches = aliases.where(item.allowedTools.contains).toList()..sort();
    if (matches.isEmpty) {
      throw ProductException(
        'agent_decision_v3_operation_not_allowed',
        'Protocol v3 operation $operation does not resolve to a tool allowed by this work item.',
        details: <String, dynamic>{
          'operation': operation,
          'candidateTools': aliases.toList()..sort(),
          'allowedTools': item.allowedTools.toList()..sort(),
        },
      );
    }
    return matches.first;
  }

  Set<String> _knownAliases(String operation) {
    return switch (operation.toLowerCase()) {
      'terminal.exec' || 'terminal.run' || 'terminal.finite' =>
        const <String>{'run_command'},
      'terminal.start' || 'terminal.background' =>
        const <String>{'start_process'},
      'terminal.status' => const <String>{'process_status'},
      'terminal.stop' || 'terminal.kill' => const <String>{'stop_process'},
      'research.search' => const <String>{'research_search'},
      'research.fetch' => const <String>{'research_fetch'},
      'data.verify' => const <String>{'verify_project'},
      'data.read' => const <String>{'read_file'},
      'data.inspect' => const <String>{'inspect_file'},
      'data.write' => const <String>{'write_file'},
      'data.patch' => const <String>{'apply_patch'},
      _ => const <String>{},
    };
  }
}
