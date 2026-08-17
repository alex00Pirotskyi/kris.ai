#!/usr/bin/env python3
"""Localhost-only KRIS Qwen v6 service controller.

The production backend delegates model/worker lifecycle to systemd. A bounded
process backend remains for tests and controlled migration only.
"""
from __future__ import annotations

import argparse
import contextlib
import dataclasses
import datetime as dt
import http.server
import json
import os
import pathlib
import secrets
import shlex
import signal
import subprocess
import sys
import threading
import time
import urllib.parse
from collections import defaultdict, deque
from typing import Any, Mapping, Sequence

import kris_qwen_v6_guard as v6

CONTROL_VERSION = "2.0.0"
EXPECTED_WORKER_VERSION = "6.0.0"
MAX_REQUEST_BODY = 4096
MAX_OPERATIONS_PER_MINUTE = 12
LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1", "[::1]"}
ACTIVE_OPERATION_STATES = {"PREPARING", "RUNNING", "STOPPING", "REFRESHING"}


class ControllerError(RuntimeError):
    pass


def utc_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def run(
    argv: Sequence[str],
    *,
    cwd: pathlib.Path | None = None,
    env: Mapping[str, str] | None = None,
    check: bool = True,
    timeout: int = 120,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        list(argv),
        cwd=str(cwd) if cwd else None,
        env=dict(env) if env else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    if check and result.returncode != 0:
        output = (result.stdout + "\n" + result.stderr).strip()
        raise ControllerError(
            f"command failed ({result.returncode}): {shlex.join(list(argv))}\n{output[-12000:]}"
        )
    return result


def _loopback_host(raw: str) -> bool:
    if not raw:
        return False
    value = raw.strip().lower()
    if value.startswith("["):
        host = value.split("]", 1)[0] + "]"
    else:
        host = value.split(":", 1)[0]
    return host in LOOPBACK_HOSTS


def _loopback_origin(raw: str | None) -> bool:
    if not raw:
        return True
    try:
        parsed = urllib.parse.urlparse(raw)
    except ValueError:
        return False
    return parsed.scheme in {"http", "https"} and (parsed.hostname or "").lower() in {"127.0.0.1", "localhost", "::1"}


@dataclasses.dataclass(frozen=True)
class ControlConfig:
    repo_dir: pathlib.Path
    repo_branch: str
    python: pathlib.Path
    worker_root: pathlib.Path
    host: str
    port: int
    backend: str
    model_unit: str
    worker_unit: str
    stop_timeout: int
    token_path: pathlib.Path
    model_path: pathlib.Path
    sandbox_mode: str

    @property
    def controller_dir(self) -> pathlib.Path:
        return self.worker_root / "controller"

    @property
    def operation_path(self) -> pathlib.Path:
        return self.controller_dir / "operation.json"

    @property
    def process_path(self) -> pathlib.Path:
        return self.controller_dir / "process.json"

    @property
    def worker_script(self) -> pathlib.Path:
        return self.repo_dir / "tool/kris_qwen_worker.py"

    @classmethod
    def from_environment(cls) -> "ControlConfig":
        root = pathlib.Path(os.environ.get("KRIS_QWEN_ROOT", "/var/lib/kris-qwen")).expanduser().resolve()
        token_default = root / "controller/control-token"
        value = cls(
            repo_dir=pathlib.Path(os.environ.get("KRIS_QWEN_REPO_DIR", "/srv/kris-qwen/kris.ai")).expanduser().resolve(),
            repo_branch=os.environ.get("KRIS_QWEN_REPO_BRANCH", "agent/qwen-server-control-v6"),
            python=pathlib.Path(os.environ.get("KRIS_QWEN_PYTHON", sys.executable)).expanduser().resolve(),
            worker_root=root,
            host=os.environ.get("KRIS_QWEN_CONTROL_HOST", "127.0.0.1"),
            port=int(os.environ.get("KRIS_QWEN_CONTROL_PORT", "8090")),
            backend=os.environ.get("KRIS_QWEN_CONTROL_BACKEND", "systemd").strip().lower(),
            model_unit=os.environ.get("KRIS_QWEN_MODEL_UNIT", "kris-qwen-model.service"),
            worker_unit=os.environ.get("KRIS_QWEN_WORKER_UNIT", "kris-qwen-worker.service"),
            stop_timeout=int(os.environ.get("KRIS_QWEN_STOP_TIMEOUT", "1800")),
            token_path=pathlib.Path(os.environ.get("KRIS_QWEN_CONTROL_TOKEN_FILE", str(token_default))).expanduser().resolve(),
            model_path=pathlib.Path(os.environ.get("QWEN_GGUF_MODEL", "/models/Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf")).expanduser().resolve(),
            sandbox_mode=os.environ.get("KRIS_QWEN_MODEL_SANDBOX", "required"),
        )
        if value.host not in {"127.0.0.1", "::1", "localhost"}:
            raise ControllerError("KRIS Qwen control must remain loopback-only")
        if value.backend not in {"systemd", "process"}:
            raise ControllerError("KRIS_QWEN_CONTROL_BACKEND must be systemd or process")
        if not 1 <= value.port <= 65535:
            raise ControllerError("invalid controller port")
        return value


def _token(path: pathlib.Path) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        token = path.read_text(encoding="utf-8").strip()
        if len(token) < 32:
            raise ControllerError("control token file is invalid")
        return token
    token = secrets.token_urlsafe(48)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(token + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    return token


def git_status(repo: pathlib.Path) -> dict[str, Any]:
    if not (repo / ".git").exists():
        return {"present": False, "path": str(repo)}
    head = run(["git", "rev-parse", "HEAD"], cwd=repo, check=False).stdout.strip()
    branch = run(["git", "branch", "--show-current"], cwd=repo, check=False).stdout.strip()
    dirty = run(["git", "status", "--porcelain"], cwd=repo, check=False).stdout.splitlines()
    return {"present": True, "path": str(repo), "head": head, "branch": branch, "dirty": dirty}


class Backend:
    def status(self) -> dict[str, Any]:
        raise NotImplementedError

    def start(self) -> dict[str, Any]:
        raise NotImplementedError

    def stop(self) -> dict[str, Any]:
        raise NotImplementedError


class SystemdBackend(Backend):
    def __init__(self, cfg: ControlConfig):
        self.cfg = cfg

    def _unit(self, unit: str) -> dict[str, Any]:
        result = run(
            ["systemctl", "show", unit, "--property=LoadState,ActiveState,SubState,MainPID,ExecMainStatus", "--no-pager"],
            check=False,
            timeout=30,
        )
        values: dict[str, str] = {}
        for row in result.stdout.splitlines():
            if "=" in row:
                key, value = row.split("=", 1)
                values[key] = value
        return {"unit": unit, "returncode": result.returncode, **values}

    def status(self) -> dict[str, Any]:
        return {"backend": "systemd", "model": self._unit(self.cfg.model_unit), "worker": self._unit(self.cfg.worker_unit)}

    def _wait(self, unit: str, active: bool, timeout: int) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            state = self._unit(unit)
            is_active = state.get("ActiveState") == "active"
            if is_active == active:
                return
            if state.get("LoadState") == "not-found":
                raise ControllerError(f"systemd unit not found: {unit}")
            time.sleep(0.5)
        raise ControllerError(f"systemd unit did not reach {'active' if active else 'inactive'}: {unit}")

    def start(self) -> dict[str, Any]:
        run(["systemctl", "start", self.cfg.model_unit], timeout=60)
        self._wait(self.cfg.model_unit, True, 120)
        try:
            run(["systemctl", "start", self.cfg.worker_unit], timeout=60)
            self._wait(self.cfg.worker_unit, True, 120)
        except Exception:
            run(["systemctl", "stop", self.cfg.worker_unit], check=False, timeout=60)
            run(["systemctl", "stop", self.cfg.model_unit], check=False, timeout=60)
            raise
        return self.status()

    def stop(self) -> dict[str, Any]:
        run(["systemctl", "stop", self.cfg.worker_unit], check=False, timeout=self.cfg.stop_timeout)
        self._wait(self.cfg.worker_unit, False, self.cfg.stop_timeout)
        run(["systemctl", "stop", self.cfg.model_unit], check=False, timeout=180)
        self._wait(self.cfg.model_unit, False, 180)
        return self.status()


class ProcessBackend(Backend):
    """Migration/test backend; production deployment should use systemd."""

    def __init__(self, cfg: ControlConfig):
        self.cfg = cfg
        self.cfg.controller_dir.mkdir(parents=True, exist_ok=True)

    def _record(self) -> dict[str, Any] | None:
        if not self.cfg.process_path.is_file():
            return None
        try:
            row = json.loads(self.cfg.process_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        identity = v6.linux_process_identity(int(row.get("pid", 0)))
        if not v6.process_identity_matches(row.get("identity", {}), identity):
            return None
        return row

    def status(self) -> dict[str, Any]:
        row = self._record()
        return {"backend": "process", "running": row is not None, "process": row}

    def start(self) -> dict[str, Any]:
        if self._record():
            return self.status()
        env = dict(os.environ)
        env.setdefault("HOME", str(self.cfg.worker_root / "service-home"))
        env.setdefault("GIT_TERMINAL_PROMPT", "0")
        env.setdefault("KRIS_QWEN_MODEL_SANDBOX", self.cfg.sandbox_mode)
        log_path = self.cfg.controller_dir / "worker-stack.log"
        log = log_path.open("ab", buffering=0)
        process = subprocess.Popen(
            [str(self.cfg.python), str(self.cfg.worker_script), "stack", "--root", str(self.cfg.worker_root), "--model-sandbox", self.cfg.sandbox_mode],
            cwd=self.cfg.repo_dir,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        deadline = time.monotonic() + 20
        identity = None
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise ControllerError(f"worker exited during startup with code {process.returncode}")
            identity = v6.linux_process_identity(process.pid)
            status_path = self.cfg.worker_root / "operator/status.json"
            if identity and status_path.is_file():
                try:
                    state = json.loads(status_path.read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError):
                    state = {}
                if state.get("scriptVersion") == EXPECTED_WORKER_VERSION and state.get("state") not in {"FAILED", "STOPPED"}:
                    break
            time.sleep(0.25)
        if identity is None:
            process.terminate()
            raise ControllerError("worker did not publish a v6 readiness heartbeat")
        row = {"schemaVersion": 2, "pid": process.pid, "identity": identity.to_json(), "startedAt": utc_iso(), "log": str(log_path)}
        v6.atomic_write_json(self.cfg.process_path, row)
        return self.status()

    def stop(self) -> dict[str, Any]:
        row = self._record()
        if not row:
            self.cfg.process_path.unlink(missing_ok=True)
            return self.status()
        pid = int(row["pid"])
        run(
            [str(self.cfg.python), str(self.cfg.worker_script), "control", "stop", "--root", str(self.cfg.worker_root), "--reason", "controller safe stop"],
            cwd=self.cfg.repo_dir,
            check=False,
            timeout=30,
        )
        deadline = time.monotonic() + self.cfg.stop_timeout
        while time.monotonic() < deadline:
            if v6.linux_process_identity(pid) is None:
                break
            time.sleep(0.5)
        if v6.linux_process_identity(pid) is not None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(pid, signal.SIGTERM)
            time.sleep(2)
        if v6.linux_process_identity(pid) is not None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(pid, signal.SIGKILL)
        self.cfg.process_path.unlink(missing_ok=True)
        return self.status()


DASHBOARD_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>KRIS Qwen v6</title><style nonce="__NONCE__">
body{font:15px system-ui;margin:2rem;max-width:1000px;background:#10131a;color:#edf2ff}button{margin:.3rem;padding:.7rem 1rem}pre{background:#07090d;padding:1rem;overflow:auto;border-radius:.5rem}.bad{color:#ff8b8b}.good{color:#8bffb0}
</style></head><body><h1>KRIS Qwen v6</h1><p>The control token is never embedded in this page. It is kept only in this browser tab.</p>
<button id="token">Set token</button><button data-op="start">Start</button><button data-op="stop">Safe stop</button><button data-op="refresh-restart">Refresh & restart</button><pre id="out">Loading…</pre>
<script nonce="__NONCE__">
const out=document.getElementById('out');
function token(){return sessionStorage.getItem('krisQwenControlToken')||''}
function setToken(){const value=prompt('Paste /var/lib/kris-qwen/controller/control-token');if(value)sessionStorage.setItem('krisQwenControlToken',value.trim())}
document.getElementById('token').onclick=setToken;
async function call(path,method='GET'){let t=token();if(!t){setToken();t=token()}const r=await fetch(path,{method,headers:{'X-Kris-Control-Token':t}});const j=await r.json();out.textContent=JSON.stringify(j,null,2);out.className=r.ok?'good':'bad';return j}
for(const b of document.querySelectorAll('[data-op]'))b.onclick=()=>call('/api/'+b.dataset.op,'POST');
call('/api/status').catch(e=>{out.textContent=String(e);out.className='bad'});setInterval(()=>call('/api/status').catch(()=>{}),5000);
</script></body></html>"""


class Controller:
    def __init__(self, cfg: ControlConfig):
        self.cfg = cfg
        self.cfg.controller_dir.mkdir(parents=True, exist_ok=True)
        self.token = _token(cfg.token_path)
        self.lock = threading.Lock()
        self.rates: dict[str, deque[float]] = defaultdict(deque)
        self.backend: Backend = SystemdBackend(cfg) if cfg.backend == "systemd" else ProcessBackend(cfg)
        self._recover_operation()

    def _recover_operation(self) -> None:
        path = self.cfg.operation_path
        if not path.is_file():
            return
        try:
            row = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return
        if row.get("state") in ACTIVE_OPERATION_STATES:
            row.update({"state": "INTERRUPTED", "recoveredAt": utc_iso(), "backendStatus": self.backend.status()})
            v6.atomic_write_json(path, row)

    def preflight(self) -> dict[str, Any]:
        if not self.cfg.repo_dir.is_dir() or not self.cfg.worker_script.is_file():
            raise ControllerError("repository or v6 worker script is missing")
        if not self.cfg.python.is_file():
            raise ControllerError("configured Python interpreter is missing")
        if not self.cfg.model_path.is_file():
            raise ControllerError("configured GGUF model is missing")
        version = run([str(self.cfg.python), str(self.cfg.worker_script), "version"], cwd=self.cfg.repo_dir).stdout.strip()
        if version != EXPECTED_WORKER_VERSION:
            raise ControllerError(f"worker version mismatch: expected {EXPECTED_WORKER_VERSION}, got {version}")
        auth = run(["gh", "auth", "status", "--hostname", "github.com"], check=False, timeout=30)
        reason = v6.github_auth_failure(["gh", "auth", "status"], auth.stdout, auth.stderr, auth.returncode)
        if reason:
            raise ControllerError(reason)
        if auth.returncode != 0:
            raise ControllerError("GitHub CLI preflight failed: " + (auth.stderr or auth.stdout)[-4000:])
        if self.cfg.sandbox_mode == "required" and not shutil_which("bwrap"):
            raise ControllerError("bubblewrap is required for unattended v6 execution")
        return {"workerVersion": version, "githubAuth": "ok", "model": str(self.cfg.model_path), "sandbox": self.cfg.sandbox_mode}

    def status(self) -> dict[str, Any]:
        operation = None
        if self.cfg.operation_path.is_file():
            with contextlib.suppress(OSError, json.JSONDecodeError):
                operation = json.loads(self.cfg.operation_path.read_text(encoding="utf-8"))
        return {
            "schemaVersion": 2,
            "controllerVersion": CONTROL_VERSION,
            "workerExpectedVersion": EXPECTED_WORKER_VERSION,
            "at": utc_iso(),
            "backend": self.backend.status(),
            "git": git_status(self.cfg.repo_dir),
            "operation": operation,
            "tokenEmbeddedInHtml": False,
        }

    def _operation(self, kind: str, callback) -> dict[str, Any]:
        if not self.lock.acquire(blocking=False):
            raise ControllerError("another controller operation is already running")
        operation_id = f"op-{int(time.time())}-{secrets.token_hex(4)}"
        row = {"schemaVersion": 2, "operationId": operation_id, "kind": kind, "state": "PREPARING", "startedAt": utc_iso()}
        v6.atomic_write_json(self.cfg.operation_path, row)
        try:
            if kind in {"start", "refresh-restart"}:
                row["preflight"] = self.preflight()
            row["state"] = "RUNNING" if kind == "start" else "STOPPING" if kind == "stop" else "REFRESHING"
            v6.atomic_write_json(self.cfg.operation_path, row)
            result = callback()
            row.update({"state": "COMPLETED", "completedAt": utc_iso(), "result": result})
            v6.atomic_write_json(self.cfg.operation_path, row)
            return row
        except Exception as exc:
            row.update({"state": "FAILED", "failedAt": utc_iso(), "error": str(exc)[:12000]})
            v6.atomic_write_json(self.cfg.operation_path, row)
            raise
        finally:
            self.lock.release()

    def start(self) -> dict[str, Any]:
        return self._operation("start", self.backend.start)

    def stop(self) -> dict[str, Any]:
        return self._operation("stop", self.backend.stop)

    def refresh_restart(self) -> dict[str, Any]:
        def perform() -> dict[str, Any]:
            status = git_status(self.cfg.repo_dir)
            if status.get("dirty"):
                raise ControllerError("refusing refresh with a dirty repository")
            run(["git", "fetch", "origin", self.cfg.repo_branch], cwd=self.cfg.repo_dir, timeout=300)
            remote = run(["git", "rev-parse", f"origin/{self.cfg.repo_branch}"], cwd=self.cfg.repo_dir).stdout.strip()
            local = str(status.get("head") or "")
            ancestor = run(["git", "merge-base", "--is-ancestor", local, remote], cwd=self.cfg.repo_dir, check=False)
            if ancestor.returncode != 0:
                raise ControllerError("refusing non-fast-forward server refresh")
            before = self.backend.stop()
            try:
                run(["git", "merge", "--ff-only", remote], cwd=self.cfg.repo_dir, timeout=300)
                after = self.backend.start()
            except Exception:
                with contextlib.suppress(Exception):
                    self.backend.stop()
                raise
            return {"previous": before, "remoteHead": remote, "current": after}
        return self._operation("refresh-restart", perform)

    def allowed_rate(self, client: str) -> bool:
        now = time.monotonic()
        rows = self.rates[client]
        while rows and rows[0] < now - 60:
            rows.popleft()
        if len(rows) >= MAX_OPERATIONS_PER_MINUTE:
            return False
        rows.append(now)
        return True


def shutil_which(name: str) -> str | None:
    import shutil
    return shutil.which(name)


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "KrisQwenControl/2"

    @property
    def controller(self) -> Controller:
        return self.server.controller  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write(f"{self.address_string()} - {fmt % args}\n")

    def _security_headers(self, nonce: str | None = None) -> None:
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        if nonce:
            self.send_header("Content-Security-Policy", f"default-src 'none'; connect-src 'self'; style-src 'nonce-{nonce}'; script-src 'nonce-{nonce}'; base-uri 'none'; frame-ancestors 'none'")

    def _json(self, status: int, value: Any) -> None:
        data = json.dumps(value, indent=2, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self._security_headers()
        self.end_headers()
        self.wfile.write(data)

    def _authorized(self) -> bool:
        supplied = self.headers.get("X-Kris-Control-Token", "")
        return bool(supplied) and secrets.compare_digest(supplied, self.controller.token)

    def _request_origin_allowed(self) -> bool:
        return _loopback_host(self.headers.get("Host", "")) and _loopback_origin(self.headers.get("Origin") or self.headers.get("Referer"))

    def _guard(self, *, write: bool) -> bool:
        if not self._request_origin_allowed():
            self._json(403, {"error": "loopback Host/Origin required"})
            return False
        if not self._authorized():
            self._json(401, {"error": "invalid control token"})
            return False
        if write:
            try:
                length = int(self.headers.get("Content-Length", "0") or "0")
            except ValueError:
                self._json(400, {"error": "invalid content length"})
                return False
            if length < 0 or length > MAX_REQUEST_BODY:
                self._json(413, {"error": "request body too large"})
                return False
            if length:
                self.rfile.read(length)
            if not self.controller.allowed_rate(self.client_address[0]):
                self._json(429, {"error": "controller operation rate exceeded"})
                return False
        return True

    def do_GET(self) -> None:  # noqa: N802
        path = urllib.parse.urlparse(self.path).path
        if path == "/":
            nonce = secrets.token_urlsafe(18)
            data = DASHBOARD_HTML.replace("__NONCE__", nonce).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self._security_headers(nonce)
            self.end_headers()
            self.wfile.write(data)
            return
        if path == "/api/status" and self._guard(write=False):
            self._json(200, self.controller.status())
            return
        self._json(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if not self._guard(write=True):
            return
        path = urllib.parse.urlparse(self.path).path
        try:
            if path == "/api/start":
                value = self.controller.start()
            elif path == "/api/stop":
                value = self.controller.stop()
            elif path == "/api/refresh-restart":
                value = self.controller.refresh_restart()
            else:
                self._json(404, {"error": "not found"})
                return
            self._json(200, value)
        except Exception as exc:
            self._json(409, {"error": str(exc)[:12000], "status": self.controller.status()})


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], controller: Controller):
        super().__init__(address, Handler)
        self.controller = controller


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host")
    parser.add_argument("--port", type=int)
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--version", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if args.version:
        print(CONTROL_VERSION)
        return 0
    cfg = ControlConfig.from_environment()
    if args.host:
        cfg = dataclasses.replace(cfg, host=args.host)
    if args.port:
        cfg = dataclasses.replace(cfg, port=args.port)
    controller = Controller(cfg)
    if args.status:
        print(json.dumps(controller.status(), indent=2, sort_keys=True))
        return 0
    server = Server((cfg.host, cfg.port), controller)
    print(json.dumps({"event": "controller-ready", "version": CONTROL_VERSION, "host": cfg.host, "port": cfg.port, "backend": cfg.backend, "tokenFile": str(cfg.token_path)}, sort_keys=True), flush=True)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
