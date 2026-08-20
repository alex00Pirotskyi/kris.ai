#!/usr/bin/env python3
"""Adversarial append-safe authority regressions."""
from __future__ import annotations

import json
import pathlib
import sys
import unittest

THIS = pathlib.Path(__file__).resolve()
if str(THIS.parent) not in sys.path:
    sys.path.insert(0, str(THIS.parent))

from mission_v15_authority_append import verify_append_safe_json


class AppendSafeJsonTests(unittest.TestCase):
    def fixture(self):
        return {
            "schemaVersion": 1,
            "authority": {"owner": "B"},
            "testCases": [
                {"testId": "tc.a", "value": 1},
                {"testId": "tc.b", "value": 2},
            ],
            "testModules": [{"moduleId": "tm.a", "tests": ["tc.a"]}],
        }

    def verify(self, base, head):
        return verify_append_safe_json(
            json.dumps(base),
            json.dumps(head),
            {"testCases": "testId", "testModules": "moduleId"},
        )

    def test_pure_append_passes(self):
        base = self.fixture()
        head = self.fixture()
        head["testCases"].append({"testId": "tc.c", "value": 3})
        result = self.verify(base, head)
        self.assertEqual(result["testCases"], ["tc.c"])

    def test_existing_object_mutation_fails(self):
        base = self.fixture()
        head = self.fixture()
        head["testCases"][0]["value"] = 99
        with self.assertRaises(ValueError):
            self.verify(base, head)

    def test_existing_identity_reorder_fails(self):
        base = self.fixture()
        head = self.fixture()
        head["testCases"] = list(reversed(head["testCases"]))
        with self.assertRaises(ValueError):
            self.verify(base, head)

    def test_duplicate_new_identity_fails(self):
        base = self.fixture()
        head = self.fixture()
        head["testCases"].append({"testId": "tc.a", "value": 9})
        with self.assertRaises(ValueError):
            self.verify(base, head)

    def test_global_semantic_field_mutation_fails(self):
        base = self.fixture()
        head = self.fixture()
        head["authority"] = {"owner": "F"}
        with self.assertRaises(ValueError):
            self.verify(base, head)

    def test_top_level_shape_change_fails(self):
        base = self.fixture()
        head = self.fixture()
        head["newGlobalPolicy"] = True
        with self.assertRaises(ValueError):
            self.verify(base, head)


if __name__ == "__main__":
    unittest.main()
