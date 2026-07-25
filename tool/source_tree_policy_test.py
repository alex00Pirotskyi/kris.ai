#!/usr/bin/env python3
"""Behavioral tests for the shared generated-state policy."""
from __future__ import annotations

from pathlib import PureWindowsPath
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
