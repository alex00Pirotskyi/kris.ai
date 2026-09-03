import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/deterministic_policy_engine.dart';

void main() {
  Map<String, dynamic> readJson(String relative) {
    final path = <String>[
      Directory.current.path,
      ...relative.split('/'),
    ].join(Platform.pathSeparator);
    return Map<String, dynamic>.from(
      jsonDecode(File(path).readAsStringSync()) as Map,
    );
  }

  late DeterministicPolicyEngineV2 engine;
  late Map<String, dynamic> fixture;

  setUpAll(() {
    engine = DeterministicPolicyEngineV2(
      accessCatalog: readJson('config/access_profiles.v2.json'),
      policyConfig: readJson('config/policy_engine.v2.json'),
    );
    fixture = readJson(
      'evals/fixtures/p1_004_policy_engine/property_cases.json',
    );
  });

  test('shared deterministic policy cases match in Dart', () {
    final selected = Set<String>.from(fixture['dartCaseNames'] as List);
    for (final raw in fixture['cases'] as List) {
      final item = Map<String, dynamic>.from(raw as Map);
      if (!selected.contains(item['name'])) {
        continue;
      }
      final result = engine.evaluate(
        Map<String, dynamic>.from(item['request'] as Map),
      );
      expect(
        result['status'],
        item['expectedStatus'],
        reason: item['name'].toString(),
      );
      final reasons = Set<String>.from(result['reasonCodes'] as List);
      expect(
        reasons,
        containsAll(item['expectedReasons'] as List),
        reason: item['name'].toString(),
      );
    }
  });

  test('overlay ordering produces byte-equivalent decisions', () {
    final raw = (fixture['cases'] as List).cast<Map>().firstWhere(
      (item) => item['name'] == 'overlay_order_reference',
    );
    final request = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(raw['request'])) as Map,
    );
    final forward = engine.evaluate(request);
    request['overlays'] = (request['overlays'] as List).reversed.toList(
      growable: false,
    );
    final reverse = engine.evaluate(request);
    expect(reverse, forward);
  });

  test('model text cannot approve or widen authority', () {
    final raw = (fixture['cases'] as List).cast<Map>().firstWhere(
      (item) => item['name'] == 'model_cannot_approve',
    );
    final result = engine.evaluate(
      Map<String, dynamic>.from(raw['request'] as Map),
    );
    expect(result['status'], 'deny');
    expect(result['reasonCodes'], contains('untrusted_authority_source'));
  });

  test('effective budgets are monotonic narrowing', () {
    final raw = (fixture['cases'] as List).cast<Map>().firstWhere(
      (item) => item['name'] == 'project_write_inside_root',
    );
    final source = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(raw['request'])) as Map,
    );
    final baseline = Map<String, dynamic>.from(
      engine.evaluate(source)['effectiveBudgets'] as Map,
    );
    source['overlays'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'layer': 'project',
        'overlayId': 'budget',
        'maxBudgets': <String, dynamic>{'maxMutations': 1},
      },
    ];
    final narrowed = Map<String, dynamic>.from(
      engine.evaluate(source)['effectiveBudgets'] as Map,
    );
    expect(
      narrowed['maxMutations'],
      lessThanOrEqualTo(baseline['maxMutations'] as int),
    );
    expect(narrowed['maxMutations'], 1);
  });
}
