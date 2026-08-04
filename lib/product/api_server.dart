import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kristin_local_agent/product/generated/prompt_studio_contracts.g.dart';
import 'package:kristin_local_agent/product/prompt_studio_v2.dart';

import 'crypto_utils.dart';
import 'domain.dart';
import 'product_runtime.dart';
import 'storage_security.dart';

class GovernedApiServer {
  GovernedApiServer(this.runtime)
      : _rateLimiter = RateLimiter(capacity: 120, refillPerMinute: 120);

  final ProductRuntime runtime;
  final RateLimiter _rateLimiter;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  Future<void> start() async {
    if (_server != null) {
      return;
    }
    final settings = runtime.settings;
    if (!settings.apiEnabled) {
      throw ProductException(
          'api_disabled', 'Enable the authenticated API in Settings first.');
    }
    final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4, settings.apiPort,
        shared: false);
    server.autoCompress = false;
    _server = server;
    _subscription = server.listen(
      (request) => unawaited(_handle(request)),
      onError: (Object error, StackTrace stackTrace) => unawaited(
          runtime.audit.append('api.server_error', 'api', <String, dynamic>{
        'error': runtime.redactor.redact('$error'),
        'stackHash': Sha256.text('$stackTrace'),
      })),
      cancelOnError: false,
    );
    await runtime.audit.append('api.started', 'api', <String, dynamic>{
      'address': '127.0.0.1',
      'port': server.port,
      'allowedOrigins': settings.allowedOrigins.toList(),
    });
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await _subscription?.cancel();
    _subscription = null;
    await server?.close(force: true);
    await runtime.audit.append('api.stopped', 'api', <String, dynamic>{});
  }

  Future<void> _handle(HttpRequest request) async {
    final correlationId = _correlationId(request.headers.value('x-request-id'));
    final response = request.response;
    response.headers
      ..set('x-request-id', correlationId)
      ..set('x-content-type-options', 'nosniff')
      ..set('x-frame-options', 'DENY')
      ..set('referrer-policy', 'no-referrer')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    try {
      final origin = request.headers.value('origin');
      if (origin != null) {
        if (!_originAllowed(origin)) {
          throw _HttpFailure(HttpStatus.forbidden, 'origin_rejected',
              'Browser origin is not allowed.');
        }
        response.headers
          ..set(HttpHeaders.accessControlAllowOriginHeader, origin)
          ..set(HttpHeaders.varyHeader, 'Origin');
      }
      if (request.method == 'OPTIONS') {
        if (origin == null) {
          throw _HttpFailure(HttpStatus.badRequest, 'origin_required',
              'CORS preflight requires an Origin header.');
        }
        response.statusCode = HttpStatus.noContent;
        response.headers
          ..set(HttpHeaders.accessControlAllowMethodsHeader,
              'GET, POST, PUT, DELETE, OPTIONS')
          ..set(HttpHeaders.accessControlAllowHeadersHeader,
              'Authorization, Content-Type, X-Request-ID')
          ..set(HttpHeaders.accessControlMaxAgeHeader, '600');
        await response.close();
        return;
      }
      final remote = request.connectionInfo?.remoteAddress.address ?? 'unknown';
      if (!_rateLimiter.allow(remote, cost: request.method == 'GET' ? 1 : 2)) {
        throw _HttpFailure(HttpStatus.tooManyRequests, 'rate_limited',
            'Too many API requests.');
      }
      await _route(request, correlationId);
    } on _HttpFailure catch (failure) {
      await _writeError(response, failure.status, failure.code, failure.message,
          correlationId, const <String, dynamic>{});
    } on ProductException catch (failure) {
      await _writeError(response, _statusForProductError(failure.code),
          failure.code, failure.message, correlationId, failure.details);
    } on FormatException {
      await _writeError(response, HttpStatus.badRequest, 'json_invalid',
          'Request JSON is invalid.', correlationId, const <String, dynamic>{});
    } catch (error, stackTrace) {
      await runtime.audit
          .append('api.request_failed', correlationId, <String, dynamic>{
        'method': request.method,
        'path': request.uri.path,
        'error': runtime.redactor.redact('$error'),
        'stackHash': Sha256.text('$stackTrace'),
      });
      await _writeError(
          response,
          HttpStatus.internalServerError,
          'internal_error',
          'The request could not be completed.',
          correlationId, const <String, dynamic>{});
    }
  }

  Future<void> _route(HttpRequest request, String correlationId) async {
    final segments = request.uri.pathSegments.map(Uri.decodeComponent).toList();
    if (request.method == 'GET' && request.uri.path == '/v1/health') {
      return _json(request.response, HttpStatus.ok, <String, dynamic>{
        'status': 'ok',
        'product': 'Kristin Local Agent',
        'version': kristinVersion,
        'api': 'v1',
        'loopbackOnly': true,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
    }
    if (request.method == 'GET' && request.uri.path == '/v1/openapi.json') {
      await _authenticate(request, 'schema:read');
      return _json(request.response, HttpStatus.ok, _openApi());
    }

    if (segments.length == 2 &&
        segments[0] == 'v1' &&
        segments[1] == 'projects') {
      if (request.method == 'GET') {
        await _authenticate(request, 'projects:read');
        return _json(request.response, HttpStatus.ok, <String, dynamic>{
          'projects': (await runtime.listProjects())
              .map((project) => project.toJson())
              .toList(),
        });
      }
      if (request.method == 'POST') {
        await _authenticate(request, 'projects:write');
        final body = await _body(request);
        final project = await runtime.addProject(
          name: body['name']?.toString() ?? '',
          rootPath: _required(body, 'rootPath'),
        );
        return _json(request.response, HttpStatus.created,
            <String, dynamic>{'project': project.toJson()});
      }
    }

    if (request.method == 'GET' && request.uri.path == '/v1/models') {
      await _authenticate(request, 'models:read');
      final models = await runtime.discoverModels();
      return _json(request.response, HttpStatus.ok, <String, dynamic>{
        'models': models.map((model) => model.toJson()).toList()
      });
    }

    if (request.method == 'GET' && request.uri.path == '/v1/prompts') {
      await _authenticate(request, 'prompts:read');
      final prompts = await runtime.listPrompts();
      return _json(
        request.response,
        HttpStatus.ok,
        <String, dynamic>{
          'prompts': prompts.map((prompt) => prompt.toJson()).toList(),
        },
      );
    }

    if (request.method == 'POST' &&
        request.uri.path == '/v1/prompts/generate') {
      await _authenticate(request, 'prompts:generate');
      final body = await _body(request);
      final action = _promptAction(body['action']);
      final current = body['currentDraft'] is Map
          ? PromptStudioDraft.fromJson(mapValue(body['currentDraft']))
          : null;
      final draft = await runtime.generatePromptDraft(
        goal: _required(body, 'goal'),
        model: ModelIdentity.fromJson(mapValue(body['model'])),
        action: action,
        current: current,
      );
      return _json(
        request.response,
        HttpStatus.created,
        <String, dynamic>{'draft': draft.toJson()},
      );
    }

    if (request.method == 'POST' &&
        request.uri.path == '/v1/prompts/versions') {
      await _authenticate(request, 'prompts:write');
      final body = await _body(request);
      final saved = await runtime.saveGeneratedPrompt(
        id: body['promptId']?.toString().trim().isEmpty == false
            ? body['promptId']!.toString().trim()
            : null,
        goal: _required(body, 'goal'),
        draft: PromptStudioDraft.fromJson(mapValue(body['draft'])),
        model: ModelIdentity.fromJson(mapValue(body['model'])),
        action: _promptAction(body['action']),
        createdBy: body['createdBy']?.toString().trim().isNotEmpty == true
            ? body['createdBy']!.toString().trim()
            : 'api-reviewed-model',
      );
      return _json(
        request.response,
        HttpStatus.created,
        <String, dynamic>{
          'prompt': saved.prompt.toJson(),
          'version': saved.version.toJson(),
        },
      );
    }

    if (segments.length == 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'prompts' &&
        segments[3] == 'versions' &&
        request.method == 'GET') {
      await _authenticate(request, 'prompts:read');
      final versions = await runtime.listPromptVersions(segments[2]);
      return _json(
        request.response,
        HttpStatus.ok,
        <String, dynamic>{
          'versions': versions.map((version) => version.toJson()).toList(),
        },
      );
    }

    if (request.method == 'GET' &&
        request.uri.path == '/v1/prompt-studio/v2/contracts') {
      await _authenticate(request, 'schema:read');
      return _json(
        request.response,
        HttpStatus.ok,
        <String, dynamic>{
          'contractDigest': promptStudioContractDigest,
          'compilerVersion': promptStudioCompilerVersion,
          'schemas': <String, dynamic>{
            'productSpecification': PromptStudioV2Contracts.specificationSchema,
            'taskPlan': PromptStudioV2Contracts.taskPlanSchema,
            'evaluationDataset': PromptStudioV2Contracts.evaluationSchema,
            'compilationReport':
                PromptStudioV2Contracts.compilationReportSchema,
            'capabilityCatalog': PromptStudioV2Contracts.capabilityCatalog,
          },
        },
      );
    }

    if (request.method == 'POST' &&
        request.uri.path == '/v1/prompt-studio/v2/compile') {
      final body = await _body(request);
      final projectId = body['projectId']?.toString().trim();
      await _authenticate(
        request,
        'plans:generate',
        projectId: projectId?.isNotEmpty == true ? projectId : null,
      );
      final policyValue = body['policy'];
      final report = await runtime.promptStudioV2.compileAndSimulate(
        specification: mapValue(body['specification']),
        plan: mapValue(body['plan']),
        policy: policyValue is Map
            ? PlanCompilerPolicyV2.fromJson(mapValue(policyValue))
            : null,
      );
      return _json(
        request.response,
        HttpStatus.ok,
        <String, dynamic>{'report': report},
      );
    }

    if (request.method == 'POST' &&
        request.uri.path == '/v1/prompt-studio/v2/evaluate') {
      await _authenticate(request, 'prompts:read');
      final body = await _body(request);
      final report = await runtime.promptStudioV2.comparePromptVersions(
        baseline: mapValue(body['baseline']),
        candidate: mapValue(body['candidate']),
        dataset: mapValue(body['dataset']),
      );
      return _json(
        request.response,
        HttpStatus.ok,
        <String, dynamic>{'report': report},
      );
    }

    if (request.method == 'POST' &&
        request.uri.path == '/v1/task-plans/generate') {
      final body = await _body(request);
      final projectId = _required(body, 'projectId');
      await _authenticate(request, 'plans:generate', projectId: projectId);
      final versionId = _required(body, 'promptVersionId');
      final version = await runtime.repositories.promptVersions.get(versionId);
      if (version == null) {
        throw _HttpFailure(
          HttpStatus.notFound,
          'prompt_version_missing',
          'Unknown prompt version.',
        );
      }
      final plan = await runtime.generateTaskPlan(
        promptVersion: version,
        projectId: projectId,
        model: ModelIdentity.fromJson(mapValue(body['model'])),
        depth: _planningDepth(body['depth']),
        maxLeafTasks:
            (int.tryParse(body['maxLeafTasks']?.toString() ?? '') ?? 25)
                .clamp(1, 100)
                .toInt(),
      );
      return _json(
        request.response,
        HttpStatus.created,
        <String, dynamic>{'plan': plan.toJson()},
      );
    }

    if (request.method == 'GET' && request.uri.path == '/v1/task-plans') {
      final projectId = request.uri.queryParameters['projectId'];
      await _authenticate(request, 'plans:read', projectId: projectId);
      final plans = await runtime.listTaskPlans(
        projectId: projectId,
        promptId: request.uri.queryParameters['promptId'],
      );
      return _json(
        request.response,
        HttpStatus.ok,
        <String, dynamic>{
          'plans': plans.map((plan) => plan.toJson()).toList(),
        },
      );
    }

    if (segments.length == 3 &&
        segments[0] == 'v1' &&
        segments[1] == 'task-plans') {
      final plan = await runtime.repositories.taskPlans.get(segments[2]);
      if (plan == null) {
        throw _HttpFailure(
          HttpStatus.notFound,
          'task_plan_missing',
          'Unknown task plan.',
        );
      }
      if (request.method == 'GET') {
        await _authenticate(request, 'plans:read', projectId: plan.projectId);
        return _json(
          request.response,
          HttpStatus.ok,
          <String, dynamic>{'plan': plan.toJson()},
        );
      }
      if (request.method == 'PUT') {
        await _authenticate(request, 'plans:write', projectId: plan.projectId);
        final body = await _body(request);
        final tasksValue = body['tasks'];
        if (tasksValue is! List) {
          throw _HttpFailure(
            HttpStatus.badRequest,
            'tasks_required',
            'Field "tasks" must be a JSON array.',
          );
        }
        final updated = await runtime.updateTaskPlan(
          plan,
          title: body['title']?.toString(),
          rationale: body['rationale']?.toString(),
          tasks: tasksValue
              .whereType<Map>()
              .map((item) => PlanTaskRecord.fromJson(mapValue(item)))
              .toList(),
        );
        return _json(
          request.response,
          HttpStatus.created,
          <String, dynamic>{'plan': updated.toJson()},
        );
      }
    }

    if (segments.length == 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'task-plans' &&
        segments[3] == 'compile' &&
        request.method == 'POST') {
      final plan = await runtime.repositories.taskPlans.get(segments[2]);
      if (plan == null) {
        throw _HttpFailure(
          HttpStatus.notFound,
          'task_plan_missing',
          'Unknown task plan.',
        );
      }
      await _authenticate(request, 'commands:prepare',
          projectId: plan.projectId);
      final body = await _body(request, allowEmpty: true);
      final versionId =
          body['promptVersionId']?.toString().trim().isNotEmpty == true
              ? body['promptVersionId']!.toString().trim()
              : plan.promptVersionId;
      final version = await runtime.repositories.promptVersions.get(versionId);
      if (version == null) {
        throw _HttpFailure(
          HttpStatus.notFound,
          'prompt_version_missing',
          'Unknown prompt version.',
        );
      }
      final selected = stringList(body['selectedTaskIds']).toSet();
      final command = await runtime.prepareTaskPlan(
        plan: plan,
        promptVersion: version,
        projectId: plan.projectId,
        model: body['model'] is Map
            ? ModelIdentity.fromJson(mapValue(body['model']))
            : plan.model,
        selectedTaskIds: selected.isEmpty ? null : selected,
      );
      return _json(
        request.response,
        HttpStatus.created,
        <String, dynamic>{'command': command.toJson()},
      );
    }

    if (request.method == 'POST' &&
        request.uri.path == '/v1/commands/prepare') {
      final body = await _body(request);
      final projectId = _required(body, 'projectId');
      await _authenticate(request, 'commands:prepare', projectId: projectId);
      final modeName = _required(body, 'mode');
      final mode = CommandMode.values
          .where((candidate) => candidate.name == modeName)
          .firstOrNull;
      if (mode == null) {
        throw _HttpFailure(
            HttpStatus.badRequest, 'mode_invalid', 'Unknown command mode.');
      }
      final command = await runtime.prepare(
        projectId: projectId,
        mode: mode,
        request: _required(body, 'request'),
        model: ModelIdentity.fromJson(mapValue(body['model'])),
      );
      return _json(request.response, HttpStatus.created,
          <String, dynamic>{'command': command.toJson()});
    }

    if (segments.length == 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'commands' &&
        segments[3] == 'runs' &&
        request.method == 'POST') {
      final command = await runtime.repositories.commands.get(segments[2]);
      if (command == null) {
        throw _HttpFailure(
            HttpStatus.notFound, 'command_missing', 'Unknown command.');
      }
      await _authenticate(request, 'runs:create',
          projectId: command.contract.projectId);
      final body = await _body(request, allowEmpty: true);
      final budget = body.isEmpty
          ? null
          : AutonomyBudget.fromJson(mapValue(body['budget']));
      final run = await runtime.createRun(command.id, budget: budget);
      return _json(request.response, HttpStatus.created,
          <String, dynamic>{'run': run.toJson()});
    }

    if (segments.length >= 3 && segments[0] == 'v1' && segments[1] == 'runs') {
      if (segments.length == 3 && request.method == 'GET') {
        final run = await runtime.getRun(segments[2]);
        if (run == null) {
          throw _HttpFailure(
              HttpStatus.notFound, 'run_missing', 'Unknown run.');
        }
        await _authenticate(request, 'runs:read',
            projectId: run.command.contract.projectId);
        return _json(request.response, HttpStatus.ok,
            <String, dynamic>{'run': run.toJson()});
      }
      if (segments.length == 4 &&
          segments[3] == 'evidence' &&
          request.method == 'GET') {
        final run = await runtime.getRun(segments[2]);
        if (run == null) {
          throw _HttpFailure(
              HttpStatus.notFound, 'run_missing', 'Unknown run.');
        }
        await _authenticate(request, 'runs:read',
            projectId: run.command.contract.projectId);
        final evidence = await runtime.evidenceForRun(run.id);
        return _json(request.response, HttpStatus.ok, <String, dynamic>{
          'evidence': evidence.map((item) => item.toJson()).toList()
        });
      }
      if (segments.length == 4 && request.method == 'POST') {
        final run = await runtime.getRun(segments[2]);
        if (run == null) {
          throw _HttpFailure(
              HttpStatus.notFound, 'run_missing', 'Unknown run.');
        }
        final action = segments[3];
        final scope = action == 'approve' || action == 'execute'
            ? 'runs:execute'
            : 'runs:control';
        await _authenticate(request, scope,
            projectId: run.command.contract.projectId);
        if (action == 'approve') {
          final body = await _body(request);
          final scopes = stringList(body['scopes'])
              .map((name) => PermissionScope.values
                  .where((candidate) => candidate.name == name)
                  .firstOrNull)
              .whereType<PermissionScope>()
              .toSet();
          final grant = await runtime.approve(
            runId: run.id,
            scopes: scopes,
            validity: Duration(
                minutes:
                    (int.tryParse(body['validityMinutes']?.toString() ?? '') ??
                            120)
                        .clamp(1, 1440)
                        .toInt()),
          );
          return _json(request.response, HttpStatus.ok,
              <String, dynamic>{'grant': grant.toJson()});
        }
        if (action == 'execute') {
          unawaited(runtime.execute(run.id));
          return _json(request.response, HttpStatus.accepted,
              <String, dynamic>{'runId': run.id, 'state': 'queued'});
        }
        if (action == 'retry') {
          final retried = await runtime.retryRun(run.id);
          return _json(
            request.response,
            HttpStatus.created,
            <String, dynamic>{'run': retried.toJson()},
          );
        }
        if (action == 'pause') {
          await runtime.pause(run.id);
          return _json(request.response, HttpStatus.ok,
              <String, dynamic>{'runId': run.id, 'state': 'paused'});
        }
        if (action == 'resume') {
          await runtime.resume(run.id);
          return _json(request.response, HttpStatus.accepted,
              <String, dynamic>{'runId': run.id, 'state': 'running'});
        }
        if (action == 'cancel') {
          await runtime.cancel(run.id);
          return _json(request.response, HttpStatus.accepted,
              <String, dynamic>{'runId': run.id, 'state': 'cancelling'});
        }
      }
    }

    if (request.method == 'GET' && request.uri.path == '/v1/runs') {
      final projectId = request.uri.queryParameters['projectId'];
      await _authenticate(request, 'runs:read', projectId: projectId);
      final runs = await runtime.listRuns(
          projectId: projectId,
          limit:
              (int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 100)
                  .clamp(1, 500)
                  .toInt());
      return _json(request.response, HttpStatus.ok,
          <String, dynamic>{'runs': runs.map((run) => run.toJson()).toList()});
    }

    if (segments.length == 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'projects') {
      final projectId = segments[2];
      final action = segments[3];
      if (action == 'manager' && request.method == 'GET') {
        await _authenticate(request, 'projects:read', projectId: projectId);
        final project = await runtime.getProject(projectId);
        if (project == null) {
          throw _HttpFailure(
            HttpStatus.notFound,
            'project_missing',
            'Unknown project.',
          );
        }
        final diagnostics = await runtime.inspectProject(projectId);
        final process = await runtime.projectProcessStatus(projectId);
        final runs = await runtime.listRuns(projectId: projectId, limit: 20);
        return _json(
          request.response,
          HttpStatus.ok,
          <String, dynamic>{
            'project': project.toJson(),
            'diagnostics': diagnostics.toJson(),
            'process': process?.toJson(),
            'recentRuns': runs.map((run) => run.toJson()).toList(),
          },
        );
      }
      if (request.method == 'POST' &&
          const <String>{'analyze', 'test', 'build', 'run', 'stop'}
              .contains(action)) {
        await _authenticate(
          request,
          'projects:execute',
          projectId: projectId,
        );
        if (action == 'analyze') {
          final report = await runtime.analyzeProject(projectId);
          return _json(
            request.response,
            HttpStatus.ok,
            <String, dynamic>{'report': report.toJson()},
          );
        }
        if (action == 'test') {
          final report = await runtime.testProject(projectId);
          return _json(
            request.response,
            HttpStatus.ok,
            <String, dynamic>{'report': report.toJson()},
          );
        }
        if (action == 'build') {
          final report = await runtime.buildProject(projectId);
          return _json(
            request.response,
            HttpStatus.ok,
            <String, dynamic>{'report': report.toJson()},
          );
        }
        if (action == 'run') {
          final process = await runtime.startProject(projectId);
          return _json(
            request.response,
            HttpStatus.accepted,
            <String, dynamic>{'process': process.toJson()},
          );
        }
        final process = await runtime.stopProject(projectId);
        return _json(
          request.response,
          HttpStatus.ok,
          <String, dynamic>{'process': process?.toJson()},
        );
      }
    }

    if (segments.length == 3 &&
        segments[0] == 'v1' &&
        segments[1] == 'projects' &&
        request.method == 'DELETE') {
      await _authenticate(request, 'projects:write', projectId: segments[2]);
      await runtime.removeProject(segments[2]);
      request.response.statusCode = HttpStatus.noContent;
      return request.response.close();
    }

    if (segments.length == 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'projects' &&
        segments[3] == 'knowledge') {
      final projectId = segments[2];
      if (request.method == 'GET') {
        await _authenticate(request, 'knowledge:read', projectId: projectId);
        final entries = await runtime.listKnowledge(projectId);
        return _json(request.response, HttpStatus.ok, <String, dynamic>{
          'knowledge': entries.map((entry) => entry.toJson()).toList()
        });
      }
      if (request.method == 'POST') {
        await _authenticate(request, 'knowledge:write', projectId: projectId);
        final body = await _body(request);
        final entry = await runtime.addKnowledge(
          projectId: projectId,
          title: _required(body, 'title'),
          content: _required(body, 'content'),
          tags: stringList(body['tags']).toSet(),
        );
        return _json(request.response, HttpStatus.created,
            <String, dynamic>{'knowledge': entry.toJson()});
      }
    }

    if (segments.length == 5 &&
        segments[0] == 'v1' &&
        segments[1] == 'projects' &&
        segments[3] == 'knowledge') {
      final projectId = segments[2];
      final action = segments[4];
      if (action == 'search' && request.method == 'GET') {
        await _authenticate(request, 'knowledge:read', projectId: projectId);
        final query = request.uri.queryParameters['q']?.trim() ?? '';
        if (query.isEmpty) {
          throw _HttpFailure(
            HttpStatus.badRequest,
            'query_required',
            'Query parameter "q" is required.',
          );
        }
        final retrieval = await runtime.searchKnowledge(
          projectId,
          query,
          limit:
              (int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 12)
                  .clamp(1, 30)
                  .toInt(),
          includeEpisodes:
              request.uri.queryParameters['includeEpisodes'] != 'false',
          includeUnsuccessfulEpisodes:
              request.uri.queryParameters['includeUnsuccessfulEpisodes'] ==
                  'true',
        );
        return _json(
          request.response,
          HttpStatus.ok,
          <String, dynamic>{'retrieval': retrieval.toJson()},
        );
      }
      if (action == 'stats' && request.method == 'GET') {
        await _authenticate(request, 'knowledge:read', projectId: projectId);
        final stats = await runtime.knowledgeStats(projectId);
        return _json(
          request.response,
          HttpStatus.ok,
          <String, dynamic>{'stats': stats.toJson()},
        );
      }
      if (action == 'reindex' && request.method == 'POST') {
        await _authenticate(request, 'knowledge:write', projectId: projectId);
        final chunks = await runtime.rebuildKnowledgeIndex(projectId);
        return _json(
          request.response,
          HttpStatus.ok,
          <String, dynamic>{'projectId': projectId, 'indexedChunks': chunks},
        );
      }
      if (action == 'export' && request.method == 'POST') {
        await _authenticate(request, 'knowledge:write', projectId: projectId);
        final file = await runtime.exportKnowledge(projectId);
        return _json(
          request.response,
          HttpStatus.created,
          <String, dynamic>{
            'projectId': projectId,
            'fileName': file.uri.pathSegments.last,
            'sha256': Sha256.hex(await file.readAsBytes()),
            'bytes': await file.length(),
          },
        );
      }
    }

    if (segments.length == 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'projects' &&
        segments[3] == 'research-archive' &&
        request.method == 'GET') {
      final projectId = segments[2];
      await _authenticate(request, 'knowledge:read', projectId: projectId);
      final records = await runtime.listResearchArchive(projectId);
      return _json(
        request.response,
        HttpStatus.ok,
        <String, dynamic>{
          'researchArchive': records.map((record) => record.toJson()).toList(),
        },
      );
    }

    if (segments.length == 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'projects' &&
        segments[3] == 'memory' &&
        request.method == 'GET') {
      final projectId = segments[2];
      await _authenticate(request, 'knowledge:read', projectId: projectId);
      final episodes = await runtime.listMemoryEpisodes(projectId);
      return _json(
        request.response,
        HttpStatus.ok,
        <String, dynamic>{
          'episodes': episodes.map((episode) => episode.toJson()).toList(),
        },
      );
    }

    if (request.method == 'POST' &&
        request.uri.path == '/v1/secret-references') {
      await _authenticate(request, 'secrets:manage');
      final body = await _body(request);
      final reference = await runtime.registerSecretReference(
        label: _required(body, 'label'),
        environmentKey: _required(body, 'environmentKey'),
        description: body['description']?.toString() ?? '',
      );
      return _json(request.response, HttpStatus.created,
          <String, dynamic>{'secretReference': reference.toJson()});
    }

    if (request.method == 'GET' &&
        request.uri.path == '/v1/secret-references') {
      await _authenticate(request, 'secrets:manage');
      return _json(request.response, HttpStatus.ok, <String, dynamic>{
        'secretReferences': (await runtime.listSecretReferences())
            .map((reference) => reference.toJson())
            .toList(),
      });
    }

    if (request.method == 'POST' && request.uri.path == '/v1/tokens') {
      await _authenticate(request, 'tokens:manage');
      final body = await _body(request);
      final issued = await runtime.issueApiToken(
        label: _required(body, 'label'),
        scopes: stringList(body['scopes']).toSet(),
        projectId: body['projectId']?.toString(),
        validity: Duration(
            minutes: (int.tryParse(body['validityMinutes']?.toString() ?? '') ??
                    43200)
                .clamp(1, 525600)
                .toInt()),
      );
      return _json(request.response, HttpStatus.created, <String, dynamic>{
        'token': issued.plaintext,
        'record': issued.record.toJson(),
        'warning':
            'This token is shown once. Store it in a secure password manager.',
      });
    }

    if (segments.length == 3 &&
        segments[0] == 'v1' &&
        segments[1] == 'tokens' &&
        request.method == 'DELETE') {
      await _authenticate(request, 'tokens:manage');
      await runtime.revokeApiToken(segments[2]);
      request.response.statusCode = HttpStatus.noContent;
      return request.response.close();
    }

    if (request.method == 'GET' && request.uri.path == '/v1/audit/verify') {
      await _authenticate(request, 'audit:read');
      return _json(
          request.response, HttpStatus.ok, await runtime.verifyAudit());
    }

    if (request.method == 'POST' && request.uri.path == '/v1/support-bundles') {
      await _authenticate(request, 'support:create');
      final body = await _body(request, allowEmpty: true);
      final file = await runtime.createSupportBundle(
        projectId: body['projectId']?.toString(),
        runId: body['runId']?.toString(),
        includeAllLogs: body['includeAllLogs'] == true,
      );
      return _json(request.response, HttpStatus.created, <String, dynamic>{
        'fileName': file.uri.pathSegments.last,
        'sha256': Sha256.hex(await file.readAsBytes()),
        'bytes': await file.length(),
      });
    }

    if (request.method == 'GET' && request.uri.path == '/v1/events') {
      await _authenticate(request, 'events:read');
      return _events(request);
    }

    throw _HttpFailure(
        HttpStatus.notFound, 'route_not_found', 'API route not found.');
  }

  Future<ApiTokenRecord> _authenticate(HttpRequest request, String scope,
      {String? projectId}) async {
    final authorization =
        request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final match = RegExp(r'^Bearer\s+([^\s]+)$', caseSensitive: false)
        .firstMatch(authorization);
    if (match == null) {
      throw _HttpFailure(HttpStatus.unauthorized, 'authentication_required',
          'A bearer token is required.');
    }
    final token = await runtime.tokens.authenticate(match.group(1)!,
        requiredScope: scope, projectId: projectId);
    if (token == null) {
      throw _HttpFailure(HttpStatus.forbidden, 'token_invalid',
          'Token is invalid, expired, revoked, out of scope, or bound to another project.');
    }
    return token;
  }

  Future<Map<String, dynamic>> _body(HttpRequest request,
      {bool allowEmpty = false}) async {
    final contentType = request.headers.contentType;
    if (contentType != null && contentType.mimeType != 'application/json') {
      throw _HttpFailure(HttpStatus.unsupportedMediaType,
          'content_type_invalid', 'Content-Type must be application/json.');
    }
    const maxBytes = 1024 * 1024;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      if (builder.length + chunk.length > maxBytes) {
        throw _HttpFailure(HttpStatus.requestEntityTooLarge, 'body_too_large',
            'Request body exceeds 1 MiB.');
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty && allowEmpty) {
      return <String, dynamic>{};
    }
    if (bytes.isEmpty) {
      throw _HttpFailure(HttpStatus.badRequest, 'body_required',
          'A JSON request body is required.');
    }
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map) {
      throw _HttpFailure(HttpStatus.badRequest, 'body_object_required',
          'Request body must be a JSON object.');
    }
    return mapValue(decoded);
  }

  Future<void> _events(HttpRequest request) async {
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers
      ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache, no-store')
      ..set(HttpHeaders.connectionHeader, 'keep-alive');
    final after = int.tryParse(request.uri.queryParameters['after'] ?? '') ?? 0;
    for (final event in await runtime.events.after(after, limit: 1000)) {
      response.write(_sse(event));
    }
    await response.flush();
    late StreamSubscription<EventEnvelope> subscription;
    Timer? heartbeat;
    final done = Completer<void>();
    subscription = runtime.eventStream.listen((event) async {
      try {
        response.write(_sse(event));
        await response.flush();
      } catch (_) {
        if (!done.isCompleted) {
          done.complete();
        }
      }
    });
    heartbeat = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        response.write(
            ': heartbeat ${DateTime.now().toUtc().toIso8601String()}\n\n');
        await response.flush();
      } catch (_) {
        if (!done.isCompleted) {
          done.complete();
        }
      }
    });
    response.done.then((_) {
      if (!done.isCompleted) {
        done.complete();
      }
    }).catchError((_) {
      if (!done.isCompleted) {
        done.complete();
      }
    });
    await done.future;
    heartbeat.cancel();
    await subscription.cancel();
    try {
      await response.close();
    } catch (_) {
      // The client may already have disconnected.
    }
  }

  String _sse(EventEnvelope event) =>
      'id: ${event.sequence}\nevent: ${event.type}\ndata: ${jsonEncode(event.toJson())}\n\n';

  bool _originAllowed(String raw) {
    final candidate = _normalizeOrigin(raw);
    if (candidate == null) {
      return false;
    }
    for (final allowed in runtime.settings.allowedOrigins) {
      if (_normalizeOrigin(allowed) == candidate) {
        return true;
      }
    }
    return false;
  }

  String? _normalizeOrigin(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.host.isEmpty ||
        !const <String>{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    if (uri.path.isNotEmpty && uri.path != '/' ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    final defaultPort = uri.scheme == 'https' ? 443 : 80;
    final port = uri.hasPort ? uri.port : defaultPort;
    return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}:$port';
  }

  String _correlationId(String? supplied) {
    if (supplied != null &&
        RegExp(r'^[A-Za-z0-9._-]{8,128}$').hasMatch(supplied)) {
      return supplied;
    }
    return newId('request');
  }

  PromptGenerationAction _promptAction(Object? raw) =>
      PromptGenerationAction.values
          .where((item) => item.name == raw?.toString())
          .firstOrNull ??
      PromptGenerationAction.generate;

  PlanningDepth _planningDepth(Object? raw) =>
      PlanningDepth.values
          .where((item) => item.name == raw?.toString())
          .firstOrNull ??
      PlanningDepth.auto;

  String _required(Map<String, dynamic> body, String name) {
    final value = body[name]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw _HttpFailure(HttpStatus.badRequest, 'argument_required',
          'Field "$name" is required.');
    }
    return value;
  }

  Future<void> _json(HttpResponse response, int status, Object value) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(value));
    await response.close();
  }

  Future<void> _writeError(
    HttpResponse response,
    int status,
    String code,
    String message,
    String correlationId,
    Map<String, dynamic> details,
  ) async {
    try {
      await _json(response, status, <String, dynamic>{
        'error': <String, dynamic>{
          'code': code,
          'message': message,
          'details': runtime.redactor.redactJson(details),
          'correlationId': correlationId,
        },
      });
    } catch (_) {
      try {
        await response.close();
      } catch (_) {
        // The response may already have been closed by a disconnected client.
      }
    }
  }

  int _statusForProductError(String code) {
    if (code.endsWith('_missing') || code == 'path_missing') {
      return HttpStatus.notFound;
    }
    if (code.startsWith('permission_') ||
        code.endsWith('_rejected') ||
        code == 'network_disabled') {
      return HttpStatus.forbidden;
    }
    if (code == 'stale_content' ||
        code.endsWith('_changed') ||
        code == 'run_retry_required') {
      return HttpStatus.conflict;
    }
    if (code.contains('timeout')) {
      return HttpStatus.gatewayTimeout;
    }
    if (code.startsWith('model_') && code.contains('unavailable')) {
      return HttpStatus.serviceUnavailable;
    }
    if (code.startsWith('budget_')) {
      return HttpStatus.unprocessableEntity;
    }
    return HttpStatus.badRequest;
  }

  Map<String, dynamic> _openApi() => <String, dynamic>{
        'openapi': '3.1.0',
        'info': <String, dynamic>{
          'title': 'Kristin Local Agent Governed API',
          'version': kristinVersion,
          'description':
              'Loopback-only, bearer-authenticated API. Tokens are hashed, scoped, expiring, and optionally project-bound.',
        },
        'servers': <Map<String, String>>[
          <String, String>{
            'url': 'http://127.0.0.1:${runtime.settings.apiPort}/v1'
          },
        ],
        'components': <String, dynamic>{
          'securitySchemes': <String, dynamic>{
            'bearerAuth': <String, String>{'type': 'http', 'scheme': 'bearer'},
          },
        },
        'security': <Map<String, Object>>[
          <String, Object>{'bearerAuth': <Object>[]},
        ],
        'paths': <String, dynamic>{
          '/health': <String, dynamic>{
            'get': <String, dynamic>{
              'security': <Object>[],
              'summary': 'Health check'
            }
          },
          '/projects': <String, dynamic>{
            'get': <String, String>{'summary': 'List projects'},
            'post': <String, String>{'summary': 'Register project'}
          },
          '/projects/{projectId}/manager': <String, dynamic>{
            'get': <String, String>{
              'summary': 'Read the Project Manager dashboard state'
            }
          },
          '/projects/{projectId}/analyze': <String, dynamic>{
            'post': <String, String>{
              'summary': 'Run the detected bounded static analysis'
            }
          },
          '/projects/{projectId}/test': <String, dynamic>{
            'post': <String, String>{
              'summary': 'Run detected bounded project tests'
            }
          },
          '/projects/{projectId}/build': <String, dynamic>{
            'post': <String, String>{
              'summary': 'Run the detected bounded project build'
            }
          },
          '/projects/{projectId}/run': <String, dynamic>{
            'post': <String, String>{
              'summary': 'Start the detected run command as a managed process'
            }
          },
          '/projects/{projectId}/stop': <String, dynamic>{
            'post': <String, String>{
              'summary': 'Stop the active managed project process'
            }
          },
          '/models': <String, dynamic>{
            'get': <String, String>{
              'summary': 'Discover exact model identities'
            }
          },
          '/prompts': <String, dynamic>{
            'get': <String, String>{'summary': 'List Prompt Studio prompts'}
          },
          '/prompts/generate': <String, dynamic>{
            'post': <String, String>{
              'summary':
                  'Generate or improve a structured prompt draft with a selected model'
            }
          },
          '/prompts/versions': <String, dynamic>{
            'post': <String, String>{
              'summary': 'Save an immutable reviewed prompt version'
            }
          },
          '/prompts/{promptId}/versions': <String, dynamic>{
            'get': <String, String>{'summary': 'List immutable prompt versions'}
          },
          '/prompt-studio/v2/contracts': <String, dynamic>{
            'get': <String, String>{
              'summary':
                  'Read the canonical Prompt Studio 2 schemas and capability catalog'
            }
          },
          '/prompt-studio/v2/compile': <String, dynamic>{
            'post': <String, String>{
              'summary':
                  'Compile and dry-run a canonical specification and 1–100 task plan'
            }
          },
          '/prompt-studio/v2/evaluate': <String, dynamic>{
            'post': <String, String>{
              'summary':
                  'Measure a prompt-version change against a deterministic evaluation dataset'
            }
          },
          '/task-plans': <String, dynamic>{
            'get': <String, String>{
              'summary': 'List generated task-plan revisions'
            }
          },
          '/task-plans/generate': <String, dynamic>{
            'post': <String, String>{
              'summary': 'Generate a validated adaptive 1–100 task plan'
            }
          },
          '/task-plans/{planId}': <String, dynamic>{
            'get': <String, String>{'summary': 'Read one task-plan revision'},
            'put': <String, String>{
              'summary': 'Create an immutable edited task-plan revision'
            }
          },
          '/task-plans/{planId}/compile': <String, dynamic>{
            'post': <String, String>{
              'summary': 'Compile all or selected tasks into a governed command'
            }
          },
          '/commands/prepare': <String, dynamic>{
            'post': <String, String>{
              'summary': 'Prepare deterministic contract and DAG'
            }
          },
          '/commands/{commandId}/runs': <String, dynamic>{
            'post': <String, String>{'summary': 'Create persistent run'}
          },
          '/runs/{runId}/approve': <String, dynamic>{
            'post': <String, String>{
              'summary': 'Approve requested granular scopes'
            }
          },
          '/runs/{runId}/execute': <String, dynamic>{
            'post': <String, String>{'summary': 'Start governed execution'}
          },
          '/runs/{runId}/retry': <String, dynamic>{
            'post': <String, String>{
              'summary':
                  'Create a fresh linked retry with reset attempts and plan-scaled budgets'
            }
          },
          '/runs/{runId}': <String, dynamic>{
            'get': <String, String>{'summary': 'Get run state'}
          },
          '/runs/{runId}/evidence': <String, dynamic>{
            'get': <String, String>{'summary': 'Get evidence records'}
          },
          '/projects/{projectId}/knowledge': <String, dynamic>{
            'get': <String, String>{'summary': 'List project knowledge'},
            'post': <String, String>{'summary': 'Add project note'}
          },
          '/projects/{projectId}/knowledge/search': <String, dynamic>{
            'get': <String, String>{
              'summary': 'Hybrid search with inspectable citations'
            }
          },
          '/projects/{projectId}/knowledge/stats': <String, dynamic>{
            'get': <String, String>{
              'summary': 'Knowledge, archive, memory, and index statistics'
            }
          },
          '/projects/{projectId}/knowledge/reindex': <String, dynamic>{
            'post': <String, String>{
              'summary': 'Rebuild the local project index'
            }
          },
          '/projects/{projectId}/knowledge/export': <String, dynamic>{
            'post': <String, String>{
              'summary': 'Create a portable knowledge ZIP'
            }
          },
          '/projects/{projectId}/research-archive': <String, dynamic>{
            'get': <String, String>{
              'summary': 'List immutable research provenance records'
            }
          },
          '/projects/{projectId}/memory': <String, dynamic>{
            'get': <String, String>{
              'summary': 'List terminal-run memory episodes'
            }
          },
          '/events': <String, dynamic>{
            'get': <String, String>{
              'summary': 'Resume-capable server-sent event stream'
            }
          },
          '/secret-references': <String, dynamic>{
            'get': <String, String>{'summary': 'List references only'},
            'post': <String, String>{
              'summary': 'Register environment reference'
            }
          },
          '/tokens': <String, dynamic>{
            'post': <String, String>{'summary': 'Issue a token shown once'}
          },
          '/audit/verify': <String, dynamic>{
            'get': <String, String>{
              'summary': 'Verify tamper-evident audit chain'
            }
          },
          '/support-bundles': <String, dynamic>{
            'post': <String, String>{
              'summary':
                  'Save a redacted diagnostic ZIP with retained logs, run budgets, and evidence metadata'
            }
          },
        },
      };
}

class _HttpFailure implements Exception {
  const _HttpFailure(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
}
