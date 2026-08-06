#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("hierarchy", ROOT / "tool/test_center_assurance_hierarchy.py")
assert SPEC and SPEC.loader
hierarchy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(hierarchy)


class FormalHierarchyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.schema = json.loads((ROOT / hierarchy.SCHEMA).read_text(encoding="utf-8"))
        cls.document = json.loads((ROOT / hierarchy.HIERARCHY).read_text(encoding="utf-8"))
        cls.registry = json.loads((ROOT / hierarchy.REGISTRY).read_text(encoding="utf-8"))

    def validate(self, mutate=None):
        schema, document, registry = copy.deepcopy(self.schema), copy.deepcopy(self.document), copy.deepcopy(self.registry)
        if mutate:
            mutate(schema, document, registry)
        return hierarchy.validate_documents(schema, document, registry)

    def rejects(self, mutate):
        with self.assertRaises(hierarchy.HierarchyError):
            self.validate(mutate)

    def test_canonical_document_passes(self):
        report = self.validate()
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["levelCount"], 8)
        self.assertEqual(report["bindingCount"], len(self.registry["testCases"]))

    def test_check_mode_is_non_mutating(self):
        before = {p: p.read_bytes() for p in (ROOT / hierarchy.SCHEMA, ROOT / hierarchy.HIERARCHY, ROOT / hierarchy.REGISTRY)}
        result = subprocess.run([sys.executable, str(ROOT / "tool/test_center_assurance_hierarchy.py"), "check", "--project", str(ROOT)], capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {p: p.read_bytes() for p in before})

    def test_rejects_wrong_schema_draft(self):
        self.rejects(lambda s, d, r: s.__setitem__("$schema", "draft-07"))

    def test_rejects_open_schema_root(self):
        self.rejects(lambda s, d, r: s.__setitem__("additionalProperties", True))

    def test_rejects_unknown_level(self):
        self.rejects(lambda s, d, r: d["levels"][0].__setitem__("levelId", "mystery"))

    def test_rejects_missing_level(self):
        self.rejects(lambda s, d, r: d["levels"].pop())

    def test_rejects_rank_drift(self):
        self.rejects(lambda s, d, r: d["levels"][2].__setitem__("rank", 25))

    def test_rejects_invalid_predecessor(self):
        self.rejects(lambda s, d, r: d["levels"][2].__setitem__("requiredPredecessorLevels", ["release"]))

    def test_release_requires_three_evidence_branches(self):
        self.rejects(lambda s, d, r: d["levels"][-1].__setitem__("requiredPredecessorLevels", ["platform"]))

    def test_source_only_cannot_promote_support(self):
        self.rejects(lambda s, d, r: d["levels"][0].__setitem__("supportClaimCeiling", "SOURCE_FOUNDATION"))

    def test_rejects_missing_report_field(self):
        self.rejects(lambda s, d, r: d["reportContract"]["requiredFields"].remove("assuranceLevel"))

    def test_rejects_permissive_unknown_level_policy(self):
        self.rejects(lambda s, d, r: d["reportContract"].__setitem__("unknownLevelPolicy", "WARN"))

    def test_rejects_cross_level_promotion(self):
        self.rejects(lambda s, d, r: d["reportContract"].__setitem__("crossLevelPromotionPolicy", "ALLOWED"))

    def test_rejects_missing_binding(self):
        self.rejects(lambda s, d, r: d["testBindings"].pop())

    def test_rejects_duplicate_binding(self):
        self.rejects(lambda s, d, r: d["testBindings"].append(copy.deepcopy(d["testBindings"][0])))

    def test_rejects_registry_profile_drift(self):
        self.rejects(lambda s, d, r: r["projectTestProfiles"].pop())

    def test_p8_ids_remain_owned_and_bound(self):
        def mutate(s, d, r):
            next(case for case in r["testCases"] if case["testId"] == "tc.p8.formal-test-hierarchy")["moduleId"] = "tm.test-center"
        self.rejects(mutate)


if __name__ == "__main__":
    unittest.main(verbosity=2)
