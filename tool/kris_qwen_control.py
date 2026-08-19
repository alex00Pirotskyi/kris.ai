#!/usr/bin/env python3
"""Phone-friendly HTTP control plane for the current KRIS Qwen worker.

The controller is dependency-free and intentionally conservative:

* Start loads the repo-owned ``tool/kris_qwen_worker.py stack`` entry point.
* Safe stop uses the worker's own graceful control protocol.
* Fetch latest + run drains the worker, fast-forwards the configured Git branch,
  validates the refreshed worker entry point, then starts the new worker bytes.
* Remote HTTP is opt-in. The dashboard never embeds the control token.

For Internet access use a private VPN/Tailscale or an SSH tunnel. Plain HTTP is
intended only for a trusted LAN/VPN because the bearer token is not encrypted in
transit.
"""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import ipaddress
import json
import os
import pathlib
import secrets
import shlex
import socket
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Sequence
from urllib.parse import urlsplit

CONTROL_VERSION = "2.1.0"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8090
WORKER_RELATIVE_PATH = "tool/kris_qwen_worker.py"
ACTIVE_OPERATION_STATES = {"QUEUED", "DRAINING", "FETCHING", "UPDATING", "STARTING"}


class ControllerError(RuntimeError):
    pass


def utc_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def env_bool(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def run(argv: Sequence[str], *, cwd: pathlib.Path | None = None, check: bool = True,
        timeout: int = 120, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        list(argv), cwd=str(cwd) if cwd else None, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout,
        env=env, check=False,
    )
    if check and result.returncode != 0:
        detail = (result.stdout + ("\n" if result.stdout and result.stderr else "") + result.stderr).strip()
        raise ControllerError(
            f"command failed ({result.returncode}): {shlex.join(list(argv))}\n{detail[-12000:]}"
        )
    return result


def atomic_write_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".tmp-{os.getpid()}-{secrets.token_hex(4)}")
    tmp.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    with contextlib.suppress(OSError):
        os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def read_json(path: pathlib.Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def pid_alive(pid: int | None) -> bool:
    if not isinstance(pid, int) or pid <= 1:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def process_cmdline(pid: int) -> str:
    path = pathlib.Path(f"/proc/{pid}/cmdline")
    try:
        return path.read_bytes().replace(b"\0", b" ").decode("utf-8", errors="replace").strip()
    except OSError:
        return ""


def is_qwen_worker_pid(pid: int | None) -> bool:
    if not pid_alive(pid):
        return False
    cmd = process_cmdline(int(pid)).lower()
    return "kris_qwen_worker.py" in cmd and "python" in cmd


def tail_text(path: pathlib.Path, max_bytes: int = 64_000, max_lines: int = 180) -> str:
    if not path.is_file():
        return ""
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - max_bytes), os.SEEK_SET)
            text = handle.read().decode("utf-8", errors="replace")
    except OSError as exc:
        return f"unable to read log: {exc}"
    return "\n".join(text.splitlines()[-max_lines:])


def _hostname_from_header(raw: str) -> str:
    value = (raw or "").strip()
    if not value:
        return ""
    try:
        parsed = urlsplit("//" + value)
    except ValueError:
        return ""
    return (parsed.hostname or "").lower()


def _origin_hostname(raw: str | None) -> str:
    if not raw:
        return ""
    try:
        parsed = urlsplit(raw)
    except ValueError:
        return ""
    if parsed.scheme not in {"http", "https"}:
        return ""
    return (parsed.hostname or "").lower()


def same_origin(host_header: str, origin_or_referer: str | None) -> bool:
    host = _hostname_from_header(host_header)
    if not host:
        return False
    if not origin_or_referer:
        return True
    return _origin_hostname(origin_or_referer) == host


def is_loopback_host(value: str) -> bool:
    host = (value or "").strip().lower()
    if host == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def worker_version_from_stdout(stdout: str) -> str:
    text = stdout.strip()
    if not text:
        raise ControllerError("worker version command returned no output")
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        if len(text.split()) == 1:
            return text
        raise ControllerError("worker version command returned invalid output")
    if not isinstance(value, dict):
        raise ControllerError("worker version command returned non-object JSON")
    version = str(value.get("scriptVersion") or "").strip()
    if not version:
        raise ControllerError("worker version JSON is missing scriptVersion")
    return version


def discover_phone_urls(port: int) -> list[str]:
    candidates: set[str] = set()
    with contextlib.suppress(OSError):
        name = socket.gethostname()
        for _, _, addresses in socket.gethostbyname_ex(name):
            candidates.update(addresses)
    with contextlib.suppress(OSError):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.connect(("1.1.1.1", 80))
            candidates.add(sock.getsockname()[0])
        finally:
            sock.close()
    rows = []
    for raw in sorted(candidates):
        try:
            ip = ipaddress.ip_address(raw)
        except ValueError:
            continue
        if ip.is_loopback or ip.is_unspecified:
            continue
        rows.append(f"http://{ip.compressed}:{port}")
    return rows


@dataclass(frozen=True)
class ControlConfig:
    repo_dir: pathlib.Path
    repo_branch: str
    python: str
    worker_script: pathlib.Path
    worker_root: pathlib.Path
    state_dir: pathlib.Path
    host: str
    port: int
    allow_remote_http: bool
    stop_timeout: int
    worker_extra_args: tuple[str, ...]

    @classmethod
    def from_environment(cls, *, host: str | None = None, port: int | None = None,
                         allow_remote_http: bool | None = None) -> "ControlConfig":
        script_repo = pathlib.Path(__file__).resolve().parents[1]
        repo_dir = pathlib.Path(os.environ.get("KRIS_QWEN_REPO_DIR", str(script_repo))).expanduser().resolve()
        branch = os.environ.get("KRIS_QWEN_REPO_BRANCH", "main").strip() or "main"
        python = os.environ.get("KRIS_QWEN_PYTHON", sys.executable).strip() or sys.executable
        worker_raw = pathlib.Path(os.environ.get("KRIS_QWEN_WORKER_SCRIPT", WORKER_RELATIVE_PATH)).expanduser()
        worker_script = worker_raw if worker_raw.is_absolute() else repo_dir / worker_raw
        worker_root = pathlib.Path(os.environ.get("KRIS_QWEN_ROOT", "~/kris-qwen-worker")).expanduser().resolve()
        state_dir = pathlib.Path(
            os.environ.get("KRIS_QWEN_CONTROL_STATE_DIR", str(worker_root / "controller"))
        ).expanduser().resolve()
        resolved_host = host or os.environ.get("KRIS_QWEN_CONTROL_HOST", DEFAULT_HOST)
        resolved_allow = env_bool("KRIS_QWEN_CONTROL_ALLOW_REMOTE_HTTP", False)
        if allow_remote_http is not None:
            resolved_allow = allow_remote_http
        if not is_loopback_host(resolved_host) and not resolved_allow:
            raise ControllerError(
                "non-loopback HTTP requires explicit --allow-remote-http or "
                "KRIS_QWEN_CONTROL_ALLOW_REMOTE_HTTP=1"
            )
        resolved_port = int(port if port is not None else os.environ.get("KRIS_QWEN_CONTROL_PORT", str(DEFAULT_PORT)))
        if not 1 <= resolved_port <= 65535:
            raise ControllerError("invalid controller port")
        return cls(
            repo_dir=repo_dir, repo_branch=branch, python=python,
            worker_script=worker_script.resolve(), worker_root=worker_root,
            state_dir=state_dir, host=resolved_host, port=resolved_port,
            allow_remote_http=resolved_allow,
            stop_timeout=max(30, int(os.environ.get("KRIS_QWEN_STOP_TIMEOUT", "1800"))),
            worker_extra_args=tuple(shlex.split(os.environ.get("KRIS_QWEN_WORKER_ARGS", ""))),
        )


class QwenController:
    def __init__(self, cfg: ControlConfig):
        self.cfg = cfg
        self.cfg.state_dir.mkdir(parents=True, exist_ok=True)
        self.lock = threading.RLock()
        self.operation_thread: threading.Thread | None = None
        self.operation = read_json(self.operation_path) or {
            "state": "IDLE", "kind": None, "updatedAt": utc_iso(),
        }
        if self.operation.get("state") in ACTIVE_OPERATION_STATES:
            self.operation.update({
                "state": "INTERRUPTED",
                "error": "controller restarted during an active operation",
                "updatedAt": utc_iso(),
            })
            atomic_write_json(self.operation_path, self.operation)
        self.token = self._load_or_create_token()

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

    def _load_or_create_token(self) -> str:
        if self.token_path.is_file():
            token = self.token_path.read_text(encoding="utf-8").strip()
            if len(token) >= 32:
                return token
            raise ControllerError(f"invalid control token file: {self.token_path}")
        token = secrets.token_urlsafe(48)
        self.token_path.write_text(token + "\n", encoding="utf-8", newline="\n")
        with contextlib.suppress(OSError):
            os.chmod(self.token_path, 0o600)
        return token

    def verify_token(self, supplied: str | None) -> bool:
        return bool(supplied) and secrets.compare_digest(str(supplied), self.token)

    def _record_operation(self, **updates: Any) -> None:
        with self.lock:
            row = dict(self.operation)
            row.update(updates)
            row["updatedAt"] = utc_iso()
            self.operation = row
            atomic_write_json(self.operation_path, row)

    def _git(self, *args: str, check: bool = True, timeout: int = 300) -> subprocess.CompletedProcess[str]:
        return run(["git", *args], cwd=self.cfg.repo_dir, check=check, timeout=timeout)

    def _git_head(self) -> str:
        return self._git("rev-parse", "HEAD").stdout.strip()

    def _git_branch(self) -> str:
        return self._git("branch", "--show-current").stdout.strip()

    def _validate_repo(self) -> None:
        if not (self.cfg.repo_dir / ".git").exists():
            raise ControllerError(f"not a Git checkout: {self.cfg.repo_dir}")
        branch = self._git_branch()
        if branch != self.cfg.repo_branch:
            raise ControllerError(
                f"server checkout must be on configured branch {self.cfg.repo_branch!r}; current={branch!r}"
            )

    def worker_version(self) -> str:
        if not self.cfg.worker_script.is_file():
            raise ControllerError(f"worker script is missing: {self.cfg.worker_script}")
        result = run(
            [self.cfg.python, str(self.cfg.worker_script), "version"],
            cwd=self.cfg.repo_dir, check=False, timeout=30,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip()
            raise ControllerError(f"worker version probe failed: {detail[-4000:]}")
        return worker_version_from_stdout(result.stdout)

    def preflight(self) -> dict[str, Any]:
        self._validate_repo()
        version = self.worker_version()
        auth = run(["gh", "auth", "status", "--hostname", "github.com"], check=False, timeout=30)
        if auth.returncode != 0:
            raise ControllerError(
                "GitHub CLI authentication is not usable by this server process: "
                + (auth.stderr or auth.stdout).strip()[-4000:]
            )
        return {
            "workerVersion": version, "githubAuth": "ok",
            "repoBranch": self.cfg.repo_branch, "repoHead": self._git_head(),
        }

    def _process_record(self) -> dict[str, Any] | None:
        row = read_json(self.process_path)
        if not row:
            return None
        pid = row.get("pid")
        if isinstance(pid, int) and is_qwen_worker_pid(pid):
            return row
        with contextlib.suppress(OSError):
            self.process_path.unlink()
        return None

    def _operator_pid(self) -> int | None:
        row = read_json(self.operator_status_path)
        if not row:
            return None
        pid = row.get("pid")
        return int(pid) if isinstance(pid, int) and is_qwen_worker_pid(pid) else None

    def worker_pid(self) -> int | None:
        row = self._process_record()
        if row and isinstance(row.get("pid"), int):
            return int(row["pid"])
        return self._operator_pid()

    def _worker_command(self) -> list[str]:
        return [
            self.cfg.python, str(self.cfg.worker_script), "stack",
            "--root", str(self.cfg.worker_root), *self.cfg.worker_extra_args,
        ]

    def _clear_stale_stop(self) -> None:
        path = self.cfg.worker_root / "operator" / "stop-request.json"
        with contextlib.suppress(FileNotFoundError):
            path.unlink()

    def _start_worker_unlocked(self) -> dict[str, Any]:
        preflight = self.preflight()
        existing = self.worker_pid()
        if existing:
            return {"status": "ALREADY_RUNNING", "pid": existing, "preflight": preflight}
        self._clear_stale_stop()
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        log = self.log_path.open("a", encoding="utf-8", buffering=1)
        log.write(f"\n=== {utc_iso()} controller start ===\n")
        command = self._worker_command()
        env = dict(os.environ)
        env["KRIS_QWEN_ROOT"] = str(self.cfg.worker_root)
        try:
            process = subprocess.Popen(
                command, cwd=str(self.cfg.repo_dir), stdout=log,
                stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                text=True, start_new_session=True, env=env,
            )
        except Exception:
            log.close()
            raise
        log.close()
        time.sleep(0.25)
        if process.poll() is not None:
            raise ControllerError(
                f"worker stack exited immediately with code {process.returncode}; see {self.log_path}"
            )
        row = {
            "schemaVersion": 1, "pid": process.pid, "startedAt": utc_iso(),
            "command": command, "repoHead": self._git_head(),
            "repoBranch": self._git_branch(), "workerVersion": preflight["workerVersion"],
        }
        atomic_write_json(self.process_path, row)
        threading.Thread(
            target=self._reap_child, args=(process,),
            name=f"kris-qwen-reaper-{process.pid}", daemon=True,
        ).start()
        return {"status": "STARTED", "pid": process.pid, "preflight": preflight}

    def _reap_child(self, process: subprocess.Popen[str]) -> None:
        returncode = process.wait()
        with self.lock:
            row = read_json(self.process_path)
            if row and row.get("pid") == process.pid:
                with contextlib.suppress(OSError):
                    self.process_path.unlink()
            if not self.operation_running():
                self._record_operation(
                    state="IDLE", kind="WORKER_EXIT",
                    result={"pid": process.pid, "returncode": returncode}, error=None,
                )

    def start(self) -> dict[str, Any]:
        with self.lock:
            if self.operation_running():
                raise ControllerError("another controller operation is already running")
            result = self._start_worker_unlocked()
            self._record_operation(state="IDLE", kind="START", result=result, error=None)
            return result

    def request_safe_stop(self, reason: str = "Qwen phone control safe stop") -> dict[str, Any]:
        pid = self.worker_pid()
        if not pid:
            return {"status": "ALREADY_STOPPED", "pid": None}
        result = run(
            [self.cfg.python, str(self.cfg.worker_script), "control", "stop",
             "--root", str(self.cfg.worker_root), "--reason", reason],
            cwd=self.cfg.repo_dir, check=False, timeout=30,
        )
        if result.returncode != 0:
            raise ControllerError(
                "worker graceful-stop request failed: "
                + (result.stderr or result.stdout).strip()[-4000:]
            )
        self._record_operation(
            state="STOP_REQUESTED", kind="STOP",
            result={"status": "STOP_REQUESTED", "pid": pid}, error=None,
        )
        return {"status": "STOP_REQUESTED", "pid": pid}

    def operation_running(self) -> bool:
        return bool(self.operation_thread and self.operation_thread.is_alive())

    def fetch_latest_and_run(self) -> dict[str, Any]:
        with self.lock:
            if self.operation_running():
                raise ControllerError("another controller operation is already running")
            self.operation_thread = threading.Thread(
                target=self._fetch_latest_and_run_job,
                name="kris-qwen-fetch-run", daemon=True,
            )
            self._record_operation(state="QUEUED", kind="FETCH_LATEST_AND_RUN", result=None, error=None)
            self.operation_thread.start()
            return {"status": "QUEUED"}

    def _wait_for_worker_exit(self, pid: int | None) -> None:
        if not pid:
            return
        deadline = time.monotonic() + self.cfg.stop_timeout
        while time.monotonic() < deadline:
            if not is_qwen_worker_pid(pid):
                with contextlib.suppress(OSError):
                    self.process_path.unlink()
                return
            self._record_operation(state="DRAINING", kind="FETCH_LATEST_AND_RUN", pid=pid)
            time.sleep(1.0)
        raise ControllerError(
            f"safe stop timed out after {self.cfg.stop_timeout}s; worker PID {pid} was not hard-killed"
        )

    def _fast_forward_repo(self) -> dict[str, Any]:
        self._record_operation(state="FETCHING", kind="FETCH_LATEST_AND_RUN")
        self._validate_repo()
        dirty = self._git("status", "--porcelain", "--untracked-files=all").stdout.strip()
        if dirty:
            raise ControllerError("refusing update because server checkout is dirty:\n" + dirty[:6000])
        before = self._git_head()
        self._git("fetch", "origin", self.cfg.repo_branch, "--prune", timeout=900)
        remote = self._git("rev-parse", f"origin/{self.cfg.repo_branch}").stdout.strip()
        if before == remote:
            return {"before": before, "after": before, "changed": False}
        ancestor = self._git("merge-base", "--is-ancestor", before, remote, check=False)
        if ancestor.returncode != 0:
            raise ControllerError(
                f"refusing non-fast-forward update: local={before} origin/{self.cfg.repo_branch}={remote}"
            )
        self._record_operation(
            state="UPDATING", kind="FETCH_LATEST_AND_RUN", before=before, remote=remote,
        )
        self._git("merge", "--ff-only", f"origin/{self.cfg.repo_branch}", timeout=900)
        after = self._git_head()
        if after != remote:
            raise ControllerError(
                f"fast-forward did not reach fetched remote head: expected={remote} actual={after}"
            )
        return {"before": before, "after": after, "changed": True}

    def _fetch_latest_and_run_job(self) -> None:
        try:
            pid = self.worker_pid()
            if pid:
                self.request_safe_stop("Fetch latest + run requested from phone control")
            self._wait_for_worker_exit(pid)
            git_result = self._fast_forward_repo()
            self._record_operation(state="STARTING", kind="FETCH_LATEST_AND_RUN", git=git_result)
            with self.lock:
                started = self._start_worker_unlocked()
            self._record_operation(
                state="IDLE", kind="FETCH_LATEST_AND_RUN", git=git_result,
                result=started, completedAt=utc_iso(), error=None,
            )
        except Exception as exc:
            self._record_operation(
                state="ERROR", kind="FETCH_LATEST_AND_RUN",
                error=str(exc), completedAt=utc_iso(),
            )

    def git_status(self) -> dict[str, Any]:
        try:
            self._validate_repo()
            dirty = bool(self._git("status", "--porcelain", "--untracked-files=all").stdout.strip())
            return {"branch": self._git_branch(), "head": self._git_head(), "dirty": dirty}
        except Exception as exc:
            return {"error": str(exc)}

    def status(self) -> dict[str, Any]:
        pid = self.worker_pid()
        worker_status = read_json(self.operator_status_path)
        version = None
        version_error = None
        try:
            version = self.worker_version()
        except Exception as exc:
            version_error = str(exc)
        return {
            "controlVersion": CONTROL_VERSION, "at": utc_iso(),
            "listener": f"http://{self.cfg.host}:{self.cfg.port}",
            "remoteHttpEnabled": self.cfg.allow_remote_http,
            "worker": {
                "running": bool(pid), "pid": pid, "version": version,
                "versionError": version_error, "operatorStatus": worker_status,
            },
            "operation": dict(self.operation), "git": self.git_status(),
            "logPath": str(self.log_path), "logTail": tail_text(self.log_path),
        }


DASHBOARD_HTML = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>KRIS Qwen Control</title><style nonce="__NONCE__">
:root{color-scheme:dark;font-family:Inter,ui-sans-serif,system-ui,sans-serif}*{box-sizing:border-box}body{margin:0;background:#0e1117;color:#edf2f7}main{max-width:900px;margin:0 auto;padding:22px 14px 44px}h1{font-size:25px;margin:0 0 6px}.sub{color:#9aa7b7;margin:0 0 18px;line-height:1.4}.card{background:#171c24;border:1px solid #29313c;border-radius:14px;padding:15px;margin:12px 0}.controls{display:grid;grid-template-columns:1fr;gap:10px}button,input{font:inherit;border-radius:10px}button{border:0;padding:14px 12px;font-weight:750;cursor:pointer}.primary{background:#e8eef8;color:#10151d}.secondary{background:#303946;color:#f4f7fb}.danger{background:#53323a;color:#ffeef1}button:disabled{opacity:.42;cursor:not-allowed}.token-row{display:flex;gap:8px}.token-row input{min-width:0;flex:1;background:#0f131a;color:#fff;border:1px solid #333d4a;padding:11px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}.k{font-size:11px;text-transform:uppercase;letter-spacing:.08em;color:#8795a7}.v{margin-top:5px;word-break:break-word}.good{color:#83e6a5}.warn{color:#ffd17c}.bad{color:#ff9696}#error{white-space:pre-wrap;color:#ff9696;margin:8px 2px}pre{white-space:pre-wrap;overflow:auto;max-height:430px;background:#090c11;border-radius:10px;padding:12px;font-size:12px;line-height:1.45}.note{font-size:12px;color:#9aa7b7;line-height:1.45}@media(min-width:620px){.controls{grid-template-columns:1.45fr 1fr 1fr}}
</style></head><body><main>
<h1>KRIS Qwen Control</h1><p class="sub">Fetch the latest repo-owned Qwen worker and run it from your phone.</p>
<div class="card"><div class="k">Control token</div><div class="token-row"><input id="tokenValue" type="password" autocomplete="off" placeholder="Paste token from server terminal"><button class="secondary" id="saveToken">Save</button></div><p class="note">Stored only in this browser tab. The server never embeds the token in this page.</p></div>
<div class="card controls"><button class="primary" id="fetchRun">Fetch latest + run Qwen</button><button class="secondary" id="start">Run current Qwen</button><button class="danger" id="stop">Safe stop</button></div><div id="error"></div><div class="card grid" id="summary"></div><div class="card"><div class="k">Recent worker output</div><pre id="log">Loading…</pre></div><p class="note">Use this over a trusted LAN/VPN. Do not expose plain HTTP directly to the public Internet.</p>
<script nonce="__NONCE__">
const q=s=>document.querySelector(s);const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));function token(){return sessionStorage.getItem('krisQwenControlToken')||''}q('#tokenValue').value=token();q('#saveToken').onclick=()=>{sessionStorage.setItem('krisQwenControlToken',q('#tokenValue').value.trim());refreshStatus()};async function api(path,method='GET'){const t=token();if(!t)throw new Error('Paste the control token first.');const r=await fetch(path,{method,headers:{'X-Kris-Control-Token':t}});const j=await r.json();if(!r.ok)throw new Error(j.error||JSON.stringify(j));return j}function cell(k,v,cls=''){return `<div><div class="k">${esc(k)}</div><div class="v ${cls}">${esc(v)}</div></div>`}async function refreshStatus(){try{const s=await api('/api/status');const w=s.worker||{},op=s.operation||{},git=s.git||{},ws=w.operatorStatus||{};q('#summary').innerHTML=cell('Worker',w.running?`RUNNING · PID ${w.pid}`:'STOPPED',w.running?'good':'warn')+cell('Worker state',ws.state||'—',String(ws.state||'').startsWith('BLOCKED')?'bad':'')+cell('Worker version',w.version||'—',w.versionError?'bad':'')+cell('Operation',`${op.kind||'—'} · ${op.state||'IDLE'}`,op.state==='ERROR'?'bad':'')+cell('Git',git.error?git.error:`${git.branch||'?'} @ ${(git.head||'').slice(0,12)}${git.dirty?' · DIRTY':''}`,git.dirty||git.error?'bad':'')+cell('Control',`v${s.controlVersion}`);q('#log').textContent=s.logTail||'(no controller-managed output yet)';q('#error').textContent=op.error||w.versionError||'';const busy=['QUEUED','DRAINING','FETCHING','UPDATING','STARTING'].includes(op.state);q('#fetchRun').disabled=busy;q('#start').disabled=busy||!!w.running;q('#stop').disabled=!w.running}catch(e){q('#error').textContent=e.message}}async function act(path){q('#error').textContent='';try{await api(path,'POST')}catch(e){q('#error').textContent=e.message}await refreshStatus()}q('#fetchRun').onclick=()=>act('/api/fetch-run');q('#start').onclick=()=>act('/api/start');q('#stop').onclick=()=>act('/api/stop');if(token())refreshStatus();setInterval(()=>{if(token())refreshStatus()},2500);
</script></main></body></html>"""


class ControlHandler(BaseHTTPRequestHandler):
    server_version = "KrisQwenControl/2.1"

    @property
    def controller(self) -> QwenController:
        return self.server.controller  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write(f"[{utc_iso()}] {self.address_string()} {fmt % args}\n")

    def _security_headers(self, nonce: str | None = None) -> None:
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        if nonce:
            self.send_header(
                "Content-Security-Policy",
                f"default-src 'none'; connect-src 'self'; style-src 'nonce-{nonce}'; "
                f"script-src 'nonce-{nonce}'; base-uri 'none'; frame-ancestors 'none'",
            )

    def _json(self, status: int, value: dict[str, Any]) -> None:
        data = json.dumps(value, indent=2, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self._security_headers()
        self.end_headers()
        self.wfile.write(data)

    def _authorized(self) -> bool:
        return self.controller.verify_token(self.headers.get("X-Kris-Control-Token"))

    def _origin_allowed(self) -> bool:
        host = self.headers.get("Host", "")
        source = self.headers.get("Origin") or self.headers.get("Referer")
        if not same_origin(host, source):
            return False
        if self.controller.cfg.allow_remote_http:
            return True
        return is_loopback_host(_hostname_from_header(host))

    def _guard(self) -> bool:
        if not self._origin_allowed():
            self._json(HTTPStatus.FORBIDDEN, {"error": "request origin/host is not allowed"})
            return False
        if not self._authorized():
            self._json(HTTPStatus.UNAUTHORIZED, {"error": "invalid control token"})
            return False
        return True

    def do_GET(self) -> None:  # noqa: N802
        path = urlsplit(self.path).path
        if path == "/":
            nonce = secrets.token_urlsafe(18)
            body = DASHBOARD_HTML.replace("__NONCE__", nonce).encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self._security_headers(nonce)
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/api/status":
            if not self._guard():
                return
            self._json(HTTPStatus.OK, self.controller.status())
            return
        self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if not self._guard():
            return
        path = urlsplit(self.path).path
        try:
            if path == "/api/start":
                value = self.controller.start()
            elif path == "/api/stop":
                value = self.controller.request_safe_stop()
            elif path == "/api/fetch-run":
                value = self.controller.fetch_latest_and_run()
            else:
                self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
        except Exception as exc:
            self._json(HTTPStatus.CONFLICT, {"error": str(exc), "status": self.controller.status()})
            return
        self._json(HTTPStatus.ACCEPTED, value)


class ControlServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], controller: QwenController):
        self.controller = controller
        super().__init__(address, ControlHandler)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=None, help="listener host")
    parser.add_argument("--port", type=int, default=None, help="listener port")
    parser.add_argument("--allow-remote-http", action="store_true", help="allow a non-loopback HTTP listener; use only on a trusted LAN/VPN")
    parser.add_argument("--phone", action="store_true", help="phone mode: bind 0.0.0.0 and allow remote HTTP on the trusted LAN/VPN")
    parser.add_argument("--status", action="store_true", help="print one status snapshot and exit")
    parser.add_argument("--version", action="store_true", help="print controller version and exit")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.version:
        print(CONTROL_VERSION)
        return 0
    host = "0.0.0.0" if args.phone else args.host
    allow_remote = True if args.phone else (True if args.allow_remote_http else None)
    cfg = ControlConfig.from_environment(host=host, port=args.port, allow_remote_http=allow_remote)
    controller = QwenController(cfg)
    if args.status:
        print(json.dumps(controller.status(), indent=2, sort_keys=True))
        return 0
    server = ControlServer((cfg.host, cfg.port), controller)
    urls = discover_phone_urls(cfg.port) if cfg.allow_remote_http else [f"http://{cfg.host}:{cfg.port}"]
    ready = {
        "status": "LISTENING", "controlVersion": CONTROL_VERSION,
        "repo": str(cfg.repo_dir), "branch": cfg.repo_branch,
        "worker": str(cfg.worker_script), "workerRoot": str(cfg.worker_root),
        "listenHost": cfg.host, "port": cfg.port, "urls": urls,
        "tokenFile": str(controller.token_path),
    }
    print(json.dumps(ready, indent=2, sort_keys=True), flush=True)
    if cfg.allow_remote_http:
        print("\nPHONE CONTROL TOKEN (keep private):", controller.token, flush=True)
        if urls:
            print("Open on phone:", urls[0], flush=True)
        print("Security: trusted LAN/VPN only. Do not expose this plain-HTTP port to the public Internet.", flush=True)
    try:
        server.serve_forever(poll_interval=0.4)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
