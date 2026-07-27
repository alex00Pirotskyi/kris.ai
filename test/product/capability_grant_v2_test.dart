import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/capability_grant_v2.dart';

void main() {
  Map<String, dynamic> fixture() {
    final path = [
      Directory.current.path,
      'evals',
      'fixtures',
      'p1_003_capability_grants',
      'vectors.json',
    ].join(Platform.pathSeparator);
    return Map<String, dynamic>.from(
      jsonDecode(File(path).readAsStringSync()) as Map,
    );
  }

  test('Capability Grant v2 round-trips without issuer key material', () {
    final source = Map<String, dynamic>.from(fixture()['validGrant'] as Map);
    final grant = CapabilityGrantV2.fromJson(source);
    expect(grant.toJson(), source);
    expect(grant.requiresWorkerAuthentication, isTrue);
    expect(grant.canonicalSigningPayload(), isNot(contains('"mac"')));
    final encoded = jsonEncode(grant.toJson());
    expect(encoded, isNot(contains('fixture-only-not-a-secret')));
    expect(encoded, isNot(contains('keyMaterial')));
  });

  test('Capability Grant v2 requires exact binding and scope domains', () {
    final source = Map<String, dynamic>.from(fixture()['validGrant'] as Map);
    final binding = Map<String, dynamic>.from(source['binding'] as Map)
      ..remove('runId');
    source['binding'] = binding;
    expect(
      () => CapabilityGrantV2.fromJson(source),
      throwsA(isA<CapabilityGrantValidationException>()),
    );
  });

  test('Capability Grant v2 forbids raw secret reveal', () {
    final source = Map<String, dynamic>.from(fixture()['validGrant'] as Map);
    final scope = Map<String, dynamic>.from(source['scope'] as Map);
    scope['secrets'] = Map<String, dynamic>.from(scope['secrets'] as Map)
      ..['rawReveal'] = true;
    source['scope'] = scope;
    expect(
      () => CapabilityGrantV2.fromJson(source),
      throwsA(isA<CapabilityGrantValidationException>()),
    );
  });
}
