#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "tool/kris_qwen_control.py"
COMPAT = ROOT / "tool/kris_qwen_control.py.compat.py"
ROTATOR = ROOT / "tool/rotate_kris_qwen_control_token.sh"


def load_compat():
    spec = importlib.util.spec_from_file_location("kris_qwen_control_security_compat", COMPAT)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load Qwen controller compatibility entry")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class ControllerTokenRedactionContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compat = load_compat()

    def test_controller_never_prints_bearer_value(self):
        text = CONTROLLER.read_text(encoding="utf-8")
        self.assertNotIn('PHONE CONTROL TOKEN (keep private):', text)
        self.assertNotIn('controller.token, flush=True', text)
        self.assertIn('token value omitted from logs', text.lower())
        self.assertIn('configured token file', text.lower())

    def test_rotation_helper_never_echoes_token_contents(self):
        text = ROTATOR.read_text(encoding="utf-8")
        self.assertIn('rm -f -- "${TOKEN_FILE}"', text)
        self.assertIn('chmod 600 "${TOKEN_FILE}"', text)
        self.assertNotIn('cat "${TOKEN_FILE}"', text)
        self.assertNotIn('$(<"${TOKEN_FILE}")', text)

    def test_public_peers_are_rejected_and_private_vpn_peers_are_allowed(self):
        allowed = (
            "127.0.0.1",
            "10.42.0.7",
            "172.16.1.8",
            "192.168.20.5",
            "100.100.20.30",
            "::1",
            "fd7a:115c:a1e0::1",
            "fe80::1",
        )
        denied = (
            "8.8.8.8",
            "1.1.1.1",
            "203.0.113.25",
            "2001:4860:4860::8888",
            "not-an-ip",
        )
        for value in allowed:
            with self.subTest(value=value):
                self.assertTrue(self.compat.is_trusted_control_peer(value))
        for value in denied:
            with self.subTest(value=value):
                self.assertFalse(self.compat.is_trusted_control_peer(value))

    def test_phone_url_discovery_never_advertises_public_interfaces(self):
        with mock.patch.object(
            self.compat,
            "_base_discover_phone_urls",
            return_value=[
                "http://10.0.0.8:8090",
                "http://100.90.1.5:8090",
                "http://203.0.113.25:8090",
            ],
        ):
            self.assertEqual(
                self.compat.trusted_discover_phone_urls(8090),
                ["http://10.0.0.8:8090", "http://100.90.1.5:8090"],
            )

    def test_http_handler_is_hardened_for_dashboard_and_api(self):
        self.assertIs(
            self.compat.base.ControlHandler._origin_allowed,
            self.compat._trusted_origin_allowed,
        )
        self.assertIs(
            self.compat.base.ControlHandler.do_GET,
            self.compat._trusted_do_get,
        )
        public_handler = type("Handler", (), {"client_address": ("203.0.113.25", 55000)})()
        private_handler = type("Handler", (), {"client_address": ("100.80.1.2", 55000)})()
        self.assertFalse(self.compat._trusted_peer_allowed(public_handler))
        self.assertTrue(self.compat._trusted_peer_allowed(private_handler))


if __name__ == "__main__":
    unittest.main(verbosity=2)
