import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/access_profile_v2.dart';

Map<String, dynamic> _copy(Map<String, dynamic> value) {
  return jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
}

void _patch(Map<String, dynamic> target, String dotted, Object? value) {
  final parts = dotted.split('.');
  var current = target;
  for (final part in parts.take(parts.length - 1)) {
    current = (current[part] as Map).cast<String, dynamic>();
  }
  current[parts.last] = value;
}

void main() {
  final root = Directory.current;
  final catalog =
      jsonDecode(
            File(
              '${root.path}/config/access_profiles.v2.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final rawProfiles = (catalog['profiles'] as List).cast<Map>();
  final byId = <String, Map<String, dynamic>>{
    for (final raw in rawProfiles)
      raw['profileId'] as String: raw.cast<String, dynamic>(),
  };

  test('canonical profiles round-trip in Dart', () {
    expect(byId.keys.toSet(), <String>{
      'chat',
      'project',
      'owner',
      'owner_unattended',
      'isolated_untrusted',
    });
    for (final raw in byId.values) {
      final first = AccessProfileV2.fromJson(_copy(raw));
      final second = AccessProfileV2.fromJson(first.toJson());
      expect(
        second.toJson(),
        first.toJson(),
        reason: raw['profileId'] as String,
      );
    }
  });

  test('shared invalid policy vectors fail in Dart', () {
    final fixture =
        jsonDecode(
              File(
                '${root.path}/evals/fixtures/p1_002_access_profiles/invalid_cases.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    for (final rawCase in fixture['cases'] as List) {
      final testCase = (rawCase as Map).cast<String, dynamic>();
      final value = _copy(byId[testCase['baseProfile']]!);
      for (final entry in (testCase['patch'] as Map).entries) {
        _patch(value, entry.key.toString(), entry.value);
      }
      expect(
        () => AccessProfileV2.fromJson(value),
        throwsA(
          isA<AccessProfileValidationException>().having(
            (error) => error.message,
            'message',
            contains(testCase['errorContains'] as String),
          ),
        ),
        reason: testCase['name'] as String,
      );
    }
  });

  test('Owner and Owner unattended remain explicit non-sandbox modes', () {
    final owner = AccessProfileV2.fromJson(_copy(byId['owner']!));
    final unattended = AccessProfileV2.fromJson(
      _copy(byId['owner_unattended']!),
    );
    expect(owner.sandboxed, isFalse);
    expect(owner.credentials['rawReveal'], 'interactive_break_glass');
    expect(unattended.sandboxed, isFalse);
    expect(unattended.credentials['rawReveal'], 'never');
    expect(unattended.process['elevation'], 'none');
  });
}
