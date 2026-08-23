import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/agent_decision.dart';
import 'package:kristin_local_agent/product/agent_decision_v3.dart';

void main() {
  group('P6-004 action protocol v3', () {
    test('round-trips every supported decision family', () {
      final decisions = <AgentDecisionV3>[
        AgentDecisionV3(
          kind: AgentDecisionV3Kind.terminal,
          operation: 'terminal.exec',
          arguments: const <String, Object?>{'command': 'git status'},
          expectedPostcondition: 'Command exits with captured status.',
        ),
        AgentDecisionV3(
          kind: AgentDecisionV3Kind.browser,
          operation: 'browser.click',
          expectedPostcondition: 'Target state is re-observed.',
        ),
        AgentDecisionV3(
          kind: AgentDecisionV3Kind.research,
          operation: 'research.fetch',
          expectedPostcondition: 'Fetched immutable source exists.',
        ),
        AgentDecisionV3(
          kind: AgentDecisionV3Kind.data,
          operation: 'data.transform',
          expectedPostcondition: 'Output manifest validates.',
        ),
        AgentDecisionV3(
          kind: AgentDecisionV3Kind.userTakeover,
          question: 'Complete the passkey ceremony, then return control.',
        ),
        AgentDecisionV3(
          kind: AgentDecisionV3Kind.wait,
          waitHandle: 'task:123',
        ),
        AgentDecisionV3(
          kind: AgentDecisionV3Kind.delegate,
          delegateTo: 'validator.agent',
          task: 'Verify the release receipt.',
        ),
        AgentDecisionV3(
          kind: AgentDecisionV3Kind.complete,
          summary: 'All acceptance criteria are objectively verified.',
        ),
        AgentDecisionV3(
          kind: AgentDecisionV3Kind.fail,
          code: 'verification_failed',
        ),
      ];

      for (final decision in decisions) {
        final decoded = AgentDecisionV3.fromJson(decision.toJson());
        expect(decoded.kind, decision.kind);
        expect(decoded.toJson(), decision.toJson());
      }
    });

    test('decision arguments cannot change after validation', () {
      final source = <String, Object?>{'command': 'git status'};
      final decision = AgentDecisionV3(
        kind: AgentDecisionV3Kind.terminal,
        operation: 'terminal.exec',
        arguments: source,
        expectedPostcondition: 'Command exits with captured status.',
      );

      source['command'] = 'unexpected replacement';
      expect(decision.arguments['command'], 'git status');
      expect(
        () => decision.arguments['command'] = 'mutated after trust',
        throwsUnsupportedError,
      );
    });

    test('effect decisions require objective postconditions', () {
      expect(
        () => AgentDecisionV3(
          kind: AgentDecisionV3Kind.browser,
          operation: 'browser.click',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('legacy tool decisions map to explicit domains', () {
      final browser = AgentDecisionV3.fromV1(
        const ToolDecision(
          tool: 'browser.click',
          arguments: <String, dynamic>{'target': 'save'},
        ),
      );
      final terminal = AgentDecisionV3.fromV1(
        const ToolDecision(
          tool: 'run_command',
          arguments: <String, dynamic>{'command': 'git status'},
        ),
      );
      final research = AgentDecisionV3.fromV1(
        const ToolDecision(
          tool: 'web_fetch',
          arguments: <String, dynamic>{'url': 'https://example.invalid'},
        ),
      );

      expect(browser.kind, AgentDecisionV3Kind.browser);
      expect(terminal.kind, AgentDecisionV3Kind.terminal);
      expect(research.kind, AgentDecisionV3Kind.research);
      expect(browser.requiresObjectivePostcondition, isTrue);
    });

    test('malformed provider payloads fail closed', () {
      final invalid = <Map<String, Object?>>[
        const <String, Object?>{'protocolVersion': '2.0.0', 'action': 'wait'},
        const <String, Object?>{'protocolVersion': '3.0.0', 'action': 'unknown'},
        const <String, Object?>{
          'protocolVersion': '3.0.0',
          'action': 'terminal',
          'operation': 'terminal.exec',
        },
        const <String, Object?>{
          'protocolVersion': '3.0.0',
          'action': 'delegate',
          'delegateTo': 'agent',
        },
        const <String, Object?>{
          'protocolVersion': '3.0.0',
          'action': 'browser',
          'operation': 'browser.click',
          'expectedPostcondition': 'verified',
          'arguments': 'not-an-object',
        },
      ];

      for (final payload in invalid) {
        expect(
          () => AgentDecisionV3.fromJson(payload),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });
}
