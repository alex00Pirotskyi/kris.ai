import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/product_runtime.dart';
import 'package:kristin_local_agent/product/task_kernel/complexity_router.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';

const candidateSha = 'e59583b170b2a5d333a3c6eff5243725daef0d54';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final receiptFile = File('exact-live-steering-dogfood.json');
  final sequence = <String>[];
  final receipt = <String, dynamic>{
    'candidateSha': candidateSha,
    'platform': 'linux-native-flutter',
    'sequence': sequence,
  };
  ProductRuntime? runtime;
  HttpServer? server;
  StreamSubscription<HttpRequest>? subscription;
  Directory? temporary;
  final firstWorkItemModelTurn = Completer<void>();
  final releaseFirstWorkItemModelTurn = Completer<void>();
  var runnerTurns = 0;

  Future<void> writeReceipt() async {
    final text = const JsonEncoder.withIndent('  ').convert(receipt);
    await receiptFile.writeAsString('$text\n', flush: true);
  }

  Future<void> streamPayload(HttpRequest request, Object payload) async {
    request.response.headers.contentType =
        ContentType('application', 'x-ndjson', charset: 'utf-8');
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
    final fixture = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server = fixture;
    subscription = fixture.listen((request) async {
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
        final body = jsonDecode(raw) as Map<String, dynamic>;
        if (body['stream'] != true) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(<String, dynamic>{
            'done': true,
            'load_duration': 1000,
          }));
          await request.response.close();
          return;
        }

        final system = body['system']?.toString() ?? '';
        if (system.contains(
          'You classify one user steering message against an active task specification.',
        )) {
          await streamPayload(request, <String, dynamic>{
            'kind': 'hardConstraint',
            'value': 'Do not modify README.md.',
            'question': '',
            'reason': 'The user stated a mandatory prohibition.',
          });
          return;
        }

        // The initial compact software plan is deterministic. Therefore the
        // first other streaming model call is the first real Runner work-item
        // turn. Hold it open so steering is provably injected while Running.
        runnerTurns++;
        if (runnerTurns == 1) {
          if (!firstWorkItemModelTurn.isCompleted) {
            firstWorkItemModelTurn.complete();
          }
          await releaseFirstWorkItemModelTurn.future;
          await streamPayload(request, <String, dynamic>{
            'action': 'tool',
            'tool': 'list_directory',
            'arguments': <String, dynamic>{
              'path': '.',
              'recursive': false,
              'maxEntries': 200,
            },
            'reason': 'Establish the project evidence baseline.',
          });
          return;
        }

        // A scope-changing compact-plan continuation is deliberately promoted
        // to reviewed graph planning. Returning a recognized invalid model
        // protocol exercises the product's documented conservative software
        // fallback without forging planning state in the harness.
        await streamPayload(request, <String, dynamic>{
          'unexpected': 'force_documented_recoverable_planning_fallback',
        });
      } catch (error, stackTrace) {
        stderr.writeln('fixture-server error: $error\n$stackTrace');
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    });

    temporary = await Directory.systemTemp.createTemp('kristin-dogfood-v2-');
    final project = Directory('${temporary.path}${Platform.pathSeparator}project');
    await project.create(recursive: true);
    await File('${project.path}${Platform.pathSeparator}README.md')
        .writeAsString('# Exact dogfood fixture\n');

    runtime = await ProductRuntime.initialize(
      dataRoot: '${temporary.path}${Platform.pathSeparator}app-data',
    );
    await runtime.updateSettings(runtime.settings.copyWith(
      ollamaBaseUrl: 'http://127.0.0.1:${fixture.port}',
      ollamaLoadTimeoutSeconds: 60,
      ollamaLoadRetries: 0,
      ollamaKeepAliveMinutes: 1,
    ));
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
    const requestText =
        'Analyze this project and improve its documented behavior without violating user constraints.';
    final specification = TaskSpecification(
      id: 'dogfood_task_specification',
      originalRequest: requestText,
      objective: 'Improve the project while preserving user constraints.',
      successCriteria: const <SpecificationClaim>[
        SpecificationClaim.stated('The requested behavior is evidence-backed.'),
      ],
      source: TaskSpecificationSource.deterministic,
    );
    const routing = RoutingDecision(
      route: PlanningRoute.compact,
      family: TaskFamily.software,
      rationale: 'Exact native dogfood uses the production compact software path.',
    );
    final planned = await runtime.prepareThroughKernel(
      specification: specification,
      routing: routing,
      project: admitted,
      mode: CommandMode.build,
      model: model,
    );
    final command = planned.command;
    final durableContext =
        await runtime.repositories.commandPlanningContexts.get(command.id);
    if (durableContext == null || durableContext.canonicalPlan.tasks.length < 2) {
      throw StateError('production_kernel_context_missing_or_too_small');
    }

    final source = await runtime.createRun(command.id);
    if (source.state != RunState.awaitingApproval) {
      throw StateError('source_not_awaiting_approval:${source.state.name}');
    }
    final sourceApproval = await runtime.approve(
      runId: source.id,
      scopes: command.contract.requiredPermissions,
      validity: const Duration(hours: 1),
    );
    sequence.add('native_approval');
    receipt['nativeApproval'] = <String, dynamic>{
      'runId': source.id,
      'commandId': command.id,
      'grantId': sourceApproval.id,
      'planningContextDurable': true,
      'canonicalTaskCount': durableContext.canonicalPlan.tasks.length,
    };

    final sourceExecution = runtime.execute(source.id);
    await firstWorkItemModelTurn.future.timeout(const Duration(seconds: 30));
    final running = await runtime.getRun(source.id);
    if (running == null || running.state != RunState.running) {
      throw StateError("source_not_running:${running?.state.name ?? 'missing'}");
    }
    await runtime.steerRun(
      source.id,
      'Do not modify README.md under any circumstance.',
    );
    sequence.add('live_steering');
    receipt['liveSteering'] = <String, dynamic>{
      'sourceRunId': source.id,
      'observedWhileState': running.state.name,
    };

    releaseFirstWorkItemModelTurn.complete();
    final interrupted =
        await sourceExecution.timeout(const Duration(minutes: 3));
    if (interrupted.state != RunState.interrupted) {
      throw StateError(
        'source_not_interrupted:${interrupted.state.name}:${interrupted.failure}',
      );
    }
    final succeeded = interrupted.items
        .where((item) => item.state == WorkItemState.succeeded)
        .length;
    final queued = interrupted.items
        .where((item) => item.state == WorkItemState.queued)
        .length;
    if (succeeded < 1 || queued < 1) {
      throw StateError('unsafe_boundary_shape:succeeded=$succeeded,queued=$queued');
    }
    sequence.add('safe_boundary_interruption');
    receipt['safeBoundaryInterruption'] = <String, dynamic>{
      'state': interrupted.state.name,
      'succeededItems': succeeded,
      'queuedItems': queued,
      'failure': interrupted.failure,
    };

    RunRecord? continuation;
    final deadline = DateTime.now().toUtc().add(const Duration(seconds: 30));
    while (DateTime.now().toUtc().isBefore(deadline)) {
      continuation = await runtime.steeringContinuationForSourceRun(source.id);
      if (continuation != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final linked = continuation;
    if (linked == null ||
        linked.sourceRunId != source.id ||
        linked.state != RunState.awaitingApproval) {
      throw StateError('linked_continuation_missing_or_invalid');
    }
    sequence.add('linked_continuation');
    receipt['linkedContinuation'] = <String, dynamic>{
      'sourceRunId': source.id,
      'continuationRunId': linked.id,
      'continuationCommandId': linked.command.id,
      'state': linked.state.name,
    };

    final before = await runtime.repositories.grants.all();
    final inherited = before.where((grant) =>
        grant.commandId == linked.command.id &&
        !grant.isExpired &&
        grant.remainingUses > 0);
    if (inherited.isNotEmpty) {
      throw StateError('continuation_inherited_authority');
    }
    sequence.add('no_inherited_authority');
    receipt['noInheritedAuthority'] = <String, dynamic>{
      'activeGrantCountBeforeExplicitApproval': 0,
    };

    final continuationApproval = await runtime.approve(
      runId: linked.id,
      scopes: linked.command.contract.requiredPermissions,
      validity: const Duration(hours: 1),
    );
    final after = await runtime.repositories.grants.all();
    final explicit = after.where((grant) =>
        grant.commandId == linked.command.id &&
        !grant.isExpired &&
        grant.remainingUses > 0);
    if (continuationApproval.commandId != linked.command.id || explicit.isEmpty) {
      throw StateError('explicit_continuation_approval_not_bound');
    }
    sequence.add('explicit_continuation_approval');
    receipt['explicitContinuationApproval'] = <String, dynamic>{
      'grantId': continuationApproval.id,
      'commandId': linked.command.id,
    };

    const expected = <String>[
      'native_approval',
      'live_steering',
      'safe_boundary_interruption',
      'linked_continuation',
      'no_inherited_authority',
      'explicit_continuation_approval',
    ];
    if (jsonEncode(sequence) != jsonEncode(expected)) {
      throw StateError('dogfood_sequence_order_invalid:$sequence');
    }
    receipt['result'] = 'pass';
    await writeReceipt();
    stdout.writeln('EXACT_LIVE_STEERING_DOGFOOD_PASS');
  } catch (error, stackTrace) {
    receipt['result'] = 'fail';
    receipt['error'] = '$error';
    receipt['stackTrace'] = '$stackTrace';
    try {
      await writeReceipt();
    } catch (_) {}
    stderr.writeln('EXACT_LIVE_STEERING_DOGFOOD_FAIL: $error');
    stderr.writeln(stackTrace);
    if (!releaseFirstWorkItemModelTurn.isCompleted) {
      releaseFirstWorkItemModelTurn.complete();
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
        if (await temporary.exists()) await temporary.delete(recursive: true);
      } catch (_) {}
    }
  }
  exit(exitCode);
}
