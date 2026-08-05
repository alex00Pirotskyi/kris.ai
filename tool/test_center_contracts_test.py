#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
sys.path.insert(0, str(HERE))

import test_center_contracts as tc  # noqa: E402

ZERO = "0" * 64
ONE = "1" * 40
TWO = "2" * 40


def evidence(commit: str = ONE, tree: str = TWO) -> dict:
    return {
        "evidenceId": "evidence.test-center.sample",
        "kind": "ORIGINAL",
        "uri": "release/evidence/generated/worker-b/sample.json",
        "sha256": "a" * 64,
        "immutable": True,
        "commit": commit,
        "tree": tree,
        "createdAt": "2026-08-05T10:00:00Z",
        "mediaType": "application/json",
        "sourceEvidenceIds": [],
    }


def result(
    *,
    state: str = "PASS",
    cleanup: str = "CLEAN",
    commit: str = ONE,
    tree: str = TWO,
    platform: str = "linux",
) -> dict:
    return {
        "resultId": f"result.test-center.{platform}",
        "testId": "tc.test-center.contracts",
        "moduleId": "tm.test-center",
        "roadmapTaskIds": [],
        "commit": commit,
        "tree": tree,
        "branch": "agent/b/test-center-contracts-and-review",
        "workingTreeIdentity": {
            "clean": True,
            "statusSha256": ZERO,
            "diffSha256": ZERO,
            "untrackedSha256": ZERO,
        },
        "platform": platform,
        "runner": {
            "provider": "fixture",
            "runnerId": f"fixture-{platform}",
            "image": "fixture",
            "architecture": "x86_64",
        },
        "toolchain": {"digest": ZERO, "components": {"python": "3.12.10"}},
        "environment": {"digest": ZERO, "allowlisted": {"CI": "true"}},
        "startedAt": "2026-08-05T10:00:00Z",
        "endedAt": "2026-08-05T10:00:01Z",
        "durationMillis": 1000,
        "resultState": state,
        "exitCode": 0 if state == "PASS" else 1,
        "assuranceClass": "source_contract",
        "evidenceReferences": [evidence(commit, tree)],
        "cleanupState": cleanup,
        "failureClassification": "NONE" if state == "PASS" else "ASSERTION",
        "certificationImpact": "NONE" if state == "PASS" else "BLOCKS_SCOPE",
    }


def certification() -> dict:
    observed = [result(platform=p) for p in ("linux", "macos", "windows")]
    review_artifact = evidence()
    review_artifact["evidenceId"] = "evidence.review.worker-b"
    review_artifact["kind"] = "REVIEW"
    return {
        "certificationId": "cert.test-center.sample",
        "candidateCommit": ONE,
        "candidateTree": TWO,
        "scope": "canonical test center contract",
        "requiredTestIds": ["tc.test-center.contracts"],
        "observedResults": observed,
        "platformMatrix": {
            "required": ["linux", "macos", "windows"],
            "observed": ["linux", "macos", "windows"],
        },
        "evidenceBindings": [evidence()],
        "independentReview": {
            "reviewId": "review.worker-b.sample",
            "reviewer": "independent-worker",
            "reviewedCommit": ONE,
            "reviewedTree": TWO,
            "decision": "PASS",
            "artifact": review_artifact,
        },
        "status": "PASS",
        "staleness": {"isStale": False, "evaluatedAt": "2026-08-05T10:05:00Z"},
        "findings": [],
        "supportImpact": "NONE",
    }


class TestCenterContractsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = json.loads(
            (PROJECT / tc.REGISTRY_RELATIVE).read_text(encoding="utf-8")
        )

    def test_schema_validity(self) -> None:
        report = tc.validate_project(PROJECT)
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["checkMode"], "NON_MUTATING")

    def test_stable_test_identity(self) -> None:
        tc.validate_stable_test_identity(self.registry)
        self.assertTrue(tc.STABLE_TEST_ID_RE.fullmatch("tc.module.case-name"))
        self.assertFalse(tc.STABLE_TEST_ID_RE.fullmatch("P2-001"))

    def test_duplicate_id_rejection(self) -> None:
        broken = copy.deepcopy(self.registry)
        broken["testCases"].append(copy.deepcopy(broken["testCases"][0]))
        with self.assertRaisesRegex(tc.ContractError, "duplicate test case IDs"):
            tc.validate_stable_test_identity(broken)

    def test_invalid_state_coercion_rejection(self) -> None:
        with self.assertRaisesRegex(tc.ContractError, "coercion rejected"):
            tc.normalize_result_state("SUCCESS")
        with self.assertRaisesRegex(tc.ContractError, "coercion rejected"):
            tc.normalize_result_state("passed")

    def test_unsafe_command_profile_rejection(self) -> None:
        profile = copy.deepcopy(self.registry["projectTestProfiles"][0])
        profile["argv"] = ["bash", "-c", "python tool/test_center_contracts.py check"]
        with self.assertRaisesRegex(tc.ContractError, "shell executable"):
            tc.validate_project_test_profile(profile)
        profile["argv"] = ["python", "tool/test_center_contracts.py", "&&", "echo"]
        with self.assertRaisesRegex(tc.ContractError, "shell control"):
            tc.validate_project_test_profile(profile)

    def test_known_mutating_operations_are_rejected(self) -> None:
        profile = copy.deepcopy(self.registry["projectTestProfiles"][0])
        for argv in (
            ["git", "push", "origin", "main"],
            ["dart", "format", "."],
            ["python", "tool/generate_contracts.py"],
            ["python", "tool/repair_contracts.py"],
        ):
            with self.subTest(argv=argv):
                candidate = copy.deepcopy(profile)
                candidate["argv"] = argv
                with self.assertRaises(tc.ContractError):
                    tc.validate_project_test_profile(candidate)

    def test_mutation_policy_enforcement(self) -> None:
        profile = copy.deepcopy(self.registry["projectTestProfiles"][0])
        profile["mutationPolicy"] = "MUTATING_REPAIR"
        with self.assertRaisesRegex(tc.ContractError, "NON_MUTATING"):
            tc.validate_project_test_profile(profile)

    def test_exact_sha_evidence_binding(self) -> None:
        tc.validate_evidence_binding(evidence(), candidate_commit=ONE, candidate_tree=TWO)
        with self.assertRaisesRegex(tc.ContractError, "another commit/tree"):
            tc.validate_evidence_binding(evidence("3" * 40), candidate_commit=ONE, candidate_tree=TWO)

    def test_stale_certification_rejection(self) -> None:
        record = certification()
        record["staleness"]["isStale"] = True
        record["staleness"]["reason"] = "candidate head changed"
        with self.assertRaisesRegex(tc.ContractError, "stale certification"):
            tc.validate_certification(record)

    def test_missing_platform_rejection(self) -> None:
        record = certification()
        record["platformMatrix"]["observed"].remove("windows")
        with self.assertRaisesRegex(tc.ContractError, "required platform"):
            tc.validate_certification(record)

    def test_missing_cleanup_rejection(self) -> None:
        record = certification()
        record["observedResults"][0]["cleanupState"] = "UNRESOLVED"
        with self.assertRaisesRegex(tc.ContractError, "cleanup unresolved"):
            tc.validate_certification(record)

    def test_missing_review_rejection(self) -> None:
        record = certification()
        del record["independentReview"]
        with self.assertRaisesRegex(tc.ContractError, "independent review"):
            tc.validate_certification(record)

    def test_affected_test_selection_determinism(self) -> None:
        paths_a = ["tool/test_center_contracts.py", "schemas/test_center.v1.json"]
        paths_b = list(reversed(paths_a))
        mappings_a = self.registry["affectedTestMappings"]
        mappings_b = list(reversed(mappings_a))
        self.assertEqual(
            tc.select_affected_tests(paths_a, mappings_a),
            tc.select_affected_tests(paths_b, mappings_b),
        )
        self.assertEqual(
            tc.select_affected_tests(paths_a, mappings_a),
            ["tc.test-center.contracts", "tc.test-center.semantic-regressions"],
        )

    def test_result_normalization(self) -> None:
        normalized = tc.normalize_legacy_result(
            {"status": "passed", "exitCode": 0},
            test_id="tc.test-center.contracts",
            module_id="tm.test-center",
        )
        self.assertEqual(normalized["resultState"], "PASS")
        self.assertNotIn("roadmapTaskStatus", normalized)
        self.assertNotIn("certificationStatus", normalized)
        self.assertNotIn("capabilitySupportStatus", normalized)

    def test_presentation_record_validity(self) -> None:
        presentation = copy.deepcopy(self.registry["testingStudioPresentationRecords"][0])
        tc.validate_presentation(presentation)
        presentation["stateDomain"] = "CERTIFICATION"
        presentation["currentState"] = "DONE"
        with self.assertRaisesRegex(tc.ContractError, "invalid for domain"):
            tc.validate_presentation(presentation)

    def test_pass_does_not_inflate_other_domains(self) -> None:
        self.assertIn("PASS", tc.TEST_RESULT_STATES)
        self.assertNotIn("PASS", tc.ROADMAP_TASK_STATES)
        self.assertNotIn("DONE", tc.TEST_RESULT_STATES)
        self.assertNotIn("RELEASE_SUPPORTED", tc.TEST_RESULT_STATES)

    def test_non_pass_result_requires_failure_classification(self) -> None:
        item = result(state="BLOCKED")
        item["failureClassification"] = "NONE"
        with self.assertRaisesRegex(tc.ContractError, "failure classification"):
            tc.validate_test_execution_result(item)

    def test_pass_certification_accepts_complete_fixture(self) -> None:
        tc.validate_certification(certification())


if __name__ == "__main__":
    unittest.main(verbosity=2)
