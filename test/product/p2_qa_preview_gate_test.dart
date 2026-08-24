import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QA preview bridge is explicit and formally ineligible', () {
    final contract = File('config/p2_qa_preview.v1.json').readAsStringSync();
    final adapter = File(
      'lib/product/p2_p1_authority_adapter.dart',
    ).readAsStringSync();
    final p1a = File(
      'lib/product/p1_authority_service_contract_v1.dart',
    ).readAsStringSync();
    final shell = File('lib/product/p2_app_shell.dart').readAsStringSync();
    final runtime = File(
      'lib/product/p2_product_runtime_integration.dart',
    ).readAsStringSync();
    final bootstrap = File(
      'lib/product/p2_product_runtime_bootstrap.dart',
    ).readAsStringSync();
    expect(contract, contains('"formalCompletion": false'));
    expect(contract, contains('"mergeEligible": false'));
    expect(adapter, contains("'qaPreviewFormalCompletion': false"));
    expect(adapter, contains('bool get qaPreview => _qaPreview'));
    expect(p1a, contains('allowQaPreview'));
    expect(runtime, contains('final secureP1aAuthority ='));
    expect(runtime, contains('final ownerRiskAuthority ='));
    expect(runtime, contains('secureP1aAuthority || ownerRiskAuthority'));
    expect(
      runtime,
      contains("authority.authorityKind == 'p1-isolated-authority-service-v2'"),
    );
    expect(
      runtime,
      contains("authority.authorityProvenance['runtimeEligible'] == true"),
    );
    expect(
      runtime,
      contains("authority.authorityProvenance['secureIsolationActive'] != false"),
    );
    expect(
      runtime,
      contains("authority.authorityKind == 'p2-owner-risk-current-account-v1'"),
    );
    expect(runtime, contains('productionCertificationComplete'));
    expect(bootstrap, contains('allowQaPreview: qaPreview'));
    expect(shell, contains('OWNER-RISK QA — SECURITY EVIDENCE WAIVED'));
  });
}
