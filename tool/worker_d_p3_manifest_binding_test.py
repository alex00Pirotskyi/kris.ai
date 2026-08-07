from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).with_name("worker_d_p3_manifest_binding.py")
SPEC = importlib.util.spec_from_file_location(
    "worker_d_p3_manifest_binding",
    MODULE_PATH,
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
ROOT = Path(__file__).resolve().parents[1]


def manifest_document() -> dict:
    return json.loads((ROOT / MODULE.MANIFEST_PATH).read_text(encoding="utf-8"))


class ManifestBindingTests(unittest.TestCase):
    def test_repository_bindings_pass(self):
        self.assertEqual([], MODULE.validate(ROOT))

    def test_recorded_hash_drift_fails(self):
        mutated = copy.deepcopy(manifest_document())
        mutated["artifacts"][0]["sha256"] = "0" * 64
        errors = MODULE.validate_manifest_document(ROOT, mutated)
        self.assertTrue(any("digest mismatch" in error for error in errors))

    def test_tested_candidate_tree_mismatch_fails(self):
        mutated = copy.deepcopy(manifest_document())
        mutated["testedSourceCandidate"]["tree"] = "0" * 40
        errors = MODULE.validate_manifest_document(ROOT, mutated)
        self.assertTrue(
            any("testedSourceCandidate.tree mismatch" in error for error in errors)
        )

    def test_stage2_packaging_candidate_is_exact_and_descends_from_tested_source(self):
        manifest = manifest_document()
        commit, tree = MODULE.PACKAGING_CANDIDATE
        self.assertEqual(tree, MODULE._git(ROOT, "rev-parse", f"{commit}^{{tree}}"))
        self.assertNotEqual(commit, manifest["testedSourceCandidate"]["commit"])
        self.assertEqual([], MODULE.validate_manifest_document(ROOT, manifest))

    def test_packaging_bytes_cannot_be_relabelled_as_stage1_bytes(self):
        manifest = manifest_document()
        tested = manifest["testedSourceCandidate"]
        with mock.patch.object(
            MODULE,
            "PACKAGING_CANDIDATE",
            (tested["commit"], tested["tree"]),
        ):
            errors = MODULE.validate_manifest_document(ROOT, manifest)
        self.assertTrue(any("digest mismatch" in error for error in errors))

    def test_packaging_candidate_tree_is_verified(self):
        manifest = manifest_document()
        commit, _ = MODULE.PACKAGING_CANDIDATE
        with mock.patch.object(
            MODULE,
            "PACKAGING_CANDIDATE",
            (commit, "0" * 40),
        ):
            errors = MODULE.validate_manifest_document(ROOT, manifest)
        self.assertTrue(
            any(
                "published evidencePackagingCandidate.tree mismatch" in error
                for error in errors
            )
        )

    def test_duplicate_binding_fails(self):
        mutated = copy.deepcopy(manifest_document())
        mutated["artifacts"].append(copy.deepcopy(mutated["artifacts"][0]))
        errors = MODULE.validate_manifest_document(ROOT, mutated)
        self.assertTrue(
            any("duplicate manifest artifact path" in error for error in errors)
        )

    def test_missing_binding_fails(self):
        mutated = copy.deepcopy(manifest_document())
        removed = mutated["artifacts"].pop()
        errors = MODULE.validate_manifest_document(ROOT, mutated)
        self.assertTrue(
            any(
                "manifest artifact bindings missing" in error
                and removed["path"] in error
                for error in errors
            )
        )

    def test_unexpected_binding_fails(self):
        mutated = copy.deepcopy(manifest_document())
        extra = copy.deepcopy(mutated["artifacts"][1])
        extra["path"] = "tool/worker_d_p3_unexpected.py"
        mutated["artifacts"].append(extra)
        errors = MODULE.validate_manifest_document(ROOT, mutated)
        self.assertTrue(
            any(
                "manifest artifact bindings unexpected" in error
                and extra["path"] in error
                for error in errors
            )
        )

    def test_unsafe_binding_path_fails(self):
        mutated = copy.deepcopy(manifest_document())
        mutated["artifacts"][0]["path"] = "../escape"
        errors = MODULE.validate_manifest_document(ROOT, mutated)
        self.assertTrue(any("unsafe path" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
