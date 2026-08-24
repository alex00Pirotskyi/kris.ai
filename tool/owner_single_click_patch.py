#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str) -> None:
    file = ROOT / path
    text = file.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, got {count}: {old[:120]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


replace_once(
    'lib/product/p2_owner_risk_authority.dart',
    'final class P2OwnerRiskQaAuthority implements P2RuntimeAuthority {\n  P2OwnerRiskQaAuthority() {',
    'final class P2OwnerRiskQaAuthority implements P2RuntimeAuthority {\n  P2OwnerRiskQaAuthority({this.productCurrentAccount = false}) {',
)
replace_once(
    'lib/product/p2_owner_risk_authority.dart',
    '  late final String _workerSessionId;\n',
    '  final bool productCurrentAccount;\n  late final String _workerSessionId;\n',
)
replace_once(
    'lib/product/p2_owner_risk_authority.dart',
    "  String get authorityImplementation => 'P2OwnerRiskQaAuthorityV1';",
    "  String get authorityImplementation => productCurrentAccount\n      ? 'P2CurrentAccountOwnerAuthorityV1'\n      : 'P2OwnerRiskQaAuthorityV1';",
)
replace_once(
    'lib/product/p2_owner_risk_authority.dart',
    "  String get authorityKind => 'p2-owner-risk-current-account-v1';",
    "  String get authorityKind => productCurrentAccount\n      ? 'p2-current-account-owner-v1'\n      : 'p2-owner-risk-current-account-v1';",
)
replace_once(
    'lib/product/p2_owner_risk_authority.dart',
    '  bool get qaPreview => true;',
    '  bool get qaPreview => !productCurrentAccount;',
)
replace_once(
    'lib/product/p2_owner_risk_authority.dart',
    "        'authorityType': 'owner-risk-local-current-account-v1',\n        'authorityKind': authorityKind,\n        'implementation': authorityImplementation,\n        'qaPreview': true,\n        'qaPreviewVersion': '1.0.0',\n        'qaPreviewFormalCompletion': false,\n        'ownerRiskAccepted': true,\n        'securityEvidenceWaived': true,\n        'authorityDenialCode': 'owner_risk_waived',\n        'currentAccountAuthority': true,\n        'rootOrAdministratorSupported': true,\n        'triPlatformQaRequired': true,",
    "        'authorityType': productCurrentAccount\n            ? 'current-account-owner-local-v1'\n            : 'owner-risk-local-current-account-v1',\n        'authorityKind': authorityKind,\n        'implementation': authorityImplementation,\n        'qaPreview': !productCurrentAccount,\n        'qaPreviewVersion': '1.0.0',\n        'qaPreviewFormalCompletion': false,\n        'productCurrentAccount': productCurrentAccount,\n        'securityProfile': productCurrentAccount\n            ? 'current-account-unisolated'\n            : 'owner-risk-qa',\n        'functionalOwnerModeEligible': productCurrentAccount,\n        'secureIsolationActive': false,\n        'ownerRiskAccepted': true,\n        'securityEvidenceWaived': true,\n        'authorityDenialCode': productCurrentAccount\n            ? 'current_account_unisolated'\n            : 'owner_risk_waived',\n        'currentAccountAuthority': true,\n        'rootOrAdministratorSupported': true,\n        'triPlatformQaRequired': !productCurrentAccount,",
)
replace_once(
    'lib/product/p2_owner_risk_authority.dart',
    "      'qaPreview': true,\n      'securityEvidenceWaived': true,",
    "      'qaPreview': !productCurrentAccount,\n      'productCurrentAccount': productCurrentAccount,\n      'securityProfile': productCurrentAccount\n          ? 'current-account-unisolated'\n          : 'owner-risk-qa',\n      'securityEvidenceWaived': true,",
)

replace_once(
    'lib/product/p2_runtime_resource_resolver.dart',
    "    const ownerRiskQa = bool.fromEnvironment(\n      'KRISTIN_OWNER_RISK_QA',\n      defaultValue: false,\n    );",
    "    const buildOwnerRiskQa = bool.fromEnvironment(\n      'KRISTIN_OWNER_RISK_QA',\n      defaultValue: false,\n    );\n    final manifestOwnerRiskQa =\n        decoded is Map && decoded['ownerRiskQa'] == true;\n    final ownerRiskQa = buildOwnerRiskQa || manifestOwnerRiskQa;",
)
replace_once(
    'lib/product/p2_runtime_resource_resolver.dart',
    "      'KRISTIN_OWNER_RISK_QA',\n",
    "      'KRISTIN_OWNER_RISK_QA',\n      'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT',\n",
)

replace_once(
    'lib/product/p2_product_runtime_bootstrap.dart',
    "      const ownerRiskQa = bool.fromEnvironment(\n        'KRISTIN_OWNER_RISK_QA',\n        defaultValue: false,\n      );\n      const qaPreviewBuild = bool.fromEnvironment(\n        'KRISTIN_QA_PREVIEW',\n        defaultValue: false,\n      );\n      final qaPreview = ownerRiskQa ||\n          (qaPreviewBuild &&\n              p1AuthorityService?.service.provenance['qaPreview'] == true);\n      if (!ownerRiskQa) {\n        if (p1AuthorityService == null) {\n          throw StateError('merged_p1a_service_unavailable');\n        }\n        p1AuthorityService.validateForP2(allowQaPreview: qaPreview);\n      }\n      final resolver = resourceResolver ??\n          P2ApplicationOwnedRuntimeResourceResolver(\n            applicationDataRoot: dataRoot,\n          );\n      final resources = runtimeResources ?? await resolver.resolve();",
    "      const buildOwnerRiskQa = bool.fromEnvironment(\n        'KRISTIN_OWNER_RISK_QA',\n        defaultValue: false,\n      );\n      const qaPreviewBuild = bool.fromEnvironment(\n        'KRISTIN_QA_PREVIEW',\n        defaultValue: false,\n      );\n      final resolver = resourceResolver ??\n          P2ApplicationOwnedRuntimeResourceResolver(\n            applicationDataRoot: dataRoot,\n          );\n      final resources = runtimeResources ?? await resolver.resolve();\n      final runtimeOwnerRisk =\n          resources.provisionedEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';\n      final productCurrentAccount = resources.provisionedEnvironment[\n              'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'] ==\n          '1';\n      final ownerRiskQa =\n          buildOwnerRiskQa || runtimeOwnerRisk || productCurrentAccount;\n      final qaPreview = !productCurrentAccount &&\n          (ownerRiskQa ||\n              (qaPreviewBuild &&\n                  p1AuthorityService?.service.provenance['qaPreview'] == true));\n      if (!ownerRiskQa) {\n        if (p1AuthorityService == null) {\n          throw StateError('merged_p1a_service_unavailable');\n        }\n        p1AuthorityService.validateForP2(allowQaPreview: qaPreview);\n      }",
)
replace_once(
    'lib/product/p2_product_runtime_bootstrap.dart',
    '      final P2RuntimeAuthority authority =\n          p1Adapter ?? P2OwnerRiskQaAuthority();',
    '      final P2RuntimeAuthority authority = p1Adapter ??\n          P2OwnerRiskQaAuthority(\n            productCurrentAccount: productCurrentAccount,\n          );',
)
replace_once(
    'lib/product/p2_product_runtime_bootstrap.dart',
    "            if (ownerRiskQa) 'KRISTIN_OWNER_RISK_QA': '1',\n",
    "            if (ownerRiskQa) 'KRISTIN_OWNER_RISK_QA': '1',\n            if (productCurrentAccount)\n              'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT': '1',\n",
)
replace_once(
    'lib/product/p2_product_runtime_bootstrap.dart',
    "      'KRISTIN_OWNER_RISK_QA',\n",
    "      'KRISTIN_OWNER_RISK_QA',\n      'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT',\n",
)

replace_once(
    'lib/product/p2_product_runtime_integration.dart',
    "    final ownerRiskAuthority = authority.qaPreview &&\n        !authority.completionEligible &&\n        authority.authorityKind == 'p2-owner-risk-current-account-v1' &&\n        authority.authorityProvenance['securityEvidenceWaived'] == true;\n    if (!(secureP1aAuthority || ownerRiskAuthority)) {",
    "    final ownerRiskAuthority = authority.qaPreview &&\n        !authority.completionEligible &&\n        authority.authorityKind == 'p2-owner-risk-current-account-v1' &&\n        authority.authorityProvenance['securityEvidenceWaived'] == true;\n    final currentAccountAuthority = !authority.qaPreview &&\n        !authority.completionEligible &&\n        authority.authorityKind == 'p2-current-account-owner-v1' &&\n        authority.authorityProvenance['currentAccountAuthority'] == true &&\n        authority.authorityProvenance['secureIsolationActive'] == false &&\n        authority.authorityProvenance['functionalOwnerModeEligible'] == true;\n    if (!(secureP1aAuthority || ownerRiskAuthority || currentAccountAuthority)) {",
)

replace_once(
    'tool/configure-owner-risk-runtime.mjs',
    "const args = parseArgs(process.argv.slice(2));\nconst root = path.resolve(args.root ?? '');",
    "const args = parseArgs(process.argv.slice(2));\nconst mode = args.mode ?? 'qa';\nif (!['qa', 'product-current-account'].includes(mode)) fail('mode invalid');\nconst productCurrentAccount = mode === 'product-current-account';\nconst root = path.resolve(args.root ?? '');",
)
replace_once(
    'tool/configure-owner-risk-runtime.mjs',
    "  ownerRiskQa: true, osIsolationWaived: true,\n};",
    "  ownerRiskQa: true, osIsolationWaived: true, productCurrentAccount,\n};",
)
replace_once(
    'tool/configure-owner-risk-runtime.mjs',
    "    KRISTIN_OWNER_RISK_QA: '1', KRISTIN_P2_COMMIT_SHA: sourceCommit,",
    "    KRISTIN_OWNER_RISK_QA: '1',\n    ...(productCurrentAccount ? { KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT: '1' } : {}),\n    KRISTIN_P2_COMMIT_SHA: sourceCommit,",
)
replace_once(
    'tool/configure-owner-risk-runtime.mjs',
    "  ownerRiskQa: true, securityEvidenceWaived: true,\n};",
    "  ownerRiskQa: true, productCurrentAccount, securityEvidenceWaived: true,\n};",
)
replace_once(
    'tool/configure-owner-risk-runtime.mjs',
    "console.log(JSON.stringify({ status: 'passed', platform, runtimeRoot: root, manifestPath, manifestSha256: shaFile(manifestPath), runtimeBuildSha256 }, null, 2));",
    "console.log(JSON.stringify({ status: 'passed', platform, mode, productCurrentAccount, runtimeRoot: root, manifestPath, manifestSha256: shaFile(manifestPath), runtimeBuildSha256 }, null, 2));",
)

replace_once(
    'tool/v70_stage_runtime.py',
    '    parser.add_argument("--configurator", required=True)\n',
    '    parser.add_argument("--configurator", required=True)\n    parser.add_argument("--mode", choices=("qa", "product-current-account"), default="qa")\n',
)
replace_once(
    'tool/v70_stage_runtime.py',
    '        "--p1-contract", str(runtime / "contracts" / contract.name),\n    ])',
    '        "--p1-contract", str(runtime / "contracts" / contract.name),\n        "--mode", args.mode,\n    ])',
)
replace_once(
    'tool/v70_stage_runtime.py',
    '        "KRISTIN_OWNER_RISK_QA": "1",\n    }',
    '        "KRISTIN_OWNER_RISK_QA": "1",\n        **({"KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT": "1"} if args.mode == "product-current-account" else {}),\n    }',
)
replace_once(
    'tool/v70_stage_runtime.py',
    '        "mode": "owner-risk-tri-platform-qa",',
    '        "mode": "product-current-account" if args.mode == "product-current-account" else "owner-risk-tri-platform-qa",',
)

replace_once(
    'tool/v70_package_platform.py',
    '    parser.add_argument("--workflow-run-attempt", default="1")\n',
    '    parser.add_argument("--workflow-run-attempt", default="1")\n    parser.add_argument("--product-current-account", action="store_true")\n',
)
replace_once(
    'tool/v70_package_platform.py',
    '    write_launchers(payload, args.platform, app_executable, args.source_commit, args.source_tree)\n\n    qa_dir = payload / "qa"\n    qa_dir.mkdir(parents=True)',
    '    if not args.product_current_account:\n        write_launchers(payload, args.platform, app_executable, args.source_commit, args.source_tree)\n\n    qa_dir = payload / "qa"\n    if not args.product_current_account:\n        qa_dir.mkdir(parents=True)',
)
replace_once(
    'tool/v70_package_platform.py',
    '    for relative in ("OWNER_RISK_QA_SHIPMENT.md", "config/p1_p2_owner_risk_qa.v1.json"):\n        source = root / relative\n        if source.is_file():\n            shutil.copy2(source, qa_dir / source.name)\n    governed_qa = root / "qa/v71r12"\n    if not governed_qa.is_dir():\n        fail("governed V71 QA handoff directory missing")\n    for source in sorted(governed_qa.rglob("*"), key=lambda item: item.relative_to(governed_qa).as_posix()):\n        if source.is_dir():\n            continue\n        relative = source.relative_to(governed_qa)\n        target = qa_dir / relative\n        target.parent.mkdir(parents=True, exist_ok=True)\n        shutil.copy2(source, target)\n    required_qa = (\n        qa_dir / "TRI_PLATFORM_TEST_MATRIX.md",\n        qa_dir / "QA_HANDOFF.md",\n        qa_dir / "KNOWN_LIMITATIONS.md",\n        qa_dir / "SHIPMENT_CLASSIFICATION.md",\n        qa_dir / "P1_P2_FEATURE_COVERAGE.json",\n    )\n    if any(not item.is_file() for item in required_qa):\n        fail("complete QA matrix/coverage payload missing")',
    '    if not args.product_current_account:\n        for relative in ("OWNER_RISK_QA_SHIPMENT.md", "config/p1_p2_owner_risk_qa.v1.json"):\n            source = root / relative\n            if source.is_file():\n                shutil.copy2(source, qa_dir / source.name)\n        governed_qa = root / "qa/v71r12"\n        if not governed_qa.is_dir():\n            fail("governed V71 QA handoff directory missing")\n        for source in sorted(governed_qa.rglob("*"), key=lambda item: item.relative_to(governed_qa).as_posix()):\n            if source.is_dir():\n                continue\n            relative = source.relative_to(governed_qa)\n            target = qa_dir / relative\n            target.parent.mkdir(parents=True, exist_ok=True)\n            shutil.copy2(source, target)\n        required_qa = (\n            qa_dir / "TRI_PLATFORM_TEST_MATRIX.md",\n            qa_dir / "QA_HANDOFF.md",\n            qa_dir / "KNOWN_LIMITATIONS.md",\n            qa_dir / "SHIPMENT_CLASSIFICATION.md",\n            qa_dir / "P1_P2_FEATURE_COVERAGE.json",\n        )\n        if any(not item.is_file() for item in required_qa):\n            fail("complete QA matrix/coverage payload missing")',
)
replace_once(
    'tool/v70_package_platform.py',
    '    metadata = {\n        "schemaVersion": "1.0.0",\n        "bundleType": "kristin-p1-p2-owner-risk-qa-v71r12",',
    '    metadata = {\n        "schemaVersion": "1.0.0",\n        "bundleType": "kristin-current-account-owner-product-v1" if args.product_current_account else "kristin-p1-p2-owner-risk-qa-v71r12",',
)
replace_once(
    'tool/v70_package_platform.py',
    '        "productionReleaseEligible": False,\n        "qaShipmentEligible": True,\n        "allThreePlatformArtifactsRequired": True,\n        "manualQaMatrixIncluded": True,\n        "p1P2FeatureCoverageIncluded": True,',
    '        "productionReleaseEligible": False,\n        "functionalOwnerModeEligible": bool(args.product_current_account),\n        "secureIsolationCertified": False,\n        "qaShipmentEligible": not args.product_current_account,\n        "allThreePlatformArtifactsRequired": True,\n        "manualQaMatrixIncluded": not args.product_current_account,\n        "p1P2FeatureCoverageIncluded": not args.product_current_account,',
)
replace_once(
    'tool/v70_package_platform.py',
    '    (payload / "QA_BUILD_METADATA.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\\n", encoding="utf-8")',
    '    metadata_name = "OWNER_RUNTIME_METADATA.json" if args.product_current_account else "QA_BUILD_METADATA.json"\n    (payload / metadata_name).write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\\n", encoding="utf-8")',
)
replace_once(
    'tool/v70_package_platform.py',
    '    (payload / "QA_BUNDLE_MANIFEST.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\\n", encoding="utf-8")\n    archive = output_dir / f"KRISTIN_P1_P2_OWNER_RISK_QA_{args.platform.upper()}_V71R12_{args.source_commit[:12]}.zip"',
    '    manifest_name = "OWNER_RUNTIME_MANIFEST.json" if args.product_current_account else "QA_BUNDLE_MANIFEST.json"\n    (payload / manifest_name).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\\n", encoding="utf-8")\n    archive_name = (\n        f"KRISTIN_OWNER_MODE_{args.platform.upper()}_{args.source_commit[:12]}.zip"\n        if args.product_current_account\n        else f"KRISTIN_P1_P2_OWNER_RISK_QA_{args.platform.upper()}_V71R12_{args.source_commit[:12]}.zip"\n    )\n    archive = output_dir / archive_name',
)

replace_once(
    'lib/product/product_runtime.dart',
    "import 'p2_product_runtime_bootstrap.dart';\n",
    "import 'p2_product_runtime_bootstrap.dart';\nimport 'p2_bundled_current_account_runtime.dart';\n",
)
replace_once(
    'lib/product/product_runtime.dart',
    "    runtime._p1AuthorityServiceRuntime =\n        await P1AuthorityServiceConnectorRegistryV1.openInstalledOrTest();\n    runtime._p2OwnerModeRuntime = await P2ProductRuntimeBootstrap.start(",
    "    runtime._p1AuthorityServiceRuntime =\n        await P1AuthorityServiceConnectorRegistryV1.openInstalledOrTest();\n    if (runtime.p1AuthorityService == null) {\n      await P2BundledCurrentAccountRuntime.prepareIfPresent(\n        applicationDataRoot: directories.root,\n      );\n    }\n    runtime._p2OwnerModeRuntime = await P2ProductRuntimeBootstrap.start(",
)

print('OWNER_SINGLE_CLICK_PATCH_OK')
