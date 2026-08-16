#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "tool/v70_package_platform.py"
SPEC = importlib.util.spec_from_file_location("v70_package_platform", PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load platform packager")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

MACHO = bytes.fromhex("cffaedfe") + b"test"


class Result:
    returncode = 0
    stdout = ""
    stderr = ""


class MacosPackagingTest(unittest.TestCase):
    def test_signing_skips_symlinks_and_never_uses_deep_for_signing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / "Kristin.app"
            runtime = app / "Contents/MacOS/runtime/automation_host"
            bin_dir = runtime / "node_modules/.bin"
            bin_dir.mkdir(parents=True)
            node = runtime / "node"
            node.write_bytes(MACHO)
            node.chmod(0o755)
            (bin_dir / "node").symlink_to(Path("../../node"))
            main = app / "Contents/MacOS/Kristin"
            main.parent.mkdir(parents=True, exist_ok=True)
            main.write_bytes(MACHO)
            main.chmod(0o755)
            p1a = root / "p1a-native"
            helper = p1a / "nested/helper"
            helper.parent.mkdir(parents=True)
            helper.write_bytes(MACHO)
            helper.chmod(0o755)
            (p1a / "script.sh").write_text("#!/bin/sh\n", encoding="utf-8")

            calls: list[list[str]] = []
            def fake_run(argv, **kwargs):
                calls.append([str(value) for value in argv])
                return Result()

            with mock.patch.object(MODULE.subprocess, "run", side_effect=fake_run):
                value = MODULE.ad_hoc_sign_macos(app, p1a)
            self.assertEqual(value, "ad-hoc-resigned-after-runtime-staging")
            sign = [row for row in calls if row and row[0] == "codesign" and "--force" in row]
            verify = [row for row in calls if row and row[0] == "codesign" and "--verify" in row]
            self.assertTrue(sign)
            self.assertTrue(verify)
            self.assertTrue(all("--deep" not in row for row in sign))
            self.assertIn(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], verify)
            self.assertEqual(sign[-1][-1], str(app))
            signed_paths = [row[-1] for row in sign[:-1]]
            self.assertNotIn(str(bin_dir / "node"), signed_paths)
            self.assertEqual(signed_paths, [str(path) for path in MODULE.macos_signing_targets(app, p1a)])
            self.assertTrue(all(not Path(path).is_symlink() for path in signed_paths))

    def test_macho_detection_and_launcher_source_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "binary"
            binary.write_bytes(MACHO)
            link = root / "link"
            link.symlink_to(binary.name)
            text = root / "text"
            text.write_text("not macho", encoding="utf-8")
            self.assertTrue(MODULE.is_macho_file(binary))
            self.assertFalse(MODULE.is_macho_file(link))
            self.assertFalse(MODULE.is_macho_file(text))
        source = PATH.read_text(encoding="utf-8")
        self.assertNotIn("codesign --force --deep --sign", source)
        self.assertIn("codesign --verify --deep --strict", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
