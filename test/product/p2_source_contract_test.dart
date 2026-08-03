import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<String> _discover(String directory, RegExp pattern) {
  final root = Directory(directory);
  if (!root.existsSync()) return const <String>[];
  return root
      .listSync(followLinks: false)
      .whereType<File>()
      .map((file) => file.path.replaceAll('\\', '/'))
      .where((path) => pattern.hasMatch(path.split('/').last))
      .toList()
    ..sort();
}

void main() {
  test('P2 governed source inventory exactly matches discovered sources', () {
    final inventoryFile = File('config/p2_source_inventory.v1.json');
    expect(inventoryFile.existsSync(), isTrue);
    final value = jsonDecode(inventoryFile.readAsStringSync());
    expect(value, isA<Map<String, Object?>>());
    final inventory = Map<String, Object?>.from(value as Map);
    final production =
        (inventory['productionDart'] as List<Object?>)
            .map((item) => item.toString().replaceAll('\\', '/'))
            .toList()
          ..sort();
    final tests =
        (inventory['testDart'] as List<Object?>)
            .map((item) => item.toString().replaceAll('\\', '/'))
            .toList()
          ..sort();

    final discoveredProduction = _discover(
      'lib/product',
      RegExp(r'^p2_.*\.dart$'),
    );
    final discoveredTests = _discover('test/product', RegExp(r'^p2_.*\.dart$'));

    expect(discoveredProduction, production);
    expect(discoveredTests, tests);

    final dependencies = (inventory['requiredMergedP1aFiles'] as List<Object?>)
        .map((item) => item.toString())
        .toList(growable: false);
    for (final dependency in dependencies) {
      expect(File(dependency).existsSync(), isTrue, reason: dependency);
    }
    expect(production.toSet().length, production.length);
    expect(tests.toSet().length, tests.length);
    for (final path in <String>[...production, ...tests]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });
}
