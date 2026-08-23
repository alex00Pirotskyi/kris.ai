#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys
import unittest

TOOL = Path(__file__).resolve().parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from p11_native_conformance import load_contract, run_process, run_suite


class P11NativeConformanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report = run_suite()

    def test_contract_lineage_is_unique_and_current_host_behavior_passes(self) -> None:
        contract = load_contract()
        self.assertEqual(len(contract["fixtureIds"]), 25)
        self.assertEqual(len(set(contract["fixtureIds"])), 25)
        self.assertEqual(len(contract["semanticOperations"]), 24)
        self.assertEqual(len(contract["forbiddenFallbacks"]), 7)
        self.assertEqual(self.report["classification"], "BEHAVIORAL_CURRENT_HOST_ONLY")
        self.assertEqual(self.report["resultState"], "PASS")
        self.assertEqual(self.report["failedFixtureCount"], 0)
        self.assertGreaterEqual(self.report["passedFixtureCount"], 16)
        self.assertGreaterEqual(self.report["verifiedOperationCount"], 11)
        self.assertEqual(self.report["failedOperationCount"], 0)

    def test_behavioral_run_never_expands_to_support_or_native_parity_claim(self) -> None:
        claims = self.report["supportClaims"]
        self.assertFalse(claims["platformSupported"])
        self.assertFalse(claims["nativeParity"])
        self.assertFalse(claims["deviceAutomation"])
        self.assertFalse(claims["isolation"])
        self.assertFalse(claims["remoteMcp"])

    def test_process_output_is_bounded(self) -> None:
        result = run_process([sys.executable, "-c", "print('z'*20000)"], max_output=1024)
        self.assertTrue(result["stdoutTruncated"])
        self.assertLessEqual(len(result["stdout"].encode("utf-8")), 1024)
        self.assertEqual(result["cleanupState"], "COMPLETE")


if __name__ == "__main__":
    unittest.main()
