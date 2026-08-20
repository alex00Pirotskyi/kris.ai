#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "tool/kris_qwen_control.py"
ROTATOR = ROOT / "tool/rotate_kris_qwen_control_token.sh"


class ControllerTokenRedactionContractTest(unittest.TestCase):
    def test_controller_never_prints_bearer_value(self):
        text = CONTROLLER.read_text(encoding="utf-8")
        self.assertNotIn('PHONE CONTROL TOKEN (keep private):', text)
        self.assertNotIn('controller.token, flush=True', text)
        self.assertIn('token value omitted from logs', text.lower())
        self.assertIn('controller.token_path', text)

    def test_rotation_helper_never_echoes_token_contents(self):
        text = ROTATOR.read_text(encoding="utf-8")
        self.assertIn('rm -f -- "${TOKEN_FILE}"', text)
        self.assertIn('chmod 600 "${TOKEN_FILE}"', text)
        self.assertNotIn('cat "${TOKEN_FILE}"', text)
        self.assertNotIn('$(<"${TOKEN_FILE}")', text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
