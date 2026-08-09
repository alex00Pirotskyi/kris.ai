import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'browser_runtime_bundle.dart';

class P3BrowserRuntimeException implements Exception {
  const P3BrowserRuntimeException(this.code, [this.message = '']);

  final String code;
  final String message;

  @override
  String toString() => message.isEmpty
      ? 'P3BrowserRuntimeException($code)'
      : 'P3BrowserRuntimeException($code, $message)';
}

/// Exact process invocation derived only from an application-owned P3 bundle.
final class P3BrowserRuntimeLaunchPlan {
  const P3BrowserRuntimeLaunchPlan({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
    required this.startupTimeout,
  });

  factory P3BrowserRuntimeLaunchPlan.probe({
    required P3BrowserRuntimeResourceSet resources,
    required Directory stateDirectory,
    Duration startupTimeout = const Duration(seconds: 30),
  }) {
    if (!stateDirectory.isAbsolute) {
      throw const P3BrowserRuntimeException('state_directory_must_be_absolute');
    }
    if (startupTimeout <= Duration.zero ||
        startupTimeout > const Duration(minutes: 2)) {
      throw const P3BrowserRuntimeException('startup_timeout_invalid');
    }
    final plan = P3BrowserRuntimeLaunchPlan(
      executable: resources.nodeExecutable,
      arguments: <String>[
        resources.workerScript,
        '--mode',
        'probe',
        '--protocol',
        'stdio-json-v1',
        '--browser-executable',
        resources.browserExecutable,
        '--browser-root',
        resources.browserRoot,
        '--runtime-manifest',
        resources.manifestPath,
        '--state-directory',
        stateDirectory.absolute.path,
      ],
      workingDirectory: resources.workingDirectory,
      environment: <String, String>{
        'KRISTIN_P3_RUNTIME_MANIFEST_SHA256': resources.manifestSha256,
        'KRISTIN_P3_RUNTIME_BUILD_SHA256': resources.runtimeBuildSha256,
        'KRISTIN_P3_BROWSER_REVISION': resources.browserRevision,
      },
      startupTimeout: startupTimeout,
    );
    plan.validate();
    return plan;
  }

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
  final Duration startupTimeout;

  void validate() {
    if (!_isAbsolute(executable) || !File(executable).existsSync()) {
      throw const P3BrowserRuntimeException('bundled_node_executable_required');
    }
    if (!_isAbsolute(workingDirectory) ||
        !Directory(workingDirectory).existsSync()) {
      throw const P3BrowserRuntimeException('browser_runtime_cwd_required');
    }
    if (arguments.length < 12 ||
        !_isAbsolute(arguments.first) ||
        !File(arguments.first).existsSync()) {
      throw const P3BrowserRuntimeException('browser_worker_script_required');
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
      throw const P3BrowserRuntimeException('browser_state_directory_required');
    }
    if (_argumentValue('--mode') != 'probe' ||
        _argumentValue('--protocol') != 'stdio-json-v1') {
      throw const P3BrowserRuntimeException('browser_probe_protocol_invalid');
    }
    if (environment.keys.toSet().difference(<String>{
          'KRISTIN_P3_RUNTIME_MANIFEST_SHA256',
          'KRISTIN_P3_RUNTIME_BUILD_SHA256',
          'KRISTIN_P3_BROWSER_REVISION',
        }).isNotEmpty ||
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
      throw P3BrowserRuntimeException('browser_runtime_argument_missing', name);
    }
    return arguments[index + 1];
  }

  static bool _isAbsolute(String value) {
    if (Platform.isWindows) {
      return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
          value.startsWith(r'\\');
    }
    return value.startsWith('/');
  }
}

final class P3BrowserRuntimeReady {
  const P3BrowserRuntimeReady({
    required this.pid,
    required this.browserPid,
    required this.browserEngine,
    required this.browserVersion,
    required this.browserRevision,
    required this.browserExecutableSha256,
    required this.protocol,
  });

  factory P3BrowserRuntimeReady.fromJson(
    Map<String, Object?> value, {
    required P3BrowserRuntimeResourceSet resources,
  }) {
    final pid = value['pid'];
    final browserPid = value['browserPid'];
    final engine = value['browserEngine']?.toString() ?? '';
    final version = value['browserVersion']?.toString() ?? '';
    final revision = value['browserRevision']?.toString() ?? '';
    final executableSha =
        value['browserExecutableSha256']?.toString().toLowerCase() ?? '';
    final protocol = value['protocol']?.toString() ?? '';
    if (value['type'] != 'ready' ||
        value['schemaVersion'] != '1.0.0' ||
        pid is! int ||
        pid <= 0 ||
        browserPid is! int ||
        browserPid <= 0 ||
        engine != resources.browserEngine ||
        revision != resources.browserRevision ||
        executableSha != resources.browserExecutableSha256 ||
        version.isEmpty ||
        protocol != 'stdio-json-v1') {
      throw const P3BrowserRuntimeException('browser_worker_ready_invalid');
    }
    return P3BrowserRuntimeReady(
      pid: pid,
      browserPid: browserPid,
      browserEngine: engine,
      browserVersion: version,
      browserRevision: revision,
      browserExecutableSha256: executableSha,
      protocol: protocol,
    );
  }

  final int pid;
  final int browserPid;
  final String browserEngine;
  final String browserVersion;
  final String browserRevision;
  final String browserExecutableSha256;
  final String protocol;
}

/// Supervised P3-001 probe process. Browser sessions/actions remain P3-002+.
final class P3BrowserRuntimeProcess {
  P3BrowserRuntimeProcess._(this._process, this.resources, this.launchPlan);

  static Future<P3BrowserRuntimeProcess> start({
    required P3BrowserRuntimeResourceSet resources,
    required Directory stateDirectory,
    Duration startupTimeout = const Duration(seconds: 30),
  }) async {
    await stateDirectory.create(recursive: true);
    final launchPlan = P3BrowserRuntimeLaunchPlan.probe(
      resources: resources,
      stateDirectory: stateDirectory.absolute,
      startupTimeout: startupTimeout,
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
    final runtime = P3BrowserRuntimeProcess._(process, resources, launchPlan);
    try {
      await runtime._awaitReady();
      return runtime;
    } catch (_) {
      await runtime.close();
      rethrow;
    }
  }

  final Process _process;
  final P3BrowserRuntimeResourceSet resources;
  final P3BrowserRuntimeLaunchPlan launchPlan;
  final Completer<P3BrowserRuntimeReady> _ready =
      Completer<P3BrowserRuntimeReady>();
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<List<int>> _stderrSubscription;
  int _stderrBytes = 0;
  bool _listenersStarted = false;
  bool _closing = false;

  P3BrowserRuntimeReady get ready {
    if (!_ready.isCompleted || _readyValue == null) {
      throw const P3BrowserRuntimeException('browser_worker_not_ready');
    }
    return _readyValue!;
  }

  P3BrowserRuntimeReady? _readyValue;
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
        _completeReadyError(
          const P3BrowserRuntimeException('browser_worker_stderr_flood'),
        );
        _process.kill();
      }
    });
    unawaited(
      _process.exitCode.then((code) {
        if (!_closing && !_ready.isCompleted) {
          _completeReadyError(
            P3BrowserRuntimeException(
              'browser_worker_exited_before_ready',
              '$code',
            ),
          );
        }
      }),
    );
    try {
      _readyValue = await _ready.future.timeout(launchPlan.startupTimeout);
    } on TimeoutException {
      throw const P3BrowserRuntimeException('browser_worker_start_timeout');
    }
  }

  void _handleLine(String line) {
    if (_ready.isCompleted || line.length > 1024 * 1024) return;
    try {
      final value = jsonDecode(line);
      if (value is! Map) return;
      final mapped = Map<String, Object?>.from(value);
      if (mapped['type'] != 'ready') return;
      _ready.complete(
        P3BrowserRuntimeReady.fromJson(mapped, resources: resources),
      );
    } catch (error) {
      _completeReadyError(
        P3BrowserRuntimeException(
          'browser_worker_ready_decode_failed',
          '$error',
        ),
      );
    }
  }

  void _handleTransportError(Object error) {
    _completeReadyError(
      P3BrowserRuntimeException('browser_worker_transport_error', '$error'),
    );
  }

  void _completeReadyError(Object error) {
    if (!_ready.isCompleted) _ready.completeError(error);
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    try {
      _process.stdin.writeln(
        jsonEncode(<String, Object?>{
          'type': 'shutdown',
          'schemaVersion': '1.0.0',
        }),
      );
      await _process.stdin.flush();
    } catch (_) {
      // The process may already have exited; teardown remains best-effort.
    }
    try {
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _process.kill();
      try {
        await _process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        throw const P3BrowserRuntimeException('browser_worker_stop_timeout');
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
