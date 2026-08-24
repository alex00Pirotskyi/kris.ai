#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest

TOOL = Path(__file__).resolve().parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from p10_release_readiness import ReadinessError, _load, evaluate_readiness


def complete_input():
    platform = {
        "behaviorVerified": True,
        "featureParityPercent": 100,
        "deviceAutomationVerified": True,
        "isolationVerified": True,
        "remoteMcpVerified": True,
    }
    return {
        "schemaVersion": 1,
        "candidate": {"sourceCommit": "c" * 40, "version": "1.9.0+190", "releasePlatforms": ["linux"]},
        "p1ToP8": {"evidenceCurrent": True},
        "p9": {
            "releaseBundleVerified": True,
            "dependencyLocksVerified": True,
            "sbomVerified": True,
            "reproducibleBuildVerified": True,
            "updateAuthenticationVerified": True,
            "rollbackVerified": True,
            "cleanInstallVerified": True,
            "upgradeVerified": True,
            "privacyAuditClosed": True,
            "penetrationReview": {"present": True, "critical": 0, "high": 0},
            "soakHours": 24,
            "soakCrashCount": 0,
            "signedArtifacts": {"linux": True, "windows": False, "macos": False},
            "nativeInstallers": {"linux": True, "windows": False, "macos": False},
            "cleanMachine": {"linux": True, "windows": False, "macos": False},
        },
        "p10": {
            "betaUsers": 100,
            "betaDays": 14,
            "betaSev1Count": 0,
            "rcSoakDays": 7,
            "rcCrashCount": 0,
            "docsRunbookReady": True,
            "synchronizedReleaseDryRun": True,
            "humanUsabilityApproved": True,
        },
        "p11": {"platforms": {"linux": dict(platform), "windows": {}, "macos": {}}},
    }


class P10ReadinessTest(unittest.TestCase):
    def test_missing_evidence_blocks_every_promotion(self) -> None:
        report = evaluate_readiness({"schemaVersion": 1})
        self.assertEqual(report["resultState"], "BLOCKED")
        self.assertFalse(report["p9"]["complete"])
        self.assertFalse(report["p10"]["betaExitReady"])
        self.assertFalse(report["p10"]["rcReady"])
        self.assertFalse(report["p10"]["gaReady"])
        codes = {row["code"] for row in report["p10"]["gaBlockers"]}
        self.assertIn("candidate.source_identity_missing", codes)
        self.assertIn("candidate.version_invalid", codes)
        self.assertIn("p9.penetration_review_missing", codes)
        self.assertIn("p10.human_usability_missing", codes)

    def test_complete_single_platform_evidence_can_pass_without_claiming_native_parity(self) -> None:
        report = evaluate_readiness(complete_input())
        self.assertEqual(report["resultState"], "PASS")
        self.assertTrue(report["p9"]["complete"])
        self.assertTrue(report["p10"]["betaExitReady"])
        self.assertTrue(report["p10"]["rcReady"])
        self.assertTrue(report["p10"]["gaReady"])
        self.assertTrue(report["p11"]["platformMatrix"]["linux"]["supportClaimed"])
        self.assertFalse(report["p11"]["platformMatrix"]["windows"]["supportClaimed"])
        self.assertFalse(report["p11"]["nativeParityClaimed"])

    def test_missing_zero_security_counts_fail_closed(self) -> None:
        data = complete_input()
        data["p9"]["penetrationReview"] = {"present": True}
        report = evaluate_readiness(data)
        codes = {row["code"] for row in report["p9"]["blockers"]}
        self.assertIn("p9.security_findings_open", codes)
        self.assertFalse(report["p10"]["gaReady"])

    def test_platform_behavior_gate_blocks_only_requested_release_claim(self) -> None:
        data = complete_input()
        data["p11"]["platforms"]["linux"]["featureParityPercent"] = 94.9
        report = evaluate_readiness(data)
        self.assertFalse(report["p11"]["platformMatrix"]["linux"]["supportClaimed"])
        codes = {row["code"] for row in report["p10"]["gaBlockers"]}
        self.assertIn("platform.linux.feature_parity_below_95", codes)
        self.assertFalse(report["p10"]["gaReady"])

    def test_unsigned_release_platform_blocks_p9_and_ga(self) -> None:
        data = complete_input()
        data["p9"]["signedArtifacts"]["linux"] = False
        report = evaluate_readiness(data)
        self.assertFalse(report["p9"]["complete"])
        self.assertFalse(report["p10"]["gaReady"])
        self.assertFalse(report["p11"]["platformMatrix"]["linux"]["supportClaimed"])

    def test_non_finite_and_out_of_range_numbers_cannot_bypass_gates(self) -> None:
        data = complete_input()
        data["p9"]["soakHours"] = float("inf")
        data["p10"]["betaDays"] = float("nan")
        data["p10"]["rcSoakDays"] = float("inf")
        data["p11"]["platforms"]["linux"]["featureParityPercent"] = 101
        report = evaluate_readiness(data)
        p9_codes = {row["code"] for row in report["p9"]["blockers"]}
        ga_codes = {row["code"] for row in report["p10"]["gaBlockers"]}
        self.assertIn("p9.soak_incomplete", p9_codes)
        self.assertIn("p10.beta_duration_below_14_days", ga_codes)
        self.assertIn("p10.rc_soak_below_7_days", ga_codes)
        self.assertIn("platform.linux.feature_parity_below_95", ga_codes)
        self.assertFalse(report["p10"]["gaReady"])

    def test_unknown_or_duplicate_release_platforms_fail_closed(self) -> None:
        for platforms in (["linux", "solaris"], ["linux", "linux"]):
            with self.subTest(platforms=platforms):
                data = complete_input()
                data["candidate"]["releasePlatforms"] = platforms
                report = evaluate_readiness(data)
                codes = {row["code"] for row in report["p10"]["gaBlockers"]}
                self.assertIn("candidate.release_platforms_invalid", codes)
                self.assertFalse(report["p10"]["gaReady"])

    def test_invalid_candidate_version_fails_closed(self) -> None:
        data = complete_input()
        data["candidate"]["version"] = "latest"
        report = evaluate_readiness(data)
        codes = {row["code"] for row in report["p10"]["gaBlockers"]}
        self.assertIn("candidate.version_invalid", codes)
        self.assertFalse(report["p10"]["gaReady"])

    def test_json_loader_rejects_nan_and_infinity(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p10-nonfinite-") as td:
            path = Path(td) / "input.json"
            for literal in ("NaN", "Infinity", "-Infinity"):
                with self.subTest(literal=literal):
                    path.write_text('{"schemaVersion":1,"p10":{"betaDays":' + literal + '}}', encoding="utf-8")
                    with self.assertRaises(ReadinessError) as caught:
                        _load(path)
                    self.assertEqual(caught.exception.code, "input_invalid")


if __name__ == "__main__":
    unittest.main()
