#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import pathlib
import sys
import threading
import time

SOURCE = pathlib.Path(__file__).with_name("kris_qwen_control.py")
TARGET_CONTROL_VERSION = "2.2.0"


def load_base():
    spec = importlib.util.spec_from_file_location("kris_qwen_control_base", SOURCE)
    if spec is None or spec.loader is None:
        raise SystemExit("KRIS_QWEN_CONTROL_COMPAT_ERROR: cannot load base controller")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


base = load_base()
base.CONTROL_VERSION = TARGET_CONTROL_VERSION
BaseController = base.QwenController


def always_on_worker_pid(pid: int | None) -> bool:
    if not base.pid_alive(pid):
        return False
    cmd = base.process_cmdline(int(pid)).lower()
    if "python" not in cmd:
        return False
    return any(
        marker in cmd
        for marker in (
            "kris_qwen_worker.py",
            "kris_qwen_worker_v53.py",
        )
    )


base.is_qwen_worker_pid = always_on_worker_pid
base.ControlHandler.server_version = "KrisQwenControl/2.2"


class AlwaysOnQwenController(BaseController):
    def __init__(self, cfg):
        super().__init__(cfg)
        self.auto_run_enabled = True
        self.auto_update_enabled = base.env_bool("KRIS_QWEN_AUTO_UPDATE", True)
        try:
            interval = int(os.environ.get("KRIS_QWEN_AUTO_UPDATE_SECONDS", "30"))
        except ValueError as exc:
            raise base.ControllerError("KRIS_QWEN_AUTO_UPDATE_SECONDS must be an integer") from exc
        self.auto_update_seconds = max(10, interval)
        self.auto_update_thread = None
        if self.auto_update_enabled:
            self.auto_update_thread = threading.Thread(
                target=self._auto_update_loop,
                name="kris-qwen-auto-update",
                daemon=True,
            )
            self.auto_update_thread.start()

    def start(self):
        self.auto_run_enabled = True
        return super().start()

    def request_safe_stop(self, reason: str = "Qwen phone control safe stop"):
        if reason == "Qwen phone control safe stop":
            self.auto_run_enabled = False
        return super().request_safe_stop(reason)

    def fetch_latest_and_run(self):
        self.auto_run_enabled = True
        return super().fetch_latest_and_run()

    def _remote_branch_head(self) -> str:
        result = self._git(
            "ls-remote",
            "--heads",
            "origin",
            f"refs/heads/{self.cfg.repo_branch}",
            timeout=120,
        )
        rows = [line.split() for line in result.stdout.splitlines() if line.strip()]
        if len(rows) != 1 or len(rows[0]) < 2:
            raise base.ControllerError(
                f"cannot resolve unique remote head for {self.cfg.repo_branch}"
            )
        head = rows[0][0]
        if len(head) != 40:
            raise base.ControllerError("remote Qwen branch returned invalid head SHA")
        return head

    def _auto_update_once(self) -> dict:
        if self.operation_running():
            return {"status": "BUSY"}
        if not self.auto_run_enabled:
            return {"status": "PAUSED"}
        self._validate_repo()
        local = self._git_head()
        remote = self._remote_branch_head()
        if remote != local:
            queued = super().fetch_latest_and_run()
            return {
                **queued,
                "status": "UPDATE_QUEUED",
                "local": local,
                "remote": remote,
            }
        if not self.worker_pid():
            started = super().start()
            return {
                "status": "AUTO_STARTED",
                "local": local,
                "remote": remote,
                "worker": started,
            }
        return {"status": "CURRENT", "local": local, "remote": remote}

    def _auto_update_loop(self) -> None:
        time.sleep(1.0)
        while True:
            try:
                self._auto_update_once()
            except Exception as exc:
                if not self.operation_running():
                    self._record_operation(
                        state="ERROR",
                        kind="AUTO_UPDATE",
                        error=str(exc),
                    )
            time.sleep(self.auto_update_seconds)

    def status(self):
        result = super().status()
        result["controllerVersion"] = TARGET_CONTROL_VERSION
        result["autoUpdate"] = {
            "enabled": self.auto_update_enabled,
            "intervalSeconds": self.auto_update_seconds,
            "autoRunEnabled": self.auto_run_enabled,
        }
        return result


base.QwenController = AlwaysOnQwenController


def main() -> int:
    return base.main()


if __name__ == "__main__":
    raise SystemExit(main())
