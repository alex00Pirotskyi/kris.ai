#!/usr/bin/env python3
"""Regressions for generation-bound connector command envelopes."""
from __future__ import annotations

import pathlib
import sys
import unittest

THIS = pathlib.Path(__file__).resolve()
TOOL = THIS.parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from mission_v15_runtime_atomicity import validate_command_document


class RuntimeCommandEnvelopeTests(unittest.TestCase):
    def command(self, generation: int = 29) -> dict[str, object]:
        return {
            "schemaVersion": 1,
            "commandId": "CMD-P7-RELEASE-29",
            "operation": "UPDATE_RELEASE_VALIDATOR_SOURCE_POLICY_V1",
            "expectedRuntimeGeneration": generation,
            "workOrderId": "WO-P7-001-RELEASE",
            "semaphoreId": "SEM-P7-001-RELEASE",
            "workerIdentity": "ELASTIC-test",
        }

    def test_exact_new_command_for_generation_passes(self) -> None:
        self.assertEqual(
            validate_command_document(
                status="A",
                path="docs/roadmap/missions/runtime-commands/CMD-P7-RELEASE-29.json",
                command=self.command(),
                generation=29,
            ),
            [],
        )

    def test_modified_existing_command_fails(self) -> None:
        violations = validate_command_document(
            status="M",
            path="docs/roadmap/missions/runtime-commands/CMD-P7-RELEASE-29.json",
            command=self.command(),
            generation=29,
        )
        self.assertTrue(any("NOT_IMMUTABLE_ADD" in item for item in violations))

    def test_wrong_generation_fails(self) -> None:
        violations = validate_command_document(
            status="A",
            path="docs/roadmap/missions/runtime-commands/CMD-P7-RELEASE-29.json",
            command=self.command(generation=28),
            generation=29,
        )
        self.assertTrue(any("GENERATION_MISMATCH" in item for item in violations))

    def test_filename_identity_mismatch_fails(self) -> None:
        violations = validate_command_document(
            status="A",
            path="docs/roadmap/missions/runtime-commands/CMD-WRONG.json",
            command=self.command(),
            generation=29,
        )
        self.assertTrue(any("FILENAME_ID_MISMATCH" in item for item in violations))

    def test_missing_operation_and_binding_fields_fail(self) -> None:
        command = self.command()
        command["operation"] = ""
        command["semaphoreId"] = ""
        violations = validate_command_document(
            status="A",
            path="docs/roadmap/missions/runtime-commands/CMD-P7-RELEASE-29.json",
            command=command,
            generation=29,
        )
        self.assertTrue(any("OPERATION_MISSING" in item for item in violations))
        self.assertTrue(any("SEMAPHOREID_MISSING" in item for item in violations))


if __name__ == "__main__":
    unittest.main()
