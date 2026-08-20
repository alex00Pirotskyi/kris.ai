#!/usr/bin/env python3
"""Focused regressions for Mission Execution 1.5 shared-authority configuration."""
from __future__ import annotations

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config/mission_v15_authorities.v1.json"
ELIGIBLE_TEST_CENTER_REQUESTERS = [
    "MISSION-004",
    "MISSION-005",
    "MISSION-006",
    "MISSION-010",
]


class MissionV15AuthorityConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = json.loads(CONFIG.read_text(encoding="utf-8"))
        cls.authorities = cls.config["authorities"]

    def test_proof_lineage_is_exact_append_safe_authority(self) -> None:
        authority = self.authorities["test-center-proof-lineage"]
        self.assertEqual(authority["ownerMission"], "MISSION-002")
        self.assertEqual(
            authority["path"],
            "release/evidence/TEST_CENTER/P8-001/contracts/assurance-proof-contract.v1.json",
        )
        self.assertEqual(authority["mode"], "APPEND_SAFE_JSON")
        self.assertEqual(
            authority["eligibleRequestingMissions"],
            ELIGIBLE_TEST_CENTER_REQUESTERS,
        )
        self.assertEqual(authority["collections"], {"lineageBindings": "testId"})

    def test_proof_lineage_authority_does_not_broaden_test_center_scope(self) -> None:
        authority = self.authorities["test-center-proof-lineage"]
        path = authority["path"]
        self.assertNotIn("*", path)
        self.assertNotEqual(path, "release/evidence/TEST_CENTER/**")
        self.assertTrue(path.endswith("/assurance-proof-contract.v1.json"))

    def test_test_center_append_authorities_share_requester_boundary(self) -> None:
        for authority_id in (
            "test-center-registry",
            "test-center-hierarchy",
            "test-center-proof-lineage",
        ):
            with self.subTest(authority=authority_id):
                authority = self.authorities[authority_id]
                self.assertEqual(authority["ownerMission"], "MISSION-002")
                self.assertEqual(authority["mode"], "APPEND_SAFE_JSON")
                self.assertEqual(
                    authority["eligibleRequestingMissions"],
                    ELIGIBLE_TEST_CENTER_REQUESTERS,
                )


if __name__ == "__main__":
    unittest.main()
