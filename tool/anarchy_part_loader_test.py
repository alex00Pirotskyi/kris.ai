#!/usr/bin/env python3
"""Security regressions for the P24 split-source loader and evidence-classification guard."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

MODULE_PATH = Path(__file__).with_name("anarchy_control_plane.py")
SPEC = importlib.util.spec_from_file_location("_p24_security_target", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
acp = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = acp
SPEC.loader.exec_module(acp)


class AnarchyPartLoaderSecurityTest(unittest.TestCase):
    expected = ("part01.inc", "part02.inc")

    def _git(self, root: Path, *args: str) -> None:
        subprocess.run(
            ["git", *args],
            cwd=root,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

    def _repo(self) -> tuple[tempfile.TemporaryDirectory[str], Path, Path]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        tool = root / "tool"
        parts = tool / "parts"
        parts.mkdir(parents=True)
        entry = tool / "entry.py"
        entry.write_text("# synthetic entry\n", encoding="utf-8")
        (parts / "part01.inc").write_text("VALUE = 1\n", encoding="utf-8")
        (parts / "part02.inc").write_text("VALUE += 1\n", encoding="utf-8")
        self._git(root, "init")
        self._git(root, "config", "user.email", "p24-test@example.invalid")
        self._git(root, "config", "user.name", "P24 Test")
        self._git(root, "add", ".")
        self._git(root, "commit", "-m", "fixture")
        return temporary, root, entry

    def _load(self, entry: Path) -> str:
        return acp._load_tracked_parts(entry.as_posix(), "parts", self.expected)

    def test_exact_tracked_allowlist_loads_in_declared_order(self) -> None:
        _, _, entry = self._repo()
        namespace: dict[str, object] = {}
        exec(self._load(entry), namespace, namespace)
        self.assertEqual(namespace["VALUE"], 2)

    def test_untracked_extra_part_is_rejected_before_execution(self) -> None:
        _, root, entry = self._repo()
        sentinel = root / "unexpected-executed"
        extra = root / "tool/parts/part03.inc"
        extra.write_text(
            f"open({str(sentinel)!r}, 'w', encoding='utf-8').write('executed')\n",
            encoding="utf-8",
        )
        with self.assertRaises(acp.PartLoadError):
            source = self._load(entry)
            exec(source, {}, {})
        self.assertFalse(sentinel.exists())

    def test_tracked_extra_part_is_rejected(self) -> None:
        _, root, entry = self._repo()
        (root / "tool/parts/part03.inc").write_text("VALUE = 99\n", encoding="utf-8")
        self._git(root, "add", ".")
        self._git(root, "commit", "-m", "unexpected tracked part")
        with self.assertRaises(acp.PartLoadError):
            self._load(entry)

    def test_untracked_expected_part_is_rejected(self) -> None:
        _, root, entry = self._repo()
        self._git(root, "rm", "--cached", "tool/parts/part02.inc")
        with self.assertRaises(acp.PartLoadError):
            self._load(entry)

    def test_modified_expected_part_is_rejected(self) -> None:
        _, root, entry = self._repo()
        (root / "tool/parts/part01.inc").write_text("VALUE = 7\n", encoding="utf-8")
        with self.assertRaises(acp.PartLoadError):
            self._load(entry)

    def test_missing_expected_part_is_rejected(self) -> None:
        _, root, entry = self._repo()
        (root / "tool/parts/part02.inc").unlink()
        with self.assertRaises(acp.PartLoadError):
            self._load(entry)

    def test_symlinked_expected_part_is_rejected(self) -> None:
        _, root, entry = self._repo()
        target = root / "tool/parts/part02.inc"
        target.unlink()
        try:
            os.symlink("part01.inc", target)
        except (OSError, NotImplementedError) as error:
            self.skipTest(f"symlink creation unavailable: {error}")
        with self.assertRaises(acp.PartLoadError):
            self._load(entry)


class AnarchyEvidenceClassificationSecurityTest(unittest.TestCase):
    def _state(self, record: dict[str, object]) -> object:
        return acp.ValidationState(
            project=MODULE_PATH.parent.parent.resolve(),
            contract={"taskRecords": [record]},
            phases=[],
            tasks={},
            workers={},
            claims=[],
            issues=[],
            blockers=[],
        )

    def _codes(self, record: dict[str, object]) -> set[str]:
        state = self._state(record)
        acp._apply_task_record_evidence_guard(state)
        return {issue.code for issue in state.issues}

    def test_current_low_assurance_vocabulary_remains_valid(self) -> None:
        record = {
            "task": "P24-001",
            "roadmapStatus": "IN_PROGRESS",
            "certificationStatus": "PARTIAL",
            "capabilitySupportStatus": "SOURCE_FOUNDATION",
            "completionClaim": False,
            "evidenceBindings": [
                {"path": "evidence.json", "classification": "SOURCE_ONLY"},
                {"path": "evidence.json", "classification": "HOSTED_CI"},
            ],
        }
        self.assertEqual(self._codes(record), set())

    def test_submitter_defined_measured_classification_is_rejected(self) -> None:
        record = {
            "task": "P24-001",
            "roadmapStatus": "IN_PROGRESS",
            "certificationStatus": "PARTIAL",
            "capabilitySupportStatus": "EXPERIMENTAL",
            "completionClaim": False,
            "evidenceBindings": [
                {"path": "evidence.json", "classification": "MEASURED"},
            ],
        }
        self.assertIn("evidence_classification_invalid", self._codes(record))

    def test_source_evidence_cannot_be_relabelled_into_behavior_support(self) -> None:
        record = {
            "task": "P24-001",
            "roadmapStatus": "IN_PROGRESS",
            "certificationStatus": "PARTIAL",
            "capabilitySupportStatus": "BEHAVIOR_SUPPORTED",
            "completionClaim": False,
            "evidenceBindings": [
                {"path": "evidence.json", "classification": "SOURCE_ONLY"},
            ],
        }
        codes = self._codes(record)
        self.assertIn("evidence_assurance_unavailable", codes)
        self.assertIn("evidence_hash_required", codes)
        self.assertIn("review_binding_required", codes)

    def test_done_pass_stays_fail_closed_even_with_self_declared_measured_evidence(self) -> None:
        record = {
            "task": "P24-001",
            "roadmapStatus": "DONE",
            "certificationStatus": "PASS",
            "capabilitySupportStatus": "RELEASE_SUPPORTED",
            "completionClaim": True,
            "evidenceBindings": [
                {
                    "path": "evidence.json",
                    "classification": "MEASURED",
                    "sha256": "a" * 64,
                },
            ],
            "reviewBinding": {
                "commit": "b" * 40,
                "tree": "c" * 40,
                "decision": "PASS",
            },
        }
        codes = self._codes(record)
        self.assertIn("evidence_classification_invalid", codes)
        self.assertIn("evidence_assurance_unavailable", codes)
        self.assertIn("review_binding_stale", codes)


if __name__ == "__main__":
    unittest.main()
