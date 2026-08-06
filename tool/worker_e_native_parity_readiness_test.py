#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import worker_e_dependency_binding as binding

class DependencyBindingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        subprocess.run(["git", "-C", str(self.root), "config", "user.email", "test@example.com"], check=True)
        subprocess.run(["git", "-C", str(self.root), "config", "user.name", "Test"], check=True)
        (self.root / "evidence.json").write_text("{}\n")
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.root), "commit", "-qm", "base"], check=True)
        self.commit = subprocess.check_output(["git", "-C", str(self.root), "rev-parse", "HEAD"], text=True).strip()
        self.tree = subprocess.check_output(["git", "-C", str(self.root), "rev-parse", "HEAD^{tree}"], text=True).strip()
    def tearDown(self):
        self.temp.cleanup()
    def ancestry(self):
        return {"bindingKind": "ANCESTRY_BASE", "branch": "main", "commit": self.commit, "tree": self.tree, "requiredAncestry": True}
    def test_exact_ancestry_passes(self):
        binding.verify_binding(self.root, "protectedMain", self.ancestry())
    def test_nonexistent_commit_fails(self):
        row = self.ancestry(); row["commit"] = "1" * 40
        with self.assertRaises(binding.DependencyBindingError):
            binding.verify_binding(self.root, "protectedMain", row)
    def test_tree_mismatch_fails(self):
        row = self.ancestry(); row["tree"] = "2" * 40
        with self.assertRaisesRegex(binding.DependencyBindingError, "commit/tree mismatch"):
            binding.verify_binding(self.root, "protectedMain", row)
    def test_missing_ancestry_fails(self):
        subprocess.run(["git", "-C", str(self.root), "checkout", "--orphan", "other"], check=True, stdout=subprocess.DEVNULL)
        for child in self.root.iterdir():
            if child.name != ".git" and child.is_file(): child.unlink()
        (self.root / "other.txt").write_text("other\n")
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.root), "commit", "-qm", "other"], check=True)
        with self.assertRaisesRegex(binding.DependencyBindingError, "required ancestry"):
            binding.verify_binding(self.root, "protectedMain", self.ancestry())
    def test_ambiguous_kind_fails(self):
        with self.assertRaisesRegex(binding.DependencyBindingError, "ambiguous"):
            binding.verify_binding(self.root, "workerA", {"commit": self.commit, "tree": self.tree})
    def test_live_head_drift_fails(self):
        row = {"bindingKind": "LIVE_HEAD_AT_CANDIDATE", "commit": self.commit, "tree": self.tree, "resolvedHead": self.commit, "observedRemoteHead": "3" * 40}
        with self.assertRaisesRegex(binding.DependencyBindingError, "live head drifted"):
            binding.verify_binding(self.root, "workerB", row)

if __name__ == "__main__":
    unittest.main(verbosity=2)
