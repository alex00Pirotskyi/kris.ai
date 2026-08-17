#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
for module_name, filename in (
    ("kris_qwen_v6_guard", "kris_qwen_v6_guard.py"),
    ("kris_qwen_control", "kris_qwen_control.py"),
):
    spec = importlib.util.spec_from_file_location(module_name, HERE / filename)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)

control = sys.modules["kris_qwen_control"]
v6 = sys.modules["kris_qwen_v6_guard"]


def config(root: pathlib.Path, backend: str = "process"):
    repo = root / "repo"
    (repo / "tool").mkdir(parents=True)
    (repo / ".git").mkdir()
    python = root / "python"
    python.write_text("")
    model = root / "model.gguf"
    model.write_bytes(b"model")
    worker = repo / "tool/kris_qwen_worker.py"
    worker.write_text("#!/usr/bin/env python3\n")
    return control.ControlConfig(
        repo_dir=repo,
        repo_branch="agent/qwen-server-control-v6",
        python=python,
        worker_root=root / "worker",
        host="127.0.0.1",
        port=8090,
        backend=backend,
        model_unit="kris-qwen-model.service",
        worker_unit="kris-qwen-worker.service",
        stop_timeout=5,
        token_path=root / "worker/controller/control-token",
        model_path=model,
        sandbox_mode="off",
    )


class SecurityContractTest(unittest.TestCase):
    def test_dashboard_never_embeds_token_placeholder_or_runtime_token(self) -> None:
        self.assertNotIn("__TOKEN__", control.DASHBOARD_HTML)
        self.assertNotIn("control-token-value", control.DASHBOARD_HTML)
        self.assertIn("sessionStorage", control.DASHBOARD_HTML)
        self.assertIn("X-Kris-Control-Token", control.DASHBOARD_HTML)

    def test_host_and_origin_are_loopback_only(self) -> None:
        self.assertTrue(control._loopback_host("127.0.0.1:8090"))
        self.assertTrue(control._loopback_host("localhost:8090"))
        self.assertFalse(control._loopback_host("10.0.0.2:8090"))
        self.assertTrue(control._loopback_origin(None))
        self.assertTrue(control._loopback_origin("http://127.0.0.1:8090"))
        self.assertFalse(control._loopback_origin("https://evil.example"))

    def test_environment_rejects_non_loopback_listener(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "KRIS_QWEN_CONTROL_HOST": "0.0.0.0",
                "KRIS_QWEN_ROOT": "/tmp/qwen-test",
            },
            clear=False,
        ):
            with self.assertRaisesRegex(control.ControllerError, "loopback-only"):
                control.ControlConfig.from_environment()


class OperationRecoveryTest(unittest.TestCase):
    def test_interrupted_operation_is_marked_and_backend_is_reconciled(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cfg = config(pathlib.Path(raw))
            cfg.controller_dir.mkdir(parents=True)
            v6.atomic_write_json(
                cfg.operation_path,
                {"schemaVersion": 2, "operationId": "op-1", "kind": "start", "state": "RUNNING"},
            )
            backend = mock.Mock()
            backend.status.return_value = {"backend": "process", "running": False}
            controller = object.__new__(control.Controller)
            controller.cfg = cfg
            controller.token = "x" * 48
            controller.lock = __import__("threading").Lock()
            controller.rates = __import__("collections").defaultdict(__import__("collections").deque)
            controller.backend = backend
            controller._recover_operation()
            row = json.loads(cfg.operation_path.read_text())
            self.assertEqual(row["state"], "INTERRUPTED")
            self.assertEqual(row["backendStatus"]["running"], False)

    def test_operation_lock_rejects_concurrent_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cfg = config(pathlib.Path(raw))
            backend = mock.Mock()
            controller = object.__new__(control.Controller)
            controller.cfg = cfg
            controller.token = "x" * 48
            controller.lock = __import__("threading").Lock()
            controller.rates = __import__("collections").defaultdict(__import__("collections").deque)
            controller.backend = backend
            controller.lock.acquire()
            try:
                with self.assertRaisesRegex(control.ControllerError, "already running"):
                    controller._operation("start", lambda: {})
            finally:
                controller.lock.release()


class SystemdBackendTest(unittest.TestCase):
    def test_start_orders_model_before_worker_and_rolls_back_on_worker_failure(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cfg = config(pathlib.Path(raw), backend="systemd")
            backend = control.SystemdBackend(cfg)
            calls = []

            def fake_run(argv, **kwargs):
                calls.append(list(argv))
                if argv[:3] == ["systemctl", "start", cfg.worker_unit]:
                    raise control.ControllerError("worker failed")
                return mock.Mock(returncode=0, stdout="", stderr="")

            with mock.patch.object(control, "run", side_effect=fake_run), mock.patch.object(
                backend, "_wait", return_value=None
            ):
                with self.assertRaisesRegex(control.ControllerError, "worker failed"):
                    backend.start()
            self.assertEqual(calls[0], ["systemctl", "start", cfg.model_unit])
            self.assertIn(["systemctl", "stop", cfg.model_unit], calls)

    def test_stop_orders_worker_before_model(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cfg = config(pathlib.Path(raw), backend="systemd")
            backend = control.SystemdBackend(cfg)
            calls = []

            def fake_run(argv, **kwargs):
                calls.append(list(argv))
                return mock.Mock(returncode=0, stdout="", stderr="")

            with mock.patch.object(control, "run", side_effect=fake_run), mock.patch.object(
                backend, "_wait", return_value=None
            ), mock.patch.object(backend, "status", return_value={"ok": True}):
                backend.stop()
            self.assertEqual(calls[0], ["systemctl", "stop", cfg.worker_unit])
            self.assertEqual(calls[1], ["systemctl", "stop", cfg.model_unit])


class ProcessBackendTest(unittest.TestCase):
    def test_stale_pid_record_is_not_adopted(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cfg = config(pathlib.Path(raw))
            cfg.controller_dir.mkdir(parents=True)
            v6.atomic_write_json(
                cfg.process_path,
                {
                    "pid": os.getpid(),
                    "identity": {
                        "pid": os.getpid(),
                        "start_ticks": 1,
                        "executable": "/wrong",
                        "cmdline_sha256": "0" * 64,
                    },
                },
            )
            backend = control.ProcessBackend(cfg)
            self.assertIsNone(backend._record())
            self.assertFalse(backend.status()["running"])


class PreflightTest(unittest.TestCase):
    def test_worker_version_and_github_auth_are_required(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cfg = config(pathlib.Path(raw))
            controller = object.__new__(control.Controller)
            controller.cfg = cfg
            responses = [
                mock.Mock(returncode=0, stdout="6.0.0\n", stderr=""),
                mock.Mock(returncode=0, stdout="logged in\n", stderr=""),
            ]
            with mock.patch.object(control, "run", side_effect=responses), mock.patch.object(
                control, "shutil_which", return_value="/usr/bin/bwrap"
            ):
                value = controller.preflight()
            self.assertEqual(value["workerVersion"], "6.0.0")
            self.assertEqual(value["githubAuth"], "ok")

    def test_github_auth_failure_is_rejected_before_start(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cfg = config(pathlib.Path(raw))
            controller = object.__new__(control.Controller)
            controller.cfg = cfg
            responses = [
                mock.Mock(returncode=0, stdout="6.0.0\n", stderr=""),
                mock.Mock(returncode=1, stdout="", stderr="not logged into any GitHub hosts; run gh auth login"),
            ]
            with mock.patch.object(control, "run", side_effect=responses):
                with self.assertRaisesRegex(control.ControllerError, "authentication"):
                    controller.preflight()


if __name__ == "__main__":
    unittest.main(verbosity=2)
