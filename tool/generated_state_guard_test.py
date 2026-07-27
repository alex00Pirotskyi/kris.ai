#!/usr/bin/env python3
"""Unit tests for the generated-state Git/source-manifest guard."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

from generated_state_guard import (
    GuardError,
    build_audit,
    build_snapshot,
    safe_relative,
    verify_snapshot,
)
from source_tree_policy import gitignore_block


def run(argv: list[str], cwd: Path) -> None:
    completed = subprocess.run(
        argv,
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise AssertionError(f"{' '.join(argv)} failed:\n{completed.stdout}")


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def remove_tree_portably(path: Path) -> None:
    """Remove a tree even when Windows Git object files are read-only."""

    def make_writable_and_retry(function, target, _exc_info):
        try:
            os.chmod(target, stat.S_IWRITE | stat.S_IREAD | stat.S_IEXEC)
        except OSError:
            pass
        function(target)

    shutil.rmtree(path, onerror=make_writable_and_retry)


def manifest(root: Path, paths: list[str]) -> None:
    import hashlib

    rows = []
    for relative in sorted(paths):
        digest = hashlib.sha256((root / relative).read_bytes()).hexdigest()
        rows.append(f"{digest}  {relative}\n")
    write(root / "SOURCE_MANIFEST.sha256", "".join(rows))


@unittest.skipUnless(shutil.which("git"), "Git is required")
class GeneratedStateGuardTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="p0-010-guard-test-")
        self.root = Path(self.temporary.name)
        run(["git", "init", "-q"], self.root)
        run(["git", "config", "user.email", "fixture@example.invalid"], self.root)
        run(["git", "config", "user.name", "Fixture"], self.root)
        write(self.root / ".gitignore", gitignore_block())
        write(self.root / "lib/source.txt", "source\n")
        write(self.root / ".flutter", "")
        write(self.root / "tool/__pycache__/fixture.pyc", "bytecode")
        manifest(
            self.root,
            [
                ".gitignore",
                ".flutter",
                "lib/source.txt",
                "tool/__pycache__/fixture.pyc",
            ],
        )
        run(["git", "add", "-f", "."], self.root)
        run(["git", "commit", "-qm", "fixture"], self.root)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_audit_detects_tracked_generated_state(self) -> None:
        report = build_audit(self.root)
        self.assertFalse(report["passed"])
        paths = {item["path"] for item in report["trackedGeneratedPresent"]}
        self.assertIn(".flutter", paths)
        self.assertIn("tool/__pycache__/fixture.pyc", paths)

    def test_pending_deletions_are_accepted_after_manifest_cleanup(self) -> None:
        (self.root / ".flutter").unlink()
        shutil.rmtree(self.root / "tool/__pycache__")
        manifest(self.root, [".gitignore", "lib/source.txt"])
        report = build_audit(self.root)
        self.assertTrue(report["passed"])
        pending = {item["path"] for item in report["trackedGeneratedPendingDeletion"]}
        self.assertEqual(pending, {".flutter", "tool/__pycache__/fixture.pyc"})

    def test_generated_outputs_are_ignored(self) -> None:
        for relative in (
            ".flutter_tool_state",
            "tool/__pycache__/new.pyc",
            "playwright-report/index.html",
            "browser-profiles/personal/Cookies",
            "release/SECRET_SCAN.json",
            "reports/kristin-test-system-20260724-010203.json",
        ):
            write(self.root / relative, "generated\n")
        completed = subprocess.run(
            ["git", "ls-files", "--others", "--exclude-standard"],
            cwd=self.root,
            stdout=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(completed.stdout.strip(), "")

    def test_snapshot_ignores_generated_but_detects_source(self) -> None:
        baseline = build_snapshot(self.root)
        write(self.root / "browser-traces/run.zip", "trace")
        same = verify_snapshot(self.root, baseline)
        self.assertTrue(same["passed"])
        write(self.root / "docs/new.md", "source")
        changed = verify_snapshot(self.root, baseline)
        self.assertFalse(changed["passed"])
        self.assertEqual(changed["addedNonGeneratedDirtyPaths"], ["docs/new.md"])

    def test_source_manifest_fallback(self) -> None:
        remove_tree_portably(self.root / ".git")
        (self.root / ".flutter").unlink()
        shutil.rmtree(self.root / "tool/__pycache__")
        manifest(self.root, [".gitignore", "lib/source.txt"])
        report = build_audit(self.root)
        self.assertTrue(report["passed"])
        self.assertEqual(report["trackedAuthority"], "source-manifest")

    def test_safe_relative_rejects_escape_and_absolute(self) -> None:
        for value in (
            "../secret",
            "/tmp/secret",
            r"\tmp\secret",
            "C:/secret",
            r"C:\secret",
            "C:secret",
            r"\\server\share\secret",
        ):
            with self.assertRaises(GuardError):
                safe_relative(value)

    def test_audit_fingerprint_is_stable(self) -> None:
        first = build_audit(self.root)
        second = build_audit(self.root)
        self.assertEqual(first["fingerprint"], second["fingerprint"])
        self.assertEqual(json.dumps(first, sort_keys=True), json.dumps(second, sort_keys=True))

    def test_gitignore_managed_block_is_required(self) -> None:
        write(self.root / ".gitignore", "*.tmp\n")
        report = build_audit(self.root)
        self.assertFalse(report["passed"])
        self.assertFalse(report["gitignoreCoverage"]["exactManagedBlock"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
