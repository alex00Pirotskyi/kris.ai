import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/key_registry_v2.dart';

void main() {
  test('protected registry serializes handles, never private material', () {
    final registry = ProtectedKeyRegistryV2();
    registry.register(
      const ProtectedKeyHandleV2(
        keyId: 'manifest-root-1',
        purpose: 'manifest_signing',
        provider: 'ephemeral_test',
        reference: 'vault://test/manifest-root-1',
        publicKeyHex:
            'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
        trustDomain: 'kristin.test',
      ),
    );
    final encoded = jsonEncode(registry.exportPublicRegistry()).toLowerCase();
    expect(encoded, contains('vault://test/manifest-root-1'));
    expect(encoded, isNot(contains('privatekey')));
    expect(encoded, isNot(contains('seed')));
    expect(encoded, isNot(contains('secret=')));
  });

  test('revoked keys fail closed', () {
    final registry = ProtectedKeyRegistryV2();
    registry.register(
      const ProtectedKeyHandleV2(
        keyId: 'manifest-root-1',
        purpose: 'manifest_signing',
        provider: 'ephemeral_test',
        reference: 'vault://test/manifest-root-1',
        publicKeyHex: '00',
        trustDomain: 'kristin.test',
      ),
    );
    registry.revoke('manifest-root-1');
    expect(
      () => registry.resolve(
        'manifest-root-1',
        purpose: 'manifest_signing',
        trustDomain: 'kristin.test',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
