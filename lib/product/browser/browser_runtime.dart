import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../crypto_utils.dart';
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

Object? _canonicalBrowserObservationValue(Object? value) {
  if (value == null || value is String || value is bool) return value;
  if (value is num && value.isFinite) return value;
  if (value is List) {
    return value
        .map<Object?>((item) => _canonicalBrowserObservationValue(item))
        .toList(growable: false);
  }
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys)
        key: _canonicalBrowserObservationValue(value[key]),
    };
  }
  throw const P3BrowserRuntimeException(
    'browser_observation_value_invalid',
  );
}

String _canonicalBrowserObservationJson(Map<String, Object?> value) =>
    jsonEncode(_canonicalBrowserObservationValue(value));

final class P3BrowserPageObservation {
  P3BrowserPageObservation._({
    required this.sessionId,
    required this.pageId,
    required this.observationHash,
    required Map<String, Object?> observation,
  }) : observation = Map<String, Object?>.unmodifiable(observation);

  factory P3BrowserPageObservation.fromJson(Map<String, Object?> value) {
    final sessionId = value['sessionId'];
    final pageId = value['pageId'];
    final observationHash = value['observationHash'];
    final rawObservation = value['observation'];
    if (sessionId is! String ||
        sessionId.isEmpty ||
        pageId is! String ||
        pageId.isEmpty ||
        observationHash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(observationHash) ||
        rawObservation is! Map) {
      throw const P3BrowserRuntimeException(
        'browser_observation_response_invalid',
      );
    }
    final observation = Map<String, Object?>.from(rawObservation);
    if (observation['schemaVersion'] != '1.0.0' ||
        observation['url'] is! String ||
        observation['title'] is! String ||
        observation['forms'] is! List ||
        observation['console'] is! Map ||
        observation['network'] is! Map) {
      throw const P3BrowserRuntimeException(
        'browser_observation_response_invalid',
      );
    }
    for (final key in const <String>[
      'dom',
      'visibleText',
      'accessibility',
    ]) {
      final field = observation[key];
      if (field is! Map) {
        throw const P3BrowserRuntimeException(
          'browser_observation_response_invalid',
        );
      }
      final mapped = Map<String, Object?>.from(field);
      if (mapped['text'] is! String ||
          mapped['bytes'] is! int ||
          mapped['truncated'] is! bool) {
        throw const P3BrowserRuntimeException(
          'browser_observation_response_invalid',
        );
      }
    }
    final screenshotValue = observation['screenshot'];
    if (screenshotValue is! Map) {
      throw const P3BrowserRuntimeException(
        'browser_observation_response_invalid',
      );
    }
    final screenshot = Map<String, Object?>.from(screenshotValue);
    final screenshotBytes = screenshot['bytes'];
    final screenshotSha = screenshot['sha256'];
    final screenshotBase64 = screenshot['base64'];
    if (screenshotBytes is! int ||
        screenshotBytes < 0 ||
        screenshotBytes > 256 * 1024 ||
        screenshotSha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(screenshotSha) ||
        screenshotBase64 is! String ||
        screenshot['mediaType'] != 'image/jpeg') {
      throw const P3BrowserRuntimeException(
        'browser_observation_response_invalid',
      );
    }
    late final List<int> decodedScreenshot;
    try {
      decodedScreenshot = base64Decode(screenshotBase64);
    } on FormatException {
      throw const P3BrowserRuntimeException(
        'browser_observation_response_invalid',
      );
    }
    if (decodedScreenshot.length != screenshotBytes ||
        Sha256.hex(decodedScreenshot) != screenshotSha) {
      throw const P3BrowserRuntimeException(
        'browser_observation_screenshot_binding_invalid',
      );
    }
    final canonical = _canonicalBrowserObservationJson(observation);
    if (utf8.encode(canonical).length > 900 * 1024 ||
        Sha256.text(canonical) != observationHash) {
      throw const P3BrowserRuntimeException(
        'browser_observation_hash_invalid',
      );
    }
    return P3BrowserPageObservation._(
      sessionId: sessionId,
      pageId: pageId,
      observationHash: observationHash,
      observation: observation,
    );
  }

  final String sessionId;
  final String pageId;
  final String observationHash;
  final Map<String, Object?> observation;
}

enum P3BrowserActionKind {
  click,
  fill,
  type,
  select,
  check,
  uncheck,
  press,
  hover,
  drag,
  wait,
  scroll;

  String get wireName => name;
}

final class P3BrowserLocator {
  const P3BrowserLocator._(this.value);

  factory P3BrowserLocator.role(
    String role,
    String name, {
    bool exact = false,
  }) =>
      P3BrowserLocator._(<String, Object?>{
        'strategy': 'role',
        'role': role,
        'name': name,
        'exact': exact,
      });

  factory P3BrowserLocator.label(String value, {bool exact = false}) =>
      P3BrowserLocator._(<String, Object?>{
        'strategy': 'label',
        'value': value,
        'exact': exact,
      });

  factory P3BrowserLocator.placeholder(
    String value, {
    bool exact = false,
  }) =>
      P3BrowserLocator._(<String, Object?>{
        'strategy': 'placeholder',
        'value': value,
        'exact': exact,
      });

  factory P3BrowserLocator.text(String value, {bool exact = false}) =>
      P3BrowserLocator._(<String, Object?>{
        'strategy': 'text',
        'value': value,
        'exact': exact,
      });

  factory P3BrowserLocator.testId(String value) =>
      P3BrowserLocator._(<String, Object?>{
        'strategy': 'testId',
        'value': value,
      });

  factory P3BrowserLocator.css(String value) =>
      P3BrowserLocator._(<String, Object?>{
        'strategy': 'css',
        'value': value,
      });

  final Map<String, Object?> value;

  Map<String, Object?> toJson() => Map<String, Object?>.from(value);
}

final class P3BrowserActionRequest {
  const P3BrowserActionRequest({
    required this.action,
    required this.locators,
    this.targetLocators = const <P3BrowserLocator>[],
    this.value,
    this.options = const <String>[],
    this.key,
    this.state,
    this.deltaY,
    this.timeout = const Duration(seconds: 10),
  });

  final P3BrowserActionKind action;
  final List<P3BrowserLocator> locators;
  final List<P3BrowserLocator> targetLocators;
  final String? value;
  final List<String> options;
  final String? key;
  final String? state;
  final int? deltaY;
  final Duration timeout;

  Map<String, Object?> toJson() {
    if (locators.isEmpty || locators.length > 8) {
      throw const P3BrowserRuntimeException(
        'browser_locator_list_invalid',
      );
    }
    if (timeout < const Duration(milliseconds: 100) ||
        timeout > const Duration(seconds: 30)) {
      throw const P3BrowserRuntimeException(
        'browser_action_timeout_invalid',
      );
    }
    final requiresValue = action == P3BrowserActionKind.fill ||
        action == P3BrowserActionKind.type;
    if (requiresValue != (value != null && value!.isNotEmpty)) {
      throw const P3BrowserRuntimeException(
        'browser_action_value_invalid',
      );
    }
    if ((action == P3BrowserActionKind.select) != options.isNotEmpty) {
      throw const P3BrowserRuntimeException(
        'browser_action_options_invalid',
      );
    }
    if ((action == P3BrowserActionKind.press) !=
        (key != null && key!.isNotEmpty)) {
      throw const P3BrowserRuntimeException(
        'browser_action_key_invalid',
      );
    }
    if ((action == P3BrowserActionKind.drag) != targetLocators.isNotEmpty) {
      throw const P3BrowserRuntimeException(
        'browser_action_target_locator_invalid',
      );
    }
    if ((action == P3BrowserActionKind.scroll) !=
        (deltaY != null && deltaY != 0)) {
      throw const P3BrowserRuntimeException(
        'browser_action_scroll_delta_invalid',
      );
    }
    return <String, Object?>{
      'action': action.wireName,
      'locators':
          locators.map((locator) => locator.toJson()).toList(growable: false),
      if (targetLocators.isNotEmpty)
        'targetLocators': targetLocators
            .map((locator) => locator.toJson())
            .toList(growable: false),
      if (value != null) 'value': value,
      if (options.isNotEmpty) 'options': options,
      if (key != null) 'key': key,
      if (state != null) 'state': state,
      if (deltaY != null) 'deltaY': deltaY,
      'timeoutMs': timeout.inMilliseconds,
    };
  }
}

final class P3BrowserActionResult {
  const P3BrowserActionResult({
    required this.sessionId,
    required this.pageId,
    required this.action,
    required this.locatorStrategy,
    required this.locatorIndex,
    required this.targetLocatorStrategy,
    required this.targetLocatorIndex,
    required this.sensitiveInputProvided,
    required this.beforeObservationHash,
    required this.afterObservationHash,
    required this.observationChanged,
  });

  factory P3BrowserActionResult.fromJson(Map<String, Object?> value) {
    final sessionId = value['sessionId'];
    final pageId = value['pageId'];
    final actionName = value['action'];
    final locatorStrategy = value['locatorStrategy'];
    final locatorIndex = value['locatorIndex'];
    final targetLocatorStrategy = value['targetLocatorStrategy'];
    final targetLocatorIndex = value['targetLocatorIndex'];
    final sensitive = value['sensitiveInputProvided'];
    final beforeHash = value['beforeObservationHash'];
    final afterHash = value['afterObservationHash'];
    final changed = value['observationChanged'];
    final action = P3BrowserActionKind.values
        .where((candidate) => candidate.wireName == actionName)
        .firstOrNull;
    final hex = RegExp(r'^[0-9a-f]{64}$');
    if (sessionId is! String ||
        sessionId.isEmpty ||
        pageId is! String ||
        pageId.isEmpty ||
        action == null ||
        locatorStrategy is! String ||
        locatorStrategy.isEmpty ||
        locatorIndex is! int ||
        locatorIndex < 0 ||
        (targetLocatorStrategy != null && targetLocatorStrategy is! String) ||
        (targetLocatorIndex != null && targetLocatorIndex is! int) ||
        sensitive is! bool ||
        beforeHash is! String ||
        !hex.hasMatch(beforeHash) ||
        afterHash is! String ||
        !hex.hasMatch(afterHash) ||
        changed is! bool ||
        changed != (beforeHash != afterHash)) {
      throw const P3BrowserRuntimeException(
        'browser_action_response_invalid',
      );
    }
    if ((action == P3BrowserActionKind.drag) !=
        (targetLocatorStrategy is String &&
            targetLocatorStrategy.isNotEmpty &&
            targetLocatorIndex is int &&
            targetLocatorIndex >= 0)) {
      throw const P3BrowserRuntimeException(
        'browser_action_response_invalid',
      );
    }
    return P3BrowserActionResult(
      sessionId: sessionId,
      pageId: pageId,
      action: action,
      locatorStrategy: locatorStrategy,
      locatorIndex: locatorIndex,
      targetLocatorStrategy: targetLocatorStrategy as String?,
      targetLocatorIndex: targetLocatorIndex as int?,
      sensitiveInputProvided: sensitive,
      beforeObservationHash: beforeHash,
      afterObservationHash: afterHash,
      observationChanged: changed,
    );
  }

  final String sessionId;
  final String pageId;
  final P3BrowserActionKind action;
  final String locatorStrategy;
  final int locatorIndex;
  final String? targetLocatorStrategy;
  final int? targetLocatorIndex;
  final bool sensitiveInputProvided;
  final String beforeObservationHash;
  final String afterObservationHash;
  final bool observationChanged;
}

final class P3BrowserVisualSource {
  const P3BrowserVisualSource({
    required this.observationHash,
    required this.screenshotSha256,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  final String observationHash;
  final String screenshotSha256;
  final int viewportWidth;
  final int viewportHeight;

  Map<String, Object?> toJson() {
    final hex = RegExp(r'^[0-9a-f]{64}$');
    if (!hex.hasMatch(observationHash) ||
        !hex.hasMatch(screenshotSha256) ||
        viewportWidth < 1 ||
        viewportWidth > 32768 ||
        viewportHeight < 1 ||
        viewportHeight > 32768) {
      throw const P3BrowserRuntimeException(
        'browser_visual_source_invalid',
      );
    }
    return <String, Object?>{
      'observationHash': observationHash,
      'screenshotSha256': screenshotSha256,
      'viewportWidth': viewportWidth,
      'viewportHeight': viewportHeight,
    };
  }
}

final class P3BrowserVisualTarget {
  const P3BrowserVisualTarget({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
    required this.description,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double confidence;
  final String description;

  Map<String, Object?> toJson() {
    if (!x.isFinite ||
        !y.isFinite ||
        !width.isFinite ||
        !height.isFinite ||
        !confidence.isFinite ||
        x < 0 ||
        y < 0 ||
        width <= 0 ||
        height <= 0 ||
        x > 100000 ||
        y > 100000 ||
        width > 100000 ||
        height > 100000 ||
        confidence < 0 ||
        confidence > 1 ||
        description.isEmpty ||
        description.contains('\u0000') ||
        utf8.encode(description).length > 4096) {
      throw const P3BrowserRuntimeException(
        'browser_visual_target_invalid',
      );
    }
    return <String, Object?>{
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'confidence': confidence,
      'description': description,
    };
  }
}

final class P3BrowserVisualVerification {
  const P3BrowserVisualVerification({
    this.requireObservationChange = true,
    this.expectedUrl,
    this.expectedUrlPrefix,
  });

  final bool requireObservationChange;
  final String? expectedUrl;
  final String? expectedUrlPrefix;

  Map<String, Object?> toJson() {
    if (expectedUrl != null && expectedUrlPrefix != null) {
      throw const P3BrowserRuntimeException(
        'browser_visual_verification_invalid',
      );
    }
    if ((expectedUrl != null && expectedUrl!.isEmpty) ||
        (expectedUrlPrefix != null && expectedUrlPrefix!.isEmpty) ||
        (!requireObservationChange &&
            expectedUrl == null &&
            expectedUrlPrefix == null)) {
      throw const P3BrowserRuntimeException(
        'browser_visual_verification_required',
      );
    }
    return <String, Object?>{
      'requireObservationChange': requireObservationChange,
      if (expectedUrl != null) 'expectedUrl': expectedUrl,
      if (expectedUrlPrefix != null) 'expectedUrlPrefix': expectedUrlPrefix,
    };
  }
}

final class P3BrowserVisualActionRequest {
  const P3BrowserVisualActionRequest({
    required this.action,
    required this.locators,
    required this.visualSource,
    required this.visualTarget,
    this.targetLocators = const <P3BrowserLocator>[],
    this.visualDragTarget,
    this.minimumConfidence = 0.9,
    this.verification = const P3BrowserVisualVerification(),
    this.timeout = const Duration(seconds: 10),
  });

  final P3BrowserActionKind action;
  final List<P3BrowserLocator> locators;
  final List<P3BrowserLocator> targetLocators;
  final P3BrowserVisualSource visualSource;
  final P3BrowserVisualTarget visualTarget;
  final P3BrowserVisualTarget? visualDragTarget;
  final double minimumConfidence;
  final P3BrowserVisualVerification verification;
  final Duration timeout;

  Map<String, Object?> toJson() {
    if (action != P3BrowserActionKind.click &&
        action != P3BrowserActionKind.drag) {
      throw const P3BrowserRuntimeException(
        'browser_visual_action_kind_invalid',
      );
    }
    if (locators.isEmpty || locators.length > 8) {
      throw const P3BrowserRuntimeException(
        'browser_locator_list_invalid',
      );
    }
    if (timeout < const Duration(milliseconds: 100) ||
        timeout > const Duration(seconds: 30)) {
      throw const P3BrowserRuntimeException(
        'browser_action_timeout_invalid',
      );
    }
    if (!minimumConfidence.isFinite ||
        minimumConfidence < 0.9 ||
        minimumConfidence > 1) {
      throw const P3BrowserRuntimeException(
        'browser_visual_confidence_invalid',
      );
    }
    final drag = action == P3BrowserActionKind.drag;
    if (drag != targetLocators.isNotEmpty ||
        drag != (visualDragTarget != null) ||
        targetLocators.length > 8) {
      throw const P3BrowserRuntimeException(
        'browser_action_target_locator_invalid',
      );
    }
    return <String, Object?>{
      'action': action.wireName,
      'locators':
          locators.map((locator) => locator.toJson()).toList(growable: false),
      if (targetLocators.isNotEmpty)
        'targetLocators': targetLocators
            .map((locator) => locator.toJson())
            .toList(growable: false),
      'visualSource': visualSource.toJson(),
      'visualTarget': visualTarget.toJson(),
      if (visualDragTarget != null)
        'visualDragTarget': visualDragTarget!.toJson(),
      'minimumConfidence': minimumConfidence,
      'verification': verification.toJson(),
      'timeoutMs': timeout.inMilliseconds,
    };
  }
}

enum P3BrowserVisualActionDisposition {
  executed('executed'),
  userTakeoverRequired('user_takeover_required');

  const P3BrowserVisualActionDisposition(this.wireName);

  final String wireName;
}

enum P3BrowserVisualExecutionMode {
  structured('structured'),
  visual('visual');

  const P3BrowserVisualExecutionMode(this.wireName);

  final String wireName;
}

final class P3BrowserVisualActionResult {
  const P3BrowserVisualActionResult({
    required this.sessionId,
    required this.pageId,
    required this.action,
    required this.disposition,
    required this.executionMode,
    required this.locatorStrategy,
    required this.locatorIndex,
    required this.targetLocatorStrategy,
    required this.targetLocatorIndex,
    required this.structuredFailureCode,
    required this.minimumConfidence,
    required this.visualConfidence,
    required this.visualDestinationConfidence,
    required this.beforeObservationHash,
    required this.beforeScreenshotSha256,
    required this.afterObservationHash,
    required this.afterScreenshotSha256,
    required this.observationChanged,
    required this.verified,
    required this.pauseReason,
  });

  factory P3BrowserVisualActionResult.fromJson(
    Map<String, Object?> value,
  ) {
    final sessionId = value['sessionId'];
    final pageId = value['pageId'];
    final actionName = value['action'];
    final dispositionName = value['disposition'];
    final executionModeName = value['executionMode'];
    final locatorStrategy = value['locatorStrategy'];
    final locatorIndex = value['locatorIndex'];
    final targetLocatorStrategy = value['targetLocatorStrategy'];
    final targetLocatorIndex = value['targetLocatorIndex'];
    final structuredFailureCode = value['structuredFailureCode'];
    final minimumConfidence = value['minimumConfidence'];
    final visualConfidence = value['visualConfidence'];
    final visualDestinationConfidence = value['visualDestinationConfidence'];
    final beforeObservationHash = value['beforeObservationHash'];
    final beforeScreenshotSha256 = value['beforeScreenshotSha256'];
    final afterObservationHash = value['afterObservationHash'];
    final afterScreenshotSha256 = value['afterScreenshotSha256'];
    final observationChanged = value['observationChanged'];
    final verified = value['verified'];
    final pauseReason = value['pauseReason'];
    final action = P3BrowserActionKind.values
        .where((candidate) => candidate.wireName == actionName)
        .firstOrNull;
    final disposition = P3BrowserVisualActionDisposition.values
        .where((candidate) => candidate.wireName == dispositionName)
        .firstOrNull;
    final executionMode = P3BrowserVisualExecutionMode.values
        .where((candidate) => candidate.wireName == executionModeName)
        .firstOrNull;
    final hex = RegExp(r'^[0-9a-f]{64}$');
    if ((locatorStrategy != null && locatorStrategy is! String) ||
        (locatorIndex != null && locatorIndex is! int) ||
        (targetLocatorStrategy != null && targetLocatorStrategy is! String) ||
        (targetLocatorIndex != null && targetLocatorIndex is! int) ||
        (structuredFailureCode != null && structuredFailureCode is! String) ||
        (visualConfidence != null && visualConfidence is! num) ||
        (visualDestinationConfidence != null &&
            visualDestinationConfidence is! num) ||
        (afterObservationHash != null && afterObservationHash is! String) ||
        (afterScreenshotSha256 != null && afterScreenshotSha256 is! String) ||
        (pauseReason != null && pauseReason is! String)) {
      throw const P3BrowserRuntimeException(
        'browser_visual_action_response_invalid',
      );
    }
    if (sessionId is! String ||
        sessionId.isEmpty ||
        pageId is! String ||
        pageId.isEmpty ||
        (action != P3BrowserActionKind.click &&
            action != P3BrowserActionKind.drag) ||
        disposition == null ||
        executionMode == null ||
        minimumConfidence is! num ||
        !minimumConfidence.isFinite ||
        minimumConfidence < 0.9 ||
        minimumConfidence > 1 ||
        beforeObservationHash is! String ||
        !hex.hasMatch(beforeObservationHash) ||
        beforeScreenshotSha256 is! String ||
        !hex.hasMatch(beforeScreenshotSha256) ||
        observationChanged is! bool ||
        verified is! bool) {
      throw const P3BrowserRuntimeException(
        'browser_visual_action_response_invalid',
      );
    }

    final structured = executionMode == P3BrowserVisualExecutionMode.structured;
    if (structured !=
            (locatorStrategy is String &&
                locatorStrategy.isNotEmpty &&
                locatorIndex is int &&
                locatorIndex >= 0) ||
        (structured &&
            (structuredFailureCode != null ||
                visualConfidence != null ||
                visualDestinationConfidence != null)) ||
        (!structured &&
            structuredFailureCode != 'browser_locator_not_found' &&
            structuredFailureCode != 'browser_locator_ambiguous')) {
      throw const P3BrowserRuntimeException(
        'browser_visual_action_response_invalid',
      );
    }
    final drag = action == P3BrowserActionKind.drag;
    if ((structured && drag) !=
            (targetLocatorStrategy is String &&
                targetLocatorStrategy.isNotEmpty &&
                targetLocatorIndex is int &&
                targetLocatorIndex >= 0) ||
        (!structured &&
            (visualConfidence is! num ||
                !visualConfidence.isFinite ||
                visualConfidence < 0 ||
                visualConfidence > 1)) ||
        (!structured &&
            drag !=
                (visualDestinationConfidence is num &&
                    visualDestinationConfidence.isFinite &&
                    visualDestinationConfidence >= 0 &&
                    visualDestinationConfidence <= 1))) {
      throw const P3BrowserRuntimeException(
        'browser_visual_action_response_invalid',
      );
    }

    final executed = disposition == P3BrowserVisualActionDisposition.executed;
    if (executed) {
      if (afterObservationHash is! String ||
          !hex.hasMatch(afterObservationHash) ||
          afterScreenshotSha256 is! String ||
          !hex.hasMatch(afterScreenshotSha256) ||
          observationChanged !=
              (beforeObservationHash != afterObservationHash) ||
          verified != true ||
          pauseReason != null) {
        throw const P3BrowserRuntimeException(
          'browser_visual_action_response_invalid',
        );
      }
    } else if (executionMode != P3BrowserVisualExecutionMode.visual ||
        afterObservationHash != null ||
        afterScreenshotSha256 != null ||
        observationChanged != false ||
        verified != false ||
        pauseReason != 'browser_visual_target_low_confidence') {
      throw const P3BrowserRuntimeException(
        'browser_visual_action_response_invalid',
      );
    }

    return P3BrowserVisualActionResult(
      sessionId: sessionId,
      pageId: pageId,
      action: action!,
      disposition: disposition,
      executionMode: executionMode,
      locatorStrategy: locatorStrategy as String?,
      locatorIndex: locatorIndex as int?,
      targetLocatorStrategy: targetLocatorStrategy as String?,
      targetLocatorIndex: targetLocatorIndex as int?,
      structuredFailureCode: structuredFailureCode as String?,
      minimumConfidence: (minimumConfidence).toDouble(),
      visualConfidence: (visualConfidence as num?)?.toDouble(),
      visualDestinationConfidence:
          (visualDestinationConfidence as num?)?.toDouble(),
      beforeObservationHash: beforeObservationHash,
      beforeScreenshotSha256: beforeScreenshotSha256,
      afterObservationHash: afterObservationHash as String?,
      afterScreenshotSha256: afterScreenshotSha256 as String?,
      observationChanged: observationChanged,
      verified: verified,
      pauseReason: pauseReason as String?,
    );
  }

  final String sessionId;
  final String pageId;
  final P3BrowserActionKind action;
  final P3BrowserVisualActionDisposition disposition;
  final P3BrowserVisualExecutionMode executionMode;
  final String? locatorStrategy;
  final int? locatorIndex;
  final String? targetLocatorStrategy;
  final int? targetLocatorIndex;
  final String? structuredFailureCode;
  final double minimumConfidence;
  final double? visualConfidence;
  final double? visualDestinationConfidence;
  final String beforeObservationHash;
  final String beforeScreenshotSha256;
  final String? afterObservationHash;
  final String? afterScreenshotSha256;
  final bool observationChanged;
  final bool verified;
  final String? pauseReason;
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
  Object? _terminalError;
  Future<void>? _closeFuture;

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
      unawaited(close());
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
      throw const FormatException('response request id unmatched');
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
    unawaited(close());
  }

  void _failProtocol(Object error) {
    _terminalError ??= error;
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
    final terminalError = _terminalError;
    if (terminalError != null) throw terminalError;
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
      const error = P3BrowserRuntimeException(
        'browser_session_request_timeout',
      );
      _failProtocol(error);
      unawaited(close());
      throw error;
    }
  }

  T _decodeResponse<T>(T Function() decode) {
    try {
      return decode();
    } catch (error, stackTrace) {
      _failProtocol(error);
      unawaited(close());
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Never _protocolViolation(String code, [String detail = '']) {
    final error = P3BrowserRuntimeException(code, detail);
    _failProtocol(error);
    unawaited(close());
    throw error;
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
    final info = _decodeResponse(() => P3BrowserSessionInfo.fromJson(result));
    if (info.kind != kind ||
        info.profileId != profileId ||
        info.pageCount != 0) {
      _protocolViolation('browser_session_response_identity_mismatch');
    }
    return info;
  }

  Future<List<P3BrowserSessionInfo>> listSessions() async {
    final result = await _request('session.list', const <String, Object?>{});
    final values = result['sessions'];
    if (values is! List) {
      throw const P3BrowserRuntimeException(
        'browser_session_response_invalid',
      );
    }
    final sessions = _decodeResponse(() => values.map((value) {
          if (value is! Map) {
            throw const P3BrowserRuntimeException(
              'browser_session_response_invalid',
            );
          }
          return P3BrowserSessionInfo.fromJson(
            Map<String, Object?>.from(value),
          );
        }).toList(growable: false));
    if (sessions.map((session) => session.sessionId).toSet().length !=
            sessions.length ||
        sessions.any(
          (session) => session.pageCount > launchPlan.quotas.maxPagesPerSession,
        )) {
      _protocolViolation('browser_session_response_identity_mismatch');
    }
    return sessions;
  }

  Future<void> closeSession(String sessionId) async {
    final result = await _request('session.close', <String, Object?>{
      'sessionId': sessionId,
    });
    if (result['sessionId'] != sessionId || result['closed'] != true) {
      _protocolViolation('browser_session_response_identity_mismatch');
    }
  }

  Future<P3BrowserPageInfo> openPage(String sessionId) async {
    final result = await _request('page.open', <String, Object?>{
      'sessionId': sessionId,
    });
    final page = _decodeResponse(() => P3BrowserPageInfo.fromJson(result));
    if (page.sessionId != sessionId) {
      _protocolViolation('browser_page_response_identity_mismatch');
    }
    return page;
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
    final pages = _decodeResponse(() => values.map((value) {
          if (value is! Map) {
            throw const P3BrowserRuntimeException(
              'browser_page_response_invalid',
            );
          }
          return P3BrowserPageInfo.fromJson(
            Map<String, Object?>.from(value),
          );
        }).toList(growable: false));
    if (pages.any((page) => page.sessionId != sessionId) ||
        pages.map((page) => page.pageId).toSet().length != pages.length) {
      _protocolViolation('browser_page_response_identity_mismatch');
    }
    return pages;
  }

  Future<P3BrowserPageObservation> observePage(
    String sessionId,
    String pageId,
  ) async {
    final result = await _request('page.observe', <String, Object?>{
      'sessionId': sessionId,
      'pageId': pageId,
    });
    final observation = _decodeResponse(
      () => P3BrowserPageObservation.fromJson(result),
    );
    if (observation.sessionId != sessionId || observation.pageId != pageId) {
      _protocolViolation('browser_observation_identity_mismatch');
    }
    return observation;
  }

  Future<P3BrowserActionResult> performAction(
    String sessionId,
    String pageId,
    P3BrowserActionRequest action,
  ) async {
    final result = await _request('page.action', <String, Object?>{
      'sessionId': sessionId,
      'pageId': pageId,
      'actionRequest': action.toJson(),
    });
    final parsed = _decodeResponse(
      () => P3BrowserActionResult.fromJson(result),
    );
    if (parsed.sessionId != sessionId || parsed.pageId != pageId) {
      _protocolViolation('browser_action_identity_mismatch');
    }
    return parsed;
  }

  Future<P3BrowserVisualActionResult> performVerifiedVisualAction(
    String sessionId,
    String pageId,
    P3BrowserVisualActionRequest action,
  ) async {
    final result = await _request('page.visualAction', <String, Object?>{
      'sessionId': sessionId,
      'pageId': pageId,
      'visualActionRequest': action.toJson(),
    });
    final parsed = _decodeResponse(
      () => P3BrowserVisualActionResult.fromJson(result),
    );
    if (parsed.sessionId != sessionId || parsed.pageId != pageId) {
      _protocolViolation('browser_visual_action_identity_mismatch');
    }
    return parsed;
  }

  Future<void> closePage(String sessionId, String pageId) async {
    final result = await _request('page.close', <String, Object?>{
      'sessionId': sessionId,
      'pageId': pageId,
    });
    if (result['sessionId'] != sessionId ||
        result['pageId'] != pageId ||
        result['closed'] != true) {
      _protocolViolation('browser_page_response_identity_mismatch');
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
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
