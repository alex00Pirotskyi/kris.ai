import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/web_preview.dart';
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

  test('static preview hot reload emits revision event', () async {
    final preview = await service.startStatic();
    final client = HttpClient();
    final request = await client.getUrl(
      preview.url.resolve('/__kristin_live_reload'),
    );
    final response = await request.close();
    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.startsWith('data:'));
    final firstReload = lines.first.timeout(const Duration(seconds: 2));

    final changed = await service.sourceChanged(preview.id);
    expect(changed.revision, 1);
    expect(await firstReload, 'data: 1');
    client.close(force: true);
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
      () => const P3DevServerConfig(
        command: 'npm',
        cwd: '.',
        url: Uri(scheme: 'http', host: 'example.com', port: 8080),
      ).validate(const P3PreviewLimits()),
      throwsStateError,
    );
  });
}

Future<void> _serveReadiness(
  HttpServer server,
  _RecordingProcessHost host,
) async {
  await for (final request in server) {
    request.response.statusCode = host.ready ? HttpStatus.ok : HttpStatus.notFound;
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

final class _RecordingProcessHost implements P3PreviewProcessHost {
  int starts = 0;
  int stops = 0;
  bool ready = false;
  P3DevServerConfig? lastConfig;
  Duration? lastGrace;
  HttpServer? fixtureServer;

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
