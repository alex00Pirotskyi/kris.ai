from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("worker_d_p3_dependency_binding.py")
SPEC = importlib.util.spec_from_file_location(
    "worker_d_p3_dependency_binding",
    MODULE_PATH,
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
ROOT = Path(__file__).resolve().parents[1]


def dependency_document() -> dict:
    return json.loads((ROOT / MODULE.DOCUMENT_PATH).read_text(encoding="utf-8"))


def dependency(document: dict, task_id: str) -> dict:
    return next(item for item in document["dependencies"] if item["taskId"] == task_id)


class DependencyBindingTests(unittest.TestCase):
    def test_repository_bindings_pass(self):
        self.assertEqual([], MODULE.validate(ROOT))

    def test_nonexistent_commit_fails(self):
        mutated = copy.deepcopy(dependency_document())
        mutated["dependencies"][0]["implementation"]["commit"] = "f" * 40
        self.assertTrue(
            any(
                "commit does not resolve" in error
                for error in MODULE.validate_document(ROOT, mutated)
            )
        )

    def test_commit_tree_mismatch_fails(self):
        document = dependency_document()
        mutated = copy.deepcopy(document)
        mutated["dependencies"][0]["implementation"]["tree"] = (
            document["dependencies"][1]["implementation"]["tree"]
        )
        self.assertTrue(
            any(
                "tree mismatch" in error
                for error in MODULE.validate_document(ROOT, mutated)
            )
        )

    def test_malformed_git_identity_fails(self):
        mutated = copy.deepcopy(dependency_document())
        mutated["repository"]["protectedMain"]["commit"] = "not-a-git-object"
        self.assertTrue(
            any(
                "repository.protectedMain.commit must be a 40-character" in error
                for error in MODULE.validate_document(ROOT, mutated)
            )
        )

    def test_worker_d_synchronization_pair_is_checked(self):
        mutated = copy.deepcopy(dependency_document())
        mutated["repository"]["workerD"]["synchronizationTree"] = "0" * 40
        self.assertTrue(
            any(
                "repository.workerD tree mismatch" in error
                for error in MODULE.validate_document(ROOT, mutated)
            )
        )

    def test_duplicate_dependency_task_fails(self):
        mutated = copy.deepcopy(dependency_document())
        mutated["dependencies"].append(copy.deepcopy(mutated["dependencies"][0]))
        self.assertTrue(
            any(
                "duplicate dependency taskId" in error
                for error in MODULE.validate_document(ROOT, mutated)
            )
        )

    def test_p1_status_rewrite_fails_with_same_commit_tree(self):
        mutated = copy.deepcopy(dependency_document())
        dependency(mutated, "P1-012")["authoritativeStatus"] = "BLOCKED"
        self.assertTrue(
            any(
                "P1-012 authoritativeStatus" in error
                for error in MODULE.validate_document(ROOT, mutated)
            )
        )

    def test_p1_owner_review_rewrite_fails_with_same_commit_tree(self):
        mutated = copy.deepcopy(dependency_document())
        dependency(mutated, "P1-012")["review"]["ownerApproval"] = "MISSING"
        self.assertTrue(
            any(
                "P1-012 ownerApproval" in error
                for error in MODULE.validate_document(ROOT, mutated)
            )
        )

    def test_p1_independent_review_cannot_advance_without_receipt(self):
        mutated = copy.deepcopy(dependency_document())
        dependency(mutated, "P1-012")["review"]["independentReview"] = "PASS"
        self.assertTrue(
            any(
                "P1-012 independentReview cannot advance" in error
                for error in MODULE.validate_document(ROOT, mutated)
            )
        )

    def test_p1_test_claim_rewrite_fails_with_same_commit_tree(self):
        mutated = copy.deepcopy(dependency_document())
        dependency(mutated, "P1-012")["tests"]["caseCount"] = 999
        self.assertTrue(
            any(
                "P1-012 tests.caseCount" in error
                for error in MODULE.validate_document(ROOT, mutated)
            )
        )

    def test_evidence_path_rewrite_fails_even_when_commit_tree_stay_valid(self):
        mutated = copy.deepcopy(dependency_document())
        item = dependency(mutated, "P1-012")
        item["evidencePaths"][0] = "README.md"
        self.assertTrue(
            any(
                "P1-012.evidencePaths" in error
                for error in MODULE.validate_document(ROOT, mutated)
            )
        )

    def test_p2_measurement_rewrite_fails_with_same_commit_tree(self):
        mutated = copy.deepcopy(dependency_document())
        dependency(mutated, "P2-004")["measurements"]["startup"] = "PASS"
        self.assertTrue(
            any(
                "P2-004 measurement claims" in error
                for error in MODULE.validate_document(ROOT, mutated)
            )
        )

    def test_p2_owner_review_rewrite_fails_with_same_commit_tree(self):
        mutated = copy.deepcopy(dependency_document())
        dependency(mutated, "P2-004")["review"]["ownerApproval"] = "PASS"
        self.assertTrue(
            any(
                "P2-004 review claims" in error
                for error in MODULE.validate_document(ROOT, mutated)
            )
        )

    def test_p2_decision_rewrite_fails_with_same_commit_tree(self):
        mutated = copy.deepcopy(dependency_document())
        dependency(mutated, "P2-004")["decision"] = "READY"
        self.assertTrue(
            any(
                "P2-004 decision" in error
                for error in MODULE.validate_document(ROOT, mutated)
            )
        )

    def test_dependency_commit_must_belong_to_worker_a_lineage(self):
        mutated = copy.deepcopy(dependency_document())
        unrelated_commit = "7eecc840f68ca0dff13ab58c138845593254e390"
        unrelated_tree = MODULE._git(ROOT, "rev-parse", f"{unrelated_commit}^{{tree}}")
        item = dependency(mutated, "P1-012")
        item["implementation"] = {
            "commit": unrelated_commit,
            "tree": unrelated_tree,
        }
        errors = MODULE.validate_document(ROOT, mutated)
        self.assertTrue(
            any(
                "P1-012 implementation is outside repository.workerADependencyCandidate lineage"
                in error
                for error in errors
            )
        )

    def test_p2_implementation_must_equal_worker_a_dependency_candidate(self):
        mutated = copy.deepcopy(dependency_document())
        p1 = dependency(mutated, "P1-012")["implementation"]
        dependency(mutated, "P2-004")["implementation"] = copy.deepcopy(p1)
        errors = MODULE.validate_document(ROOT, mutated)
        self.assertTrue(
            any(
                "P2-004 implementation must equal repository.workerADependencyCandidate"
                in error
                for error in errors
            )
        )


if __name__ == "__main__":
    unittest.main()
