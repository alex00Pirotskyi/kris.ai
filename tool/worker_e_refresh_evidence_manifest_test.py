#!/usr/bin/env python3
"""Regression tests for the deterministic Worker E evidence-manifest refresher."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tool" / "worker_e_refresh_evidence_manifest.py"
SPEC = importlib.util.spec_from_file_location("worker_e_refresh_evidence_manifest", MODULE_PATH)
assert SPEC and SPEC.loader
refresh = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = refresh
SPEC.loader.exec_module(refresh)


class WorkerEEvidenceManifestRefreshTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="worker-e-evidence-manifest-")
        self.project = Path(self.temp.name)
        manifest_path = self.project / refresh.MANIFEST
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(
            json.dumps(
                {
                    "schemaVersion": "1.0.0",
                    "recordType": "WorkerENativeReadinessManifest",
                    "artifacts": [],
                },
                sort_keys=True,
                separators=(",", ":"),
            )
            + "\n",
            encoding="utf-8",
        )
        for index, relative in enumerate(refresh.REQUIRED_ARTIFACTS):
            path = self.project / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"fixture-{index}\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_write_is_deterministic_and_idempotent(self) -> None:
        first = refresh.write(self.project)
        first_bytes = (self.project / refresh.MANIFEST).read_bytes()
        second = refresh.write(self.project)
        self.assertTrue(first["changed"])
        self.assertFalse(second["changed"])
        self.assertEqual(first_bytes, (self.project / refresh.MANIFEST).read_bytes())
        self.assertEqual(len(refresh.REQUIRED_ARTIFACTS), second["artifactCount"])

    def test_check_rejects_artifact_drift(self) -> None:
        refresh.write(self.project)
        path = self.project / refresh.REQUIRED_ARTIFACTS[0]
        path.write_text("changed\n", encoding="utf-8")
        with self.assertRaisesRegex(refresh.ManifestError, "stale"):
            refresh.check(self.project)

    def test_missing_required_artifact_fails_closed(self) -> None:
        missing = self.project / refresh.REQUIRED_ARTIFACTS[-1]
        missing.unlink()
        with self.assertRaisesRegex(refresh.ManifestError, "does not exist"):
            refresh.expected_manifest(self.project)

    def test_duplicate_artifact_path_fails_closed(self) -> None:
        manifest_path = self.project / refresh.MANIFEST
        value = json.loads(manifest_path.read_text(encoding="utf-8"))
        value["artifacts"] = [
            {"path": refresh.REQUIRED_ARTIFACTS[0]},
            {"path": refresh.REQUIRED_ARTIFACTS[0]},
        ]
        manifest_path.write_text(json.dumps(value) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(refresh.ManifestError, "duplicate artifact path"):
            refresh.expected_manifest(self.project)


if __name__ == "__main__":
    unittest.main()
