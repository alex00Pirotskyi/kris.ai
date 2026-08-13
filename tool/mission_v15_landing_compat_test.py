#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import pathlib
import tempfile
import unittest

import mission_v15_landing_gate_compat as compat


def write_json(path: pathlib.Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


class LandingAuthorityCompatibilityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.project = pathlib.Path(self.temp.name)
        self.request = {
            "schemaVersion": 1,
            "mission": "MISSION-004",
            "task": "P4-001",
            "runtimeGeneration": 564,
            "landingWorkOrderId": "WO-P4-001-CURRENT-MAIN-LANDING-A1B2C3D4",
            "landingSemaphoreId": "SEM-P4-001-SOLO-MAIN-LANDING-38CB129E",
            "productPr": 62,
            "sourceCommit": "4" * 40,
            "sourceTree": "5" * 40,
            "landingBaseCommit": "3" * 40,
        }
        self.semaphore = {
            "schemaVersion": 1,
            "semaphoreId": self.request["landingSemaphoreId"],
            "workOrderId": self.request["landingWorkOrderId"],
            "mission": self.request["mission"],
            "kind": "INTEGRATION",
            "status": "ACTIVE",
            "runtimeGeneration": 564,
            "createdAt": "2026-08-13T10:21:35Z",
            "executionRole": "INTEGRATOR",
            "workerIdentity": "GPT-5.6-PRO-SOLO-38CB129E",
        }
        write_json(
            self.project
            / "runtime"
            / "semaphores"
            / self.request["mission"]
            / f"{self.request['landingSemaphoreId']}.json",
            self.semaphore,
        )
        self.superseded_event = {
            "schemaVersion": 1,
            "eventId": "EVT-OLD-SEMAPHORE_ACQUIRED",
            "eventType": "SEMAPHORE_ACQUIRED",
            "mission": self.request["mission"],
            "workOrderId": self.request["landingWorkOrderId"],
            "runtimeGeneration": 550,
            "recordedAt": "2026-08-13T09:00:00Z",
            "payload": {
                "kind": "INTEGRATION",
                "semaphoreId": "SEM-P4-001-SUPERSEDED",
                "executionRole": "INTEGRATOR",
                "workerIdentity": "OLDER-WORKER",
            },
        }
        self.active_event = {
            "schemaVersion": 1,
            "eventId": "EVT-ACTIVE-SEMAPHORE_ACQUIRED",
            "eventType": "SEMAPHORE_ACQUIRED",
            "mission": self.request["mission"],
            "workOrderId": self.request["landingWorkOrderId"],
            "runtimeGeneration": 561,
            "recordedAt": self.semaphore["createdAt"],
            "payload": {
                "kind": "INTEGRATION",
                "semaphoreId": self.request["landingSemaphoreId"],
                "executionRole": self.semaphore["executionRole"],
                "workerIdentity": self.semaphore["workerIdentity"],
            },
        }
        write_json(
            self.project / "runtime" / "events" / "2026-08-13" / "EVT-OLD.json",
            self.superseded_event,
        )
        write_json(
            self.project / "runtime" / "events" / "2026-08-13" / "EVT-ACTIVE.json",
            self.active_event,
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_exact_active_semaphore_ignores_superseded_acquisitions(self) -> None:
        projected, acquisition_generation = compat._project_authority_event(
            self.project,
            self.request,
        )
        self.assertEqual(projected["eventId"], self.active_event["eventId"])
        self.assertEqual(acquisition_generation, 561)
        self.assertEqual(
            projected["runtimeGeneration"],
            self.request["runtimeGeneration"],
        )
        self.assertEqual(
            projected["payload"]["expectedProductHead"],
            self.request["sourceCommit"],
        )
        self.assertEqual(
            projected["payload"]["canonicalProductTree"],
            self.request["sourceTree"],
        )
        self.assertEqual(
            projected["payload"]["protectedMain"],
            self.request["landingBaseCommit"],
        )
        self.assertEqual(projected["payload"]["productPr"], 62)
        self.assertEqual(projected["payload"]["mergeMethod"], "squash")

    def test_duplicate_exact_semaphore_acquisition_fails_closed(self) -> None:
        duplicate = copy.deepcopy(self.active_event)
        duplicate["eventId"] = "EVT-DUPLICATE-SEMAPHORE_ACQUIRED"
        write_json(
            self.project / "runtime" / "events" / "2026-08-13" / "EVT-DUPLICATE.json",
            duplicate,
        )
        with self.assertRaisesRegex(
            compat.gate.ExactLandingValidationError,
            "found 2",
        ):
            compat._project_authority_event(self.project, self.request)

    def test_future_acquisition_generation_fails_closed(self) -> None:
        future = copy.deepcopy(self.active_event)
        future["runtimeGeneration"] = 565
        write_json(
            self.project / "runtime" / "events" / "2026-08-13" / "EVT-ACTIVE.json",
            future,
        )
        with self.assertRaisesRegex(
            compat.gate.ExactLandingValidationError,
            "cannot exceed",
        ):
            compat._project_authority_event(self.project, self.request)

    def test_conflicting_optional_payload_fails_closed(self) -> None:
        conflicting = copy.deepcopy(self.active_event)
        conflicting["payload"]["productPr"] = 999
        write_json(
            self.project / "runtime" / "events" / "2026-08-13" / "EVT-ACTIVE.json",
            conflicting,
        )
        with self.assertRaisesRegex(
            compat.gate.ExactLandingValidationError,
            "authority productPr",
        ):
            compat._project_authority_event(self.project, self.request)

    def test_acquisition_timestamp_must_bind_semaphore_creation(self) -> None:
        mismatched = copy.deepcopy(self.active_event)
        mismatched["recordedAt"] = "2026-08-13T10:21:36Z"
        write_json(
            self.project / "runtime" / "events" / "2026-08-13" / "EVT-ACTIVE.json",
            mismatched,
        )
        with self.assertRaisesRegex(
            compat.gate.ExactLandingValidationError,
            "authority acquisition timestamp",
        ):
            compat._project_authority_event(self.project, self.request)


if __name__ == "__main__":
    unittest.main()
