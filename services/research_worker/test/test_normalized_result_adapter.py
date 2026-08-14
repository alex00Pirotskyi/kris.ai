from __future__ import annotations

import unittest

from tool import test_center_contracts as canonical
from tool.p4_001_test_center_v1 import CANONICAL_STATES, normalize_observed_state


class NormalizedResultAdapterTest(unittest.TestCase):
    def test_preserves_every_canonical_state_without_upgrade(self) -> None:
        observed = [normalize_observed_state(state) for state in CANONICAL_STATES]
        self.assertEqual(list(CANONICAL_STATES), observed)
        for state in observed:
            if state != "PASS":
                self.assertNotEqual("PASS", state)
        for invalid in (
            "passed",
            "PASS_WITH_WARNINGS",
            "BLOCKED_BY_SHARED_CONTRACT",
            "NOT_RUN",
        ):
            with self.subTest(invalid=invalid), self.assertRaises(
                canonical.ContractError
            ):
                normalize_observed_state(invalid)


if __name__ == "__main__":
    unittest.main()
