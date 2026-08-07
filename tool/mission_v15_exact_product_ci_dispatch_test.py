#!/usr/bin/env python3
"""Regressions for bounded exact Product PR CI dispatch commands."""
from __future__ import annotations

import pathlib
import sys
import unittest

THIS = pathlib.Path(__file__).resolve()
TOOL = THIS.parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from mission_v15_exact_product_ci_dispatch import validate_command_shape


class ExactProductCiDispatchCommandTests(unittest.TestCase):
    def command(self, generation: int = 38) -> dict[str, object]:
        return {
            "schemaVersion": 1,
            "commandId": "CMD-P7-EXACT-PRODUCT-CI-38",
            "operation": "DISPATCH_EXACT_PRODUCT_GATES_V1",
            "expectedRuntimeGeneration": generation,
            "workOrderId": "WO-P7-001-EXACT-PRODUCT-CI",
            "semaphoreId": "SEM-P7-001-EXACT-PRODUCT-CI",
            "workerIdentity": "ELASTIC-test",
            "productPr": 96,
            "expectedProductHead": "1" * 40,
        }

    def test_exact_command_passes(self) -> None:
        validate_command_shape(
            self.command(),
            pathlib.Path(
                "docs/roadmap/missions/runtime-commands/CMD-P7-EXACT-PRODUCT-CI-38.json"
            ),
        )

    def test_wrong_operation_fails(self) -> None:
        command = self.command()
        command["operation"] = "ARBITRARY_COMMAND"
        with self.assertRaises(ValueError):
            validate_command_shape(
                command,
                pathlib.Path(
                    "docs/roadmap/missions/runtime-commands/CMD-P7-EXACT-PRODUCT-CI-38.json"
                ),
            )

    def test_filename_identity_mismatch_fails(self) -> None:
        with self.assertRaises(ValueError):
            validate_command_shape(
                self.command(),
                pathlib.Path("docs/roadmap/missions/runtime-commands/CMD-WRONG.json"),
            )

    def test_wrong_generation_shape_fails(self) -> None:
        command = self.command()
        command["expectedRuntimeGeneration"] = "38"
        with self.assertRaises(ValueError):
            validate_command_shape(
                command,
                pathlib.Path(
                    "docs/roadmap/missions/runtime-commands/CMD-P7-EXACT-PRODUCT-CI-38.json"
                ),
            )

    def test_invalid_product_head_fails(self) -> None:
        command = self.command()
        command["expectedProductHead"] = "not-a-git-sha"
        with self.assertRaises(ValueError):
            validate_command_shape(
                command,
                pathlib.Path(
                    "docs/roadmap/missions/runtime-commands/CMD-P7-EXACT-PRODUCT-CI-38.json"
                ),
            )

    def test_extra_field_fails_closed(self) -> None:
        command = self.command()
        command["shell"] = "rm -rf /"
        with self.assertRaises(ValueError):
            validate_command_shape(
                command,
                pathlib.Path(
                    "docs/roadmap/missions/runtime-commands/CMD-P7-EXACT-PRODUCT-CI-38.json"
                ),
            )


if __name__ == "__main__":
    unittest.main()
