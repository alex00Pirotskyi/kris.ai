#!/usr/bin/env python3
"""Focused regressions for immutable Product-head resolution."""
from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import unittest

THIS = pathlib.Path(__file__).resolve()
if str(THIS.parent) not in sys.path:
    sys.path.insert(0, str(THIS.parent))

from mission_v15_live_runtime_audit import resolve_product_head


class ProductHeadResolutionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="mission-v15-live-runtime-")
        self.repo = pathlib.Path(self.temp.name)
        self._git("init")
        self._git("config", "user.name", "Mission V1.5 Test")
        self._git("config", "user.email", "mission-v15-test@example.invalid")
        (self.repo / "product.txt").write_text("one\n", encoding="utf-8")
        self._git("add", "product.txt")
        self._git("commit", "-m", "one")
        self.first = self._git("rev-parse", "HEAD")

        (self.repo / "product.txt").write_text("two\n", encoding="utf-8")
        self._git("add", "product.txt")
        self._git("commit", "-m", "two")
        self.second = self._git("rev-parse", "HEAD")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _git(self, *args: str) -> str:
        result = subprocess.run(
            ["git", *args],
            cwd=self.repo,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(
                f"git {' '.join(args)} failed ({result.returncode}): {result.stderr}"
            )
        return result.stdout.strip()

    def test_live_source_branch_is_preferred(self) -> None:
        branch = "agent/example/product"
        self._git("update-ref", f"refs/remotes/origin/{branch}", self.first)
        self._git("update-ref", "refs/remotes/origin/pull/76/head", self.second)
        result = resolve_product_head(self.repo, branch, 76)
        self.assertEqual(result["head"], self.first)
        self.assertEqual(result["ref"], f"refs/remotes/origin/{branch}")
        self.assertTrue(result["sourceBranchPresent"])

    def test_deleted_source_branch_uses_immutable_pr_head(self) -> None:
        branch = "agent/deleted/product"
        self._git("update-ref", "refs/remotes/origin/pull/76/head", self.second)
        result = resolve_product_head(self.repo, branch, 76)
        self.assertEqual(result["head"], self.second)
        self.assertEqual(result["ref"], "refs/remotes/origin/pull/76/head")
        self.assertFalse(result["sourceBranchPresent"])

    def test_missing_branch_and_pr_ref_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, r"PR76:agent/missing/product"):
            resolve_product_head(self.repo, "agent/missing/product", 76)


if __name__ == "__main__":
    unittest.main()
