import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_owner_risk_authority.dart';

void main() {
  test('product current-account Owner Mode is functional but not isolated', () {
    final authority = P2OwnerRiskQaAuthority(productCurrentAccount: true);
    expect(authority.authorityKind, 'p2-current-account-owner-v1');
    expect(
      authority.authorityImplementation,
      'P2CurrentAccountOwnerAuthorityV1',
    );
    expect(authority.qaPreview, isFalse);
    expect(authority.completionEligible, isFalse);
    expect(authority.authorityProvenance['productCurrentAccount'], isTrue);
    expect(authority.authorityProvenance['currentAccountAuthority'], isTrue);
    expect(
      authority.authorityProvenance['functionalOwnerModeEligible'],
      isTrue,
    );
    expect(authority.authorityProvenance['secureIsolationActive'], isFalse);
    expect(
      authority.authorityProvenance['securityProfile'],
      'current-account-unisolated',
    );
    expect(authority.authorityProvenance['triPlatformQaRequired'], isFalse);
  });

  test('single-click Owner Mode uses the in-app ensure-ready lifecycle', () {
    final main = File('lib/main.dart').readAsStringSync();
    final shell = File(
      'lib/product/runtime_provisioning_shell.dart',
    ).readAsStringSync();
    final bridge = File(
      'lib/product/product_runtime_provisioning.dart',
    ).readAsStringSync();
    final provisioner = File(
      'lib/product/application_runtime_provisioner.dart',
    ).readAsStringSync();
    final materializer = File(
      'tool/application_runtime_materializer.mjs',
    ).readAsStringSync();

    expect(main, contains('ProvisioningKristinApp'));
    expect(shell, contains('Preparing Owner Mode'));
    expect(shell, contains('Preparing local runtime...'));
    expect(shell, contains('ensureOwnerModeReady'));
    expect(shell, contains("Owner Mode couldn't be prepared."));
    expect(shell, contains('owner-runtime-retry'));
    expect(shell, contains('owner-runtime-diagnostics'));
    expect(bridge, contains('provisioner.ensureP2'));
    expect(bridge, contains('P2ProductRuntimeBootstrap.start'));
    expect(bridge, contains('runtimeResources: resources'));
    expect(provisioner, contains('AtomicApplicationRuntimeSlot'));
    expect(materializer, contains("'--mode'"));
    expect(materializer, contains("'product-current-account'"));
    expect(materializer, isNot(contains('winget')));
    expect(materializer, isNot(contains('choco')));
    expect(materializer, isNot(contains('npm -g')));
  });

  test('provisioned Owner runtime is closed by the app lifecycle', () {
    final bridge = File(
      'lib/product/product_runtime_provisioning.dart',
    ).readAsStringSync();
    final shell = File(
      'lib/product/runtime_provisioning_shell.dart',
    ).readAsStringSync();

    expect(shell, contains('closeRuntimeProvisioning'));
    expect(bridge, contains('final provisionedOwner = state.ownerMode;'));
    expect(bridge, contains('!identical(provisionedOwner, p2OwnerMode)'));
    expect(bridge, contains('await provisionedOwner.close();'));
    expect(bridge, contains('_runtimeProvisioningStates[this] = null;'));
  });

  test('P1A remains preferred over current-account materialization', () {
    final bridge = File(
      'lib/product/product_runtime_provisioning.dart',
    ).readAsStringSync();
    final provisioner = File(
      'lib/product/application_runtime_provisioner.dart',
    ).readAsStringSync();

    expect(
      bridge,
      contains('currentAccountRequired: p1AuthorityService == null'),
    );
    expect(
      provisioner,
      contains('p2_secure_runtime_materialization_unavailable'),
    );
    expect(
      provisioner,
      contains("'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'"),
    );
    expect(
      provisioner,
      contains("'KRISTIN_OWNER_RISK_QA'"),
    );
  });
}
