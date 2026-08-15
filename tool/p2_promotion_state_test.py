#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import unittest

from p2_evidence_state import validate_repository


ROOT = Path(__file__).resolve().parents[1]


class P2PromotionStateTest(unittest.TestCase):
    def test_canonical_state_is_valid(self) -> None:
        result = validate_repository(ROOT)
        self.assertEqual(result["acceptedDecisionTasks"], ["P2-004"])
        self.assertEqual(result["behaviorCertifiedTasks"], [])
        self.assertFalse(result["platformQualified"])
        self.assertFalse(result["releaseSupported"])

    def test_exact_source_gate_uses_canonical_state(self) -> None:
        source = (ROOT / "tool/v71r12_exact_source_gate.py").read_text(
            encoding="utf-8"
        )
        self.assertIn("P2 canonical evidence state", source)
        self.assertIn("tool/p2_evidence_state.py", source)
        self.assertIn(
            'project / "release/evidence/P2-004/state.json"',
            source,
        )
        self.assertIn('if task_id == "P2-004":', source)
        self.assertIn("committed unfinished P2 evidence invalid", source)
        self.assertNotIn("committed P2 evidence invalid:", source)
        self.assertLess(
            source.index('if task_id == "P2-004":'),
            source.index("committed unfinished P2 evidence invalid"),
        )

    def test_unfinished_capabilities_remain_source_only(self) -> None:
        phase = json.loads(
            (ROOT / "release/evidence/P2/state.json").read_text(encoding="utf-8")
        )
        states = phase["taskStates"]
        self.assertEqual(states["P2-004"], "accepted_decision")
        for task_id, status in states.items():
            if task_id != "P2-004":
                self.assertEqual(status, "source_only", task_id)
        self.assertEqual(phase["behaviorCertifiedTasks"], [])
        self.assertFalse(phase["phaseCompletionEligible"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
