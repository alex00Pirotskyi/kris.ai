import 'dart:convert';

final class LocalIpcEnvelopeV1 {
  LocalIpcEnvelopeV1({
    required this.peerId,
    required this.requestId,
    required this.deadline,
    required this.body,
    required this.mac,
    this.schemaVersion = '1.0.0',
  }) {
    if (schemaVersion != '1.0.0') {
      throw const FormatException('ipc_version');
    }
    if (peerId.isEmpty) {
      throw const FormatException('ipc_peer_id');
    }
    if (requestId.isEmpty) {
      throw const FormatException('ipc_request_id');
    }
    if (deadline.isBefore(DateTime.now().toUtc())) {
      throw const FormatException('ipc_expired');
    }
    if (utf8.encode(jsonEncode(body)).length > 65536) {
      throw const FormatException('ipc_payload_limit');
    }
    if (mac.length != 64) {
      throw const FormatException('ipc_auth_failed');
    }
  }

  final String schemaVersion;
  final String peerId;
  final String requestId;
  final DateTime deadline;
  final Map<String, Object?> body;
  final String mac;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'peerId': peerId,
    'requestId': requestId,
    'deadline': deadline.toUtc().toIso8601String(),
    'body': body,
    'mac': mac,
  };
}

final class LocalIpcTransportPolicyV1 {
  const LocalIpcTransportPolicyV1();

  static const Map<String, List<String>> transports = <String, List<String>>{
    'windows': <String>['named_pipe', 'authenticated_loopback_mutual_auth'],
    'macos': <String>[
      'unix_domain_socket',
      'authenticated_loopback_mutual_auth',
    ],
    'linux': <String>[
      'unix_domain_socket',
      'authenticated_loopback_mutual_auth',
    ],
  };

  bool get requiresMutualAuthentication => true;
  bool get requiresPeerIdentity => true;
  bool get requiresRequestId => true;
  bool get requiresDeadline => true;
  bool get requiresPayloadLimits => true;
  bool get requiresReplayProtection => true;
}
