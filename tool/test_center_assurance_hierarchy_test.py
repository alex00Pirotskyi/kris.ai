#!/usr/bin/env python3
from __future__ import annotations

import copy
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
sys.path.insert(0, str(HERE))
import test_center_assurance_hierarchy as H  # noqa: E402

FIXTURE = Path("release/evidence/TEST_CENTER/P8-001/fixtures/assurance-execution-report.pass.json")
COMPONENT_FIXTURE = "release/evidence/TEST_CENTER/P8-001/fixtures/component-pass-fixture.json"
COMPONENT_FIXTURE_SHA256 = "779714fd586b2896c39056dd541a5be80512b240bd147a72b67d60f59702164a"
COMPONENT_RESULT_FIXTURE = "release/evidence/TEST_CENTER/P8-001/fixtures/component-pass-machine-result.json"
COMPONENT_RESULT_FIXTURE_SHA256 = "68a1720c473c4d3188181dde18e9fe8df572d8236e0ab105c2edfcb9da19aee3"


def at(value, path):
    for key in path: value = value[key]
    return value

def put(path, replacement):
    def mutate(value): at(value, path[:-1])[path[-1]] = replacement
    return mutate

def pop(path):
    def mutate(value): at(value, path[:-1]).pop(path[-1])
    return mutate

def duplicate(path):
    def mutate(value):
        items = at(value, path); items.append(copy.deepcopy(items[0]))
    return mutate

def pending(test_id, **updates):
    def mutate(value): next(item for item in value["pendingMigrationBindings"] if item["testId"] == test_id).update(updates)
    return mutate

def both(*mutations):
    def mutate(value):
        for operation in mutations: operation(value)
    return mutate

def add_unreviewed_pending_binding(value):
    binding = copy.deepcopy(value["pendingMigrationBindings"][0]); binding["testId"] = "tc.p1a.review.outcome"; value["pendingMigrationBindings"].append(binding)

def promote_source_only_report(value):
    value["executionResult"].update(testId="tc.p8.formal-test-hierarchy", assuranceClass="source_contract")
    value["hierarchyBinding"].update(testId="tc.p8.formal-test-hierarchy", levelId="architecture_lint", sourceOnly=True)
    value.update(assuranceLevel="architecture_lint", requestedSupportImpact="SOURCE_FOUNDATION")

def use_unknown_test(value): value["executionResult"].update(testId="tc.unknown.actual-record"); value["hierarchyBinding"].update(testId="tc.unknown.actual-record")
def append_wrapper_evidence(value): value["evidenceReferences"].append("evidence.p8-001.unknown")
def append_distinct_canonical_evidence(value):
    evidence = copy.deepcopy(value["executionResult"]["evidenceReferences"][0]); evidence["evidenceId"] = "evidence.p8-001.second"; evidence["sha256"] = "b" * 64; value["executionResult"]["evidenceReferences"].append(evidence)
def duplicate_canonical_evidence_id(value):
    evidence = copy.deepcopy(value["executionResult"]["evidenceReferences"][0]); evidence["sha256"] = "b" * 64; value["executionResult"]["evidenceReferences"].append(evidence)

DOCUMENT_REGRESSIONS = [
    ("unknown level", put(("levels",1,"levelId"),"smoke")), ("rank drift", put(("levels",2,"rank"),31)), ("invalid predecessor", put(("levels",2,"requiredPredecessorLevels"),["release"])), ("missing binding", lambda value:value["testBindings"].pop()), ("duplicate binding", duplicate(("testBindings",))), ("architecture promotion", put(("levels",0,"supportClaimCeiling"),"SOURCE_FOUNDATION")), ("release predecessors", put(("levels",7,"requiredPredecessorLevels"),["platform"])), ("missing report schema", pop(("reportContract","executionReportSchema"))), ("missing migration", lambda value:value["pendingMigrationBindings"].pop()), ("duplicate migration", duplicate(("pendingMigrationBindings",))), ("active overlap", put(("pendingMigrationBindings",0,"testId"),"tc.test-center.contracts")), ("Worker A identity drift", put(("pendingMigrationSource","commit"),"0"*40)), ("Worker A level drift", pending("tc.p2.behavioral-closure",levelId="integration")), ("p1a exit gate platform", pending("tc.p1a.exit-gate",levelId="platform")), ("unreviewed Worker A ID", add_unreviewed_pending_binding),
]
REPORT_REGRESSIONS = [
    ("missing assuranceLevel",pop(("assuranceLevel",))), ("unknown assuranceLevel",put(("assuranceLevel",),"smoke")), ("level binding mismatch",both(put(("assuranceLevel",),"component"),put(("hierarchyBinding","levelId"),"component"))), ("wrapper mismatch",put(("hierarchyBinding","testId"),"tc.p8.formal-test-hierarchy")), ("class mismatch",put(("executionResult","assuranceClass"),"platform")), ("cross candidate",put(("candidateCommit",),"3"*40)), ("above ceiling",put(("requestedSupportImpact",),"BEHAVIOR_SUPPORTED")), ("unexecuted",put(("executionResult","resultState"),"SKIPPED")), ("non pass",put(("executionResult","resultState"),"FAIL")), ("missing canonical field",pop(("executionResult","runner"))), ("canonical extra field",put(("executionResult","assuranceLevel"),"unit")), ("wrapper extra field",put(("supportPromotion",),True)), ("source promotion",promote_source_only_report), ("unknown test",use_unknown_test), ("PASS non-zero exit",put(("executionResult","exitCode"),7)), ("duration mismatch",put(("executionResult","durationMillis"),2000)), ("endedAt precedes startedAt",put(("executionResult","endedAt"),"2026-08-06T10:29:59Z")), ("cross-candidate immutable evidence",put(("executionResult","evidenceReferences",0,"commit"),"3"*40)), ("dirty cleanup promotion",put(("executionResult","cleanupState"),"DIRTY")), ("unresolved cleanup promotion",put(("executionResult","cleanupState"),"UNRESOLVED")), ("PASS failure contradiction",put(("executionResult","failureClassification"),"ASSERTION")), ("PASS certification contradiction",put(("executionResult","certificationImpact"),"BLOCKS_SCOPE")), ("wrapper evidence mismatch",put(("evidenceReferences",0),"evidence.p8-001.mismatch")), ("wrapper evidence extra",append_wrapper_evidence), ("wrapper evidence missing",put(("evidenceReferences",),[])), ("canonical evidence missing wrapper binding",append_distinct_canonical_evidence), ("duplicate canonical evidence ID",duplicate_canonical_evidence_id), ("duplicate wrapper evidence ID",duplicate(("evidenceReferences",))), ("support-bearing report without canonical evidence",put(("executionResult","evidenceReferences"),[])),
]


class AssuranceHierarchyTest(unittest.TestCase):
    def setUp(self):
        self.hierarchy_schema=H.load(PROJECT/H.HIERARCHY_SCHEMA); self.report_schema=H.load(PROJECT/H.REPORT_SCHEMA); self.canonical_schema=H.load(PROJECT/H.CANONICAL_SCHEMA); self.hierarchy=H.load(PROJECT/H.HIERARCHY); self.registry=H.load(PROJECT/H.REGISTRY); self.proof_contract=H.load(PROJECT/H.PROOF_CONTRACT); self.report_fixture=H.load(PROJECT/FIXTURE)

    def validate_documents(self,value): return H.validate_documents(self.hierarchy_schema,self.report_schema,value,self.registry)
    def validate_report(self,value,*,hierarchy=None,proof_contract=None): return H.validate_assurance_execution_report(value,report_schema=self.report_schema,canonical_schema=self.canonical_schema,hierarchy=hierarchy or self.hierarchy,registry=self.registry,project=PROJECT,proof_contract=proof_contract or self.proof_contract)

    def component_report_with_unit_predecessor(self):
        report=copy.deepcopy(self.report_fixture); hierarchy=copy.deepcopy(self.hierarchy)
        current_test_id=report["executionResult"]["testId"]
        for binding in hierarchy["testBindings"]:
            if binding["testId"]==current_test_id: binding["levelId"]="component"
            if binding["testId"]=="tc.p8.formal-test-hierarchy": binding["levelId"]="unit"
        report["assuranceLevel"]="component"; report["hierarchyBinding"]["levelId"]="component"; report["requestedSupportImpact"]="BEHAVIOR_SUPPORTED"; report["executionResult"]["resultId"]="result.p8-001.component-linux"
        result_id="evidence.p8-001.component-pass.result"; result_evidence=report["executionResult"]["evidenceReferences"][1]; result_evidence.update(evidenceId=result_id,uri=COMPONENT_RESULT_FIXTURE,sha256=COMPONENT_RESULT_FIXTURE_SHA256); report["evidenceReferences"][1]=result_id; report["evidenceBindings"][1]["evidenceId"]=result_id
        component_id="evidence.p8-001.component-pass.fixture"; component=report["executionResult"]["evidenceReferences"][2]; component.update(evidenceId=component_id,uri=COMPONENT_FIXTURE,sha256=COMPONENT_FIXTURE_SHA256); report["evidenceReferences"][2]=component_id; report["evidenceBindings"][2].update(category="component_fixture",evidenceId=component_id)
        predecessor=copy.deepcopy(self.report_fixture["executionResult"]); predecessor["testId"]="tc.p8.formal-test-hierarchy"
        report["predecessorResults"]=[{"assuranceLevel":"unit","executionResult":predecessor,"evidenceBindings":copy.deepcopy(self.report_fixture["evidenceBindings"]),"predecessorResults":[]}]
        return report,hierarchy

    def _synthetic_result(self,test_id,assurance_class,result_id):
        result=copy.deepcopy(self.report_fixture["executionResult"]); result["testId"]=test_id; result["assuranceClass"]=assurance_class; result["resultId"]=result_id; return result

    def release_proof_with_deep_missing_unit(self):
        report=copy.deepcopy(self.report_fixture); hierarchy=copy.deepcopy(self.hierarchy); proof=copy.deepcopy(self.proof_contract)
        current_id=report["executionResult"]["testId"]
        for binding in hierarchy["testBindings"]:
            if binding["testId"]==current_id: binding["levelId"]="release"
        report["assuranceLevel"]="release"; report["hierarchyBinding"]["levelId"]="release"; report["executionResult"]["assuranceClass"]="release"; report["requestedSupportImpact"]="RELEASE_SUPPORTED"
        ids={"platform":"tc.p8.proof-platform","adversarial":"tc.p8.proof-adversarial","benchmark":"tc.p8.proof-benchmark","integration":"tc.p8.proof-integration","component":"tc.p8.proof-component"}
        for level,test_id in ids.items():
            hierarchy["testBindings"].append({"testId":test_id,"levelId":level,"rationale":"deterministic transitive proof regression"}); proof["lineageBindings"].append({"testId":test_id,"lineageId":"p8.formal-test-hierarchy"})
        component={"assuranceLevel":"component","executionResult":self._synthetic_result(ids["component"],"behavioral","result.p8.proof-component"),"evidenceBindings":copy.deepcopy(self.report_fixture["evidenceBindings"]),"predecessorResults":[]}
        integration={"assuranceLevel":"integration","executionResult":self._synthetic_result(ids["integration"],"behavioral","result.p8.proof-integration"),"evidenceBindings":copy.deepcopy(self.report_fixture["evidenceBindings"]),"predecessorResults":[component]}
        platform={"assuranceLevel":"platform","executionResult":self._synthetic_result(ids["platform"],"platform","result.p8.proof-platform"),"evidenceBindings":copy.deepcopy(self.report_fixture["evidenceBindings"]),"predecessorResults":[integration]}
        adversarial={"assuranceLevel":"adversarial","executionResult":self._synthetic_result(ids["adversarial"],"behavioral","result.p8.proof-adversarial"),"evidenceBindings":copy.deepcopy(self.report_fixture["evidenceBindings"]),"predecessorResults":[]}
        benchmark={"assuranceLevel":"benchmark","executionResult":self._synthetic_result(ids["benchmark"],"behavioral","result.p8.proof-benchmark"),"evidenceBindings":copy.deepcopy(self.report_fixture["evidenceBindings"]),"predecessorResults":[]}
        report["predecessorResults"]=[platform,adversarial,benchmark]
        return report,hierarchy,proof

    def test_deterministic_contract_checks(self):
        self.assertEqual(H.validate_project(PROJECT)["pendingMigrationBindingCount"],11); self.assertEqual(self.validate_report(self.report_fixture)["assuranceLevel"],"unit")
        for name,mutation in DOCUMENT_REGRESSIONS:
            with self.subTest(document=name),self.assertRaises(H.HierarchyError): value=copy.deepcopy(self.hierarchy); mutation(value); self.validate_documents(value)
        for name,mutation in REPORT_REGRESSIONS:
            with self.subTest(report=name),self.assertRaises(H.HierarchyError): value=copy.deepcopy(self.report_fixture); mutation(value); self.validate_report(value)
        with tempfile.TemporaryDirectory() as directory,self.assertRaises(H.HierarchyError): H.write_report(Path(directory),Path("../outside.json"),H.validate_project(PROJECT))

    def test_canonical_registry_runs_enforcement_layer(self):
        mapping=next(item for item in self.registry["affectedTestMappings"] if item["mappingId"]=="affected.p8-formal-test-hierarchy"); required_paths={"config/test_center_assurance_report_contract.v1.json","schemas/test_center_assurance_report_contract.v1.json","tool/test_center_assurance_enforcement.py","tool/test_center_assurance_enforcement_test.py"}; self.assertTrue(required_paths.issubset(set(mapping["pathPatterns"])))
        profiles={item["stableCheckId"]:item for item in self.registry["projectTestProfiles"]}; formal=profiles["tc.p8.formal-test-hierarchy"]; regressions=profiles["tc.p8.formal-test-hierarchy-regressions"]
        self.assertTrue({"config/test_center_assurance_report_contract.v1.json","schemas/test_center_assurance_report_contract.v1.json","tool/test_center_assurance_enforcement.py"}.issubset(set(formal["inputPaths"]))); self.assertEqual(regressions["argv"],["python","-m","unittest","-v","tool/test_center_assurance_hierarchy_test.py","tool/test_center_assurance_enforcement_test.py"]); self.assertTrue(required_paths.issubset(set(regressions["affectedPaths"])))

    def test_component_synthetic_support_evidence_fails_closed_without_git_candidate(self):
        report,hierarchy=self.component_report_with_unit_predecessor()
        with self.assertRaisesRegex(H.HierarchyError,"Git evidence binding failed"): self.validate_report(report,hierarchy=hierarchy)

    def test_component_rejects_unrelated_same_candidate_unit_predecessor(self):
        report,hierarchy=self.component_report_with_unit_predecessor(); predecessor=report["predecessorResults"][0]["executionResult"]; predecessor["testId"]="tc.test-center.semantic-regressions"; predecessor["moduleId"]="tm.test-center"; predecessor["roadmapTaskIds"]=[]
        with self.assertRaisesRegex(H.HierarchyError,"unrelated assurance lineage"): self.validate_report(report,hierarchy=hierarchy)

    def test_current_evidence_category_swap_is_rejected(self):
        report=copy.deepcopy(self.report_fixture); first=report["evidenceBindings"][0]["evidenceId"]; report["evidenceBindings"][0]["evidenceId"]=report["evidenceBindings"][1]["evidenceId"]; report["evidenceBindings"][1]["evidenceId"]=first
        with self.assertRaisesRegex(H.HierarchyError,"evidence for exact_candidate_identity"): self.validate_report(report)

    def test_predecessor_evidence_category_swap_is_rejected(self):
        report,hierarchy=self.component_report_with_unit_predecessor(); bindings=report["predecessorResults"][0]["evidenceBindings"]; first=bindings[0]["evidenceId"]; bindings[0]["evidenceId"]=bindings[1]["evidenceId"]; bindings[1]["evidenceId"]=first
        with self.assertRaisesRegex(H.HierarchyError,"evidence for exact_candidate_identity"): self.validate_report(report,hierarchy=hierarchy)

    def test_predecessor_missing_required_evidence_category_is_rejected(self):
        report,hierarchy=self.component_report_with_unit_predecessor(); report["predecessorResults"][0]["evidenceBindings"].pop()
        with self.assertRaisesRegex(H.HierarchyError,"predecessor unit evidence categories"): self.validate_report(report,hierarchy=hierarchy)

    def test_predecessor_mistyped_required_evidence_category_is_rejected(self):
        report,hierarchy=self.component_report_with_unit_predecessor(); report["predecessorResults"][0]["evidenceBindings"][2]["category"]="component_fixture"
        with self.assertRaisesRegex(H.HierarchyError,"predecessor unit evidence categories"): self.validate_report(report,hierarchy=hierarchy)

    def test_predecessor_cannot_reuse_one_evidence_object_across_categories(self):
        report,hierarchy=self.component_report_with_unit_predecessor(); bindings=report["predecessorResults"][0]["evidenceBindings"]; bindings[1]["evidenceId"]=bindings[0]["evidenceId"]
        with self.assertRaisesRegex(H.HierarchyError,"reuses one evidence object"): self.validate_report(report,hierarchy=hierarchy)

    def test_release_chain_rejects_platform_integration_component_missing_unit(self):
        report,hierarchy,proof=self.release_proof_with_deep_missing_unit()
        with self.assertRaisesRegex(H.HierarchyError,"missing=.*unit"): self.validate_report(report,hierarchy=hierarchy,proof_contract=proof)

    def test_release_direct_predecessors_each_require_integration_chain(self):
        for index,level in enumerate(("platform","adversarial","benchmark")):
            report,hierarchy,proof=self.release_proof_with_deep_missing_unit(); target=next(item for item in report["predecessorResults"] if item["assuranceLevel"]==level); target["predecessorResults"]=[]; report["predecessorResults"].remove(target); report["predecessorResults"].insert(0,target)
            with self.subTest(level=level),self.assertRaisesRegex(H.HierarchyError,"missing=.*integration"): self.validate_report(report,hierarchy=hierarchy,proof_contract=proof)

    def test_recursive_proof_rejects_reused_result_receipt(self):
        report,hierarchy,proof=self.release_proof_with_deep_missing_unit(); platform=report["predecessorResults"][0]; integration=platform["predecessorResults"][0]; integration["executionResult"]["resultId"]=platform["executionResult"]["resultId"]
        with self.assertRaisesRegex(H.HierarchyError,"receipt/resultId is reused"): self.validate_report(report,hierarchy=hierarchy,proof_contract=proof)

    def test_recursive_proof_rejects_wrong_nested_level(self):
        report,hierarchy,proof=self.release_proof_with_deep_missing_unit(); platform=report["predecessorResults"][0]; platform["predecessorResults"][0]["assuranceLevel"]="component"
        with self.assertRaisesRegex(H.HierarchyError,"missing=.*integration"): self.validate_report(report,hierarchy=hierarchy,proof_contract=proof)


if __name__=="__main__": unittest.main(verbosity=2)