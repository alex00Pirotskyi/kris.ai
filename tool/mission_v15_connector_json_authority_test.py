#!/usr/bin/env python3
"""Adversarial regressions for explicit append-safe JSON authority relay."""
from __future__ import annotations

import json
import unittest

from mission_v15_connector_json_authority_apply import append_explicit_identities


COLLECTIONS = {
    "testCases": "testId",
    "testModules": "moduleId",
}

BASE = """{
  \"schemaVersion\": 1,
  \"testCases\": [
    {
      \"testId\": \"tc.base\",
      \"value\": \"keep-byte-shape\"
    }
  ],
  \"testModules\": [
    {
      \"moduleId\": \"tm.base\",
      \"value\": 1
    }
  ]
}
"""

SOURCE = """{
  \"schemaVersion\": 1,
  \"testCases\": [
    {
      \"testId\": \"tc.base\",
      \"value\": \"keep-byte-shape\"
    },
    {
      \"testId\": \"tc.requested\",
      \"value\": \"copy-me\"
    },
    {
      \"testId\": \"tc.unrequested\",
      \"value\": \"do-not-copy\"
    }
  ],
  \"testModules\": [
    {
      \"moduleId\": \"tm.base\",
      \"value\": 1
    },
    {
      \"moduleId\": \"tm.requested\",
      \"value\": 2
    }
  ]
}
"""


class ExplicitJsonAuthorityAppendTest(unittest.TestCase):
    def test_appends_only_explicit_identities_and_preserves_existing_bytes(self) -> None:
        updated, appended = append_explicit_identities(
            BASE,
            SOURCE,
            COLLECTIONS,
            {
                "testCases": ["tc.requested"],
                "testModules": ["tm.requested"],
            },
        )
        decoded = json.loads(updated)
        self.assertEqual(appended, {
            "testCases": ["tc.requested"],
            "testModules": ["tm.requested"],
        })
        self.assertEqual(
            [item["testId"] for item in decoded["testCases"]],
            ["tc.base", "tc.requested"],
        )
        self.assertEqual(
            [item["moduleId"] for item in decoded["testModules"]],
            ["tm.base", "tm.requested"],
        )
        self.assertNotIn("tc.unrequested", updated)
        self.assertIn(
            '    {\n      "testId": "tc.base",\n      "value": "keep-byte-shape"\n    }',
            updated,
        )

    def test_is_idempotent_when_requested_identity_already_matches(self) -> None:
        once, _ = append_explicit_identities(
            BASE,
            SOURCE,
            COLLECTIONS,
            {"testCases": ["tc.requested"]},
        )
        twice, appended = append_explicit_identities(
            once,
            SOURCE,
            COLLECTIONS,
            {"testCases": ["tc.requested"]},
        )
        self.assertEqual(twice, once)
        self.assertEqual(appended, {})

    def test_rejects_existing_identity_with_different_object(self) -> None:
        conflicting_source = SOURCE.replace(
            '"value": "keep-byte-shape"',
            '"value": "changed"',
            1,
        )
        with self.assertRaisesRegex(ValueError, "conflicts with source"):
            append_explicit_identities(
                BASE,
                conflicting_source,
                COLLECTIONS,
                {"testCases": ["tc.base"]},
            )

    def test_rejects_missing_source_identity(self) -> None:
        with self.assertRaisesRegex(ValueError, "missing from source commit"):
            append_explicit_identities(
                BASE,
                SOURCE,
                COLLECTIONS,
                {"testCases": ["tc.missing"]},
            )

    def test_rejects_duplicate_request_and_unknown_collection(self) -> None:
        with self.assertRaisesRegex(ValueError, "duplicate identities"):
            append_explicit_identities(
                BASE,
                SOURCE,
                COLLECTIONS,
                {"testCases": ["tc.requested", "tc.requested"]},
            )
        with self.assertRaisesRegex(ValueError, "unsupported collections"):
            append_explicit_identities(
                BASE,
                SOURCE,
                COLLECTIONS,
                {"notACollection": ["x"]},
            )


if __name__ == "__main__":
    unittest.main()
