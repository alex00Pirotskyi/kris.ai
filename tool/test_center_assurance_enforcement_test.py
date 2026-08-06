#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "tool"))

from test_center_assurance_enforcement import HierarchyError, validate_assurance_execution_report, validate_documents  # noqa: E402


def load(path: str) -> dict:
    return json.loads((PROJECT / path).read_text(encoding="utf-8"))


class AssuranceEnforcementTest(unittest.TestCase):
    def setUp(self) -> None:
        self.hierarchy_schema = load("schemas/test_center_assurance_hierarchy.v1.json")
        self.report_schema = load("schemas/test_center_assurance_execution_report.v1.json")
        self.canonical = load("schemas/test_center.v1.json")
        self.hierarchy = load("config/test_center_assurance_hierarchy.v1.json")
        self.registry = load("config/test_center_registry.v1.json")
        self.contract_schema = load("schemas/test_center_assurance_report_contract.v1.json")
        self.contract = load("config/test_center_assurance_report_contract.v1.json")
        self.report = load("release/evidence/TEST_CENTER/P8-001/fixtures/assurance-execution-report.pass.json")

    def validate_documents(self, **overrides) -> dict:
        return validate_documents(overrides.get("hierarchy_schema", self.hierarchy_schema), overrides.get("report_schema", self.report_schema), overrides.get("canonical", self.canonical), overrides.get("hierarchy", self.hierarchy), overrides.get("registry", self.registry), overrides.get("contract_schema", self.contract_schema), overrides.get("contract", self.contract))

    def validate_report(self, report: dict, *, hierarchy: dict | None = None) -> dict:
        return validate_assurance_execution_report(report, report_schema=self.report_schema, canonical_schema=self.canonical, hierarchy=hierarchy or self.hierarchy, registry=self.registry, project=PROJECT)

    def test_valid_contract_and_report(self) -> None:
        self.assertEqual(self.validate_documents()["status"], "PASS")
        result = self.validate_report(self.report)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["evidenceResolution"], "REPOSITORY_RELATIVE_SHA256_AND_TYPED_JSON")
        self.assertEqual(result["predecessorLevelsVerified"], [])
        self.assertEqual(result["predecessorProofMode"], "RECURSIVE_EXACT_CANDIDATE_LINEAGE")

    def test_empty_toolchain_components_fail_min_properties(self) -> None:
        report = copy.deepcopy(self.report); report["executionResult"]["toolchain"]["components"] = {}
        with self.assertRaisesRegex(HierarchyError, "too few properties"): self.validate_report(report)

    def test_naive_timestamp_rejected(self) -> None:
        report = copy.deepcopy(self.report); report["executionResult"]["startedAt"] = "2026-08-06T10:30:00"
        with self.assertRaisesRegex(HierarchyError, "RFC3339"): self.validate_report(report)

    def test_space_separated_timestamp_rejected(self) -> None:
        report = copy.deepcopy(self.report); report["executionResult"]["endedAt"] = "2026-08-06 10:30:01Z"
        with self.assertRaisesRegex(HierarchyError, "RFC3339"): self.validate_report(report)

    def test_generated_at_must_follow_execution(self) -> None:
        report = copy.deepcopy(self.report); report["generatedAt"] = "2026-08-06T10:29:59Z"
        with self.assertRaisesRegex(HierarchyError, "generatedAt precedes"): self.validate_report(report)

    def test_missing_evidence_target_rejected(self) -> None:
        report = copy.deepcopy(self.report); report["executionResult"]["evidenceReferences"][0]["uri"] = "release/evidence/TEST_CENTER/P8-001/fixtures/does-not-exist.json"
        with self.assertRaisesRegex(HierarchyError, "does not resolve"): self.validate_report(report)

    def test_evidence_digest_mismatch_rejected(self) -> None:
        report = copy.deepcopy(self.report); report["executionResult"]["evidenceReferences"][0]["sha256"] = "f" * 64
        with self.assertRaisesRegex(HierarchyError, "digest mismatch"): self.validate_report(report)

    def test_missing_required_evidence_category_rejected(self) -> None:
        report = copy.deepcopy(self.report); report["evidenceBindings"] = report["evidenceBindings"][:-1]
        with self.assertRaisesRegex(HierarchyError, "evidence categories"): self.validate_report(report)

    def test_duplicate_evidence_category_rejected(self) -> None:
        report = copy.deepcopy(self.report); report["evidenceBindings"][2]["category"] = report["evidenceBindings"][0]["category"]
        with self.assertRaisesRegex(HierarchyError, "duplicate evidence categories"): self.validate_report(report)

    def test_one_evidence_object_cannot_fill_two_categories(self) -> None:
        report = copy.deepcopy(self.report); report["evidenceBindings"][2]["evidenceId"] = report["evidenceBindings"][0]["evidenceId"]
        with self.assertRaisesRegex(HierarchyError, "reuses one evidence object"): self.validate_report(report)

    def _component_report_and_hierarchy(self) -> tuple[dict, dict]:
        report = copy.deepcopy(self.report); hierarchy = copy.deepcopy(self.hierarchy)
        test_id = report["executionResult"]["testId"]
        for binding in hierarchy["testBindings"]:
            if binding["testId"] == test_id: binding["levelId"] = "component"
        report["assuranceLevel"] = "component"; report["hierarchyBinding"]["levelId"] = "component"; report["requestedSupportImpact"] = "BEHAVIOR_SUPPORTED"
        return report, hierarchy

    def test_missing_predecessor_result_rejected(self) -> None:
        report, hierarchy = self._component_report_and_hierarchy()
        with self.assertRaisesRegex(HierarchyError, "predecessor results"): self.validate_report(report, hierarchy=hierarchy)

    def test_wrong_candidate_predecessor_rejected(self) -> None:
        report, hierarchy = self._component_report_and_hierarchy(); predecessor = copy.deepcopy(report["executionResult"])
        predecessor["testId"] = "tc.test-center.semantic-regressions"; predecessor["moduleId"] = "tm.test-center"; predecessor["roadmapTaskIds"] = []; predecessor["commit"] = "3" * 40; predecessor["tree"] = "4" * 40
        for evidence in predecessor["evidenceReferences"]: evidence["commit"] = predecessor["commit"]; evidence["tree"] = predecessor["tree"]
        report["predecessorResults"] = [{"assuranceLevel":"unit","executionResult":predecessor,"evidenceBindings":copy.deepcopy(self.report["evidenceBindings"]),"predecessorResults":[]}]
        with self.assertRaisesRegex(HierarchyError, "another candidate"): self.validate_report(report, hierarchy=hierarchy)

    def test_report_contract_schema_path_drift_rejected(self) -> None:
        contract = copy.deepcopy(self.contract); contract["hierarchyRequiredFieldMappings"]["durationMillis"] = "executionResult.notAField"
        with self.assertRaisesRegex(HierarchyError, "absent from closed schema"): self.validate_documents(contract=contract)

    def test_report_schema_required_field_missing_from_contract_rejected(self) -> None:
        contract = copy.deepcopy(self.contract); contract["reportRequiredTopLevelFields"].remove("evidenceBindings")
        with self.assertRaisesRegex(HierarchyError, "required fields and mapping contract drifted"): self.validate_documents(contract=contract)


if __name__ == "__main__": unittest.main()
