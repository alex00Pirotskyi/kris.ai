#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import mission_runtime_model as runtime


class MissionRuntimeHistoryCompatTest(unittest.TestCase):
    def test_terminal_work_order_uses_audit_shape_not_current_policy(self) -> None:
        item = {
            "schemaVersion": 1,
            "workOrderId": "WO-LEGACY-AUDIT-0001",
            "mission": "MISSION-001",
            "roadmapTask": "P0-001",
            "parentProductPr": None,
            "priority": 1,
            "type": "IMPLEMENTATION",
            "objective": "Preserve legacy immutable audit history.",
            "requestedRole": "IMPLEMENTER",
            "allowedPaths": ["docs/roadmap/missions/delivery/records/P0-001/**"],
            "baseCommit": "e" * 40,
            "baseTree": "f" * 40,
            "dependencyRequirements": ["WO-OLD@LANDED"],
            "requiredTests": [],
            "maxChildWorkOrders": 0,
            "status": "LANDED",
            "createdBy": "LEGACY",
            "createdAt": "2026-08-01T00:00:00Z",
            "updatedAt": "2026-08-01T00:00:01Z",
        }
        with tempfile.TemporaryDirectory() as directory:
            runtime._audit_non_authoritative_work_order(pathlib.Path(directory), item)

    def test_locally_available_historical_commit_still_requires_exact_tree(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            project = pathlib.Path(directory)
            subprocess.run(["git", "init", "-q", str(project)], check=True)
            subprocess.run(
                ["git", "-C", str(project), "config", "user.name", "test"], check=True
            )
            subprocess.run(
                ["git", "-C", str(project), "config", "user.email", "test@example.invalid"],
                check=True,
            )
            (project / "x").write_text("x\n", encoding="utf-8")
            subprocess.run(["git", "-C", str(project), "add", "x"], check=True)
            subprocess.run(
                ["git", "-C", str(project), "commit", "-q", "-m", "fixture"], check=True
            )
            head = subprocess.check_output(
                ["git", "-C", str(project), "rev-parse", "HEAD"], text=True
            ).strip()
            with self.assertRaisesRegex(ValueError, "baseCommit/baseTree mismatch"):
                runtime._audit_git_binding(project, head, "0" * 40, "fixture")

    def test_terminal_children_do_not_consume_live_child_budget(self) -> None:
        parent = {
            "mission": "MISSION-001",
            "roadmapTask": "P0-001",
            "parentProductPr": 1,
            "maxChildWorkOrders": 0,
        }
        landed_child = {
            "mission": "MISSION-002",
            "roadmapTask": "P2-004",
            "parentProductPr": 2,
            "parentWorkOrderId": "WO-PARENT",
            "status": "LANDED",
        }
        runtime.validate_delegation_graph(
            {"WO-PARENT": parent, "WO-HISTORY": landed_child}
        )

    def test_operational_child_budget_remains_strict(self) -> None:
        parent = {
            "mission": "MISSION-001",
            "roadmapTask": "P0-001",
            "parentProductPr": 1,
            "maxChildWorkOrders": 0,
        }
        active_child = {
            "mission": "MISSION-001",
            "roadmapTask": "P0-001",
            "parentProductPr": 1,
            "parentWorkOrderId": "WO-PARENT",
            "status": "READY",
        }
        with self.assertRaisesRegex(ValueError, "child budget exceeded"):
            runtime.validate_delegation_graph(
                {"WO-PARENT": parent, "WO-ACTIVE": active_child}
            )


if __name__ == "__main__":
    unittest.main()
