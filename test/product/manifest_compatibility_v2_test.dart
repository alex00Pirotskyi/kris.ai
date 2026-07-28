import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/manifest_compatibility_v2.dart';

void main() {
  const compatibility = ManifestCompatibilityV2();

  test('v1 remains rejected', () {
    expect(
      () => compatibility.classify(
        <String, Object?>{'schemaVersion': '1.0.0'},
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('mixed v1 and v2 trust fields are rejected', () {
    expect(
      () => compatibility.classify(<String, Object?>{
        'schemaVersion': '2.0.0',
        'hmac': 'attacker-controlled',
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('clean v2 envelope is classified', () {
    expect(
      compatibility.classify(
        <String, Object?>{'schemaVersion': '2.0.0'},
      ),
      'signed_manifest_v2',
    );
  });
}
