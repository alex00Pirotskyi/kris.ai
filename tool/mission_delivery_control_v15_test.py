#!/usr/bin/env python3
from __future__ import annotations

import unittest

import mission_delivery_control_v15 as compat


class MissionDeliveryV15CompatibilityTests(unittest.TestCase):
    def test_exact_control_plane_inputs_are_authorized(self) -> None:
        result = compat.control.classify_v15_control_plane_paths(
            [
                "config/mission_delivery.v1.json",
                "docs/roadmap/missions/landing-validations/requests/"
                "REQ-P4-001-B9038323-38CB129E.json",
                "docs/roadmap/missions/landing-validations/requests/"
                "REQ-P6-001-989A43C4-9D907DBC.json",
                "tool/branch_hygiene.py",
                "tool/mission_v15_landing_gate_compat.py",
            ]
        )
        self.assertTrue(result["authorized"])
        self.assertEqual(result["violations"], [])

    def test_scope_remains_closed_outside_immutable_requests(self) -> None:
        result = compat.control.classify_v15_control_plane_paths(
            [
                "docs/roadmap/missions/landing-validations/receipts/"
                "unscoped.json",
            ]
        )
        self.assertFalse(result["authorized"])
        self.assertEqual(
            result["violations"],
            [
                "docs/roadmap/missions/landing-validations/receipts/"
                "unscoped.json",
            ],
        )


if __name__ == "__main__":
    unittest.main()
