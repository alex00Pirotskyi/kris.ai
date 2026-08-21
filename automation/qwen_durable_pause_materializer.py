#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys


def replace_once(path: pathlib.Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{label}: expected one anchor in {path.as_posix()}, found {count}"
        )
    path.write_text(
        text.replace(old, new, 1),
        encoding="utf-8",
        newline="\n",
    )


def materialize(project: pathlib.Path) -> None:
    controller_path = project / "tool/kris_qwen_control.py.compat.py"
    replace_once(
        controller_path,
        'TARGET_CONTROL_VERSION = "2.2.0"',
        'TARGET_CONTROL_VERSION = "2.2.1"',
        "controller version",
    )
    replace_once(
        controller_path,
        'base.ControlHandler.server_version = "KrisQwenControl/2.2"',
        'base.ControlHandler.server_version = "KrisQwenControl/2.2.1"',
        "HTTP controller version",
    )

    old_lifecycle = '''class AlwaysOnQwenController(BaseController):
    def __init__(self, cfg):
        super().__init__(cfg)
        self.auto_run_enabled = True
        self.auto_update_enabled = base.env_bool("KRIS_QWEN_AUTO_UPDATE", True)
        self.self_restart_on_update = base.env_bool("KRIS_QWEN_CONTROLLER_SELF_RESTART", False)
        self.controller_runtime_sha256 = controller_runtime_fingerprint(CONTROLLER_ENTRY, SOURCE)
        self.last_auto_update: dict | None = None
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
'''
    new_lifecycle = '''class AlwaysOnQwenController(BaseController):
    def __init__(self, cfg):
        super().__init__(cfg)
        self.auto_run_state_error: str | None = None
        self.auto_run_state: dict = {}
        self.auto_run_enabled = self._load_auto_run_enabled()
        self.auto_update_enabled = base.env_bool("KRIS_QWEN_AUTO_UPDATE", True)
        self.self_restart_on_update = base.env_bool("KRIS_QWEN_CONTROLLER_SELF_RESTART", False)
        self.controller_runtime_sha256 = controller_runtime_fingerprint(CONTROLLER_ENTRY, SOURCE)
        self.last_auto_update: dict | None = None
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

    @property
    def auto_run_state_path(self) -> pathlib.Path:
        return self.cfg.state_dir / "auto-run-state.json"

    def _write_auto_run_state(self, enabled: bool, reason: str) -> dict:
        row = {
            "schemaVersion": 1,
            "autoRunEnabled": bool(enabled),
            "reason": str(reason).strip()[:512] or "unspecified",
            "updatedAt": base.utc_iso(),
        }
        base.atomic_write_json(self.auto_run_state_path, row)
        self.auto_run_state = row
        self.auto_run_enabled = bool(enabled)
        self.auto_run_state_error = None
        return row

    def _load_auto_run_enabled(self) -> bool:
        path = self.auto_run_state_path
        if not path.exists():
            self._write_auto_run_state(True, "initial_default_enabled")
            return True
        row = base.read_json(path)
        valid = (
            isinstance(row, dict)
            and row.get("schemaVersion") == 1
            and isinstance(row.get("autoRunEnabled"), bool)
            and isinstance(row.get("reason"), str)
            and bool(str(row.get("reason")).strip())
            and isinstance(row.get("updatedAt"), str)
            and bool(str(row.get("updatedAt")).strip())
        )
        if not valid:
            detail = (
                "invalid durable auto-run state; automatic update and restart "
                "remain paused until an explicit Run current Qwen or "
                "Fetch latest + run Qwen"
            )
            self._write_auto_run_state(
                False,
                "invalid_durable_state_fail_closed",
            )
            self.auto_run_state_error = detail
            return False
        self.auto_run_state = dict(row)
        self.auto_run_enabled = bool(row["autoRunEnabled"])
        return self.auto_run_enabled

    def _set_auto_run_enabled(self, enabled: bool, reason: str) -> dict:
        with self.lock:
            return self._write_auto_run_state(enabled, reason)

    def start(self):
        self._set_auto_run_enabled(True, "operator_run_current")
        return super().start()

    def request_safe_stop(self, reason: str = "Qwen phone control safe stop"):
        if reason == "Qwen phone control safe stop":
            self._set_auto_run_enabled(False, "operator_safe_stop")
        return super().request_safe_stop(reason)

    def fetch_latest_and_run(self):
        self._set_auto_run_enabled(
            True,
            "operator_fetch_latest_and_run",
        )
        return super().fetch_latest_and_run()
'''
    replace_once(
        controller_path,
        old_lifecycle,
        new_lifecycle,
        "controller lifecycle",
    )

    old_status = '''        result["autoUpdate"] = {
            "enabled": self.auto_update_enabled,
            "intervalSeconds": self.auto_update_seconds,
            "autoRunEnabled": self.auto_run_enabled,
            "selfRestartOnControllerUpdate": self.self_restart_on_update,
            "last": self.last_auto_update,
        }
'''
    new_status = '''        result["autoUpdate"] = {
            "enabled": self.auto_update_enabled,
            "intervalSeconds": self.auto_update_seconds,
            "autoRunEnabled": self.auto_run_enabled,
            "operatorIntent": dict(self.auto_run_state),
            "operatorIntentPath": str(self.auto_run_state_path),
            "operatorIntentError": self.auto_run_state_error,
            "selfRestartOnControllerUpdate": self.self_restart_on_update,
            "last": self.last_auto_update,
        }
'''
    replace_once(
        controller_path,
        old_status,
        new_status,
        "controller status",
    )

    test_path = project / "tool/kris_qwen_control_compat_test.py"
    replace_once(
        test_path,
        "import importlib.util\nimport os\n",
        "import importlib.util\nimport json\nimport os\n",
        "test json import",
    )
    replace_once(
        test_path,
        '''    repo.mkdir()
    (repo / ".git").mkdir()
    worker = repo / "tool" / "kris_qwen_worker_v53.py"
    worker.parent.mkdir()
''',
        '''    repo.mkdir(exist_ok=True)
    (repo / ".git").mkdir(exist_ok=True)
    worker = repo / "tool" / "kris_qwen_worker_v53.py"
    worker.parent.mkdir(exist_ok=True)
''',
        "restart-safe test fixture",
    )

    test_anchor = '''    def test_operator_pause_blocks_restart_and_remote_update(self) -> None:
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
'''
    durable_tests = test_anchor + '''
    def test_operator_pause_survives_controller_restart(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            controller = self.controller(root)
            result = controller.request_safe_stop()
            self.assertEqual(result["status"], "ALREADY_STOPPED")
            self.assertFalse(controller.auto_run_enabled)
            persisted = json.loads(
                controller.auto_run_state_path.read_text(encoding="utf-8")
            )
            self.assertFalse(persisted["autoRunEnabled"])
            self.assertEqual(persisted["reason"], "operator_safe_stop")

            restarted = self.controller(root)
            self.assertFalse(restarted.auto_run_enabled)
            with mock.patch.object(restarted, "_validate_repo") as validate:
                self.assertEqual(
                    restarted._auto_update_once(),
                    {"status": "PAUSED"},
                )
            validate.assert_not_called()

    def test_explicit_run_actions_clear_durable_pause(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            controller = self.controller(root)
            controller._set_auto_run_enabled(False, "test_pause")

            restarted = self.controller(root)
            with mock.patch.object(
                control.BaseController,
                "start",
                return_value={"status": "STARTED", "pid": 42},
            ):
                self.assertEqual(restarted.start()["status"], "STARTED")
            after_start = self.controller(root)
            self.assertTrue(after_start.auto_run_enabled)
            self.assertEqual(
                after_start.auto_run_state["reason"],
                "operator_run_current",
            )

            after_start._set_auto_run_enabled(False, "test_pause_again")
            paused_again = self.controller(root)
            with mock.patch.object(
                control.BaseController,
                "fetch_latest_and_run",
                return_value={"status": "QUEUED"},
            ):
                self.assertEqual(
                    paused_again.fetch_latest_and_run()["status"],
                    "QUEUED",
                )
            after_fetch = self.controller(root)
            self.assertTrue(after_fetch.auto_run_enabled)
            self.assertEqual(
                after_fetch.auto_run_state["reason"],
                "operator_fetch_latest_and_run",
            )

    def test_invalid_durable_state_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            cfg = config(root)
            cfg.state_dir.mkdir(parents=True, exist_ok=True)
            state = cfg.state_dir / "auto-run-state.json"
            state.write_text(
                '{"schemaVersion":1,"autoRunEnabled":"yes"}\n',
                encoding="utf-8",
            )
            env = {
                "KRIS_QWEN_AUTO_UPDATE": "0",
                "KRIS_QWEN_CONTROLLER_SELF_RESTART": "0",
            }
            with mock.patch.dict(os.environ, env, clear=False):
                controller = control.AlwaysOnQwenController(cfg)
            self.assertFalse(controller.auto_run_enabled)
            self.assertIsNotNone(controller.auto_run_state_error)
            rewritten = json.loads(state.read_text(encoding="utf-8"))
            self.assertFalse(rewritten["autoRunEnabled"])
            self.assertEqual(
                rewritten["reason"],
                "invalid_durable_state_fail_closed",
            )

    def test_status_exposes_durable_operator_intent(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            controller = self.controller(pathlib.Path(raw))
            controller._set_auto_run_enabled(False, "test_status")
            with mock.patch.object(
                control.BaseController,
                "status",
                return_value={},
            ):
                status = controller.status()["autoUpdate"]
            self.assertFalse(status["autoRunEnabled"])
            self.assertEqual(
                status["operatorIntent"]["reason"],
                "test_status",
            )
            self.assertEqual(
                status["operatorIntentPath"],
                str(controller.auto_run_state_path),
            )
'''
    replace_once(
        test_path,
        test_anchor,
        durable_tests,
        "durable controller tests",
    )

    ci_path = project / ".github/workflows/ci.yml"
    replace_once(
        ci_path,
        "            tool/kris_qwen_control.py.compat.py \\\n"
        "            tool/kris_qwen_v531_test.py \\\n",
        "            tool/kris_qwen_control.py.compat.py \\\n"
        "            tool/kris_qwen_control_compat_test.py \\\n"
        "            tool/kris_qwen_v531_test.py \\\n",
        "CI compile coverage",
    )
    replace_once(
        ci_path,
        "          python tool/kris_qwen_v541_test.py\n"
        "          python tool/kris_qwen_control_token_redaction_test.py\n",
        "          python tool/kris_qwen_v541_test.py\n"
        "          python tool/kris_qwen_control_compat_test.py\n"
        "          python tool/kris_qwen_control_token_redaction_test.py\n",
        "CI runtime coverage",
    )
    replace_once(
        ci_path,
        "[[ \"$(python tool/kris_qwen_control.py.compat.py --version)\" == '2.2.0' ]]",
        "[[ \"$(python tool/kris_qwen_control.py.compat.py --version)\" == '2.2.1' ]]",
        "CI controller version",
    )

    installer_path = project / "tool/install_kris_qwen_control_systemd.sh"
    replacements = (
        (
            "Qwen engineering worker 5.4.1 / controller 2.2.",
            "Qwen engineering worker 5.4.1 / controller 2.2.1.",
            "installer help version",
        ),
        (
            '  "${REPO_DIR}/tool/kris_qwen_v541_test.py"\n'
            '  "${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py"\n',
            '  "${REPO_DIR}/tool/kris_qwen_v541_test.py"\n'
            '  "${REPO_DIR}/tool/kris_qwen_control_compat_test.py"\n'
            '  "${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py"\n',
            "installer required test",
        ),
        (
            '  "${REPO_DIR}/tool/kris_qwen_v541_test.py" \\\n'
            '  "${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py"\n',
            '  "${REPO_DIR}/tool/kris_qwen_v541_test.py" \\\n'
            '  "${REPO_DIR}/tool/kris_qwen_control_compat_test.py" \\\n'
            '  "${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py"\n',
            "installer compile test",
        ),
        (
            'if ! as_service_user "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py" >/dev/null; then\n',
            'if ! as_service_user "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_control_compat_test.py" >/dev/null; then\n'
            '  echo "Qwen controller durable-pause regression preflight failed." >&2\n'
            '  exit 2\n'
            'fi\n'
            'if ! as_service_user "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py" >/dev/null; then\n',
            "installer test execution",
        ),
        (
            'if [[ "${CONTROLLER_VERSION}" != "2.2.0" ]]; then\n'
            '  echo "Qwen controller 2.2 preflight failed: ${CONTROLLER_VERSION}" >&2\n',
            'if [[ "${CONTROLLER_VERSION}" != "2.2.1" ]]; then\n'
            '  echo "Qwen controller 2.2.1 preflight failed: ${CONTROLLER_VERSION}" >&2\n',
            "installer version preflight",
        ),
        (
            "ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_v541_test.py\n"
            "ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py\n",
            "ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_v541_test.py\n"
            "ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_control_compat_test.py\n"
            "ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py\n",
            "systemd test preflight",
        ),
        (
            'echo "Controller:   2.2.0"',
            'echo "Controller:   2.2.1"',
            "installer result version",
        ),
        (
            "are recovered by controller 2.2 / worker 5.4.1, safe branch updates are automatic,",
            "are recovered by controller 2.2.1 / worker 5.4.1, safe branch updates are automatic,",
            "installer recovery version",
        ),
    )
    for old, new, label in replacements:
        replace_once(installer_path, old, new, label)


if __name__ == "__main__":
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    materialize(root)
