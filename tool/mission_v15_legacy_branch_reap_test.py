#!/usr/bin/env python3
"""Regressions for bounded Mission v1.5 legacy-debt branch reap commands."""
from __future__ import annotations

import pathlib
import sys
import unittest

THIS = pathlib.Path(__file__).resolve()
TOOL = THIS.parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from mission_v15_legacy_branch_reap import cleanup_class_for, validate_command_shape


class LegacyBranchReapCommandTests(unittest.TestCase):
    def command(self) -> dict[str, object]:
        return {
            "schemaVersion": 1,
            "commandId": "CMD-P6-LEGACY-BRANCH-REAP-47",
            "operation": "DELETE_EXACT_LEGACY_BRANCH_V1",
            "expectedRuntimeGeneration": 47,
            "workOrderId": "WO-P6-001-BRANCH-BUDGET",
            "semaphoreId": "SEM-P6-001-BRANCH-BUDGET",
            "workerIdentity": "ELASTIC-test",
            "productPr": 76,
            "targetBranch": "validation/g-p6-001-85135ef-base",
            "expectedTargetHead": "1" * 40,
        }

    def test_exact_command_passes(self) -> None:
        validate_command_shape(
            self.command(),
            pathlib.Path(
                "docs/roadmap/missions/runtime-commands/CMD-P6-LEGACY-BRANCH-REAP-47.json"
            ),
        )

    def test_unknown_operation_fails(self) -> None:
        value = self.command()
        value["operation"] = "DELETE_ARBITRARY_REF"
        with self.assertRaises(ValueError):
            validate_command_shape(
                value,
                pathlib.Path(
                    "docs/roadmap/missions/runtime-commands/CMD-P6-LEGACY-BRANCH-REAP-47.json"
                ),
            )

    def test_extra_field_fails_closed(self) -> None:
        value = self.command()
        value["force"] = True
        with self.assertRaises(ValueError):
            validate_command_shape(
                value,
                pathlib.Path(
                    "docs/roadmap/missions/runtime-commands/CMD-P6-LEGACY-BRANCH-REAP-47.json"
                ),
            )

    def test_non_legacy_branch_rejected(self) -> None:
        with self.assertRaises(ValueError):
            cleanup_class_for("agent/g/mission-006-model-routing", ["validation/*", "automation/*"])

    def test_validation_branch_maps_to_failure_snapshot(self) -> None:
        self.assertEqual(
            cleanup_class_for("validation/g-p6-001-85135ef-base", ["validation/*"]),
            "failure-snapshot",
        )

    def test_automation_branch_maps_to_superseded_repair(self) -> None:
        self.assertEqual(
            cleanup_class_for("automation/e-p11-old", ["automation/*"]),
            "superseded-repair",
        )

    def test_runtime_tx_requires_exact_grandfathering(self) -> None:
        branch = "runtime/tx/p4-integrate-92-gen1"
        with self.assertRaises(ValueError):
            cleanup_class_for(branch, ["validation/*", "automation/*"])
        self.assertEqual(
            cleanup_class_for(
                branch,
                ["validation/*", "automation/*"],
                [branch],
            ),
            "superseded-repair",
        )
        with self.assertRaises(ValueError):
            cleanup_class_for(
                "runtime/tx/not-grandfathered",
                ["validation/*", "automation/*"],
                [branch],
            )

    def test_relay_uses_branch_hygiene_success_receipt(self) -> None:
        workflow = (
            TOOL.parent / ".github" / "workflows" / "mission-v15-connector-authority-relay.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("receipt.get('status') == 'success'", workflow)
        self.assertNotIn("receipt.get('status') == 'complete'", workflow)


if __name__ == "__main__":
    unittest.main()
