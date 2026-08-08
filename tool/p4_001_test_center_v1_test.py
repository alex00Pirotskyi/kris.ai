#!/usr/bin/env python3
from __future__ import annotations

import json
import unittest
from pathlib import Path

from tool import test_center_contracts as canonical
from tool.p4_001_test_center_v1 import (
    CANONICAL_STATES,
    MODULE_ID,
    P4_MAPPING_IDS,
    P4_TEST_IDS,
    check_project,
    normalize_observed_state,
    validate_order_independence,
)


class P4001CanonicalTestCenterTest(unittest.TestCase):
    def setUp(self) -> None:
        self.project = Path(__file__).resolve().parents[1]
        self.registry = json.loads(
            (self.project / "config/test_center_registry.v1.json").read_text(
                encoding="utf-8"
            )
        )

    def test_registration_validates_against_worker_b_contract(self) -> None:
        report = check_project(self.project)
        self.assertEqual("PASS", report["status"])
        self.assertEqual(MODULE_ID, report["registration"]["moduleId"])
        self.assertEqual(list(P4_TEST_IDS), report["registration"]["testIds"])
        self.assertEqual(list(P4_MAPPING_IDS), report["registration"]["mappingIds"])
        self.assertEqual("SOURCE_FOUNDATION", report["capabilitySupport"])
        self.assertEqual("NOT_EVALUATED", report["certificationState"])
        self.assertFalse(report["behaviorSupportEstablished"])

    def test_every_canonical_state_is_preserved_without_upgrade(self) -> None:
        self.assertEqual(
            list(CANONICAL_STATES),
            [normalize_observed_state(state) for state in CANONICAL_STATES],
        )
        for invalid in (
            "passed",
            "PASS_WITH_WARNINGS",
            "BLOCKED_BY_SHARED_CONTRACT",
            "NOT-RUN",
        ):
            with self.subTest(invalid=invalid), self.assertRaises(
                canonical.ContractError
            ):
                normalize_observed_state(invalid)

    def test_affected_selection_is_order_independent(self) -> None:
        observations = validate_order_independence(self.registry)
        self.assertEqual(3, len(observations))
        for observation in observations:
            selected = observation["selectedTestIds"]
            self.assertEqual(sorted(set(selected)), selected)
            self.assertTrue(set(selected).intersection(P4_TEST_IDS))

    def test_profiles_are_non_mutating_and_use_canonical_platforms(self) -> None:
        profiles = {
            profile["stableCheckId"]: profile
            for profile in self.registry["projectTestProfiles"]
            if profile["stableCheckId"].startswith("tc.p4-001.")
        }
        self.assertEqual(set(P4_TEST_IDS), set(profiles))
        for test_id in P4_TEST_IDS:
            profile = profiles[test_id]
            self.assertEqual("NON_MUTATING", profile["mutationPolicy"])
            self.assertEqual(["linux", "macos", "windows"], profile["platforms"])
            self.assertIsInstance(profile["argv"], list)
            self.assertEqual(
                [
                    "python",
                    "tool/p4_001_search_provider_test.py",
                    "--project",
                    ".",
                    "--test-id",
                    test_id,
                ],
                profile["argv"],
            )
            self.assertTrue(
                profile["evidenceDestination"].startswith("release/evidence/")
            )

    def test_source_only_registration_cannot_claim_behavior_or_release(self) -> None:
        presentation = next(
            item
            for item in self.registry["testingStudioPresentationRecords"]
            if item["presentationId"]
            == "presentation.p4-001.search-provider-interface"
        )
        self.assertEqual("source_contract", presentation["assuranceClass"])
        self.assertIsNone(presentation["lastExactCommitResult"])
        self.assertTrue(presentation["staleResultWarning"])
        claim = presentation["supportClaimImpact"].casefold()
        for boundary in (
            "live",
            "fetch",
            "browser",
            "citations",
            "datasets",
            "release",
            "production",
            "ga",
        ):
            self.assertIn(boundary, claim)


if __name__ == "__main__":
    unittest.main()
