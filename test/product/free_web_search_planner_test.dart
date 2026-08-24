import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/planning_runtime.dart';

void main() {
  final project = ProjectRecord(
    id: 'search-permission-project',
    name: 'Search permission project',
    rootPath: Directory.current.path,
    createdAt: DateTime.utc(2026, 8, 24),
    updatedAt: DateTime.utc(2026, 8, 24),
  );
  final model = ModelIdentity(
    providerId: 'ollama',
    name: 'test-model',
    digest: 'sha256:test',
    discoveredAt: DateTime.utc(2026, 8, 24),
  );

  test('ordinary web research does not request secret authority', () {
    final prepared = const ContractPlanner().prepare(
      project: project,
      mode: CommandMode.analyze,
      request: 'Research current documentation online',
      model: model,
    );

    expect(
      prepared.contract.requiredPermissions,
      contains(PermissionScope.networkResearch),
    );
    expect(
      prepared.contract.requiredPermissions,
      isNot(contains(PermissionScope.secretUse)),
    );
  });

  test('explicit API-key research still requests secret authority', () {
    final prepared = const ContractPlanner().prepare(
      project: project,
      mode: CommandMode.analyze,
      request: 'Research current documentation online using an API key',
      model: model,
    );

    expect(
      prepared.contract.requiredPermissions,
      containsAll(<PermissionScope>{
        PermissionScope.networkResearch,
        PermissionScope.secretUse,
      }),
    );
  });
}
