#!/usr/bin/env python3
"""Small localhost control plane for the KRIS local Qwen stack.

The service intentionally has no third-party Python dependencies. It stays up
while the repo-owned worker is started/stopped/refreshed underneath it.

Buttons/API:
  - Start: run ``kris_qwen_worker.py stack``.
  - Safe stop: use the worker's existing file-based graceful-stop protocol.
  - Refresh + restart: drain safely, fast-forward the configured Git branch,
    then start the updated repo-owned worker.

The HTTP listener is localhost-only by design. Use an SSH tunnel for remote UI
access instead of exposing this unauthenticated operational surface publicly.
"""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import hashlib
import json
import os
import pathlib
import secrets
import shlex
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Sequence
from urllib.parse import urlsplit

CONTROL_VERSION = "1.0.0"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8090
WORKER_RELATIVE_PATH = "tool/kris_qwen_worker.py"


def utc_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def atomic_write_json(path: pathlib.Path, value: dict[str, Any], mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".tmp-{os.getpid()}-{secrets.token_hex(4)}")
    tmp.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    with contextlib.suppress(OSError):
        os.chmod(tmp, mode)
    os.replace(tmp, path)


def read_json(path: pathlib.Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def run(
    argv: Sequence[str],
    *,
    cwd: pathlib.Path | None = None,
    check: bool = True,
    timeout: int = 120,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        list(argv),
        cwd=str(cwd) if cwd else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        env=env,
        check=False,
    )
    if check and result.returncode != 0:
        detail = (result.stdout + ("\n" if result.stdout and result.stderr else "") + result.stderr).strip()
        raise RuntimeError(f"command failed ({result.returncode}): {shlex.join(list(argv))}\n{detail[-8000:]}")
    return result


def pid_alive(pid: int | None) -> bool:
    if not isinstance(pid, int) or pid <= 1:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def pid_cmdline(pid: int) -> str:
    path = pathlib.Path(f"/proc/{pid}/cmdline")
    try:
        raw = path.read_bytes().replace(b"\0", b" ").decode("utf-8", errors="replace")
    except OSError:
        return ""
    return " ".join(raw.split())


def looks_like_qwen_worker(pid: int) -> bool:
    cmd = pid_cmdline(pid).lower()
    return "kris_qwen_worker" in cmd and "python" in cmd


def tail_text(path: pathlib.Path, max_bytes: int = 48_000, max_lines: int = 120) -> str:
    if not path.is_file():
        return ""
    try:
        with path.open("rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - max_bytes), os.SEEK_SET)
            data = fh.read().decode("utf-8", errors="replace")
    except OSError as exc:
        return f"unable to read log: {exc}"
    return "\n".join(data.splitlines()[-max_lines:])


@dataclass(frozen=True)
class ControllerConfig:
    repo_dir: pathlib.Path
    branch: str
    python_executable: str
    worker_script: pathlib.Path
    worker_root: pathlib.Path
    state_dir: pathlib.Path
    host: str
    port: int
    stop_timeout: int
    worker_extra_args: tuple[str, ...]

    @classmethod
    def from_env(cls, *, host: str | None = None, port: int | None = None) -> "ControllerConfig":
        script_repo = pathlib.Path(__file__).resolve().parents[1]
        repo_dir = pathlib.Path(os.environ.get("KRIS_QWEN_REPO_DIR", str(script_repo))).expanduser().resolve()
        branch = os.environ.get("KRIS_QWEN_REPO_BRANCH", "main").strip() or "main"
        python_executable = os.environ.get("KRIS_QWEN_PYTHON", sys.executable).strip() or sys.executable
        worker_raw = os.environ.get("KRIS_QWEN_WORKER_SCRIPT", WORKER_RELATIVE_PATH)
        worker_script = pathlib.Path(worker_raw).expanduser()
        if not worker_script.is_absolute():
            worker_script = repo_dir / worker_script
        worker_script = worker_script.resolve()
        worker_root = pathlib.Path(os.environ.get("KRIS_QWEN_ROOT", "~/kris-qwen-worker")).expanduser().resolve()
        state_dir = pathlib.Path(
            os.environ.get("KRIS_QWEN_CONTROL_STATE_DIR", str(worker_root / "controller"))
        ).expanduser().resolve()
        extra = tuple(shlex.split(os.environ.get("KRIS_QWEN_WORKER_ARGS", "")))
        return cls(
            repo_dir=repo_dir,
            branch=branch,
            python_executable=python_executable,
            worker_script=worker_script,
            worker_root=worker_root,
            state_dir=state_dir,
            host=host or os.environ.get("KRIS_QWEN_CONTROL_HOST", DEFAULT_HOST),
            port=int(port if port is not None else os.environ.get("KRIS_QWEN_CONTROL_PORT", str(DEFAULT_PORT))),
            stop_timeout=max(30, int(os.environ.get("KRIS_QWEN_STOP_TIMEOUT", "1800"))),
            worker_extra_args=extra,
        )


class QwenController:
    def __init__(self, cfg: ControllerConfig):
        self.cfg = cfg
        if cfg.host not in {"127.0.0.1", "localhost", "::1"}:
            raise RuntimeError(
                "kris_qwen_control refuses a non-loopback listener. Use SSH port forwarding or a protected reverse proxy."
            )
        self.cfg.state_dir.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._operation_thread: threading.Thread | None = None
        self._operation = read_json(self.operation_path) or {
            "state": "IDLE",
            "kind": None,
            "updatedAt": utc_iso(),
        }
        self._token = self._load_or_create_token()

    @property
    def token_path(self) -> pathlib.Path:
        return self.cfg.state_dir / "control-token"

    @property
    def process_path(self) -> pathlib.Path:
        return self.cfg.state_dir / "worker-process.json"

    @property
    def operation_path(self) -> pathlib.Path:
        return self.cfg.state_dir / "operation.json"

    @property
    def log_path(self) -> pathlib.Path:
        return self.cfg.state_dir / "worker-stack.log"

    @property
    def operator_status_path(self) -> pathlib.Path:
        return self.cfg.worker_root / "operator" / "status.json"

    @property
    def stop_request_path(self) -> pathlib.Path:
        return self.cfg.worker_root / "operator" / "stop-request.json"

    def _load_or_create_token(self) -> str:
        if self.token_path.is_file():
            token = self.token_path.read_text(encoding="utf-8").strip()
            if len(token) >= 32:
                return token
        token = secrets.token_urlsafe(32)
        self.token_path.write_text(token + "\n", encoding="utf-8", newline="\n")
        with contextlib.suppress(OSError):
            os.chmod(self.token_path, 0o600)
        return token

    def verify_token(self, supplied: str | None) -> bool:
        return bool(supplied) and secrets.compare_digest(str(supplied), self._token)

    def _record_operation(self, **values: Any) -> None:
        with self._lock:
            current = dict(self._operation)
            current.update(values)
            current["updatedAt"] = utc_iso()
            self._operation = current
            atomic_write_json(self.operation_path, current)

    def _worker_command(self) -> list[str]:
        return [
            self.cfg.python_executable,
            str(self.cfg.worker_script),
            "stack",
            "--root",
            str(self.cfg.worker_root),
            *self.cfg.worker_extra_args,
        ]

    def _git(self, *args: str, check: bool = True, timeout: int = 300) -> subprocess.CompletedProcess[str]:
        return run(["git", *args], cwd=self.cfg.repo_dir, check=check, timeout=timeout)

    def _git_head(self) -> str | None:
        result = self._git("rev-parse", "HEAD", check=False)
        return result.stdout.strip() if result.returncode == 0 else None

    def _git_branch(self) -> str | None:
        result = self._git("branch", "--show-current", check=False)
        return result.stdout.strip() if result.returncode == 0 else None

    def _process_record(self) -> dict[str, Any] | None:
        row = read_json(self.process_path)
        if not row:
            return None
        pid = row.get("pid")
        if isinstance(pid, int) and pid_alive(pid) and looks_like_qwen_worker(pid):
            return row
        with contextlib.suppress(OSError):
            self.process_path.unlink()
        return None

    def _operator_worker_pid(self) -> int | None:
        row = read_json(self.operator_status_path)
        if not row:
            return None
        pid = row.get("pid")
        if isinstance(pid, int) and pid_alive(pid) and looks_like_qwen_worker(pid):
            return pid
        return None

    def worker_pid(self) -> int | None:
        record = self._process_record()
        if record and isinstance(record.get("pid"), int):
            return int(record["pid"])
        return self._operator_worker_pid()

    def _validate_start_prerequisites(self) -> None:
        if not (self.cfg.repo_dir / ".git").exists():
            raise RuntimeError(f"not a Git checkout: {self.cfg.repo_dir}")
        if not self.cfg.worker_script.is_file():
            raise RuntimeError(f"repo-owned worker script is missing: {self.cfg.worker_script}")
        if self._git_branch() != self.cfg.branch:
            raise RuntimeError(
                f"repo must be on configured branch {self.cfg.branch!r}; current={self._git_branch()!r}"
            )

    def _clear_stale_stop(self) -> None:
        # Keep lifecycle control independent of the worker source being refreshed.
        # This is the same file protocol implemented by kris_qwen_worker.py.
        with contextlib.suppress(FileNotFoundError):
            self.stop_request_path.unlink()

    def _request_stop_file(self, reason: str) -> dict[str, Any]:
        row = {
            "schemaVersion": 1,
            "requestedAt": utc_iso(),
            "requestedByPid": os.getpid(),
            "source": "kris-qwen-control",
            "mode": "GRACEFUL",
            "reason": str(reason)[:1000],
        }
        atomic_write_json(self.stop_request_path, row)
        return row

    def _validate_worker_entrypoint(self) -> None:
        result = run(
            [self.cfg.python_executable, str(self.cfg.worker_script), "version"],
            cwd=self.cfg.repo_dir,
            check=False,
            timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(
                "worker entrypoint failed its version probe; refusing to start:\n"
                + (result.stderr or result.stdout).strip()[-4000:]
            )

    def _start_worker_unlocked(self) -> dict[str, Any]:
        self._validate_start_prerequisites()
        self._validate_worker_entrypoint()
        existing = self.worker_pid()
        if existing:
            return {"status": "ALREADY_RUNNING", "pid": existing}
        self._clear_stale_stop()
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        log_fh = self.log_path.open("a", encoding="utf-8", buffering=1)
        log_fh.write(f"\n=== {utc_iso()} controller start ===\n")
        command = self._worker_command()
        env = dict(os.environ)
        env["KRIS_QWEN_ROOT"] = str(self.cfg.worker_root)
        try:
            proc = subprocess.Popen(
                command,
                cwd=str(self.cfg.repo_dir),
                stdout=log_fh,
                stderr=subprocess.STDOUT,
                text=True,
                start_new_session=True,
                env=env,
            )
        except Exception:
            log_fh.close()
            raise
        # Popen has duplicated/inherited the FD; controller does not need to retain it.
        log_fh.close()
        time.sleep(0.15)
        if proc.poll() is not None:
            raise RuntimeError(
                f"worker stack exited immediately with code {proc.returncode}; see {self.log_path}"
            )
        row = {
            "schemaVersion": 1,
            "pid": proc.pid,
            "startedAt": utc_iso(),
            "command": command,
            "repoHead": self._git_head(),
            "repoBranch": self._git_branch(),
            "workerScript": str(self.cfg.worker_script),
        }
        atomic_write_json(self.process_path, row)
        threading.Thread(
            target=self._reap_worker_child,
            args=(proc,),
            name=f"kris-qwen-reaper-{proc.pid}",
            daemon=True,
        ).start()
        return {"status": "STARTED", "pid": proc.pid, "repoHead": row["repoHead"]}

    def _reap_worker_child(self, proc: subprocess.Popen[str]) -> None:
        """Wait owned worker children so exited stack processes never remain zombies."""
        returncode = proc.wait()
        with self._lock:
            row = read_json(self.process_path)
            if row and row.get("pid") == proc.pid:
                with contextlib.suppress(OSError):
                    self.process_path.unlink()
            # Preserve a running refresh operation's state; otherwise expose the
            # natural child exit for the dashboard without manufacturing an error.
            if not self.operation_running():
                self._record_operation(
                    state="IDLE",
                    kind="WORKER_EXIT",
                    result={"pid": proc.pid, "returncode": returncode},
                    error=None,
                )

    def start_worker(self) -> dict[str, Any]:
        with self._lock:
            if self.operation_running():
                raise RuntimeError("another controller operation is already running")
            result = self._start_worker_unlocked()
            self._record_operation(state="IDLE", kind="START", result=result, error=None)
            return result

    def request_graceful_stop(self, reason: str = "Qwen control panel safe stop") -> dict[str, Any]:
        with self._lock:
            request = self._request_stop_file(reason)
            pid = self.worker_pid()
            self._record_operation(
                state="STOP_REQUESTED" if pid else "IDLE",
                kind="STOP",
                pid=pid,
                error=None,
                result={"status": "STOP_REQUESTED", "pid": pid, "request": request},
            )
            return {"status": "STOP_REQUESTED", "pid": pid}

    def operation_running(self) -> bool:
        thread = self._operation_thread
        return bool(thread and thread.is_alive())

    def refresh_and_restart(self) -> dict[str, Any]:
        with self._lock:
            if self.operation_running():
                raise RuntimeError("another controller operation is already running")
            thread = threading.Thread(target=self._refresh_restart_job, name="kris-qwen-refresh", daemon=True)
            self._operation_thread = thread
            self._record_operation(state="QUEUED", kind="REFRESH_RESTART", error=None, result=None)
            thread.start()
            return {"status": "QUEUED"}

    def _wait_for_worker_exit(self, pid: int | None, timeout: int) -> None:
        if not pid:
            return
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not pid_alive(pid) or not looks_like_qwen_worker(pid):
                with contextlib.suppress(OSError):
                    self.process_path.unlink()
                return
            self._record_operation(state="DRAINING", kind="REFRESH_RESTART", pid=pid)
            time.sleep(1.0)
        raise RuntimeError(
            f"safe stop timed out after {timeout}s; worker PID {pid} was NOT hard-killed. Resolve it manually before refresh."
        )

    def _refresh_repo_fast_forward(self) -> dict[str, Any]:
        self._record_operation(state="REFRESHING_GIT", kind="REFRESH_RESTART")
        self._validate_start_prerequisites()
        dirty = self._git("status", "--porcelain", "--untracked-files=all").stdout.strip()
        if dirty:
            raise RuntimeError("refusing refresh because the server checkout is dirty:\n" + dirty[:4000])
        before = self._git_head()
        self._git("fetch", "origin", self.cfg.branch, "--prune", timeout=900)
        remote = self._git("rev-parse", f"origin/{self.cfg.branch}").stdout.strip()
        if before == remote:
            return {"before": before, "after": before, "changed": False}
        ancestor = self._git("merge-base", "--is-ancestor", str(before), remote, check=False)
        if ancestor.returncode != 0:
            raise RuntimeError(
                f"refusing non-fast-forward refresh: local {before} is not an ancestor of origin/{self.cfg.branch} {remote}"
            )
        self._git("merge", "--ff-only", f"origin/{self.cfg.branch}", timeout=900)
        after = self._git_head()
        if after != remote:
            raise RuntimeError(f"fast-forward did not reach fetched remote head: expected={remote} actual={after}")
        return {"before": before, "after": after, "changed": before != after}

    def _refresh_restart_job(self) -> None:
        try:
            self._record_operation(state="STOPPING", kind="REFRESH_RESTART", startedAt=utc_iso(), error=None)
            pid = self.worker_pid()
            if pid:
                self._request_stop_file("Refresh + restart requested from Qwen control panel")
            self._wait_for_worker_exit(pid, self.cfg.stop_timeout)
            git_result = self._refresh_repo_fast_forward()
            self._record_operation(state="STARTING", kind="REFRESH_RESTART", git=git_result)
            with self._lock:
                started = self._start_worker_unlocked()
            self._record_operation(
                state="IDLE",
                kind="REFRESH_RESTART",
                completedAt=utc_iso(),
                git=git_result,
                result=started,
                error=None,
            )
        except Exception as exc:
            self._record_operation(
                state="ERROR",
                kind="REFRESH_RESTART",
                completedAt=utc_iso(),
                error=str(exc),
            )

    def git_status(self) -> dict[str, Any]:
        try:
            branch = self._git_branch()
            head = self._git_head()
            dirty_result = self._git("status", "--porcelain", "--untracked-files=all", check=False)
            dirty = bool(dirty_result.stdout.strip()) if dirty_result.returncode == 0 else None
            return {"branch": branch, "head": head, "dirty": dirty}
        except Exception as exc:
            return {"error": str(exc)}

    def worker_script_status(self) -> dict[str, Any]:
        if not self.cfg.worker_script.is_file():
            return {"exists": False, "path": str(self.cfg.worker_script)}
        data = self.cfg.worker_script.read_bytes()
        version = None
        for line in data.decode("utf-8", errors="replace").splitlines()[:100]:
            if line.startswith("SCRIPT_VERSION") and "=" in line:
                version = line.split("=", 1)[1].strip().strip("'\"")
                break
        return {
            "exists": True,
            "path": str(self.cfg.worker_script),
            "version": version,
            "sha256": hashlib.sha256(data).hexdigest(),
        }

    def status(self) -> dict[str, Any]:
        pid = self.worker_pid()
        operator = read_json(self.operator_status_path)
        process = self._process_record()
        operation = dict(self._operation)
        if operation.get("state") == "STOP_REQUESTED" and not pid:
            operation["state"] = "IDLE"
        return {
            "controlVersion": CONTROL_VERSION,
            "at": utc_iso(),
            "controllerPid": os.getpid(),
            "listener": f"http://{self.cfg.host}:{self.cfg.port}",
            "worker": {
                "running": bool(pid),
                "pid": pid,
                "managedProcess": process,
                "operatorStatus": operator,
                "stopRequest": read_json(self.stop_request_path),
            },
            "operation": operation,
            "git": self.git_status(),
            "workerScript": self.worker_script_status(),
            "logPath": str(self.log_path),
            "logTail": tail_text(self.log_path),
        }


DASHBOARD_HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>KRIS Qwen Worker</title>
<style>
:root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; }
body { margin:0; background:#111318; color:#e9edf4; }
main { max-width:980px; margin:0 auto; padding:28px 18px 50px; }
h1 { margin:0 0 5px; font-size:26px; }
.sub { color:#9ca7b8; margin-bottom:22px; }
.card { background:#191d24; border:1px solid #2a303a; border-radius:14px; padding:18px; margin:12px 0; }
.controls { display:flex; gap:10px; flex-wrap:wrap; }
button { border:0; border-radius:9px; padding:11px 16px; font-weight:700; cursor:pointer; }
.start { background:#e9edf4; color:#111318; }
.stop { background:#343b47; color:#fff; }
.refresh { background:#5a6474; color:#fff; }
button:disabled { opacity:.45; cursor:not-allowed; }
.grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:10px; }
.k { color:#8e99aa; font-size:12px; text-transform:uppercase; letter-spacing:.08em; }
.v { margin-top:5px; word-break:break-word; }
.good { color:#86e3a6; } .bad { color:#ff9d9d; } .warn { color:#ffd283; }
pre { white-space:pre-wrap; overflow:auto; max-height:430px; background:#0d0f13; border-radius:10px; padding:14px; font-size:12px; line-height:1.45; }
#error { color:#ff9d9d; white-space:pre-wrap; }
</style>
</head>
<body><main>
<h1>KRIS Qwen Worker</h1>
<div class="sub">Persistent controller · repo-owned stack · safe drain · fast-forward refresh</div>
<div class="card controls">
<button class="start" id="start">Start worker</button>
<button class="stop" id="stop">Safe stop</button>
<button class="refresh" id="refresh">Refresh + restart</button>
</div>
<div id="error"></div>
<div class="card grid" id="summary"></div>
<div class="card"><div class="k">Last worker output</div><pre id="log">Loading…</pre></div>
<script>
const token = __TOKEN__;
const esc = v => String(v ?? '').replace(/[&<>\"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]));
async function api(path, method='GET') {
  const r = await fetch(path, {method, headers:{'X-Kris-Control-Token':token}});
  const body = await r.json();
  if (!r.ok) throw new Error(body.error || JSON.stringify(body));
  return body;
}
function cell(k,v,cls='') { return `<div><div class="k">${esc(k)}</div><div class="v ${cls}">${esc(v)}</div></div>`; }
async function refreshStatus() {
  try {
    const s = await api('/api/status');
    const w = s.worker || {}, op = s.operation || {}, git = s.git || {}, ws = w.operatorStatus || {};
    document.getElementById('summary').innerHTML =
      cell('Worker', w.running ? `RUNNING · PID ${w.pid}` : 'STOPPED', w.running ? 'good' : 'warn') +
      cell('Worker state', ws.state || '—', ws.state === 'BLOCKED_CONTROL_PLANE' ? 'bad' : '') +
      cell('Operation', `${op.kind || '—'} · ${op.state || 'IDLE'}`, op.state === 'ERROR' ? 'bad' : '') +
      cell('Git', `${git.branch || '?'} @ ${(git.head || '').slice(0,12)}${git.dirty ? ' · DIRTY' : ''}`, git.dirty ? 'bad' : '') +
      cell('Worker version', s.workerScript?.version || '—') +
      cell('Control', `v${s.controlVersion}`);
    document.getElementById('log').textContent = s.logTail || '(no controller-managed worker output yet)';
    document.getElementById('error').textContent = op.error || '';
    document.getElementById('start').disabled = !!w.running || ['QUEUED','STOPPING','DRAINING','REFRESHING_GIT','STARTING'].includes(op.state);
    document.getElementById('stop').disabled = !w.running;
    document.getElementById('refresh').disabled = ['QUEUED','STOPPING','DRAINING','REFRESHING_GIT','STARTING'].includes(op.state);
  } catch (e) { document.getElementById('error').textContent = e.message; }
}
async function act(path) {
  document.getElementById('error').textContent = '';
  try { await api(path,'POST'); } catch(e) { document.getElementById('error').textContent=e.message; }
  await refreshStatus();
}
document.getElementById('start').onclick=()=>act('/api/start');
document.getElementById('stop').onclick=()=>act('/api/stop');
document.getElementById('refresh').onclick=()=>act('/api/refresh-restart');
refreshStatus(); setInterval(refreshStatus, 2000);
</script>
</main></body></html>"""


class ControlHandler(BaseHTTPRequestHandler):
    server_version = "KrisQwenControl/1"

    @property
    def controller(self) -> QwenController:
        return self.server.controller  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write(f"[{utc_iso()}] {self.address_string()} {fmt % args}\n")

    def _json(self, status: int, value: dict[str, Any]) -> None:
        data = json.dumps(value, indent=2, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    def _authorized(self) -> bool:
        return self.controller.verify_token(self.headers.get("X-Kris-Control-Token"))

    def do_GET(self) -> None:  # noqa: N802
        path = urlsplit(self.path).path
        if path == "/":
            body = DASHBOARD_HTML.replace("__TOKEN__", json.dumps(self.controller._token)).encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-ancestors 'none'")
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/api/status":
            if not self._authorized():
                self._json(HTTPStatus.FORBIDDEN, {"error": "invalid control token"})
                return
            self._json(HTTPStatus.OK, self.controller.status())
            return
        self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if not self._authorized():
            self._json(HTTPStatus.FORBIDDEN, {"error": "invalid control token"})
            return
        path = urlsplit(self.path).path
        try:
            if path == "/api/start":
                result = self.controller.start_worker()
            elif path == "/api/stop":
                result = self.controller.request_graceful_stop()
            elif path == "/api/refresh-restart":
                result = self.controller.refresh_and_restart()
            else:
                self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
        except Exception as exc:
            self._json(HTTPStatus.CONFLICT, {"error": str(exc)})
            return
        self._json(HTTPStatus.ACCEPTED, result)


class ControlServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], controller: QwenController):
        self.controller = controller
        super().__init__(address, ControlHandler)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Localhost Start/Stop/Refresh controller for the KRIS Qwen worker stack")
    parser.add_argument("--host", default=None, help="listener host; loopback only")
    parser.add_argument("--port", type=int, default=None, help="listener port")
    parser.add_argument("--status", action="store_true", help="print one status snapshot and exit")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    cfg = ControllerConfig.from_env(host=args.host, port=args.port)
    controller = QwenController(cfg)
    if args.status:
        print(json.dumps(controller.status(), indent=2, sort_keys=True))
        return 0
    server = ControlServer((cfg.host, cfg.port), controller)
    print(
        json.dumps(
            {
                "status": "LISTENING",
                "url": f"http://{cfg.host}:{cfg.port}",
                "repo": str(cfg.repo_dir),
                "branch": cfg.branch,
                "worker": str(cfg.worker_script),
                "root": str(cfg.worker_root),
            },
            indent=2,
            sort_keys=True,
        ),
        flush=True,
    )
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
