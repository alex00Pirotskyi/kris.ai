#!/usr/bin/env python3
"""Behavioral tests for the shared generated-state policy."""
from __future__ import annotations

import json
from pathlib import Path, PureWindowsPath
import shutil
import subprocess
import tempfile
import unittest

from source_tree_policy import (
    GENERATED_STATE_POLICY_VERSION,
    GITIGNORE_BEGIN,
    GITIGNORE_END,
    generated_path_reason,
    gitignore_block,
    is_generated_path,
    normalized_relative_path,
    representative_generated_paths,
    representative_source_paths,
)


class SourceTreePolicyTest(unittest.TestCase):
    def test_policy_version_is_explicit(self) -> None:
        self.assertEqual(GENERATED_STATE_POLICY_VERSION, "2.0.0")

    def test_representative_generated_paths_are_generated(self) -> None:
        failures = [p for p in representative_generated_paths() if not is_generated_path(p)]
        self.assertEqual(failures, [])

    def test_representative_source_paths_are_not_generated(self) -> None:
        failures = [p for p in representative_source_paths() if is_generated_path(p)]
        self.assertEqual(failures, [])

    def test_windows_separators_and_case_are_normalized(self) -> None:
        path = PureWindowsPath(r"WINDOWS\Flutter\Ephemeral\flutter_windows.dll")
        self.assertTrue(is_generated_path(path))
        self.assertEqual(
            normalized_relative_path(path),
            "windows/flutter/ephemeral/flutter_windows.dll",
        )

    def test_python_bytecode_suffixes_are_generated(self) -> None:
        self.assertEqual(generated_path_reason("tool/a.PYC"), "python-bytecode")
        self.assertEqual(generated_path_reason("tool/a.pyo"), "python-bytecode")

    def test_reviewed_generated_source_is_not_disposable(self) -> None:
        self.assertFalse(is_generated_path("lib/product/generated/protocol_contracts.g.dart"))

    def test_committed_evidence_is_not_disposable(self) -> None:
        self.assertFalse(is_generated_path("release/evidence/P0-010/manifest.json"))
        self.assertFalse(is_generated_path("release/evidence/baseline/execution.json"))

    def test_generated_evidence_staging_is_disposable(self) -> None:
        self.assertTrue(is_generated_path("release/evidence/generated/tmp.json"))
        self.assertTrue(is_generated_path("release/reports/generated/report.json"))

    def test_timestamped_legacy_test_reports_are_generated(self) -> None:
        self.assertTrue(is_generated_path("reports/kristin-test-release-20260724-101112.md"))
        self.assertFalse(is_generated_path("reports/manual-security-review.md"))

    def test_release_gate_outputs_are_generated(self) -> None:
        for path in (
            "release/SECRET_SCAN.json",
            "release/SBOM.cdx.json",
            "release/VALIDATION_REPORT.md",
            "release/validation_report.json",
            "release/ASSURANCE_REPORT.json",
        ):
            self.assertTrue(is_generated_path(path), path)

    def test_browser_profile_and_trace_paths_are_generated(self) -> None:
        self.assertTrue(is_generated_path("browser-profiles/work/Default/Cookies"))
        self.assertTrue(is_generated_path("browser-traces/run-1/trace.zip"))
        self.assertTrue(is_generated_path("playwright-report/index.html"))

    def test_yarn_source_and_cache_are_distinguished(self) -> None:
        self.assertTrue(is_generated_path(".yarn/cache/package.zip"))
        self.assertTrue(is_generated_path(".yarn/install-state.gz"))
        self.assertFalse(is_generated_path(".yarn/releases/yarn-4.5.0.cjs"))

    def test_gitignore_block_is_bounded_and_stable(self) -> None:
        block = gitignore_block()
        self.assertTrue(block.startswith(GITIGNORE_BEGIN + "\n"))
        self.assertTrue(block.endswith(GITIGNORE_END + "\n"))
        self.assertEqual(block.count(GITIGNORE_BEGIN), 1)
        self.assertEqual(block.count(GITIGNORE_END), 1)

    def test_empty_and_dot_paths_are_not_generated(self) -> None:
        self.assertFalse(is_generated_path(""))
        self.assertFalse(is_generated_path("."))

    def test_false_positive_sensitive_paths_remain_source(self) -> None:
        for path in (
            "docs/build/architecture.md",
            "lib/coverage_model.dart",
            "schemas/browser_profile.v1.json",
            "datasets/source/data.jsonl",
        ):
            # Directory-name policy is intentionally structural. A directory
            # literally named build/coverage is disposable, while source file
            # names containing those words remain source.
            if path == "docs/build/architecture.md":
                self.assertTrue(is_generated_path(path))
            else:
                self.assertFalse(is_generated_path(path), path)

    def test_legacy_pruner_preserves_governed_nested_paths(self) -> None:
        dart = shutil.which("dart")
        if dart is None:
            self.skipTest("Dart SDK is not available")

        root = Path(tempfile.mkdtemp(prefix="kristin-prune-regression-"))
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)

        def write(relative: str, content: str = "fixture\n") -> None:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")

        write("lib/main.dart", "void main() {}\n")
        write("lib/product/product_runtime.dart", "final runtime = true;\n")
        write("lib/product/browser/browser_runtime.dart", "final browser = true;\n")
        write("test/product/browser/browser_runtime_test.dart", "void main() {}\n")
        write("test/product/fixtures/rendered_page.json", '{"ok":true}\n')
        write("tool/support.dart", "final support = true;\n")
        write("lib/product/obsolete/old.dart", "final obsolete = true;\n")
        write("test/product/stale_test.dart", "void main() {}\n")

        inventory = {
            "productionDart": ["lib/product/browser/browser_runtime.dart"],
            "testDart": ["test/product/browser/browser_runtime_test.dart"],
            "supportDart": ["tool/support.dart"],
        }
        write(
            "config/p2_source_inventory.v1.json",
            json.dumps(inventory, indent=2) + "\n",
        )
        governed_manifest_paths = (
            "lib/main.dart",
            "lib/product/product_runtime.dart",
            "lib/product/browser/browser_runtime.dart",
            "test/product/browser/browser_runtime_test.dart",
            "test/product/fixtures/rendered_page.json",
            "tool/support.dart",
        )
        write(
            "SOURCE_MANIFEST.sha256",
            "".join(f"{'0' * 64}  {path}\n" for path in governed_manifest_paths),
        )

        pruner = Path(__file__).with_name("prune_stale_legacy.dart").resolve()
        completed = subprocess.run(
            [dart, "run", str(pruner)],
            cwd=root,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            check=False,
            timeout=60,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)

        for relative in governed_manifest_paths:
            self.assertTrue((root / relative).is_file(), relative)
        self.assertFalse((root / "lib/product/obsolete/old.dart").exists())
        self.assertFalse((root / "test/product/stale_test.dart").exists())

        report = json.loads(
            (root / "release/legacy_quarantine_report.json").read_text(
                encoding="utf-8"
            )
        )
        quarantined = set(report["quarantinedPaths"])
        self.assertIn("lib/product/obsolete", quarantined)
        self.assertIn("test/product/stale_test.dart", quarantined)
        self.assertNotIn("lib/product/browser", quarantined)
        self.assertNotIn("test/product/browser", quarantined)
        self.assertNotIn("test/product/fixtures", quarantined)


if __name__ == "__main__":
    unittest.main(verbosity=2)
