#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tool"))

import test_center_contracts as canonical
import worker_a_test_center_v1 as worker_a


class WorkerATestCenterV1Test(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = json.loads(
            (ROOT / "config/test_center_registry.v1.json").read_text(encoding="utf-8")
        )

    def test_canonical_registry_and_worker_a_overlay_pass(self) -> None:
        report = worker_a.check_project(ROOT)
        self.assertEqual("PASS", report["status"])
        self.assertEqual("NON_MUTATING", report["checkMode"])
        self.assertGreaterEqual(report["workerModuleCount"], 7)
        self.assertGreaterEqual(report["workerTestCount"], 11)
        self.assertGreaterEqual(report["workerMappingCount"], 5)

    def test_required_stable_ids_are_canonical(self) -> None:
        required = {
            "tc.p1.exit-gate",
            "tc.p1a.exit-gate",
            "tc.p2.source-inventory",
            "tc.p2.application-composition",
            "tc.p2.acceptance-contract",
            "tc.p2.evidence-contract",
            "tc.p2.runner-attestation",
            "tc.p2.cleanup-contract",
            "tc.p2.strict-finalizer",
            "tc.p2.behavioral-closure",
            "tc.worker-a.canonical-integration",
        }
        case_ids = {case["testId"] for case in self.registry["testCases"]}
        profile_ids = {
            profile["stableCheckId"] for profile in self.registry["projectTestProfiles"]
        }
        self.assertTrue(required <= case_ids)
        self.assertEqual(case_ids, profile_ids)
        for stable_id in required:
            self.assertRegex(stable_id, canonical.STABLE_TEST_ID_RE)

    def test_profiles_are_non_mutating_and_repository_relative(self) -> None:
        for profile in self.registry["projectTestProfiles"]:
            canonical.validate_project_test_profile(profile)
            self.assertEqual("NON_MUTATING", profile["mutationPolicy"])
            self.assertEqual(".", profile["workingDirectory"])
            self.assertTrue(profile["inputPaths"])
            self.assertTrue(
                profile["evidenceDestination"].startswith("release/evidence/")
            )

    def test_affected_selection_is_order_independent(self) -> None:
        changed = [
            "tool/p2_platform_ci.py",
            "config/test_center_registry.v1.json",
            "tool/p1a_exit_gate_test.py",
        ]
        forward = canonical.select_affected_tests(
            changed, self.registry["affectedTestMappings"]
        )
        reverse = canonical.select_affected_tests(
            list(reversed(changed)),
            list(reversed(self.registry["affectedTestMappings"])),
        )
        self.assertEqual(forward, reverse)
        self.assertIn("tc.p2.behavioral-closure", forward)
        self.assertIn("tc.worker-a.canonical-integration", forward)
        self.assertIn("tc.p1a.exit-gate", forward)

    def test_result_taxonomy_includes_error_without_coercion(self) -> None:
        expected = {
            "PASS",
            "FAIL",
            "ERROR",
            "SKIPPED",
            "BLOCKED",
            "UNKNOWN",
            "FLAKY",
            "NOT_IMPLEMENTED",
        }
        self.assertEqual(expected, canonical.TEST_RESULT_STATES)
        for state in expected:
            self.assertEqual(state, canonical.normalize_result_state(state))
        with self.assertRaises(canonical.ContractError):
            canonical.normalize_result_state("passed")

    def test_behavioral_profile_is_not_in_source_suite(self) -> None:
        self.assertNotIn("tc.p2.behavioral-closure", worker_a.SOURCE_SUITE_DEFAULTS)
        self.assertIn("tc.p2.behavioral-closure", {
            profile["stableCheckId"]
            for profile in self.registry["projectTestProfiles"]
        })

    def test_p1a_profile_uses_governed_source_only_mode(self) -> None:
        profile = next(
            profile
            for profile in self.registry["projectTestProfiles"]
            if profile["stableCheckId"] == "tc.p1a.exit-gate"
        )
        self.assertEqual(
            ["python", "tool/p1a_exit_gate_test.py", "--project", ".", "--source-only"],
            profile["argv"],
        )
        self.assertEqual("source_contract", profile["assuranceClass"])

    def test_worker_b_review_is_immutable_history(self) -> None:
        review = json.loads(
            (
                ROOT
                / "docs/roadmap/anarchy/reviews/WORKER_B_A_REVIEW_345847c.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual("REQUEST_CHANGES", review["decision"])
        self.assertEqual(
            "345847cb06b3123f2841bdface68a6615cd5de42",
            review["reviewedCommit"],
        )
        self.assertEqual(
            "10345698dea33222955cce23e5c45e59459f626f",
            review["reviewedTree"],
        )


if __name__ == "__main__":
    unittest.main()
