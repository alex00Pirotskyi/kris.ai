#!/usr/bin/env python3

from __future__ import annotations

import ast
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DevEntrypointContractTest(unittest.TestCase):
    def test_run_path_is_fast_and_non_mutating(self) -> None:
        source = (ROOT / "dev.py").read_text(encoding="utf-8")
        module = ast.parse(source)
        run_function = next(
            node
            for node in module.body
            if isinstance(node, ast.FunctionDef) and node.name == "run_app"
        )
        run_source = ast.get_source_segment(source, run_function) or ""
        forbidden = (
            "flutter clean",
            "flutter create",
            "verify.cmd",
            "verify.sh",
            "validate_release",
            "source_manifest",
            "flutter test",
        )
        for token in forbidden:
            self.assertNotIn(token, run_source.lower())

    def test_bootstrap_uses_correct_platform_markers(self) -> None:
        source = (ROOT / "dev.py").read_text(encoding="utf-8")
        self.assertIn('"windows": Path("windows/CMakeLists.txt")', source)
        self.assertIn(
            '"macos": Path("macos/Runner.xcodeproj/project.pbxproj")',
            source,
        )
        self.assertIn('"linux": Path("linux/CMakeLists.txt")', source)

    def test_compatibility_launchers_delegate_to_dev_entrypoint(self) -> None:
        expected = {
            "RUN_WINDOWS.bat": "dev.py run windows",
            "RUN_LINUX.sh": "dev.py run linux",
            "RUN_MAC.command": "dev.py run macos",
            "tool/run_windows.cmd": "dev.py run windows",
        }
        for relative, marker in expected.items():
            content = (ROOT / relative).read_text(encoding="utf-8").lower()
            self.assertIn(marker, content)

    def test_windows_verifier_does_not_format_in_place(self) -> None:
        content = (ROOT / "tool/verify.cmd").read_text(encoding="utf-8").lower()
        self.assertIn("dart_format_scope.py --check", content)
        self.assertNotIn("dart format lib", content)


if __name__ == "__main__":
    unittest.main()
