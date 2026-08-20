#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import importlib.util
import io
import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SECURE = ROOT / "tool/kris_qwen_control_secure.py"


def load_secure():
    spec = importlib.util.spec_from_file_location("kris_qwen_control_secure_test_module", SECURE)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load secure controller")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class SecureControllerTest(unittest.TestCase):
    def test_sensitive_phone_token_print_is_redacted(self):
        module = load_secure()
        output = io.StringIO()
        secret = "unit-test-secret-that-must-never-appear"
        with contextlib.redirect_stdout(output):
            module.safe_controller_print("PHONE CONTROL TOKEN (keep private):", secret, flush=True)
        text = output.getvalue()
        self.assertNotIn(secret, text)
        self.assertIn("omitted from logs", text)

    def test_normal_controller_output_is_preserved(self):
        module = load_secure()
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            module.safe_controller_print("controller-ready", flush=True)
        self.assertIn("controller-ready", output.getvalue())

    def test_secure_controller_reports_221(self):
        result = subprocess.run(
            [sys.executable, str(SECURE), "--version"],
            cwd=ROOT,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        self.assertEqual(result.stdout.strip(), "2.2.1")


if __name__ == "__main__":
    unittest.main(verbosity=2)
