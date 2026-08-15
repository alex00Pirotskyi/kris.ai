#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from mission_delivery_control_test_v1 import *  # noqa: E402,F401,F403


class MissionDeliveryWorkIdCompatibilityTests(unittest.TestCase):
    def test_historical_uppercase_work_id_is_accepted_without_broadening_hex(self):
        model = {
            "config": {
                "statuses": ["BLOCKED_EXTERNAL"],
                "terminalAcceptedStatuses": [],
            },
            "missions": {"MISSION-005": {}},
            "tasks": {"P5-001": {"mission": "MISSION-005"}},
        }
        record = {
            "mission": "MISSION-005",
            "task": "P5-001",
            "status": "BLOCKED_EXTERNAL",
            "workExecutionId": "WRK-20260806T191459Z-5C0A9E2D",
            "recordedAt": "2026-08-06T19:24:00Z",
        }

        M.validate_record(record, model)

        record["workExecutionId"] = "WRK-20260806T191459Z-5C0A9E2G"
        with self.assertRaises(M.DeliveryError):
            M.validate_record(record, model)


if __name__ == "__main__":
    unittest.main()
