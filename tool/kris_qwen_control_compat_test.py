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

    def test_legacy_entry_remains_recognized(self) -> None:
        with mock.patch.object(control.base, "pid_alive", return_value=True), mock.patch.object(
            control.base,
            "process_cmdline",
            return_value="python3 /repo/tool/kris_qwen_worker.py.compat.py stack --root /tmp/qwen",
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

    def test_candidate_entries_are_executed_in_detached_probe(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            controller = self.controller(pathlib.Path(raw))

            def fake_git(*args, check=True, timeout=300):
                if args[:3] == ("worktree", "add", "--detach"):
                    target = pathlib.Path(args[3])
                    (target / "tool").mkdir(parents=True)
                    (target / "tool/kris_qwen_worker_v53.py").write_text(
                        "import json\nprint(json.dumps({'scriptVersion':'5.3.0'}))\n",
                        encoding="utf-8",
                    )
                    (target / "tool/kris_qwen_control.py.compat.py").write_text(
                        "print('2.2.0')\n",
                        encoding="utf-8",
                    )
                    return mock.Mock(returncode=0, stdout="", stderr="")
                if args[:3] == ("worktree", "remove", "--force"):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                raise AssertionError(args)

            with mock.patch.object(controller, "_git", side_effect=fake_git):
                result = controller._probe_candidate_entries("b" * 40)
            self.assertEqual(result["workerVersion"], "5.3.0")
            self.assertEqual(result["controllerVersion"], "2.2.0")
            self.assertEqual(result["candidate"], "b" * 40)

    def test_remote_change_queues_safe_fetch_run(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            controller = self.controller(pathlib.Path(raw))
            with mock.patch.object(controller, "_validate_repo"), mock.patch.object(
                controller, "_git_head", return_value="a" * 40
            ), mock.patch.object(
                controller, "_remote_branch_head", return_value="b" * 40
            ), mock.patch.object(
                controller,
                "_auto_update_preflight",
                return_value={
                    "status": "UPDATE_READY", "local": "a" * 40, "remote": "b" * 40,
                    "probe": {"workerVersion": "5.3.0", "controllerVersion": "2.2.0"},
                },
            ), mock.patch.object(
                control.BaseController, "fetch_latest_and_run", return_value={"status": "QUEUED"}
            ) as fetch:
                result = controller._auto_update_once()
            self.assertEqual(result["status"], "UPDATE_QUEUED")
            self.assertEqual(result["remote"], "b" * 40)
            self.assertEqual(result["probe"]["workerVersion"], "5.3.0")
            fetch.assert_called_once_with()

    def test_dirty_checkout_blocks_auto_update_before_drain(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            controller = self.controller(pathlib.Path(raw))
            calls: list[tuple[str, ...]] = []

            def fake_git(*args, check=True, timeout=300):
                calls.append(tuple(args))
                if args == ("status", "--porcelain", "--untracked-files=all"):
                    return mock.Mock(returncode=0, stdout=" M local.txt\n", stderr="")
                raise AssertionError(args)

            with mock.patch.object(controller, "_git", side_effect=fake_git):
                result = controller._auto_update_preflight("a" * 40, "b" * 40)
            self.assertEqual(result["status"], "UPDATE_BLOCKED_DIRTY")
            self.assertEqual(calls, [("status", "--porcelain", "--untracked-files=all")])

    def test_non_fast_forward_blocks_auto_update_before_drain(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            controller = self.controller(pathlib.Path(raw))
            calls: list[tuple[str, ...]] = []

            def fake_git(*args, check=True, timeout=300):
                calls.append(tuple(args))
                if args == ("status", "--porcelain", "--untracked-files=all"):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                if args == ("fetch", "origin", "agent/qwen-phone-control", "--prune"):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                if args == ("rev-parse", "origin/agent/qwen-phone-control"):
                    return mock.Mock(returncode=0, stdout="b" * 40 + "\n", stderr="")
                if args == ("merge-base", "--is-ancestor", "a" * 40, "b" * 40):
                    return mock.Mock(returncode=1, stdout="", stderr="")
                raise AssertionError(args)

            with mock.patch.object(controller, "_git", side_effect=fake_git):
                result = controller._auto_update_preflight("a" * 40, "b" * 40)
            self.assertEqual(result["status"], "UPDATE_BLOCKED_NON_FAST_FORWARD")
            self.assertIn(("merge-base", "--is-ancestor", "a" * 40, "b" * 40), calls)

    def test_invalid_candidate_blocks_before_drain(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            controller = self.controller(pathlib.Path(raw))

            def fake_git(*args, check=True, timeout=300):
                if args == ("status", "--porcelain", "--untracked-files=all"):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                if args == ("fetch", "origin", "agent/qwen-phone-control", "--prune"):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                if args == ("rev-parse", "origin/agent/qwen-phone-control"):
                    return mock.Mock(returncode=0, stdout="b" * 40 + "\n", stderr="")
                if args == ("merge-base", "--is-ancestor", "a" * 40, "b" * 40):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                raise AssertionError(args)

            with mock.patch.object(controller, "_git", side_effect=fake_git), mock.patch.object(
                controller, "_probe_candidate_entries",
                side_effect=control.base.ControllerError("broken candidate"),
            ):
                result = controller._auto_update_preflight("a" * 40, "b" * 40)
            self.assertEqual(result["status"], "UPDATE_BLOCKED_CANDIDATE_INVALID")
            self.assertIn("broken candidate", result["detail"])

    def test_validated_fast_forward_is_pinned_to_exact_probe_sha(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            controller = self.controller(pathlib.Path(raw))
            old = "a" * 40
            new = "b" * 40
            calls: list[tuple[str, ...]] = []

            def fake_git(*args, check=True, timeout=300):
                calls.append(tuple(args))
                if args == ("status", "--porcelain", "--untracked-files=all"):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                if args == ("merge-base", "--is-ancestor", old, new):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                if args == ("merge", "--ff-only", new):
                    return mock.Mock(returncode=0, stdout="", stderr="")
                raise AssertionError(args)

            with mock.patch.object(controller, "_validate_repo"), mock.patch.object(
                controller, "_git_head", side_effect=[old, new]
            ), mock.patch.object(controller, "_remote_branch_head", return_value=new), mock.patch.object(
                controller, "_git", side_effect=fake_git
            ), mock.patch.object(controller, "_record_operation"):
                result = controller._fast_forward_validated(new)
            self.assertTrue(result["changed"])
            self.assertEqual(result["after"], new)
            self.assertIn(("merge", "--ff-only", new), calls)
            self.assertNotIn(("merge", "--ff-only", "origin/agent/qwen-phone-control"), calls)

    def test_aborted_post_drain_update_recovers_current_worker(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            controller = self.controller(pathlib.Path(raw))
            old = "a" * 40
            new = "b" * 40
            records = []

            with mock.patch.object(controller, "_validate_repo"), mock.patch.object(
                controller, "_git_head", return_value=old
            ), mock.patch.object(controller, "_remote_branch_head", return_value=new), mock.patch.object(
                controller, "_auto_update_preflight",
                return_value={
                    "status": "UPDATE_READY", "local": old, "remote": new,
                    "probe": {"workerVersion": "5.3.0", "controllerVersion": "2.2.0"},
                },
            ), mock.patch.object(controller, "worker_pid", side_effect=[1234, None]), mock.patch.object(
                controller, "request_safe_stop"
            ), mock.patch.object(controller, "_wait_for_worker_exit"), mock.patch.object(
                controller, "_fast_forward_validated",
                side_effect=control.base.ControllerError("remote moved during drain"),
            ), mock.patch.object(
                controller, "_start_worker_unlocked",
                return_value={"status": "STARTED", "pid": 4321},
            ) as restart, mock.patch.object(
                controller, "_record_operation", side_effect=lambda **kwargs: records.append(kwargs)
            ):
                controller._fetch_latest_and_run_job()

            restart.assert_called_once_with()
            self.assertTrue(records)
            final = records[-1]
            self.assertEqual(final["state"], "ERROR")
            self.assertEqual(final["recovery"]["status"], "STARTED")
            self.assertIn("remote moved during drain", final["error"])

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
