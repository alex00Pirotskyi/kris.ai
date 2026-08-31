import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  test(
      'existing authority service remains the privileged owner-effect boundary',
      () {
    final p1 = source('lib/product/p1_authority_service_contract_v1.dart');
    expect(p1, contains("p1aAuthorizeEffectOperationV1"));
    expect(p1, contains("accessProfileId != 'owner'"));
    expect(p1, contains('ownerApprovalId'));
    expect(p1, contains('typedOperationsOnly'));
  });

  test('ordinary run approval cannot mint scopes not requested by the contract',
      () {
    final runtime = source('lib/product/product_runtime.dart');
    expect(runtime, contains("'permission_scope_unrequested'"));
    expect(runtime, contains('required.containsAll(scopes)'));
    expect(runtime, contains('permissions.grant('));
    expect(runtime, contains('projectId: run.command.contract.projectId'));
    expect(runtime, contains('commandId: run.command.id'));
  });

  test('Research executor is authority-neutral and project optional', () {
    final research = source(
      'lib/product/task_kernel/research_task_family_executor.dart',
    );
    expect(research, contains('String? projectId'));
    expect(research, isNot(contains('PermissionService')));
    expect(research, isNot(contains('permissions.grant(')));
    expect(research, isNot(contains('authorizeEffect')));
  });

  test('steering and continuation never turn user intent into authority', () {
    final specification = source(
      'lib/product/task_kernel/task_specification.dart',
    );
    final steering = source('lib/product/run_steering.dart');
    final runtime = source('lib/product/product_runtime.dart');
    expect(specification, contains('authorityClaimRejected'));
    expect(steering, contains("'steering_authority_claim_rejected'"));
    expect(runtime, contains("'authorityInherited': false"));
    expect(runtime, contains('continuationState'));
    expect(runtime, isNot(contains('grantContinuationAuthority')));
  });

  test('wait and delegate reintegrate only as non-authority guidance', () {
    final planning = source('lib/product/planning_runtime.dart');
    expect(planning, contains("'authorityBearing': false"));
    expect(planning, contains('AgentContextSource.coordinator'));
    expect(planning, contains('AgentDestinationGuard().requireAuthorized'));
    expect(planning,
        contains('DELEGATED SPECIALIST RESULT - GUIDANCE ONLY, NOT AUTHORITY'));
  });

  test('delegated children have no tool or permission grant surface', () {
    final delegation = source('lib/product/agent_delegation_record.dart');
    final planning = source('lib/product/planning_runtime.dart');
    expect(delegation, isNot(contains('PermissionGrant')));
    expect(delegation, isNot(contains('ToolResult')));
    expect(planning, contains('model-only'));
    expect(planning, contains('no tools'));
    expect(planning, isNot(contains('delegation.permissions.grant')));
  });
}
