#!/usr/bin/env python3
"""Adversarial regressions for Mission Execution 1.5 Work Order supersession."""
from __future__ import annotations

import json
import pathlib
import sys
import tempfile
import unittest

THIS = pathlib.Path(__file__).resolve()
TOOL = THIS.parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from mission_v15_supersession_invariant import validate_supersession


class SupersessionInvariantTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        (self.root / "runtime/work-orders/MISSION-007").mkdir(parents=True)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write(self, work_id: str, **extra: object) -> None:
        value: dict[str, object] = {
            "workOrderId": work_id,
            "mission": "MISSION-007",
            "roadmapTask": "P7-001",
            "parentProductPr": 96,
            "status": "READY",
        }
        value.update(extra)
        path = self.root / "runtime/work-orders/MISSION-007" / f"{work_id}.json"
        path.write_text(json.dumps(value), encoding="utf-8")

    def test_reciprocal_same_scope_pair_passes(self) -> None:
        self.write("WO-OLD", status="SUPERSEDED", supersededBy="WO-NEW")
        self.write("WO-NEW", supersedes="WO-OLD")
        result = validate_supersession(self.root)
        self.assertTrue(result["pass"])
        self.assertEqual(result["supersessionEdgeCount"], 1)

    def test_dangling_replacement_fails(self) -> None:
        self.write("WO-OLD", status="SUPERSEDED", supersededBy="WO-MISSING")
        with self.assertRaises(ValueError):
            validate_supersession(self.root)

    def test_non_reciprocal_replacement_fails(self) -> None:
        self.write("WO-OLD", status="SUPERSEDED", supersededBy="WO-NEW")
        self.write("WO-NEW")
        with self.assertRaises(ValueError):
            validate_supersession(self.root)

    def test_cross_scope_replacement_fails(self) -> None:
        self.write("WO-OLD", status="SUPERSEDED", supersededBy="WO-NEW")
        self.write("WO-NEW", roadmapTask="P7-002", supersedes="WO-OLD")
        with self.assertRaises(ValueError):
            validate_supersession(self.root)

    def test_cycle_fails(self) -> None:
        self.write(
            "WO-A",
            status="SUPERSEDED",
            supersededBy="WO-B",
            supersedes="WO-B",
        )
        self.write(
            "WO-B",
            status="SUPERSEDED",
            supersededBy="WO-A",
            supersedes="WO-A",
        )
        with self.assertRaises(ValueError):
            validate_supersession(self.root)


if __name__ == "__main__":
    unittest.main()
