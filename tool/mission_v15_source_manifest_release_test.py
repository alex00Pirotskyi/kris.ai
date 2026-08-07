#!/usr/bin/env python3
"""Regressions for the exact source-manifest RELEASE command envelope."""
from __future__ import annotations

import pathlib
import sys
import unittest

THIS = pathlib.Path(__file__).resolve()
TOOL = THIS.parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from mission_v15_source_manifest_release_apply import validate_command_shape


class SourceManifestReleaseCommandTests(unittest.TestCase):
    def command(self) -> dict[str, object]:
        return {
            "schemaVersion": 1,
            "commandId": "CMD-P7-SOURCE-MANIFEST-34",
            "operation": "MATERIALIZE_SOURCE_MANIFEST_V1",
            "expectedRuntimeGeneration": 34,
            "workOrderId": "WO-P7-001-SOURCE-MANIFEST",
            "semaphoreId": "SEM-P7-001-SOURCE-MANIFEST",
            "workerIdentity": "ELASTIC-test",
            "productPr": 96,
            "expectedProductHead": "1" * 40,
        }

    def test_exact_command_passes(self) -> None:
        validate_command_shape(
            self.command(),
            pathlib.Path("docs/roadmap/missions/runtime-commands/CMD-P7-SOURCE-MANIFEST-34.json"),
        )

    def test_filename_identity_mismatch_fails(self) -> None:
        with self.assertRaises(ValueError):
            validate_command_shape(
                self.command(),
                pathlib.Path("docs/roadmap/missions/runtime-commands/CMD-WRONG.json"),
            )

    def test_wrong_operation_fails(self) -> None:
        command = self.command()
        command["operation"] = "SHELL"
        with self.assertRaises(ValueError):
            validate_command_shape(
                command,
                pathlib.Path("docs/roadmap/missions/runtime-commands/CMD-P7-SOURCE-MANIFEST-34.json"),
            )

    def test_short_product_head_fails(self) -> None:
        command = self.command()
        command["expectedProductHead"] = "1234"
        with self.assertRaises(ValueError):
            validate_command_shape(
                command,
                pathlib.Path("docs/roadmap/missions/runtime-commands/CMD-P7-SOURCE-MANIFEST-34.json"),
            )

    def test_unknown_field_fails(self) -> None:
        command = self.command()
        command["shell"] = "rm -rf /"
        with self.assertRaises(ValueError):
            validate_command_shape(
                command,
                pathlib.Path("docs/roadmap/missions/runtime-commands/CMD-P7-SOURCE-MANIFEST-34.json"),
            )


if __name__ == "__main__":
    unittest.main()
