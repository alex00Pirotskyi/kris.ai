#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
ENTRY = HERE / "kris_qwen_control.py.compat.py"
spec = importlib.util.spec_from_file_location("kris_qwen_control_compat_tested", ENTRY)
assert spec is not None and spec.loader is not None
control = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = control
spec.loader.exec_module(control)


def config(root: pathlib.Path):
    repo = root / "repo"
    repo.mkdir()
    (repo / ".git").mkdir()
    worker = repo / "tool" / "kris_qwen_worker_v53.py"
    worker.parent.mkdir()
    worker.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
    return control.base.ControlConfig(
        repo_dir=repo,
        repo_branch="agent/qwen-phone-control",
        python=sys.executable,
        worker_script=worker,
        worker_root=root / "worker",
        state_dir=root / "worker/controller",
        host="127.0.0.1",
        port=8090,
        allow_remote_http=False,
        stop_timeout=30,
        worker_extra_args=(),
    )


class WorkerPidCompatibilityTest(unittest.TestCase):
    def test_v53_entry_is_recognized_as_qwen_worker(self) -> None:
        with mock.patch.object(control.base, "pid_alive", return_value=True), mock.patch.object(
            control.base,
            "process_cmdline",
            return_value="python3 /repo/tool/kris_qwen_worker_v53.py stack --root /tmp/qwen",
        ):
            self.assertTrue(control.always_on_worker_pid(1234))

    def test_unrelated_python_process_is_rejected(self) -> None:
        with mock.patch.object(control.base, "pid_alive", return_value=True), mock.patch.object(
            control.base,
            "process_cmdline",
            return_value="python3 unrelated_server.py",
        ):
            self.assertFalse(control.always_on_worker_pid(1234))


class AutoUpdateContractTest(unittest.TestCase):
    def controller(self, root: pathlib.Path):
        with mock.patch.dict(os.environ, {"KRIS_QWEN_AUTO_UPDATE": "0"}, clear=False):
            return control.AlwaysOnQwenController(config(root))

    def test_remote_change_queues_safe_fetch_run(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            controller = self.controller(pathlib.Path(raw))
            with mock.patch.object(controller, "_validate_repo"), mock.patch.object(
                controller, "_git_head", return_value="a" * 40
            ), mock.patch.object(
                controller, "_remote_branch_head", return_value="b" * 40
            ), mock.patch.object(
                control.BaseController, "fetch_latest_and_run", return_value={"status": "QUEUED"}
            ) as fetch:
                result = controller._auto_update_once()
            self.assertEqual(result["status"], "UPDATE_QUEUED")
            fetch.assert_called_once_with()

    def test_current_branch_auto_starts_stopped_worker(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            controller = self.controller(pathlib.Path(raw))
            with mock.patch.object(controller, "_validate_repo"), mock.patch.object(
                controller, "_git_head", return_value="c" * 40
            ), mock.patch.object(
                controller, "_remote_branch_head", return_value="c" * 40
            ), mock.patch.object(controller, "worker_pid", return_value=None), mock.patch.object(
                control.BaseController, "start", return_value={"status": "STARTED", "pid": 42}
            ) as start:
                result = controller._auto_update_once()
            self.assertEqual(result["status"], "AUTO_STARTED")
            start.assert_called_once_with()

    def test_operator_pause_blocks_restart_and_remote_update(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            controller = self.controller(pathlib.Path(raw))
            controller.auto_run_enabled = False
            with mock.patch.object(controller, "_validate_repo") as validate, mock.patch.object(
                control.BaseController, "fetch_latest_and_run"
            ) as fetch, mock.patch.object(control.BaseController, "start") as start:
                result = controller._auto_update_once()
            self.assertEqual(result, {"status": "PAUSED"})
            validate.assert_not_called()
            fetch.assert_not_called()
            start.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
