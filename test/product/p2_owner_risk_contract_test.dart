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
    final commandService = File(
      'lib/product/p2_automation_command_service.dart',
    ).readAsStringSync();
    final packagePlatform = File(
      'tool/v70_package_platform.py',
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
    expect(commandService, contains("response['code']"));
    expect(commandService, contains("response['message']"));
    expect(packagePlatform, contains('windows_only_conpty'));
    expect(packagePlatform, contains('shutil.rmtree(windows_only_conpty)'));
    expect(authority, contains('requestedPathRoots'));
    expect(authority, contains("'cwd'"));
    expect(authority, contains("'executable'"));
    expect(authority, contains('final value = payload[key]'));
    final processClient = File(
      'lib/product/p2_automation_host_process_client.dart',
    ).readAsStringSync();
    expect(processClient, contains("'KRISTIN_WINDOWS_JOB_HELPER'"));
    expect(processClient, contains("'KRISTIN_POSIX_WATCHDOG_HELPER'"));
    expect(processClient, contains("'KRISTIN_INTERACTIVE_DESKTOP_ADAPTER'"));
    expect(processClient, contains("'KRISTIN_P2_INTERACTIVE_DESKTOP'"));
    expect(processClient, contains('_stderrTail'));
    expect(processClient, contains('_reportUnexpectedExit'));
    expect(processClient, contains("'automation_host_exited'"));
  });
}
