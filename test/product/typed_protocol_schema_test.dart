import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/agent_decision.dart';
import 'package:kristin_local_agent/product/agent_protocol.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/generated/protocol_contracts.g.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/tool_schema.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

void main() {
  const item = WorkItem(
    id: 'typed-protocol',
    title: 'Create the requested artifact',
    description: 'Write docs/design/wireframes.md with complete Markdown.',
    dependencies: <String>{},
    allowedTools: <String>{
      'write_file',
      'read_file',
      'inspect_file',
      'list_directory',
      'run_command',
    },
    acceptanceCriteria: <String>['The Markdown artifact is non-empty.'],
  );

  group('generated tool schema registry', () {
    test('covers every executable governed tool exactly once', () {
      const schemas = ToolSchemaRegistry();
      final tools = ToolRegistry.standard();

      expect(generatedToolRegistryVersion, '2.0.0');
      expect(generatedAgentDecisionSchemaVersion, '1.0.0');
      expect(generatedProtocolContractDigest, hasLength(64));
      expect(schemas.names, hasLength(23));
      expect(tools.names, schemas.names);
      expect(schemas.names, containsAll(generatedToolNames));
    });

    test('write_file fails closed when canonical content is absent', () {
      const schemas = ToolSchemaRegistry();

      expect(
        () => schemas.normalizeAndValidate(
          'write_file',
          <String, dynamic>{'path': 'docs/result.md'},
        ),
        throwsA(
          isA<ToolSchemaException>()
              .having((error) => error.code, 'code', 'argument_required')
              .having(
                (error) => error.details['argument'],
                'argument',
                'content',
              )
              .having(
                (error) => error.details['retryability'],
                'retryability',
                'model_correction',
              ),
        ),
      );
    });

    test('aliases are promoted without losing canonical field values', () {
      const schemas = ToolSchemaRegistry();
      const content = '# Exact content\n\nKeep `\${value}` and all whitespace.\n';
      final normalized = schemas.normalizeAndValidate(
        'write_file',
        <String, dynamic>{
          'filePath': 'docs/result.md',
          'body': content,
          'expected_exists': false,
        },
      );

      expect(normalized.arguments['path'], 'docs/result.md');
      expect(normalized.arguments['content'], content);
      expect(normalized.arguments['expectedExists'], isFalse);
      expect(normalized.arguments, isNot(contains('filePath')));
      expect(normalized.arguments, isNot(contains('body')));
      expect(normalized.changed, isTrue);
    });

    test('unknown authority-bearing arguments are rejected', () {
      const schemas = ToolSchemaRegistry();

      expect(
        () => schemas.normalizeAndValidate(
          'run_command',
          <String, dynamic>{
            'executable': 'dart',
            'args': <String>['test'],
            'workingDirectory': '/tmp/outside',
          },
        ),
        throwsA(
          isA<ToolSchemaException>().having(
            (error) => error.code,
            'code',
            'argument_unknown',
          ),
        ),
      );
    });

    test('provider and MCP descriptors come from the same contract', () {
      const schemas = ToolSchemaRegistry();
      final openAi = schemas.descriptors(
        allowlist: const <String>{'write_file'},
        dialect: ToolDescriptorDialect.openAiCompatible,
      ).single;
      final mcp = schemas.descriptors(
        allowlist: const <String>{'write_file'},
        dialect: ToolDescriptorDialect.mcp,
      ).single;

      expect(openAi['type'], 'function');
      expect(
        ((openAi['function'] as Map)['parameters'] as Map)['required'],
        containsAll(<String>['path', 'content']),
      );
      expect((openAi['function'] as Map)['strict'], isTrue);
      expect((mcp['inputSchema'] as Map)['additionalProperties'], isFalse);
      expect((mcp['outputSchema'] as Map)['type'], 'object');
    });

    test('mutating tool output is schema checked', () {
      final contract = const ToolSchemaRegistry().require('write_file');
      contract.validateOutput(<String, dynamic>{
        'ok': true,
        'summary': 'created docs/result.md.',
        'mutated': true,
        'data': <String, dynamic>{
          'id': 'mutation_1',
          'operation': 'create',
          'relativePath': 'docs/result.md',
          'existed': false,
          'beforeHash': '',
          'afterHash': List<String>.filled(64, 'a').join(),
          'backupPath': '',
          'timestamp': '2026-07-22T00:00:00.000Z',
        },
      });

      expect(
        () => contract.validateOutput(<String, dynamic>{
          'ok': true,
          'summary': 'invalid',
          'mutated': true,
          'data': <String, dynamic>{'operation': 'create'},
        }),
        throwsA(
          isA<ToolSchemaException>().having(
            (error) => error.code,
            'code',
            'tool_output_invalid',
          ),
        ),
      );
    });
  });

  group('typed AgentDecision protocol', () {
    test('supports all canonical decision variants', () {
      const codec = AgentDecisionCodec();

      expect(
        codec.decodeCanonical(<String, dynamic>{
          'action': 'tool',
          'tool': 'read_file',
          'arguments': <String, dynamic>{'path': 'README.md'},
        }),
        isA<ToolDecision>(),
      );
      expect(
        codec.decodeCanonical(<String, dynamic>{
          'action': 'complete',
          'summary': 'Verified.',
        }),
        isA<CompleteDecision>(),
      );
      expect(
        codec.decodeCanonical(<String, dynamic>{
          'action': 'fail',
          'reason': 'Policy rejected the operation.',
        }),
        isA<FailDecision>(),
      );
      expect(
        codec.decodeCanonical(<String, dynamic>{
          'action': 'ask_user',
          'question': 'Which approved target should be used?',
        }),
        isA<AskUserDecision>(),
      );
      expect(
        codec.decodeCanonical(<String, dynamic>{
          'action': 'delegate',
          'delegateTo': 'verifier',
          'task': 'Verify artifact evidence independently.',
        }),
        isA<DelegateDecision>(),
      );
    });

    test('canonical failure metadata survives direct and recorded envelopes', () {
      const adapter = AgentProtocolAdapter();
      final payload = <String, dynamic>{
        'action': 'fail',
        'summary': 'The approved dependency is unavailable.',
        'code': 'resource_unavailable',
        'retryable': true,
        'reason': 'Provider health check failed.',
      };

      final direct = adapter.parseDecision(
        jsonEncode(payload),
        item: item,
        allowPlainCompletion: false,
      );
      final recorded = adapter.parseDecision(
        jsonEncode(<String, dynamic>{'normalizedAction': payload}),
        item: item,
        allowPlainCompletion: false,
        provider: AgentProviderProtocol.recorded,
      );

      for (final decision in <AgentDecision>[direct, recorded]) {
        expect(decision, isA<FailDecision>());
        final failure = decision as FailDecision;
        expect(failure.code, 'resource_unavailable');
        expect(failure.retryable, isTrue);
        expect(failure.summary, 'The approved dependency is unavailable.');
        expect(failure.reason, 'Provider health check failed.');
      }
    });

    test('current coordinator bridge rejects future decision kinds', () {
      const adapter = AgentProtocolAdapter();

      expect(
        () => adapter.parse(
          jsonEncode(<String, dynamic>{
            'action': 'ask_user',
            'question': 'Need a target.',
          }),
          item: item,
          allowPlainCompletion: false,
        ),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'model_decision_not_supported',
          ),
        ),
      );
    });

    test('provider adapters preserve the same canonical tool decision', () {
      const adapter = AgentProtocolAdapter();
      const arguments = <String, dynamic>{
        'path': 'docs/provider.md',
        'content': '# Provider-safe\n',
      };
      final envelopes = <(AgentProviderProtocol, String)>[
        (
          AgentProviderProtocol.ollama,
          jsonEncode(<String, dynamic>{
            'message': <String, dynamic>{
              'role': 'assistant',
              'content': jsonEncode(<String, dynamic>{
                'action': 'tool',
                'tool': 'write_file',
                'arguments': arguments,
              }),
            },
          }),
        ),
        (
          AgentProviderProtocol.openAiCompatible,
          jsonEncode(<String, dynamic>{
            'choices': <Object?>[
              <String, dynamic>{
                'message': <String, dynamic>{
                  'tool_calls': <Object?>[
                    <String, dynamic>{
                      'type': 'function',
                      'function': <String, dynamic>{
                        'name': 'write_file',
                        'arguments': jsonEncode(arguments),
                      },
                    },
                  ],
                },
              },
            ],
          }),
        ),
        (
          AgentProviderProtocol.mcp,
          jsonEncode(<String, dynamic>{
            'structuredContent': <String, dynamic>{
              'action': 'tool',
              'tool': 'write_file',
              'arguments': arguments,
            },
          }),
        ),
        (
          AgentProviderProtocol.recorded,
          jsonEncode(<String, dynamic>{
            'normalizedAction': <String, dynamic>{
              'action': 'tool',
              'tool': 'write_file',
              'arguments': arguments,
            },
          }),
        ),
      ];

      for (final envelope in envelopes) {
        final action = adapter.parse(
          envelope.$2,
          item: item,
          allowPlainCompletion: false,
          provider: envelope.$1,
        );
        expect(action.kind, 'tool');
        expect(action.tool, 'write_file');
        expect(action.arguments['path'], arguments['path']);
        expect(action.arguments['content'], arguments['content']);
      }
    });

    test('legacy scalar action_input is consumed into the canonical path', () {
      const adapter = AgentProtocolAdapter();
      final action = adapter.parse(
        '{"action":"inspect_project","action_input":"."}',
        item: item,
        allowPlainCompletion: false,
      );

      expect(action.tool, 'list_directory');
      expect(action.arguments['path'], '.');
      expect(action.arguments, isNot(contains('action_input')));
    });

    test('legacy command vectors become canonical executable and args', () {
      const adapter = AgentProtocolAdapter();
      final action = adapter.parse(
        jsonEncode(<String, dynamic>{
          'action': 'tool',
          'tool': 'run_command',
          'command': <String>['dart', 'test', '--reporter=expanded'],
        }),
        item: item,
        allowPlainCompletion: false,
      );

      expect(action.tool, 'run_command');
      expect(action.arguments['executable'], 'dart');
      expect(action.arguments['args'], <String>['test', '--reporter=expanded']);
      expect(action.arguments, isNot(contains('command')));
    });

    test('deterministic envelope fuzzing never loses write content', () {
      const adapter = AgentProtocolAdapter();
      final random = Random(120);
      const aliases = <String>['content', 'body', 'fileContent', 'new_content'];

      for (var index = 0; index < 300; index++) {
        final content = 'case-$index-${random.nextInt(1 << 30)}\n'
            "${List<String>.filled(random.nextInt(80), 'x').join()}";
        final path = index.isEven
            ? '`docs/fuzz-$index.md`'
            : 'docs/fuzz-$index.md';
        final payload = <String, dynamic>{
          'action': 'tool_call',
          'tool': index % 5 == 0 ? 'write' : 'write_file',
          'arguments': <String, dynamic>{
            index % 3 == 0 ? 'filePath' : 'path': path,
            aliases[index % aliases.length]: content,
          },
        };
        final wrapped = switch (index % 4) {
          0 => jsonEncode(payload),
          1 => jsonEncode(<String, dynamic>{
              'message': <String, dynamic>{'content': jsonEncode(payload)},
            }),
          2 => 'analysis before action\n```json\n${jsonEncode(payload)}\n```',
          _ => jsonEncode(<String, dynamic>{'decision': payload}),
        };

        final action = adapter.parse(
          wrapped,
          item: item,
          allowPlainCompletion: false,
        );
        expect(action.tool, 'write_file', reason: 'case $index');
        expect(
          action.arguments['path'],
          'docs/fuzz-$index.md',
          reason: 'case $index path',
        );
        expect(
          action.arguments['content'],
          content,
          reason: 'case $index content',
        );
      }
    });

    test('fuzzed missing mutation data cannot reach dispatch', () {
      const adapter = AgentProtocolAdapter();

      for (var index = 0; index < 50; index++) {
        final payload = jsonEncode(<String, dynamic>{
          'action': 'tool',
          'tool': 'write_file',
          'arguments': <String, dynamic>{'path': 'docs/missing-$index.md'},
        });
        expect(
          () => adapter.parse(
            payload,
            item: item,
            allowPlainCompletion: false,
          ),
          throwsA(
            isA<ProductException>().having(
              (error) => error.code,
              'code',
              'argument_required',
            ),
          ),
        );
      }
    });
  });
}
