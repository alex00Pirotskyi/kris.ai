#!/usr/bin/env python3
"""Behavioral tests for the local KRIS Qwen worker controller."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

HERE = Path(__file__).resolve().parent
CONTROL = HERE / "kris_qwen_control.py"
INSTALLER = HERE / "install_kris_qwen_control_systemd.sh"

spec = importlib.util.spec_from_file_location("kris_qwen_control", CONTROL)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)
ControllerConfig = mod.ControllerConfig
QwenController = mod.QwenController


FAKE_WORKER = r'''#!/usr/bin/env python3
import json, os, pathlib, sys, time

def root_arg():
    i = sys.argv.index("--root")
    return pathlib.Path(sys.argv[i + 1]).expanduser().resolve()

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value) + "\n")

cmd = sys.argv[1]
if cmd == "version":
    print(json.dumps({"scriptVersion":"test"}))
    raise SystemExit(0)
root = root_arg()
op = root / "operator"
stop = op / "stop-request.json"
status = op / "status.json"
if cmd == "control":
    action = sys.argv[2]
    if action == "clear":
        stop.unlink(missing_ok=True)
        raise SystemExit(0)
    if action == "stop":
        write(stop, {"mode":"GRACEFUL", "reason":"test"})
        raise SystemExit(0)
    raise SystemExit(2)
if cmd == "stack":
    write(status, {"pid":os.getpid(), "state":"IDLE", "scriptVersion":"test"})
    while not stop.exists():
        time.sleep(0.05)
    write(status, {"pid":os.getpid(), "state":"STOPPED", "scriptVersion":"test"})
    stop.unlink(missing_ok=True)
    raise SystemExit(0)
raise SystemExit(2)
'''


class ControllerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-b", "main"], cwd=self.repo, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=self.repo, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=self.repo, check=True)
        tool = self.repo / "tool"
        tool.mkdir()
        self.worker = tool / "kris_qwen_worker.py"
        self.worker.write_text(FAKE_WORKER, encoding="utf-8")
        (self.repo / "README.md").write_text("fixture\n", encoding="utf-8")
        subprocess.run(["git", "add", "."], cwd=self.repo, check=True)
        subprocess.run(["git", "commit", "-m", "fixture"], cwd=self.repo, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.worker_root = self.root / "worker-root"
        self.state_dir = self.root / "control-state"
        self.cfg = ControllerConfig(
            repo_dir=self.repo,
            branch="main",
            python_executable=sys.executable,
            worker_script=self.worker,
            worker_root=self.worker_root,
            state_dir=self.state_dir,
            host="127.0.0.1",
            port=0,
            stop_timeout=5,
            worker_extra_args=(),
        )
        self.controller = QwenController(self.cfg)

    def tearDown(self) -> None:
        pid = self.controller.worker_pid()
        if pid:
            try:
                self.controller.request_graceful_stop("test cleanup")
            except Exception:
                pass
            deadline = time.time() + 2
            while time.time() < deadline and mod.pid_alive(pid):
                time.sleep(0.05)
            if mod.pid_alive(pid):
                os.kill(pid, 9)
        self.temp.cleanup()

    def test_worker_command_uses_stack(self) -> None:
        command = self.controller._worker_command()
        self.assertIn("stack", command)
        self.assertNotIn("serve", command)
        self.assertEqual(command[1], str(self.worker))

    def test_start_and_safe_stop_use_worker_protocol(self) -> None:
        started = self.controller.start_worker()
        self.assertEqual(started["status"], "STARTED")
        pid = int(started["pid"])
        deadline = time.time() + 2
        while time.time() < deadline and not self.controller.operator_status_path.exists():
            time.sleep(0.02)
        self.assertTrue(mod.pid_alive(pid))
        stopped = self.controller.request_graceful_stop("unit test")
        self.assertEqual(stopped["status"], "STOP_REQUESTED")
        deadline = time.time() + 3
        while time.time() < deadline and mod.pid_alive(pid):
            time.sleep(0.05)
        self.assertFalse(mod.pid_alive(pid))

    def test_refresh_refuses_dirty_checkout_before_fetch(self) -> None:
        (self.repo / "dirty.txt").write_text("do not destroy\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "checkout is dirty"):
            self.controller._refresh_repo_fast_forward()
        self.assertTrue((self.repo / "dirty.txt").exists())

    def test_non_loopback_listener_is_rejected(self) -> None:
        cfg = ControllerConfig(**{**self.cfg.__dict__, "host": "0.0.0.0"})
        with self.assertRaisesRegex(RuntimeError, "non-loopback"):
            QwenController(cfg)

    def test_control_token_is_required(self) -> None:
        self.assertFalse(self.controller.verify_token(None))
        self.assertFalse(self.controller.verify_token("wrong"))
        token = self.controller.token_path.read_text(encoding="utf-8").strip()
        self.assertTrue(self.controller.verify_token(token))

    def test_systemd_installer_pins_root_gh_credential_store(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        self.assertIn("Environment=HOME=/root", installer)
        self.assertIn("Environment=GH_CONFIG_DIR=/root/.config/gh", installer)
        self.assertIn("Environment=GIT_TERMINAL_PROMPT=0", installer)
        self.assertIn(
            "HOME=/root GH_CONFIG_DIR=/root/.config/gh gh auth status --hostname github.com",
            installer,
        )
        self.assertIn(
            "HOME=/root GH_CONFIG_DIR=/root/.config/gh gh auth setup-git --hostname github.com",
            installer,
        )


if __name__ == "__main__":
    unittest.main()
