enum ProtectedKeyStatus { active, revoked }

final class ProtectedKeyHandleV2 {
  const ProtectedKeyHandleV2({
    required this.keyId,
    required this.purpose,
    required this.provider,
    required this.reference,
    required this.publicKeyHex,
    required this.trustDomain,
    this.status = ProtectedKeyStatus.active,
  });

  final String keyId;
  final String purpose;
  final String provider;
  final String reference;
  final String publicKeyHex;
  final String trustDomain;
  final ProtectedKeyStatus status;

  Map<String, Object?> toPublicJson() => <String, Object?>{
    'keyId': keyId,
    'purpose': purpose,
    'provider': provider,
    'reference': reference,
    'publicKeyHex': publicKeyHex,
    'trustDomain': trustDomain,
    'status': status.name,
  };

  ProtectedKeyHandleV2 revoke() => ProtectedKeyHandleV2(
    keyId: keyId,
    purpose: purpose,
    provider: provider,
    reference: reference,
    publicKeyHex: publicKeyHex,
    trustDomain: trustDomain,
    status: ProtectedKeyStatus.revoked,
  );
}

final class ProtectedKeyRegistryV2 {
  final Map<String, ProtectedKeyHandleV2> _handles =
      <String, ProtectedKeyHandleV2>{};

  void register(ProtectedKeyHandleV2 handle) {
    if (_handles.containsKey(handle.keyId)) {
      throw const FormatException('duplicate_key_id');
    }
    if (!const <String>{
      'windows_credential_manager',
      'macos_keychain',
      'linux_secret_service',
      'external_hsm',
      'ephemeral_test',
    }.contains(handle.provider)) {
      throw const FormatException('unsupported_provider');
    }
    final normalized = handle.reference.toLowerCase();
    if (handle.reference.isEmpty ||
        const <String>{
          'privatekey=',
          'seed=',
          'secret=',
          'keymaterial=',
        }.any(normalized.contains)) {
      throw const FormatException('invalid_reference');
    }
    _handles[handle.keyId] = handle;
  }

  ProtectedKeyHandleV2 resolve(
    String keyId, {
    required String purpose,
    required String trustDomain,
  }) {
    final handle = _handles[keyId];
    if (handle == null) {
      throw const FormatException('unknown_key');
    }
    if (handle.status != ProtectedKeyStatus.active) {
      throw const FormatException('key_revoked');
    }
    if (handle.purpose != purpose) {
      throw const FormatException('wrong_key_purpose');
    }
    if (handle.trustDomain != trustDomain) {
      throw const FormatException('wrong_trust_domain');
    }
    return handle;
  }

  void revoke(String keyId) {
    final handle = _handles[keyId];
    if (handle == null) {
      throw const FormatException('unknown_key');
    }
    _handles[keyId] = handle.revoke();
  }

  List<Map<String, Object?>> exportPublicRegistry() => <Map<String, Object?>>[
    for (final key in (_handles.keys.toList()..sort()))
      _handles[key]!.toPublicJson(),
  ];
}
