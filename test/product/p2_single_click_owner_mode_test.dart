import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_owner_risk_authority.dart';

void main() {
  test('product current-account Owner Mode is functional but not isolated', () {
    final authority = P2OwnerRiskQaAuthority(productCurrentAccount: true);
    expect(authority.authorityKind, 'p2-current-account-owner-v1');
    expect(authority.authorityImplementation, 'P2CurrentAccountOwnerAuthorityV1');
    expect(authority.qaPreview, isFalse);
    expect(authority.completionEligible, isFalse);
    expect(authority.authorityProvenance['productCurrentAccount'], isTrue);
    expect(authority.authorityProvenance['currentAccountAuthority'], isTrue);
    expect(authority.authorityProvenance['functionalOwnerModeEligible'], isTrue);
    expect(authority.authorityProvenance['secureIsolationActive'], isFalse);
    expect(
      authority.authorityProvenance['securityProfile'],
      'current-account-unisolated',
    );
    expect(authority.authorityProvenance['triPlatformQaRequired'], isFalse);
  });

  test('ProductRuntime prepares a bundled fallback only when P1A is absent', () {
    final runtime = File('lib/product/product_runtime.dart').readAsStringSync();
    final bootstrap = File(
      'lib/product/p2_bundled_current_account_runtime.dart',
    ).readAsStringSync();
    final configurator = File(
      'tool/configure-owner-risk-runtime.mjs',
    ).readAsStringSync();
    final staging = File('tool/v70_stage_runtime.py').readAsStringSync();
    final packaging = File('tool/v70_package_platform.py').readAsStringSync();

    expect(runtime, contains('if (runtime.p1AuthorityService == null)'));
    expect(runtime, contains('P2BundledCurrentAccountRuntime.prepareIfPresent'));
    expect(bootstrap, contains("'--mode'"));
    expect(bootstrap, contains("'product-current-account'"));
    expect(configurator, contains("mode === 'product-current-account'"));
    expect(configurator, contains('KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'));
    expect(staging, contains('product-current-account'));
    expect(packaging, contains('--product-current-account'));
    expect(packaging, contains('functionalOwnerModeEligible'));
    expect(packaging, contains('secureIsolationCertified'));
  });
}
