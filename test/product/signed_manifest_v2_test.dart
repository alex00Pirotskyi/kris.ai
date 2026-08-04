import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/signed_manifest_v2.dart';

void main() {
  test('RFC 8032 Ed25519 vector passes in Dart', () {
    final seed = hexToBytesV2(
      '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
    );
    final publicKey = Ed25519Reference.publicKey(seed);
    expect(
      bytesToHexV2(publicKey),
      'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
    );
    final signature = Ed25519Reference.sign(seed, const <int>[]);
    expect(
      bytesToHexV2(signature),
      'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
      '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
    );
    expect(
      Ed25519Reference.verify(publicKey, const <int>[], signature),
      isTrue,
    );
  });

  test('Signed Manifest v2 canonical vector matches Python', () {
    final body = <String, Object?>{
      'schemaVersion': '2.0.0',
      'keyId': 'p1-test-root',
      'intendedUse': 'extension_manifest',
      'trustDomain': 'kristin.test',
      'issuedAt': '2026-07-28T00:00:00Z',
      'expiresAt': '2026-07-29T00:00:00Z',
      'payload': <String, Object?>{
        'artifactId': 'plugin.example',
        'digest':
            'sha256:1111111111111111111111111111111111111111111111111111111111111111',
        'version': '1.0.0',
        'capabilities': <String>['filesystem.read'],
        'publisher': 'builtin.kristin',
      },
    };
    final canonical = canonicalJsonV2(body);
    expect(
      canonical,
      '{"expiresAt":"2026-07-29T00:00:00Z","intendedUse":"extension_manifest",'
      '"issuedAt":"2026-07-28T00:00:00Z","keyId":"p1-test-root","payload":'
      '{"artifactId":"plugin.example","capabilities":["filesystem.read"],'
      '"digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111",'
      '"publisher":"builtin.kristin","version":"1.0.0"},"schemaVersion":"2.0.0",'
      '"trustDomain":"kristin.test"}',
    );
    final seed = hexToBytesV2(
      '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
    );
    final signature = Ed25519Reference.sign(seed, utf8.encode(canonical));
    expect(
      bytesToHexV2(signature),
      'b6a04dd30a21b94a7f852f09f531581ce5e511f41b882cdc56c0486137abb2a8'
      '4957fd359c26f8fdb5862af54a6539a68c3423504fe16203389e0a4c389b460a',
    );
  });

  test('Signed manifest carries no private key material', () {
    final manifest = SignedManifestV2.fromJson(<String, Object?>{
      'schemaVersion': '2.0.0',
      'keyId': 'p1-test-root',
      'intendedUse': 'extension_manifest',
      'trustDomain': 'kristin.test',
      'issuedAt': '2026-07-28T00:00:00Z',
      'expiresAt': '2026-07-29T00:00:00Z',
      'payload': <String, Object?>{'artifactId': 'plugin.example'},
      'signature': List<String>.filled(64, '00').join(),
    });
    final encoded = jsonEncode(manifest.toJson()).toLowerCase();
    expect(encoded, isNot(contains('privatekey')));
    expect(encoded, isNot(contains('keymaterial')));
    expect(encoded, isNot(contains('seed')));
  });
}
