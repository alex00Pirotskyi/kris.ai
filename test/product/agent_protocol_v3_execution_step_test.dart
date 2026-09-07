import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/agent_decision_v3.dart';
import 'package:kristin_local_agent/product/agent_protocol_v3.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

void main() {
  const adapter = AgentProtocolV3Adapter();
  const item = WorkItem(
    id: 'work-v3-execution',
    title: 'Execute bounded work',
    description: 'Use only the approved tool set.',
    dependencies: <String>{},
    allowedTools: <String>{'read_file', 'run_command'},
    acceptanceCriteria: <String>['Produce objective evidence.'],
  );

  test('user takeover is a typed deferred step, not a synchronous effect', () {
    final payload = jsonEncode(<String, Object?>{
      'protocolVersion': AgentDecisionV3.protocolVersion,
      'action': 'user_takeover',
      'question': 'Please complete the MFA challenge in the active window.',
      'reason': 'The next step requires a human authentication factor.',
    });

    final step = adapter.parseExecutionStep(
      payload,
      item: item,
      allowPlainCompletion: false,
    );

    expect(step, isA<AgentProtocolV3DeferredStep>());
    final deferred = step as AgentProtocolV3DeferredStep;
    expect(deferred.isUserTakeover, isTrue);
    expect(deferred.isWait, isFalse);
    expect(
      deferred.decision.question,
      'Please complete the MFA challenge in the active window.',
    );
    expect(deferred.toEvidence()['decisionKind'], 'user_takeover');
  });

  test('durable wait retains its resume handle and never becomes a tool', () {
    final payload = jsonEncode(<String, Object?>{
      'protocolVersion': AgentDecisionV3.protocolVersion,
      'action': 'wait',
      'waitHandle': 'browser:download:42',
      'reason': 'Wait for the governed download receipt.',
    });

    final step = adapter.parseExecutionStep(
      payload,
      item: item,
      allowPlainCompletion: false,
    );

    expect(step, isA<AgentProtocolV3DeferredStep>());
    final deferred = step as AgentProtocolV3DeferredStep;
    expect(deferred.isWait, isTrue);
    expect(deferred.decision.waitHandle, 'browser:download:42');
    expect(deferred.toEvidence()['waitHandle'], 'browser:download:42');
  });

  test('ordinary v3 tool decision still uses the synchronous Runner shape', () {
    final payload = jsonEncode(<String, Object?>{
      'protocolVersion': AgentDecisionV3.protocolVersion,
      'action': 'data',
      'operation': 'data.read',
      'arguments': <String, Object?>{'path': 'README.md'},
      'expectedPostcondition': 'The file content and hash are observed.',
    });

    final step = adapter.parseExecutionStep(
      payload,
      item: item,
      allowPlainCompletion: false,
    );

    expect(step, isA<AgentProtocolV3SynchronousStep>());
    final synchronous = step as AgentProtocolV3SynchronousStep;
    expect(synchronous.action.kind, 'tool');
    expect(synchronous.action.tool, 'read_file');
    expect(synchronous.action.arguments['path'], 'README.md');
  });

  test(
    'legacy synchronous boundary still fails closed for deferred actions',
    () {
      final payload = jsonEncode(<String, Object?>{
        'protocolVersion': AgentDecisionV3.protocolVersion,
        'action': 'user_takeover',
        'question': 'Please approve the external consent prompt.',
      });

      expect(
        () => adapter.parseLegacyCompatibleAction(
          payload,
          item: item,
          allowPlainCompletion: false,
        ),
        throwsA(
          isA<ProductException>()
              .having(
                (error) => error.code,
                'code',
                'agent_decision_v3_deferred_action',
              )
              .having(
                (error) => error.details['decisionKind'],
                'decisionKind',
                'user_takeover',
              ),
        ),
      );
    },
  );
}
