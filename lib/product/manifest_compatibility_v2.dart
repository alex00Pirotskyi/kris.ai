final class ManifestCompatibilityV2 {
  const ManifestCompatibilityV2();

  String classify(Map<String, Object?> envelope) {
    final version = envelope['schemaVersion']?.toString() ?? '';
    if (const <String>{'1', '1.0', '1.0.0', 'v1'}.contains(version)) {
      throw const FormatException('v1_trust_disabled');
    }
    if (version != '2.0.0') {
      throw const FormatException('unsupported_manifest_version');
    }
    for (final field in const <String>{
      'hmac',
      'secret',
      'keyMaterial',
      'signingKey',
      'algorithm',
    }) {
      if (envelope.containsKey(field)) {
        throw const FormatException('mixed_format_rejected');
      }
    }
    return 'signed_manifest_v2';
  }
}
