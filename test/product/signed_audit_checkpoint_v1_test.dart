import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/signed_audit_checkpoint_v1.dart';
import 'package:kristin_local_agent/product/signed_manifest_v2.dart';

void main() {
  test('signed audit checkpoint verifies with external public key', () {
    final seed = hexToBytesV2(
      '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
    );
    final body = <String, Object?>{
      'schemaVersion': '1.0.0',
      'sequence': 1,
      'eventCount': 10,
      'previousCheckpointHash': '',
      'auditHeadHash':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'keyId': 'audit-root-1',
    };
    final signature = bytesToHexV2(
      Ed25519Reference.sign(seed, utf8.encode(canonicalJsonV2(body))),
    );
    final checkpoint = SignedAuditCheckpointV1(
      sequence: 1,
      eventCount: 10,
      previousCheckpointHash: '',
      auditHeadHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      keyId: 'audit-root-1',
      signatureHex: signature,
    );
    expect(
      checkpoint.verifyWithPublicKeyHex(
        bytesToHexV2(Ed25519Reference.publicKey(seed)),
      ),
      isTrue,
    );
    const SignedAuditCheckpointVerifierV1().verify(
      <SignedAuditCheckpointV1>[checkpoint],
      <String, String>{
        'audit-root-1':
            'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
      },
    );
  });

  test('reordered checkpoint sequences are rejected', () {
    const checkpoint = SignedAuditCheckpointV1(
      sequence: 2,
      eventCount: 10,
      previousCheckpointHash: '',
      auditHeadHash: 'a',
      keyId: 'audit-root-1',
      signatureHex: '00',
    );
    expect(
      () => const SignedAuditCheckpointVerifierV1().verify(
        <SignedAuditCheckpointV1>[checkpoint],
        const <String, String>{'audit-root-1': '00'},
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
