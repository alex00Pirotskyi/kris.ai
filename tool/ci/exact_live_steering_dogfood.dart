import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/product_runtime.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

const candidateSha = 'e59583b170b2a5d333a3c6eff5243725daef0d54';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final receiptFile = File('exact-live-steering-dogfood.json');
  final receipt = <String, dynamic>{
    'candidateSha': candidateSha,
    'platform': 'linux-native-flutter',
    'sequence': <String>[],
  };
  ProductRuntime? runtime;
  HttpServer? server;
  StreamSubscription<HttpRequest>? subscription;
  Directory? temporary;
  final firstExecutionStreamStarted = Completer<void>();
  final releaseFirstExecutionStream = Completer<void>();
  var executionStreamingTurns = 0;

  Future<void> writeReceipt() async {
    final encoded = const JsonEncoder.withIndent('  ').convert(receipt);
    await receiptFile.writeAsString('$encoded\n', flush: true);
  }

  Future<void> streamJson(HttpRequest request, Object payload) async {
    request.response.headers.contentType = ContentType(
      'application',
      'x-ndjson',
      charset: 'utf-8',
    );
    request.response.writeln(jsonEncode(<String, dynamic>{
      'response': jsonEncode(payload),
      'done': false,
    }));
    request.response.writeln(jsonEncode(<String, dynamic>{
      'response': '',
      'done': true,
      'prompt_eval_count': 12,
      'eval_count': 8,
    }));
    await request.response.close();
  }

  try {
    final fixtureServer =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server = fixtureServer;
    subscription = fixtureServer.listen((request) async {
      try {
        if (request.uri.path == '/api/tags') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(<String, dynamic>{
            'models': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'dogfood-model',
                'digest': 'sha256:dogfood',
                'details': <String, dynamic>{
                  'parameter_size': '1B',
                  'quantization_level': 'Q4',
                },
              },
            ],
          }));
          await request.response.close();
          return;
        }
        if (request.uri.path != '/api/generate') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        final raw = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['stream'] != true) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(<String, dynamic>{
            'done': true,
            'load_duration': 1000,
          }));
          await request.response.close();
          return;
        }

        final system = decoded['system']?.toString() ?? '';
        if (system.contains(
          'You classify one user steering message against an active task specification.',
        )) {
          await streamJson(request, <String, dynamic>{
            'kind': 'hardConstraint',
            'value': 'Do not modify README.md.',
            'question': '',
            'reason': 'The user stated a mandatory prohibition.',
          });
          return;
        }

        executionStreamingTurns++;
        if (executionStreamingTurns == 1) {
          if (!firstExecutionStreamStarted.isCompleted) {
            firstExecutionStreamStarted.complete();
          }
          await releaseFirstExecutionStream.future;
        }

        final payload = switch (executionStreamingTurns) {
          1 => <String, dynamic>{
              'action': 'tool',
              'tool': 'list_directory',
              'arguments': <String, dynamic>{
                'path': '.',
                'recursive': false,
                'maxEntries': 200,
              },
              'reason': 'Establish the project evidence baseline.',
            },
          2 => <String, dynamic>{
              'action': 'tool',
              'tool': 'inspect_file',
              'arguments': <String, dynamic>{'path': 'README.md'},
              'reason': 'Inspect the primary project document.',
            },
          3 => <String, dynamic>{
              'action': 'tool',
              'tool': 'index_project',
              'arguments': <String, dynamic>{},
              'reason': 'Capture diverse project-wide evidence.',
            },
          _ => <String, dynamic>{
              'action': 'complete',
              'summary': 'Project evidence baseline established.',
            },
        };
        await streamJson(request, payload);
      } catch (error, stackTrace) {
        stderr.writeln('fixture-server error: $error\n$stackTrace');
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    });

    temporary = await Directory.systemTemp.createTemp(
      'kristin-exact-live-steering-dogfood-',
    );
    final project = Directory(
      '${temporary.path}${Platform.pathSeparator}project',
    );
    await project.create(recursive: true);
    await File(
      '${project.path}${Platform.pathSeparator}README.md',
    ).writeAsString('# Exact dogfood fixture\n');

    runtime = await ProductRuntime.initialize(
      dataRoot: '${temporary.path}${Platform.pathSeparator}app-data',
    );
    await runtime.updateSettings(
      runtime.settings.copyWith(
        ollamaBaseUrl: 'http://127.0.0.1:${fixtureServer.port}',
        ollamaLoadTimeoutSeconds: 60,
        ollamaLoadRetries: 0,
        ollamaKeepAliveMinutes: 1,
      ),
    );
    final admitted = await runtime.addProject(
      name: 'Exact live-steering dogfood',
      rootPath: project.path,
    );
    final model = ModelIdentity(
      providerId: 'ollama',
      name: 'dogfood-model',
      digest: 'sha256:dogfood',
      discoveredAt: DateTime.now().toUtc(),
    );
    final command = await runtime.prepare(
      projectId: admitted.id,
      mode: CommandMode.analyze,
      request: 'Analyze this project structure and produce evidence-backed findings.',
      model: model,
    );
    final source = await runtime.createRun(command.id);
    if (source.state != RunState.awaitingApproval) {
      throw StateError('source_not_awaiting_approval:${source.state.name}');
    }

    final sourceApproval = await runtime.approve(
      runId: source.id,
      scopes: command.contract.requiredPermissions,
      validity: const Duration(hours: 1),
    );
    if (sourceApproval.commandId != command.id ||
        sourceApproval.scopes.length !=
            command.contract.requiredPermissions.length) {
      throw StateError('source_approval_not_bound');
    }
    (receipt['sequence'] as List<String>).add('native_approval');
    receipt['nativeApproval'] = <String, dynamic>{
      'runId': source.id,
      'commandId': command.id,
      'grantId': sourceApproval.id,
      'scopes': sourceApproval.scopes.map((e) => e.name).toList()..sort(),
    };

    final sourceExecution = runtime.execute(source.id);
    await firstExecutionStreamStarted.future.timeout(const Duration(seconds: 30));
    final running = await runtime.getRun(source.id);
    if (running == null || running.state != RunState.running) {
      throw StateError(
        "source_not_running:${running?.state.name ?? 'missing'}",
      );
    }

    await runtime.steerRun(
      source.id,
      'Do not modify README.md under any circumstance.',
    );
    (receipt['sequence'] as List<String>).add('live_steering');
    receipt['liveSteering'] = <String, dynamic>{
      'sourceRunId': source.id,
      'observedWhileState': running.state.name,
      'instruction': 'Do not modify README.md under any circumstance.',
    };

    if (!releaseFirstExecutionStream.isCompleted) {
      releaseFirstExecutionStream.complete();
    }
    final interrupted =
        await sourceExecution.timeout(const Duration(minutes: 2));
    if (interrupted.state != RunState.interrupted) {
      throw StateError(
        'source_not_interrupted:${interrupted.state.name}:${interrupted.failure}',
      );
    }
    final succeededItems = interrupted.items
        .where((item) => item.state == WorkItemState.succeeded)
        .length;
    final queuedItems = interrupted.items
        .where((item) => item.state == WorkItemState.queued)
        .length;
    if (succeededItems < 1 || queuedItems < 1) {
      throw StateError(
        'not_a_verified_between_item_boundary:succeeded=$succeededItems,queued=$queuedItems',
      );
    }
    (receipt['sequence'] as List<String>).add('safe_boundary_interruption');
    receipt['safeBoundaryInterruption'] = <String, dynamic>{
      'sourceRunId': interrupted.id,
      'state': interrupted.state.name,
      'failure': interrupted.failure,
      'succeededItems': succeededItems,
      'queuedItems': queuedItems,
    };

    RunRecord? continuation;
    final continuationDeadline =
        DateTime.now().toUtc().add(const Duration(seconds: 30));
    while (DateTime.now().toUtc().isBefore(continuationDeadline)) {
      continuation = await runtime.steeringContinuationForSourceRun(source.id);
      if (continuation != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final linked = continuation;
    if (linked == null) {
      throw StateError('linked_continuation_missing');
    }
    if (linked.sourceRunId != source.id ||
        linked.state != RunState.awaitingApproval) {
      throw StateError(
        'continuation_link_or_state_invalid:${linked.sourceRunId}:${linked.state.name}',
      );
    }
    (receipt['sequence'] as List<String>).add('linked_continuation');
    receipt['linkedContinuation'] = <String, dynamic>{
      'sourceRunId': source.id,
      'continuationRunId': linked.id,
      'continuationCommandId': linked.command.id,
      'state': linked.state.name,
    };

    final grantsBeforeContinuationApproval =
        await runtime.repositories.grants.all();
    final inherited = grantsBeforeContinuationApproval.where(
      (grant) =>
          grant.commandId == linked.command.id &&
          !grant.isExpired &&
          grant.remainingUses > 0,
    );
    if (inherited.isNotEmpty) {
      throw StateError('continuation_inherited_authority');
    }
    (receipt['sequence'] as List<String>).add('no_inherited_authority');
    receipt['noInheritedAuthority'] = <String, dynamic>{
      'continuationRunId': linked.id,
      'continuationCommandId': linked.command.id,
      'activeGrantCountBeforeExplicitApproval': 0,
    };

    final continuationApproval = await runtime.approve(
      runId: linked.id,
      scopes: linked.command.contract.requiredPermissions,
      validity: const Duration(hours: 1),
    );
    if (continuationApproval.commandId != linked.command.id) {
      throw StateError('continuation_approval_not_bound');
    }
    final grantsAfterContinuationApproval = await runtime.repositories.grants.all();
    final explicit = grantsAfterContinuationApproval.where(
      (grant) =>
          grant.commandId == linked.command.id &&
          !grant.isExpired &&
          grant.remainingUses > 0,
    );
    if (explicit.isEmpty) {
      throw StateError('continuation_explicit_grant_missing');
    }
    (receipt['sequence'] as List<String>).add('explicit_continuation_approval');
    receipt['explicitContinuationApproval'] = <String, dynamic>{
      'continuationRunId': linked.id,
      'commandId': linked.command.id,
      'grantId': continuationApproval.id,
      'scopes': continuationApproval.scopes.map((e) => e.name).toList()..sort(),
    };

    const expected = <String>[
      'native_approval',
      'live_steering',
      'safe_boundary_interruption',
      'linked_continuation',
      'no_inherited_authority',
      'explicit_continuation_approval',
    ];
    final actual = receipt['sequence'] as List<String>;
    if (jsonEncode(actual) != jsonEncode(expected)) {
      throw StateError('dogfood_sequence_order_invalid:$actual');
    }
    receipt['result'] = 'pass';
    await writeReceipt();
    stdout.writeln('EXACT_LIVE_STEERING_DOGFOOD_PASS');
    stdout.writeln(jsonEncode(receipt));
  } catch (error, stackTrace) {
    receipt['result'] = 'fail';
    receipt['error'] = '$error';
    receipt['stackTrace'] = '$stackTrace';
    try {
      await writeReceipt();
    } catch (_) {}
    stderr.writeln('EXACT_LIVE_STEERING_DOGFOOD_FAIL: $error');
    stderr.writeln(stackTrace);
    if (!releaseFirstExecutionStream.isCompleted) {
      releaseFirstExecutionStream.complete();
    }
    exitCode = 1;
  } finally {
    if (runtime != null) {
      try {
        await runtime.close();
      } catch (_) {}
    }
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
    if (temporary != null) {
      try {
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      } catch (_) {}
    }
  }
  exit(exitCode);
}
