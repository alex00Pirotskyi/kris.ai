import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'p1_authority_service_contract_v1.dart';

typedef _AllocNative = Pointer<Void> Function(IntPtr);
typedef _AllocDart = Pointer<Void> Function(int);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);
typedef _CallNative = Int32 Function(Pointer<Uint8>, IntPtr);
typedef _CallDart = int Function(Pointer<Uint8>, int);
typedef _SizeNative = IntPtr Function();
typedef _SizeDart = int Function();
typedef _CopyNative = IntPtr Function(Pointer<Uint8>, IntPtr);
typedef _CopyDart = int Function(Pointer<Uint8>, int);
typedef _CloseNative = Void Function();
typedef _CloseDart = void Function();

final class P1AuthorityNativeConnectorV2
    implements P1AuthorityServiceConnectorV1 {
  const P1AuthorityNativeConnectorV2({required this.configurationPath});
  final String configurationPath;

  @override
  Future<P1AuthorityServiceClientV1> connect() async {
    final file = File(configurationPath);
    if (!file.isAbsolute || !file.existsSync()) {
      throw StateError('p1a_native_connector_configuration_missing');
    }
    final value = jsonDecode(await file.readAsString());
    if (value is! Map) {
      throw const FormatException('p1a_native_connector_configuration');
    }
    return P1AuthorityNativeClientV2.open(Map<String, Object?>.from(value));
  }
}

final class P1AuthorityNativeClientV2 implements P1AuthorityServiceClientV1 {
  P1AuthorityNativeClientV2._({
    required DynamicLibrary library,
    required this.endpoint,
    required this.provenance,
    required this.completionEligible,
    required int maxResponseBytes,
  })  : _maxResponseBytes = maxResponseBytes,
        _alloc = library.lookupFunction<_AllocNative, _AllocDart>(
          'p1a_connector_alloc',
        ),
        _free = library.lookupFunction<_FreeNative, _FreeDart>(
          'p1a_connector_free',
        ),
        _configure = library.lookupFunction<_CallNative, _CallDart>(
          'p1a_connector_configure',
        ),
        _request = library.lookupFunction<_CallNative, _CallDart>(
          'p1a_connector_request',
        ),
        _responseSize = library.lookupFunction<_SizeNative, _SizeDart>(
          'p1a_connector_response_size',
        ),
        _copyResponse = library.lookupFunction<_CopyNative, _CopyDart>(
          'p1a_connector_copy_response',
        ),
        _closeNative = library.lookupFunction<_CloseNative, _CloseDart>(
          'p1a_connector_close',
        );

  @override
  final P1AuthorityServiceEndpointV1 endpoint;
  @override
  final Map<String, Object?> provenance;
  @override
  final bool completionEligible;
  final int _maxResponseBytes;
  final _AllocDart _alloc;
  final _FreeDart _free;
  final _CallDart _configure;
  final _CallDart _request;
  final _SizeDart _responseSize;
  final _CopyDart _copyResponse;
  final _CloseDart _closeNative;
  final Random _random = Random.secure();
  String? _workerSessionId;
  String? _channelId;
  int _revocationEpoch = 0;
  bool _closed = false;

  static Future<P1AuthorityNativeClientV2> open(
    Map<String, Object?> config,
  ) async {
    if (config['schemaVersion'] != '2.0.0') {
      throw const FormatException('p1a_native_connector_config_version');
    }
    final libraryPath = config['connectorLibraryPath']?.toString() ?? '';
    final libraryFile = File(libraryPath);
    if (!libraryFile.isAbsolute || !libraryFile.existsSync()) {
      throw StateError('p1a_native_connector_library_missing');
    }
    final endpointRaw = config['endpoint'];
    final provenanceRaw = config['provenance'];
    if (endpointRaw is! Map || provenanceRaw is! Map) {
      throw const FormatException('p1a_native_connector_identity_missing');
    }
    final endpoint = P1AuthorityServiceEndpointV1.fromJson(
      Map<String, Object?>.from(endpointRaw),
    )..validate();
    final maxResponseBytes = config['maxResponseBytes'] is int
        ? config['maxResponseBytes']! as int
        : 4 * 1024 * 1024;
    if (maxResponseBytes < 65536 || maxResponseBytes > 16 * 1024 * 1024) {
      throw StateError('p1a_native_connector_response_budget_invalid');
    }
    final client = P1AuthorityNativeClientV2._(
      library: DynamicLibrary.open(libraryPath),
      endpoint: endpoint,
      provenance: Map<String, Object?>.unmodifiable(
        Map<String, Object?>.from(provenanceRaw),
      ),
      completionEligible: config['completionEligible'] == true,
      maxResponseBytes: maxResponseBytes,
    );
    client._invokeNative(client._configure, <String, Object?>{
      'schemaVersion': '2.0.0',
      'address': endpoint.address,
      'maxResponseBytes': maxResponseBytes,
    });
    final described = client._requestJson(<String, Object?>{
      'schemaVersion': '2.0.0',
      'operation': p1aPublicVerifierBootstrapOperationV1,
    });
    if (described['status'] != 'ok' ||
        described['serviceInstanceId'] != endpoint.serviceInstanceId ||
        described['policySnapshotSha256'] !=
            provenanceRaw['policySnapshotSha256'] ||
        described['keyProvider'] is! Map) {
      client._closeNative();
      throw StateError('p1a_native_connector_service_identity_mismatch');
    }
    client._revocationEpoch = described['revocationEpoch'] is int
        ? described['revocationEpoch']! as int
        : -1;
    if (client._revocationEpoch < 0) {
      client._closeNative();
      throw StateError('p1a_native_connector_revocation_state_invalid');
    }
    return client;
  }

  String _id(String prefix) {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    return '$prefix-${bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';
  }

  Map<String, Object?> _requestJson(Map<String, Object?> request) {
    if (_closed) {
      throw StateError('p1a_native_connector_closed');
    }
    return _invokeNative(_request, request);
  }

  Map<String, Object?> _invokeNative(
    _CallDart function,
    Map<String, Object?> request,
  ) {
    final input = utf8.encode(p1aCanonicalJson(request));
    final inputPointer = _alloc(input.length).cast<Uint8>();
    if (inputPointer.address == 0) {
      throw StateError('p1a_native_connector_allocation_failed');
    }
    try {
      inputPointer.asTypedList(input.length).setAll(0, input);
      final status = function(inputPointer, input.length);
      final size = _responseSize();
      if (size <= 0 || size > _maxResponseBytes) {
        throw StateError('p1a_native_connector_response_size_invalid');
      }
      final outputPointer = _alloc(size).cast<Uint8>();
      if (outputPointer.address == 0) {
        throw StateError('p1a_native_connector_allocation_failed');
      }
      try {
        final copied = _copyResponse(outputPointer, size);
        if (copied != size) {
          throw StateError('p1a_native_connector_response_copy_failed');
        }
        final decoded = jsonDecode(
          utf8.decode(outputPointer.asTypedList(size)),
        );
        if (decoded is! Map) {
          throw const FormatException('p1a_native_connector_response');
        }
        final response = Map<String, Object?>.from(decoded);
        if (status != 0 ||
            response['status'] == 'denied' ||
            response['status'] == 'transport-error') {
          throw StateError(
            'p1a_authority_denied:${response['errorCode'] ?? 'unknown'}',
          );
        }
        return response;
      } finally {
        _free(outputPointer.cast<Void>());
      }
    } finally {
      inputPointer.asTypedList(input.length).fillRange(0, input.length, 0);
      _free(inputPointer.cast<Void>());
    }
  }

  @override
  Future<Map<String, Object?>> workerVerifierBootstrap() async {
    final described = _requestJson(<String, Object?>{
      'schemaVersion': '2.0.0',
      'operation': p1aPublicVerifierBootstrapOperationV1,
    });
    final provider = described['keyProvider'];
    if (provider is! Map) {
      throw StateError('p1a_key_provider_description_missing');
    }
    final key = Map<String, Object?>.from(provider);
    if (key['algorithm'] != 'ecdsa-p256-sha256' ||
        key['nonExportable'] != true ||
        key['privateExportDenied'] != true ||
        (key['publicKeySpkiBase64']?.toString() ?? '').length < 80) {
      throw StateError('p1a_key_provider_ineligible');
    }
    _workerSessionId = _id('worker-session');
    _channelId = _id('authority-channel');
    _revocationEpoch = described['revocationEpoch']! as int;
    return <String, Object?>{
      'schemaVersion': '4.0.0',
      'verificationMode': 'ecdsa-p256-public-only',
      'permitVerifier': <String, Object?>{
        'algorithm': key['algorithm'],
        'keyId': key['keyId'],
        'publicKeySpkiBase64': key['publicKeySpkiBase64'],
        'providerAttestationSha256': key['providerAttestationSha256'],
      },
      'channelId': _channelId,
      'workerSessionId': _workerSessionId,
      'authorityState': <String, Object?>{
        'revocationEpoch': _revocationEpoch,
        'authoritativeStateVersion': 0,
        'authoritativeGrantUses': const <String, int>{},
        'authoritativeConsumedRequestIds': const <String>[],
        'revokedGrantIds': const <String>[],
      },
      'workerCanIssue': false,
      'privateSigningMaterialPresent': false,
      'symmetricSigningMaterialPresent': false,
      'rawAuthoritySecretsReturned': false,
      'serviceInstanceId': endpoint.serviceInstanceId,
      'serviceBuildSha256': endpoint.serviceBuildSha256,
    };
  }

  @override
  Future<Map<String, Object?>> recordOwnerApproval(
    P1AuthorityOwnerApprovalRequestV2 request,
  ) async {
    final now = DateTime.now().toUtc();
    request.validate(now);
    final response = _requestJson(request.toJson());
    if (response['status'] != 'recorded' || response['approval'] is! Map) {
      throw StateError('p1a_owner_approval_not_recorded');
    }
    return response;
  }

  @override
  Future<P1AuthorityEffectPermitV1> authorizeEffect(
    P1AuthorityEffectRequestV1 request,
  ) async {
    final workerSessionId = _workerSessionId;
    final channelId = _channelId;
    if (workerSessionId == null ||
        channelId == null ||
        request.workerSessionId != workerSessionId ||
        request.channelId != channelId) {
      throw StateError('p1a_worker_session_not_open');
    }
    final response = _requestJson(request.toJson());
    return P1AuthorityEffectPermitV1.fromJson(response);
  }

  @override
  Future<Map<String, Object?>> recordEffectOutcome(
    P1AuthorityEffectOutcomeV1 outcome,
  ) async =>
      _requestJson(outcome.toJson());

  @override
  Future<Map<String, Object?>> beginBehaviorSessionForEvidence({
    required String behaviorSessionId,
    required String exactRunBindingSha256,
  }) async =>
      _requestJson(<String, Object?>{
        'schemaVersion': '2.0.0',
        'operation': p1aBeginBehaviorSessionOperationV2,
        'behaviorSessionId': behaviorSessionId,
        'exactRunBindingSha256': exactRunBindingSha256,
      });

  @override
  Future<Map<String, Object?>> finalizeBehaviorSessionForEvidence({
    required String behaviorSessionId,
    required String exactRunBindingSha256,
  }) async =>
      _requestJson(<String, Object?>{
        'schemaVersion': '2.0.0',
        'operation': p1aFinalizeBehaviorSessionOperationV2,
        'behaviorSessionId': behaviorSessionId,
        'exactRunBindingSha256': exactRunBindingSha256,
      });

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _closeNative();
  }

  @override
  String toString() =>
      'P1AuthorityNativeClientV2(${endpoint.platform}, [PROTECTED])';
}
