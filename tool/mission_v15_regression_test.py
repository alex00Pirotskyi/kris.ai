#!/usr/bin/env python3
"""Mission Execution 1.5 runtime/delivery regression tests."""
from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import unittest

THIS = pathlib.Path(__file__).resolve()
TOOL = THIS.parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from mission_runtime_control import (
    pattern_within,
    prefixes_overlap,
    verify_candidate_ancestry,
    verify_git_base,
)
from mission_delivery_lib import DeliveryError
from mission_delivery_strict import validate_review_receipt
from mission_v15_connector_authority_apply import _append_dart_set_entry
from mission_v15_hygiene import classify_branch_capacity
from mission_v15_legacy_branch_reap import cleanup_class_for


def git(root: pathlib.Path, *args: str) -> str:
    result = subprocess.run(["git", *args], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    return result.stdout.strip()


class RuntimeGitBindingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        git(self.root, "init")
        git(self.root, "config", "user.email", "v15@example.invalid")
        git(self.root, "config", "user.name", "Mission V15 Test")
        (self.root / "a.txt").write_text("a\n", encoding="utf-8")
        git(self.root, "add", "a.txt")
        git(self.root, "commit", "-m", "base")
        self.base = git(self.root, "rev-parse", "HEAD")
        self.tree = git(self.root, "rev-parse", "HEAD^{tree}")
        (self.root / "b.txt").write_text("b\n", encoding="utf-8")
        git(self.root, "add", "b.txt")
        git(self.root, "commit", "-m", "child")
        self.child = git(self.root, "rev-parse", "HEAD")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_exact_commit_tree_binding_passes(self) -> None:
        verify_git_base(self.root, self.base, self.tree)

    def test_wrong_tree_fails(self) -> None:
        with self.assertRaises(ValueError):
            verify_git_base(self.root, self.base, "0" * 40)

    def test_candidate_must_descend_from_reserved_base(self) -> None:
        verify_candidate_ancestry(self.root, self.base, self.child)
        git(self.root, "checkout", "--orphan", "other")
        git(self.root, "rm", "-rf", ".")
        (self.root / "other.txt").write_text("x\n", encoding="utf-8")
        git(self.root, "add", "other.txt")
        git(self.root, "commit", "-m", "other")
        other = git(self.root, "rev-parse", "HEAD")
        with self.assertRaises(ValueError):
            verify_candidate_ancestry(self.root, self.base, other)

    def test_path_overlap_is_scoped(self) -> None:
        self.assertTrue(prefixes_overlap("lib/product/model/**", "lib/product/model/a.dart"))
        self.assertFalse(prefixes_overlap("lib/product/model/**", "test/product/model/**"))

    def test_concrete_file_matches_basename_glob_policy(self) -> None:
        self.assertTrue(
            pattern_within(
                "tool/test_center_contracts_test.py",
                "tool/test_center*.py",
            )
        )

    def test_basename_glob_does_not_cross_directory_boundary(self) -> None:
        self.assertFalse(
            pattern_within(
                "tool/test_center/contract.py",
                "tool/test_center*.py",
            )
        )

    def test_recursive_evidence_glob_matches_concrete_descendant(self) -> None:
        self.assertTrue(
            pattern_within(
                "release/evidence/P5-001/sub/result.json",
                "release/evidence/P5-*/**",
            )
        )


class ConnectorAuthorityMutationTests(unittest.TestCase):
    def test_append_preserves_all_bytes_outside_governed_set(self) -> None:
        source = (
            "prefix\n"
            "const expected = <String>{\n"
            "  'lib/a.dart',\n"
            "  'lib/b.dart',\n"
            "};\n"
            "suffix\n"
        )
        updated, changed = _append_dart_set_entry(
            source,
            marker="const expected = <String>{",
            value="lib/c.dart",
        )
        self.assertTrue(changed)
        self.assertEqual(
            updated,
            (
                "prefix\n"
                "const expected = <String>{\n"
                "  'lib/a.dart',\n"
                "  'lib/b.dart',\n"
                "  'lib/c.dart',\n"
                "};\n"
                "suffix\n"
            ),
        )

    def test_append_is_idempotent_when_entry_already_exists(self) -> None:
        source = "const expected = <String>{\n  'lib/a.dart',\n};\n"
        updated, changed = _append_dart_set_entry(
            source,
            marker="const expected = <String>{",
            value="lib/a.dart",
        )
        self.assertFalse(changed)
        self.assertEqual(updated, source)


class BranchCapacityRegressionTests(unittest.TestCase):
    def policy(self) -> dict:
        return {
            "migration": {
                "maxTotalBranchesDuringMigration": 150,
                "maxLegacyDebtBranchesDuringMigration": 25,
                "maxActiveHelperBranches": 20,
            },
            "branchCapacity": {
                "softTotalBranchTarget": 80,
                "hardNewBranchCreationCeiling": 150,
            },
        }

    def test_ordinary_execution_is_not_blocked_by_old_sixty_branch_threshold(self) -> None:
        capacity = classify_branch_capacity(
            self.policy(),
            total_branch_count=62,
            legacy_debt_count=10,
            helper_branch_count=12,
        )
        self.assertFalse(capacity["newBranchCreationBlocked"])
        self.assertEqual(capacity["warnings"], [])

    def test_soft_pressure_is_reported_without_becoming_creation_block(self) -> None:
        capacity = classify_branch_capacity(
            self.policy(),
            total_branch_count=81,
            legacy_debt_count=26,
            helper_branch_count=21,
        )
        self.assertFalse(capacity["newBranchCreationBlocked"])
        self.assertIn("TOTAL_BRANCH_SOFT_TARGET:81>80", capacity["warnings"])
        self.assertIn("LEGACY_DEBT_PRESSURE:26>25", capacity["warnings"])
        self.assertIn("HELPER_BRANCH_PRESSURE:21>20", capacity["warnings"])

    def test_hard_ceiling_blocks_new_branch_creation(self) -> None:
        capacity = classify_branch_capacity(
            self.policy(),
            total_branch_count=150,
            legacy_debt_count=10,
            helper_branch_count=12,
        )
        self.assertTrue(capacity["newBranchCreationBlocked"])

    def test_exact_incident_probe_is_cleanup_eligible_without_wildcarding_root(self) -> None:
        self.assertEqual(
            cleanup_class_for(
                "THIS_MUST_NOT_BE_CREATED",
                ["ci/*", "validation/*"],
                [],
                ["THIS_MUST_NOT_BE_CREATED"],
            ),
            "superseded-repair",
        )
        with self.assertRaises(ValueError):
            cleanup_class_for(
                "another_unapproved_root_ref",
                ["ci/*", "validation/*"],
                [],
                ["THIS_MUST_NOT_BE_CREATED"],
            )


class ReviewIdentityTests(unittest.TestCase):
    def receipt(self, tier: str) -> dict:
        return {
            "candidateCommit": "1" * 40,
            "candidateTree": "2" * 40,
            "decision": "PASS",
            "reviewTier": tier,
            "reviewerWorkerIdentity": "I",
            "reviewerGitHubIdentity": "reviewer",
            "implementerGitHubIdentity": "implementer",
            "reviewContextId": "REV-I-1",
            "authoringContextIds": ["REV-I-1"],
            "implementerAuthoringContextIds": ["WRK-G-1"],
            "scopes": ["SOURCE"]
        }

    def test_r1_distinct_context_passes(self) -> None:
        validate_review_receipt(self.receipt("R1"), candidate_commit="1" * 40, record_path=pathlib.Path("record.json"))

    def test_r1_author_context_contamination_fails(self) -> None:
        value = self.receipt("R1")
        value["implementerAuthoringContextIds"] = ["REV-I-1"]
        with self.assertRaises(DeliveryError):
            validate_review_receipt(value, candidate_commit="1" * 40, record_path=pathlib.Path("record.json"))

    def test_r2_same_github_identity_fails(self) -> None:
        value = self.receipt("R2")
        value["implementerGitHubIdentity"] = "same"
        value["reviewerGitHubIdentity"] = "same"
        with self.assertRaises(DeliveryError):
            validate_review_receipt(value, candidate_commit="1" * 40, record_path=pathlib.Path("record.json"))

    def test_r0_cannot_satisfy_terminal_acceptance(self) -> None:
        with self.assertRaises(DeliveryError):
            validate_review_receipt(self.receipt("R0"), candidate_commit="1" * 40, record_path=pathlib.Path("record.json"))


if __name__ == "__main__":
    unittest.main()
