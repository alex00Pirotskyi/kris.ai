#!/usr/bin/env python3
from __future__ import annotations

import copy
import datetime as dt
import importlib.util
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "mission_delivery_control",
    HERE / "mission_delivery_control.py",
)
assert SPEC and SPEC.loader
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


def write_json(path: pathlib.Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def git(project: pathlib.Path, *args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=project,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return result.stdout.strip()


class MissionDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.project = pathlib.Path(self.temp.name)
        for path in [
            "config",
            "docs/roadmap/missions",
            "docs/roadmap/missions/delivery/records",
            "tool",
            "lib/a",
            "lib/b",
        ]:
            (self.project / path).mkdir(parents=True, exist_ok=True)

        self.config = {
            "schemaVersion": 1,
            "statuses": [
                "NOT_EVALUATED","DISCOVERY","IMPLEMENTATION","VALIDATION","REVIEW",
                "BLOCKED","BLOCKED_EXTERNAL","ACCEPTED","MERGED_MAIN","SUPERSEDED"
            ],
            "terminalAcceptedStatuses":["ACCEPTED","MERGED_MAIN"],
            "recordsRoot":"docs/roadmap/missions/delivery/records",
            "generated":{
                "metrics":"docs/roadmap/missions/DELIVERY_METRICS.json",
                "dashboard":"docs/roadmap/missions/DELIVERY_DASHBOARD.md"
            },
            "priorityOrder":{"CRITICAL_PATH":0,"HIGH":1},
            "commonGeneratedPaths":[
                "SOURCE_MANIFEST.sha256",
                "docs/roadmap/missions/DELIVERY_METRICS.json",
                "docs/roadmap/missions/DELIVERY_DASHBOARD.md",
                "docs/roadmap/missions/delivery/records/**"
            ],
            "missionPathPolicies":{
                "MISSION-001":{
                    "owned":["lib/a/**","tool/a*.py"],
                    "namespaces":[{"pattern":"lib/a/**","mode":"EXISTING_ON_CLAIM_BRANCH"}],
                },
                "MISSION-002":{
                    "owned":["lib/b/**","tool/test_center*.py"],
                    "namespaces":[{"pattern":"lib/b/**","mode":"RESERVED_FUTURE_NAMESPACE"}],
                },
            },
            "sharedAuthorities":[
                {
                    "authorityId":"tc",
                    "ownerMission":"MISSION-002",
                    "patterns":["tool/test_center*.py"],
                    "ownerReviewRequired":True,
                }
            ],
            "sharedPathGrants":[
                {
                    "coordinationId":"A-TC",
                    "requestingMission":"MISSION-001",
                    "ownerMission":"MISSION-002",
                    "patterns":["tool/test_center_portability_test.py"],
                    "operations":["append-regression"],
                    "ownerReviewRequired":True,
                }
            ],
            "reviewScopes":{
                "SOURCE":["lib/**","tool/**"],
                "SECURITY":["tool/*security*"],
                "EVIDENCE":["release/evidence/**","SOURCE_MANIFEST.sha256"],
                "INTEGRATION":["tool/test_center*.py","SOURCE_MANIFEST.sha256"],
            },
            "branchLifecycle":{
                "protectedPatterns":["main"],
                "backupPatterns":["*-backup*"],
                "ephemeralPatterns":["ci/*"],
                "staleDays":14,
                "deleteOnlyWhenNoOpenPr":True,
            },
        }
        write_json(self.project / M.CONFIG, self.config)
        registry = {
            "schemaVersion":1,
            "missionCount":2,
            "taskCount":3,
            "missions":[
                {
                    "id":"MISSION-001","title":"A","priority":"CRITICAL_PATH",
                    "entryDependsOn":[],"taskCount":2,
                    "activeClaim":{"mission":"MISSION-001","worker":"A","branch":"agent/a","pr":1,"head":"a"*40,"status":"CLAIMED"},
                },
                {
                    "id":"MISSION-002","title":"B","priority":"HIGH",
                    "entryDependsOn":["MISSION-001"],"taskCount":1,"activeClaim":None,
                },
            ],
        }
        write_json(self.project / M.REGISTRY, registry)
        tasks = {
            "schemaVersion":1,
            "taskCount":3,
            "tasks":[
                {"id":"P1-001","mission":"MISSION-001","dependencies":[]},
                {"id":"P1-002","mission":"MISSION-001","dependencies":["P1-001"]},
                {"id":"P2-001","mission":"MISSION-002","dependencies":["P1-002"]},
            ],
        }
        write_json(self.project / M.TASKS, tasks)
        write_json(self.project / M.INTERLOCKS, {"schemaVersion":1,"count":1,"interlocks":[]})
        mission_config = {
            "schemaVersion":1,
            "missions":[
                {"id":"MISSION-001"},{"id":"MISSION-002"},
            ],
            "activeClaims":[
                {"mission":"MISSION-001","worker":"A","branch":"agent/a","pr":1,"head":"a"*40,"status":"CLAIMED"}
            ],
        }
        write_json(self.project / M.MISSION_CONFIG, mission_config)
        (self.project / "lib/a/file.txt").write_text("a\n", encoding="utf-8")

        git(self.project, "init")
        git(self.project, "config", "user.email", "test@example.com")
        git(self.project, "config", "user.name", "Test")
        git(self.project, "add", ".")
        git(self.project, "commit", "-m", "base")
        self.base = git(self.project, "rev-parse", "HEAD")

    def tearDown(self):
        self.temp.cleanup()

    def model(self):
        return M.validate_model(self.project)

    def test_work_id_is_repository_valid(self):
        value = M.execution_id(
            dt.datetime(2026, 8, 6, 1, 2, 3, tzinfo=dt.timezone.utc),
            b"fixed",
        )
        self.assertRegex(value, M.WORK_ID_RE)
        self.assertEqual(value[:20], "WRK-20260806T010203Z")

    def test_owned_shared_generated_and_violation_paths(self):
        result = M.classify_changed_paths(
            "MISSION-001",
            [
                "lib/a/file.txt",
                "tool/test_center_portability_test.py",
                "SOURCE_MANIFEST.sha256",
                "lib/b/nope.txt",
                "unknown.txt",
            ],
            self.model(),
        )
        categories = {row["path"]:row["category"] for row in result["paths"]}
        self.assertEqual(categories["lib/a/file.txt"], "MISSION_OWNED")
        self.assertEqual(categories["tool/test_center_portability_test.py"], "APPROVED_SHARED")
        self.assertEqual(categories["SOURCE_MANIFEST.sha256"], "GENERATOR_OWNED")
        self.assertEqual(categories["lib/b/nope.txt"], "OTHER_MISSION_PATH")
        self.assertEqual(categories["unknown.txt"], "UNDECLARED_PATH")
        self.assertFalse(result["authorized"])
        self.assertEqual(result["requiredOwnerReviews"], ["MISSION-002"])

    def test_ungranted_shared_authority_rejected(self):
        result = M.classify_changed_paths(
            "MISSION-001",
            ["tool/test_center_contracts.py"],
            self.model(),
        )
        self.assertEqual(result["paths"][0]["category"], "UNGRANTED_SHARED_AUTHORITY")
        self.assertFalse(result["authorized"])

    def test_existing_and_reserved_namespace_modes(self):
        diagnostics = M.namespace_diagnostics(self.project, "MISSION-001", self.model())
        self.assertEqual(diagnostics[0]["state"], "PASS")
        reserved = M.namespace_diagnostics(self.project, "MISSION-002", self.model())
        self.assertEqual(reserved[0]["state"], "RESERVED")
        (self.project / "lib/a/file.txt").unlink()
        diagnostics = M.namespace_diagnostics(self.project, "MISSION-001", self.model())
        self.assertEqual(diagnostics[0]["state"], "FAIL")

    def test_scoped_review_impact_not_tree_only(self):
        result = M.review_impact(
            ["lib/a/file.txt", "SOURCE_MANIFEST.sha256"],
            self.model(),
        )
        self.assertIn("SOURCE", result["invalidatedScopes"])
        self.assertIn("EVIDENCE", result["invalidatedScopes"])
        self.assertIn("INTEGRATION", result["invalidatedScopes"])
        self.assertFalse(result["treeOnlyReviewBindingAllowed"])

    def test_missing_records_are_not_evaluated_not_complete(self):
        metrics = M.delivery_metrics(self.project, self.model())
        self.assertEqual(metrics["taskCount"], 3)
        self.assertEqual(metrics["acceptedTaskCount"], 0)
        self.assertEqual(metrics["notEvaluatedTaskCount"], 3)
        self.assertEqual(metrics["progressPercentage"], 0.0)
        self.assertEqual(metrics["explicitRecordCount"], 0)

    def test_accepted_record_requires_exact_evidence(self):
        model = self.model()
        record = {
            "schemaVersion":1,
            "mission":"MISSION-001",
            "task":"P1-001",
            "status":"ACCEPTED",
            "workExecutionId":"WRK-20260806T010203Z-1234abcd",
            "recordedAt":"2026-08-06T01:02:03Z",
            "commit":"a"*40,
            "tree":"b"*40,
            "evidence":[],
        }
        with self.assertRaises(M.DeliveryError):
            M.validate_record(record, model)
        record["evidence"] = ["run:1"]
        M.validate_record(record, model)

    def test_append_only_record_changes_frontier_deterministically(self):
        model = self.model()
        target = M.append_record(
            project=self.project,
            model=model,
            mission="MISSION-001",
            task="P1-001",
            status="ACCEPTED",
            work_id="WRK-20260806T010203Z-1234abcd",
            worker="A",
            branch="agent/a",
            pr=1,
            commit="a"*40,
            tree="b"*40,
            evidence=["run:1"],
            next_action="P1-002",
            merged_main_commit=None,
        )
        self.assertTrue(target.exists())
        metrics = M.delivery_metrics(self.project, self.model())
        row = next(item for item in metrics["missions"] if item["mission"] == "MISSION-001")
        self.assertEqual(row["acceptedTasks"], 1)
        self.assertEqual(row["records"][0]["task"], "P1-001")

    def test_git_diff_ownership_uses_actual_changed_files(self):
        (self.project / "lib/b/nope.txt").write_text("bad\n", encoding="utf-8")
        git(self.project, "add", ".")
        git(self.project, "commit", "-m", "foreign")
        head = git(self.project, "rev-parse", "HEAD")
        paths = M.git_changed_paths(self.project, self.base, head)
        self.assertIn("lib/b/nope.txt", paths)
        result = M.classify_changed_paths("MISSION-001", paths, self.model())
        self.assertFalse(result["authorized"])

    def test_infer_mission_requires_single_candidate(self):
        model = self.model()
        self.assertEqual(M.infer_mission("agent/a", "", model), "MISSION-001")
        with self.assertRaises(M.DeliveryError):
            M.infer_mission("unknown", "", model)


if __name__ == "__main__":
    unittest.main()
