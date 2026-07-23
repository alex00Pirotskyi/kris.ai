import 'package:flutter_test/flutter_test.dart';

import 'package:kristin_local_agent/product/interoperability_v19.dart';

void main() {
  test('signed manifest encodes required fields', () {
    final envelope = SignedManifestEnvelope(
      manifestType: 'plugin',
      manifest: const <String, dynamic>{'id': 'mock'},
      manifestSha256: 'a' * 64,
      signature: 'sig',
      signerKeyId: 'test',
      signerPublicKey: 'pub',
      signedAt: DateTime.utc(2026, 7, 23),
    );
    expect(encodeSignedManifest(envelope), contains('manifestType'));
  });
}
