import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/release_operations_v19.dart';

void main() {
  test('v1.9 release operations models remain constructible', () {
    const profile = PolicyProfileV19(
      id: 'strict_local',
      name: 'Strict local-only',
      dataBoundary: 'local',
      networkPolicy: 'none',
      allowA2ADelegation: false,
      allowRemoteMcp: false,
      allowedUpdateChannels: <String>['stable'],
    );
    const support = SupportLifecyclePolicyV19(
      currentVersion: '1.9.0+190',
      minimumSupportedUpgradeFrom: '1.8.0+180',
      minimumSupportedRollbackTo: '1.8.0+180',
    );
    const audit = AuditVerificationResultV19(
      verified: true,
      recordCount: 3,
    );

    expect(profile.allowedUpdateChannels, contains('stable'));
    expect(support.currentVersion, '1.9.0+190');
    expect(audit.verified, isTrue);
  });
}
