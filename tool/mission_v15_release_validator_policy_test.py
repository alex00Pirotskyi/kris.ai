#!/usr/bin/env python3
"""Regressions for the bounded release-validator source-policy transform."""
from __future__ import annotations

import pathlib
import sys
import unittest

THIS = pathlib.Path(__file__).resolve()
TOOL = THIS.parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from mission_v15_release_validator_policy_apply import transform_release_validator


BASE = '''def _load_governed_p2_dart_files() -> set[str]:
    return {"lib/product/p2.dart"}

EXPECTED_DART_FILES.update(_load_governed_p2_dart_files())

def check_imports_and_syntax() -> None:
    actual = {"lib/main.dart"}
    unexpected = sorted(actual - EXPECTED_DART_FILES)
'''


class ReleaseValidatorPolicyTests(unittest.TestCase):
    def test_transform_uses_governed_library_inventory(self) -> None:
        updated, changed = transform_release_validator(BASE)
        self.assertTrue(changed)
        self.assertIn("def _load_governed_product_library_files()", updated)
        self.assertIn(
            "EXPECTED_DART_FILES.update(_load_governed_product_library_files())",
            updated,
        )
        self.assertIn('if not path.startswith("test/")', updated)

    def test_transform_is_idempotent(self) -> None:
        updated, changed = transform_release_validator(BASE)
        self.assertTrue(changed)
        same, changed_again = transform_release_validator(updated)
        self.assertFalse(changed_again)
        self.assertEqual(updated, same)

    def test_missing_p2_anchor_fails(self) -> None:
        with self.assertRaises(ValueError):
            transform_release_validator(BASE.replace(
                "EXPECTED_DART_FILES.update(_load_governed_p2_dart_files())\n",
                "",
            ))

    def test_missing_unexpected_calculation_fails(self) -> None:
        with self.assertRaises(ValueError):
            transform_release_validator(BASE.replace(
                "    unexpected = sorted(actual - EXPECTED_DART_FILES)\n",
                "",
            ))

    def test_partial_prior_migration_fails(self) -> None:
        partial = BASE.replace(
            "EXPECTED_DART_FILES.update(_load_governed_p2_dart_files())\n",
            "def _load_governed_product_library_files() -> set[str]:\n    return set()\n\n"
            "EXPECTED_DART_FILES.update(_load_governed_p2_dart_files())\n",
        )
        with self.assertRaises(ValueError):
            transform_release_validator(partial)


if __name__ == "__main__":
    unittest.main()
