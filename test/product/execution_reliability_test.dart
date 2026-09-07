import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/agent_protocol.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/planning_runtime.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

void main() {
  group('chat-first planning', () {
    final project = ProjectRecord(
      id: 'project-test',
      name: 'Test project',
      rootPath: Directory.current.path,
      createdAt: DateTime.utc(2026, 7, 16),
      updatedAt: DateTime.utc(2026, 7, 16),
    );
    final model = ModelIdentity(
      providerId: 'ollama',
      name: 'test-model',
      digest: 'sha256:test',
      discoveredAt: DateTime.utc(2026, 7, 16),
    );

    test('a greeting becomes one model-only work item with no permissions', () {
      final prepared = const ContractPlanner().prepare(
        project: project,
        mode: CommandMode.ask,
        request: 'hi',
        model: model,
      );

      expect(prepared.contract.requiredPermissions, isEmpty);
      expect(prepared.plan.items, hasLength(1));
      expect(prepared.plan.items.single.title, 'Respond conversationally');
      expect(prepared.plan.items.single.allowedTools, isEmpty);
      expect(
        prepared.plan.items.any(
          (item) => item.title.contains('Inspect project'),
        ),
        isFalse,
      );
    });

    test('a project question uses one grounded answer node', () {
      final prepared = const ContractPlanner().prepare(
        project: project,
        mode: CommandMode.ask,
        request: 'Which file defines the local API server?',
        model: model,
      );

      expect(
        prepared.contract.requiredPermissions,
        contains(PermissionScope.projectRead),
      );
      expect(prepared.plan.items, hasLength(1));
      expect(prepared.plan.items.single.title, 'Answer from grounded context');
      expect(prepared.plan.items.single.allowedTools, contains('read_file'));
      expect(
        prepared.plan.items.any(
          (item) => item.title.contains('Inspect project'),
        ),
        isFalse,
      );
    });
  });

  group('failed-memory intent policy', () {
    test(
      'does not treat application error handling or history as a failed-run investigation',
      () {
        expect(
          isFailureInvestigationRequest(
            'Build a calculator with calculation history, input validation, error handling, and responsive tests.',
          ),
          isFalse,
        );
        expect(
          isFailureInvestigationRequest(
            'What went wrong with calculator error handling and input validation?',
          ),
          isFalse,
        );
        expect(
          isFailureInvestigationRequest('What went wrong in the previous run?'),
          isTrue,
        );
        expect(
          isFailureInvestigationRequest(
            'Why did the previous Kristin run fail?',
          ),
          isTrue,
        );
        expect(
          isFailureInvestigationRequest(
            'Retry the failed task from the last run.',
          ),
          isTrue,
        );
      },
    );
  });

  group('model action compatibility', () {
    test('accepts OpenAI-style nested function calls', () {
      final action = AgentAction.fromJson(<String, dynamic>{
        'tool_calls': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'function',
            'function': <String, dynamic>{
              'name': 'read_file',
              'arguments': '{"path":"README.md"}',
            },
          },
        ],
      });

      expect(action.kind, 'tool');
      expect(action.tool, 'read_file');
      expect(action.arguments, <String, dynamic>{'path': 'README.md'});
    });

    test('infers completion from answer-only JSON', () {
      final action = AgentAction.fromJson(<String, dynamic>{
        'answer': 'Hello from Kristin.',
      });

      expect(action.kind, 'complete');
      expect(action.summary, 'Hello from Kristin.');
    });

    test('normalizes common completion synonyms', () {
      final action = AgentAction.fromJson(<String, dynamic>{
        'action': 'done',
        'result': 'The task is complete.',
      });

      expect(action.kind, 'complete');
      expect(action.summary, 'The task is complete.');
    });
  });

  test('Ollama provider consumes streamed NDJSON responses', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var warmupRequested = false;
    var streamingRequested = false;
    final subscription = server.listen((request) async {
      if (request.uri.path == '/api/tags') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, dynamic>{
            'models': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'tiny-model',
                'digest': 'sha256:tiny',
                'details': <String, dynamic>{
                  'parameter_size': '1B',
                  'quantization_level': 'Q4',
                },
              },
            ],
          }),
        );
        await request.response.close();
        return;
      }
      if (request.uri.path == '/api/generate') {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body);
        final streaming = decoded is Map && decoded['stream'] == true;
        if (!streaming) {
          warmupRequested = true;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, dynamic>{'done': true, 'load_duration': 1000}),
          );
          await request.response.close();
          return;
        }
        streamingRequested = true;
        request.response.headers.contentType = ContentType(
          'application',
          'x-ndjson',
          charset: 'utf-8',
        );
        request.response.writeln(
          jsonEncode(<String, dynamic>{
            'response': '{"action":"complete",',
            'done': false,
          }),
        );
        await request.response.flush();
        request.response.writeln(
          jsonEncode(<String, dynamic>{
            'response': '"summary":"Hello."}',
            'done': false,
          }),
        );
        request.response.writeln(
          jsonEncode(<String, dynamic>{
            'response': '',
            'done': true,
            'prompt_eval_count': 12,
            'eval_count': 8,
          }),
        );
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    try {
      final provider = OllamaProvider(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        redactor: SecretRedactor(),
      );
      final identity = ModelIdentity(
        providerId: 'ollama',
        name: 'tiny-model',
        digest: 'sha256:tiny',
        discoveredAt: DateTime.now().toUtc(),
      );
      final result = await provider.generate(
        ModelGenerationRequest(
          identity: identity,
          systemPrompt: 'Return JSON.',
          userPrompt: 'Say hello.',
          commandId: 'command-test',
          loadTimeout: const Duration(seconds: 2),
          loadRetries: 0,
          firstTokenTimeout: const Duration(seconds: 2),
          totalTimeout: const Duration(seconds: 5),
        ),
      );

      expect(warmupRequested, isTrue);
      expect(streamingRequested, isTrue);
      expect(result.text, '{"action":"complete","summary":"Hello."}');
      expect(result.inputTokens, 12);
      expect(result.outputTokens, 8);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test(
    'Ollama retries a transient cold-load timeout inside one model turn',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final firstWarmupStarted = Completer<void>();
      final secondWarmupStarted = Completer<void>();
      final firstWarmupFinished = Completer<void>();
      var warmupAttempts = 0;
      var generationRequests = 0;
      final progressStages = <String>[];
      final subscription = server.listen((request) async {
        if (request.uri.path == '/api/tags') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, dynamic>{
              'models': <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': 'tiny-model',
                  'digest': 'sha256:tiny',
                  'details': <String, dynamic>{
                    'parameter_size': '1B',
                    'quantization_level': 'Q4',
                  },
                },
              ],
            }),
          );
          await request.response.close();
          return;
        }
        if (request.uri.path == '/api/generate') {
          final body = await utf8.decoder.bind(request).join();
          final decoded = jsonDecode(body);
          final streaming = decoded is Map && decoded['stream'] == true;
          if (!streaming) {
            warmupAttempts++;
            if (warmupAttempts == 1) {
              if (!firstWarmupStarted.isCompleted) {
                firstWarmupStarted.complete();
              }
              try {
                // Keep the first response open. The provider must hit its bounded
                // deadline and issue a second request before this fixture releases it.
                await secondWarmupStarted.future.timeout(
                  const Duration(seconds: 8),
                );
                request.response.headers.contentType = ContentType.json;
                request.response.write(
                  jsonEncode(<String, dynamic>{
                    'done': true,
                    'load_duration': 9000000000,
                  }),
                );
                await request.response.close();
              } catch (_) {
                // The first client is expected to close when the deadline fires.
              } finally {
                if (!firstWarmupFinished.isCompleted) {
                  firstWarmupFinished.complete();
                }
              }
              return;
            }
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(<String, dynamic>{
                'done': true,
                'load_duration': 2000,
              }),
            );
            await request.response.close();
            if (!secondWarmupStarted.isCompleted) {
              secondWarmupStarted.complete();
            }
            return;
          }
          generationRequests++;
          request.response.headers.contentType = ContentType(
            'application',
            'x-ndjson',
            charset: 'utf-8',
          );
          request.response.writeln(
            jsonEncode(<String, dynamic>{
              'response': '{"action":"complete","summary":"Recovered."}',
              'done': false,
            }),
          );
          request.response.writeln(
            jsonEncode(<String, dynamic>{'response': '', 'done': true}),
          );
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      try {
        final provider = OllamaProvider(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          redactor: SecretRedactor(),
          defaultLoadTimeout: const Duration(seconds: 2),
          defaultLoadRetries: 1,
        );
        final identity = ModelIdentity(
          providerId: 'ollama',
          name: 'tiny-model',
          digest: 'sha256:tiny',
          discoveredAt: DateTime.now().toUtc(),
        );
        final result = await provider.generate(
          ModelGenerationRequest(
            identity: identity,
            systemPrompt: 'Return JSON.',
            userPrompt: 'Recover after a cold-load timeout.',
            commandId: 'command-retry-test',
            loadRetryDelay: Duration.zero,
            firstTokenTimeout: const Duration(seconds: 2),
            totalTimeout: const Duration(seconds: 5),
            onProgress: (progress) => progressStages.add(progress.stage),
          ),
        );

        expect(firstWarmupStarted.isCompleted, isTrue);
        expect(result.text, contains('Recovered.'));
        expect(warmupAttempts, 2);
        expect(generationRequests, 1);
        expect(
          progressStages,
          containsAllInOrder(<String>[
            'load_started',
            'load_retry_scheduled',
            'load_retry_started',
            'load_completed',
            'generation_started',
          ]),
        );
        expect(result.providerDetails['warmupAttempts'], 2);
      } finally {
        if (!secondWarmupStarted.isCompleted) {
          secondWarmupStarted.complete();
        }
        if (firstWarmupStarted.isCompleted &&
            !firstWarmupFinished.isCompleted) {
          await firstWarmupFinished.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () {},
          );
        }
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );

  test('cancelling a run closes an in-flight Ollama cold load', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final warmupRequestStarted = Completer<void>();
    final releaseWarmupResponse = Completer<void>();
    final warmupRequestFinished = Completer<void>();
    final subscription = server.listen((request) async {
      if (request.uri.path == '/api/tags') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, dynamic>{
            'models': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'tiny-model',
                'digest': 'sha256:tiny',
                'details': <String, dynamic>{},
              },
            ],
          }),
        );
        await request.response.close();
        return;
      }
      if (request.uri.path == '/api/generate') {
        await utf8.decoder.bind(request).join();
        if (!warmupRequestStarted.isCompleted) {
          warmupRequestStarted.complete();
        }
        try {
          // Keep the response pending until the client cancellation has been
          // observed. The test releases this handler during deterministic cleanup.
          await releaseWarmupResponse.future;
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"done":true}');
          await request.response.close();
        } catch (_) {
          // Cancellation closes the client before this response is released.
        } finally {
          if (!warmupRequestFinished.isCompleted) {
            warmupRequestFinished.complete();
          }
        }
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final cancellation = Completer<void>();
    try {
      final provider = OllamaProvider(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        redactor: SecretRedactor(),
        defaultLoadTimeout: const Duration(seconds: 5),
        defaultLoadRetries: 0,
      );
      final identity = ModelIdentity(
        providerId: 'ollama',
        name: 'tiny-model',
        digest: 'sha256:tiny',
        discoveredAt: DateTime.now().toUtc(),
      );
      final future = provider.generate(
        ModelGenerationRequest(
          identity: identity,
          systemPrompt: 'Return JSON.',
          userPrompt: 'This request will be cancelled.',
          commandId: 'command-cancel-test',
          cancellation: cancellation.future,
        ),
      );
      await warmupRequestStarted.future.timeout(const Duration(seconds: 5));
      cancellation.complete();

      await expectLater(
        future,
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'cancelled',
          ),
        ),
      );
    } finally {
      if (!releaseWarmupResponse.isCompleted) {
        releaseWarmupResponse.complete();
      }
      if (warmupRequestStarted.isCompleted &&
          !warmupRequestFinished.isCompleted) {
        await warmupRequestFinished.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      }
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  group('v1.0.1 model protocol compatibility', () {
    const adapter = AgentProtocolAdapter();
    const item = WorkItem(
      id: 'protocol-item',
      title: 'Inspect project and establish evidence baseline',
      description: 'Collect bounded evidence before implementation.',
      dependencies: <String>{},
      allowedTools: <String>{'list_directory', 'read_file', 'search_text'},
      acceptanceCriteria: <String>['Project evidence is recorded.'],
    );

    test('accepts snake-case function_call envelopes', () {
      final action = adapter.parse(
        jsonEncode(<String, dynamic>{
          'function_call': <String, dynamic>{
            'name': 'read_file',
            'arguments': '{"path":"README.md"}',
          },
        }),
        item: item,
        allowPlainCompletion: false,
      );

      expect(action.kind, 'tool');
      expect(action.tool, 'read_file');
      expect(action.arguments['path'], 'README.md');
    });

    test('normalizes safe tool and argument aliases', () {
      final action = adapter.parse(
        '{"action":"inspect_project","action_input":"."}',
        item: item,
        allowPlainCompletion: false,
      );

      expect(action.kind, 'tool');
      expect(action.tool, 'list_directory');
      expect(action.arguments['path'], '.');
    });

    test(
      'preserves canonical path nested directly inside an action object',
      () {
        final action = adapter.parse(
          jsonEncode(<String, dynamic>{
            'action': <String, dynamic>{
              'type': 'read_file',
              'path': 'README.md',
            },
          }),
          item: item,
          allowPlainCompletion: false,
        );

        expect(action.kind, 'tool');
        expect(action.tool, 'read_file');
        expect(action.arguments['path'], 'README.md');
      },
    );

    test(
      'preserves direct nested write content from the observed failure envelope',
      () {
        const writeItem = WorkItem(
          id: 'wireframe-write-item',
          title: 'Create project-local calculator wireframes',
          description: 'Write `docs/design/wireframes.md`.',
          dependencies: <String>{},
          allowedTools: <String>{'write_file', 'inspect_file'},
          acceptanceCriteria: <String>['The wireframe artifact is written.'],
        );
        const content = '# Calculator wireframes\nKeyboard and touch flows.';
        final action = adapter.parse(
          jsonEncode(<String, dynamic>{
            'action': <String, dynamic>{
              'type': 'write_file',
              'id': 'task_001',
              'filePath': 'docs/design/wireframes.md',
              'content': content,
              'complexity': 1,
              'effort': 2,
              'risk': 'medium',
            },
          }),
          item: writeItem,
          allowPlainCompletion: false,
        );

        expect(action.kind, 'tool');
        expect(action.tool, 'write_file');
        expect(action.arguments['path'], 'docs/design/wireframes.md');
        expect(action.arguments['content'], content);
      },
    );

    test('unwraps double-encoded response objects', () {
      final action = adapter.parse(
        jsonEncode(<String, dynamic>{
          'response': jsonEncode(<String, dynamic>{
            'action': 'final_answer',
            'final_answer': 'The project evidence is ready.',
          }),
        }),
        item: item,
        allowPlainCompletion: false,
      );

      expect(action.kind, 'complete');
      expect(action.summary, 'The project evidence is ready.');
    });

    test('unwraps chat-completion choices and tool_input aliases', () {
      final action = adapter.parse(
        jsonEncode(<String, dynamic>{
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'message': <String, dynamic>{
                'content': jsonEncode(<String, dynamic>{
                  'action': 'tool_call',
                  'tool_name': 'read_file',
                  'tool_input': <String, dynamic>{'file_path': 'README.md'},
                }),
              },
            },
          ],
        }),
        item: item,
        allowPlainCompletion: false,
      );

      expect(action.kind, 'tool');
      expect(action.tool, 'read_file');
      expect(action.arguments['path'], 'README.md');
    });

    test(
      'unwraps message envelopes instead of treating them as completion',
      () {
        final action = adapter.parse(
          jsonEncode(<String, dynamic>{
            'type': 'message',
            'content': jsonEncode(<String, dynamic>{
              'action': 'tool',
              'tool': 'read_file',
              'arguments': <String, dynamic>{'path': 'README.md'},
            }),
          }),
          item: item,
          allowPlainCompletion: false,
        );

        expect(action.kind, 'tool');
        expect(action.tool, 'read_file');
        expect(action.arguments['path'], 'README.md');
      },
    );

    test('accepts bounded ReAct-style action output', () {
      final action = adapter.parse(
        'Thought: inspect the readme first.\n'
        'Action: read_file\n'
        'Action Input: {"file":"README.md"}',
        item: item,
        allowPlainCompletion: false,
      );

      expect(action.kind, 'tool');
      expect(action.tool, 'read_file');
      expect(action.arguments['path'], 'README.md');
    });

    test(
      'uses an explicit allowed tool even with a nonstandard action verb',
      () {
        final action = adapter.parse(
          '{"action":"continue","tool":"read_file",'
          '"parameters":{"file":"README.md"}}',
          item: item,
          allowPlainCompletion: false,
        );

        expect(action.kind, 'tool');
        expect(action.tool, 'read_file');
        expect(action.arguments['path'], 'README.md');
      },
    );

    test(
      'accepts nested completion payloads and boolean completion signals',
      () {
        final action = adapter.parse(
          jsonEncode(<String, dynamic>{
            'action': 'conclusion',
            'done': true,
            'result': <String, dynamic>{'summary': 'Inspection is complete.'},
          }),
          item: item,
          allowPlainCompletion: false,
        );

        expect(action.kind, 'complete');
        expect(action.summary, 'Inspection is complete.');
      },
    );

    test('prefers a direct canonical decision over nested content', () {
      final action = adapter.parse(
        jsonEncode(<String, dynamic>{
          'action': 'complete',
          'summary': 'The bounded inspection is complete.',
          'content': jsonEncode(<String, dynamic>{
            'action': 'tool',
            'tool': 'read_file',
            'arguments': <String, dynamic>{'path': 'README.md'},
          }),
        }),
        item: item,
        allowPlainCompletion: false,
      );

      expect(action.kind, 'complete');
      expect(action.summary, 'The bounded inspection is complete.');
    });

    test(
      'normalizes the observed composite planning action without failed-memory opt-in',
      () {
        const informationItem = WorkItem(
          id: 'information-item',
          title: 'Gather Development Tools and Libraries Information',
          description:
              'Review locally archived documentation and information about suitable frameworks and libraries.',
          dependencies: <String>{},
          allowedTools: <String>{
            'knowledge_search',
            'list_directory',
            'read_file',
          },
          acceptanceCriteria: <String>['Relevant information is grounded.'],
        );
        final action = adapter.parse(
          jsonEncode(<String, dynamic>{
            'action': 'inspect_project_and_establish_evidence_baseline',
            'task_id': '[K8]',
            'description': 'Review existing project documentation.',
          }),
          item: informationItem,
          allowPlainCompletion: false,
        );

        expect(action.kind, 'tool');
        expect(action.tool, 'knowledge_search');
        expect(action.arguments['query'], contains('Development Tools'));
        expect(action.arguments['includeUnsuccessfulEpisodes'], isFalse);
        expect(action.reason, contains('Compatibility normalization'));
      },
    );

    test('preserves nested command arrays in the domain action model', () {
      final action = AgentAction.fromJson(<String, dynamic>{
        'action': <String, dynamic>{
          'type': 'run_command',
          'command': <String>['git', '-C', '/outside/project', 'status'],
        },
      });

      expect(action.kind, 'run_command');
      expect(action.arguments['command'], <String>[
        'git',
        '-C',
        '/outside/project',
        'status',
      ]);
    });

    test(
      'normalizes the observed nested command vector to project-scoped Git status',
      () {
        const commandItem = WorkItem(
          id: 'command-item',
          title: 'Inspect project state',
          description: 'Collect bounded project status evidence.',
          dependencies: <String>{},
          allowedTools: <String>{'run_command', 'git_status'},
          acceptanceCriteria: <String>['Project state is recorded.'],
        );
        final action = adapter.parse(
          jsonEncode(<String, dynamic>{
            'action': <String, dynamic>{
              'type': 'run_command',
              'command': <String>[
                'git',
                '-C',
                '/MathWebApp/project-directory',
                'status',
              ],
            },
          }),
          item: commandItem,
          allowPlainCompletion: false,
        );

        expect(action.kind, 'tool');
        expect(action.tool, 'git_status');
        expect(action.arguments, isEmpty);
        expect(action.reason, contains('project-scoped git_status'));
      },
    );

    test(
      'preserves a generic nested command vector as executable and args',
      () {
        const commandItem = WorkItem(
          id: 'generic-command-item',
          title: 'Run a project check',
          description: 'Execute a bounded existing project command.',
          dependencies: <String>{},
          allowedTools: <String>{'run_command'},
          acceptanceCriteria: <String>['The command result is recorded.'],
        );
        final action = adapter.parse(
          jsonEncode(<String, dynamic>{
            'action': <String, dynamic>{
              'type': 'run_command',
              'command': <String>['node', 'tool/check.js', '--json'],
            },
          }),
          item: commandItem,
          allowPlainCompletion: false,
        );

        expect(action.tool, 'run_command');
        expect(action.arguments['executable'], 'node');
        expect(action.arguments['args'], <String>['tool/check.js', '--json']);
      },
    );

    test('does not normalize a tool outside the work-item allowlist', () {
      expect(
        () => adapter.parse(
          '{"action":"tool","tool":"run_command",'
          '"arguments":{"executable":"dart"}}',
          item: item,
          allowPlainCompletion: false,
        ),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'model_tool_not_allowed',
          ),
        ),
      );
    });
  });

  group('v1.1.6 product-specific artifact evidence', () {
    const policy = ArtifactEvidencePolicy();
    const item = WorkItem(
      id: 'wireframe-item',
      title: 'Create project-local wireframes and user flows',
      description:
          'Create and inspect `docs/design/wireframes.md` for the calculator application.',
      dependencies: <String>{},
      allowedTools: <String>{'write_file', 'inspect_file'},
      acceptanceCriteria: <String>[
        'The calculator wireframes cover interaction and responsive states.',
      ],
    );

    test('requires inspected artifact evidence before bounded completion', () {
      expect(policy.requiresValidatedArtifact(item), isTrue);
      expect(
        policy.expectedArtifactPaths(item),
        contains('docs/design/wireframes.md'),
      );

      const reviewItem = WorkItem(
        id: 'wireframe-review-policy',
        title: 'Review calculator wireframes',
        description: 'Inspect `docs/design/wireframes.md` and report gaps.',
        dependencies: <String>{},
        allowedTools: <String>{'inspect_file'},
        acceptanceCriteria: <String>['Design gaps are reported.'],
      );
      expect(policy.requiresValidatedArtifact(reviewItem), isFalse);
    });

    test('rejects an unrelated commerce wireframe even when the file exists',
        () {
      final assessment = policy.assess(
        item: item,
        request:
            'Build a calculator with mouse and keyboard input, instant results, and calculation history.',
        tool: 'inspect_file',
        result: const ToolResult(
          ok: true,
          summary: 'Inspected docs/design/wireframes.md.',
          data: <String, dynamic>{
            'path': 'docs/design/wireframes.md',
            'sha256': 'commerce-hash',
            'content':
                'Screen hierarchy: product listing, product detail, shopping cart, and checkout. Responsive mobile layout and hover states.',
          },
        ),
        mutatedPaths: const <String>{'docs/design/wireframes.md'},
      );

      expect(assessment.state, ArtifactEvidenceState.incomplete);
      expect(
        assessment.missingCoverage,
        containsAll(<String>[
          'calculator or arithmetic product scope',
          'keyboard interaction',
          'calculation history',
          'remove unrelated commerce flows',
        ]),
      );
    });

    test('accepts a mutated calculator wireframe with required coverage', () {
      final assessment = policy.assess(
        item: item,
        request:
            'Build a calculator with mouse and keyboard input, instant results, and calculation history.',
        tool: 'inspect_file',
        result: const ToolResult(
          ok: true,
          summary: 'Inspected docs/design/wireframes.md.',
          data: <String, dynamic>{
            'path': 'docs/design/wireframes.md',
            'sha256': 'calculator-hash',
            'content': '''
Calculator screen hierarchy and responsive mobile/tablet layout.
User flow: enter operands, choose addition, subtraction, multiplication, or division, then show an instant result in the result display.
Keyboard shortcuts and pointer buttons share the same interaction flow.
A calculation history panel records the current session.
Interaction states include hover, focus, pressed, disabled, and error state.
Accessibility notes cover ARIA labels, contrast, focus order, and screen-reader output.
''',
          },
        ),
        mutatedPaths: const <String>{'docs/design/wireframes.md'},
      );

      expect(assessment.state, ArtifactEvidenceState.complete);
      expect(assessment.summary, contains('docs/design/wireframes.md'));
      expect(assessment.summary, contains('calculator-hash'));
    });

    test('accepts an already-correct artifact without forcing a rewrite', () {
      final assessment = policy.assess(
        item: item,
        request:
            'Build a touchscreen calculator with keyboard input, editable results, history, undo, and redo.',
        tool: 'inspect_file',
        result: const ToolResult(
          ok: true,
          summary: 'Inspected docs/design/wireframes.md.',
          data: <String, dynamic>{
            'path': 'docs/design/wireframes.md',
            'sha256': 'existing-hash',
            'content': '''
Calculator screen hierarchy with a responsive mobile and tablet layout.
User flow: enter values with touchscreen touch targets or keyboard shortcuts, then use +, -, *, and / operator buttons.
The editable text field shows a real-time result and supports copying to the clipboard.
A history log includes undo and redo actions.
Interaction states include hover, focus, pressed, disabled, and error state.
Accessibility notes cover ARIA labels, contrast, focus order, and screen-reader output.
''',
          },
        ),
        mutatedPaths: const <String>{},
      );

      expect(assessment.state, ArtifactEvidenceState.complete);
      expect(assessment.reason, contains('already satisfied'));
      expect(assessment.summary, startsWith('Validated'));
      expect(assessment.summary, contains('existing-hash'));
    });

    test('does not force mutation for a read-only design review', () {
      const reviewItem = WorkItem(
        id: 'wireframe-review',
        title: 'Review calculator wireframes',
        description: 'Inspect `docs/design/wireframes.md` and report gaps.',
        dependencies: <String>{},
        allowedTools: <String>{'inspect_file'},
        acceptanceCriteria: <String>['Design gaps are reported.'],
      );
      final assessment = policy.assess(
        item: reviewItem,
        request: 'Review the existing calculator design.',
        tool: 'inspect_file',
        result: const ToolResult(
          ok: true,
          summary: 'Inspected docs/design/wireframes.md.',
          data: <String, dynamic>{
            'path': 'docs/design/wireframes.md',
            'content': 'Calculator screen hierarchy and keyboard user flow.',
          },
        ),
        mutatedPaths: const <String>{},
      );

      expect(assessment.state, ArtifactEvidenceState.notApplicable);
    });
  });

  group('v1.1.7 current diagnostic replay contracts', () {
    const item = WorkItem(
      id: 'diagnostic-wireframe-item',
      title: 'Create project-local wireframes and user flows',
      description:
          'Create and inspect `docs/design/wireframes.md` for the calculator application.',
      dependencies: <String>{},
      allowedTools: <String>{
        'knowledge_search',
        'list_directory',
        'write_file',
        'inspect_file',
      },
      acceptanceCriteria: <String>[
        'The calculator wireframes cover mouse, keyboard, responsive, and accessibility behavior.',
      ],
    );
    const request =
        'Build a calculator web app with mouse and keyboard input, real-time results, and calculation history.';

    test('canonicalizes the exact Markdown-wrapped filePath envelope', () {
      const content = '# Calculator design draft';
      final action = const AgentProtocolAdapter().parse(
        jsonEncode(<String, dynamic>{
          'action': <String, dynamic>{
            'type': 'write_file',
            'filePath': '`docs/design/wireframes.md`',
            'content': content,
          },
        }),
        item: item,
        allowPlainCompletion: false,
      );

      expect(action.tool, 'write_file');
      expect(action.arguments['path'], 'docs/design/wireframes.md');
      expect(action.arguments['content'], content);
      expect(
        canonicalModelPathToken('"`docs/design/wireframes.md`"'),
        'docs/design/wireframes.md',
      );
    });

    test('normalizes Markdown wrappers at the workspace boundary', () async {
      final root = await Directory.systemTemp.createTemp('kristin-path-token-');
      try {
        final boundary = await WorkspaceBoundary.open(root.path);
        expect(
          boundary.normalizeToolPath('```docs/design/wireframes.md```'),
          'docs/design/wireframes.md',
        );
        expect(
          () => boundary.normalizeToolPath('`../outside.md`'),
          throwsA(
            isA<ProductException>().having(
              (error) => error.code,
              'code',
              'path_traversal_rejected',
            ),
          ),
        );
      } finally {
        await root.delete(recursive: true);
      }
    });

    test(
      'bounded recovery changes repeated discovery into a validated mutation',
      () {
        final recovery = const BoundedArtifactRecoveryPolicy().actionFor(
          item: item,
          request: request,
        );

        expect(recovery, isNotNull);
        final action = recovery!;
        expect(action.tool, 'write_file');
        expect(action.arguments['path'], 'docs/design/wireframes.md');
        expect(action.arguments['expectedExists'], isFalse);
        final content = action.arguments['content'] as String;
        expect(content, contains('Calculator Web Application'));
        expect(content, contains('real-time result'));
        expect(content, contains('calculation history'));

        final assessment = const ArtifactEvidencePolicy().assess(
          item: item,
          request: request,
          tool: 'inspect_file',
          result: ToolResult(
            ok: true,
            summary: 'Inspected the recovered artifact.',
            data: <String, dynamic>{
              'path': '`docs/design/wireframes.md`',
              'sha256': 'recovered-hash',
              'textPreview': content,
            },
          ),
          mutatedPaths: const <String>{'`docs/design/wireframes.md`'},
        );

        expect(assessment.state, ArtifactEvidenceState.complete);
        expect(assessment.path, 'docs/design/wireframes.md');
      },
    );

    test('hash-guards deterministic replacement of an inspected artifact', () {
      final recovery = const BoundedArtifactRecoveryPolicy().actionFor(
        item: item,
        request: request,
        expectedSha256: 'known-artifact-hash',
      );

      expect(recovery, isNotNull);
      expect(recovery!.arguments['expectedExists'], isTrue);
      expect(recovery.arguments['expectedSha256'], 'known-artifact-hash');
    });

    test('strips only exact supported whole-scalar backtick wrappers', () {
      expect(canonicalModelPathToken('docs/`draft`.md'), 'docs/`draft`.md');
      expect(
        canonicalModelPathToken('```docs/design/wireframes.md``'),
        '```docs/design/wireframes.md``',
      );
      expect(
        canonicalModelPathToken('````docs/design/wireframes.md````'),
        '````docs/design/wireframes.md````',
      );
    });

    test(
      'automatically inspects the exact expected artifact after mutation',
      () {
        final target =
            const AutomaticArtifactVerificationPolicy().inspectionTarget(
          item: item,
          mutationResult: const ToolResult(
            ok: true,
            summary: 'Created artifact.',
            data: <String, dynamic>{
              'relativePath': '`docs/design/wireframes.md`',
            },
            mutated: true,
          ),
          mutationPaths: const <String>{'`docs/design/wireframes.md`'},
        );

        expect(target, 'docs/design/wireframes.md');
      },
    );

    test('does not start a retry without a meaningful repair reserve', () {
      const policy = RunRetryBudgetPolicy();
      expect(
        policy.canStartAnotherAttempt(repairs: 10, maxRepairs: 12),
        isFalse,
      );
      expect(policy.canStartAnotherAttempt(repairs: 8, maxRepairs: 12), isTrue);
      expect(policy.remaining(repairs: 10, maxRepairs: 12), 2);
    });
  });
}
