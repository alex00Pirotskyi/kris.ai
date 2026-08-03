import 'dart:convert';
import 'dart:typed_data';

import 'crypto_utils.dart';
import 'signed_manifest_v2.dart';

final class SignedAuditCheckpointV1 {
  const SignedAuditCheckpointV1({
    required this.sequence,
    required this.eventCount,
    required this.previousCheckpointHash,
    required this.auditHeadHash,
    required this.keyId,
    required this.signatureHex,
  });

  final int sequence;
  final int eventCount;
  final String previousCheckpointHash;
  final String auditHeadHash;
  final String keyId;
  final String signatureHex;

  Map<String, Object?> body() => <String, Object?>{
    'schemaVersion': '1.0.0',
    'sequence': sequence,
    'eventCount': eventCount,
    'previousCheckpointHash': previousCheckpointHash,
    'auditHeadHash': auditHeadHash,
    'keyId': keyId,
  };

  Uint8List canonicalPayload() =>
      Uint8List.fromList(utf8.encode(canonicalJsonV2(body())));

  bool verifyWithPublicKeyHex(String publicKeyHex) => Ed25519Reference.verify(
    hexToBytesV2(publicKeyHex),
    canonicalPayload(),
    hexToBytesV2(signatureHex),
  );

  String checkpointHash() => Sha256.text(
    canonicalJsonV2(<String, Object?>{...body(), 'signature': signatureHex}),
  );
}

final class SignedAuditCheckpointVerifierV1 {
  const SignedAuditCheckpointVerifierV1();

  void verify(
    List<SignedAuditCheckpointV1> checkpoints,
    Map<String, String> publicKeys,
  ) {
    var previousSequence = 0;
    var previousEventCount = 0;
    var previousHash = '';
    for (final checkpoint in checkpoints) {
      if (checkpoint.sequence != previousSequence + 1) {
        throw const FormatException('checkpoint_reordered');
      }
      if (checkpoint.eventCount <= previousEventCount) {
        throw const FormatException('checkpoint_truncated');
      }
      if (checkpoint.previousCheckpointHash != previousHash) {
        throw const FormatException('checkpoint_chain_mismatch');
      }
      final publicKey = publicKeys[checkpoint.keyId];
      if (publicKey == null) {
        throw const FormatException('unknown_signer');
      }
      if (!checkpoint.verifyWithPublicKeyHex(publicKey)) {
        throw const FormatException('checkpoint_tampered');
      }
      previousHash = checkpoint.checkpointHash();
      previousSequence = checkpoint.sequence;
      previousEventCount = checkpoint.eventCount;
    }
  }
}
