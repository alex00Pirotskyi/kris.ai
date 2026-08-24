import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/agent_decision_v3.dart';
import 'package:kristin_local_agent/product/agent_protocol.dart';
import 'package:kristin_local_agent/product/agent_protocol_v3.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

void main() {
  const item = WorkItem(
    id: 'work-v3',
    title: 'Execute bounded work',
    description: 'Use only the approved tool set.',
    dependencies: <String>{},
    allowedTools: <String>{
      'run_command',
      'research_fetch',
      'read_file',
    },
    acceptanceCriteria: <String>['Produce objective evidence.'],
  );
  const adapter = AgentProtocolV3Adapter();

  Map<String, Object?> terminalDecision() => <String, Object?>{
        'protocolVersion': '3.0.0',
        'action': 'terminal',
        'operation': 'terminal.exec',
        'arguments': <String, Object?>{'command': 'git status'},
        'expectedPostcondition': 'Command exits and status is captured.',
      };

  group('P6-004 cross-provider action protocol v3', () {
    test('normalizes v3 decisions across provider envelopes', () {
      final canonical = jsonEncode(terminalDecision());
      final envelopes = <MapEntry<AgentProviderProtocol, String>>[
        MapEntry(AgentProviderProtocol.auto, canonical),
        MapEntry(
          AgentProviderProtocol.ollama,
          jsonEncode(<String, Object?>{
            'message': <String, Object?>{'content': canonical},
          }),
        ),
        MapEntry(
          AgentProviderProtocol.openAiCompatible,
          jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{'content': canonical},
              },
            ],
          }),
        ),
        MapEntry(
          AgentProviderProtocol.mcp,
          jsonEncode(<String, Object?>{
            'content': <Object?>[
              <String, Object?>{'text': canonical},
            ],
          }),
        ),
        MapEntry(
          AgentProviderProtocol.recorded,
          jsonEncode(<String, Object?>{
            'normalizedAction': terminalDecision(),
          }),
        ),
      ];

      for (final envelope in envelopes) {
        final decision = adapter.parseDecision(
          envelope.value,
          item: item,
          allowPlainCompletion: false,
          provider: envelope.key,
        );
        expect(decision.kind, AgentDecisionV3Kind.terminal);
        expect(decision.operation, 'terminal.exec');
        final legacy = adapter.parseLegacyCompatibleAction(
          envelope.value,
          item: item,
          allowPlainCompletion: false,
          provider: envelope.key,
        );
        expect(legacy.kind, 'tool');
        expect(legacy.tool, 'run_command');
        expect(legacy.reason, contains('Protocol v3 postcondition'));
      }
    });

    test('preserves v1 compatibility through the established adapter', () {
      final action = adapter.parseLegacyCompatibleAction(
        jsonEncode(<String, Object?>{
          'action': 'tool',
          'tool': 'read_file',
          'arguments': <String, Object?>{'path': 'README.md'},
        }),
        item: item,
        allowPlainCompletion: false,
      );
      expect(action.kind, 'tool');
      expect(action.tool, 'read_file');
    });

    test('v3 cannot widen the active work-item tool scope', () {
      final payload = terminalDecision()..['operation'] = 'terminal.kill';
      expect(
        () => adapter.parseDecision(
          jsonEncode(payload),
          item: item,
          allowPlainCompletion: false,
        ),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'agent_decision_v3_operation_not_allowed',
          ),
        ),
      );
    });

    test('deferred v3 decisions never collapse into synchronous effects', () {
      final wait = jsonEncode(<String, Object?>{
        'protocolVersion': '3.0.0',
        'action': 'wait',
        'waitHandle': 'browser:download:42',
      });
      final parsed = adapter.parseDecision(
        wait,
        item: item,
        allowPlainCompletion: false,
      );
      expect(parsed.kind, AgentDecisionV3Kind.wait);
      expect(
        () => adapter.parseLegacyCompatibleAction(
          wait,
          item: item,
          allowPlainCompletion: false,
        ),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'agent_decision_v3_deferred_action',
          ),
        ),
      );
    });

    test('conflicting v3 decisions in one envelope fail closed', () {
      final first = terminalDecision();
      final second = <String, Object?>{
        'protocolVersion': '3.0.0',
        'action': 'research',
        'operation': 'research.fetch',
        'arguments': <String, Object?>{'url': 'https://example.invalid'},
        'expectedPostcondition': 'Fetched source is hashed.',
      };
      final envelope = jsonEncode(<String, Object?>{
        'response': first,
        'output': second,
      });
      expect(
        () => adapter.parseDecision(
          envelope,
          item: item,
          allowPlainCompletion: false,
          provider: AgentProviderProtocol.recorded,
        ),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'agent_decision_v3_ambiguous',
          ),
        ),
      );
    });

    test('malformed v3 corpus fails without falling back to authority', () {
      for (var index = 0; index < 128; index++) {
        final payload = <String, Object?>{
          'protocolVersion': '3.0.0',
          'action': index.isEven ? 'terminal' : 'research',
          if (index % 3 != 0) 'operation': 'not.allowed.$index',
          if (index % 5 != 0)
            'expectedPostcondition': 'synthetic postcondition $index',
          'arguments': <String, Object?>{'seed': index},
        };
        expect(
          () => adapter.parseDecision(
            jsonEncode(payload),
            item: item,
            allowPlainCompletion: false,
          ),
          throwsA(anyOf(isA<FormatException>(), isA<ProductException>())),
        );
      }
    });
  });
}
