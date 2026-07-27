#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import access_profile_v2 as AP

ROOT = Path(__file__).resolve().parents[1]


class AccessProfileV2Test(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = AP.load_catalog(ROOT / "config/access_profiles.v2.json")

    def test_exact_canonical_profiles_exist(self) -> None:
        self.assertEqual(set(self.catalog), set(AP.PROFILE_IDS))

    def test_round_trip_is_stable(self) -> None:
        for profile in self.catalog.values():
            first = profile.canonical_json()
            second = AP.AccessProfileV2.from_json(profile.to_json()).canonical_json()
            self.assertEqual(first, second, profile.profile_id)

    def test_shared_invalid_vectors_are_rejected(self) -> None:
        fixture = json.loads(
            (ROOT / "evals/fixtures/p1_002_access_profiles/invalid_cases.json").read_text(encoding="utf-8")
        )
        for case in fixture["cases"]:
            with self.subTest(case=case["name"]):
                value = AP.apply_fixture_patch(
                    self.catalog[case["baseProfile"]].to_json(), case["patch"]
                )
                with self.assertRaisesRegex(AP.AccessProfileValidationError, case["errorContains"]):
                    AP.AccessProfileV2.from_json(value)

    def test_catalog_round_trips_from_disk(self) -> None:
        for profile in self.catalog.values():
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / f"{profile.profile_id}.json"
                path.write_text(json.dumps(profile.to_json()), encoding="utf-8")
                self.assertEqual(
                    profile.canonical_json(), AP.AccessProfileV2.from_file(path).canonical_json()
                )

    def test_owner_and_unattended_secret_boundaries(self) -> None:
        owner = self.catalog["owner"].to_json()
        unattended = self.catalog["owner_unattended"].to_json()
        self.assertFalse(owner["sandboxed"])
        self.assertEqual(owner["credentials"]["rawReveal"], "interactive_break_glass")
        self.assertFalse(unattended["sandboxed"])
        self.assertEqual(unattended["credentials"]["rawReveal"], "never")
        self.assertEqual(unattended["process"]["elevation"], "none")


if __name__ == "__main__":
    unittest.main(verbosity=2)
