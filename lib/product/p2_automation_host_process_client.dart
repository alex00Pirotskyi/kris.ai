import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'crypto_utils.dart';
import 'p2_automation_host.dart';
import 'p2_effect_boundary.dart';

class P2AutomationHostException implements Exception {
  const P2AutomationHostException(this.code, [this.message = '']);

  final String code;
  final String message;

  @override
  String toString() => message.isEmpty
      ? 'P2AutomationHostException($code)'
      : 'P2AutomationHostException($code, $message)';
}

abstract interface class P2RestrictedWorkerIdentitySink {
  void bindRestrictedWorkerIdentity(Map<String, Object?> identity);
}

abstract interface class P2ProtectedAutomationBootstrapProvider {
  /// Returns one protected bootstrap payload containing only key handles resolved
  /// by the desktop authority and its durable grant/replay state.
  Future<Map<String, Object?>> take();
}

final class P2OneShotAutomationBootstrap
    implements P2ProtectedAutomationBootstrapProvider {
  P2OneShotAutomationBootstrap(Map<String, Object?> value)
    : _value = Map<String, Object?>.from(value);

  Map<String, Object?>? _value;

  @override
  Future<Map<String, Object?>> take() async {
    final value = _value;
    _value = null;
    if (value == null) {
      throw const P2AutomationHostException('bootstrap_already_consumed');
    }
    return value;
  }

  @override
  String toString() => 'P2OneShotAutomationBootstrap([PROTECTED])';
}

final class P2AutomationHostLaunchConfig {
  const P2AutomationHostLaunchConfig({
    required this.nodeExecutable,
    required this.hostScript,
    required this.workingDirectory,
    required this.restrictedWorkerLauncher,
    required this.restrictedWorkerLauncherSha256,
    required this.workerPolicy,
    required this.workerPolicySha256,
    required this.nodeExecutableSha256,
    required this.hostScriptSha256,
    required this.bootstrapProvider,
    this.windowsJobHelper,
    this.posixWatchdog,
    this.interactiveDesktopAdapter,
    this.interactiveDesktopAttested = false,
    this.fixtureRoot,
    this.additionalEnvironment = const <String, String>{},
    this.startupTimeout = const Duration(seconds: 15),
    this.maxTransportLineBytes = 16 * 1024 * 1024,
  });

  final String nodeExecutable;
  final String hostScript;
  final String workingDirectory;
  final String restrictedWorkerLauncher;
  final String restrictedWorkerLauncherSha256;
  final String workerPolicy;
  final String workerPolicySha256;
  final String nodeExecutableSha256;
  final String hostScriptSha256;
  final P2ProtectedAutomationBootstrapProvider bootstrapProvider;
  final String? windowsJobHelper;
  final String? posixWatchdog;
  final String? interactiveDesktopAdapter;
  final bool interactiveDesktopAttested;
  final String? fixtureRoot;
  final Map<String, String> additionalEnvironment;
  final Duration startupTimeout;
  final int maxTransportLineBytes;

  static bool _isAbsolute(String value) {
    if (Platform.isWindows) {
      return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
          value.startsWith(r'\\');
    }
    return value.startsWith('/');
  }

  void validate() {
    if (!_isAbsolute(nodeExecutable) || !File(nodeExecutable).existsSync()) {
      throw const P2AutomationHostException('node_executable_required');
    }
    if (!_isAbsolute(hostScript) || !File(hostScript).existsSync()) {
      throw const P2AutomationHostException('automation_host_script_required');
    }
    if (!_isAbsolute(workingDirectory) ||
        !Directory(workingDirectory).existsSync()) {
      throw const P2AutomationHostException('automation_host_cwd_required');
    }
    if (!_isAbsolute(restrictedWorkerLauncher) ||
        !File(restrictedWorkerLauncher).existsSync()) {
      throw const P2AutomationHostException(
        'restricted_worker_launcher_required',
      );
    }
    if (!_isAbsolute(workerPolicy) || !File(workerPolicy).existsSync()) {
      throw const P2AutomationHostException(
        'restricted_worker_policy_required',
      );
    }
    for (final digest in <String>[
      restrictedWorkerLauncherSha256,
      workerPolicySha256,
      nodeExecutableSha256,
      hostScriptSha256,
    ]) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
        throw const P2AutomationHostException(
          'restricted_worker_digest_invalid',
        );
      }
    }
    final observedDigests = <String, String>{
      restrictedWorkerLauncher: Sha256.hex(
        File(restrictedWorkerLauncher).readAsBytesSync(),
      ),
      workerPolicy: Sha256.hex(File(workerPolicy).readAsBytesSync()),
      nodeExecutable: Sha256.hex(File(nodeExecutable).readAsBytesSync()),
      hostScript: Sha256.hex(File(hostScript).readAsBytesSync()),
    };
    final expectedDigests = <String, String>{
      restrictedWorkerLauncher: restrictedWorkerLauncherSha256,
      workerPolicy: workerPolicySha256,
      nodeExecutable: nodeExecutableSha256,
      hostScript: hostScriptSha256,
    };
    for (final entry in observedDigests.entries) {
      if (entry.value != expectedDigests[entry.key]) {
        throw const P2AutomationHostException(
          'restricted_worker_digest_mismatch',
        );
      }
    }
    for (final optional in <String?>[
      windowsJobHelper,
      posixWatchdog,
      interactiveDesktopAdapter,
    ]) {
      if (optional != null &&
          (!_isAbsolute(optional) || !File(optional).existsSync())) {
        throw const P2AutomationHostException('native_helper_invalid');
      }
    }
    if (fixtureRoot != null && !_isAbsolute(fixtureRoot!)) {
      throw const P2AutomationHostException('fixture_root_invalid');
    }
    if (startupTimeout <= Duration.zero ||
        startupTimeout > const Duration(minutes: 2)) {
      throw const P2AutomationHostException('startup_timeout_invalid');
    }
    if (maxTransportLineBytes < 65536 ||
        maxTransportLineBytes > 64 * 1024 * 1024) {
      throw const P2AutomationHostException('transport_line_budget_invalid');
    }
    for (final entry in additionalEnvironment.entries) {
      if (entry.key.contains('=') ||
          entry.key.contains('\u0000') ||
          entry.value.contains('\u0000')) {
        throw const P2AutomationHostException('environment_invalid');
      }
      if (RegExp(
        r'(secret|token|password|credential|api.?key|private.?key)',
        caseSensitive: false,
      ).hasMatch(entry.key)) {
        throw const P2AutomationHostException(
          'secret_environment_key_forbidden',
        );
      }
    }
  }
}

/// Concrete production transport for the supervised automation host.
///
/// Protected bootstrap material crosses only the private parent/child pipe after
/// a child-generated challenge. It never appears in argv, environment, ordinary
/// logs, transcripts, screenshots, or release evidence.
final class P2ProcessAutomationHostClient implements P2AutomationHostClient {
  P2ProcessAutomationHostClient._(
    this._process,
    this._config,
    this._bootstrap,
    this._expectedWorkerSessionId,
  ) {
    _stdoutSubscription = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleLine,
          onError: _handleTransportError,
          onDone: _handleDone,
        );
    _stderrSubscription = _process.stderr.listen((List<int> bytes) {
      _stderrBytes += bytes.length;
      if (_stderrBytes > 4 * 1024 * 1024) {
        _failAll(
          const P2AutomationHostException('automation_host_stderr_flood'),
        );
        _process.kill();
      }
    });
    unawaited(_watchExit());
  }

  static Future<P2ProcessAutomationHostClient> start(
    P2AutomationHostLaunchConfig config,
  ) async {
    config.validate();
    final bootstrap = await config.bootstrapProvider.take();
    final workerSessionId = bootstrap['workerSessionId']?.toString() ?? '';
    if (bootstrap['schemaVersion'] != '4.0.0' ||
        workerSessionId.length < 16 ||
        bootstrap['verificationMode'] != 'ecdsa-p256-public-only') {
      throw const P2AutomationHostException(
        'restricted_worker_bootstrap_invalid',
      );
    }
    final launcherEnvironment = <String, String>{
      if (Platform.environment['SystemRoot'] case final value?)
        'SystemRoot': value,
      if (Platform.environment['WINDIR'] case final value?) 'WINDIR': value,
      if (Platform.environment['TEMP'] case final value?) 'TEMP': value,
      if (Platform.environment['TMP'] case final value?) 'TMP': value,
      'KRISTIN_WORKER_SESSION_ID': workerSessionId,
      if (config.additionalEnvironment['KRISTIN_OWNER_RISK_QA']
          case final value?)
        'KRISTIN_OWNER_RISK_QA': value,
    };
    final ownerRiskQa =
        config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';
    final process = await Process.start(
      ownerRiskQa ? config.nodeExecutable : config.restrictedWorkerLauncher,
      <String>[
        if (ownerRiskQa) config.restrictedWorkerLauncher,
        '--policy',
        config.workerPolicy,
        '--session',
        workerSessionId,
      ],
      workingDirectory: config.workingDirectory,
      environment: launcherEnvironment,
      includeParentEnvironment: false,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    final client = P2ProcessAutomationHostClient._(
      process,
      config,
      Map<String, Object?>.unmodifiable(bootstrap),
      workerSessionId,
    );
    try {
      final workerIdentity = await client._workerIdentity.future.timeout(
        config.startupTimeout,
      );
      final denial = await client._workerAuthorityDenial.future.timeout(
        config.startupTimeout,
      );
      final boundIdentity = client._finalizeWorkerIdentity(<String, Object?>{
        ...workerIdentity,
        ...denial,
      });
      client._workerIdentityValue = boundIdentity;
      final provider = config.bootstrapProvider;
      if (provider case final P2RestrictedWorkerIdentitySink identitySink) {
        identitySink.bindRestrictedWorkerIdentity(boundIdentity);
      }
      final challenge = await client._challenge.future.timeout(
        config.startupTimeout,
      );
      client._sendJson(<String, Object?>{
        'type': 'bootstrap',
        'schemaVersion': '4.0.0',
        'challenge': challenge,
        ...bootstrap,
      });
      await client._ready.future.timeout(config.startupTimeout);
      return client;
    } on TimeoutException {
      await client.close();
      throw const P2AutomationHostException('automation_host_start_timeout');
    } catch (_) {
      await client.close();
      rethrow;
    }
  }

  final Process _process;
  final P2AutomationHostLaunchConfig _config;
  final Map<String, Object?> _bootstrap;
  final String _expectedWorkerSessionId;
  final Completer<Map<String, Object?>> _workerIdentity =
      Completer<Map<String, Object?>>();
  final Completer<Map<String, Object?>> _workerAuthorityDenial =
      Completer<Map<String, Object?>>();
  Map<String, Object?> _workerIdentityValue = const <String, Object?>{};
  final Completer<String> _challenge = Completer<String>();
  final Completer<void> _ready = Completer<void>();
  final Map<String, Completer<Map<String, Object?>>> _pending =
      <String, Completer<Map<String, Object?>>>{};
  final StreamController<Map<String, Object?>> _events =
      StreamController<Map<String, Object?>>.broadcast(sync: true);
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<List<int>> _stderrSubscription;
  int _stderrBytes = 0;
  bool _closing = false;
  bool _closed = false;

  @override
  Stream<Map<String, Object?>> get events => _events.stream;
  int get pid => _workerIdentityValue['pid'] is int
      ? _workerIdentityValue['pid']! as int
      : _process.pid;
  Map<String, Object?> get workerIdentity => _workerIdentityValue;
  Map<String, Object?> get bootstrapProvenance => <String, Object?>{
    'schemaVersion': _bootstrap['schemaVersion'],
    'workerSessionId': _expectedWorkerSessionId,
    'verificationMode': _bootstrap['verificationMode'],
  };
  bool get isClosed => _closed;

  @override
  Future<Map<String, Object?>> invoke(P2AutomationEnvelope envelope) async {
    envelope.validate();
    if (_closed || _closing) {
      throw const P2AutomationHostException('automation_host_closed');
    }
    await _ready.future;
    if (_pending.containsKey(envelope.requestId)) {
      throw const P2AutomationHostException('duplicate_request_id');
    }
    final remaining = envelope.deadline.toUtc().difference(
      DateTime.now().toUtc(),
    );
    if (remaining <= Duration.zero) {
      throw const P2AutomationHostException('deadline_expired');
    }
    final completer = Completer<Map<String, Object?>>();
    _pending[envelope.requestId] = completer;
    _sendJson(envelope.toJson());
    try {
      final response = await completer.future.timeout(remaining);
      return _bindWorkerIdentityToResponse(response);
    } on TimeoutException {
      _pending.remove(envelope.requestId);
      throw const P2AutomationHostException('automation_host_deadline_unknown');
    }
  }

  @override
  Stream<Map<String, Object?>> stream(
    String requestId, {
    required P2EffectBinding binding,
    required P2WorkerGrantProof grantProof,
  }) {
    return _events.stream.where((Map<String, Object?> event) {
      final openRequestId = event['requestId'] ?? event['openRequestId'];
      if (openRequestId != requestId) return false;
      final rawBinding = event['authorizationBinding'];
      if (rawBinding is! Map) return false;
      final value = Map<String, Object?>.from(rawBinding);
      return value['runId'] == binding.runId &&
          value['taskId'] == binding.taskId &&
          value['actorId'] == binding.actorId &&
          value['grantId'] == grantProof.grantId &&
          value['grantDigest'] == grantProof.grantDigest;
    });
  }

  @override
  Future<Map<String, Object?>> cancel(P2AutomationEnvelope envelope) {
    if (envelope.operation != 'control.cancel') {
      throw const P2AutomationHostException(
        'authorized_cancel_envelope_required',
      );
    }
    return invoke(envelope);
  }

  @override
  Future<void> close() async {
    if (_closed || _closing) return;
    _closing = true;
    try {
      _sendJson(const <String, Object?>{'type': 'shutdown'});
    } catch (_) {
      // Continue to bounded termination.
    }
    try {
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      await _process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () => -1,
      );
    } finally {
      _closed = true;
      _closing = false;
      await _stdoutSubscription.cancel();
      await _stderrSubscription.cancel();
      _failAll(const P2AutomationHostException('automation_host_closed'));
      await _events.close();
    }
  }

  void _sendJson(Map<String, Object?> value) {
    if (_closed) {
      throw const P2AutomationHostException('automation_host_closed');
    }
    final line = jsonEncode(value);
    if (utf8.encode(line).length > _config.maxTransportLineBytes) {
      throw const P2AutomationHostException('transport_line_budget_exceeded');
    }
    _process.stdin.writeln(line);
  }

  void _handleLine(String line) {
    if (utf8.encode(line).length > _config.maxTransportLineBytes) {
      _handleTransportError(
        const P2AutomationHostException('transport_line_budget_exceeded'),
      );
      _process.kill();
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      _handleTransportError(
        const P2AutomationHostException('automation_host_protocol_invalid'),
      );
      return;
    }
    if (decoded is! Map) return;
    final message = Map<String, Object?>.from(decoded);
    final type = message['type'];
    if (type == 'launcher.identity') {
      try {
        final identity = _validateWorkerIdentity(message);
        _workerIdentityValue = identity;
        if (!_workerIdentity.isCompleted) _workerIdentity.complete(identity);
        final ownerRiskQa =
            _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';
        if (!_workerAuthorityDenial.isCompleted &&
            ((!ownerRiskQa &&
                    identity['authorityConnectionDenied'] == true &&
                    identity['authorityDenialCode'] ==
                        'worker_principal_denied') ||
                (ownerRiskQa &&
                    identity['authorityConnectionDenied'] == false &&
                    identity['authorityDenialCode'] == 'owner_risk_waived' &&
                    identity['ownerRiskQa'] == true &&
                    identity['osIsolationWaived'] == true))) {
          _workerAuthorityDenial.complete(<String, Object?>{
            'authorityConnectionDenied': ownerRiskQa ? false : true,
            'authorityDenialCode': ownerRiskQa
                ? 'owner_risk_waived'
                : 'worker_principal_denied',
            'authorityDenialObservedBy': ownerRiskQa
                ? 'owner-risk-waiver'
                : 'restricted-launcher',
            if (ownerRiskQa) 'ownerRiskQa': true,
            if (ownerRiskQa) 'osIsolationWaived': true,
            if (ownerRiskQa) 'currentAccountAuthority': true,
          });
        }
      } catch (error, stack) {
        _handleTransportError(error, stack);
        _process.kill();
      }
      return;
    }
    if (type == 'worker.authority-denial') {
      final code = message['errorCode']?.toString() ?? '';
      if (message['status'] != 'denied' ||
          code != 'worker_principal_denied' ||
          message['workerSessionId'] != _expectedWorkerSessionId ||
          message['pid'] != _workerIdentityValue['pid']) {
        _handleTransportError(
          const P2AutomationHostException('worker_authority_denial_invalid'),
        );
        _process.kill();
      } else if (!_workerAuthorityDenial.isCompleted) {
        _workerAuthorityDenial.complete(<String, Object?>{
          'authorityConnectionDenied': true,
          'authorityDenialCode': code,
          'authorityDenialObservedBy': 'restricted-worker-process',
          'authorityDenialTransport': message['transport'],
        });
      }
      return;
    }
    if (type == 'bootstrap.challenge') {
      final challenge = message['challenge']?.toString() ?? '';
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(challenge)) {
        _handleTransportError(
          const P2AutomationHostException('bootstrap_challenge_invalid'),
        );
      } else if (!_challenge.isCompleted) {
        _challenge.complete(challenge);
      }
      return;
    }
    if (type == 'ready') {
      final ownerRiskQa =
          _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';
      final principalReady = ownerRiskQa
          ? message['restrictedWorkerPrincipal'] == false &&
                message['ownerRiskCurrentAccount'] == true &&
                message['osIsolationWaived'] == true
          : message['restrictedWorkerPrincipal'] == true;
      if (message['executorOnly'] != true ||
          message['grantIssuer'] != false ||
          message['authenticatedIpcRequired'] != true ||
          message['desktopIssuedEffectPermitRequired'] != true ||
          message['publicVerifierOnly'] != true ||
          message['rawAuthorityKeysPresent'] != false ||
          !principalReady ||
          message['workerSessionId'] != _expectedWorkerSessionId ||
          message['pid'] != _workerIdentityValue['pid']) {
        if (!_ready.isCompleted) {
          _ready.completeError(
            const P2AutomationHostException('ready_contract_invalid'),
          );
        }
      } else if (!_ready.isCompleted) {
        _ready.complete();
      }
      return;
    }
    if (type == 'response') {
      final requestId = message['requestId']?.toString();
      final completer = requestId == null ? null : _pending.remove(requestId);
      if (completer != null) {
        final response = Map<String, Object?>.from(message)
          ..remove('type')
          ..remove('requestId');
        completer.complete(response);
      }
      return;
    }
    if (type == 'fatal') {
      _handleTransportError(
        P2AutomationHostException(
          message['code']?.toString() ?? 'automation_host_fatal',
          _safeDiagnostic(message['message']?.toString() ?? ''),
        ),
      );
      return;
    }
    if (!_events.isClosed) _events.add(message);
  }

  Map<String, Object?> _bindWorkerIdentityToResponse(
    Map<String, Object?> response,
  ) {
    final identity = _workerIdentityValue;
    if (identity.isEmpty) {
      throw const P2AutomationHostException(
        'restricted_worker_identity_missing',
      );
    }
    final copy = Map<String, Object?>.from(response)
      ..['restrictedWorkerIdentity'] = identity
      ..['restrictedWorkerIdentitySha256'] = identity['identitySha256'];
    final rawReceipt = copy['receipt'];
    if (rawReceipt is Map) {
      final receipt = Map<String, Object?>.from(rawReceipt);
      final details = receipt['details'] is Map
          ? Map<String, Object?>.from(receipt['details']! as Map)
          : <String, Object?>{};
      details['restrictedWorkerIdentity'] = identity;
      details['restrictedWorkerIdentitySha256'] = identity['identitySha256'];
      receipt['details'] = details;
      copy['receipt'] = receipt;
    }
    return Map<String, Object?>.unmodifiable(copy);
  }

  Map<String, Object?> _validateWorkerIdentity(Map<String, Object?> message) {
    final expectedPlatform = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
        ? 'macos'
        : 'linux';
    final ownerRiskQa =
        _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';
    final expectedPrincipal = ownerRiskQa
        ? 'owner-risk-current-account'
        : Platform.isWindows
        ? 'appcontainer'
        : Platform.isMacOS
        ? 'signed-app-sandbox-helper'
        : 'dedicated-uid';
    final pid = message['pid'];
    final startToken = message['startToken']?.toString() ?? '';
    if (message['schemaVersion'] != '2.0.0' ||
        message['platform'] != expectedPlatform ||
        message['principalType'] != expectedPrincipal ||
        message['sessionId'] != _expectedWorkerSessionId ||
        pid is! int ||
        pid <= 0 ||
        startToken.isEmpty ||
        message['launcherSha256'] != _config.restrictedWorkerLauncherSha256 ||
        message['nodeSha256'] != _config.nodeExecutableSha256 ||
        message['hostScriptSha256'] != _config.hostScriptSha256) {
      throw const P2AutomationHostException(
        'restricted_worker_identity_invalid',
      );
    }
    if (!ownerRiskQa &&
        Platform.isLinux &&
        (message['workerUid'] is! int ||
            message['workerGid'] is! int ||
            message['noNewPrivileges'] != true ||
            message['namespaceIsolation'] != true)) {
      throw const P2AutomationHostException('linux_worker_identity_invalid');
    }
    if (!ownerRiskQa &&
        Platform.isWindows &&
        ((message['workerSid']?.toString().isEmpty ?? true) ||
            message['jobObjectBound'] != true)) {
      throw const P2AutomationHostException('windows_worker_identity_invalid');
    }
    if (!ownerRiskQa &&
        Platform.isMacOS &&
        ((message['codeDirectoryHash']?.toString().isEmpty ?? true) ||
            message['appSandbox'] != true ||
            message['authorityClientEntitlement'] != false)) {
      throw const P2AutomationHostException('macos_worker_identity_invalid');
    }
    final denial = message['authorityConnectionDenied'];
    final denialCode = message['authorityDenialCode'];
    if (ownerRiskQa) {
      if (message['ownerRiskQa'] != true ||
          message['osIsolationWaived'] != true ||
          message['currentAccountAuthority'] != true ||
          denial != false ||
          denialCode != 'owner_risk_waived') {
        throw const P2AutomationHostException(
          'owner_risk_worker_waiver_invalid',
        );
      }
    } else if (denial != null &&
        (denial != true || denialCode != 'worker_principal_denied')) {
      throw const P2AutomationHostException(
        'restricted_worker_authority_denial_invalid',
      );
    }
    final unsignedIdentity = Map<String, Object?>.from(message)
      ..remove('type')
      ..remove('identitySha256')
      ..['workerPolicySha256'] = _config.workerPolicySha256;
    final identitySha256 = Sha256.text(p2CanonicalJson(unsignedIdentity));
    final supplied = message['identitySha256']?.toString();
    if (supplied != null && supplied.isNotEmpty && supplied != identitySha256) {
      throw const P2AutomationHostException(
        'restricted_worker_identity_digest_mismatch',
      );
    }
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      ...unsignedIdentity,
      'identitySha256': identitySha256,
    });
  }

  Map<String, Object?> _finalizeWorkerIdentity(Map<String, Object?> merged) {
    final ownerRiskQa =
        _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';
    if (ownerRiskQa) {
      if (merged['authorityConnectionDenied'] != false ||
          merged['authorityDenialCode'] != 'owner_risk_waived' ||
          merged['authorityDenialObservedBy'] != 'owner-risk-waiver' ||
          merged['ownerRiskQa'] != true ||
          merged['osIsolationWaived'] != true ||
          merged['currentAccountAuthority'] != true) {
        throw const P2AutomationHostException(
          'owner_risk_worker_waiver_unproved',
        );
      }
    } else if (merged['authorityConnectionDenied'] != true ||
        merged['authorityDenialCode'] != 'worker_principal_denied') {
      throw const P2AutomationHostException(
        'restricted_worker_authority_denial_unproved',
      );
    }
    final unsigned = Map<String, Object?>.from(merged)
      ..remove('identitySha256');
    final identitySha256 = Sha256.text(p2CanonicalJson(unsigned));
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      ...unsigned,
      'identitySha256': identitySha256,
    });
  }

  String _safeDiagnostic(String value) {
    if (RegExp(
      r'(secret|token|password|authorization|api.?key|private.?key|bearer)',
      caseSensitive: false,
    ).hasMatch(value)) {
      return '[REDACTED: credential-shaped diagnostic]';
    }
    return value.length <= 2048 ? value : value.substring(value.length - 2048);
  }

  void _handleTransportError(Object error, [StackTrace? stack]) {
    final failure = error is P2AutomationHostException
        ? error
        : const P2AutomationHostException('automation_host_transport_failed');
    if (!_workerIdentity.isCompleted) {
      _workerIdentity.completeError(failure, stack);
    }
    if (!_workerAuthorityDenial.isCompleted) {
      _workerAuthorityDenial.completeError(failure, stack);
    }
    if (!_challenge.isCompleted) _challenge.completeError(failure, stack);
    if (!_ready.isCompleted) _ready.completeError(failure, stack);
    _failAll(failure, stack);
  }

  void _handleDone() {
    if (!_closed && !_closing) {
      _handleTransportError(
        const P2AutomationHostException('automation_host_transport_closed'),
      );
    }
  }

  Future<void> _watchExit() async {
    final code = await _process.exitCode;
    if (!_closed && !_closing && code != 0) {
      _handleTransportError(
        P2AutomationHostException('automation_host_exited', '$code'),
      );
    }
  }

  void _failAll(Object error, [StackTrace? stack]) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    }
    _pending.clear();
  }
}
