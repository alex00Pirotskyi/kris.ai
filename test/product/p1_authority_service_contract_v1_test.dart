import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p1_authority_service_contract_v1.dart';

void main() {
  test('P1A endpoint requires OS isolation and a separate worker principal',
      () {
    final endpoint = P1AuthorityServiceEndpointV1(
      platform: 'linux',
      transport: 'linux-af-unix',
      address: '/run/kristin/p1-authority.sock',
      serviceInstanceId: 'p1a-test-instance',
      serviceBuildSha256: '1' * 64,
      serverIdentity: const <String, Object?>{'uid': 991, 'exeSha256': '2'},
      osEnforcedIsolation: true,
      workerPrincipalSeparated: true,
      typedOperationsOnly: true,
      nonExportableKeys: true,
      connectorLibrarySha256: '4' * 64,
      installerSha256: '5' * 64,
    );
    expect(endpoint.validate, returnsNormally);
  });

  test('P1A rejects metadata-only isolation claims', () {
    final endpoint = P1AuthorityServiceEndpointV1(
      platform: 'linux',
      transport: 'linux-af-unix',
      address: '/tmp/unsafe.sock',
      serviceInstanceId: 'p1a-unsafe',
      serviceBuildSha256: '3' * 64,
      serverIdentity: const <String, Object?>{'uid': 1000},
      osEnforcedIsolation: false,
      workerPrincipalSeparated: false,
      typedOperationsOnly: true,
      nonExportableKeys: false,
      connectorLibrarySha256: '4' * 64,
      installerSha256: '5' * 64,
    );
    expect(endpoint.validate, throwsStateError);
  });
}
