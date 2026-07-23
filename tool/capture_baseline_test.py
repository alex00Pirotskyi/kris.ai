#!/usr/bin/env python3
"""Behavioral tests for the P0-001 baseline capture."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

MODULE_PATH = Path(__file__).with_name("capture_baseline.py")
SPEC = importlib.util.spec_from_file_location("capture_baseline", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
baseline = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = baseline
SPEC.loader.exec_module(baseline)


class BaselineCaptureTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="kristin-baseline-test-")
        self.root = Path(self.temporary.name)
        (self.root / "release/evidence/baseline").mkdir(parents=True)
        self.previous_epoch = os.environ.get("SOURCE_DATE_EPOCH")
        os.environ["SOURCE_DATE_EPOCH"] = "1784764800"

    def tearDown(self) -> None:
        if self.previous_epoch is None:
            os.environ.pop("SOURCE_DATE_EPOCH", None)
        else:
            os.environ["SOURCE_DATE_EPOCH"] = self.previous_epoch
        self.temporary.cleanup()

    def write(self, relative: str, content: str | bytes) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            path.write_bytes(content)
        else:
            path.write_text(content, encoding="utf-8")
        return path

    def observations(self) -> Path:
        payload = {
            "observedAt": "2026-07-23T05:32:17Z",
            "repository": {
                "url": "https://example.invalid/kris.ai",
                "branch": "main",
                "commit": "a" * 40,
                "commitMessage": "fixture",
                "filesChanged": 3,
                "additions": 10,
            },
            "release": {
                "version": "1.9.0+190",
                "classification": "source-release",
                "sourceGatePassed": True,
                "compiledReleaseValidated": False,
            },
            "toolRegistry": {
                "registryVersion": "2.0.0",
                "canonicalToolContractCount": 1,
            },
            "ci": {
                "workflowName": "product-gates",
                "matrix": ["ubuntu-latest"],
                "latestObservedRun": {
                    "id": 1,
                    "conclusion": "failure",
                    "failedStep": "format",
                    "failedCommand": "dart format",
                    "jobs": [],
                },
            },
            "knownBlockers": [],
            "evidenceSources": [],
        }
        return self.write(
            "release/evidence/baseline/observations.json",
            json.dumps(payload, indent=2, sort_keys=True) + "\n",
        )

    def create_manifest(self, paths: list[str]) -> Path:
        lines = []
        for relative in sorted(paths):
            digest = baseline.sha256_file(self.root / relative)
            lines.append(f"{digest}  {relative}\n")
        return self.write("SOURCE_MANIFEST.sha256", "".join(lines))

    def test_manifest_parser_rejects_duplicate_and_traversal(self) -> None:
        duplicate = self.write(
            "duplicate.sha256",
            f"{'0' * 64}  README.md\n{'1' * 64}  README.md\n",
        )
        with self.assertRaises(baseline.BaselineError):
            baseline.parse_source_manifest(duplicate)
        traversal = self.write("traversal.sha256", f"{'0' * 64}  ../secret\n")
        with self.assertRaises(baseline.BaselineError):
            baseline.parse_source_manifest(traversal)

    def test_inventory_counts_schemas_tests_tools_and_ci(self) -> None:
        entries = [
            baseline.ManifestEntry("0" * 64, ".github/workflows/ci.yml"),
            baseline.ManifestEntry("1" * 64, "docs/README.md"),
            baseline.ManifestEntry("2" * 64, "schemas/a.v1.json"),
            baseline.ManifestEntry("3" * 64, "test/a_test.dart"),
            baseline.ManifestEntry("4" * 64, "tool/b_test.py"),
            baseline.ManifestEntry("5" * 64, "tool/run.py"),
        ]
        inventory = baseline.inventory_source_tree(entries)
        self.assertEqual(inventory["entryCount"], 6)
        self.assertEqual(inventory["schemaCount"], 1)
        self.assertEqual(inventory["testAndGateFileCount"], 2)
        self.assertEqual(inventory["toolSourceCount"], 2)
        self.assertEqual(inventory["ciWorkflowCount"], 1)

    def test_source_verification_reports_missing_and_mismatch(self) -> None:
        self.write("good.txt", "good")
        self.write("changed.txt", "changed")
        entries = [
            baseline.ManifestEntry(baseline.sha256_bytes(b"good"), "good.txt"),
            baseline.ManifestEntry(baseline.sha256_bytes(b"expected"), "changed.txt"),
            baseline.ManifestEntry(baseline.sha256_bytes(b"missing"), "missing.txt"),
        ]
        result = baseline.verify_source_manifest(self.root, entries, "verify")
        self.assertEqual(result["status"], baseline.STATUS_FAILED)
        self.assertEqual(result["missing"], ["missing.txt"])
        self.assertEqual(result["mismatched"][0]["path"], "changed.txt")

    def test_snapshot_mode_is_explicitly_unavailable(self) -> None:
        result = baseline.verify_source_manifest(
            self.root,
            [baseline.ManifestEntry("0" * 64, "not-present")],
            "snapshot",
        )
        self.assertEqual(result["status"], baseline.STATUS_UNAVAILABLE)
        self.assertIn("snapshot mode", result["reason"])
        self.assertEqual(result["verifiedCount"], 0)

    def test_redaction_removes_credentials_and_project_path(self) -> None:
        synthetic_key = "sk-" + "abcdefghijklmnopqrstuvwxyz"
        text = (
            f"{self.root}/file Authorization: Bearer abcdef "
            "https://user:pass@example.invalid/x api_key=supersecretvalue "
            + synthetic_key
        )
        safe = baseline.redact(text, self.root)
        self.assertNotIn(str(self.root), safe)
        self.assertNotIn("abcdef", safe)
        self.assertNotIn("user:pass", safe)
        self.assertNotIn("supersecretvalue", safe)
        self.assertNotIn("sk-" + "abcdefghijklmnopqrstuvwxyz", safe)

    def test_local_tool_registry_is_fully_inventoried(self) -> None:
        registry = self.write(
            "schemas/tool_registry.v2.json",
            json.dumps(
                {
                    "registryVersion": "2.0.0",
                    "compatibilityPolicyVersion": "1.0.0",
                    "tools": [
                        {
                            "name": "read_file",
                            "version": "2.0.0",
                            "permission": "projectRead",
                            "risk": "read",
                            "dataBoundary": "project-local",
                            "idempotency": "normalized_arguments",
                        }
                    ],
                }
            ),
        )
        entries = [
            baseline.ManifestEntry(
                baseline.sha256_file(registry), "schemas/tool_registry.v2.json"
            )
        ]
        result = baseline.inspect_tool_registry(self.root, entries)
        self.assertEqual(result["status"], baseline.STATUS_PASSED)
        self.assertEqual(result["toolCount"], 1)
        self.assertEqual(result["tools"][0]["name"], "read_file")

    def test_deterministic_outputs_are_byte_identical(self) -> None:
        self.write("README.md", "fixture\n")
        self.write("schemas/example.v1.json", "{}\n")
        self.write("test/example_test.dart", "void main() {}\n")
        manifest = self.create_manifest(
            ["README.md", "schemas/example.v1.json", "test/example_test.dart"]
        )
        observations = self.observations()
        first = self.root / "out-one"
        second = self.root / "out-two"
        baseline.capture(
            project_root=self.root,
            manifest_path=manifest,
            observations_path=observations,
            output_directory=first,
            manifest_mode="verify",
            run_safe_gates_enabled=False,
        )
        baseline.capture(
            project_root=self.root,
            manifest_path=manifest,
            observations_path=observations,
            output_directory=second,
            manifest_mode="verify",
            run_safe_gates_enabled=False,
        )
        for name in ("baseline.json", "BASELINE.md"):
            self.assertEqual((first / name).read_bytes(), (second / name).read_bytes())
        decoded = json.loads((first / "baseline.json").read_text(encoding="utf-8"))
        self.assertEqual(decoded["sourceTree"]["entryCount"], 3)
        self.assertRegex(decoded["stableFingerprintSha256"], r"^[0-9a-f]{64}$")

    def test_cli_snapshot_capture_succeeds_without_checkout_files(self) -> None:
        self.write("only-manifested-remotely.txt", "not the expected bytes")
        manifest = self.write(
            "SOURCE_MANIFEST.sha256",
            f"{'0' * 64}  absent-upstream-file.txt\n",
        )
        self.observations()
        completed = subprocess.run(
            [
                sys.executable,
                str(MODULE_PATH),
                "--project",
                str(self.root),
                "--manifest-mode",
                "snapshot",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
            env={**os.environ, "SOURCE_DATE_EPOCH": "1784764800"},
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)
        execution = json.loads(
            (self.root / "release/evidence/baseline/execution.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(
            execution["sourceManifestIntegrity"]["status"],
            baseline.STATUS_UNAVAILABLE,
        )
        statuses = {item["name"]: item["status"] for item in execution["gates"]}
        self.assertIn(statuses["flutter_tests"], {baseline.STATUS_UNAVAILABLE, baseline.STATUS_NOT_RUN})


if __name__ == "__main__":
    unittest.main(verbosity=2)
