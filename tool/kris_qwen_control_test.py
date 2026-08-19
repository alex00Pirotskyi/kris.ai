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
spec = importlib.util.spec_from_file_location("kris_qwen_control", HERE / "kris_qwen_control.py")
assert spec is not None and spec.loader is not None
control = importlib.util.module_from_spec(spec)
sys.modules["kris_qwen_control"] = control
spec.loader.exec_module(control)


def config(root: pathlib.Path, *, host: str = "127.0.0.1", remote: bool = False):
    repo = root / "repo"
    (repo / "tool").mkdir(parents=True)
    (repo / ".git").mkdir()
    worker = repo / "tool/kris_qwen_worker.py"
    worker.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
    return control.ControlConfig(
        repo_dir=repo,
        repo_branch="main",
        python=sys.executable,
        worker_script=worker,
        worker_root=root / "worker",
        state_dir=root / "worker/controller",
        host=host,
        port=8090,
        allow_remote_http=remote,
        stop_timeout=30,
        worker_extra_args=(),
    )


class SecurityContractTest(unittest.TestCase):
    def test_dashboard_does_not_embed_control_token(self) -> None:
        self.assertNotIn("__TOKEN__", control.DASHBOARD_HTML)
        self.assertIn("sessionStorage", control.DASHBOARD_HTML)
        self.assertIn("X-Kris-Control-Token", control.DASHBOARD_HTML)
        self.assertIn("Fetch latest + run Qwen", control.DASHBOARD_HTML)

    def test_same_origin_accepts_phone_address_and_rejects_cross_origin(self) -> None:
        self.assertTrue(control.same_origin("192.168.1.10:8090", "http://192.168.1.10:8090"))
        self.assertTrue(control.same_origin("100.90.1.5:8090", "http://100.90.1.5:8090/"))
        self.assertFalse(control.same_origin("192.168.1.10:8090", "https://evil.example"))
        self.assertFalse(control.same_origin("", None))

    def test_environment_rejects_remote_listener_without_explicit_opt_in(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "KRIS_QWEN_CONTROL_HOST": "0.0.0.0",
                "KRIS_QWEN_CONTROL_ALLOW_REMOTE_HTTP": "0",
                "KRIS_QWEN_ROOT": "/tmp/kris-qwen-control-test",
            },
            clear=False,
        ):
            with self.assertRaisesRegex(control.ControllerError, "explicit"):
                control.ControlConfig.from_environment()

    def test_phone_mode_can_opt_in_to_remote_http(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "KRIS_QWEN_CONTROL_HOST": "127.0.0.1",
                "KRIS_QWEN_CONTROL_ALLOW_REMOTE_HTTP": "0",
                "KRIS_QWEN_ROOT": "/tmp/kris-qwen-control-test",
            },
            clear=False,
        ):
            cfg = control.ControlConfig.from_environment(host="0.0.0.0", allow_remote_http=True)
        self.assertEqual(cfg.host, "0.0.0.0")
        self.assertTrue(cfg.allow_remote_http)


class WorkerVersionTest(unittest.TestCase):
    def test_json_worker_version_is_parsed(self) -> None:
        self.assertEqual(
            control.worker_version_from_stdout(json.dumps({"scriptVersion": "5.2.0", "sha256": "abc"})),
            "5.2.0",
        )

    def test_plain_worker_version_remains_compatible(self) -> None:
        self.assertEqual(control.worker_version_from_stdout("6.0.0\n"), "6.0.0")

    def test_missing_json_version_is_rejected(self) -> None:
        with self.assertRaisesRegex(control.ControllerError, "scriptVersion"):
            control.worker_version_from_stdout(json.dumps({"version": "6.0.0"}))


class ControllerPreflightTest(unittest.TestCase):
    def test_preflight_accepts_real_worker_version_json_shape(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cfg = config(pathlib.Path(raw))
            controller = control.QwenController(cfg)
            calls = [
                mock.Mock(returncode=0, stdout="main\n", stderr=""),
                mock.Mock(returncode=0, stdout=json.dumps({"scriptVersion": "5.2.0"}) + "\n", stderr=""),
                mock.Mock(returncode=0, stdout="logged in\n", stderr=""),
                mock.Mock(returncode=0, stdout="abc123\n", stderr=""),
            ]
            with mock.patch.object(control, "run", side_effect=calls):
                value = controller.preflight()
            self.assertEqual(value["workerVersion"], "5.2.0")
            self.assertEqual(value["githubAuth"], "ok")

    def test_preflight_rejects_github_auth_failure(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cfg = config(pathlib.Path(raw))
            controller = control.QwenController(cfg)
            with mock.patch.object(controller, "_validate_repo"), mock.patch.object(
                controller, "worker_version", return_value="5.2.0"
            ), mock.patch.object(
                control, "run", return_value=mock.Mock(returncode=1, stdout="", stderr="not logged in")
            ):
                with self.assertRaisesRegex(control.ControllerError, "authentication"):
                    controller.preflight()


class FastForwardTest(unittest.TestCase):
    def test_fetch_latest_refuses_dirty_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cfg = config(pathlib.Path(raw))
            controller = control.QwenController(cfg)
            with mock.patch.object(controller, "_validate_repo"), mock.patch.object(
                controller, "_git", return_value=mock.Mock(returncode=0, stdout=" M local.txt\n", stderr="")
            ):
                with self.assertRaisesRegex(control.ControllerError, "dirty"):
                    controller._fast_forward_repo()

    def test_fetch_latest_fast_forwards_only_to_fetched_remote(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cfg = config(pathlib.Path(raw))
            controller = control.QwenController(cfg)
            calls: list[tuple[str, ...]] = []

            def fake_git(*args, check=True, timeout=300):
                calls.append(tuple(args))
                if args[:2] == ("status", "--porcelain"):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                if args == ("rev-parse", "HEAD"):
                    count = sum(1 for row in calls if row == ("rev-parse", "HEAD"))
                    return mock.Mock(returncode=0, stdout=("old\n" if count == 1 else "new\n"), stderr="")
                if args == ("fetch", "origin", "main", "--prune"):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                if args == ("rev-parse", "origin/main"):
                    return mock.Mock(returncode=0, stdout="new\n", stderr="")
                if args == ("merge-base", "--is-ancestor", "old", "new"):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                if args == ("merge", "--ff-only", "origin/main"):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                raise AssertionError(args)

            with mock.patch.object(controller, "_validate_repo"), mock.patch.object(
                controller, "_git", side_effect=fake_git
            ):
                result = controller._fast_forward_repo()
            self.assertTrue(result["changed"])
            self.assertEqual(result["before"], "old")
            self.assertEqual(result["after"], "new")
            self.assertIn(("merge", "--ff-only", "origin/main"), calls)

    def test_non_fast_forward_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cfg = config(pathlib.Path(raw))
            controller = control.QwenController(cfg)

            def fake_git(*args, check=True, timeout=300):
                if args[:2] == ("status", "--porcelain"):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                if args == ("rev-parse", "HEAD"):
                    return mock.Mock(returncode=0, stdout="old\n", stderr="")
                if args == ("fetch", "origin", "main", "--prune"):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                if args == ("rev-parse", "origin/main"):
                    return mock.Mock(returncode=0, stdout="other\n", stderr="")
                if args == ("merge-base", "--is-ancestor", "old", "other"):
                    return mock.Mock(returncode=1, stdout="", stderr="")
                raise AssertionError(args)

            with mock.patch.object(controller, "_validate_repo"), mock.patch.object(
                controller, "_git", side_effect=fake_git
            ):
                with self.assertRaisesRegex(control.ControllerError, "non-fast-forward"):
                    controller._fast_forward_repo()


class LaunchCommandTest(unittest.TestCase):
    def test_worker_command_runs_stack_with_configured_root(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cfg = config(pathlib.Path(raw))
            controller = control.QwenController(cfg)
            argv = controller._worker_command()
            self.assertEqual(argv[1], str(cfg.worker_script))
            self.assertEqual(argv[2], "stack")
            self.assertIn(str(cfg.worker_root), argv)


if __name__ == "__main__":
    unittest.main(verbosity=2)
