import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'browser_runtime_bundle.dart';
import 'browser_runtime_process.dart';

export 'browser_runtime_process.dart' show P3BrowserRuntimeException;

final class P3BrowserRuntimeProbeResult {
  const P3BrowserRuntimeProbeResult({
    required this.ready,
    required this.bundleProvenance,
  });

  final P3BrowserRuntimeReady ready;
  final Map<String, Object?> bundleProvenance;

  Map<String, Object?> get provenance => <String, Object?>{
        ...bundleProvenance,
        'probeWorkerPid': ready.pid,
        'probeBrowserPid': ready.browserPid,
        'browserEngine': ready.browserEngine,
        'browserVersion': ready.browserVersion,
        'browserRevision': ready.browserRevision,
        'protocol': ready.protocol,
        'sandboxMode': ready.sandboxMode,
        'p3_002SessionServiceImplemented': false,
      };
}

enum P3BrowserSessionKind {
  ephemeral,
  persistent;

  String get wireName => name;
}

final class P3BrowserSessionQuotas {
  const P3BrowserSessionQuotas({
    this.maxSessions = 4,
    this.maxPagesPerSession = 8,
    this.maxPersistentProfiles = 8,
  });

  final int maxSessions;
  final int maxPagesPerSession;
  final int maxPersistentProfiles;

  void validate() {
    if (maxSessions < 1 || maxSessions > 16) {
      throw const P3BrowserRuntimeException(
        'browser_session_quota_invalid',
        'maxSessions',
      );
    }
    if (maxPagesPerSession < 1 || maxPagesPerSession > 32) {
      throw const P3BrowserRuntimeException(
        'browser_session_quota_invalid',
        'maxPagesPerSession',
      );
    }
    if (maxPersistentProfiles < 1 || maxPersistentProfiles > 32) {
      throw const P3BrowserRuntimeException(
        'browser_session_quota_invalid',
        'maxPersistentProfiles',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'maxSessions': maxSessions,
        'maxPagesPerSession': maxPagesPerSession,
        'maxPersistentProfiles': maxPersistentProfiles,
      };

  @override
  bool operator ==(Object other) =>
      other is P3BrowserSessionQuotas &&
      other.maxSessions == maxSessions &&
      other.maxPagesPerSession == maxPagesPerSession &&
      other.maxPersistentProfiles == maxPersistentProfiles;

  @override
  int get hashCode => Object.hash(
        maxSessions,
        maxPagesPerSession,
        maxPersistentProfiles,
      );
}

final class P3BrowserSessionLaunchPlan {
  const P3BrowserSessionLaunchPlan({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
    required this.startupTimeout,
    required this.requestTimeout,
    required this.quotas,
  });

  static const Set<String> _identityEnvironmentKeys = <String>{
    'KRISTIN_P3_RUNTIME_MANIFEST_SHA256',
    'KRISTIN_P3_RUNTIME_BUILD_SHA256',
    'KRISTIN_P3_BROWSER_REVISION',
  };

  static const List<String> _windowsBootstrapEnvironmentKeys = <String>[
    'SYSTEMROOT',
    'WINDIR',
    'COMSPEC',
    'TEMP',
    'TMP',
    'USERPROFILE',
    'LOCALAPPDATA',
    'APPDATA',
    'PROGRAMFILES',
    'PROGRAMFILES(X86)',
    'PROGRAMDATA',
    'HOMEDRIVE',
    'HOMEPATH',
  ];

  factory P3BrowserSessionLaunchPlan.create({
    required P3BrowserRuntimeResourceSet resources,
    required Directory stateDirectory,
    P3BrowserSessionQuotas quotas = const P3BrowserSessionQuotas(),
    Duration startupTimeout = const Duration(seconds: 30),
    Duration requestTimeout = const Duration(seconds: 10),
  }) {
    quotas.validate();
    if (!stateDirectory.isAbsolute) {
      throw const P3BrowserRuntimeException(
        'state_directory_must_be_absolute',
      );
    }
    if (startupTimeout <= Duration.zero ||
        startupTimeout > const Duration(minutes: 2)) {
      throw const P3BrowserRuntimeException('startup_timeout_invalid');
    }
    if (requestTimeout <= Duration.zero ||
        requestTimeout > const Duration(minutes: 1)) {
      throw const P3BrowserRuntimeException('request_timeout_invalid');
    }
    final environment = <String, String>{
      'KRISTIN_P3_RUNTIME_MANIFEST_SHA256': resources.manifestSha256,
      'KRISTIN_P3_RUNTIME_BUILD_SHA256': resources.runtimeBuildSha256,
      'KRISTIN_P3_BROWSER_REVISION': resources.browserRevision,
    };
    if (Platform.isWindows) {
      for (final key in _windowsBootstrapEnvironmentKeys) {
        final value = _environmentValue(Platform.environment, key);
        if (value != null && value.isNotEmpty && !value.contains('\u0000')) {
          environment[key] = value;
        }
      }
      final systemRoot = environment['SYSTEMROOT'];
      if (systemRoot == null || !_isAbsolute(systemRoot)) {
        throw const P3BrowserRuntimeException(
          'windows_system_root_required',
        );
      }
    }
    final plan = P3BrowserSessionLaunchPlan(
      executable: resources.nodeExecutable,
      arguments: <String>[
        resources.workerScript,
        '--mode',
        'sessions',
        '--protocol',
        'stdio-json-v1',
        '--sandbox-mode',
        'required',
        '--browser-executable',
        resources.browserExecutable,
        '--browser-root',
        resources.browserRoot,
        '--runtime-manifest',
        resources.manifestPath,
        '--state-directory',
        stateDirectory.absolute.path,
        '--max-sessions',
        '${quotas.maxSessions}',
        '--max-pages-per-session',
        '${quotas.maxPagesPerSession}',
        '--max-persistent-profiles',
        '${quotas.maxPersistentProfiles}',
      ],
      workingDirectory: resources.workingDirectory,
      environment: environment,
      startupTimeout: startupTimeout,
      requestTimeout: requestTimeout,
      quotas: quotas,
    );
    plan.validate();
    return plan;
  }

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
  final Duration startupTimeout;
  final Duration requestTimeout;
  final P3BrowserSessionQuotas quotas;

  void validate() {
    quotas.validate();
    if (!_isAbsolute(executable) || !File(executable).existsSync()) {
      throw const P3BrowserRuntimeException(
        'bundled_node_executable_required',
      );
    }
    if (!_isAbsolute(workingDirectory) ||
        !Directory(workingDirectory).existsSync()) {
      throw const P3BrowserRuntimeException('browser_runtime_cwd_required');
    }
    if (arguments.length != 21 ||
        !_isAbsolute(arguments.first) ||
        !File(arguments.first).existsSync()) {
      throw const P3BrowserRuntimeException(
        'browser_worker_script_required',
      );
    }
    final browserExecutable = _argumentValue('--browser-executable');
    final browserRoot = _argumentValue('--browser-root');
    final runtimeManifest = _argumentValue('--runtime-manifest');
    final stateDirectory = _argumentValue('--state-directory');
    if (!_isAbsolute(browserExecutable) ||
        !File(browserExecutable).existsSync()) {
      throw const P3BrowserRuntimeException(
        'bundled_browser_executable_required',
      );
    }
    if (!_isAbsolute(browserRoot) || !Directory(browserRoot).existsSync()) {
      throw const P3BrowserRuntimeException('bundled_browser_root_required');
    }
    if (!_isAbsolute(runtimeManifest) || !File(runtimeManifest).existsSync()) {
      throw const P3BrowserRuntimeException(
        'browser_runtime_manifest_required',
      );
    }
    if (!_isAbsolute(stateDirectory) ||
        !Directory(stateDirectory).existsSync()) {
      throw const P3BrowserRuntimeException(
        'browser_state_directory_required',
      );
    }
    if (_argumentValue('--mode') != 'sessions' ||
        _argumentValue('--protocol') != 'stdio-json-v1') {
      throw const P3BrowserRuntimeException(
        'browser_session_protocol_invalid',
      );
    }
    if (_argumentValue('--sandbox-mode') != 'required') {
      throw const P3BrowserRuntimeException(
        'browser_sandbox_mode_invalid',
      );
    }
    if (_argumentValue('--max-sessions') != '${quotas.maxSessions}' ||
        _argumentValue('--max-pages-per-session') !=
            '${quotas.maxPagesPerSession}' ||
        _argumentValue('--max-persistent-profiles') !=
            '${quotas.maxPersistentProfiles}') {
      throw const P3BrowserRuntimeException(
        'browser_session_quota_binding_invalid',
      );
    }
    final allowedEnvironmentKeys = <String>{..._identityEnvironmentKeys};
    if (Platform.isWindows) {
      allowedEnvironmentKeys.addAll(_windowsBootstrapEnvironmentKeys);
    }
    if (environment.containsKey('PATH') ||
        environment.keys
            .toSet()
            .difference(allowedEnvironmentKeys)
            .isNotEmpty ||
        environment.values.any(
          (value) => value.isEmpty || value.contains('\u0000'),
        )) {
      throw const P3BrowserRuntimeException(
        'browser_runtime_environment_invalid',
      );
    }
  }

  String _argumentValue(String name) {
    final index = arguments.indexOf(name);
    if (index < 0 || index + 1 >= arguments.length) {
      throw P3BrowserRuntimeException(
        'browser_runtime_argument_missing',
        name,
      );
    }
    return arguments[index + 1];
  }

  static String? _environmentValue(
    Map<String, String> environment,
    String key,
  ) {
    final direct = environment[key];
    if (direct != null) return direct;
    final normalized = key.toUpperCase();
    for (final entry in environment.entries) {
      if (entry.key.toUpperCase() == normalized) return entry.value;
    }
    return null;
  }

  static bool _isAbsolute(String value) {
    if (Platform.isWindows) {
      return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
          value.startsWith(r'\\');
    }
    return value.startsWith('/');
  }
}

final class P3BrowserSessionReady {
  const P3BrowserSessionReady({
    required this.runtime,
    required this.quotas,
  });

  factory P3BrowserSessionReady.fromJson(
    Map<String, Object?> value, {
    required P3BrowserRuntimeResourceSet resources,
    required P3BrowserSessionQuotas expectedQuotas,
  }) {
    final runtime = P3BrowserRuntimeReady.fromJson(
      value,
      resources: resources,
    );
    final quotasValue = value['quotas'];
    if (value['serviceMode'] != 'sessions' || quotasValue is! Map) {
      throw const P3BrowserRuntimeException(
        'browser_session_ready_invalid',
      );
    }
    final quotasMap = Map<String, Object?>.from(quotasValue);
    final maxSessions = quotasMap['maxSessions'];
    final maxPagesPerSession = quotasMap['maxPagesPerSession'];
    final maxPersistentProfiles = quotasMap['maxPersistentProfiles'];
    final quotas = P3BrowserSessionQuotas(
      maxSessions: maxSessions is int ? maxSessions : -1,
      maxPagesPerSession: maxPagesPerSession is int ? maxPagesPerSession : -1,
      maxPersistentProfiles:
          maxPersistentProfiles is int ? maxPersistentProfiles : -1,
    );
    try {
      quotas.validate();
    } on P3BrowserRuntimeException {
      throw const P3BrowserRuntimeException(
        'browser_session_ready_invalid',
      );
    }
    if (quotas != expectedQuotas) {
      throw const P3BrowserRuntimeException(
        'browser_session_ready_quota_mismatch',
      );
    }
    return P3BrowserSessionReady(runtime: runtime, quotas: quotas);
  }

  final P3BrowserRuntimeReady runtime;
  final P3BrowserSessionQuotas quotas;

  Map<String, Object?> get provenance => <String, Object?>{
        'workerPid': runtime.pid,
        'browserPid': runtime.browserPid,
        'browserEngine': runtime.browserEngine,
        'browserVersion': runtime.browserVersion,
        'browserRevision': runtime.browserRevision,
        'protocol': runtime.protocol,
        'sandboxMode': runtime.sandboxMode,
        'serviceMode': 'sessions',
        'quotas': quotas.toJson(),
        'applicationOwned': true,
        'globalRuntimeRequired': false,
        'browserNetworkInstallRequired': false,
        'persistentProfileStateLocalOnly': true,
        'p3_002SessionServiceImplemented': true,
      };
}

final class P3BrowserSessionInfo {
  const P3BrowserSessionInfo({
    required this.sessionId,
    required this.kind,
    required this.profileId,
    required this.pageCount,
    required this.createdAt,
  });

  factory P3BrowserSessionInfo.fromJson(Map<String, Object?> value) {
    final sessionId = value['sessionId'];
    final kindName = value['kind'];
    final profileId = value['profileId'];
    final pageCount = value['pageCount'];
    final createdAt = DateTime.tryParse(value['createdAt']?.toString() ?? '');
    final kind = P3BrowserSessionKind.values
        .where((candidate) => candidate.wireName == kindName)
        .firstOrNull;
    if (sessionId is! String ||
        sessionId.isEmpty ||
        kind == null ||
        (profileId != null && profileId is! String) ||
        pageCount is! int ||
        pageCount < 0 ||
        createdAt == null) {
      throw const P3BrowserRuntimeException(
        'browser_session_response_invalid',
      );
    }
    if ((kind == P3BrowserSessionKind.persistent &&
            (profileId is! String || profileId.isEmpty)) ||
        (kind == P3BrowserSessionKind.ephemeral && profileId != null)) {
      throw const P3BrowserRuntimeException(
        'browser_session_response_invalid',
      );
    }
    return P3BrowserSessionInfo(
      sessionId: sessionId,
      kind: kind,
      profileId: profileId as String?,
      pageCount: pageCount,
      createdAt: createdAt.toUtc(),
    );
  }

  final String sessionId;
  final P3BrowserSessionKind kind;
  final String? profileId;
  final int pageCount;
  final DateTime createdAt;
}

final class P3BrowserPageInfo {
  const P3BrowserPageInfo({
    required this.pageId,
    required this.sessionId,
  });

  factory P3BrowserPageInfo.fromJson(Map<String, Object?> value) {
    final pageId = value['pageId'];
    final sessionId = value['sessionId'];
    if (pageId is! String ||
        pageId.isEmpty ||
        sessionId is! String ||
        sessionId.isEmpty) {
      throw const P3BrowserRuntimeException(
        'browser_page_response_invalid',
      );
    }
    return P3BrowserPageInfo(pageId: pageId, sessionId: sessionId);
  }

  final String pageId;
  final String sessionId;
}

final class P3BrowserSessionProcess {
  P3BrowserSessionProcess._(
    this._process,
    this.resources,
    this.launchPlan,
  );

  static Future<P3BrowserSessionProcess> start({
    required P3BrowserRuntimeResourceSet resources,
    required Directory stateDirectory,
    P3BrowserSessionQuotas quotas = const P3BrowserSessionQuotas(),
    Duration startupTimeout = const Duration(seconds: 30),
    Duration requestTimeout = const Duration(seconds: 10),
  }) async {
    await stateDirectory.create(recursive: true);
    final launchPlan = P3BrowserSessionLaunchPlan.create(
      resources: resources,
      stateDirectory: stateDirectory.absolute,
      quotas: quotas,
      startupTimeout: startupTimeout,
      requestTimeout: requestTimeout,
    );
    final process = await Process.start(
      launchPlan.executable,
      launchPlan.arguments,
      workingDirectory: launchPlan.workingDirectory,
      environment: launchPlan.environment,
      includeParentEnvironment: false,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    final service = P3BrowserSessionProcess._(
      process,
      resources,
      launchPlan,
    );
    try {
      await service._awaitReady();
      return service;
    } catch (_) {
      await service.close();
      rethrow;
    }
  }

  final Process _process;
  final P3BrowserRuntimeResourceSet resources;
  final P3BrowserSessionLaunchPlan launchPlan;
  final Completer<P3BrowserSessionReady> _ready =
      Completer<P3BrowserSessionReady>();
  final Map<String, Completer<Map<String, Object?>>> _pending =
      <String, Completer<Map<String, Object?>>>{};
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<List<int>> _stderrSubscription;
  P3BrowserSessionReady? _readyValue;
  int _stderrBytes = 0;
  int _requestSequence = 0;
  bool _listenersStarted = false;
  bool _closing = false;

  P3BrowserSessionReady get ready {
    final value = _readyValue;
    if (value == null) {
      throw const P3BrowserRuntimeException('browser_worker_not_ready');
    }
    return value;
  }

  int get pid => _process.pid;

  Future<void> _awaitReady() async {
    _listenersStarted = true;
    _stdoutSubscription = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onError: _handleTransportError);
    _stderrSubscription = _process.stderr.listen((bytes) {
      _stderrBytes += bytes.length;
      if (_stderrBytes > 1024 * 1024) {
        _failProtocol(
          const P3BrowserRuntimeException('browser_worker_stderr_flood'),
        );
        _process.kill();
      }
    });
    unawaited(
      _process.exitCode.then((code) {
        if (_closing) return;
        final error = P3BrowserRuntimeException(
          _ready.isCompleted
              ? 'browser_session_worker_exited'
              : 'browser_worker_exited_before_ready',
          '$code',
        );
        _failProtocol(error);
      }),
    );
    try {
      _readyValue = await _ready.future.timeout(launchPlan.startupTimeout);
    } on TimeoutException {
      throw const P3BrowserRuntimeException('browser_worker_start_timeout');
    }
  }

  void _handleLine(String line) {
    if (line.length > 1024 * 1024) {
      _failProtocol(
        const P3BrowserRuntimeException('browser_session_protocol_flood'),
      );
      return;
    }
    try {
      final value = jsonDecode(line);
      if (value is! Map) {
        throw const FormatException('JSON object required');
      }
      final mapped = Map<String, Object?>.from(value);
      if (!_ready.isCompleted && mapped['type'] == 'ready') {
        _ready.complete(
          P3BrowserSessionReady.fromJson(
            mapped,
            resources: resources,
            expectedQuotas: launchPlan.quotas,
          ),
        );
        return;
      }
      if (mapped['type'] == 'response') {
        _handleResponse(mapped);
        return;
      }
      throw const FormatException('unsupported browser session message');
    } catch (error) {
      _failProtocol(
        P3BrowserRuntimeException(
          'browser_session_protocol_invalid',
          '$error',
        ),
      );
    }
  }

  void _handleResponse(Map<String, Object?> value) {
    if (value['schemaVersion'] != '1.0.0') {
      throw const FormatException('response schema invalid');
    }
    final requestId = value['requestId'];
    final ok = value['ok'];
    if (requestId is! String || ok is! bool) {
      throw const FormatException('response envelope invalid');
    }
    final completer = _pending.remove(requestId);
    if (completer == null) {
      return;
    }
    if (ok) {
      final result = value['result'];
      if (result is! Map) {
        completer.completeError(
          const P3BrowserRuntimeException(
            'browser_session_response_invalid',
          ),
        );
      } else {
        completer.complete(Map<String, Object?>.from(result));
      }
      return;
    }
    final errorValue = value['error'];
    if (errorValue is! Map) {
      completer.completeError(
        const P3BrowserRuntimeException(
          'browser_session_response_invalid',
        ),
      );
      return;
    }
    final mappedError = Map<String, Object?>.from(errorValue);
    final code = mappedError['code']?.toString() ?? '';
    if (code.isEmpty) {
      completer.completeError(
        const P3BrowserRuntimeException(
          'browser_session_response_invalid',
        ),
      );
      return;
    }
    completer.completeError(
      P3BrowserRuntimeException(
        code,
        mappedError['message']?.toString() ?? '',
      ),
    );
  }

  void _handleTransportError(Object error) {
    _failProtocol(
      P3BrowserRuntimeException('browser_worker_transport_error', '$error'),
    );
  }

  void _failProtocol(Object error) {
    if (!_ready.isCompleted) {
      _ready.completeError(error);
    }
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  Future<Map<String, Object?>> _request(
    String type,
    Map<String, Object?> payload,
  ) async {
    if (_closing) {
      throw const P3BrowserRuntimeException(
        'browser_session_service_closed',
      );
    }
    if (_readyValue == null) {
      throw const P3BrowserRuntimeException('browser_worker_not_ready');
    }
    final requestId = 'request_${++_requestSequence}';
    final completer = Completer<Map<String, Object?>>();
    _pending[requestId] = completer;
    try {
      _process.stdin.writeln(
        jsonEncode(<String, Object?>{
          'type': type,
          'schemaVersion': '1.0.0',
          'requestId': requestId,
          ...payload,
        }),
      );
      await _process.stdin.flush();
    } catch (error) {
      _pending.remove(requestId);
      throw P3BrowserRuntimeException(
        'browser_session_request_write_failed',
        '$error',
      );
    }
    try {
      return await completer.future.timeout(launchPlan.requestTimeout);
    } on TimeoutException {
      _pending.remove(requestId);
      throw const P3BrowserRuntimeException(
        'browser_session_request_timeout',
      );
    }
  }

  Future<P3BrowserSessionInfo> openSession({
    P3BrowserSessionKind kind = P3BrowserSessionKind.ephemeral,
    String? profileId,
  }) async {
    if (kind == P3BrowserSessionKind.persistent &&
        (profileId == null || profileId.isEmpty)) {
      throw const P3BrowserRuntimeException(
        'browser_profile_id_required',
      );
    }
    if (kind == P3BrowserSessionKind.ephemeral && profileId != null) {
      throw const P3BrowserRuntimeException(
        'browser_ephemeral_profile_forbidden',
      );
    }
    final result = await _request('session.open', <String, Object?>{
      'kind': kind.wireName,
      if (profileId != null) 'profileId': profileId,
    });
    return P3BrowserSessionInfo.fromJson(result);
  }

  Future<List<P3BrowserSessionInfo>> listSessions() async {
    final result = await _request('session.list', const <String, Object?>{});
    final values = result['sessions'];
    if (values is! List) {
      throw const P3BrowserRuntimeException(
        'browser_session_response_invalid',
      );
    }
    return values.map((value) {
      if (value is! Map) {
        throw const P3BrowserRuntimeException(
          'browser_session_response_invalid',
        );
      }
      return P3BrowserSessionInfo.fromJson(
        Map<String, Object?>.from(value),
      );
    }).toList(growable: false);
  }

  Future<void> closeSession(String sessionId) async {
    await _request('session.close', <String, Object?>{
      'sessionId': sessionId,
    });
  }

  Future<P3BrowserPageInfo> openPage(String sessionId) async {
    final result = await _request('page.open', <String, Object?>{
      'sessionId': sessionId,
    });
    return P3BrowserPageInfo.fromJson(result);
  }

  Future<List<P3BrowserPageInfo>> listPages(String sessionId) async {
    final result = await _request('page.list', <String, Object?>{
      'sessionId': sessionId,
    });
    final values = result['pages'];
    if (values is! List) {
      throw const P3BrowserRuntimeException(
        'browser_page_response_invalid',
      );
    }
    return values.map((value) {
      if (value is! Map) {
        throw const P3BrowserRuntimeException(
          'browser_page_response_invalid',
        );
      }
      return P3BrowserPageInfo.fromJson(
        Map<String, Object?>.from(value),
      );
    }).toList(growable: false);
  }

  Future<void> closePage(String sessionId, String pageId) async {
    await _request('page.close', <String, Object?>{
      'sessionId': sessionId,
      'pageId': pageId,
    });
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _failProtocol(
      const P3BrowserRuntimeException('browser_session_service_closed'),
    );
    try {
      _process.stdin.writeln(
        jsonEncode(const <String, Object?>{
          'type': 'shutdown',
          'schemaVersion': '1.0.0',
        }),
      );
      await _process.stdin.flush();
    } catch (_) {
      // The process may already have exited; teardown remains fail-closed.
    }
    try {
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _process.kill();
      try {
        await _process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        throw const P3BrowserRuntimeException(
          'browser_session_worker_stop_timeout',
        );
      }
    } finally {
      if (_listenersStarted) {
        await _stdoutSubscription.cancel();
        await _stderrSubscription.cancel();
      }
      try {
        await _process.stdin.close();
      } catch (_) {
        // Ignore an already-closed pipe.
      }
    }
  }
}

/// Application-side P3 browser entry point.
///
/// P3-001 resolves and probes the pinned application-owned runtime. P3-002 adds
/// isolated ephemeral/persistent contexts and bounded page lifecycle over the
/// same exact bundled worker without a global Node or browser installation.
final class P3BrowserRuntimeService {
  P3BrowserRuntimeService({
    required Directory applicationDataRoot,
    String? executablePath,
  }) : _resolver = P3ApplicationOwnedBrowserRuntimeResolver(
          applicationDataRoot: applicationDataRoot,
          executablePath: executablePath,
        );

  P3BrowserRuntimeService.withResolver(this._resolver);

  final P3ApplicationOwnedBrowserRuntimeResolver _resolver;

  Future<P3BrowserRuntimeResourceSet> resolveBundle() => _resolver.resolve();

  Future<P3BrowserRuntimeProbeResult> probe({
    required Directory stateDirectory,
    Duration startupTimeout = const Duration(seconds: 30),
  }) async {
    final resources = await resolveBundle();
    final process = await P3BrowserRuntimeProcess.start(
      resources: resources,
      stateDirectory: stateDirectory,
      startupTimeout: startupTimeout,
    );
    try {
      return P3BrowserRuntimeProbeResult(
        ready: process.ready,
        bundleProvenance: resources.provenance,
      );
    } finally {
      await process.close();
    }
  }

  Future<P3BrowserSessionProcess> startSessions({
    required Directory stateDirectory,
    P3BrowserSessionQuotas quotas = const P3BrowserSessionQuotas(),
    Duration startupTimeout = const Duration(seconds: 30),
    Duration requestTimeout = const Duration(seconds: 10),
  }) async {
    final resources = await resolveBundle();
    return P3BrowserSessionProcess.start(
      resources: resources,
      stateDirectory: stateDirectory,
      quotas: quotas,
      startupTimeout: startupTimeout,
      requestTimeout: requestTimeout,
    );
  }
}
