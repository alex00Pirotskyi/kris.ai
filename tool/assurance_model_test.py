#!/usr/bin/env python3
"""Behavioral tests for P0-007 assurance classification."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from assurance_model import (
    ASSURANCE_ARCHITECTURE_LINT,
    ASSURANCE_BEHAVIORAL,
    ASSURANCE_MIXED,
    ASSURANCE_SDK_TOOLCHAIN,
    ASSURANCE_UNCLASSIFIED,
    PROOF_EXECUTED_BEHAVIOR,
    PROOF_MIXED,
    PROOF_SOURCE_INSPECTION,
    classify_validator_check,
    summarize_assurance_checks,
    validate_assurance_summary,
)


class AssuranceModelTest(unittest.TestCase):
    def test_source_contract_is_never_behavioral(self) -> None:
        value = classify_validator_check("check_architecture", "single governed architecture")
        self.assertEqual(value.assurance_level, ASSURANCE_ARCHITECTURE_LINT)
        self.assertEqual(value.proof_kind, PROOF_SOURCE_INSPECTION)
        self.assertFalse(value.behavioral_proof)

    def test_mixed_gate_is_not_pure_behavior(self) -> None:
        value = classify_validator_check("check_prompt_studio_v2", "Prompt Studio")
        self.assertEqual(value.assurance_level, ASSURANCE_MIXED)
        self.assertEqual(value.proof_kind, PROOF_MIXED)
        self.assertFalse(value.behavioral_proof)

    def test_durable_harness_is_behavioral(self) -> None:
        value = classify_validator_check("check_durable_workflow_kernel", "SQLite")
        self.assertEqual(value.assurance_level, ASSURANCE_BEHAVIORAL)
        self.assertEqual(value.proof_kind, PROOF_EXECUTED_BEHAVIOR)
        self.assertTrue(value.behavioral_proof)

    def test_sdk_tool_is_not_product_behavior(self) -> None:
        value = classify_validator_check("check_sdk", "flutter analyze")
        self.assertEqual(value.assurance_level, ASSURANCE_SDK_TOOLCHAIN)
        self.assertFalse(value.behavioral_proof)

    def test_unknown_check_fails_classification(self) -> None:
        value = classify_validator_check("new_check_without_classification", "new")
        self.assertEqual(value.assurance_level, ASSURANCE_UNCLASSIFIED)
        summary = summarize_assurance_checks(
            [
                {
                    "name": "new",
                    "status": "passed",
                    "blocking": True,
                    **value.as_dict(),
                }
            ]
        )
        self.assertFalse(summary["classificationComplete"])
        self.assertFalse(summary["strictValid"])

    def test_source_pass_without_behavior_does_not_claim_behavior(self) -> None:
        source = classify_validator_check("check_architecture", "source")
        summary = summarize_assurance_checks(
            [
                {
                    "name": "source",
                    "status": "passed",
                    "blocking": True,
                    **source.as_dict(),
                }
            ]
        )
        self.assertTrue(summary["sourceContractPassed"])
        self.assertFalse(summary["behavioralAssurancePassed"])

    def test_mixed_pass_does_not_claim_behavior(self) -> None:
        mixed = classify_validator_check("check_execution_intelligence", "mixed")
        summary = summarize_assurance_checks(
            [
                {
                    "name": "mixed",
                    "status": "passed",
                    "blocking": True,
                    **mixed.as_dict(),
                }
            ]
        )
        self.assertEqual(summary["groups"]["mixed"]["count"], 1)
        self.assertFalse(summary["behavioralAssurancePassed"])
        self.assertTrue(summary["noSourceMarkerOverclaim"])

    def test_pure_behavioral_pass_is_reported(self) -> None:
        behavioral = classify_validator_check("check_durable_workflow_kernel", "behavior")
        summary = summarize_assurance_checks(
            [
                {
                    "name": "behavior",
                    "status": "passed",
                    "blocking": True,
                    **behavioral.as_dict(),
                }
            ]
        )
        self.assertTrue(summary["behavioralAssurancePassed"])

    def test_behavioral_failure_is_reported(self) -> None:
        behavioral = classify_validator_check("check_durable_workflow_kernel", "behavior")
        summary = summarize_assurance_checks(
            [
                {
                    "name": "behavior",
                    "status": "failed",
                    "blocking": True,
                    **behavioral.as_dict(),
                }
            ]
        )
        self.assertFalse(summary["behavioralAssurancePassed"])
        self.assertEqual(summary["groups"]["behavioral"]["failedCount"], 1)

    def test_source_overclaim_is_detected(self) -> None:
        summary = summarize_assurance_checks(
            [
                {
                    "name": "dishonest source gate",
                    "status": "passed",
                    "blocking": True,
                    "assurance_level": "source_contract",
                    "proof_kind": "source_inspection",
                    "behavioral_proof": True,
                }
            ]
        )
        self.assertFalse(summary["noSourceMarkerOverclaim"])
        self.assertIn("dishonest source gate", summary["overclaimChecks"])

    def test_invalid_status_is_detected(self) -> None:
        source = classify_validator_check("check_architecture", "source")
        summary = summarize_assurance_checks(
            [
                {
                    "name": "source",
                    "status": "maybe",
                    "blocking": True,
                    **source.as_dict(),
                }
            ]
        )
        self.assertIn("source", summary["invalidStatusChecks"])
        self.assertFalse(summary["classificationComplete"])

    def test_summary_validation_rejects_overclaim(self) -> None:
        failures = validate_assurance_summary(
            {
                "schemaVersion": "1.0.0",
                "classificationComplete": True,
                "noSourceMarkerOverclaim": False,
                "mixedChecksCountAsBehavioral": False,
            }
        )
        self.assertIn("source or mixed checks were counted as behavioral proof", failures)

    def test_dashboard_rejects_source_overclaim(self) -> None:
        root = Path(__file__).resolve().parents[1]
        dashboard = root / "tool" / "assurance_dashboard.py"
        with tempfile.TemporaryDirectory(prefix="kristin-assurance-") as temporary:
            work = Path(temporary)
            validation = work / "validation.json"
            architecture = work / "architecture.json"
            output = work / "report.json"
            validation.write_text(
                json.dumps(
                    {
                        "product": "fixture",
                        "version": "1",
                        "checks": [
                            {
                                "name": "source",
                                "status": "passed",
                                "blocking": True,
                                "assurance_level": "source_contract",
                                "proof_kind": "source_inspection",
                                "behavioral_proof": True,
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            architecture.write_text(
                json.dumps(
                    {
                        "passed": True,
                        "passedCount": 1,
                        "failedCount": 0,
                        "proofKind": "source_inspection",
                        "behavioralProof": False,
                    }
                ),
                encoding="utf-8",
            )
            completed = subprocess.run(
                [
                    sys.executable,
                    str(dashboard),
                    "--validation-report",
                    str(validation),
                    "--architecture-report",
                    str(architecture),
                    "--output-json",
                    str(output),
                    "--output-markdown",
                    str(work / "report.md"),
                    "--strict",
                ],
                cwd=root,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )
            self.assertNotEqual(completed.returncode, 0, completed.stdout)
            payload = json.loads(output.read_text(encoding="utf-8"))
            self.assertFalse(payload["passed"])
            self.assertTrue(payload["assuranceSummary"]["overclaimChecks"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
