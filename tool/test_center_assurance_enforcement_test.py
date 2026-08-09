#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import json
import subprocess
import sys
import unittest
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "tool"))

from test_center_assurance_enforcement import (  # noqa: E402
    SUPPORT_REQUIREMENT_ID,
    HierarchyError,
    _repository_support_requirement,
    _resolve_evidence,
    _validate_independent_review_document,
    _validate_support_matrix_document,
    validate_assurance_execution_report,
    validate_documents,
)


def load(path: str) -> dict:
    return json.loads((PROJECT / path).read_text(encoding="utf-8"))


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args],
        cwd=PROJECT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.strip()


class AssuranceEnforcementTest(unittest.TestCase):
    def setUp(self) -> None:
        self.hierarchy_schema = load("schemas/test_center_assurance_hierarchy.v1.json")
        self.report_schema = load("schemas/test_center_assurance_execution_report.v1.json")
        self.canonical = load("schemas/test_center.v1.json")
        self.hierarchy = load("config/test_center_assurance_hierarchy.v1.json")
        self.registry = load("config/test_center_registry.v1.json")
        self.contract_schema = load("schemas/test_center_assurance_report_contract.v1.json")
        self.contract = load("config/test_center_assurance_report_contract.v1.json")
        self.proof_contract = load("release/evidence/TEST_CENTER/P8-001/contracts/assurance-proof-contract.v1.json")
        self.report = load("release/evidence/TEST_CENTER/P8-001/fixtures/assurance-execution-report.pass.json")

    def validate_documents(self, **overrides) -> dict:
        return validate_documents(overrides.get("hierarchy_schema", self.hierarchy_schema), overrides.get("report_schema", self.report_schema), overrides.get("canonical", self.canonical), overrides.get("hierarchy", self.hierarchy), overrides.get("registry", self.registry), overrides.get("contract_schema", self.contract_schema), overrides.get("contract", self.contract))

    def validate_report(self, report: dict, *, hierarchy: dict | None = None) -> dict:
        return validate_assurance_execution_report(report, report_schema=self.report_schema, canonical_schema=self.canonical, hierarchy=hierarchy or self.hierarchy, registry=self.registry, project=PROJECT)

    def test_valid_contract_and_report(self) -> None:
        self.assertEqual(self.validate_documents()["status"], "PASS")
        result = self.validate_report(self.report)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["evidenceResolution"], "REPOSITORY_RELATIVE_SHA256_TYPED_JSON_AND_GIT_BOUND_SUPPORT_EVIDENCE")
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
        predecessor["resultId"] = "result.p8-001.wrong-candidate-unit-linux"; predecessor["testId"] = "tc.test-center.semantic-regressions"; predecessor["moduleId"] = "tm.test-center"; predecessor["roadmapTaskIds"] = []; predecessor["commit"] = "3" * 40; predecessor["tree"] = "4" * 40
        for evidence in predecessor["evidenceReferences"]: evidence["commit"] = predecessor["commit"]; evidence["tree"] = predecessor["tree"]
        report["predecessorResults"] = [{"assuranceLevel":"unit","executionResult":predecessor,"evidenceBindings":copy.deepcopy(self.report["evidenceBindings"]),"predecessorResults":[]}]
        with self.assertRaisesRegex(HierarchyError, "another candidate"): self.validate_report(report, hierarchy=hierarchy)

    def test_report_contract_schema_path_drift_rejected(self) -> None:
        contract = copy.deepcopy(self.contract); contract["hierarchyRequiredFieldMappings"]["durationMillis"] = "executionResult.notAField"
        with self.assertRaisesRegex(HierarchyError, "absent from closed schema"): self.validate_documents(contract=contract)

    def test_report_schema_required_field_missing_from_contract_rejected(self) -> None:
        contract = copy.deepcopy(self.contract); index = contract["reportRequiredTopLevelFields"].index("evidenceBindings"); contract["reportRequiredTopLevelFields"][index] = "notARequiredField"
        with self.assertRaisesRegex(HierarchyError, "required fields and mapping contract drifted"): self.validate_documents(contract=contract)

    def test_independent_review_self_declaration_fails_closed(self) -> None:
        document = {
            "schemaVersion": "1.0.0",
            "kind": "INDEPENDENT_REVIEW",
            "reviewedCommit": "a" * 40,
            "reviewedTree": "b" * 40,
            "decision": "PASS",
            "reviewerGitHubIdentity": "self-declared-reviewer",
        }
        with self.assertRaisesRegex(HierarchyError, "repository-authoritative external review provenance"):
            _validate_independent_review_document(document)

    def test_support_requirement_comes_from_canonical_registry(self) -> None:
        result = self.report["executionResult"]
        platforms, capabilities = _repository_support_requirement(result, self.registry)
        self.assertEqual(platforms, ("linux", "macos", "windows"))
        self.assertEqual(capabilities, (result["testId"],))
        support_contract = next(item for item in self.proof_contract["evidenceContracts"] if item["category"] == "support_matrix")
        self.assertEqual(support_contract["requiredConstants"]["supportRequirementId"], SUPPORT_REQUIREMENT_ID)
        self.assertTrue({"supportRequirementId", "requiredPlatforms", "requiredCapabilities", "matrix"}.issubset(set(support_contract["requiredJsonFields"])))

    def test_support_matrix_requires_authoritative_scope_and_exact_platform_proofs(self) -> None:
        required_platforms = ("windows", "macos")
        required_capabilities = ("owner-mode", "process-supervision")
        platform_proofs = {
            (platform, capability): f"result.platform.{platform}.{capability}"
            for platform in required_platforms
            for capability in required_capabilities
        }
        document = {
            "schemaVersion": "1.0.0",
            "kind": "SUPPORT_MATRIX",
            "candidateCommit": "a" * 40,
            "candidateTree": "b" * 40,
            "status": "PASS",
            "supportRequirementId": SUPPORT_REQUIREMENT_ID,
            "requiredPlatforms": list(required_platforms),
            "requiredCapabilities": list(required_capabilities),
            "matrix": [
                {
                    "platform": platform,
                    "capability": capability,
                    "supportState": "SUPPORTED",
                    "proofResultId": platform_proofs[(platform, capability)],
                }
                for platform in required_platforms
                for capability in required_capabilities
            ],
        }
        _validate_support_matrix_document(
            document,
            required_platforms=required_platforms,
            required_capabilities=required_capabilities,
            platform_proofs=platform_proofs,
        )

        empty = copy.deepcopy(document); empty["matrix"] = []
        with self.assertRaisesRegex(HierarchyError, "non-empty matrix"):
            _validate_support_matrix_document(empty, required_platforms=required_platforms, required_capabilities=required_capabilities, platform_proofs=platform_proofs)

        duplicate = copy.deepcopy(document); duplicate["matrix"].append(copy.deepcopy(duplicate["matrix"][0]))
        with self.assertRaisesRegex(HierarchyError, "duplicates platform/capability"):
            _validate_support_matrix_document(duplicate, required_platforms=required_platforms, required_capabilities=required_capabilities, platform_proofs=platform_proofs)

        blocked = copy.deepcopy(document); blocked["matrix"][0]["supportState"] = "BLOCKED"
        with self.assertRaisesRegex(HierarchyError, "non-supported required coverage"):
            _validate_support_matrix_document(blocked, required_platforms=required_platforms, required_capabilities=required_capabilities, platform_proofs=platform_proofs)

        narrow = copy.deepcopy(document); narrow["requiredPlatforms"] = ["windows"]; narrow["matrix"] = [entry for entry in narrow["matrix"] if entry["platform"] == "windows"]
        with self.assertRaisesRegex(HierarchyError, "requiredPlatforms do not exactly match repository-authoritative requirement"):
            _validate_support_matrix_document(narrow, required_platforms=required_platforms, required_capabilities=required_capabilities, platform_proofs=platform_proofs)

        omitted_capability = copy.deepcopy(document); omitted_capability["requiredCapabilities"] = ["owner-mode"]; omitted_capability["matrix"] = [entry for entry in omitted_capability["matrix"] if entry["capability"] == "owner-mode"]
        with self.assertRaisesRegex(HierarchyError, "requiredCapabilities do not exactly match repository-authoritative requirement"):
            _validate_support_matrix_document(omitted_capability, required_platforms=required_platforms, required_capabilities=required_capabilities, platform_proofs=platform_proofs)

        extra = copy.deepcopy(document); extra["requiredPlatforms"].append("linux")
        extra["matrix"].extend({"platform":"linux","capability":capability,"supportState":"SUPPORTED","proofResultId":f"result.platform.linux.{capability}"} for capability in required_capabilities)
        with self.assertRaisesRegex(HierarchyError, "requiredPlatforms do not exactly match repository-authoritative requirement"):
            _validate_support_matrix_document(extra, required_platforms=required_platforms, required_capabilities=required_capabilities, platform_proofs=platform_proofs)

        missing_proof = copy.deepcopy(document); missing_proof["matrix"][0]["proofResultId"] = "result.platform.unrelated"
        with self.assertRaisesRegex(HierarchyError, "lacks corresponding exact-candidate platform proof"):
            _validate_support_matrix_document(missing_proof, required_platforms=required_platforms, required_capabilities=required_capabilities, platform_proofs=platform_proofs)

        wrong_requirement = copy.deepcopy(document); wrong_requirement["supportRequirementId"] = "self-declared"
        with self.assertRaisesRegex(HierarchyError, "supportRequirementId does not match repository-authoritative requirement"):
            _validate_support_matrix_document(wrong_requirement, required_platforms=required_platforms, required_capabilities=required_capabilities, platform_proofs=platform_proofs)

    def test_support_bearing_evidence_requires_exact_candidate_git_blob(self) -> None:
        head = git("rev-parse", "HEAD")
        tree = git("rev-parse", "HEAD^{tree}")
        uri = "release/evidence/TEST_CENTER/P8-001/fixtures/unit-pass-candidate-identity.json"
        payload = (PROJECT / uri).read_bytes()
        evidence = {
            "evidenceId": "evidence.test.git-bound",
            "uri": uri,
            "sha256": hashlib.sha256(payload).hexdigest(),
            "immutable": True,
            "commit": head,
            "tree": tree,
        }
        resolved, exact = _resolve_evidence(
            PROJECT,
            evidence,
            candidate_commit=head,
            candidate_tree=tree,
            require_git_binding=True,
        )
        self.assertEqual(resolved, (PROJECT / uri).resolve())
        self.assertEqual(exact, payload)

        fake = copy.deepcopy(evidence)
        fake["commit"] = "1" * 40
        fake["tree"] = "2" * 40
        with self.assertRaisesRegex(HierarchyError, "Git evidence binding failed"):
            _resolve_evidence(
                PROJECT,
                fake,
                candidate_commit=fake["commit"],
                candidate_tree=fake["tree"],
                require_git_binding=True,
            )


if __name__ == "__main__": unittest.main()
