#!/usr/bin/env python3
"""Linux namespace sandbox worker for Kristin.

This helper intentionally uses only the Python standard library and common Linux
utilities (`unshare`, `mount`, `chroot`) so a source checkout can enforce a real
project boundary before Dart/Flutter are available.
"""
from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from typing import Any, Mapping

import secret_broker

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.9.0+190"
MAX_OUTPUT_BYTES = 2 * 1024 * 1024
SAFE_SYSTEM_MOUNTS = (
    "/usr",
    "/bin",
    "/lib",
    "/lib64",
    "/etc",
    "/opt",
)
SNAPSHOT_EXCLUDES = frozenset({
    ".git",
    ".dart_tool",
    "build",
    "dist",
    "node_modules",
    "__pycache__",
})


class SandboxError(RuntimeError):
    pass


class SandboxUnavailableError(SandboxError):
    pass


class SandboxPolicyError(SandboxError):
    pass


def _proc_identity(pid: int) -> dict[str, int | str] | None:
    """Return a PID-reuse-safe Linux process identity.

    `/proc/<pid>/stat` places the executable name in parentheses and that name
    may itself contain spaces or parentheses.  Split after the final closing
    parenthesis so PPID and start-time ticks are read from stable field
    positions.  The start-time value makes cancellation safe when a stored PID
    has already been recycled by the operating system.
    """

    if pid <= 1 or not sys.platform.startswith("linux"):
        return None
    try:
        text = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    close = text.rfind(")")
    if close < 0:
        return None
    fields = text[close + 2 :].split()
    if len(fields) <= 19:
        return None
    try:
        return {
            "pid": pid,
            "state": fields[0],
            "ppid": int(fields[1]),
            "startTimeTicks": int(fields[19]),
        }
    except (TypeError, ValueError):
        return None


def process_identity(pid: int) -> dict[str, int | str] | None:
    """Public, bounded process identity used by durable process records."""

    return _proc_identity(pid)


def process_identity_alive(identity: Mapping[str, Any] | None) -> bool:
    """Return true only while the exact non-zombie process still exists."""

    if not identity:
        return False
    try:
        pid = int(identity["pid"])
        expected = int(identity["startTimeTicks"])
    except (KeyError, TypeError, ValueError):
        return False
    current = _proc_identity(pid)
    return bool(
        current
        and current.get("state") != "Z"
        and int(current.get("startTimeTicks", -1)) == expected
    )


def process_tree_snapshot(root_pid: int) -> list[dict[str, int | str]]:
    """Capture a PID-reuse-safe snapshot of a Linux process tree.

    The result is root-first.  Callers retain the identities before signalling
    so descendants can still be checked after re-parenting.
    """

    if root_pid <= 1 or not sys.platform.startswith("linux"):
        identity = _proc_identity(root_pid)
        return [identity] if identity else []
    identities: dict[int, dict[str, int | str]] = {}
    try:
        entries = list(Path("/proc").iterdir())
    except OSError:
        entries = []
    for entry in entries:
        if not entry.name.isdigit():
            continue
        identity = _proc_identity(int(entry.name))
        if identity:
            identities[int(identity["pid"])] = identity
    if root_pid not in identities:
        return []
    children: dict[int, list[int]] = {}
    for pid, identity in identities.items():
        children.setdefault(int(identity["ppid"]), []).append(pid)
    ordered: list[dict[str, int | str]] = []
    pending = [root_pid]
    seen: set[int] = set()
    while pending:
        pid = pending.pop(0)
        if pid in seen or pid not in identities:
            continue
        seen.add(pid)
        ordered.append(identities[pid])
        pending[0:0] = sorted(children.get(pid, []))
    return ordered


def terminate_process_tree(root_pid: int, *, grace_seconds: float = 3.0) -> dict[str, Any]:
    """Terminate one exact Linux process tree without trusting a stale PID.

    A tree snapshot is captured before signalling.  Every later signal is
    guarded by the process start-time ticks, so PID reuse cannot redirect a
    cancellation at an unrelated process.  SIGTERM is followed by bounded
    SIGKILL cleanup.  The returned survivor list is suitable for a blocking
    release assertion.
    """

    identities = process_tree_snapshot(root_pid)
    if not identities:
        return {"observed": 0, "terminated": 0, "survivors": []}

    def signal_exact(identity: Mapping[str, Any], signum: int) -> None:
        if not process_identity_alive(identity):
            return
        try:
            os.kill(int(identity["pid"]), signum)
        except (ProcessLookupError, PermissionError):
            return

    # Signal the launcher first so parent-death and unshare --kill-child
    # protections activate, then signal the captured descendants deepest-first
    # as a deterministic fallback.
    signal_exact(identities[0], signal.SIGTERM)
    for identity in reversed(identities[1:]):
        signal_exact(identity, signal.SIGTERM)

    deadline = time.monotonic() + max(0.1, grace_seconds)
    while time.monotonic() < deadline:
        if not any(process_identity_alive(identity) for identity in identities):
            break
        time.sleep(0.05)

    for identity in reversed(identities):
        signal_exact(identity, signal.SIGKILL)
    kill_deadline = time.monotonic() + 2.0
    while time.monotonic() < kill_deadline:
        if not any(process_identity_alive(identity) for identity in identities):
            break
        time.sleep(0.05)

    survivors = [identity for identity in identities if process_identity_alive(identity)]
    return {
        "observed": len(identities),
        "terminated": len(identities) - len(survivors),
        "survivors": survivors,
    }


def _set_parent_death_signal() -> None:
    """Ask Linux to kill the worker launcher when its direct parent dies."""

    if not sys.platform.startswith("linux"):
        return
    # PR_SET_PDEATHSIG = 1.  Re-check the parent after prctl to close the race
    # where it exits between fork and this callback.
    parent = os.getppid()
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:
        return
    if os.getppid() != parent:
        os.kill(os.getpid(), signal.SIGKILL)


def _utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _run_checked(argv: list[str], *, cwd: Path | None = None) -> None:
    completed = subprocess.run(
        argv,
        cwd=str(cwd) if cwd is not None else None,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        text=True,
        errors="replace",
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "").strip()
        raise SandboxError(f"command failed: {' '.join(argv)} :: {detail}")


def _mount_bind(source: str, target: str, *, read_only: bool) -> None:
    _run_checked(["mount", "--rbind", source, target])
    if read_only:
        _run_checked(["mount", "-o", "remount,bind,ro", target])


def _safe_relative(path: str) -> str:
    normalized = path.replace("\\", "/").strip().strip("/")
    if not normalized or normalized == ".":
        return "."
    parts = [part for part in normalized.split("/") if part and part != "."]
    if any(part == ".." for part in parts):
        raise SandboxPolicyError(f"path escapes the workspace: {path}")
    return "/".join(parts)


def _resolve_executable(executable: str, environment: dict[str, str]) -> str:
    if os.path.isabs(executable):
        return executable
    resolved = shutil.which(executable, path=environment.get("PATH"))
    if not resolved:
        raise SandboxPolicyError(f"{executable} was not found on PATH")
    return resolved


def _copy_project_snapshot(source: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for entry in sorted(source.iterdir(), key=lambda item: item.name):
        if entry.name in SNAPSHOT_EXCLUDES:
            continue
        target = dest / entry.name
        if entry.is_symlink():
            raise SandboxPolicyError(
                f"snapshot creation rejects symlinks: {entry.relative_to(source)}"
            )
        if entry.is_dir():
            _copy_project_snapshot(entry, target)
        elif entry.is_file():
            shutil.copy2(entry, target)


def _digest_directory(root: Path) -> str:
    hasher = hashlib.sha256()
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            raise SandboxPolicyError(f"workspace digest rejects symlink: {relative}")
        hasher.update(relative.encode("utf-8") + b"\0")
        if path.is_file():
            hasher.update(path.read_bytes())
    return hasher.hexdigest()


def probe_backend() -> dict[str, Any]:
    issues: list[str] = []
    commands = {name: shutil.which(name) for name in ("unshare", "mount", "chroot")}
    available = all(commands.values()) and sys.platform.startswith("linux")
    if not sys.platform.startswith("linux"):
        issues.append("linux namespaces are unavailable on this platform")
    for name, path in commands.items():
        if not path:
            issues.append(f"missing required helper: {name}")
    if available:
        try:
            with tempfile.TemporaryDirectory(prefix="kristin-sandbox-probe-") as temp_dir:
                probe_script = (
                    "set -e\n"
                    "ROOT=\"$1\"\n"
                    "mount -t tmpfs tmpfs \"$ROOT\"\n"
                    "mkdir -p \"$ROOT/workspace\"\n"
                    "mkdir -p \"$ROOT/tmp\"\n"
                    ": > \"$ROOT/tmp/ok\"\n"
                    "mount --bind /tmp \"$ROOT/workspace\"\n"
                    "mount -o remount,bind,ro \"$ROOT/workspace\"\n"
                    "test -f \"$ROOT/workspace\"/.. || true\n"
                    "umount \"$ROOT/workspace\"\n"
                    "umount \"$ROOT\"\n"
                )
                completed = subprocess.run(
                    [
                        commands["unshare"],
                        "--user",
                        "--map-root-user",
                        "--mount",
                        "--net",
                        "--pid",
                        "--fork",
                        "--kill-child=SIGKILL",
                        "bash",
                        "-lc",
                        probe_script,
                        "bash",
                        temp_dir,
                    ],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    errors="replace",
                    check=False,
                    timeout=20,
                )
                if completed.returncode != 0:
                    available = False
                    issues.append((completed.stderr or completed.stdout or "sandbox probe failed").strip())
        except Exception as exc:  # noqa: BLE001 - probe must never crash the caller
            available = False
            issues.append(str(exc))
    return {
        "version": VERSION,
        "backend": "linux_userns_namespace_worker" if available else "unavailable",
        "available": available,
        "platform": sys.platform,
        "commands": commands,
        "issues": issues,
        "supports": {
            "mountNamespace": available,
            "networkNamespace": available,
            "pidNamespace": available,
            "readOnlyWorkspace": available,
            "snapshotWritableWorkspace": available,
            "boundedFiniteCommand": available,
            "killOnWorkerExit": available,
            "directNetworkOff": available,
            "publicHttpsBroker": True,
            "oneUseSecretHandles": True,
        },
    }


def _prepare_request(
    request: dict[str, Any],
    *,
    workspace_root: Path,
    working_directory: str,
    workspace_mode: str,
) -> dict[str, Any]:
    environment = dict(request.get("environment") or {})
    safe_env = {
        key: value
        for key, value in os.environ.items()
        if key
        in {
            "PATH",
            "LANG",
            "LC_ALL",
            "HOME",
            "TMP",
            "TEMP",
            "TMPDIR",
        }
    }
    safe_env.update({str(key): str(value) for key, value in environment.items()})
    executable = _resolve_executable(str(request.get("executable", "")), safe_env)
    working = _safe_relative(working_directory)
    if working != "." and not (workspace_root / working).exists():
        raise SandboxPolicyError(f"working directory does not exist inside the workspace: {working_directory}")
    host_executable = Path(executable)
    if host_executable.is_relative_to(workspace_root):
        inside_executable = f"/workspace/{host_executable.relative_to(workspace_root).as_posix()}"
    elif any(executable == prefix or executable.startswith(f"{prefix}/") for prefix in SAFE_SYSTEM_MOUNTS):
        inside_executable = executable
    else:
        raise SandboxPolicyError(
            "sandbox permits project-local executables or host executables under /usr, /bin, /lib, /lib64, /etc, and /opt only"
        )
    request = dict(request)
    request.update(
        {
            "resolvedExecutable": executable,
            "insideExecutable": inside_executable,
            "workspaceRoot": str(workspace_root),
            "workspaceHash": _digest_directory(workspace_root),
            "workingDirectoryRelative": working,
            "workspaceMode": workspace_mode,
            "preparedAt": _utc_now(),
        }
    )
    request["environment"] = safe_env
    request["arguments"] = [str(item) for item in request.get("arguments") or []]
    return request


def run_finite(
    *,
    executable: str,
    arguments: list[str],
    project_root: Path,
    working_directory: str = ".",
    workspace_mode: str = "read_only",
    timeout_seconds: int = 600,
    environment: dict[str, str] | None = None,
    secret_environment: dict[str, str] | None = None,
    memory_limit_mb: int = 1024,
    process_limit: int = 64,
    file_size_limit_mb: int = 128,
    max_output_bytes: int = MAX_OUTPUT_BYTES,
    retained_snapshot_root: Path | None = None,
) -> dict[str, Any]:
    probe = probe_backend()
    if not probe["available"]:
        raise SandboxUnavailableError("linux namespace sandbox backend is unavailable")
    with tempfile.TemporaryDirectory(prefix="kristin-worker-") as temp_dir:
        temp = Path(temp_dir)
        workspace_root = project_root
        snapshot_root: Path | None = None
        retained_snapshot = False
        if workspace_mode == "snapshot_writable":
            if retained_snapshot_root is not None:
                snapshot_root = retained_snapshot_root.expanduser().resolve()
                project_resolved = project_root.expanduser().resolve()
                if snapshot_root == project_resolved or snapshot_root.is_relative_to(project_resolved) or project_resolved.is_relative_to(snapshot_root):
                    raise SandboxPolicyError("retained snapshot must be outside the source project tree")
                if snapshot_root.exists():
                    if snapshot_root.is_symlink() or any(snapshot_root.iterdir()):
                        raise SandboxPolicyError("retained snapshot destination must be a new empty directory")
                else:
                    snapshot_root.mkdir(parents=True, exist_ok=False)
                retained_snapshot = True
            else:
                snapshot_root = temp / "snapshot"
            _copy_project_snapshot(project_root, snapshot_root)
            workspace_root = snapshot_root
        elif retained_snapshot_root is not None:
            raise SandboxPolicyError("retained snapshots require snapshot_writable mode")
        elif workspace_mode != "read_only":
            raise SandboxPolicyError(f"unsupported workspace mode: {workspace_mode}")
        secret_handles: dict[str, str] = {}
        for key, value in (secret_environment or {}).items():
            if not key.replace("_", "a").isalnum() or not (key[0].isalpha() or key[0] == "_"):
                raise SandboxPolicyError(f"invalid environment variable name: {key}")
            secret_handles[key] = secret_broker.issue_secret(value, owner="sandbox_worker", ttl_seconds=120)["handle"]
        request = _prepare_request(
            {
                "executable": executable,
                "arguments": list(arguments),
                "environment": environment or {},
                "secretEnvironmentHandles": secret_handles,
                "timeoutSeconds": max(1, int(timeout_seconds)),
                "memoryLimitMb": max(128, int(memory_limit_mb)),
                "processLimit": max(8, int(process_limit)),
                "fileSizeLimitMb": max(1, int(file_size_limit_mb)),
                "maxOutputBytes": max(1024, int(max_output_bytes)),
            },
            workspace_root=workspace_root,
            working_directory=working_directory,
            workspace_mode=workspace_mode,
        )
        request_path = temp / "request.json"
        request_path.write_text(json.dumps(request, sort_keys=True), encoding="utf-8")
        command = [
            probe["commands"]["unshare"],
            "--user",
            "--map-root-user",
            "--mount",
            "--net",
            "--pid",
            "--fork",
            "--kill-child=SIGKILL",
            sys.executable,
            str(Path(__file__).resolve()),
            "internal-run",
            str(request_path),
        ]
        started = dt.datetime.now(dt.timezone.utc)
        worker = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            errors="replace",
            close_fds=True,
            preexec_fn=_set_parent_death_signal if sys.platform.startswith("linux") else None,
        )
        try:
            stdout, stderr = worker.communicate(timeout=max(5, timeout_seconds + 5))
        except subprocess.TimeoutExpired as exc:
            cleanup = terminate_process_tree(worker.pid, grace_seconds=1.0)
            try:
                stdout, stderr = worker.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                stdout = exc.output or ""
                stderr = exc.stderr or ""
            raise SandboxError(
                "sandbox worker timed out; "
                f"terminated={cleanup['terminated']}/{cleanup['observed']} "
                f"survivors={len(cleanup['survivors'])}"
            ) from exc
        duration_ms = int((dt.datetime.now(dt.timezone.utc) - started).total_seconds() * 1000)
        if worker.returncode != 0:
            detail = (stderr or stdout or "sandbox worker failed").strip()
            raise SandboxError(detail)
        result = json.loads(stdout)
        result["durationMs"] = duration_ms
        if snapshot_root is not None:
            result["workspaceSnapshotHash"] = _digest_directory(snapshot_root)
            result["workspaceRetained"] = retained_snapshot
            if retained_snapshot:
                result["workspaceSnapshotPath"] = str(snapshot_root)
        return result


def _apply_limits(request: dict[str, Any]) -> None:
    memory_limit = int(request.get("memoryLimitMb", 1024)) * 1024 * 1024
    process_limit = int(request.get("processLimit", 64))
    file_size_limit = int(request.get("fileSizeLimitMb", 128)) * 1024 * 1024
    cpu_seconds = max(1, min(int(request.get("timeoutSeconds", 600)), 3600))
    try:
        resource.setrlimit(resource.RLIMIT_AS, (memory_limit, memory_limit))
    except (ValueError, OSError):
        pass
    try:
        resource.setrlimit(resource.RLIMIT_NPROC, (process_limit, process_limit))
    except (ValueError, OSError):
        pass
    try:
        resource.setrlimit(resource.RLIMIT_FSIZE, (file_size_limit, file_size_limit))
    except (ValueError, OSError):
        pass
    try:
        resource.setrlimit(resource.RLIMIT_CPU, (cpu_seconds, cpu_seconds))
    except (ValueError, OSError):
        pass
    try:
        resource.setrlimit(resource.RLIMIT_NOFILE, (256, 256))
    except (ValueError, OSError):
        pass
    os.setsid()


def _capture(process: subprocess.Popen[bytes], max_output_bytes: int, timeout: int) -> tuple[int, str, str, bool]:
    truncated = False
    try:
        stdout, stderr = process.communicate(timeout=max(1, timeout))
    except subprocess.TimeoutExpired:
        terminate_process_tree(process.pid, grace_seconds=1.0)
        try:
            stdout, stderr = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            terminate_process_tree(process.pid, grace_seconds=0.1)
            stdout, stderr = process.communicate(timeout=2)
        return -124, (stdout or b"")[:max_output_bytes].decode("utf-8", errors="replace"), (stderr or b"")[:max_output_bytes].decode("utf-8", errors="replace"), True
    if len(stdout) > max_output_bytes:
        stdout = stdout[:max_output_bytes]
        truncated = True
    if len(stderr) > max_output_bytes:
        stderr = stderr[:max_output_bytes]
        truncated = True
    return process.returncode, stdout.decode("utf-8", errors="replace"), stderr.decode("utf-8", errors="replace"), truncated


def _internal_run(request_path: Path) -> int:
    request = json.loads(request_path.read_text(encoding="utf-8"))
    sandbox_root = Path(tempfile.mkdtemp(prefix="kristin-chroot-"))
    mount_root = sandbox_root / "root"
    mount_root.mkdir(parents=True, exist_ok=True)
    try:
        _run_checked(["mount", "-t", "tmpfs", "tmpfs", str(mount_root)])
        for directory in ("usr", "bin", "lib", "lib64", "etc", "dev", "tmp", "workspace"):
            (mount_root / directory).mkdir(parents=True, exist_ok=True)
        for path in SAFE_SYSTEM_MOUNTS:
            source = Path(path)
            if source.exists():
                target = mount_root / path.lstrip("/")
                target.mkdir(parents=True, exist_ok=True)
                _mount_bind(str(source), str(target), read_only=True)
        for device_name, host_path in (("null", "/dev/null"), ("urandom", "/dev/urandom")):
            target = mount_root / "dev" / device_name
            target.touch(exist_ok=True)
            _mount_bind(host_path, str(target), read_only=False)
        _mount_bind(
            str(request["workspaceRoot"]),
            str(mount_root / "workspace"),
            read_only=request["workspaceMode"] == "read_only",
        )
        env = {
            "PATH": request["environment"].get("PATH", "/usr/bin:/bin"),
            "LANG": request["environment"].get("LANG", "C.UTF-8"),
            "LC_ALL": request["environment"].get("LC_ALL", request["environment"].get("LANG", "C.UTF-8")),
            "HOME": "/tmp",
            "TMPDIR": "/tmp",
        }
        for key, value in request["environment"].items():
            if key not in env:
                env[key] = str(value)
        for key, handle in (request.get("secretEnvironmentHandles") or {}).items():
            env[str(key)] = secret_broker.consume_secret(str(handle), owner="sandbox_worker")
        cwd = "/workspace"
        relative = request.get("workingDirectoryRelative", ".")
        if relative not in ("", "."):
            cwd = f"/workspace/{relative}"
        child = subprocess.Popen(
            [
                "chroot",
                str(mount_root),
                "/usr/bin/python3",
                "-c",
                "import os, sys; os.chdir(sys.argv[1]); os.execv(sys.argv[2], sys.argv[2:])",
                cwd,
                request["insideExecutable"],
                *request["arguments"],
            ],
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            preexec_fn=lambda: _apply_limits(request),
        )
        exit_code, stdout, stderr, truncated = _capture(
            child,
            int(request.get("maxOutputBytes", MAX_OUTPUT_BYTES)),
            int(request.get("timeoutSeconds", 600)),
        )
        result = {
            "backend": "linux_userns_namespace_worker",
            "available": True,
            "workspaceMode": request["workspaceMode"],
            "workspaceHash": request["workspaceHash"],
            "workingDirectory": cwd,
            "insideExecutable": request["insideExecutable"],
            "arguments": request["arguments"],
            "startedAt": request["preparedAt"],
            "completedAt": _utc_now(),
            "exitCode": exit_code,
            "stdout": stdout,
            "stderr": stderr,
            "truncated": truncated,
        }
        sys.stdout.write(json.dumps(result, sort_keys=True))
        return 0
    finally:
        try:
            subprocess.run(["umount", "-l", str(mount_root)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        except Exception:
            pass


def _main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Kristin sandbox worker")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("probe")

    run_parser = sub.add_parser("run")
    run_parser.add_argument("--project", type=Path, required=True)
    run_parser.add_argument("--cwd", default=".")
    run_parser.add_argument("--workspace-mode", choices=("read_only", "snapshot_writable"), default="read_only")
    run_parser.add_argument("--timeout", type=int, default=600)
    run_parser.add_argument("--memory-mb", type=int, default=1024)
    run_parser.add_argument("--process-limit", type=int, default=64)
    run_parser.add_argument("--file-size-mb", type=int, default=128)
    run_parser.add_argument("--retain-snapshot", type=Path)
    run_parser.add_argument("executable")
    run_parser.add_argument("arguments", nargs=argparse.REMAINDER)

    internal = sub.add_parser("internal-run")
    internal.add_argument("request")

    args = parser.parse_args(argv)
    if args.command == "probe":
        print(json.dumps(probe_backend(), indent=2, sort_keys=True))
        return 0
    if args.command == "run":
        result = run_finite(
            executable=args.executable,
            arguments=list(args.arguments),
            project_root=args.project.expanduser().resolve(),
            working_directory=args.cwd,
            workspace_mode=args.workspace_mode,
            timeout_seconds=args.timeout,
            memory_limit_mb=args.memory_mb,
            process_limit=args.process_limit,
            file_size_limit_mb=args.file_size_mb,
            retained_snapshot_root=(
                args.retain_snapshot.expanduser().resolve()
                if args.retain_snapshot is not None
                else None
            ),
        )
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    if args.command == "internal-run":
        return _internal_run(Path(args.request).expanduser().resolve())
    parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
