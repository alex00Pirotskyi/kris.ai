#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def rep(path: str, old: str, new: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, got {count}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


rep(
    'lib/product/p2_owner_risk_authority.dart',
    "    'rawAuthoritySecretsReturned': false,\n    'ownerRiskQa': true,\n  };",
    "    'rawAuthoritySecretsReturned': false,\n    'ownerRiskQa': !productCurrentAccount,\n    'productCurrentAccount': productCurrentAccount,\n  };",
)
rep(
    'lib/product/p2_owner_risk_authority.dart',
    "    final authority = <String, Object?>{\n      'authorityKind': 'p2-owner-risk-current-account-v1',\n      'sharedP1ControlPlane': false,\n      'p2CanIssueGrants': false,\n      'workerCanIssue': false,\n      'osEnforcedIsolation': false,\n      'workerDeniedByOs': false,\n      'securityEvidenceWaived': true,\n      'workerIdentitySha256': workerIdentitySha256,\n      'instanceId': 'owner-risk-local-authority',",
    "    final authority = <String, Object?>{\n      'authorityKind': authorityKind,\n      'sharedP1ControlPlane': false,\n      'p2CanIssueGrants': false,\n      'workerCanIssue': false,\n      'osEnforcedIsolation': false,\n      'workerDeniedByOs': false,\n      'securityEvidenceWaived': true,\n      'productCurrentAccount': productCurrentAccount,\n      'securityProfile': productCurrentAccount\n          ? 'current-account-unisolated'\n          : 'owner-risk-qa',\n      'workerIdentitySha256': workerIdentitySha256,\n      'instanceId': productCurrentAccount\n          ? 'current-account-local-authority'\n          : 'owner-risk-local-authority',",
)
rep(
    'lib/product/p2_owner_risk_authority.dart',
    "      'ownerRiskQa': true,\n    };",
    "      'ownerRiskQa': !productCurrentAccount,\n    };",
)
rep(
    'lib/product/p2_owner_risk_authority.dart',
    "      sharedAuthorityInstanceId: 'owner-risk-local-authority',",
    "      sharedAuthorityInstanceId: productCurrentAccount\n          ? 'current-account-local-authority'\n          : 'owner-risk-local-authority',",
)

rep(
    'lib/product/p2_automation_host_process_client.dart',
    "      if (config.additionalEnvironment['KRISTIN_OWNER_RISK_QA']\n          case final value?)\n        'KRISTIN_OWNER_RISK_QA': value,",
    "      if (config.additionalEnvironment['KRISTIN_OWNER_RISK_QA']\n          case final value?)\n        'KRISTIN_OWNER_RISK_QA': value,\n      if (config.additionalEnvironment['KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT']\n          case final value?)\n        'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT': value,",
)
rep(
    'lib/product/p2_automation_host_process_client.dart',
    "    final ownerRiskQa =\n        config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';\n    final process = await Process.start(\n      ownerRiskQa ? config.nodeExecutable : config.restrictedWorkerLauncher,\n      <String>[\n        if (ownerRiskQa) config.restrictedWorkerLauncher,",
    "    final ownerRiskQa =\n        config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';\n    final productCurrentAccount =\n        config.additionalEnvironment['KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'] ==\n        '1';\n    final localCurrentAccount = ownerRiskQa || productCurrentAccount;\n    final process = await Process.start(\n      localCurrentAccount\n          ? config.nodeExecutable\n          : config.restrictedWorkerLauncher,\n      <String>[\n        if (localCurrentAccount) config.restrictedWorkerLauncher,",
)

rep(
    'lib/product/p2_automation_host_process_client.dart',
    "        final ownerRiskQa =\n            _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';\n        if (!_workerAuthorityDenial.isCompleted &&\n            ((!ownerRiskQa &&\n                    identity['authorityConnectionDenied'] == true &&\n                    identity['authorityDenialCode'] ==\n                        'worker_principal_denied') ||\n                (ownerRiskQa &&\n                    identity['authorityConnectionDenied'] == false &&\n                    identity['authorityDenialCode'] == 'owner_risk_waived' &&\n                    identity['ownerRiskQa'] == true &&\n                    identity['osIsolationWaived'] == true))) {\n          _workerAuthorityDenial.complete(<String, Object?>{\n            'authorityConnectionDenied': ownerRiskQa ? false : true,\n            'authorityDenialCode':\n                ownerRiskQa ? 'owner_risk_waived' : 'worker_principal_denied',\n            'authorityDenialObservedBy':\n                ownerRiskQa ? 'owner-risk-waiver' : 'restricted-launcher',\n            if (ownerRiskQa) 'ownerRiskQa': true,\n            if (ownerRiskQa) 'osIsolationWaived': true,\n            if (ownerRiskQa) 'currentAccountAuthority': true,\n          });\n        }",
    "        final ownerRiskQa =\n            _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';\n        final productCurrentAccount =\n            _config.additionalEnvironment[\n                    'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'] ==\n                '1';\n        final localCurrentAccount = ownerRiskQa || productCurrentAccount;\n        final secureDenied =\n            !localCurrentAccount &&\n            identity['authorityConnectionDenied'] == true &&\n            identity['authorityDenialCode'] == 'worker_principal_denied';\n        final qaWaived =\n            ownerRiskQa &&\n            !productCurrentAccount &&\n            identity['authorityConnectionDenied'] == false &&\n            identity['authorityDenialCode'] == 'owner_risk_waived' &&\n            identity['ownerRiskQa'] == true &&\n            identity['productCurrentAccount'] == false &&\n            identity['osIsolationWaived'] == true;\n        final productCurrentAccountAccepted =\n            productCurrentAccount &&\n            !ownerRiskQa &&\n            identity['authorityConnectionDenied'] == false &&\n            identity['authorityDenialCode'] ==\n                'current_account_unisolated' &&\n            identity['ownerRiskQa'] == false &&\n            identity['productCurrentAccount'] == true &&\n            identity['osIsolationWaived'] == true &&\n            identity['currentAccountAuthority'] == true;\n        if (!_workerAuthorityDenial.isCompleted &&\n            (secureDenied || qaWaived || productCurrentAccountAccepted)) {\n          _workerAuthorityDenial.complete(<String, Object?>{\n            'authorityConnectionDenied': localCurrentAccount ? false : true,\n            'authorityDenialCode': productCurrentAccount\n                ? 'current_account_unisolated'\n                : ownerRiskQa\n                    ? 'owner_risk_waived'\n                    : 'worker_principal_denied',\n            'authorityDenialObservedBy': productCurrentAccount\n                ? 'current-account-product'\n                : ownerRiskQa\n                    ? 'owner-risk-waiver'\n                    : 'restricted-launcher',\n            if (ownerRiskQa) 'ownerRiskQa': true,\n            if (productCurrentAccount) 'ownerRiskQa': false,\n            if (productCurrentAccount) 'productCurrentAccount': true,\n            if (localCurrentAccount) 'osIsolationWaived': true,\n            if (localCurrentAccount) 'currentAccountAuthority': true,\n          });\n        }",
)

rep(
    'lib/product/p2_automation_host_process_client.dart',
    "    final ownerRiskQa =\n        _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';\n    final expectedPrincipal = ownerRiskQa\n        ? 'owner-risk-current-account'\n        : Platform.isWindows\n            ? 'appcontainer'\n            : Platform.isMacOS\n                ? 'signed-app-sandbox-helper'\n                : 'dedicated-uid';",
    "    final ownerRiskQa =\n        _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';\n    final productCurrentAccount =\n        _config.additionalEnvironment['KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'] ==\n        '1';\n    if (ownerRiskQa && productCurrentAccount) {\n      throw const P2AutomationHostException(\n        'restricted_worker_identity_mode_conflict',\n      );\n    }\n    final localCurrentAccount = ownerRiskQa || productCurrentAccount;\n    final expectedPrincipal = ownerRiskQa\n        ? 'owner-risk-current-account'\n        : productCurrentAccount\n            ? 'current-account-owner'\n            : Platform.isWindows\n                ? 'appcontainer'\n                : Platform.isMacOS\n                    ? 'signed-app-sandbox-helper'\n                    : 'dedicated-uid';",
)
rep(
    'lib/product/p2_automation_host_process_client.dart',
    "    if (!ownerRiskQa &&\n        Platform.isLinux &&",
    "    if (!localCurrentAccount &&\n        Platform.isLinux &&",
)
rep(
    'lib/product/p2_automation_host_process_client.dart',
    "    if (!ownerRiskQa &&\n        Platform.isWindows &&",
    "    if (!localCurrentAccount &&\n        Platform.isWindows &&",
)
rep(
    'lib/product/p2_automation_host_process_client.dart',
    "    if (!ownerRiskQa &&\n        Platform.isMacOS &&",
    "    if (!localCurrentAccount &&\n        Platform.isMacOS &&",
)
rep(
    'lib/product/p2_automation_host_process_client.dart',
    "    if (ownerRiskQa) {\n      if (message['ownerRiskQa'] != true ||\n          message['osIsolationWaived'] != true ||\n          message['currentAccountAuthority'] != true ||\n          denial != false ||\n          denialCode != 'owner_risk_waived') {\n        throw const P2AutomationHostException(\n          'owner_risk_worker_waiver_invalid',\n        );\n      }\n    } else if (denial != null &&\n        (denial != true || denialCode != 'worker_principal_denied')) {\n      throw const P2AutomationHostException(\n        'restricted_worker_authority_denial_invalid',\n      );\n    }",
    "    if (ownerRiskQa) {\n      if (message['ownerRiskQa'] != true ||\n          message['productCurrentAccount'] != false ||\n          message['osIsolationWaived'] != true ||\n          message['currentAccountAuthority'] != true ||\n          denial != false ||\n          denialCode != 'owner_risk_waived') {\n        throw const P2AutomationHostException(\n          'owner_risk_worker_waiver_invalid',\n        );\n      }\n    } else if (productCurrentAccount) {\n      if (message['ownerRiskQa'] != false ||\n          message['productCurrentAccount'] != true ||\n          message['osIsolationWaived'] != true ||\n          message['currentAccountAuthority'] != true ||\n          message['authorityDenialObservedBy'] != 'current-account-product' ||\n          denial != false ||\n          denialCode != 'current_account_unisolated') {\n        throw const P2AutomationHostException(\n          'current_account_worker_identity_invalid',\n        );\n      }\n    } else if (denial != null &&\n        (denial != true || denialCode != 'worker_principal_denied')) {\n      throw const P2AutomationHostException(\n        'restricted_worker_authority_denial_invalid',\n      );\n    }",
)
rep(
    'lib/product/p2_automation_host_process_client.dart',
    "    final ownerRiskQa =\n        _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';\n    if (ownerRiskQa) {\n      if (merged['authorityConnectionDenied'] != false ||\n          merged['authorityDenialCode'] != 'owner_risk_waived' ||\n          merged['authorityDenialObservedBy'] != 'owner-risk-waiver' ||\n          merged['ownerRiskQa'] != true ||\n          merged['osIsolationWaived'] != true ||\n          merged['currentAccountAuthority'] != true) {\n        throw const P2AutomationHostException(\n          'owner_risk_worker_waiver_unproved',\n        );\n      }\n    } else if (merged['authorityConnectionDenied'] != true ||\n        merged['authorityDenialCode'] != 'worker_principal_denied') {\n      throw const P2AutomationHostException(\n        'restricted_worker_authority_denial_unproved',\n      );\n    }",
    "    final ownerRiskQa =\n        _config.additionalEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';\n    final productCurrentAccount =\n        _config.additionalEnvironment['KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'] ==\n        '1';\n    if (ownerRiskQa && productCurrentAccount) {\n      throw const P2AutomationHostException(\n        'restricted_worker_identity_mode_conflict',\n      );\n    }\n    if (ownerRiskQa) {\n      if (merged['authorityConnectionDenied'] != false ||\n          merged['authorityDenialCode'] != 'owner_risk_waived' ||\n          merged['authorityDenialObservedBy'] != 'owner-risk-waiver' ||\n          merged['ownerRiskQa'] != true ||\n          merged['productCurrentAccount'] != false ||\n          merged['osIsolationWaived'] != true ||\n          merged['currentAccountAuthority'] != true) {\n        throw const P2AutomationHostException(\n          'owner_risk_worker_waiver_unproved',\n        );\n      }\n    } else if (productCurrentAccount) {\n      if (merged['authorityConnectionDenied'] != false ||\n          merged['authorityDenialCode'] != 'current_account_unisolated' ||\n          merged['authorityDenialObservedBy'] != 'current-account-product' ||\n          merged['ownerRiskQa'] != false ||\n          merged['productCurrentAccount'] != true ||\n          merged['osIsolationWaived'] != true ||\n          merged['currentAccountAuthority'] != true) {\n        throw const P2AutomationHostException(\n          'current_account_worker_identity_unproved',\n        );\n      }\n    } else if (merged['authorityConnectionDenied'] != true ||\n        merged['authorityDenialCode'] != 'worker_principal_denied') {\n      throw const P2AutomationHostException(\n        'restricted_worker_authority_denial_unproved',\n      );\n    }",
)

rep(
    'automation_host/src/authenticated-ipc.mjs',
    "  const ownerRiskQa = auth.authority?.ownerRiskQa === true;\n  const authorityModeValid = ownerRiskQa\n    ? auth.authority?.sharedP1ControlPlane === false &&\n      auth.authority?.authorityKind === 'p2-owner-risk-current-account-v1' &&\n      auth.authority?.securityEvidenceWaived === true &&\n      auth.authority?.osEnforcedIsolation === false &&\n      auth.authority?.workerDeniedByOs === false\n    : auth.authority?.sharedP1ControlPlane === true &&\n      auth.authority?.authorityKind === 'p1-isolated-authority-service-v2';",
    "  const ownerRiskQa = auth.authority?.ownerRiskQa === true;\n  const productCurrentAccount = auth.authority?.productCurrentAccount === true;\n  const localCurrentAccountBase =\n    auth.authority?.sharedP1ControlPlane === false &&\n    auth.authority?.securityEvidenceWaived === true &&\n    auth.authority?.osEnforcedIsolation === false &&\n    auth.authority?.workerDeniedByOs === false;\n  const authorityModeValid = ownerRiskQa\n    ? localCurrentAccountBase &&\n      !productCurrentAccount &&\n      auth.authority?.authorityKind === 'p2-owner-risk-current-account-v1'\n    : productCurrentAccount\n      ? localCurrentAccountBase &&\n        auth.authority?.authorityKind === 'p2-current-account-owner-v1' &&\n        auth.authority?.securityProfile === 'current-account-unisolated'\n      : auth.authority?.sharedP1ControlPlane === true &&\n        auth.authority?.authorityKind === 'p1-isolated-authority-service-v2';",
)
rep(
    'automation_host/src/authenticated-ipc.mjs',
    "  if (process.env.KRISTIN_OWNER_RISK_QA !== '1') {",
    "  if (process.env.KRISTIN_OWNER_RISK_QA !== '1' &&\n      process.env.KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT !== '1') {",
)

rep(
    'tool/configure-owner-risk-runtime.mjs',
    "    KRISTIN_OWNER_RISK_QA: '1',\n    ...(productCurrentAccount ? { KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT: '1' } : {}),",
    "    ...(!productCurrentAccount ? { KRISTIN_OWNER_RISK_QA: '1' } : {}),\n    ...(productCurrentAccount ? { KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT: '1' } : {}),",
)
rep(
    'tool/configure-owner-risk-runtime.mjs',
    "  ownerRiskQa: true, productCurrentAccount, securityEvidenceWaived: true,",
    "  ownerRiskQa: !productCurrentAccount, productCurrentAccount, securityEvidenceWaived: true,",
)

rep(
    'tool/v70_stage_runtime.py',
    '        "KRISTIN_OWNER_RISK_QA": "1",\n        **({"KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT": "1"} if args.mode == "product-current-account" else {}),',
    '        **({"KRISTIN_OWNER_RISK_QA": "1"} if args.mode == "qa" else {}),\n        **({"KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT": "1"} if args.mode == "product-current-account" else {}),',
)

rep(
    'lib/product/p2_runtime_resource_resolver.dart',
    "    final manifestOwnerRiskQa =\n        decoded is Map && decoded['ownerRiskQa'] == true;\n    final ownerRiskQa = buildOwnerRiskQa || manifestOwnerRiskQa;",
    "    final manifestOwnerRiskQa =\n        decoded is Map && decoded['ownerRiskQa'] == true;\n    final manifestProductCurrentAccount =\n        decoded is Map && decoded['productCurrentAccount'] == true;\n    final localCurrentAccount =\n        buildOwnerRiskQa || manifestOwnerRiskQa || manifestProductCurrentAccount;",
)
rep(
    'lib/product/p2_runtime_resource_resolver.dart',
    "        (!ownerRiskQa && decoded['authorityServiceExternal'] != true) ||\n        (ownerRiskQa && decoded['authorityServiceExternal'] != false) ||\n        (!ownerRiskQa && decoded['restrictedWorkerLauncherExternal'] != true) ||\n        (ownerRiskQa && decoded['restrictedWorkerLauncherExternal'] != false) ||\n        (!ownerRiskQa &&\n            decoded['restrictedWorkerLauncherOsEnforced'] != true) ||\n        (ownerRiskQa &&\n            decoded['restrictedWorkerLauncherOsEnforced'] != false) ||\n        (ownerRiskQa && decoded['ownerRiskQa'] != true)) {",
    "        (!localCurrentAccount && decoded['authorityServiceExternal'] != true) ||\n        (localCurrentAccount && decoded['authorityServiceExternal'] != false) ||\n        (!localCurrentAccount &&\n            decoded['restrictedWorkerLauncherExternal'] != true) ||\n        (localCurrentAccount &&\n            decoded['restrictedWorkerLauncherExternal'] != false) ||\n        (!localCurrentAccount &&\n            decoded['restrictedWorkerLauncherOsEnforced'] != true) ||\n        (localCurrentAccount &&\n            decoded['restrictedWorkerLauncherOsEnforced'] != false) ||\n        (manifestOwnerRiskQa && manifestProductCurrentAccount) ||\n        (manifestProductCurrentAccount && decoded['ownerRiskQa'] != false)) {",
)

rep(
    'lib/product/p2_product_runtime_bootstrap.dart',
    "            if (ownerRiskQa) 'KRISTIN_OWNER_RISK_QA': '1',\n            if (productCurrentAccount)\n              'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT': '1',",
    "            if (buildOwnerRiskQa || runtimeOwnerRisk)\n              'KRISTIN_OWNER_RISK_QA': '1',\n            if (productCurrentAccount)\n              'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT': '1',",
)

rep(
    'test/product/p2_single_click_owner_mode_test.dart',
    "      expect(configurator, contains('KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'));\n      expect(staging, contains('product-current-account'));",
    "      expect(configurator, contains('KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'));\n      expect(\n        configurator,\n        contains('ownerRiskQa: !productCurrentAccount'),\n      );\n      final hostVerifier = File(\n        'automation_host/src/authenticated-ipc.mjs',\n      ).readAsStringSync();\n      final processClient = File(\n        'lib/product/p2_automation_host_process_client.dart',\n      ).readAsStringSync();\n      expect(hostVerifier, contains(\"'p2-current-account-owner-v1'\"));\n      expect(hostVerifier, contains('KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'));\n      expect(processClient, contains('KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'));\n      expect(processClient, contains('localCurrentAccount'));\n      expect(processClient, contains(\"'current-account-owner'\"));\n      expect(processClient, contains(\"'current_account_unisolated'\"));\n      expect(processClient, contains(\"'current-account-product'\"));\n      expect(staging, contains('product-current-account'));",
)

print('OWNER_SINGLE_CLICK_TRANSPORT_FIX_OK')
