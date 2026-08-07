from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("worker_d_p3_dependency_binding.py")
SPEC = importlib.util.spec_from_file_location("worker_d_p3_dependency_binding", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
ROOT = Path(__file__).resolve().parents[1]


def dependency_document() -> dict:
    return json.loads((ROOT / MODULE.DOCUMENT_PATH).read_text(encoding="utf-8"))


class DependencyBindingTests(unittest.TestCase):
    def test_repository_bindings_pass(self):
        self.assertEqual([], MODULE.validate(ROOT))

    def test_nonexistent_commit_fails(self):
        document = dependency_document()
        mutated = copy.deepcopy(document)
        mutated["dependencies"][0]["implementation"]["commit"] = "f" * 40
        errors = MODULE.validate_document(ROOT, mutated)
        self.assertTrue(any("commit does not resolve" in error for error in errors))

    def test_commit_tree_mismatch_fails(self):
        document = dependency_document()
        mutated = copy.deepcopy(document)
        mutated["dependencies"][0]["implementation"]["tree"] = (
            document["dependencies"][1]["implementation"]["tree"]
        )
        errors = MODULE.validate_document(ROOT, mutated)
        self.assertTrue(any("tree mismatch" in error for error in errors))

    def test_malformed_git_identity_fails(self):
        document = dependency_document()
        mutated = copy.deepcopy(document)
        mutated["repository"]["protectedMain"]["commit"] = "not-a-git-object"
        errors = MODULE.validate_document(ROOT, mutated)
        self.assertTrue(
            any(
                "repository.protectedMain.commit must be a 40-character" in error
                for error in errors
            )
        )

    def test_worker_d_synchronization_pair_is_checked(self):
        document = dependency_document()
        mutated = copy.deepcopy(document)
        mutated["repository"]["workerD"]["synchronizationTree"] = "0" * 40
        errors = MODULE.validate_document(ROOT, mutated)
        self.assertTrue(
            any("repository.workerD tree mismatch" in error for error in errors)
        )

    def test_duplicate_dependency_task_fails(self):
        document = dependency_document()
        mutated = copy.deepcopy(document)
        duplicate = copy.deepcopy(mutated["dependencies"][0])
        mutated["dependencies"].append(duplicate)
        errors = MODULE.validate_document(ROOT, mutated)
        self.assertTrue(any("duplicate dependency taskId" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
