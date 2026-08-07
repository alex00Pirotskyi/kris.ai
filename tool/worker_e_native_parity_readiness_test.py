#!/usr/bin/env python3
from __future__ import annotations
import copy
import hashlib
import json
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
        self.commit = self.git("rev-parse", "HEAD")
        self.tree = self.git("rev-parse", "HEAD^{tree}")
        self.evidence_blob = self.git("rev-parse", f"{self.commit}:evidence.json")
        self.evidence_sha256 = hashlib.sha256(b"{}\n").hexdigest()

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args: str) -> str:
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True).strip()

    def commit_all(self, message: str) -> tuple[str, str]:
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.root), "commit", "-qm", message], check=True)
        return self.git("rev-parse", "HEAD"), self.git("rev-parse", "HEAD^{tree}")

    def ancestry(self):
        return {"bindingKind": "ANCESTRY_BASE", "branch": "main", "commit": self.commit, "tree": self.tree, "requiredAncestry": True}

    def immutable(self):
        return {
            "bindingKind": "IMMUTABLE_EVIDENCE_SNAPSHOT",
            "commit": self.commit,
            "tree": self.tree,
            "liveHeadClaimed": False,
            "evidencePaths": ["evidence.json"],
            "evidenceBindings": [{
                "path": "evidence.json",
                "gitBlob": self.evidence_blob,
                "sha256": self.evidence_sha256,
            }],
        }

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

    def test_immutable_snapshot_binds_snapshot_bytes_not_head(self):
        row = self.immutable()
        (self.root / "evidence.json").write_text('{"changed":true}\n')
        self.commit_all("change working evidence")
        binding.verify_binding(self.root, "workerA", row)

    def test_immutable_snapshot_rejects_wrong_blob(self):
        row = self.immutable()
        row["evidenceBindings"][0]["gitBlob"] = "3" * 40
        with self.assertRaisesRegex(binding.DependencyBindingError, "blob mismatch"):
            binding.verify_binding(self.root, "workerA", row)

    def test_immutable_snapshot_rejects_path_created_after_snapshot(self):
        row = self.immutable()
        row["evidencePaths"] = ["late.json"]
        (self.root / "late.json").write_text("{}\n")
        self.commit_all("add late evidence")
        late_blob = self.git("rev-parse", "HEAD:late.json")
        row["evidenceBindings"] = [{"path": "late.json", "gitBlob": late_blob}]
        with self.assertRaises(binding.DependencyBindingError):
            binding.verify_binding(self.root, "workerA", row)

    def test_immutable_review_binds_reviewed_candidate_and_purpose(self):
        reviewed_commit = self.commit
        reviewed_tree = self.tree
        artifact = {
            "candidate": {"commit": reviewed_commit, "tree": reviewed_tree},
            "reviewerRole": "Worker J",
            "decision": "PASS",
            "reviewType": "NO_CONFLICT_AND_ACTIVATION_STATE",
            "mission": "MISSION-010",
            "pullRequest": 71,
            "task": "P11-001 native readiness source foundation",
            "scope": {
                "activationState": True,
                "crossWorkerPathConflict": True,
                "nativeBehaviorSecurityReview": False,
                "testCenterOwnerReview": False,
            },
        }
        (self.root / "review.json").write_text(json.dumps(artifact, sort_keys=True) + "\n")
        snapshot_commit, snapshot_tree = self.commit_all("review artifact")
        blob = self.git("rev-parse", f"{snapshot_commit}:review.json")
        row = {
            "bindingKind": "IMMUTABLE_REVIEW_SNAPSHOT",
            "commit": snapshot_commit,
            "tree": snapshot_tree,
            "liveHeadClaimed": False,
            "evidencePaths": ["review.json"],
            "evidenceBindings": [{"path": "review.json", "gitBlob": blob}],
            "reviewArtifactPath": "review.json",
            "reviewedCommit": reviewed_commit,
            "reviewedTree": reviewed_tree,
            "reviewerRole": "Worker J",
            "decision": "PASS",
            "expectedReview": {
                "reviewType": "NO_CONFLICT_AND_ACTIVATION_STATE",
                "mission": "MISSION-010",
                "task": "P11-001 native readiness source foundation",
                "pullRequest": 71,
                "requiredScope": {
                    "activationState": True,
                    "crossWorkerPathConflict": True,
                    "nativeBehaviorSecurityReview": False,
                    "testCenterOwnerReview": False,
                },
            },
        }
        binding.verify_binding(self.root, "workerJ", row)

        wrong_candidate = copy.deepcopy(row)
        wrong_candidate["reviewedCommit"] = snapshot_commit
        with self.assertRaisesRegex(binding.DependencyBindingError, "candidate does not match"):
            binding.verify_binding(self.root, "workerJ", wrong_candidate)

        wrong_type = copy.deepcopy(row)
        wrong_type["expectedReview"]["reviewType"] = "NATIVE_SECURITY"
        with self.assertRaisesRegex(binding.DependencyBindingError, "review type mismatch"):
            binding.verify_binding(self.root, "workerJ", wrong_type)

        wrong_scope = copy.deepcopy(row)
        wrong_scope["expectedReview"]["requiredScope"]["nativeBehaviorSecurityReview"] = True
        with self.assertRaisesRegex(binding.DependencyBindingError, "review scope mismatch"):
            binding.verify_binding(self.root, "workerJ", wrong_scope)

        missing_requirement = copy.deepcopy(row)
        del missing_requirement["expectedReview"]
        with self.assertRaisesRegex(binding.DependencyBindingError, "lacks expected review requirement"):
            binding.verify_binding(self.root, "workerJ", missing_requirement)

    def test_live_head_resolves_real_ref_and_detects_ref_move(self):
        subprocess.run(["git", "-C", str(self.root), "branch", "candidate", self.commit], check=True)
        row = {
            "bindingKind": "LIVE_HEAD_AT_CANDIDATE",
            "commit": self.commit,
            "tree": self.tree,
            "ref": "refs/heads/candidate",
        }
        binding.verify_binding(self.root, "workerB", row)
        (self.root / "later.txt").write_text("later\n")
        later_commit, _ = self.commit_all("move candidate")
        subprocess.run(["git", "-C", str(self.root), "branch", "-f", "candidate", later_commit], check=True)
        with self.assertRaisesRegex(binding.DependencyBindingError, "live head drifted"):
            binding.verify_binding(self.root, "workerB", row)

    def test_live_head_rejects_self_attestation(self):
        row = {
            "bindingKind": "LIVE_HEAD_AT_CANDIDATE",
            "commit": self.commit,
            "tree": self.tree,
            "ref": "refs/heads/main",
            "resolvedHead": self.commit,
        }
        with self.assertRaisesRegex(binding.DependencyBindingError, "self-attested"):
            binding.verify_binding(self.root, "workerB", row)


if __name__ == "__main__":
    unittest.main(verbosity=2)
