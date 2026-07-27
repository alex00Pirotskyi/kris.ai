#!/usr/bin/env python3
"""Unit tests for the P0-008 bootstrap roadmap control plane."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import roadmap_control as rc


def master_text(version: str = "test-roadmap") -> str:
    return f"""# Test Master

**Roadmap authority:** `HUMAN_CONSTITUTION`
**Roadmap version:** `{version}`

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P0-001` | Baseline | `none` | Capture truth. | Evidence exists. |
| `P0-002` | Trust retirement | `P0-001` | Disable legacy trust. | Forgery fails. |
| `P0-008` | Roadmap controls | `P0-001` | Add control plane. | Fresh session selects work. |
| `P1-001` | Runtime ADR | `P0-008` | Approve boundaries. | ADR accepted. |
"""


def task_definitions() -> list[dict[str, object]]:
    parsed = rc.parse_master_tasks(master_text())
    statuses = {
        "P0-001": "DONE",
        "P0-002": "READY",
        "P0-008": "REVIEW",
        "P1-001": "NOT_STARTED",
    }
    result = []
    for item in parsed:
        task_id = str(item["id"])
        result.append(
            {
                **item,
                "status": statuses[task_id],
                "packet": f"tasks/active/{task_id}.md",
                "evidence": ([f"release/evidence/{task_id}/evidence.md"] if statuses[task_id] in {"DONE", "REVIEW"} else []),
            }
        )
    return result


def manifest() -> dict[str, object]:
    master = master_text()
    tasks = task_definitions()
    return {
        "schemaVersion": "1.0.0",
        "format": "yaml-1.2-json-subset",
        "roadmapVersion": "test-roadmap",
        "authority": {
            "human": "docs/roadmap/MASTER.md",
            "machine": "docs/roadmap/roadmap.yaml",
            "scope": ["P0", "P1"],
            "masterSha256": hashlib.sha256(master.encode()).hexdigest(),
        },
        "statusValues": list(rc.ALLOWED_STATUSES),
        "taskOrder": ["P0-001", "P0-002", "P0-008", "P1-001"],
        "tasks": tasks,
        "nextReady": ["P0-002"],
        "taskGraphSha256": rc.graph_fingerprint(tasks),
    }


class RoadmapControlTest(unittest.TestCase):
    def assert_has(self, issues: list[rc.Issue], code: str) -> None:
        self.assertIn(code, {item.code for item in issues})

    def make_project(self, data: dict[str, object] | None = None) -> Path:
        temporary = tempfile.TemporaryDirectory(prefix="roadmap-control-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / "docs/roadmap").mkdir(parents=True)
        (root / "tasks/active").mkdir(parents=True)
        (root / "release/evidence").mkdir(parents=True)
        source = data or manifest()
        master = master_text(str(source["roadmapVersion"]))
        (root / "docs/roadmap/MASTER.md").write_text(master, encoding="utf-8")
        for task in source["tasks"]:  # type: ignore[index]
            packet = root / str(task["packet"])
            packet.parent.mkdir(parents=True, exist_ok=True)
            packet.write_text(f"# {task['id']}\n", encoding="utf-8")
            for evidence in task.get("evidence") or []:
                path = root / str(evidence)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("evidence\n", encoding="utf-8")
        source = copy.deepcopy(source)
        source["authority"]["masterSha256"] = hashlib.sha256(master.encode()).hexdigest()  # type: ignore[index]
        (root / "docs/roadmap/roadmap.yaml").write_text(json.dumps(source, indent=2) + "\n", encoding="utf-8")
        (root / "docs/roadmap/STATUS.md").write_text(rc.render_status_text(source), encoding="utf-8")
        return root

    def test_valid_manifest_and_project_pass(self) -> None:
        root = self.make_project()
        report = rc.validate_project(root, strict=True)
        self.assertTrue(report["passed"], report)
        self.assertEqual(report["nextReady"], ["P0-002"])

    def test_duplicate_task_id_rejected(self) -> None:
        data = manifest()
        data["tasks"].append(copy.deepcopy(data["tasks"][0]))  # type: ignore[index,union-attr]
        issues = rc.validate_manifest_data(data, master_text=master_text())
        self.assert_has(issues, "task_id_duplicate")

    def test_missing_dependency_rejected(self) -> None:
        data = manifest()
        data["tasks"][1]["dependsOn"] = ["P0-999"]  # type: ignore[index]
        data["taskGraphSha256"] = rc.graph_fingerprint(data["tasks"])  # type: ignore[arg-type]
        issues = rc.validate_manifest_data(data, master_text=master_text())
        self.assert_has(issues, "dependency_missing")

    def test_cycle_rejected(self) -> None:
        data = manifest()
        data["tasks"][0]["dependsOn"] = ["P0-002"]  # type: ignore[index]
        data["taskGraphSha256"] = rc.graph_fingerprint(data["tasks"])  # type: ignore[arg-type]
        issues = rc.validate_manifest_data(data)
        self.assert_has(issues, "dependency_cycle")

    def test_invalid_status_rejected(self) -> None:
        data = manifest()
        data["tasks"][1]["status"] = "FINISHED"  # type: ignore[index]
        issues = rc.validate_manifest_data(data)
        self.assert_has(issues, "task_status_invalid")

    def test_ready_requires_done_dependencies(self) -> None:
        data = manifest()
        data["tasks"][0]["status"] = "REVIEW"  # type: ignore[index]
        issues = rc.validate_manifest_data(data)
        self.assert_has(issues, "dependency_not_done")

    def test_done_requires_evidence(self) -> None:
        data = manifest()
        data["tasks"][0]["evidence"] = []  # type: ignore[index]
        issues = rc.validate_manifest_data(data)
        self.assert_has(issues, "evidence_required")

    def test_unsafe_packet_path_rejected(self) -> None:
        data = manifest()
        data["tasks"][1]["packet"] = "../outside.md"  # type: ignore[index]
        issues = rc.validate_manifest_data(data)
        self.assert_has(issues, "task_packet_path")

    def test_status_mismatch_rejected(self) -> None:
        data = manifest()
        status = rc.render_status_text(data).replace("| P0-002 | READY |", "| P0-002 | BLOCKED |")
        issues = rc.validate_manifest_data(data, status_text=status)
        self.assert_has(issues, "status_manifest_conflict")

    def test_master_dependency_conflict_rejected(self) -> None:
        data = manifest()
        data["tasks"][1]["dependsOn"] = []  # type: ignore[index]
        data["taskGraphSha256"] = rc.graph_fingerprint(data["tasks"])  # type: ignore[arg-type]
        issues = rc.validate_manifest_data(data, master_text=master_text())
        self.assert_has(issues, "master_task_conflict")

    def test_master_hash_conflict_rejected(self) -> None:
        data = manifest()
        data["authority"]["masterSha256"] = "0" * 64  # type: ignore[index]
        issues = rc.validate_manifest_data(data, master_text=master_text())
        self.assert_has(issues, "master_hash_conflict")

    def test_conflicting_human_authority_rejected(self) -> None:
        root = self.make_project()
        (root / "docs/roadmap/OTHER.md").write_text("**Roadmap authority:** `HUMAN_CONSTITUTION`\n", encoding="utf-8")
        report = rc.validate_project(root, strict=True)
        self.assertFalse(report["passed"])
        self.assertIn("authority_conflict", {item["code"] for item in report["issues"]})

    def test_next_ready_must_match_statuses(self) -> None:
        data = manifest()
        data["nextReady"] = []
        issues = rc.validate_manifest_data(data)
        self.assert_has(issues, "next_ready_mismatch")

    def test_not_started_with_done_dependencies_must_be_ready(self) -> None:
        data = manifest()
        data["tasks"][1]["status"] = "NOT_STARTED"  # type: ignore[index]
        data["nextReady"] = []
        issues = rc.validate_manifest_data(data, strict=True)
        self.assert_has(issues, "ready_task_not_marked")

    def test_render_is_deterministic(self) -> None:
        data = manifest()
        self.assertEqual(rc.render_status_text(data), rc.render_status_text(copy.deepcopy(data)))
        self.assertEqual(rc.render_handoff_text(data), rc.render_handoff_text(copy.deepcopy(data)))

    def test_graph_fingerprint_changes_with_dependency(self) -> None:
        data = manifest()
        first = data["taskGraphSha256"]
        data["tasks"][1]["dependsOn"] = []  # type: ignore[index]
        second = rc.graph_fingerprint(data["tasks"])  # type: ignore[arg-type]
        self.assertNotEqual(first, second)


if __name__ == "__main__":
    unittest.main(verbosity=2)
