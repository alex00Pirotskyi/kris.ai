import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/web_preview.dart';
import 'package:kristin_local_agent/product/p2_effect_boundary.dart';
import 'package:kristin_local_agent/product/p2_process_tree.dart';
import 'package:kristin_local_agent/product/p2_pty_service.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

void main() {
  late Directory root;
  late WorkspaceBoundary boundary;
  late _RecordingProcessHost processHost;
  late _RecordingRefreshTarget refreshTarget;
  late P3LivePreviewService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('p3-preview-');
    await File('${root.path}/index.html').writeAsString(
      '<html><body><main>preview</main></body></html>',
      flush: true,
    );
    await File('${root.path}/app.js').writeAsString('console.log("ready");\n');
    boundary = await WorkspaceBoundary.open(root.path);
    processHost = _RecordingProcessHost();
    refreshTarget = _RecordingRefreshTarget();
    service = P3LivePreviewService(
      boundary: boundary,
      processHost: processHost,
      refreshTarget: refreshTarget,
      limits: const P3PreviewLimits(
        defaultReadinessTimeout: Duration(seconds: 2),
        maxReadinessTimeout: Duration(seconds: 5),
        readinessPollInterval: Duration(milliseconds: 25),
      ),
    );
  });

  tearDown(() async {
    await service.close();
    await processHost.closeFixtures();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('static preview serves project files and injects live reload', () async {
    final preview = await service.startStatic();
    expect(preview.kind, P3PreviewKind.staticFiles);
    expect(preview.lifecycle, P3PreviewLifecycle.ready);
    expect(preview.url.host, '127.0.0.1');

    final response = await _get(preview.url);
    expect(response.statusCode, HttpStatus.ok);
    expect(response.body, contains('<main>preview</main>'));
    expect(response.body, contains('data-kristin-live-reload'));

    final js = await _get(preview.url.resolve('/app.js'));
    expect(js.statusCode, HttpStatus.ok);
    expect(js.body, contains('console.log'));

    final missing = await _get(preview.url.resolve('/missing.js'));
    expect(missing.statusCode, HttpStatus.notFound);
  });

  test('static preview hot reload exposes monotonic revision polling',
      () async {
    final preview = await service.startStatic();
    final reloadUri = preview.url.resolve('/__kristin_live_reload');

    final initial = await _get(reloadUri);
    expect(initial.statusCode, HttpStatus.ok);
    expect(jsonDecode(initial.body), <String, Object?>{'revision': 0});

    final changed = await service.sourceChanged(preview.id);
    expect(changed.revision, 1);

    final updated = await _get(reloadUri);
    expect(updated.statusCode, HttpStatus.ok);
    expect(jsonDecode(updated.body), <String, Object?>{'revision': 1});

    final refreshedPage = await _get(preview.url);
    expect(refreshedPage.body, contains('var revision=1'));
    expect(refreshedPage.body, contains('fetch("/__kristin_live_reload"'));
  });

  test('static preview rejects encoded path traversal', () async {
    final preview = await service.startStatic();
    final response = await _get(
      Uri.parse('${preview.url.origin}/%2e%2e/outside.txt'),
    );
    expect(response.statusCode, HttpStatus.notFound);
  });

  test('configured dev server waits for readiness and refreshes on save',
      () async {
    final fixture = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    processHost.fixtureServer = fixture;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 100), () async {
        processHost.ready = true;
      }),
    );
    unawaited(_serveReadiness(fixture, processHost));

    final url = Uri.parse('http://127.0.0.1:${fixture.port}/');
    final preview = await service.startDevServer(
      P3DevServerConfig(
        command: 'npm',
        arguments: const <String>['run', 'dev'],
        cwd: '.',
        url: url,
        readinessPath: '/health',
      ),
    );

    expect(preview.lifecycle, P3PreviewLifecycle.ready);
    expect(processHost.starts, 1);
    expect(processHost.lastConfig?.command, 'npm');
    expect(processHost.lastConfig?.arguments, <String>['run', 'dev']);

    final changed = await service.sourceChanged(preview.id);
    expect(changed.revision, 1);
    expect(refreshTarget.urls, <Uri>[url]);

    await service.stop(preview.id);
    expect(processHost.stops, 1);
    expect(processHost.lastGrace, const Duration(seconds: 3));
  });

  test('dev server readiness failure stops managed process', () async {
    final portHolder = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = portHolder.port;
    await portHolder.close();

    await expectLater(
      service.startDevServer(
        P3DevServerConfig(
          command: 'fixture-dev',
          cwd: '.',
          url: Uri.parse('http://127.0.0.1:$port/'),
          readinessTimeout: const Duration(milliseconds: 150),
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(processHost.starts, 1);
    expect(processHost.stops, 1);
  });

  test('configured dev server rejects non-loopback targets', () async {
    expect(
      () => P3DevServerConfig(
        command: 'npm',
        cwd: '.',
        url: Uri(scheme: 'http', host: 'example.com', port: 8080),
      ).validate(const P3PreviewLimits()),
      throwsStateError,
    );
  });
  test('P2 managed preview host binds PTY launch and exact process stop',
      () async {
    final pty = _RecordingPreviewPtyBackend();
    final processTree = _RecordingPreviewProcessTreeAdapter();
    final completions = <String>[];
    final host = P3P2ManagedPreviewProcessHost(
      ptyBackend: pty,
      processTreeAdapter: processTree,
      authorizationFor: (_) => P3PreviewProcessAuthorization(
        binding: _previewBinding(),
        grantDigest: 'a' * 64,
      ),
      onProcessStopped: (sessionId, identity) async {
        completions.add('$sessionId:${identity.stableKey}');
      },
    );
    final config = P3DevServerConfig(
      command: 'npm',
      arguments: const <String>['run', 'dev'],
      cwd: '.',
      url: Uri.parse('http://127.0.0.1:4173/'),
      environmentDelta: const <String, String?>{'MODE': 'preview'},
    );

    final session = await host.start(config);
    expect(session.sessionId, 'managed-preview');
    expect(session.processIdentity, _previewIdentity.stableKey);
    expect(pty.lastRequest?.shell, 'npm');
    expect(pty.lastRequest?.arguments, <String>['run', 'dev']);
    expect(pty.lastRequest?.environmentDelta, <String, String?>{
      'MODE': 'preview',
    });
    expect(pty.lastBinding?.operation, 'pty.open');
    expect(pty.lastGrantDigest, 'a' * 64);
    expect(processTree.calls, <String>['inspect']);

    await host.stop(session, const Duration(milliseconds: 75));
    expect(processTree.calls, <String>[
      'inspect',
      'inspect',
      'stop:75',
      'inspect',
    ]);
    expect(completions, <String>[
      'managed-preview:${_previewIdentity.stableKey}',
    ]);
  });

  test('P2 managed preview host rejects malformed authorization', () async {
    final pty = _RecordingPreviewPtyBackend();
    final host = P3P2ManagedPreviewProcessHost(
      ptyBackend: pty,
      processTreeAdapter: _RecordingPreviewProcessTreeAdapter(),
      authorizationFor: (_) => P3PreviewProcessAuthorization(
        binding: _previewBinding(),
        grantDigest: 'not-a-digest',
      ),
      onProcessStopped: (_, __) async {},
    );

    await expectLater(
      host.start(
        P3DevServerConfig(
          command: 'npm',
          cwd: '.',
          url: Uri.parse('http://127.0.0.1:4173/'),
        ),
      ),
      throwsStateError,
    );
    expect(pty.openCount, 0);
  });

  test('failed dev-server stop remains observable and retryable', () async {
    final fixture = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    processHost
      ..fixtureServer = fixture
      ..ready = true;
    unawaited(_serveReadiness(fixture, processHost));

    final preview = await service.startDevServer(
      P3DevServerConfig(
        command: 'fixture-dev',
        cwd: '.',
        url: Uri.parse('http://127.0.0.1:${fixture.port}/'),
      ),
    );
    processHost.stopFailures = 1;

    await expectLater(service.stop(preview.id), throwsStateError);
    final failed = service.snapshot(preview.id);
    expect(failed.lifecycle, P3PreviewLifecycle.failed);
    expect(failed.failureCode, 'web_preview_stop_failed');

    await service.stop(preview.id);
    expect(processHost.stops, 2);
    expect(() => service.snapshot(preview.id), throwsStateError);
  });
}

Future<void> _serveReadiness(
  HttpServer server,
  _RecordingProcessHost host,
) async {
  await for (final request in server) {
    request.response.statusCode =
        host.ready ? HttpStatus.ok : HttpStatus.notFound;
    request.response.write(host.ready ? 'ready' : 'starting');
    await request.response.close();
  }
}

Future<_HttpFixtureResponse> _get(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return _HttpFixtureResponse(response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

final class _HttpFixtureResponse {
  const _HttpFixtureResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

const P2ProcessIdentity _previewIdentity = P2ProcessIdentity(
  pid: 4101,
  startToken: 'preview-start',
  supervisorToken: 'preview-supervisor',
  platformGroupId: 'preview-group',
);

P2EffectBinding _previewBinding() => const P2EffectBinding(
      runId: 'run-preview',
      taskId: 'P3-013',
      actorId: 'desktop_host',
      toolId: 'web_preview',
      accessProfileId: 'owner',
      capabilityId: 'pty',
      operation: 'pty.open',
    );

final class _RecordingPreviewPtyBackend implements P2PtyBackend {
  int openCount = 0;
  P2PtyOpenRequest? lastRequest;
  P2EffectBinding? lastBinding;
  String? lastGrantDigest;

  @override
  Future<P2PtySession> open(
    P2PtyOpenRequest request,
    P2EffectBinding binding,
    String grantDigest,
  ) async {
    openCount += 1;
    lastRequest = request;
    lastBinding = binding;
    lastGrantDigest = grantDigest;
    return P2PtySession(
      sessionId: 'managed-preview',
      runId: binding.runId,
      taskId: binding.taskId,
      actorId: binding.actorId,
      grantDigest: grantDigest,
      processIdentity: _previewIdentity,
      state: P2PtyState.attached,
      transcriptCursor: 0,
    );
  }

  @override
  Future<void> terminate(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) async {}

  @override
  Future<P2PtySession> attach(
    String sessionId,
    int fromCursor, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> detach(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> input(
    String sessionId,
    List<int> bytes, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> interrupt(
    String sessionId, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) =>
      throw UnimplementedError();

  @override
  Stream<List<int>> output(
    String sessionId,
    int fromCursor, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) =>
      const Stream<List<int>>.empty();

  @override
  Future<void> resize(
    String sessionId,
    int columns,
    int rows, {
    required P2EffectBinding binding,
    required String grantDigest,
  }) =>
      throw UnimplementedError();
}

final class _RecordingPreviewProcessTreeAdapter
    implements P2NativeProcessTreeAdapter {
  final List<String> calls = <String>[];
  P2ProcessLifecycle state = P2ProcessLifecycle.running;

  @override
  Future<P2ProcessLifecycle> inspect(P2ProcessIdentity identity) async {
    expect(identity.stableKey, _previewIdentity.stableKey);
    calls.add('inspect');
    return state;
  }

  @override
  Future<void> requestStop(
    P2ProcessIdentity identity,
    Duration grace,
  ) async {
    expect(identity.stableKey, _previewIdentity.stableKey);
    calls.add('stop:${grace.inMilliseconds}');
    state = P2ProcessLifecycle.stopped;
  }

  @override
  Future<void> forceKill(P2ProcessIdentity identity) async {
    expect(identity.stableKey, _previewIdentity.stableKey);
    calls.add('kill');
    state = P2ProcessLifecycle.killed;
  }
}

final class _RecordingProcessHost implements P3PreviewProcessHost {
  int starts = 0;
  int stops = 0;
  bool ready = false;
  P3DevServerConfig? lastConfig;
  Duration? lastGrace;
  HttpServer? fixtureServer;
  int stopFailures = 0;

  @override
  Future<P3PreviewProcessSession> start(P3DevServerConfig config) async {
    starts += 1;
    lastConfig = config;
    return P3PreviewProcessSession(
      sessionId: 'dev-session-$starts',
      processIdentity: 'managed-process-$starts',
    );
  }

  @override
  Future<void> stop(
    P3PreviewProcessSession session,
    Duration grace,
  ) async {
    stops += 1;
    lastGrace = grace;
    if (stopFailures > 0) {
      stopFailures -= 1;
      throw StateError('fixture_stop_failed');
    }
    final server = fixtureServer;
    fixtureServer = null;
    if (server != null) await server.close(force: true);
  }

  Future<void> closeFixtures() async {
    final server = fixtureServer;
    fixtureServer = null;
    if (server != null) await server.close(force: true);
  }
}

final class _RecordingRefreshTarget implements P3PreviewRefreshTarget {
  final List<Uri> urls = <Uri>[];

  @override
  Future<void> refresh(Uri url) async {
    urls.add(url);
  }
}
