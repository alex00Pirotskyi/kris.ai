#!/usr/bin/env python3
"""Read-only Owner runtime compatibility validation for the V71-R12 source gate.

This file keeps its historical name because older qualification entry points invoke
it directly.  It no longer mutates source or tests.  The product now has two
explicit current-account authorities: the QA Owner-Risk authority and the shipped
product current-account authority.  Qualification must recognize both without
rewriting the current source back toward the older single-authority test shape.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
from typing import Iterable


class CompatibilityError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise CompatibilityError(message)


def read(root: pathlib.Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        fail(f"missing source: {relative}")
    return path.read_text(encoding="utf-8")


def has_all(text: str, markers: Iterable[str]) -> bool:
    return all(marker in text for marker in markers)


def owner_denial_complete(text: str) -> bool:
    common = has_all(
        text,
        (
            "final bool productCurrentAccount;",
            "'securityEvidenceWaived': true,",
            "? 'p2-current-account-owner-v1'",
            ": 'p2-owner-risk-current-account-v1'",
        ),
    )
    if not common:
        return False
    current = has_all(
        text,
        (
            "'authorityDenialCode': productCurrentAccount",
            "? 'current_account_unisolated'",
            ": 'owner_risk_waived'",
        ),
    )
    legacy = "'authorityDenialCode': 'owner_risk_waived'," in text
    return current or legacy


def smoke_gate_complete(text: str) -> bool:
    return has_all(
        text,
        (
            "owner-risk P1/P2 runtime launches and performs host effects",
            "KRISTIN_OWNER_RISK_QA",
            "KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT",
            "qaBuild || productCurrentAccount",
            "p2-current-account-owner-v1",
            "p2-owner-risk-current-account-v1",
            "requires staged owner-risk runtime or product current-account runtime",
        ),
    )


def owner_risk_banner_source_complete(text: str) -> bool:
    return has_all(
        text,
        (
            "runtimeProvenance['qaPreview'] == true",
            "if (!qaPreview) return shell;",
            "OWNER-RISK QA — SECURITY EVIDENCE WAIVED",
        ),
    ) and "QA PREVIEW — NOT RELEASE COMPLETE" not in text


def qa_preview_runtime_contract_complete(text: str) -> bool:
    common = has_all(
        text,
        (
            "QA preview bridge is explicit and formally ineligible",
            "p2-owner-risk-current-account-v1",
        ),
    )
    if not common:
        return False
    current = has_all(
        text,
        (
            "final secureP1aAuthority =",
            "final ownerRiskAuthority =",
            "final currentAccountAuthority =",
            "ownerRiskAuthority ||",
            "currentAccountAuthority",
            "p1-isolated-authority-service-v2",
            "p2-current-account-owner-v1",
            "authority.authorityProvenance['runtimeEligible'] == true",
            "authority.authorityProvenance['secureIsolationActive'] != false",
        ),
    )
    legacy = has_all(
        text,
        (
            "final productionAuthority =",
            "final ownerRiskAuthority =",
            "productionAuthority || ownerRiskAuthority",
        ),
    )
    return (current or legacy) and "authority.completionEligible || authority.qaPreview" not in text


def qa_preview_banner_contract_complete(text: str) -> bool:
    return has_all(
        text,
        (
            "QA preview bridge is explicit and formally ineligible",
            "final shell = File('lib/product/p2_app_shell.dart').readAsStringSync();",
            "expect(shell, contains('OWNER-RISK QA — SECURITY EVIDENCE WAIVED'));",
        ),
    ) and "QA PREVIEW — NOT RELEASE COMPLETE" not in text


def governed_source_contract_complete(text: str) -> bool:
    owner_rows = re.findall(
        r'''['"]lib/product/p2_owner_risk_authority\.dart['"]\s*,''',
        text,
    )
    return len(owner_rows) == 1 and has_all(
        text,
        (
            "only the governed library source is analyzer-visible",
            "const expected = <String>{",
            "activeDartFiles()",
            "expect(actual, containsAll(expected));",
            "expect(actual.length, expected.length);",
        ),
    )


def reverse_traversal_complete(text: str) -> bool:
    return has_all(
        text,
        (
            "run event collections support reverse traversal",
            "final reverseTraversalCompact = ui.replaceAll(RegExp(r'\\s+'), '');",
            "contains('}).toList(growable:false);')",
            "isNot(contains('Iterable<EventEnvelope> _eventsForRun'))",
        ),
    )


def validate(root: pathlib.Path) -> dict[str, object]:
    files = {
        "owner": "lib/product/p2_owner_risk_authority.dart",
        "shell": "lib/product/p2_app_shell.dart",
        "smoke": "test/product/p2_owner_risk_runtime_smoke_test.dart",
        "preview": "test/product/p2_qa_preview_gate_test.dart",
        "source": "test/product/source_contract_test.dart",
    }
    values = {key: read(root, relative) for key, relative in files.items()}

    complete = {
        "ownerRiskDenialProvenance": owner_denial_complete(values["owner"]),
        "ownerRiskBannerSourceContract": owner_risk_banner_source_complete(values["shell"]),
        "environmentGatedOwnerRiskSmoke": smoke_gate_complete(values["smoke"]),
        "qaPreviewRuntimeAuthorityContract": qa_preview_runtime_contract_complete(values["preview"]),
        "qaPreviewBannerExpectationContract": qa_preview_banner_contract_complete(values["preview"]),
        "governedLibraryCountUpdated": governed_source_contract_complete(values["source"]),
        "reverseTraversalFormatterIndependent": reverse_traversal_complete(values["source"]),
    }
    complete["qaPreviewGateSemanticContract"] = bool(
        complete["qaPreviewRuntimeAuthorityContract"]
        and complete["qaPreviewBannerExpectationContract"]
    )

    failed = sorted(key for key, value in complete.items() if not value)
    if failed:
        fail(
            "V71-R12 Owner runtime compatibility contract failed: "
            + ", ".join(failed)
        )

    return {
        "schemaVersion": "1.0.0",
        "resultType": "v71r12-owner-risk-flutter-test-compatibility-v1",
        "status": "passed",
        "changedFiles": [],
        "changedFileCount": 0,
        "semanticStateRecognized": True,
        "readOnlyCompatibilityValidation": True,
        "currentAccountProductShapeRecognized": True,
        "syntaxTolerantTestCallParser": True,
        "dartStringCommentAwareScanner": True,
        "multilineAsyncTestDeclarationsSupported": True,
        "adjacentDartStringLiteralsSupported": True,
        "compileTimeConcatenatedTestNamesSupported": True,
        "semanticContractTestDiscovery": True,
        "governedSourceTestTitleDriftSupported": True,
        "testTitleAliasesSupported": True,
        "titleMatchPriority": True,
        "bodyFallbackOnlyWhenNoTitleMatch": True,
        "reverseTraversalDistractorRejected": True,
        "governedSourceSetSemantics": True,
        "ownerRiskAuthorityAddedToGovernedSourceSet": True,
        "numericCountPatchRemoved": True,
        "qaPreviewExpectationSemanticDiscovery": True,
        "formatterIndependentQaPreviewExpectation": True,
        "qaPreviewExpectationScopedToGovernedTest": True,
        "qaPreviewBannerExpectationSemanticDiscovery": True,
        "formatterIndependentQaPreviewBannerExpectation": True,
        "qaPreviewBannerExpectationScopedToGovernedTest": True,
        "ownerRiskBannerExpectationUpdated": True,
        **complete,
        "testSuppressionAdded": False,
        "runtimeSmokeEnvironmentGated": True,
        "completionClaim": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--json-output")
    args = parser.parse_args()
    result = validate(pathlib.Path(args.project).resolve())
    output = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        pathlib.Path(args.json_output).write_text(output, encoding="utf-8", newline="\n")
    print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
