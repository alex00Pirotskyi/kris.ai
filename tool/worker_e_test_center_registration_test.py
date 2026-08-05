#!/usr/bin/env python3
"""Atomicity and idempotence regressions for Worker E Test Center registration."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tool" / "worker_e_test_center_registration.py"
SPEC = importlib.util.spec_from_file_location("worker_e_test_center_registration", MODULE_PATH)
assert SPEC and SPEC.loader
registration = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = registration
SPEC.loader.exec_module(registration)

INDEX_PATHS = (
    Path("release/evidence/P11-001/native-capability-inventory.json"),
    Path("release/evidence/P11-001/platform-gap-matrix.json"),
    Path("release/evidence/P11-001/conformance-fixture-catalog.json"),
    Path("release/evidence/P11-001/isolation-readiness.json"),
)


class WorkerETestCenterRegistrationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="worker-e-registration-")
        self.project = Path(self.temp.name)
        for relative in (registration.REGISTRY, *INDEX_PATHS):
            source = ROOT / relative
            target = self.project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def base_registry_bytes(self) -> bytes:
        path = self.project / registration.REGISTRY
        data = json.loads(path.read_text(encoding="utf-8"))
        data["testModules"] = [
            row for row in data["testModules"] if row.get("moduleId") != registration.MODULE_ID
        ]
        data["testCases"] = [
            row for row in data["testCases"] if row.get("moduleId") != registration.MODULE_ID
        ]
        data["projectTestProfiles"] = [
            row
            for row in data["projectTestProfiles"]
            if not row.get("stableCheckId", "").startswith("tc.p11.readiness.")
        ]
        data["affectedTestMappings"] = [
            row
            for row in data["affectedTestMappings"]
            if not row.get("mappingId", "").startswith("affected.p11-readiness")
        ]
        return registration.canonical_bytes(data)

    def test_registration_is_deterministic_and_idempotent(self) -> None:
        path = self.project / registration.REGISTRY
        expected = path.read_bytes()
        path.write_bytes(self.base_registry_bytes())
        first = registration.register(self.project)
        first_bytes = path.read_bytes()
        second = registration.register(self.project)
        self.assertTrue(first["changed"])
        self.assertFalse(second["changed"])
        self.assertEqual(expected, first_bytes)
        self.assertEqual(first_bytes, path.read_bytes())

    def test_replace_failure_preserves_original(self) -> None:
        path = self.project / registration.REGISTRY
        path.write_bytes(self.base_registry_bytes())
        before = path.read_bytes()
        with mock.patch.object(registration.os, "replace", side_effect=OSError("injected")):
            with self.assertRaisesRegex(OSError, "injected"):
                registration.register(self.project)
        self.assertEqual(before, path.read_bytes())


if __name__ == "__main__":
    unittest.main()
