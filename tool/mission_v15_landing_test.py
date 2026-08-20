#!/usr/bin/env python3
"""Mission Execution 1.5 source-landing semantic regressions."""
from __future__ import annotations

import datetime as dt
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

THIS = pathlib.Path(__file__).resolve()
if str(THIS.parent) not in sys.path:
    sys.path.insert(0, str(THIS.parent))

from mission_delivery_lib import DeliveryError
from mission_delivery_strict import LINEAR_LANDING_MODE, validate_source_landing
from mission_v15_landing_gate import (
    ExactLandingValidationError,
    _promotes_without_acceptance,
    validate_exact_main_landing,
)


class LandingSemanticsTests(unittest.TestCase):
    def base(self):
        return {
            "task": "P6-001",
            "status": "VALIDATION",
            "sourceLanding": "LANDED_MAIN",
            "behavioralSupport": "NOT_EVALUATED",
            "platformSupport": "NOT_ESTABLISHED",
            "releaseSupport": "UNSUPPORTED",
            "productionReadiness": "NOT_CLAIMED",
            "gaReadiness": "NOT_CLAIMED",
            "supportPromotion": False,
        }

    def test_truthful_source_only_landing_passes(self):
        self.assertEqual(_promotes_without_acceptance(self.base()), [])

    def test_platform_support_promotion_fails(self):
        value = self.base()
        value["platformSupport"] = "SUPPORTED"
        self.assertTrue(_promotes_without_acceptance(value))

    def test_release_support_promotion_fails(self):
        value = self.base()
        value["releaseSupport"] = "SUPPORTED"
        self.assertTrue(_promotes_without_acceptance(value))

    def test_ga_promotion_fails(self):
        value = self.base()
        value["gaReadiness"] = "GA_READY"
        self.assertTrue(_promotes_without_acceptance(value))

    def test_explicit_support_promotion_flag_fails(self):
        value = self.base()
        value["supportPromotion"] = True
        self.assertTrue(_promotes_without_acceptance(value))

    def test_accepted_record_is_not_rejected_by_source_only_rule(self):
        value = self.base()
        value["status"] = "ACCEPTED"
        value["platformSupport"] = "SUPPORTED"
        self.assertEqual(_promotes_without_acceptance(value), [])


class LinearLandingProofTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mission-v15-linear-landing-")
        self.repo = pathlib.Path(self.temp.name)
        self._git("init")
        self._git("config", "user.name", "Mission V1.5 Test")
        self._git("config", "user.email", "mission-v15-test@example.invalid")
        (self.repo / "product.txt").write_text("base\n", encoding="utf-8")
        self._git("add", "product.txt")
        self._git("commit", "-m", "base")
        self.base_commit = self._git("rev-parse", "HEAD")

        (self.repo / "product.txt").write_text("candidate\n", encoding="utf-8")
        self._git("add", "product.txt")
        self._git("commit", "-m", "candidate")
        self.candidate = self._git("rev-parse", "HEAD")
        self.candidate_tree = self._git("rev-parse", f"{self.candidate}^{{tree}}")

    def tearDown(self):
        self.temp.cleanup()

    def _git(self, *args: str, input_text: str | None = None) -> str:
        result = subprocess.run(
            ["git", *args],
            cwd=self.repo,
            text=True,
            input=input_text,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(
                f"git {' '.join(args)} failed ({result.returncode}): {result.stderr}"
            )
        return result.stdout.strip()

    def _commit_tree(self, tree: str, parent: str, message: str) -> str:
        return self._git(
            "commit-tree",
            tree,
            "-p",
            parent,
            input_text=message + "\n",
        )

    def _linear_record(self, merged: str, merged_tree: str | None = None) -> dict:
        return {
            "sourceLanding": "LANDED_MAIN",
            "commit": self.candidate,
            "tree": self.candidate_tree,
            "mergedMainCommit": merged,
            "sourceLandingProof": {
                "mode": LINEAR_LANDING_MODE,
                "landingBaseCommit": self.base_commit,
                "mergedMainTree": merged_tree or self.candidate_tree,
            },
        }

    def test_tree_equivalent_linear_landing_passes(self):
        landed = self._commit_tree(
            self.candidate_tree,
            self.base_commit,
            "squash-equivalent landing",
        )
        self.assertNotEqual(landed, self.candidate)
        validate_source_landing(
            self.repo,
            self._linear_record(landed),
            pathlib.Path("linear.json"),
        )

    def test_tree_equivalent_linear_landing_rejects_tree_drift(self):
        (self.repo / "product.txt").write_text("different-main-tree\n", encoding="utf-8")
        self._git("add", "product.txt")
        drift_tree = self._git("write-tree")
        landed = self._commit_tree(drift_tree, self.base_commit, "drifted landing")
        with self.assertRaises(DeliveryError):
            validate_source_landing(
                self.repo,
                self._linear_record(landed, drift_tree),
                pathlib.Path("tree-drift.json"),
            )

    def test_tree_equivalent_linear_landing_rejects_wrong_parent(self):
        landed = self._commit_tree(
            self.candidate_tree,
            self.candidate,
            "wrong-parent landing",
        )
        with self.assertRaises(DeliveryError):
            validate_source_landing(
                self.repo,
                self._linear_record(landed),
                pathlib.Path("wrong-parent.json"),
            )

    def test_legacy_ancestry_landing_remains_valid(self):
        landed = self._commit_tree(
            self.candidate_tree,
            self.candidate,
            "legacy descendant landing",
        )
        validate_source_landing(
            self.repo,
            {
                "sourceLanding": "LANDED_MAIN",
                "commit": self.candidate,
                "mergedMainCommit": landed,
            },
            pathlib.Path("legacy.json"),
        )


class ExactMainLandingReceiptTests(unittest.TestCase):
    NOW = dt.datetime(2026, 8, 13, 0, 35, tzinfo=dt.timezone.utc)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mission-v15-exact-main-")
        self.root = pathlib.Path(self.temp.name)
        self.target = self.root / "target"
        self.runtime = self.root / "runtime"
        self.target.mkdir()
        self.runtime.mkdir()
        self._init_repo(self.target)
        self._init_repo(self.runtime)
        self._build_target()
        self._build_runtime()
        self._write_receipts()

    def tearDown(self):
        self.temp.cleanup()

    def _init_repo(self, repo: pathlib.Path) -> None:
        self._git(repo, "init")
        self._git(repo, "config", "user.name", "Mission V1.5 Test")
        self._git(repo, "config", "user.email", "mission-v15-test@example.invalid")

    def _git(
        self,
        repo: pathlib.Path,
        *args: str,
        input_text: str | None = None,
    ) -> str:
        result = subprocess.run(
            ["git", *args],
            cwd=repo,
            text=True,
            input=input_text,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(
                f"git {' '.join(args)} failed ({result.returncode}): {result.stderr}"
            )
        return result.stdout.strip()

    def _write_json(self, path: pathlib.Path, value: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    def _build_target(self) -> None:
        (self.target / "tool").mkdir()
        (self.target / "tool" / "p1a_refresh_source_manifest.py").write_text(
            "#!/usr/bin/env python3\nimport pathlib, sys\n"
            "p = pathlib.Path(sys.argv[1]) / 'SOURCE_MANIFEST.sha256'\n"
            "p.write_bytes(p.read_bytes())\n",
            encoding="utf-8",
        )
        (self.target / "SOURCE_MANIFEST.sha256").write_text(
            "fixture  product.txt\n", encoding="utf-8"
        )
        (self.target / "product.txt").write_text("base\n", encoding="utf-8")
        self._git(self.target, "add", ".")
        self._git(self.target, "commit", "-m", "base")
        self.base = self._git(self.target, "rev-parse", "HEAD")

        self._git(self.target, "checkout", "-b", "agent/g/mission-006-model-routing")
        (self.target / "product.txt").write_text("candidate\n", encoding="utf-8")
        self._git(self.target, "add", "product.txt")
        self._git(self.target, "commit", "-m", "candidate")
        self.source = self._git(self.target, "rev-parse", "HEAD")
        self.source_tree = self._git(self.target, "rev-parse", "HEAD^{tree}")

        self.landed = self._git(
            self.target,
            "commit-tree",
            self.source_tree,
            "-p",
            self.base,
            input_text="squash landing\n",
        )
        self._git(self.target, "checkout", "--detach", self.landed)
        self._git(
            self.target,
            "update-ref",
            "refs/remotes/origin/agent/g/mission-006-model-routing",
            self.source,
        )

    def _build_runtime(self) -> None:
        mission = "MISSION-006"
        work_order_id = "WO-P6-001-CURRENT-MAIN-LANDING-B6E4C9A1"
        semaphore_id = "SEM-P6-001-CURRENT-MAIN-LANDING-B6E4C9A1"
        self._write_json(
            self.runtime / "runtime" / "meta.json",
            {"schemaVersion": 1, "runtimeGeneration": 545},
        )
        self._write_json(
            self.runtime / "runtime" / "work-orders" / mission / f"{work_order_id}.json",
            {
                "schemaVersion": 1,
                "workOrderId": work_order_id,
                "mission": mission,
                "roadmapTask": "P6-001",
                "status": "INTEGRATING",
                "executionRole": "INTEGRATOR",
                "baseCommit": self.source,
                "baseTree": self.source_tree,
                "parentProductPr": 76,
                "activeSemaphoreId": semaphore_id,
            },
        )
        self._write_json(
            self.runtime / "runtime" / "semaphores" / mission / f"{semaphore_id}.json",
            {
                "schemaVersion": 1,
                "semaphoreId": semaphore_id,
                "workOrderId": work_order_id,
                "status": "ACTIVE",
                "productPr": 76,
                "baseCommit": self.source,
                "baseTree": self.source_tree,
                "expiresAt": "2026-08-13T03:57:00Z",
            },
        )
        self._write_json(
            self.runtime / "runtime" / "events" / "2026-08-12" / "EVT-00000545-SEMAPHORE_ACQUIRED.json",
            {
                "schemaVersion": 1,
                "eventId": "EVT-00000545-SEMAPHORE_ACQUIRED",
                "eventType": "SEMAPHORE_ACQUIRED",
                "runtimeGeneration": 545,
                "workOrderId": work_order_id,
                "payload": {
                    "kind": "INTEGRATION",
                    "expectedProductHead": self.source,
                    "canonicalProductTree": self.source_tree,
                    "protectedMain": self.base,
                    "productPr": 76,
                    "mergeMethod": "squash",
                    "semaphoreId": semaphore_id,
                },
            },
        )
        self._git(self.runtime, "add", ".")
        self._git(self.runtime, "commit", "-m", "runtime authority")
        self.runtime_commit = self._git(self.runtime, "rev-parse", "HEAD")

    def _write_receipts(self) -> None:
        self.request = {
            "schemaVersion": 1,
            "requestId": "REQ-P6-001-TEST",
            "mission": "MISSION-006",
            "task": "P6-001",
            "landingWorkOrderId": "WO-P6-001-CURRENT-MAIN-LANDING-B6E4C9A1",
            "landingSemaphoreId": "SEM-P6-001-CURRENT-MAIN-LANDING-B6E4C9A1",
            "runtimeCommit": self.runtime_commit,
            "runtimeGeneration": 545,
            "productPr": 76,
            "sourceBranch": "agent/g/mission-006-model-routing",
            "sourceCommit": self.source,
            "sourceTree": self.source_tree,
            "landingBaseCommit": self.base,
            "mergedMainCommit": self.landed,
            "mergedMainTree": self.source_tree,
            "productGatesRun": 1234,
            "expectedJobs": [
                {"name": "validate-ubuntu", "id": 11},
                {"name": "validate-windows", "id": 12},
                {"name": "validate-macos", "id": 13},
            ],
        }
        self.pr = {
            "number": 76,
            "state": "closed",
            "merged": True,
            "merged_at": "2026-08-12T22:14:55Z",
            "merge_commit_sha": self.landed,
            "head": {"sha": self.source},
            "base": {"sha": self.base},
        }
        self.run = {
            "id": 1234,
            "name": "product-gates",
            "head_sha": self.landed,
            "event": "push",
            "status": "completed",
            "conclusion": "success",
        }
        self.jobs = {
            "jobs": [
                {
                    "id": 11,
                    "name": "validate-ubuntu",
                    "head_sha": self.landed,
                    "status": "completed",
                    "conclusion": "success",
                },
                {
                    "id": 12,
                    "name": "validate-windows",
                    "head_sha": self.landed,
                    "status": "completed",
                    "conclusion": "success",
                },
                {
                    "id": 13,
                    "name": "validate-macos",
                    "head_sha": self.landed,
                    "status": "completed",
                    "conclusion": "success",
                },
            ]
        }
        self.request_path = self.root / "request.json"
        self.pr_path = self.root / "pr.json"
        self.run_path = self.root / "run.json"
        self.jobs_path = self.root / "jobs.json"
        self._flush_receipts()

    def _flush_receipts(self) -> None:
        self._write_json(self.request_path, self.request)
        self._write_json(self.pr_path, self.pr)
        self._write_json(self.run_path, self.run)
        self._write_json(self.jobs_path, self.jobs)

    def _validate(self) -> dict:
        self._flush_receipts()
        return validate_exact_main_landing(
            self.target,
            self.runtime,
            self.request_path,
            self.pr_path,
            self.run_path,
            self.jobs_path,
            now=self.NOW,
        )

    def test_exact_tree_equivalent_main_receipt_passes(self):
        result = self._validate()
        self.assertEqual(result["git"]["mergedMainCommit"], self.landed)
        self.assertEqual(result["productGates"]["runId"], 1234)
        self.assertTrue(result["sourceManifest"]["targetCheckoutUnmodified"])
        self.assertTrue(result["acceptedCountNotInferred"])

    def test_failed_platform_job_is_rejected(self):
        self.jobs["jobs"][1]["conclusion"] = "failure"
        with self.assertRaises(ExactLandingValidationError):
            self._validate()

    def test_pr_source_drift_is_rejected(self):
        self.pr["head"]["sha"] = self.base
        with self.assertRaises(ExactLandingValidationError):
            self._validate()

    def test_expired_landing_semaphore_is_rejected(self):
        sem_path = (
            self.runtime
            / "runtime"
            / "semaphores"
            / "MISSION-006"
            / "SEM-P6-001-CURRENT-MAIN-LANDING-B6E4C9A1.json"
        )
        semaphore = json.loads(sem_path.read_text(encoding="utf-8"))
        semaphore["expiresAt"] = "2026-08-12T23:00:00Z"
        self._write_json(sem_path, semaphore)
        self._git(self.runtime, "add", str(sem_path.relative_to(self.runtime)))
        self._git(self.runtime, "commit", "-m", "expire semaphore")
        self.request["runtimeCommit"] = self._git(self.runtime, "rev-parse", "HEAD")
        with self.assertRaises(ExactLandingValidationError):
            self._validate()

    def test_non_equivalent_main_tree_is_rejected(self):
        self.request["mergedMainTree"] = self.base
        with self.assertRaises(ExactLandingValidationError):
            self._validate()


if __name__ == "__main__":
    unittest.main()
