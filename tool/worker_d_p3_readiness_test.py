from __future__ import annotations
import importlib.util
import json
import tempfile
import unittest
from hashlib import sha256
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("worker_d_p3_readiness.py")
SPEC = importlib.util.spec_from_file_location("worker_d_p3_readiness", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
ROOT = Path(__file__).resolve().parents[1]
RECORDS = (
    "release/evidence/P3-001/dependency-status.json",
    "release/evidence/P3-001/runtime-candidate-matrix.json",
    "release/evidence/P3-001/fixture-specification.json",
    "release/evidence/P3-001/test-center-registration.json",
    "release/evidence/P3-001/claim-boundary.json",
    "release/evidence/P3-001/manifest.json",
    "release/evidence/P3-001/packaging-readiness-contract.json",
    "release/evidence/P3-001/READINESS.md",
    "docs/roadmap/progress/2026-08-05-p3-001-readiness.md",
)

class ReadinessTests(unittest.TestCase):
    def copy_records(self, destination: Path) -> None:
        for rel in RECORDS:
            target = destination / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / rel).read_bytes())

    def mutate_json(self, destination: Path, rel: str, mutation) -> list[str]:
        self.copy_records(destination)
        path = destination / rel
        data = json.loads(path.read_text(encoding="utf-8"))
        mutation(data)
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8", newline="\n")
        return MODULE.validate(destination)

    def test_repository_records_pass(self):
        self.assertEqual([], MODULE.validate(ROOT))

    def test_fixture_checksum_mutation_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            errors = self.mutate_json(
                Path(temp),
                "release/evidence/P3-001/fixture-specification.json",
                lambda data: data["fixtures"][0].__setitem__("purpose", "mutated"),
            )
            self.assertTrue(any("checksum mismatch" in error for error in errors))

    def test_order_independent_selection_contract(self):
        paths = [
            "tool/worker_d_p3_readiness.py",
            "release/evidence/P3-001/fixture-specification.json",
        ]
        selected = lambda values: sorted(
            {
                "tc.p3.readiness.fixture-specification",
                "tc.p3.readiness.fixture-determinism",
                "tc.p3.readiness.network-denial",
            }
            if any("fixture-specification" in value for value in values)
            else {"tc.p3.readiness.dependencies"}
        )
        self.assertEqual(selected(paths), selected(list(reversed(paths))))

    def test_candidate_commit_placeholder_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            errors = self.mutate_json(
                Path(temp),
                "release/evidence/P3-001/test-center-registration.json",
                lambda data: data["developmentVerificationRequest"].__setitem__(
                    "candidateCommit", "STAGE_1_COMMIT_PENDING"
                ),
            )
            self.assertTrue(any("candidate commit unresolved identity placeholder" in error for error in errors))

    def test_candidate_tree_placeholder_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            errors = self.mutate_json(
                Path(temp),
                "release/evidence/P3-001/test-center-registration.json",
                lambda data: data["developmentVerificationRequest"].__setitem__(
                    "candidateTree", "STAGE_1_TREE_PENDING"
                ),
            )
            self.assertTrue(any("candidate tree unresolved identity placeholder" in error for error in errors))

    def test_workflow_identity_placeholder_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            errors = self.mutate_json(
                Path(temp),
                "release/evidence/P3-001/manifest.json",
                lambda data: data["workflowEvidence"]["workerDReadiness"].__setitem__(
                    "headSha", "PENDING_EXACT_HEAD_CI"
                ),
            )
            self.assertTrue(any("workerDReadiness head SHA unresolved identity placeholder" in error for error in errors))

    def test_source_manifest_placeholder_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            errors = self.mutate_json(
                Path(temp),
                "release/evidence/P3-001/manifest.json",
                lambda data: data["sourceManifestEvidence"]["stage1"].__setitem__(
                    "sha256", "TODO_SHA"
                ),
            )
            self.assertTrue(any("source-manifest SHA-256 unresolved identity placeholder" in error for error in errors))

    def test_valid_40_character_sha_accepted(self):
        self.assertTrue(MODULE.is_sha40("a" * 40))
        self.assertFalse(MODULE.identity_placeholder("a" * 40))

    def test_stage1_and_stage2_identities_remain_distinct(self):
        self.assertTrue(
            MODULE.stage_identities_distinct(
                MODULE.STAGE1_COMMIT, MODULE.STAGE1_TREE, "a" * 40, "b" * 40
            )
        )
        self.assertFalse(
            MODULE.stage_identities_distinct(
                MODULE.STAGE1_COMMIT,
                MODULE.STAGE1_TREE,
                MODULE.STAGE1_COMMIT,
                MODULE.STAGE1_TREE,
            )
        )

    def test_no_evidence_record_rewrites_stage1_as_stage2(self):
        with tempfile.TemporaryDirectory() as temp:
            def mutate(data):
                data["evidencePackagingCandidate"]["commit"] = MODULE.STAGE1_COMMIT
                data["evidencePackagingCandidate"]["tree"] = MODULE.STAGE1_TREE
            errors = self.mutate_json(
                Path(temp), "release/evidence/P3-001/manifest.json", mutate
            )
            self.assertTrue(any("Stage 1 identity rewritten as Stage 2" in error for error in errors))

    def test_validator_is_non_mutating(self):
        before = {
            rel: sha256((ROOT / rel).read_bytes()).hexdigest()
            for rel in RECORDS
        }
        self.assertEqual([], MODULE.validate(ROOT))
        after = {
            rel: sha256((ROOT / rel).read_bytes()).hexdigest()
            for rel in RECORDS
        }
        self.assertEqual(before, after)

if __name__ == "__main__":
    unittest.main()
