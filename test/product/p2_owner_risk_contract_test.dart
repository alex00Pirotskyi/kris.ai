import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owner-risk QA mode is explicit and never overclaims security', () {
    final config = File(
      'config/p1_p2_owner_risk_qa.v1.json',
    ).readAsStringSync();
    final authority = File(
      'lib/product/p2_owner_risk_authority.dart',
    ).readAsStringSync();
    final bootstrap = File(
      'lib/product/p2_product_runtime_bootstrap.dart',
    ).readAsStringSync();
    final host = File(
      'automation_host/src/authenticated-ipc.mjs',
    ).readAsStringSync();
    expect(config, contains('"formalSecurityCompletion": false'));
    expect(config, contains('"productionReleaseEligible": false'));
    expect(config, contains('"qaShipmentEligibleAfterTriPlatformPass": true'));
    expect(authority, contains("'securityEvidenceWaived': true"));
    expect(
      authority,
      contains("authorityKind => 'p2-owner-risk-current-account-v1'"),
    );
    expect(authority, contains("'authorityDenialCode': 'owner_risk_waived'"));
    expect(authority, contains('bool get completionEligible => false'));
    expect(bootstrap, contains("'KRISTIN_OWNER_RISK_QA': '1'"));
    expect(host, contains("process.env.KRISTIN_OWNER_RISK_QA !== '1'"));
  });
}
