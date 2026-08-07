#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import mission_live_materializer as live  # noqa: E402


class LiveClaimMaterializerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.project = Path(self.temp.name)
        self.missions = [
            {"id": "MISSION-001"},
            {"id": "MISSION-002"},
        ]
        self.seed = [self.claim("MISSION-001", head="1" * 40)]

    def tearDown(self) -> None:
        self.temp.cleanup()

    def claim(self, mission: str, *, head: str, branch: str | None = None) -> dict:
        worker = "A" if mission == "MISSION-001" else "B"
        return {
            "mission": mission,
            "worker": worker,
            "branch": branch or f"agent/{worker.lower()}/work",
            "pr": 1 if mission == "MISSION-001" else 2,
            "head": head,
            "tree": "a" * 40,
            "status": "CLAIMED",
            "current": "bounded live work",
            "exclusivePaths": [f"lib/{mission.lower()}/**"],
        }

    def state(
        self,
        mission: str,
        *,
        status: str,
        claim: dict | None = None,
    ) -> dict:
        return {
            "schemaVersion": 1,
            "mission": mission,
            "status": status,
            "assignedWorker": claim["worker"] if claim else None,
            "branch": claim["branch"] if claim else None,
            "pullRequest": claim["pr"] if claim else None,
            "observedHead": claim["head"] if claim else None,
            "observedTree": claim.get("tree") if claim else None,
        }

    def write_memory(
        self,
        states: dict[str, dict],
        claims: dict[str, dict] | None = None,
    ) -> None:
        state_dir = self.project / "docs/roadmap/missions/state"
        claim_dir = self.project / "docs/roadmap/missions/claims"
        state_dir.mkdir(parents=True, exist_ok=True)
        claim_dir.mkdir(parents=True, exist_ok=True)
        for mission, value in states.items():
            (state_dir / f"{mission}.json").write_text(
                json.dumps(value) + "\n", encoding="utf-8"
            )
        for mission, value in (claims or {}).items():
            (claim_dir / f"{mission}.claim.json").write_text(
                json.dumps(value) + "\n", encoding="utf-8"
            )

    def test_initial_bootstrap_uses_seed_claims(self) -> None:
        claims, materialized = live.load_live_claims(
            self.project, self.missions, self.seed
        )
        self.assertFalse(materialized)
        self.assertEqual(self.seed, claims)

    def test_materialized_claim_overrides_static_seed(self) -> None:
        current = self.claim("MISSION-001", head="2" * 40)
        self.write_memory(
            {
                "MISSION-001": self.state(
                    "MISSION-001", status="CLAIMED", claim=current
                ),
                "MISSION-002": self.state("MISSION-002", status="AVAILABLE"),
            },
            {"MISSION-001": current},
        )
        claims, materialized = live.load_live_claims(
            self.project, self.missions, self.seed
        )
        self.assertTrue(materialized)
        self.assertEqual([current], claims)
        self.assertNotEqual(self.seed[0]["head"], claims[0]["head"])

    def test_yielded_state_does_not_resurrect_static_seed(self) -> None:
        self.write_memory(
            {
                "MISSION-001": self.state("MISSION-001", status="YIELDED"),
                "MISSION-002": self.state("MISSION-002", status="AVAILABLE"),
            }
        )
        claims, materialized = live.load_live_claims(
            self.project, self.missions, self.seed
        )
        self.assertTrue(materialized)
        self.assertEqual([], claims)

    def test_active_state_without_claim_fails_closed(self) -> None:
        self.write_memory(
            {
                "MISSION-001": self.state("MISSION-001", status="CLAIMED"),
                "MISSION-002": self.state("MISSION-002", status="AVAILABLE"),
            }
        )
        with self.assertRaisesRegex(
            live.LiveMaterializerError, "active-looking mission state has no ownership claim"
        ):
            live.load_live_claims(self.project, self.missions, self.seed)

    def test_claim_state_identity_mismatch_fails_closed(self) -> None:
        current = self.claim("MISSION-001", head="2" * 40)
        state = self.state("MISSION-001", status="CLAIMED", claim=current)
        state["observedHead"] = "3" * 40
        self.write_memory(
            {
                "MISSION-001": state,
                "MISSION-002": self.state("MISSION-002", status="AVAILABLE"),
            },
            {"MISSION-001": current},
        )
        with self.assertRaisesRegex(
            live.LiveMaterializerError, "claim/state identity mismatch"
        ):
            live.load_live_claims(self.project, self.missions, self.seed)

    def test_incomplete_materialized_state_set_fails_closed(self) -> None:
        self.write_memory(
            {"MISSION-001": self.state("MISSION-001", status="AVAILABLE")}
        )
        with self.assertRaisesRegex(
            live.LiveMaterializerError, "materialized mission memory is incomplete"
        ):
            live.load_live_claims(self.project, self.missions, self.seed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
