#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import os
import pathlib
import shutil
import sys
import tempfile
import threading
import time

SOURCE = pathlib.Path(__file__).with_name("kris_qwen_control.py")
CONTROLLER_ENTRY = pathlib.Path(__file__).resolve()
TARGET_CONTROL_VERSION = "2.2.2"


def controller_runtime_fingerprint(entry: pathlib.Path, source: pathlib.Path) -> str:
    digest = hashlib.sha256()
    for path in (entry, source):
        if not path.is_file():
            raise RuntimeError(f"controller runtime source missing: {path}")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


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


TRUSTED_CONTROL_NETWORKS = tuple(
    base.ipaddress.ip_network(value)
    for value in (
        "127.0.0.0/8",
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16",
        "169.254.0.0/16",
        "100.64.0.0/10",
        "::1/128",
        "fc00::/7",
        "fe80::/10",
    )
)


def is_trusted_control_peer(value: str) -> bool:
    try:
        address = base.ipaddress.ip_address(str(value).split("%", 1)[0])
    except ValueError:
        return False
    if getattr(address, "ipv4_mapped", None) is not None:
        address = address.ipv4_mapped
    return any(address.version == network.version and address in network for network in TRUSTED_CONTROL_NETWORKS)


_base_discover_phone_urls = base.discover_phone_urls


def trusted_discover_phone_urls(port: int) -> list[str]:
    rows: list[str] = []
    for url in _base_discover_phone_urls(port):
        try:
            host = base.urlsplit(url).hostname or ""
        except ValueError:
            continue
        if is_trusted_control_peer(host):
            rows.append(url)
    return rows


_base_origin_allowed = base.ControlHandler._origin_allowed
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


def _trusted_peer_allowed(handler) -> bool:
    try:
        peer = str(handler.client_address[0])
    except (AttributeError, IndexError, TypeError):
        return False
    return is_trusted_control_peer(peer)


def _trusted_origin_allowed(handler) -> bool:
    if not _trusted_peer_allowed(handler):
        return False
    return _base_origin_allowed(handler)


def _trusted_do_get(handler) -> None:
    if not _trusted_peer_allowed(handler):
        handler._json(
            base.HTTPStatus.FORBIDDEN,
            {"error": "public controller peers are rejected; use loopback, trusted LAN, VPN, or Tailscale"},
        )
        return
    _base_do_get(handler)


base.is_qwen_worker_pid = always_on_worker_pid
base.discover_phone_urls = trusted_discover_phone_urls
base.ControlHandler._peer_allowed = _trusted_peer_allowed
base.ControlHandler._origin_allowed = _trusted_origin_allowed
base.ControlHandler.do_GET = _trusted_do_get
base.DASHBOARD_HTML = operator_aware_dashboard_html(base.DASHBOARD_HTML)
base.ControlHandler.server_version = "KrisQwenControl/2.2.2"


class AlwaysOnQwenController(BaseController):
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

    def _candidate_worker_relative(self) -> pathlib.Path:
        try:
            return self.cfg.worker_script.resolve().relative_to(self.cfg.repo_dir.resolve())
        except ValueError as exc:
            raise base.ControllerError(
                f"configured worker entry is outside repository: {self.cfg.worker_script}"
            ) from exc

    def _probe_candidate_entries(self, candidate_ref: str) -> dict:
        self.cfg.state_dir.mkdir(parents=True, exist_ok=True)
        probe_dir = pathlib.Path(
            tempfile.mkdtemp(prefix="candidate-probe-", dir=str(self.cfg.state_dir))
        )
        probe_dir.rmdir()
        added = False
        try:
            self._git(
                "worktree", "add", "--detach", str(probe_dir), candidate_ref,
                timeout=300,
            )
            added = True
            worker = probe_dir / self._candidate_worker_relative()
            if not worker.is_file():
                raise base.ControllerError(
                    f"candidate worker entry is missing at {candidate_ref}: {worker.relative_to(probe_dir)}"
                )
            worker_result = base.run(
                [self.cfg.python, str(worker), "version"],
                cwd=probe_dir, check=False, timeout=180,
            )
            if worker_result.returncode != 0:
                detail = (worker_result.stderr or worker_result.stdout).strip()
                raise base.ControllerError(
                    f"candidate worker version probe failed at {candidate_ref}: {detail[-6000:]}"
                )
            worker_version = base.worker_version_from_stdout(worker_result.stdout)

            controller_entry = probe_dir / "tool/kris_qwen_control.py.compat.py"
            controller_source = probe_dir / "tool/kris_qwen_control.py"
            if not controller_entry.is_file() or not controller_source.is_file():
                raise base.ControllerError(
                    f"candidate controller runtime sources are missing at {candidate_ref}"
                )
            controller_result = base.run(
                [self.cfg.python, str(controller_entry), "--version"],
                cwd=probe_dir, check=False, timeout=120,
            )
            if controller_result.returncode != 0:
                detail = (controller_result.stderr or controller_result.stdout).strip()
                raise base.ControllerError(
                    f"candidate controller version probe failed at {candidate_ref}: {detail[-6000:]}"
                )
            controller_version = controller_result.stdout.strip()
            if not controller_version:
                raise base.ControllerError(
                    f"candidate controller returned an empty version at {candidate_ref}"
                )
            return {
                "workerVersion": worker_version,
                "controllerVersion": controller_version,
                "controllerRuntimeSha256": controller_runtime_fingerprint(
                    controller_entry, controller_source
                ),
                "candidate": candidate_ref,
            }
        finally:
            if added:
                self._git(
                    "worktree", "remove", "--force", str(probe_dir),
                    check=False, timeout=180,
                )
            shutil.rmtree(probe_dir, ignore_errors=True)

    def _auto_update_preflight(self, local: str, advertised_remote: str) -> dict:
        dirty = self._git("status", "--porcelain", "--untracked-files=all").stdout.strip()
        if dirty:
            return {
                "status": "UPDATE_BLOCKED_DIRTY",
                "local": local,
                "remote": advertised_remote,
                "detail": dirty[:6000],
            }

        self._git("fetch", "origin", self.cfg.repo_branch, "--prune", timeout=900)
        fetched_remote = self._git("rev-parse", f"origin/{self.cfg.repo_branch}").stdout.strip()
        if fetched_remote == local:
            return {"status": "CURRENT", "local": local, "remote": fetched_remote}
        ancestor = self._git(
            "merge-base", "--is-ancestor", local, fetched_remote,
            check=False,
        )
        if ancestor.returncode != 0:
            return {
                "status": "UPDATE_BLOCKED_NON_FAST_FORWARD",
                "local": local,
                "remote": fetched_remote,
            }
        try:
            probe = self._probe_candidate_entries(fetched_remote)
        except Exception as exc:
            return {
                "status": "UPDATE_BLOCKED_CANDIDATE_INVALID",
                "local": local,
                "remote": fetched_remote,
                "detail": str(exc)[:6000],
            }
        return {
            "status": "UPDATE_READY",
            "local": local,
            "remote": fetched_remote,
            "probe": probe,
        }

    def _fast_forward_validated(self, expected_remote: str) -> dict:
        self._record_operation(state="FETCHING", kind="FETCH_LATEST_AND_RUN")
        self._validate_repo()
        dirty = self._git("status", "--porcelain", "--untracked-files=all").stdout.strip()
        if dirty:
            raise base.ControllerError(
                "validated update aborted because checkout became dirty before fast-forward:\n"
                + dirty[:6000]
            )
        before = self._git_head()
        live_remote = self._remote_branch_head()
        if live_remote != expected_remote:
            raise base.ControllerError(
                "validated update aborted because remote moved during graceful drain: "
                f"validated={expected_remote} live={live_remote}"
            )
        ancestor = self._git(
            "merge-base", "--is-ancestor", before, expected_remote,
            check=False,
        )
        if ancestor.returncode != 0:
            raise base.ControllerError(
                f"validated candidate is no longer a fast-forward: local={before} candidate={expected_remote}"
            )
        if before == expected_remote:
            return {"before": before, "after": before, "changed": False}
        self._record_operation(
            state="UPDATING", kind="FETCH_LATEST_AND_RUN",
            before=before, remote=expected_remote,
        )
        self._git("merge", "--ff-only", expected_remote, timeout=900)
        after = self._git_head()
        if after != expected_remote:
            raise base.ControllerError(
                f"fast-forward did not reach validated candidate: expected={expected_remote} actual={after}"
            )
        return {"before": before, "after": after, "changed": True}

    def _controller_reload_required(self, probe: dict | None) -> bool:
        if not isinstance(probe, dict):
            return False
        candidate = str(probe.get("controllerRuntimeSha256") or "")
        return bool(candidate and candidate != self.controller_runtime_sha256)

    def _exit_for_supervisor_restart(self) -> None:
        time.sleep(0.75)
        os._exit(0)

    def _fetch_latest_and_run_job(self) -> None:
        git_result = None
        update_probe = None
        try:
            self._validate_repo()
            local = self._git_head()
            advertised_remote = self._remote_branch_head()
            validated_remote = local
            if advertised_remote != local:
                preflight = self._auto_update_preflight(local, advertised_remote)
                if preflight.get("status") != "UPDATE_READY":
                    raise base.ControllerError(
                        f"{preflight.get('status')}: {preflight.get('detail') or preflight}"
                    )
                validated_remote = str(preflight["remote"])
                update_probe = preflight.get("probe")

            pid = self.worker_pid()
            if pid:
                self.request_safe_stop("Fetch latest + run requested from phone control")
            self._wait_for_worker_exit(pid)
            git_result = self._fast_forward_validated(validated_remote)
            self._record_operation(
                state="STARTING", kind="FETCH_LATEST_AND_RUN",
                git=git_result, candidateProbe=update_probe,
            )
            with self.lock:
                started = self._start_worker_unlocked()
            reload_required = self._controller_reload_required(update_probe)
            self._record_operation(
                state="IDLE", kind="FETCH_LATEST_AND_RUN", git=git_result,
                candidateProbe=update_probe, result=started,
                controllerReloadRequired=reload_required,
                controllerSupervisorRestart=self.self_restart_on_update and reload_required,
                completedAt=base.utc_iso(), error=None,
            )
            if reload_required and self.self_restart_on_update:
                threading.Thread(
                    target=self._exit_for_supervisor_restart,
                    name="kris-qwen-controller-supervisor-restart",
                    daemon=True,
                ).start()
        except Exception as exc:
            recovery = None
            recovery_error = None
            try:
                if not self.worker_pid():
                    with self.lock:
                        recovery = self._start_worker_unlocked()
            except Exception as restart_exc:
                recovery_error = str(restart_exc)
            self._record_operation(
                state="ERROR", kind="FETCH_LATEST_AND_RUN",
                git=git_result, candidateProbe=update_probe,
                recovery=recovery, recoveryError=recovery_error,
                error=str(exc), completedAt=base.utc_iso(),
            )

    def _auto_update_once(self) -> dict:
        if self.operation_running():
            return {"status": "BUSY"}
        if not self.auto_run_enabled:
            return {"status": "PAUSED"}
        self._validate_repo()
        local = self._git_head()
        remote = self._remote_branch_head()
        if remote != local:
            preflight = self._auto_update_preflight(local, remote)
            if preflight["status"] != "UPDATE_READY":
                return preflight
            queued = super().fetch_latest_and_run()
            return {
                **queued,
                "status": "UPDATE_QUEUED",
                "local": local,
                "remote": preflight["remote"],
                "probe": preflight.get("probe"),
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

    def _remember_auto_update(self, result: dict) -> None:
        self.last_auto_update = {"at": base.utc_iso(), **result}

    def _auto_update_loop(self) -> None:
        time.sleep(1.0)
        while True:
            try:
                self._remember_auto_update(self._auto_update_once())
            except Exception as exc:
                self._remember_auto_update({"status": "ERROR", "error": str(exc)})
                if not self.operation_running():
                    self._record_operation(
                        state="ERROR",
                        kind="AUTO_UPDATE",
                        error=str(exc),
                    )
            time.sleep(self.auto_update_seconds)

    def status(self):
        result = super().status()
        result["controlVersion"] = TARGET_CONTROL_VERSION
        result["controllerVersion"] = TARGET_CONTROL_VERSION
        result["controllerRuntimeSha256"] = self.controller_runtime_sha256
        result["peerPolicy"] = "loopback-private-lan-vpn-tailscale-only"
        result["autoUpdate"] = {
            "enabled": self.auto_update_enabled,
            "intervalSeconds": self.auto_update_seconds,
            "autoRunEnabled": self.auto_run_enabled,
            "operatorIntent": dict(self.auto_run_state),
            "operatorIntentPath": str(self.auto_run_state_path),
            "operatorIntentError": self.auto_run_state_error,
            "selfRestartOnControllerUpdate": self.self_restart_on_update,
            "last": self.last_auto_update,
        }
        return result


base.QwenController = AlwaysOnQwenController


def main() -> int:
    return base.main()


if __name__ == "__main__":
    raise SystemExit(main())
