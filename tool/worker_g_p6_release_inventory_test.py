#!/usr/bin/env python3
"""P6-001 regression coverage for the canonical release Dart inventory."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tool"
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

import validate_release as V  # noqa: E402

P6_DART = {
    "lib/product/model/model.dart",
    "lib/product/model/model_registry.dart",
    "test/product/model/model_registry_test.dart",
}


class P6ReleaseInventoryTest(unittest.TestCase):
    def test_p6_sources_and_tests_are_governed(self) -> None:
        self.assertTrue(P6_DART.issubset(V.EXPECTED_DART_FILES))

    def test_release_inventory_accepts_every_active_dart_source(self) -> None:
        actual = {
            path.relative_to(V.ROOT).as_posix()
            for path in V.package_dart_files()
        }
        self.assertEqual(actual - V.EXPECTED_DART_FILES, set())


if __name__ == "__main__":
    unittest.main(verbosity=2)
