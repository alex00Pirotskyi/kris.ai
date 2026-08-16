#!/usr/bin/env python3
"""Regressions for the commit-bound runtime atomicity debt baseline."""
from __future__ import annotations

import pathlib
import sys
import unittest

THIS = pathlib.Path(__file__).resolve()
TOOL = THIS.parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from mission_v15_runtime_atomicity_baseline import (
    compare_historical_debt,
    normalize_debt_records,
    require_full_sha,
)


COMMIT_A = "a" * 40
COMMIT_B = "b" * 40


class RuntimeAtomicityBaselineTests(unittest.TestCase):
    def configured(self) -> list[dict[str, object]]:
        return [
            {
                "commit": COMMIT_A,
                "runtimeGeneration": 623,
                "violations": [
                    "GENERATION_EVENT_ATOMICITY:eventChanges=0,added=0"
                ],
            }
        ]

    def normalized_actual(self) -> dict[str, dict[str, object]]:
        return {
            COMMIT_A: {
                "commit": COMMIT_A,
                "runtimeGeneration": 623,
                "violations": [
                    "GENERATION_EVENT_ATOMICITY:eventChanges=0,added=0"
                ],
            }
        }

    def test_exact_commit_bound_debt_passes(self) -> None:
        configured = normalize_debt_records(
            self.configured(),
            enforce_from_generation=627,
        )
        self.assertEqual(
            compare_historical_debt(
                configured=configured,
                actual=self.normalized_actual(),
            ),
            self.configured(),
        )

    def test_unrecorded_historical_violation_fails(self) -> None:
        configured = normalize_debt_records(
            self.configured(),
            enforce_from_generation=627,
        )
        actual = self.normalized_actual()
        actual[COMMIT_B] = {
            "commit": COMMIT_B,
            "runtimeGeneration": 624,
            "violations": ["RUNTIME_CHANGE_WITHOUT_META"],
        }
        with self.assertRaisesRegex(
            ValueError,
            "HISTORICAL_VIOLATION_DEBT_COMMIT_SET_MISMATCH",
        ):
            compare_historical_debt(
                configured=configured,
                actual=actual,
            )

    def test_stale_configured_debt_fails(self) -> None:
        configured_rows = self.configured()
        configured_rows.append(
            {
                "commit": COMMIT_B,
                "runtimeGeneration": 624,
                "violations": ["RUNTIME_CHANGE_WITHOUT_META"],
            }
        )
        configured = normalize_debt_records(
            configured_rows,
            enforce_from_generation=627,
        )
        with self.assertRaisesRegex(
            ValueError,
            "HISTORICAL_VIOLATION_DEBT_COMMIT_SET_MISMATCH",
        ):
            compare_historical_debt(
                configured=configured,
                actual=self.normalized_actual(),
            )

    def test_violation_relabeling_fails(self) -> None:
        configured = normalize_debt_records(
            self.configured(),
            enforce_from_generation=627,
        )
        actual = self.normalized_actual()
        actual[COMMIT_A]["violations"] = ["RUNTIME_CHANGE_WITHOUT_META"]
        with self.assertRaisesRegex(
            ValueError,
            "HISTORICAL_VIOLATION_DEBT_VIOLATIONS_MISMATCH",
        ):
            compare_historical_debt(
                configured=configured,
                actual=actual,
            )

    def test_debt_cannot_excuse_baseline_or_descendant(self) -> None:
        rows = self.configured()
        rows[0]["runtimeGeneration"] = 627
        with self.assertRaisesRegex(
            ValueError,
            "HISTORICAL_VIOLATION_DEBT_GENERATION_INVALID",
        ):
            normalize_debt_records(
                rows,
                enforce_from_generation=627,
            )

    def test_debt_violation_list_must_be_canonical(self) -> None:
        rows = self.configured()
        rows[0]["violations"] = [
            "RUNTIME_CHANGE_WITHOUT_META",
            "GENERATION_EVENT_ATOMICITY:eventChanges=0,added=0",
        ]
        with self.assertRaisesRegex(
            ValueError,
            "HISTORICAL_VIOLATION_DEBT_VIOLATIONS_NOT_CANONICAL",
        ):
            normalize_debt_records(
                rows,
                enforce_from_generation=627,
            )

    def test_full_sha_is_required(self) -> None:
        self.assertEqual(require_full_sha(COMMIT_A, "TEST"), COMMIT_A)
        with self.assertRaisesRegex(ValueError, "TEST_INVALID"):
            require_full_sha("ABC", "TEST")


if __name__ == "__main__":
    unittest.main()
