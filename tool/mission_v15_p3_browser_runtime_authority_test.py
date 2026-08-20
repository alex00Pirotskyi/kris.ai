#!/usr/bin/env python3
"""Regression coverage for the bounded P3-001 browser-runtime authority repair."""
from __future__ import annotations

import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tool"))

from mission_runtime_model import _path_allowed_for_work_order, load_model


P3_BROWSER_RUNTIME_PATHS = (
    "automation_host/package.json",
    "automation_host/package-lock.json",
    "automation_host/src/browser-runtime.mjs",
    "automation_host/src/browser-runtime.test.mjs",
    "config/p3.browser-runtime-lock.json",
    "tool/p3_stage_browser_runtime_bundle.py",
    "tool/p3_stage_browser_runtime_bundle_test.py",
    ".github/workflows/p3-browser-runtime.yml",
)


class P3BrowserRuntimeAuthorityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.model = load_model(ROOT)
        cls.owned = cls.model["config"]["missionPathPolicies"]["MISSION-003"]["owned"]

    def test_exact_browser_runtime_bundle_paths_are_authorized(self) -> None:
        for path in P3_BROWSER_RUNTIME_PATHS:
            with self.subTest(path=path):
                self.assertTrue(
                    _path_allowed_for_work_order(
                        ROOT,
                        self.model,
                        "MISSION-003",
                        "PRODUCT_FEATURE",
                        path,
                    ),
                    path,
                )

    def test_automation_host_scope_remains_fail_closed(self) -> None:
        self.assertNotIn("automation_host/**", self.owned)
        self.assertFalse(
            _path_allowed_for_work_order(
                ROOT,
                self.model,
                "MISSION-003",
                "PRODUCT_FEATURE",
                "automation_host/src/unrelated.mjs",
            )
        )


if __name__ == "__main__":
    unittest.main()
