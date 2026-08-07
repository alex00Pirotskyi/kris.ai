#!/usr/bin/env python3
"""Mission Execution 1.5 source-landing semantic regressions."""
from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import unittest

THIS = pathlib.Path(__file__).resolve()
if str(THIS.parent) not in sys.path:
    sys.path.insert(0, str(THIS.parent))

from mission_delivery_lib import DeliveryError
from mission_delivery_strict import LINEAR_LANDING_MODE, validate_source_landing
from mission_v15_landing_gate import _promotes_without_acceptance


class LandingSemanticsTests(unittest.TestCase):
    def base(self):
        return {
            "task": "P6-001",
            "status": "VALIDATION",
            "sourceLanding": "LANDED_MAIN",
            "behavioralSupport": "NOT_EVALUATED",
            "platformSupport": "NOT_ESTABLISHED",
            "releaseSupport": "UNSUPPORTED",
            "productionReadiness": "NOT_CLAIMED",
            "gaReadiness": "NOT_CLAIMED",
            "supportPromotion": False,
        }

    def test_truthful_source_only_landing_passes(self):
        self.assertEqual(_promotes_without_acceptance(self.base()), [])

    def test_platform_support_promotion_fails(self):
        value = self.base()
        value["platformSupport"] = "SUPPORTED"
        self.assertTrue(_promotes_without_acceptance(value))

    def test_release_support_promotion_fails(self):
        value = self.base()
        value["releaseSupport"] = "SUPPORTED"
        self.assertTrue(_promotes_without_acceptance(value))

    def test_ga_promotion_fails(self):
        value = self.base()
        value["gaReadiness"] = "GA_READY"
        self.assertTrue(_promotes_without_acceptance(value))

    def test_explicit_support_promotion_flag_fails(self):
        value = self.base()
        value["supportPromotion"] = True
        self.assertTrue(_promotes_without_acceptance(value))

    def test_accepted_record_is_not_rejected_by_source_only_rule(self):
        value = self.base()
        value["status"] = "ACCEPTED"
        value["platformSupport"] = "SUPPORTED"
        self.assertEqual(_promotes_without_acceptance(value), [])


class LinearLandingProofTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mission-v15-linear-landing-")
        self.repo = pathlib.Path(self.temp.name)
        self._git("init")
        self._git("config", "user.name", "Mission V1.5 Test")
        self._git("config", "user.email", "mission-v15-test@example.invalid")
        (self.repo / "product.txt").write_text("base\n", encoding="utf-8")
        self._git("add", "product.txt")
        self._git("commit", "-m", "base")
        self.base_commit = self._git("rev-parse", "HEAD")

        (self.repo / "product.txt").write_text("candidate\n", encoding="utf-8")
        self._git("add", "product.txt")
        self._git("commit", "-m", "candidate")
        self.candidate = self._git("rev-parse", "HEAD")
        self.candidate_tree = self._git("rev-parse", f"{self.candidate}^{{tree}}")

    def tearDown(self):
        self.temp.cleanup()

    def _git(self, *args: str, input_text: str | None = None) -> str:
        result = subprocess.run(
            ["git", *args],
            cwd=self.repo,
            text=True,
            input=input_text,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(
                f"git {' '.join(args)} failed ({result.returncode}): {result.stderr}"
            )
        return result.stdout.strip()

    def _commit_tree(self, tree: str, parent: str, message: str) -> str:
        return self._git(
            "commit-tree",
            tree,
            "-p",
            parent,
            input_text=message + "\n",
        )

    def _linear_record(self, merged: str, merged_tree: str | None = None) -> dict:
        return {
            "sourceLanding": "LANDED_MAIN",
            "commit": self.candidate,
            "tree": self.candidate_tree,
            "mergedMainCommit": merged,
            "sourceLandingProof": {
                "mode": LINEAR_LANDING_MODE,
                "landingBaseCommit": self.base_commit,
                "mergedMainTree": merged_tree or self.candidate_tree,
            },
        }

    def test_tree_equivalent_linear_landing_passes(self):
        landed = self._commit_tree(
            self.candidate_tree,
            self.base_commit,
            "squash-equivalent landing",
        )
        self.assertNotEqual(landed, self.candidate)
        validate_source_landing(
            self.repo,
            self._linear_record(landed),
            pathlib.Path("linear.json"),
        )

    def test_tree_equivalent_linear_landing_rejects_tree_drift(self):
        (self.repo / "product.txt").write_text("different-main-tree\n", encoding="utf-8")
        self._git("add", "product.txt")
        drift_tree = self._git("write-tree")
        landed = self._commit_tree(drift_tree, self.base_commit, "drifted landing")
        with self.assertRaises(DeliveryError):
            validate_source_landing(
                self.repo,
                self._linear_record(landed, drift_tree),
                pathlib.Path("tree-drift.json"),
            )

    def test_tree_equivalent_linear_landing_rejects_wrong_parent(self):
        landed = self._commit_tree(
            self.candidate_tree,
            self.candidate,
            "wrong-parent landing",
        )
        with self.assertRaises(DeliveryError):
            validate_source_landing(
                self.repo,
                self._linear_record(landed),
                pathlib.Path("wrong-parent.json"),
            )

    def test_legacy_ancestry_landing_remains_valid(self):
        landed = self._commit_tree(
            self.candidate_tree,
            self.candidate,
            "legacy descendant landing",
        )
        validate_source_landing(
            self.repo,
            {
                "sourceLanding": "LANDED_MAIN",
                "commit": self.candidate,
                "mergedMainCommit": landed,
            },
            pathlib.Path("legacy.json"),
        )


if __name__ == "__main__":
    unittest.main()
