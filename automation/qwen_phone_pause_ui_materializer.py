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
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


def replace_all(path: pathlib.Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count < 1:
        raise SystemExit(f"{label}: no anchors in {path.as_posix()}")
    path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")


def materialize(project: pathlib.Path) -> None:
    controller = project / "tool/kris_qwen_control.py.compat.py"
    replace_once(
        controller,
        'TARGET_CONTROL_VERSION = "2.2.1"',
        'TARGET_CONTROL_VERSION = "2.2.2"',
        "controller version",
    )
    replace_once(
        controller,
        '''_base_origin_allowed = base.ControlHandler._origin_allowed
_base_do_get = base.ControlHandler.do_GET
''',
        '''_base_origin_allowed = base.ControlHandler._origin_allowed
_base_do_get = base.ControlHandler.do_GET


def operator_aware_dashboard_html(source: str) -> str:
    replacements = (
        (
            '<button class="danger" id="stop">Safe stop</button>',
            '<button class="danger" id="stop">Pause automation + safe stop</button>',
        ),
        (
            "const s=await api('/api/status');const w=s.worker||{},op=s.operation||{},git=s.git||{},ws=w.operatorStatus||{};",
            "const s=await api('/api/status');const w=s.worker||{},op=s.operation||{},git=s.git||{},ws=w.operatorStatus||{},au=s.autoUpdate||{},intent=au.operatorIntent||{},automationError=au.operatorIntentError||'',automationState=automationError?'ERROR':au.autoRunEnabled===false?'PAUSED':au.autoRunEnabled===true?'ACTIVE':'UNKNOWN';",
        ),
        (
            "q('#summary').innerHTML=cell('Worker',",
            "q('#summary').innerHTML=cell('Automation',automationState+(intent.reason?` · ${intent.reason}`:''),automationError?'bad':automationState==='ACTIVE'?'good':'warn')+cell('Worker',",
        ),
        (
            "cell('Control',`v${s.controlVersion}`);",
            "cell('Control',`v${s.controlVersion||s.controllerVersion||'?'}`);",
        ),
        (
            "q('#error').textContent=op.error||w.versionError||'';",
            "q('#error').textContent=automationError||op.error||w.versionError||'';",
        ),
        (
            "q('#stop').disabled=!w.running",
            "q('#stop').disabled=busy||(!w.running&&au.autoRunEnabled===false)",
        ),
    )
    rendered = source
    for old, new in replacements:
        count = rendered.count(old)
        if count != 1:
            raise RuntimeError(
                f"Qwen dashboard contract drift: expected one anchor, found {count}: {old[:80]}"
            )
        rendered = rendered.replace(old, new, 1)
    return rendered
''',
        "dashboard transformer",
    )
    replace_once(
        controller,
        '''base.ControlHandler._origin_allowed = _trusted_origin_allowed
base.ControlHandler.do_GET = _trusted_do_get
base.ControlHandler.server_version = "KrisQwenControl/2.2.1"
''',
        '''base.ControlHandler._origin_allowed = _trusted_origin_allowed
base.ControlHandler.do_GET = _trusted_do_get
base.DASHBOARD_HTML = operator_aware_dashboard_html(base.DASHBOARD_HTML)
base.ControlHandler.server_version = "KrisQwenControl/2.2.2"
''',
        "dashboard activation and HTTP identity",
    )
    replace_once(
        controller,
        '''    def status(self):
        result = super().status()
        result["controllerVersion"] = TARGET_CONTROL_VERSION
''',
        '''    def status(self):
        result = super().status()
        result["controlVersion"] = TARGET_CONTROL_VERSION
        result["controllerVersion"] = TARGET_CONTROL_VERSION
''',
        "visible controller version",
    )

    tests = project / "tool/kris_qwen_control_compat_test.py"
    replace_once(
        tests,
        '''class AutoUpdateContractTest(unittest.TestCase):
''',
        '''class DashboardOperatorIntentContractTest(unittest.TestCase):
    def test_dashboard_exposes_durable_automation_intent(self) -> None:
        html = control.base.DASHBOARD_HTML
        self.assertIn("Pause automation + safe stop", html)
        self.assertIn("cell('Automation'", html)
        self.assertIn("au.autoRunEnabled===false?'PAUSED'", html)
        self.assertIn("automationError||op.error||w.versionError||''", html)
        self.assertNotIn('id="stop">Safe stop</button>', html)

    def test_active_stopped_controller_can_be_paused_from_phone(self) -> None:
        html = control.base.DASHBOARD_HTML
        self.assertIn(
            "q('#stop').disabled=busy||(!w.running&&au.autoRunEnabled===false)",
            html,
        )
        self.assertNotIn("q('#stop').disabled=!w.running", html)

    def test_dashboard_uses_executed_controller_version(self) -> None:
        self.assertEqual(control.TARGET_CONTROL_VERSION, "2.2.2")
        self.assertEqual(control.base.CONTROL_VERSION, "2.2.2")
        self.assertIn(
            "s.controlVersion||s.controllerVersion||'?'",
            control.base.DASHBOARD_HTML,
        )


class AutoUpdateContractTest(unittest.TestCase):
''',
        "dashboard contract tests",
    )
    replace_once(
        tests,
        '''    def test_status_exposes_durable_operator_intent(self) -> None:
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
''',
        '''    def test_malformed_json_durable_state_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            cfg = config(root)
            cfg.state_dir.mkdir(parents=True, exist_ok=True)
            state = cfg.state_dir / "auto-run-state.json"
            state.write_text("{not-json", encoding="utf-8")
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
                snapshot = controller.status()
            status = snapshot["autoUpdate"]
            self.assertEqual(snapshot["controlVersion"], "2.2.2")
            self.assertEqual(snapshot["controllerVersion"], "2.2.2")
            self.assertFalse(status["autoRunEnabled"])
            self.assertEqual(
                status["operatorIntent"]["reason"],
                "test_status",
            )
            self.assertEqual(
                status["operatorIntentPath"],
                str(controller.auto_run_state_path),
            )
''',
        "malformed state and visible status tests",
    )

    ci = project / ".github/workflows/ci.yml"
    replace_once(
        ci,
        "[[ \"$(python tool/kris_qwen_control.py.compat.py --version)\" == '2.2.1' ]]",
        "[[ \"$(python tool/kris_qwen_control.py.compat.py --version)\" == '2.2.2' ]]",
        "CI controller version",
    )

    installer = project / "tool/install_kris_qwen_control_systemd.sh"
    replace_all(installer, "2.2.1", "2.2.2", "installer controller version")

    server_docs = project / "docs/KRIS_QWEN_SERVER_CONTROL.md"
    old_versions = '''- executed worker: `tool/kris_qwen_worker_v53.py` — **5.3.0**;
- legacy worker path: `tool/kris_qwen_worker.py.compat.py` — forwards to the deterministic 5.3 entry so an already-running 2.1 controller that remembers the old path reaches the same worker after Fetch latest;
- retained base worker: `tool/kris_qwen_worker.py` — still labeled **5.2.2** during rollout;
- executed controller: `tool/kris_qwen_control.py.compat.py` — **2.2.0**;
- retained base controller: `tool/kris_qwen_control.py` — still labeled **2.1.0** during rollout.
'''
    new_versions = '''- stable controller-facing worker: `tool/kris_qwen_worker_v53.py` — forwards to the deterministic 5.4.1 entry;
- executed worker: `tool/kris_qwen_worker_v541.py` — **5.4.1**;
- legacy worker path: `tool/kris_qwen_worker.py.compat.py` — forwards to the same stable 5.4.1 path so older controller configuration reaches current worker bytes after Fetch latest;
- retained base worker: `tool/kris_qwen_worker.py` — compatibility/transformation base, not the reported executed version;
- executed controller: `tool/kris_qwen_control.py.compat.py` — **2.2.2**;
- retained base controller: `tool/kris_qwen_control.py` — compatibility base, not the reported executed version.
'''
    replace_once(server_docs, old_versions, new_versions, "operator docs executed versions")
    replace_all(server_docs, "Worker 5.3", "Worker 5.4.1", "operator docs worker title")
    replace_all(server_docs, "worker 5.3", "worker 5.4.1", "operator docs worker text")
    replace_once(
        server_docs,
        "Successful Work Orders chain immediately. The normal 60-second inter-job sleep is removed by the 5.3 execution adapter.",
        "Successful Work Orders chain immediately. The normal 60-second inter-job sleep is removed by the 5.4.1 execution adapter.",
        "operator docs execution adapter",
    )
    replace_all(server_docs, "Controller 2.2", "Controller 2.2.2", "operator docs controller title")
    replace_all(server_docs, "controller 2.2", "controller 2.2.2", "operator docs controller text")
    replace_once(
        server_docs,
        '''If the tracked branch is already current but the worker process exited unexpectedly, controller 2.2.2 starts it again automatically. A deliberate **Safe stop** pauses automatic worker restart until the operator explicitly selects Run current Qwen or Fetch latest + run Qwen.

The controller process itself must be loaded once with 2.2. Future worker branch changes are then detected automatically; repeated manual Fetch latest presses are not part of the normal protocol.
''',
        '''If the tracked branch is already current but the worker process exited unexpectedly, controller 2.2.2 starts it again automatically while automation is **ACTIVE**. **Pause automation + safe stop** atomically persists operator intent in `<state_dir>/auto-run-state.json`, pauses automatic updates and restarts across controller/systemd restarts, and safely stops a running worker. Run current Qwen or Fetch latest + run Qwen explicitly returns automation to **ACTIVE**. Invalid or malformed durable state fails closed to **PAUSED**.

The phone dashboard exposes **ACTIVE**, **PAUSED**, or **ERROR** plus the persisted intent reason. The pause control remains available when automation is active even if the worker is already stopped, preventing the controller from silently restarting it before the operator can pause it.

The controller process itself must be loaded once with 2.2.2. Future worker/controller branch changes are then detected automatically; repeated manual Fetch latest presses are not part of the normal protocol.
''',
        "operator docs dashboard and durable pause",
    )

    engineering_docs = project / "docs/KRIS_QWEN_ENGINEERING_ENVIRONMENT.md"
    replace_once(
        engineering_docs,
        "# KRIS Qwen Engineering Environment 5.4",
        "# KRIS Qwen Engineering Environment 5.4.1",
        "engineering docs title",
    )
    replace_all(engineering_docs, "Qwen 5.4", "Qwen 5.4.1", "engineering docs runtime")
    replace_once(
        engineering_docs,
        "After 5.4 rollout that stable entry forwards to `tool/kris_qwen_worker_v54.py`.",
        "The stable entry forwards to `tool/kris_qwen_worker_v541.py`, the executed 5.4.1 worker.",
        "engineering docs stable entry",
    )
    replace_all(engineering_docs, "in 5.4.", "in 5.4.1.", "engineering docs capability version")


if __name__ == "__main__":
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    materialize(root)
