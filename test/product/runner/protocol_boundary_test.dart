import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/agent_protocol_v3.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/protocol_recovery_policy.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/tool_schema_base.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

/// Regressions for the real production failure:
///
///     model_protocol_exhausted:
///     The selected model still returned an unsupported action after
///     bounded correction attempts.
///
/// Reproduced with local models (phi4-mini, Qwen) asked to scaffold a
/// Flutter web app. Every fixture here is a sanitized shape taken from
/// that failure class -- no live model, no network, no Ollama.
void main() {
  WorkItem scaffoldItem({
    Set<String> allowedTools = const <String>{
      'apply_patch',
      'write_file',
      'read_file',
      'inspect_file',
      'list_directory',
      'search_text',
      'replace_text',
      'run_command',
      'git_status',
      'git_diff',
    },
  }) =>
      WorkItem(
        id: 'task_001',
        title: 'Scaffold the Flutter web application',
        description: 'Create the application source inside the active '
            'project root.',
        dependencies: const <String>{},
        allowedTools: allowedTools,
        acceptanceCriteria: const <String>['The app source exists.'],
      );

  AgentAction parse(String text, {WorkItem? item}) =>
      const AgentProtocolV3Adapter().parseLegacyCompatibleAction(
        text,
        item: item ?? scaffoldItem(),
        allowPlainCompletion: false,
      );

  group('CASE A: nested valid tool action normalizes without a repair', () {
    test('a nested action object resolves to the canonical envelope', () {
      final action = parse('''
{"action":{"type":"tool","tool":"apply_patch","arguments":{
  "path":"lib/main.dart",
  "hunks":[{"old":"void main()","replacement":"void main() {}"}]}}}''');
      expect(action.kind, 'tool');
      expect(action.tool, 'apply_patch');
      expect(action.arguments['path'], 'lib/main.dart');
      // No exception means no correction round trip was needed -- the
      // whole point, at ~80s per local-model call.
    });
  });

  group('CASE B: an allowed tool supplied as the action alias', () {
    test('run_command as the action normalizes when it is allowed', () {
      final action = parse('''
{"action":"run_command","arguments":{"executable":"flutter",
  "args":["create","."]}}''');
      expect(action.kind, 'tool');
      expect(action.tool, 'run_command');
      expect(action.arguments['executable'], 'flutter');
    });

    test('the same shape FAILS CLOSED when the tool is not allowed', () {
      expect(
        () => parse(
          '{"action":"run_command","arguments":{"executable":"flutter"}}',
          item: scaffoldItem(
            allowedTools: const <String>{'read_file', 'list_directory'},
          ),
        ),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'model_action_invalid',
          ),
        ),
      );
    });

    test('invalid arguments still fail schema validation', () {
      expect(
        () => parse('{"action":"run_command","arguments":{"bogus":1}}'),
        throwsA(isA<ProductException>()),
      );
    });
  });

  group('CASE C: the hallucinated coordinator tool', () {
    // This is the exact action the real run emitted, because the plan
    // told it to "use the agent.create_project capability".
    test('a nested create_project is refused, never silently allowed', () {
      expect(
        () => parse(
          '{"action":{"type":"tool","tool":"create_project",'
          '"arguments":{"name":"mp3_converter"}}}',
        ),
        throwsA(
          isA<ProductException>()
              .having((error) => error.code, 'code', 'model_tool_not_allowed')
              .having(
                (error) => error.details['requestedTool'],
                'requestedTool',
                'create_project',
              ),
        ),
      );
    });

    test('create_project as the action is refused', () {
      expect(
        () => parse('{"action":"create_project","arguments":{}}'),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'model_action_invalid',
          ),
        ),
      );
    });

    test('create_project is NEVER rewritten into run_command', () {
      try {
        parse(
          '{"action":{"type":"tool","tool":"create_project",'
          '"arguments":{"command":"flutter create ."}}}',
        );
        fail('create_project must not resolve to any tool');
      } on ProductException catch (error) {
        expect(error.details['requestedTool'], isNot('run_command'));
      }
    });

    test('no arbitrary shell string becomes an execution bypass', () {
      // "command": "flutter create foo" must not be parsed into a shell
      // invocation as a new compatibility feature.
      expect(
        () => parse(
          '{"action":"tool","tool":"run_command",'
          '"arguments":{"command":"flutter create foo"}}',
        ),
        throwsA(isA<ProductException>()),
      );
    });
  });

  group('ambiguity fails closed', () {
    test('conflicting outer and nested tool declarations are refused', () {
      expect(
        () => parse(
          '{"action":{"type":"tool","tool":"apply_patch"},'
          '"tool":"write_file","arguments":{"path":"a.txt","content":"x"}}',
        ),
        throwsA(
          isA<ProductException>()
              .having((error) => error.code, 'code', 'model_action_invalid')
              .having(
                (error) => error.details['receivedAction'],
                'receivedAction',
                'conflicting_tool_declarations',
              ),
        ),
      );
    });

    test('an unrecognized nested action type is refused', () {
      expect(
        () => parse('{"action":{"type":"scaffold","tool":"create_project"}}'),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'model_action_invalid',
          ),
        ),
      );
    });
  });

  group('CASE D: no copyable dummy payloads reach the executor', () {
    // A local model copied Kristin's own apply_patch example verbatim
    // while trying to scaffold an unrelated Flutter app.
    const dummies = <String>['README.md', 'Old text', 'New text'];

    test('the executor tool descriptor carries no concrete example', () {
      final descriptors = ToolRegistry.standard().descriptors(
        allowlist: scaffoldItem().allowedTools,
        dialect: ToolDescriptorDialect.executor,
      );
      expect(descriptors, isNotEmpty);
      final rendered = descriptors.toString();
      for (final dummy in dummies) {
        expect(
          rendered.contains(dummy),
          isFalse,
          reason: 'executor descriptors must not suggest "$dummy" for an '
              'unrelated task: $rendered',
        );
      }
      // Shape is still communicated -- only invented content is gone.
      final applyPatch = descriptors.firstWhere(
        (descriptor) => descriptor['name'] == 'apply_patch',
      );
      final argumentSchema =
          applyPatch['argumentSchema'] as Map<String, dynamic>;
      expect(argumentSchema['required'], isNotEmpty);
      expect(argumentSchema.containsKey('example'), isFalse);
      expect(argumentSchema['exampleShape'].toString(), contains('<string>'));
    });

    test('the documentation dialect still keeps its examples', () {
      // The published contract is unchanged; only the execution-facing
      // projection is neutralized.
      final descriptors = ToolRegistry.standard().descriptors(
        allowlist: const <String>{'apply_patch'},
        dialect: ToolDescriptorDialect.model,
      );
      expect(descriptors.toString(), contains('README.md'));
    });

    test('a neutralized repair example keeps shape, drops content', () {
      final contract = ToolRegistry.standard().contractFor('apply_patch');
      final neutral = contract.neutralizedRepairExample();
      final rendered = neutral.toString();
      expect(neutral['action'], 'tool');
      expect(neutral['tool'], 'apply_patch');
      for (final dummy in dummies) {
        expect(rendered.contains(dummy), isFalse, reason: rendered);
      }
      expect(rendered, contains('<string>'));
    });
  });

  group('CASE E: repeated identical invalid actions', () {
    ProtocolRecoveryDecision invalid(
      ProtocolRecoveryPolicy policy, {
      required Object? receivedAction,
      Object? requestedTool,
      String errorCode = 'model_tool_not_allowed',
      Duration elapsed = Duration.zero,
      bool fallbackAvailable = true,
    }) =>
        policy.onInvalidDecision(
          errorCode: errorCode,
          receivedAction: receivedAction,
          requestedTool: requestedTool,
          elapsed: elapsed,
          fallbackAvailable: fallbackAvailable,
        );

    test('the same invalid action in a new shape is recognized', () {
      // These three are byte-different and semantically identical --
      // exactly what the real model produced.
      final a = ProtocolRecoveryPolicy.signatureFor(
        errorCode: 'model_tool_not_allowed',
        receivedAction: 'tool',
        requestedTool: 'create_project',
      );
      final b = ProtocolRecoveryPolicy.signatureFor(
        errorCode: 'model_tool_not_allowed',
        receivedAction: 'TOOL',
        requestedTool: 'create-project',
      );
      expect(b, a);
      final different = ProtocolRecoveryPolicy.signatureFor(
        errorCode: 'model_tool_not_allowed',
        receivedAction: 'tool',
        requestedTool: 'write_file',
      );
      expect(different, isNot(a));
    });

    test(
        'a repeat escalates immediately instead of paying for another '
        'model call', () {
      final policy = ProtocolRecoveryPolicy();
      final first = invalid(
        policy,
        receivedAction: 'tool',
        requestedTool: 'create_project',
        elapsed: const Duration(seconds: 80),
      );
      expect(first.action, ProtocolRecoveryAction.requestCorrection);
      expect(first.repeated, isFalse);

      final second = invalid(
        policy,
        receivedAction: 'tool',
        requestedTool: 'create-project',
        elapsed: const Duration(seconds: 160),
      );
      expect(second.repeated, isTrue);
      expect(second.action, ProtocolRecoveryAction.useDeterministicFallback);
      // Only ONE correction was ever requested.
      expect(policy.attempts, 1);
    });

    test('a repeat with no safe fallback stops promptly', () {
      final policy = ProtocolRecoveryPolicy();
      invalid(policy, receivedAction: 'tool', requestedTool: 'create_project');
      final second = invalid(
        policy,
        receivedAction: 'tool',
        requestedTool: 'create_project',
        fallbackAvailable: false,
      );
      expect(second.action, ProtocolRecoveryAction.stop);
    });

    test('a bounded number of DISTINCT failures still ends', () {
      final policy = ProtocolRecoveryPolicy();
      expect(
        invalid(policy, receivedAction: 'a').action,
        ProtocolRecoveryAction.requestCorrection,
      );
      expect(
        invalid(policy, receivedAction: 'b').action,
        ProtocolRecoveryAction.requestCorrection,
      );
      expect(
        invalid(policy, receivedAction: 'c').action,
        ProtocolRecoveryAction.useDeterministicFallback,
      );
    });

    test('slow protocol recovery is bounded by elapsed recovery time', () {
      final policy = ProtocolRecoveryPolicy(
        maxRecoveryWithoutProgress: const Duration(minutes: 6),
      );
      // Recovery time is measured from the FIRST failure, not from the
      // start of the task, so a slow-but-correct model is unaffected.
      final first = invalid(
        policy,
        receivedAction: 'a',
        elapsed: const Duration(minutes: 30),
      );
      expect(first.action, ProtocolRecoveryAction.requestCorrection);
      expect(first.elapsed, Duration.zero);

      final later = invalid(
        policy,
        receivedAction: 'b',
        elapsed: const Duration(minutes: 37),
      );
      expect(later.action, ProtocolRecoveryAction.useDeterministicFallback);
      expect(later.reason, contains('without a valid action'));
    });
  });

  group('CASE F: recovery state resets on progress, not on new bytes', () {
    test('real progress clears the streak; rewording does not', () {
      final policy = ProtocolRecoveryPolicy();
      final first = policy.onInvalidDecision(
        errorCode: 'model_tool_not_allowed',
        receivedAction: 'tool',
        requestedTool: 'create_project',
        elapsed: Duration.zero,
        fallbackAvailable: true,
      );
      expect(first.action, ProtocolRecoveryAction.requestCorrection);

      // A valid decision followed by a REAL tool failure: the tool ran,
      // so protocol recovery is over even though the item is not done.
      policy.recordProgress();
      expect(policy.attempts, 0);
      expect(policy.isRecovering, isFalse);

      // The same invalid action much later is treated as new, because
      // genuine progress happened in between.
      final afterProgress = policy.onInvalidDecision(
        errorCode: 'model_tool_not_allowed',
        receivedAction: 'tool',
        requestedTool: 'create_project',
        elapsed: const Duration(minutes: 4),
        fallbackAvailable: true,
      );
      expect(afterProgress.repeated, isFalse);
      expect(afterProgress.action, ProtocolRecoveryAction.requestCorrection);
    });

    test('a real tool failure is not a protocol failure', () {
      // Tool errors carry their own codes and never enter the protocol
      // recovery signature space.
      final protocolSignature = ProtocolRecoveryPolicy.signatureFor(
        errorCode: 'model_tool_not_allowed',
        receivedAction: 'tool',
        requestedTool: 'write_file',
      );
      final toolSignature = ProtocolRecoveryPolicy.signatureFor(
        errorCode: 'path_outside_project',
        receivedAction: 'tool',
        requestedTool: 'write_file',
      );
      expect(toolSignature, isNot(protocolSignature));
    });
  });
}
