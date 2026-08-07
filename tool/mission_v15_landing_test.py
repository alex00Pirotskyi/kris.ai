#!/usr/bin/env python3
"""Mission Execution 1.5 source-landing semantic regressions."""
from __future__ import annotations

import pathlib
import sys
import unittest

THIS = pathlib.Path(__file__).resolve()
if str(THIS.parent) not in sys.path:
    sys.path.insert(0, str(THIS.parent))

from mission_v15_landing_gate import _promotes_without_acceptance


class LandingSemanticsTests(unittest.TestCase):
    def base(self):
        return {
            "task": "P6-001",
            "status": "VALIDATION",
            "sourceLanding": "LANDED_MAIN",
            "behavioralSupport": "NOT_EVALUATED",
            "platformSupport": "NOT_ESTABLISHED",
            "releaseSupport": "UNSUPPORTED",
            "productionReadiness": "NOT_CLAIMED",
            "gaReadiness": "NOT_CLAIMED",
            "supportPromotion": False,
        }

    def test_truthful_source_only_landing_passes(self):
        self.assertEqual(_promotes_without_acceptance(self.base()), [])

    def test_platform_support_promotion_fails(self):
        value = self.base()
        value["platformSupport"] = "SUPPORTED"
        self.assertTrue(_promotes_without_acceptance(value))

    def test_release_support_promotion_fails(self):
        value = self.base()
        value["releaseSupport"] = "SUPPORTED"
        self.assertTrue(_promotes_without_acceptance(value))

    def test_ga_promotion_fails(self):
        value = self.base()
        value["gaReadiness"] = "GA_READY"
        self.assertTrue(_promotes_without_acceptance(value))

    def test_explicit_support_promotion_flag_fails(self):
        value = self.base()
        value["supportPromotion"] = True
        self.assertTrue(_promotes_without_acceptance(value))

    def test_accepted_record_is_not_rejected_by_source_only_rule(self):
        value = self.base()
        value["status"] = "ACCEPTED"
        value["platformSupport"] = "SUPPORTED"
        self.assertEqual(_promotes_without_acceptance(value), [])


if __name__ == "__main__":
    unittest.main()
