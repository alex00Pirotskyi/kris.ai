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

const int _p3HardMaxDownloadBytes = 128 * 1024 * 1024;
const String _p3DownloadReceiptType = 'kristin-p3-browser-download-receipt-v1';
const Set<String> _p3DownloadLocatorStrategies = <String>{
  'role',
  'label',
  'placeholder',
  'text',
  'testId',
  'css',
};
final RegExp _p3GeneratedId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
final RegExp _p3ProfileId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');
final RegExp _p3DownloadId = RegExp(r'^download_[A-Za-z0-9_-]{1,119}$');
final RegExp _p3Sha256 = RegExp(r'^[0-9a-f]{64}$');

void _requireExactBrowserKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String code,
) {
  if (value.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(value.keys.toSet()).isNotEmpty) {
    throw P3BrowserRuntimeException(code);
  }
}

String _boundedBrowserDownloadFilename(String raw) {
  var value = raw.split(RegExp(r'[\\/]')).last;
  value = value
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f<>:"|?*]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (value.isEmpty || value == '.' || value == '..') value = 'download';
  final result = StringBuffer();
  var bytes = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final characterBytes = utf8.encode(character).length;
    if (bytes + characterBytes > 255) break;
    result.write(character);
    bytes += characterBytes;
  }
  final bounded = result.toString();
  return bounded.isEmpty ? 'download' : bounded;
}

String _canonicalBrowserIsoTimestamp(DateTime value) {
  final utc = value.toUtc();
  String two(int part) => part.toString().padLeft(2, '0');
  String three(int part) => part.toString().padLeft(3, '0');
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${two(utc.month)}-${two(utc.day)}T'
      '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}.'
      '${three(utc.millisecond)}Z';
}

final class P3BrowserDownloadPolicy {
  const P3BrowserDownloadPolicy({
    this.maxPayloadBytes = _p3HardMaxDownloadBytes,
    this.maxQuarantineBytes = _p3HardMaxDownloadBytes,
    this.maxReceipts = 1024,
    this.maxReceiptBytes = 64 * 1024,
  });

  factory P3BrowserDownloadPolicy.fromJson(Map<String, Object?> value) {
    _requireExactBrowserKeys(
      value,
      const <String>{
        'maxPayloadBytes',
        'maxQuarantineBytes',
        'maxReceipts',
        'maxReceiptBytes',
      },
      'browser_download_limits_invalid',
    );
    final policy = P3BrowserDownloadPolicy(
      maxPayloadBytes: value['maxPayloadBytes'] is int
          ? value['maxPayloadBytes']! as int
          : -1,
      maxQuarantineBytes: value['maxQuarantineBytes'] is int
          ? value['maxQuarantineBytes']! as int
          : -1,
      maxReceipts:
          value['maxReceipts'] is int ? value['maxReceipts']! as int : -1,
      maxReceiptBytes: value['maxReceiptBytes'] is int
          ? value['maxReceiptBytes']! as int
          : -1,
    );
    policy.validate();
    return policy;
  }

  final int maxPayloadBytes;
  final int maxQuarantineBytes;
  final int maxReceipts;
  final int maxReceiptBytes;

  void validate() {
    if (maxPayloadBytes < 1 ||
        maxPayloadBytes > _p3HardMaxDownloadBytes ||
        maxQuarantineBytes < maxPayloadBytes ||
        maxQuarantineBytes > _p3HardMaxDownloadBytes ||
        maxReceipts < 1 ||
        maxReceipts > 4096 ||
        maxReceiptBytes < 1024 ||
        maxReceiptBytes > 64 * 1024) {
      throw const P3BrowserRuntimeException(
        'browser_download_limits_invalid',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'maxPayloadBytes': maxPayloadBytes,
        'maxQuarantineBytes': maxQuarantineBytes,
        'maxReceipts': maxReceipts,
        'maxReceiptBytes': maxReceiptBytes,
      };

  @override
  bool operator ==(Object other) =>
      other is P3BrowserDownloadPolicy &&
      other.maxPayloadBytes == maxPayloadBytes &&
      other.maxQuarantineBytes == maxQuarantineBytes &&
      other.maxReceipts == maxReceipts &&
      other.maxReceiptBytes == maxReceiptBytes;

  @override
  int get hashCode => Object.hash(
        maxPayloadBytes,
        maxQuarantineBytes,
        maxReceipts,
        maxReceiptBytes,
      );
}

const int _p3HardMaxUploadBytes = 32 * 1024 * 1024;
const String _p3UploadStageManifestType = 'kristin-p3-browser-upload-stage-v1';
const String _p3UploadReceiptType = 'kristin-p3-browser-upload-receipt-v1';
final RegExp _p3UploadStageId = RegExp(r'^uploadstage_[A-Za-z0-9_-]{1,115}$');
final RegExp _p3UploadReceiptId =
    RegExp(r'^uploadreceipt_[A-Za-z0-9_-]{1,113}$');
final RegExp _p3UploadMimeType =
    RegExp(r'^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$');

String _boundedBrowserUploadFilename(String raw) {
  var value = raw.split(RegExp(r'[\\/]')).last;
  value = value
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f<>:"|?*]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (value.isEmpty || value == '.' || value == '..') value = 'upload';
  final result = StringBuffer();
  var bytes = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final characterBytes = utf8.encode(character).length;
    if (bytes + characterBytes > 255) break;
    result.write(character);
    bytes += characterBytes;
  }
  final bounded = result.toString();
  return bounded.isEmpty ? 'upload' : bounded;
}

String _normalizedBrowserUploadMimeType(String raw) {
  if (raw.length < 3 ||
      utf8.encode(raw).length > 255 ||
      raw.contains('\u0000') ||
      !_p3UploadMimeType.hasMatch(raw)) {
    throw const P3BrowserRuntimeException(
      'browser_upload_mime_type_invalid',
    );
  }
  return raw.toLowerCase();
}

bool _isAbsoluteBrowserUploadPath(String value) =>
    value.startsWith('/') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
    value.startsWith(r'\\');

final class P3BrowserUploadPolicy {
  const P3BrowserUploadPolicy({
    this.maxPayloadBytes = _p3HardMaxUploadBytes,
    this.maxStagingBytes = _p3HardMaxUploadBytes,
    this.maxStages = 128,
    this.maxReceipts = 1024,
    this.maxManifestBytes = 64 * 1024,
    this.maxReceiptBytes = 64 * 1024,
  });

  factory P3BrowserUploadPolicy.fromJson(Map<String, Object?> value) {
    _requireExactBrowserKeys(
      value,
      const <String>{
        'maxPayloadBytes',
        'maxStagingBytes',
        'maxStages',
        'maxReceipts',
        'maxManifestBytes',
        'maxReceiptBytes',
      },
      'browser_upload_limits_invalid',
    );
    final policy = P3BrowserUploadPolicy(
      maxPayloadBytes: value['maxPayloadBytes'] is int
          ? value['maxPayloadBytes']! as int
          : -1,
      maxStagingBytes: value['maxStagingBytes'] is int
          ? value['maxStagingBytes']! as int
          : -1,
      maxStages: value['maxStages'] is int ? value['maxStages']! as int : -1,
      maxReceipts:
          value['maxReceipts'] is int ? value['maxReceipts']! as int : -1,
      maxManifestBytes: value['maxManifestBytes'] is int
          ? value['maxManifestBytes']! as int
          : -1,
      maxReceiptBytes: value['maxReceiptBytes'] is int
          ? value['maxReceiptBytes']! as int
          : -1,
    );
    policy.validate();
    return policy;
  }

  final int maxPayloadBytes;
  final int maxStagingBytes;
  final int maxStages;
  final int maxReceipts;
  final int maxManifestBytes;
  final int maxReceiptBytes;

  void validate() {
    if (maxPayloadBytes < 1 ||
        maxPayloadBytes > _p3HardMaxUploadBytes ||
        maxStagingBytes < maxPayloadBytes ||
        maxStagingBytes > _p3HardMaxUploadBytes ||
        maxStages < 1 ||
        maxStages > 256 ||
        maxReceipts < 1 ||
        maxReceipts > 4096 ||
        maxManifestBytes < 1024 ||
        maxManifestBytes > 64 * 1024 ||
        maxReceiptBytes < 1024 ||
        maxReceiptBytes > 64 * 1024) {
      throw const P3BrowserRuntimeException(
        'browser_upload_limits_invalid',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'maxPayloadBytes': maxPayloadBytes,
        'maxStagingBytes': maxStagingBytes,
        'maxStages': maxStages,
        'maxReceipts': maxReceipts,
        'maxManifestBytes': maxManifestBytes,
        'maxReceiptBytes': maxReceiptBytes,
      };

  @override
  bool operator ==(Object other) =>
      other is P3BrowserUploadPolicy &&
      other.maxPayloadBytes == maxPayloadBytes &&
      other.maxStagingBytes == maxStagingBytes &&
      other.maxStages == maxStages &&
      other.maxReceipts == maxReceipts &&
      other.maxManifestBytes == maxManifestBytes &&
      other.maxReceiptBytes == maxReceiptBytes;

  @override
  int get hashCode => Object.hash(
        maxPayloadBytes,
        maxStagingBytes,
        maxStages,
        maxReceipts,
        maxManifestBytes,
        maxReceiptBytes,
      );
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
    required this.downloadPolicy,
    required this.uploadPolicy,
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
    final downloadPolicyValue = value['downloadPolicy'];
    final uploadPolicyValue = value['uploadPolicy'];
    if (value['serviceMode'] != 'sessions' ||
        quotasValue is! Map ||
        downloadPolicyValue is! Map ||
        uploadPolicyValue is! Map) {
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
    late final P3BrowserDownloadPolicy downloadPolicy;
    try {
      downloadPolicy = P3BrowserDownloadPolicy.fromJson(
        Map<String, Object?>.from(downloadPolicyValue),
      );
    } on P3BrowserRuntimeException {
      throw const P3BrowserRuntimeException(
        'browser_session_ready_invalid',
      );
    }
    if (downloadPolicy != const P3BrowserDownloadPolicy()) {
      throw const P3BrowserRuntimeException(
        'browser_session_ready_download_policy_mismatch',
      );
    }
    late final P3BrowserUploadPolicy uploadPolicy;
    try {
      uploadPolicy = P3BrowserUploadPolicy.fromJson(
        Map<String, Object?>.from(uploadPolicyValue),
      );
    } on P3BrowserRuntimeException {
      throw const P3BrowserRuntimeException(
        'browser_session_ready_invalid',
      );
    }
    if (uploadPolicy != const P3BrowserUploadPolicy()) {
      throw const P3BrowserRuntimeException(
        'browser_session_ready_upload_policy_mismatch',
      );
    }
    return P3BrowserSessionReady(
      runtime: runtime,
      quotas: quotas,
      downloadPolicy: downloadPolicy,
      uploadPolicy: uploadPolicy,
    );
  }

  final P3BrowserRuntimeReady runtime;
  final P3BrowserSessionQuotas quotas;
  final P3BrowserDownloadPolicy downloadPolicy;
  final P3BrowserUploadPolicy uploadPolicy;

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
        'downloadPolicy': downloadPolicy.toJson(),
        'uploadPolicy': uploadPolicy.toJson(),
        'applicationOwned': true,
        'globalRuntimeRequired': false,
        'browserNetworkInstallRequired': false,
        'persistentProfileStateLocalOnly': true,
        'downloadQuarantineApplicationOwned': true,
        'downloadReceiptValidationIndependent': true,
        'uploadStagingApplicationOwned': true,
        'uploadReceiptValidationIndependent': true,
        'uploadBrowserTransferMode': 'in-memory-buffer',
        'p3_002SessionServiceImplemented': true,
        'p3_006aDownloadQuarantineImplemented': true,
        'p3_006bUploadStagingImplemented': true,
      };
}

final class P3BrowserSessionInfo {
  const P3BrowserSessionInfo({
    required this.sessionId,
    required this.kind,
    required this.profileId,
    required this.pageCount,
    required this.downloadsEnabled,
    required this.uploadsEnabled,
    required this.createdAt,
  });

  factory P3BrowserSessionInfo.fromJson(Map<String, Object?> value) {
    final sessionId = value['sessionId'];
    final kindName = value['kind'];
    final profileId = value['profileId'];
    final pageCount = value['pageCount'];
    final downloadsEnabled = value['downloadsEnabled'];
    final uploadsEnabled = value['uploadsEnabled'];
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
        downloadsEnabled is! bool ||
        uploadsEnabled is! bool ||
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
      downloadsEnabled: downloadsEnabled,
      uploadsEnabled: uploadsEnabled,
      createdAt: createdAt.toUtc(),
    );
  }

  final String sessionId;
  final P3BrowserSessionKind kind;
  final String? profileId;
  final int pageCount;
  final bool downloadsEnabled;
  final bool uploadsEnabled;
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

final class P3BrowserLocalNavigationRequest {
  const P3BrowserLocalNavigationRequest({
    required this.url,
    this.timeout = const Duration(seconds: 30),
  });

  final String url;
  final Duration timeout;

  Map<String, Object?> toJson() {
    final value = url.trim();
    final parsed = Uri.tryParse(value);
    final localHost = parsed != null &&
        const <String>{'localhost', '127.0.0.1', '::1'}
            .contains(parsed.host.toLowerCase());
    final aboutBlank = parsed != null &&
        parsed.scheme == 'about' &&
        parsed.path == 'blank' &&
        parsed.query.isEmpty &&
        parsed.fragment.isEmpty;
    final localHttp = parsed != null &&
        const <String>{'http', 'https'}.contains(parsed.scheme) &&
        localHost &&
        parsed.userInfo.isEmpty;
    if (value.isEmpty ||
        value.contains('\u0000') ||
        utf8.encode(value).length > 8192 ||
        !(aboutBlank || localHttp)) {
      throw const P3BrowserRuntimeException(
        'browser_local_navigation_target_forbidden',
      );
    }
    if (timeout < const Duration(milliseconds: 100) ||
        timeout > const Duration(seconds: 60)) {
      throw const P3BrowserRuntimeException(
        'browser_local_navigation_timeout_invalid',
      );
    }
    return <String, Object?>{
      'url': parsed.toString(),
      'timeoutMs': timeout.inMilliseconds,
    };
  }
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

final class P3BrowserDownloadRequest {
  const P3BrowserDownloadRequest({
    required this.locators,
    this.timeout = const Duration(seconds: 30),
  });

  final List<P3BrowserLocator> locators;
  final Duration timeout;

  Map<String, Object?> toJson() {
    if (locators.isEmpty || locators.length > 8) {
      throw const P3BrowserRuntimeException(
        'browser_locator_list_invalid',
      );
    }
    if (timeout < const Duration(milliseconds: 100) ||
        timeout > const Duration(seconds: 60)) {
      throw const P3BrowserRuntimeException(
        'browser_download_timeout_invalid',
      );
    }
    return <String, Object?>{
      'locators':
          locators.map((locator) => locator.toJson()).toList(growable: false),
      'timeoutMs': timeout.inMilliseconds,
    };
  }
}

final class P3BrowserDownloadReceipt {
  P3BrowserDownloadReceipt._({
    required this.downloadId,
    required this.sessionId,
    required this.sessionKind,
    required this.profileId,
    required this.pageId,
    required this.sourceUrl,
    required this.suggestedFilename,
    required this.payloadRelativePath,
    required this.bytes,
    required this.sha256,
    required this.locatorStrategy,
    required this.locatorIndex,
    required this.createdAt,
    required this.receiptHash,
    required Map<String, Object?> json,
  }) : json = Map<String, Object?>.unmodifiable(json);

  factory P3BrowserDownloadReceipt.fromJson(Map<String, Object?> value) {
    _requireExactBrowserKeys(
      value,
      const <String>{
        'schemaVersion',
        'receiptType',
        'downloadId',
        'sessionId',
        'sessionKind',
        'profileId',
        'pageId',
        'sourceUrl',
        'suggestedFilename',
        'content',
        'locator',
        'createdAt',
        'receiptHash',
      },
      'browser_download_receipt_invalid',
    );
    final contentValue = value['content'];
    final locatorValue = value['locator'];
    if (contentValue is! Map || locatorValue is! Map) {
      throw const P3BrowserRuntimeException(
        'browser_download_receipt_invalid',
      );
    }
    final content = Map<String, Object?>.from(contentValue);
    final locator = Map<String, Object?>.from(locatorValue);
    _requireExactBrowserKeys(
      content,
      const <String>{'relativePath', 'bytes', 'sha256'},
      'browser_download_receipt_invalid',
    );
    _requireExactBrowserKeys(
      locator,
      const <String>{'strategy', 'index'},
      'browser_download_receipt_invalid',
    );

    final downloadId = value['downloadId'];
    final sessionId = value['sessionId'];
    final sessionKindName = value['sessionKind'];
    final profileId = value['profileId'];
    final pageId = value['pageId'];
    final sourceUrl = value['sourceUrl'];
    final suggestedFilename = value['suggestedFilename'];
    final relativePath = content['relativePath'];
    final bytes = content['bytes'];
    final sha256 = content['sha256'];
    final locatorStrategy = locator['strategy'];
    final locatorIndex = locator['index'];
    final createdAtValue = value['createdAt'];
    final receiptHash = value['receiptHash'];
    final sessionKind = P3BrowserSessionKind.values
        .where((candidate) => candidate.wireName == sessionKindName)
        .firstOrNull;
    final createdAt =
        createdAtValue is String ? DateTime.tryParse(createdAtValue) : null;
    final profileValid =
        (sessionKind == P3BrowserSessionKind.ephemeral && profileId == null) ||
            (sessionKind == P3BrowserSessionKind.persistent &&
                profileId is String &&
                _p3ProfileId.hasMatch(profileId));
    final scopeId =
        sessionKind == P3BrowserSessionKind.persistent ? profileId : sessionId;
    final expectedRelativePath = scopeId is String && downloadId is String
        ? 'downloads/quarantine/${sessionKind?.wireName}/$scopeId/'
            '$downloadId/payload.bin'
        : '';

    if (value['schemaVersion'] != '1.0.0' ||
        value['receiptType'] != _p3DownloadReceiptType ||
        downloadId is! String ||
        !_p3DownloadId.hasMatch(downloadId) ||
        sessionId is! String ||
        !_p3GeneratedId.hasMatch(sessionId) ||
        sessionKind == null ||
        !profileValid ||
        pageId is! String ||
        !_p3GeneratedId.hasMatch(pageId) ||
        sourceUrl is! String ||
        utf8.encode(sourceUrl).length > 4096 ||
        suggestedFilename is! String ||
        _boundedBrowserDownloadFilename(suggestedFilename) !=
            suggestedFilename ||
        utf8.encode(suggestedFilename).length > 255 ||
        relativePath != expectedRelativePath ||
        bytes is! int ||
        bytes < 0 ||
        bytes > _p3HardMaxDownloadBytes ||
        sha256 is! String ||
        !_p3Sha256.hasMatch(sha256) ||
        locatorStrategy is! String ||
        !_p3DownloadLocatorStrategies.contains(locatorStrategy) ||
        locatorIndex is! int ||
        locatorIndex < 0 ||
        locatorIndex > 7 ||
        createdAtValue is! String ||
        createdAt == null ||
        createdAtValue != _canonicalBrowserIsoTimestamp(createdAt) ||
        receiptHash is! String ||
        !_p3Sha256.hasMatch(receiptHash)) {
      throw const P3BrowserRuntimeException(
        'browser_download_receipt_invalid',
      );
    }

    final hashInput = Map<String, Object?>.from(value)..remove('receiptHash');
    if (utf8.encode(canonicalJson(value)).length > 64 * 1024 ||
        Sha256.text(canonicalJson(hashInput)) != receiptHash) {
      throw const P3BrowserRuntimeException(
        'browser_download_receipt_hash_mismatch',
      );
    }
    return P3BrowserDownloadReceipt._(
      downloadId: downloadId,
      sessionId: sessionId,
      sessionKind: sessionKind,
      profileId: profileId as String?,
      pageId: pageId,
      sourceUrl: sourceUrl,
      suggestedFilename: suggestedFilename,
      payloadRelativePath: relativePath as String,
      bytes: bytes,
      sha256: sha256,
      locatorStrategy: locatorStrategy,
      locatorIndex: locatorIndex,
      createdAt: createdAt.toUtc(),
      receiptHash: receiptHash,
      json: <String, Object?>{
        ...value,
        'content': Map<String, Object?>.unmodifiable(content),
        'locator': Map<String, Object?>.unmodifiable(locator),
      },
    );
  }

  final String downloadId;
  final String sessionId;
  final P3BrowserSessionKind sessionKind;
  final String? profileId;
  final String pageId;
  final String sourceUrl;
  final String suggestedFilename;
  final String payloadRelativePath;
  final int bytes;
  final String sha256;
  final String locatorStrategy;
  final int locatorIndex;
  final DateTime createdAt;
  final String receiptHash;
  final Map<String, Object?> json;

  Map<String, Object?> toJson() => Map<String, Object?>.from(json);
}

final class P3BrowserUploadStageRequest {
  const P3BrowserUploadStageRequest({
    required this.sourcePath,
    required this.fileName,
    this.mimeType = 'application/octet-stream',
  });

  final String sourcePath;
  final String fileName;
  final String mimeType;

  Map<String, Object?> toJson() {
    if (sourcePath.isEmpty ||
        sourcePath.contains('\u0000') ||
        utf8.encode(sourcePath).length > 32 * 1024 ||
        !_isAbsoluteBrowserUploadPath(sourcePath)) {
      throw const P3BrowserRuntimeException(
        'browser_upload_source_path_invalid',
      );
    }
    return <String, Object?>{
      'sourcePath': sourcePath,
      'fileName': _boundedBrowserUploadFilename(fileName),
      'mimeType': _normalizedBrowserUploadMimeType(mimeType),
    };
  }
}

final class P3BrowserUploadStage {
  P3BrowserUploadStage._({
    required this.stageId,
    required this.sessionId,
    required this.sessionKind,
    required this.profileId,
    required this.fileName,
    required this.mimeType,
    required this.payloadRelativePath,
    required this.bytes,
    required this.sha256,
    required this.createdAt,
    required this.manifestHash,
    required Map<String, Object?> json,
  }) : json = Map<String, Object?>.unmodifiable(json);

  factory P3BrowserUploadStage.fromJson(Map<String, Object?> value) {
    _requireExactBrowserKeys(
      value,
      const <String>{
        'schemaVersion',
        'manifestType',
        'stageId',
        'sessionId',
        'sessionKind',
        'profileId',
        'file',
        'createdAt',
        'manifestHash',
      },
      'browser_upload_manifest_invalid',
    );
    final fileValue = value['file'];
    if (fileValue is! Map) {
      throw const P3BrowserRuntimeException(
        'browser_upload_manifest_invalid',
      );
    }
    final file = Map<String, Object?>.from(fileValue);
    _requireExactBrowserKeys(
      file,
      const <String>{'name', 'mimeType', 'relativePath', 'bytes', 'sha256'},
      'browser_upload_manifest_invalid',
    );

    final stageId = value['stageId'];
    final sessionId = value['sessionId'];
    final sessionKindName = value['sessionKind'];
    final profileId = value['profileId'];
    final fileName = file['name'];
    final mimeType = file['mimeType'];
    final relativePath = file['relativePath'];
    final bytes = file['bytes'];
    final sha256 = file['sha256'];
    final createdAtValue = value['createdAt'];
    final manifestHash = value['manifestHash'];
    final sessionKind = P3BrowserSessionKind.values
        .where((candidate) => candidate.wireName == sessionKindName)
        .firstOrNull;
    final createdAt =
        createdAtValue is String ? DateTime.tryParse(createdAtValue) : null;
    final profileValid =
        (sessionKind == P3BrowserSessionKind.ephemeral && profileId == null) ||
            (sessionKind == P3BrowserSessionKind.persistent &&
                profileId is String &&
                _p3ProfileId.hasMatch(profileId));
    final expectedRelativePath =
        stageId is String ? 'uploads/staging/$stageId/payload.bin' : '';
    String? normalizedMimeType;
    if (mimeType is String) {
      try {
        normalizedMimeType = _normalizedBrowserUploadMimeType(mimeType);
      } on P3BrowserRuntimeException {
        normalizedMimeType = null;
      }
    }

    if (value['schemaVersion'] != '1.0.0' ||
        value['manifestType'] != _p3UploadStageManifestType ||
        stageId is! String ||
        !_p3UploadStageId.hasMatch(stageId) ||
        sessionId is! String ||
        !_p3GeneratedId.hasMatch(sessionId) ||
        sessionKind == null ||
        !profileValid ||
        fileName is! String ||
        _boundedBrowserUploadFilename(fileName) != fileName ||
        utf8.encode(fileName).length > 255 ||
        mimeType is! String ||
        normalizedMimeType != mimeType ||
        relativePath != expectedRelativePath ||
        bytes is! int ||
        bytes < 0 ||
        bytes > _p3HardMaxUploadBytes ||
        sha256 is! String ||
        !_p3Sha256.hasMatch(sha256) ||
        createdAtValue is! String ||
        createdAt == null ||
        createdAtValue != _canonicalBrowserIsoTimestamp(createdAt) ||
        manifestHash is! String ||
        !_p3Sha256.hasMatch(manifestHash)) {
      throw const P3BrowserRuntimeException(
        'browser_upload_manifest_invalid',
      );
    }

    final hashInput = Map<String, Object?>.from(value)..remove('manifestHash');
    if (utf8.encode(canonicalJson(value)).length > 64 * 1024 ||
        Sha256.text(canonicalJson(hashInput)) != manifestHash) {
      throw const P3BrowserRuntimeException(
        'browser_upload_manifest_hash_mismatch',
      );
    }
    return P3BrowserUploadStage._(
      stageId: stageId,
      sessionId: sessionId,
      sessionKind: sessionKind,
      profileId: profileId as String?,
      fileName: fileName,
      mimeType: mimeType,
      payloadRelativePath: relativePath as String,
      bytes: bytes,
      sha256: sha256,
      createdAt: createdAt.toUtc(),
      manifestHash: manifestHash,
      json: <String, Object?>{
        ...value,
        'file': Map<String, Object?>.unmodifiable(file),
      },
    );
  }

  final String stageId;
  final String sessionId;
  final P3BrowserSessionKind sessionKind;
  final String? profileId;
  final String fileName;
  final String mimeType;
  final String payloadRelativePath;
  final int bytes;
  final String sha256;
  final DateTime createdAt;
  final String manifestHash;
  final Map<String, Object?> json;

  Map<String, Object?> get requestIdentity => <String, Object?>{
        'stageId': stageId,
        'manifestHash': manifestHash,
        'fileName': fileName,
        'mimeType': mimeType,
        'bytes': bytes,
        'sha256': sha256,
      };

  Map<String, Object?> toJson() => Map<String, Object?>.from(json);
}

final class P3BrowserUploadRequest {
  const P3BrowserUploadRequest({
    required this.locators,
    required this.stage,
    this.timeout = const Duration(seconds: 30),
  });

  final List<P3BrowserLocator> locators;
  final P3BrowserUploadStage stage;
  final Duration timeout;

  Map<String, Object?> toJson() {
    if (locators.isEmpty || locators.length > 8) {
      throw const P3BrowserRuntimeException(
        'browser_locator_list_invalid',
      );
    }
    if (timeout < const Duration(milliseconds: 100) ||
        timeout > const Duration(seconds: 60)) {
      throw const P3BrowserRuntimeException(
        'browser_upload_timeout_invalid',
      );
    }
    return <String, Object?>{
      'locators':
          locators.map((locator) => locator.toJson()).toList(growable: false),
      'stage': stage.requestIdentity,
      'timeoutMs': timeout.inMilliseconds,
    };
  }
}

final class P3BrowserUploadReceipt {
  P3BrowserUploadReceipt._({
    required this.receiptId,
    required this.stageId,
    required this.manifestHash,
    required this.sessionId,
    required this.sessionKind,
    required this.profileId,
    required this.pageId,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.sha256,
    required this.locatorStrategy,
    required this.locatorIndex,
    required this.createdAt,
    required this.receiptHash,
    required Map<String, Object?> json,
  }) : json = Map<String, Object?>.unmodifiable(json);

  factory P3BrowserUploadReceipt.fromJson(Map<String, Object?> value) {
    _requireExactBrowserKeys(
      value,
      const <String>{
        'schemaVersion',
        'receiptType',
        'receiptId',
        'stageId',
        'manifestHash',
        'sessionId',
        'sessionKind',
        'profileId',
        'pageId',
        'file',
        'locator',
        'transferMode',
        'createdAt',
        'receiptHash',
      },
      'browser_upload_receipt_invalid',
    );
    final fileValue = value['file'];
    final locatorValue = value['locator'];
    if (fileValue is! Map || locatorValue is! Map) {
      throw const P3BrowserRuntimeException(
        'browser_upload_receipt_invalid',
      );
    }
    final file = Map<String, Object?>.from(fileValue);
    final locator = Map<String, Object?>.from(locatorValue);
    _requireExactBrowserKeys(
      file,
      const <String>{'name', 'mimeType', 'bytes', 'sha256'},
      'browser_upload_receipt_invalid',
    );
    _requireExactBrowserKeys(
      locator,
      const <String>{'strategy', 'index'},
      'browser_upload_receipt_invalid',
    );

    final receiptId = value['receiptId'];
    final stageId = value['stageId'];
    final manifestHash = value['manifestHash'];
    final sessionId = value['sessionId'];
    final sessionKindName = value['sessionKind'];
    final profileId = value['profileId'];
    final pageId = value['pageId'];
    final fileName = file['name'];
    final mimeType = file['mimeType'];
    final bytes = file['bytes'];
    final sha256 = file['sha256'];
    final locatorStrategy = locator['strategy'];
    final locatorIndex = locator['index'];
    final createdAtValue = value['createdAt'];
    final receiptHash = value['receiptHash'];
    final sessionKind = P3BrowserSessionKind.values
        .where((candidate) => candidate.wireName == sessionKindName)
        .firstOrNull;
    final createdAt =
        createdAtValue is String ? DateTime.tryParse(createdAtValue) : null;
    final profileValid =
        (sessionKind == P3BrowserSessionKind.ephemeral && profileId == null) ||
            (sessionKind == P3BrowserSessionKind.persistent &&
                profileId is String &&
                _p3ProfileId.hasMatch(profileId));
    String? normalizedMimeType;
    if (mimeType is String) {
      try {
        normalizedMimeType = _normalizedBrowserUploadMimeType(mimeType);
      } on P3BrowserRuntimeException {
        normalizedMimeType = null;
      }
    }

    if (value['schemaVersion'] != '1.0.0' ||
        value['receiptType'] != _p3UploadReceiptType ||
        receiptId is! String ||
        !_p3UploadReceiptId.hasMatch(receiptId) ||
        stageId is! String ||
        !_p3UploadStageId.hasMatch(stageId) ||
        manifestHash is! String ||
        !_p3Sha256.hasMatch(manifestHash) ||
        sessionId is! String ||
        !_p3GeneratedId.hasMatch(sessionId) ||
        sessionKind == null ||
        !profileValid ||
        pageId is! String ||
        !_p3GeneratedId.hasMatch(pageId) ||
        fileName is! String ||
        _boundedBrowserUploadFilename(fileName) != fileName ||
        utf8.encode(fileName).length > 255 ||
        mimeType is! String ||
        normalizedMimeType != mimeType ||
        bytes is! int ||
        bytes < 0 ||
        bytes > _p3HardMaxUploadBytes ||
        sha256 is! String ||
        !_p3Sha256.hasMatch(sha256) ||
        locatorStrategy is! String ||
        !_p3DownloadLocatorStrategies.contains(locatorStrategy) ||
        locatorIndex is! int ||
        locatorIndex < 0 ||
        locatorIndex > 7 ||
        value['transferMode'] != 'in-memory-buffer' ||
        createdAtValue is! String ||
        createdAt == null ||
        createdAtValue != _canonicalBrowserIsoTimestamp(createdAt) ||
        receiptHash is! String ||
        !_p3Sha256.hasMatch(receiptHash)) {
      throw const P3BrowserRuntimeException(
        'browser_upload_receipt_invalid',
      );
    }

    final hashInput = Map<String, Object?>.from(value)..remove('receiptHash');
    if (utf8.encode(canonicalJson(value)).length > 64 * 1024 ||
        Sha256.text(canonicalJson(hashInput)) != receiptHash) {
      throw const P3BrowserRuntimeException(
        'browser_upload_receipt_hash_mismatch',
      );
    }
    return P3BrowserUploadReceipt._(
      receiptId: receiptId,
      stageId: stageId,
      manifestHash: manifestHash,
      sessionId: sessionId,
      sessionKind: sessionKind,
      profileId: profileId as String?,
      pageId: pageId,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
      sha256: sha256,
      locatorStrategy: locatorStrategy,
      locatorIndex: locatorIndex,
      createdAt: createdAt.toUtc(),
      receiptHash: receiptHash,
      json: <String, Object?>{
        ...value,
        'file': Map<String, Object?>.unmodifiable(file),
        'locator': Map<String, Object?>.unmodifiable(locator),
      },
    );
  }

  final String receiptId;
  final String stageId;
  final String manifestHash;
  final String sessionId;
  final P3BrowserSessionKind sessionKind;
  final String? profileId;
  final String pageId;
  final String fileName;
  final String mimeType;
  final int bytes;
  final String sha256;
  final String locatorStrategy;
  final int locatorIndex;
  final DateTime createdAt;
  final String receiptHash;
  final Map<String, Object?> json;

  Map<String, Object?> toJson() => Map<String, Object?>.from(json);
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
    bool downloadsEnabled = false,
    bool uploadsEnabled = false,
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
      'downloadsEnabled': downloadsEnabled,
      'uploadsEnabled': uploadsEnabled,
    });
    final info = _decodeResponse(() => P3BrowserSessionInfo.fromJson(result));
    if (info.kind != kind ||
        info.profileId != profileId ||
        info.pageCount != 0 ||
        info.downloadsEnabled != downloadsEnabled ||
        info.uploadsEnabled != uploadsEnabled) {
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

  Future<P3BrowserPageObservation> navigateLocalPage(
    String sessionId,
    String pageId,
    P3BrowserLocalNavigationRequest request,
  ) async {
    final result = await _request('page.navigateLocal', <String, Object?>{
      'sessionId': sessionId,
      'pageId': pageId,
      'navigationRequest': request.toJson(),
    });
    final observation = _decodeResponse(
      () => P3BrowserPageObservation.fromJson(result),
    );
    if (observation.sessionId != sessionId || observation.pageId != pageId) {
      _protocolViolation('browser_observation_identity_mismatch');
    }
    return observation;
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

  Future<P3BrowserDownloadReceipt> downloadPage(
    String sessionId,
    String pageId,
    P3BrowserDownloadRequest request,
  ) async {
    final result = await _request('page.download', <String, Object?>{
      'sessionId': sessionId,
      'pageId': pageId,
      'downloadRequest': request.toJson(),
    });
    final receipt = _decodeResponse(
      () => P3BrowserDownloadReceipt.fromJson(result),
    );
    if (receipt.sessionId != sessionId || receipt.pageId != pageId) {
      _protocolViolation('browser_download_receipt_identity_mismatch');
    }
    return receipt;
  }

  Future<List<P3BrowserDownloadReceipt>> listDownloads() async {
    final result = await _request('download.list', const <String, Object?>{});
    final values = result['downloads'];
    if (values is! List) {
      throw const P3BrowserRuntimeException(
        'browser_download_response_invalid',
      );
    }
    final receipts = _decodeResponse(() => values.map((value) {
          if (value is! Map) {
            throw const P3BrowserRuntimeException(
              'browser_download_response_invalid',
            );
          }
          return P3BrowserDownloadReceipt.fromJson(
            Map<String, Object?>.from(value),
          );
        }).toList(growable: false));
    if (receipts.length > ready.downloadPolicy.maxReceipts ||
        receipts.map((receipt) => receipt.downloadId).toSet().length !=
            receipts.length) {
      _protocolViolation('browser_download_response_identity_mismatch');
    }
    var bytes = 0;
    for (final receipt in receipts) {
      bytes += receipt.bytes;
      if (bytes > ready.downloadPolicy.maxQuarantineBytes) {
        _protocolViolation('browser_download_response_identity_mismatch');
      }
    }
    for (var index = 1; index < receipts.length; index += 1) {
      final previous = receipts[index - 1];
      final current = receipts[index];
      final ordered = previous.createdAt.isBefore(current.createdAt) ||
          (previous.createdAt.isAtSameMomentAs(current.createdAt) &&
              previous.downloadId.compareTo(current.downloadId) <= 0);
      if (!ordered) {
        _protocolViolation('browser_download_response_identity_mismatch');
      }
    }
    return receipts;
  }

  Future<void> discardDownload(
    String downloadId,
    String receiptHash,
  ) async {
    if (!_p3DownloadId.hasMatch(downloadId) ||
        !_p3Sha256.hasMatch(receiptHash)) {
      throw const P3BrowserRuntimeException(
        'browser_download_receipt_identity_mismatch',
      );
    }
    final result = await _request('download.discard', <String, Object?>{
      'downloadId': downloadId,
      'receiptHash': receiptHash,
    });
    if (result['downloadId'] != downloadId || result['discarded'] != true) {
      _protocolViolation('browser_download_response_identity_mismatch');
    }
  }

  Future<P3BrowserUploadStage> stageUpload(
    String sessionId,
    P3BrowserUploadStageRequest request,
  ) async {
    final result = await _request('upload.stage', <String, Object?>{
      'sessionId': sessionId,
      'stageRequest': request.toJson(),
    });
    final stage = _decodeResponse(
      () => P3BrowserUploadStage.fromJson(result),
    );
    if (stage.sessionId != sessionId) {
      _protocolViolation('browser_upload_manifest_identity_mismatch');
    }
    return stage;
  }

  Future<P3BrowserUploadReceipt> uploadPage(
    String sessionId,
    String pageId,
    P3BrowserUploadRequest request,
  ) async {
    final result = await _request('page.upload', <String, Object?>{
      'sessionId': sessionId,
      'pageId': pageId,
      'uploadRequest': request.toJson(),
    });
    final receipt = _decodeResponse(
      () => P3BrowserUploadReceipt.fromJson(result),
    );
    if (receipt.sessionId != sessionId ||
        receipt.pageId != pageId ||
        receipt.stageId != request.stage.stageId ||
        receipt.manifestHash != request.stage.manifestHash) {
      _protocolViolation('browser_upload_receipt_identity_mismatch');
    }
    return receipt;
  }

  Future<List<P3BrowserUploadReceipt>> listUploadReceipts(
    String sessionId,
  ) async {
    final result = await _request('upload.list', <String, Object?>{
      'sessionId': sessionId,
    });
    final values = result['uploads'];
    if (values is! List) {
      throw const P3BrowserRuntimeException(
        'browser_upload_response_invalid',
      );
    }
    final receipts = _decodeResponse(() => values.map((value) {
          if (value is! Map) {
            throw const P3BrowserRuntimeException(
              'browser_upload_response_invalid',
            );
          }
          return P3BrowserUploadReceipt.fromJson(
            Map<String, Object?>.from(value),
          );
        }).toList(growable: false));
    if (receipts.length > ready.uploadPolicy.maxReceipts ||
        receipts.any((receipt) => receipt.sessionId != sessionId) ||
        receipts.map((receipt) => receipt.receiptId).toSet().length !=
            receipts.length ||
        receipts.map((receipt) => receipt.stageId).toSet().length !=
            receipts.length) {
      _protocolViolation('browser_upload_response_identity_mismatch');
    }
    for (var index = 1; index < receipts.length; index += 1) {
      final previous = receipts[index - 1];
      final current = receipts[index];
      final ordered = previous.createdAt.isBefore(current.createdAt) ||
          (previous.createdAt.isAtSameMomentAs(current.createdAt) &&
              previous.receiptId.compareTo(current.receiptId) <= 0);
      if (!ordered) {
        _protocolViolation('browser_upload_response_identity_mismatch');
      }
    }
    return receipts;
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
/// isolated ephemeral/persistent contexts and bounded page lifecycle. P3-006A
/// adds controlled download quarantine. P3-006B adds explicit upload opt-in,
/// application-owned staging, in-memory browser transfer, one-use consumption
/// locks, and independently verified durable upload receipts.
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
