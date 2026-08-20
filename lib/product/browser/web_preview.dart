import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../p2_effect_boundary.dart';
import '../p2_process_tree.dart';
import '../p2_pty_service.dart';
import '../storage_security.dart' show ProductException;
import '../workspace_tools.dart';

final class P3PreviewLimits {
  const P3PreviewLimits({
    this.maxStaticFileBytes = 16 * 1024 * 1024,
    this.maxReloadClients = 32,
    this.defaultReadinessTimeout = const Duration(seconds: 20),
    this.maxReadinessTimeout = const Duration(minutes: 2),
    this.readinessPollInterval = const Duration(milliseconds: 150),
    this.stopGrace = const Duration(seconds: 3),
  });

  final int maxStaticFileBytes;
  final int maxReloadClients;
  final Duration defaultReadinessTimeout;
  final Duration maxReadinessTimeout;
  final Duration readinessPollInterval;
  final Duration stopGrace;

  void validate() {
    if (maxStaticFileBytes < 1024 ||
        maxStaticFileBytes > 128 * 1024 * 1024 ||
        maxReloadClients < 1 ||
        maxReloadClients > 256 ||
        defaultReadinessTimeout <= Duration.zero ||
        defaultReadinessTimeout > maxReadinessTimeout ||
        maxReadinessTimeout > const Duration(minutes: 10) ||
        readinessPollInterval < const Duration(milliseconds: 20) ||
        readinessPollInterval > const Duration(seconds: 5) ||
        stopGrace <= Duration.zero ||
        stopGrace > const Duration(seconds: 30)) {
      throw StateError('web_preview_limits_invalid');
    }
  }
}

final class P3DevServerConfig {
  const P3DevServerConfig({
    required this.command,
    required this.cwd,
    required this.url,
    this.arguments = const <String>[],
    this.environmentDelta = const <String, String?>{},
    this.readinessPath = '/',
    this.readinessTimeout,
    this.acceptedStatusMinimum = 200,
    this.acceptedStatusMaximum = 499,
    this.refreshOnSourceChange = true,
  });

  final String command;
  final String cwd;
  final Uri url;
  final List<String> arguments;
  final Map<String, String?> environmentDelta;
  final String readinessPath;
  final Duration? readinessTimeout;
  final int acceptedStatusMinimum;
  final int acceptedStatusMaximum;
  final bool refreshOnSourceChange;

  void validate(P3PreviewLimits limits) {
    if (command.trim().isEmpty || cwd.trim().isEmpty) {
      throw StateError('web_preview_dev_server_command_invalid');
    }
    _requireLoopbackHttp(url);
    if (arguments.length > 256 || environmentDelta.length > 128) {
      throw StateError('web_preview_dev_server_quota_exceeded');
    }
    if (!readinessPath.startsWith('/') || readinessPath.length > 2048) {
      throw StateError('web_preview_readiness_path_invalid');
    }
    final timeout = readinessTimeout ?? limits.defaultReadinessTimeout;
    if (timeout <= Duration.zero || timeout > limits.maxReadinessTimeout) {
      throw StateError('web_preview_readiness_timeout_invalid');
    }
    if (acceptedStatusMinimum < 100 ||
        acceptedStatusMaximum > 599 ||
        acceptedStatusMinimum > acceptedStatusMaximum) {
      throw StateError('web_preview_readiness_status_invalid');
    }
  }
}

final class P3PreviewProcessSession {
  const P3PreviewProcessSession({
    required this.sessionId,
    required this.processIdentity,
  });

  final String sessionId;
  final String processIdentity;
}

abstract interface class P3PreviewProcessHost {
  Future<P3PreviewProcessSession> start(P3DevServerConfig config);
  Future<void> stop(P3PreviewProcessSession session, Duration grace);
}

final class P3PreviewProcessAuthorization {
  const P3PreviewProcessAuthorization({
    required this.binding,
    required this.grantDigest,
  });

  final P2EffectBinding binding;
  final String grantDigest;

  void validate() {
    final values = <String>[
      binding.runId,
      binding.taskId,
      binding.actorId,
      binding.toolId,
      binding.accessProfileId,
      binding.capabilityId,
    ];
    if (values.any((value) => value.trim().isEmpty) ||
        binding.operation != 'pty.open' ||
        !RegExp(r'^[0-9a-f]{64}$', caseSensitive: false)
            .hasMatch(grantDigest)) {
      throw StateError('web_preview_process_authorization_invalid');
    }
  }
}

typedef P3PreviewProcessAuthorizationResolver = P3PreviewProcessAuthorization
    Function(P3DevServerConfig config);
typedef P3PreviewProcessCompletion = Future<void> Function(
  String sessionId,
  P2ProcessIdentity processIdentity,
);

final class P3P2ManagedPreviewProcessHost implements P3PreviewProcessHost {
  P3P2ManagedPreviewProcessHost({
    required this.ptyBackend,
    required P2NativeProcessTreeAdapter processTreeAdapter,
    required this.authorizationFor,
    required this.onProcessStopped,
  }) : _processTrees = P2ProcessTreeManager(processTreeAdapter);

  final P2PtyBackend ptyBackend;
  final P3PreviewProcessAuthorizationResolver authorizationFor;
  final P3PreviewProcessCompletion onProcessStopped;
  final P2ProcessTreeManager _processTrees;
  final Map<String, _P3P2ManagedPreviewSession> _sessions =
      <String, _P3P2ManagedPreviewSession>{};

  @override
  Future<P3PreviewProcessSession> start(P3DevServerConfig config) async {
    final authorization = authorizationFor(config);
    authorization.validate();
    final session = await ptyBackend.open(
      P2PtyOpenRequest(
        shell: config.command,
        cwd: config.cwd,
        arguments: List<String>.unmodifiable(config.arguments),
        environmentDelta:
            Map<String, String?>.unmodifiable(config.environmentDelta),
        transcriptBudgetBytes: 1024 * 1024,
      ),
      authorization.binding,
      authorization.grantDigest,
    );
    if (_sessions.containsKey(session.sessionId)) {
      await _terminateFailedOpen(session, authorization);
      throw StateError('web_preview_process_session_duplicate');
    }
    try {
      final identity =
          await _processTrees.adoptManaged(session.processIdentity);
      _sessions[session.sessionId] = _P3P2ManagedPreviewSession(
        session: session,
        authorization: authorization,
        processIdentity: identity,
      );
      return P3PreviewProcessSession(
        sessionId: session.sessionId,
        processIdentity: identity.stableKey,
      );
    } catch (_) {
      await _terminateFailedOpen(session, authorization);
      rethrow;
    }
  }

  Future<void> _terminateFailedOpen(
    P2PtySession session,
    P3PreviewProcessAuthorization authorization,
  ) async {
    var stopped = false;
    try {
      await ptyBackend.terminate(
        session.sessionId,
        binding: authorization.binding,
        grantDigest: authorization.grantDigest,
      );
      stopped = true;
    } catch (_) {}
    if (stopped) {
      try {
        await onProcessStopped(session.sessionId, session.processIdentity);
      } catch (_) {}
    }
  }

  @override
  Future<void> stop(
    P3PreviewProcessSession session,
    Duration grace,
  ) async {
    final record = _sessions[session.sessionId];
    if (record == null) {
      throw StateError('web_preview_process_session_unknown');
    }
    if (session.processIdentity != record.processIdentity.stableKey) {
      throw StateError('web_preview_process_identity_mismatch');
    }
    await _processTrees.stop(record.processIdentity, grace: grace);
    await onProcessStopped(session.sessionId, record.processIdentity);
    _sessions.remove(session.sessionId);
  }
}

final class _P3P2ManagedPreviewSession {
  const _P3P2ManagedPreviewSession({
    required this.session,
    required this.authorization,
    required this.processIdentity,
  });

  final P2PtySession session;
  final P3PreviewProcessAuthorization authorization;
  final P2ProcessIdentity processIdentity;
}

abstract interface class P3PreviewRefreshTarget {
  Future<void> refresh(Uri url);
}

enum P3PreviewKind { staticFiles, devServer }

enum P3PreviewLifecycle { starting, ready, stopping, stopped, failed }

final class P3PreviewSnapshot {
  const P3PreviewSnapshot({
    required this.id,
    required this.kind,
    required this.lifecycle,
    required this.url,
    required this.revision,
    required this.startedAt,
    this.processSession,
    this.failureCode,
  });

  final String id;
  final P3PreviewKind kind;
  final P3PreviewLifecycle lifecycle;
  final Uri url;
  final int revision;
  final DateTime startedAt;
  final P3PreviewProcessSession? processSession;
  final String? failureCode;
}

final class P3LivePreviewService {
  P3LivePreviewService({
    required this.boundary,
    required this.processHost,
    this.refreshTarget,
    this.limits = const P3PreviewLimits(),
    HttpClient Function()? httpClientFactory,
    DateTime Function()? clock,
  })  : _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _clock = clock ?? DateTime.now {
    limits.validate();
  }

  final WorkspaceBoundary boundary;
  final P3PreviewProcessHost processHost;
  final P3PreviewRefreshTarget? refreshTarget;
  final P3PreviewLimits limits;
  final HttpClient Function() _httpClientFactory;
  final DateTime Function() _clock;

  final Map<String, _P3StaticPreview> _static = <String, _P3StaticPreview>{};
  final Map<String, _P3DevPreview> _dev = <String, _P3DevPreview>{};
  int _nextPreview = 0;
  bool _closed = false;

  String _id() {
    _nextPreview += 1;
    return 'preview-${_nextPreview.toString().padLeft(6, '0')}';
  }

  void _requireOpen() {
    if (_closed) throw StateError('web_preview_service_closed');
  }

  Future<P3PreviewSnapshot> startStatic({
    String root = '.',
    String entryPoint = 'index.html',
  }) async {
    _requireOpen();
    final normalizedRoot = boundary.normalizeToolPath(root);
    final rootDirectory = await boundary.directory(normalizedRoot);
    final normalizedEntry = _normalizeRequestPath(entryPoint);
    final entry = await boundary.file(
      _joinRelative(normalizedRoot, normalizedEntry),
    );
    if (!await entry.exists()) {
      throw ProductException(
        'web_preview_entry_missing',
        'The static preview entry point does not exist.',
      );
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final id = _id();
    final preview = _P3StaticPreview(
      id: id,
      server: server,
      root: rootDirectory,
      rootRelative: normalizedRoot,
      entryPoint: normalizedEntry,
      startedAt: _clock().toUtc(),
      maxFileBytes: limits.maxStaticFileBytes,
      maxReloadClients: limits.maxReloadClients,
      boundary: boundary,
    );
    _static[id] = preview;
    preview.serve().whenComplete(() {
      _static.remove(id);
    });
    return preview.snapshot;
  }

  Future<P3PreviewSnapshot> startDevServer(P3DevServerConfig config) async {
    _requireOpen();
    config.validate(limits);
    await boundary.directory(boundary.normalizeToolPath(config.cwd));

    final id = _id();
    final startedAt = _clock().toUtc();
    final process = await processHost.start(config);
    if (process.sessionId.trim().isEmpty ||
        process.processIdentity.trim().isEmpty) {
      try {
        await processHost.stop(process, limits.stopGrace);
      } catch (_) {}
      throw StateError('web_preview_process_identity_invalid');
    }
    final preview = _P3DevPreview(
      id: id,
      config: config,
      process: process,
      startedAt: startedAt,
    );
    _dev[id] = preview;
    try {
      await _waitUntilReady(config);
      preview.lifecycle = P3PreviewLifecycle.ready;
      return preview.snapshot;
    } catch (_) {
      preview.lifecycle = P3PreviewLifecycle.failed;
      preview.failureCode = 'web_preview_readiness_failed';
      try {
        await processHost.stop(process, limits.stopGrace);
      } finally {
        _dev.remove(id);
      }
      rethrow;
    }
  }

  Future<void> _waitUntilReady(P3DevServerConfig config) async {
    final timeout = config.readinessTimeout ?? limits.defaultReadinessTimeout;
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    while (stopwatch.elapsed < timeout) {
      final client = _httpClientFactory();
      try {
        client.connectionTimeout = limits.readinessPollInterval;
        final probeUri = config.url.replace(path: config.readinessPath);
        final request = await client.getUrl(probeUri);
        request.followRedirects = false;
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode >= config.acceptedStatusMinimum &&
            response.statusCode <= config.acceptedStatusMaximum) {
          return;
        }
        lastError = StateError(
          'readiness_status_${response.statusCode}',
        );
      } catch (error) {
        lastError = error;
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(limits.readinessPollInterval);
    }
    throw TimeoutException(
      'web_preview_readiness_timeout:${lastError ?? 'unreachable'}',
      timeout,
    );
  }

  P3PreviewSnapshot snapshot(String previewId) {
    final staticPreview = _static[previewId];
    if (staticPreview != null) return staticPreview.snapshot;
    final devPreview = _dev[previewId];
    if (devPreview != null) return devPreview.snapshot;
    throw StateError('web_preview_unknown');
  }

  Future<P3PreviewSnapshot> sourceChanged(String previewId) async {
    _requireOpen();
    final staticPreview = _static[previewId];
    if (staticPreview != null) {
      await staticPreview.notifyReload();
      return staticPreview.snapshot;
    }
    final devPreview = _dev[previewId];
    if (devPreview == null) throw StateError('web_preview_unknown');
    if (devPreview.lifecycle != P3PreviewLifecycle.ready) {
      throw StateError('web_preview_not_ready');
    }
    devPreview.revision += 1;
    if (devPreview.config.refreshOnSourceChange) {
      final target = refreshTarget;
      if (target != null) await target.refresh(devPreview.config.url);
    }
    return devPreview.snapshot;
  }

  Future<void> stop(String previewId) async {
    final staticPreview = _static.remove(previewId);
    if (staticPreview != null) {
      await staticPreview.stop();
      return;
    }
    final devPreview = _dev.remove(previewId);
    if (devPreview == null) return;
    devPreview.lifecycle = P3PreviewLifecycle.stopping;
    try {
      await processHost.stop(devPreview.process, limits.stopGrace);
      devPreview.lifecycle = P3PreviewLifecycle.stopped;
    } catch (_) {
      devPreview.lifecycle = P3PreviewLifecycle.failed;
      devPreview.failureCode = 'web_preview_stop_failed';
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final ids = <String>{..._static.keys, ..._dev.keys}.toList();
    Object? firstError;
    StackTrace? firstStack;
    for (final id in ids) {
      try {
        await stop(id);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}

final class _P3DevPreview {
  _P3DevPreview({
    required this.id,
    required this.config,
    required this.process,
    required this.startedAt,
  });

  final String id;
  final P3DevServerConfig config;
  final P3PreviewProcessSession process;
  final DateTime startedAt;
  P3PreviewLifecycle lifecycle = P3PreviewLifecycle.starting;
  int revision = 0;
  String? failureCode;

  P3PreviewSnapshot get snapshot => P3PreviewSnapshot(
        id: id,
        kind: P3PreviewKind.devServer,
        lifecycle: lifecycle,
        url: config.url,
        revision: revision,
        startedAt: startedAt,
        processSession: process,
        failureCode: failureCode,
      );
}

final class _P3StaticPreview {
  _P3StaticPreview({
    required this.id,
    required this.server,
    required this.root,
    required this.rootRelative,
    required this.entryPoint,
    required this.startedAt,
    required this.maxFileBytes,
    required this.maxReloadClients,
    required this.boundary,
  });

  static const String reloadPath = '/__kristin_live_reload';
  static const String reloadScript =
      '<script data-kristin-live-reload>(function(){var e=new EventSource("/__kristin_live_reload");e.onmessage=function(){location.reload();};})();</script>';

  final String id;
  final HttpServer server;
  final Directory root;
  final String rootRelative;
  final String entryPoint;
  final DateTime startedAt;
  final int maxFileBytes;
  final int maxReloadClients;
  final WorkspaceBoundary boundary;

  final Set<HttpResponse> _reloadClients = <HttpResponse>{};
  P3PreviewLifecycle lifecycle = P3PreviewLifecycle.ready;
  int revision = 0;
  bool _stopped = false;

  Uri get url => Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: '/$entryPoint',
      );

  P3PreviewSnapshot get snapshot => P3PreviewSnapshot(
        id: id,
        kind: P3PreviewKind.staticFiles,
        lifecycle: lifecycle,
        url: url,
        revision: revision,
        startedAt: startedAt,
      );

  Future<void> serve() async {
    try {
      await for (final request in server) {
        unawaited(_handle(request));
      }
    } finally {
      for (final response in _reloadClients.toList()) {
        try {
          await response.close();
        } catch (_) {}
      }
      _reloadClients.clear();
      if (!_stopped) lifecycle = P3PreviewLifecycle.failed;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }
      if (request.uri.path == reloadPath) {
        if (request.method == 'HEAD') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }
        if (_reloadClients.length >= maxReloadClients) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        final response = request.response;
        response.statusCode = HttpStatus.ok;
        response.headers
          ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
          ..set(HttpHeaders.cacheControlHeader, 'no-store')
          ..set(HttpHeaders.connectionHeader, 'keep-alive');
        response.bufferOutput = false;
        _reloadClients.add(response);
        try {
          response.write('retry: 500\n\n');
          await response.flush();
        } catch (_) {
          _reloadClients.remove(response);
          rethrow;
        }
        return;
      }

      var requested = _normalizeRequestPath(request.uri.path);
      if (requested.isEmpty) requested = entryPoint;
      final relative = _joinRelative(rootRelative, requested);
      final file = await boundary.file(relative);
      if (!await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final stat = await file.stat();
      if (stat.size > maxFileBytes) {
        request.response.statusCode = HttpStatus.requestEntityTooLarge;
        await request.response.close();
        return;
      }
      final bytes = await file.readAsBytes();
      request.response.headers
        ..contentType = _contentType(file.path)
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('X-Content-Type-Options', 'nosniff');
      if (request.method == 'HEAD') {
        request.response.contentLength = bytes.length;
        await request.response.close();
        return;
      }
      if (_isHtml(file.path)) {
        final html = utf8.decode(bytes, allowMalformed: false);
        final body = _injectReload(html);
        request.response.write(body);
      } else {
        request.response.add(bytes);
      }
      await request.response.close();
    } on ProductException {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } on FormatException {
      request.response.statusCode = HttpStatus.unsupportedMediaType;
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  String _injectReload(String html) {
    final bodyIndex = html.toLowerCase().lastIndexOf('</body>');
    if (bodyIndex < 0) return '$html$reloadScript';
    return '${html.substring(0, bodyIndex)}$reloadScript${html.substring(bodyIndex)}';
  }

  Future<void> notifyReload() async {
    if (lifecycle != P3PreviewLifecycle.ready) {
      throw StateError('web_preview_not_ready');
    }
    revision += 1;
    for (final response in _reloadClients.toList()) {
      try {
        response.write('data: $revision\n\n');
        await response.flush();
      } catch (_) {
        _reloadClients.remove(response);
      }
    }
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    lifecycle = P3PreviewLifecycle.stopping;
    for (final response in _reloadClients.toList()) {
      try {
        await response.close();
      } catch (_) {}
    }
    _reloadClients.clear();
    await server.close(force: true);
    lifecycle = P3PreviewLifecycle.stopped;
  }
}

String _normalizeRequestPath(String value) {
  final decoded = Uri.decodeComponent(value.replaceAll('\\', '/'));
  final segments = decoded.split('/').where((segment) => segment.isNotEmpty);
  final output = <String>[];
  for (final segment in segments) {
    if (segment == '.' || segment.isEmpty) continue;
    if (segment == '..' || segment.contains('\u0000')) {
      throw ProductException(
        'web_preview_path_rejected',
        'The preview path escapes the configured project root.',
      );
    }
    output.add(segment);
  }
  return output.join('/');
}

String _joinRelative(String root, String child) {
  if (root == '.' || root.isEmpty) return child;
  if (child.isEmpty) return root;
  return '${root.replaceAll('\\', '/')}/$child';
}

void _requireLoopbackHttp(Uri url) {
  if ((url.scheme != 'http' && url.scheme != 'https') ||
      url.port <= 0 ||
      !_isLoopbackHost(url.host)) {
    throw StateError('web_preview_url_must_be_loopback');
  }
}

bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' || normalized == '::1') return true;
  final address = InternetAddress.tryParse(normalized);
  return address?.isLoopback ?? false;
}

bool _isHtml(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.html') || lower.endsWith('.htm');
}

ContentType _contentType(String path) {
  final lower = path.toLowerCase();
  if (_isHtml(lower)) {
    return ContentType.html;
  }
  if (lower.endsWith('.css')) {
    return ContentType('text', 'css', charset: 'utf-8');
  }
  if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
    return ContentType('text', 'javascript', charset: 'utf-8');
  }
  if (lower.endsWith('.json')) {
    return ContentType.json;
  }
  if (lower.endsWith('.svg')) {
    return ContentType('image', 'svg+xml');
  }
  if (lower.endsWith('.png')) {
    return ContentType('image', 'png');
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return ContentType('image', 'jpeg');
  }
  if (lower.endsWith('.gif')) {
    return ContentType('image', 'gif');
  }
  if (lower.endsWith('.webp')) {
    return ContentType('image', 'webp');
  }
  return ContentType.binary;
}
