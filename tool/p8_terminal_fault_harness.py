#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import asdict, dataclass
import os
from pathlib import Path
import signal
import subprocess
import tempfile
from typing import Mapping, Sequence


@dataclass(frozen=True)
class TerminalFaultResult:
    exit_code: int | None
    timed_out: bool
    stdout_bytes: int
    stderr_bytes: int
    stdout_truncated: bool
    stderr_truncated: bool
    termination_strategy: str

    def to_json(self) -> dict[str, object]:
        return asdict(self)


def sanitized_environment(extra: Mapping[str, str] | None = None) -> dict[str, str]:
    allowed = {
        key: os.environ[key]
        for key in ("PATH", "SYSTEMROOT", "WINDIR", "LANG", "LC_ALL", "TMP", "TEMP", "TMPDIR")
        if key in os.environ
    }
    if extra:
        for key, value in extra.items():
            if "SECRET" in key.upper() or "TOKEN" in key.upper() or "PASSWORD" in key.upper():
                raise ValueError(f"terminal_environment_sensitive_key_rejected:{key}")
            allowed[str(key)] = str(value)
    return allowed


def run_fault_case(
    command: Sequence[str],
    *,
    timeout_seconds: float,
    max_output_bytes: int,
    cwd: Path | None = None,
    extra_environment: Mapping[str, str] | None = None,
) -> TerminalFaultResult:
    if not command or any("\x00" in argument for argument in command):
        raise ValueError("terminal_command_invalid")
    if timeout_seconds <= 0:
        raise ValueError("terminal_timeout_invalid")
    if max_output_bytes < 1024:
        raise ValueError("terminal_output_limit_invalid")

    kwargs: dict[str, object] = {}
    if os.name == "nt":
        kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kwargs["start_new_session"] = True

    with tempfile.TemporaryFile() as stdout_file, tempfile.TemporaryFile() as stderr_file:
        process = subprocess.Popen(
            [str(value) for value in command],
            cwd=str(cwd) if cwd is not None else None,
            env=sanitized_environment(extra_environment),
            stdin=subprocess.DEVNULL,
            stdout=stdout_file,
            stderr=stderr_file,
            shell=False,
            **kwargs,
        )
        timed_out = False
        termination_strategy = "natural_exit"
        try:
            exit_code = process.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            timed_out = True
            termination_strategy = _terminate_process_tree(process)
            try:
                exit_code = process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                exit_code = process.wait(timeout=2)
                termination_strategy = "forced_process_kill"

        stdout_file.seek(0, os.SEEK_END)
        stdout_size = stdout_file.tell()
        stdout_file.seek(0)
        stdout_file.read(max_output_bytes + 1)
        stderr_file.seek(0, os.SEEK_END)
        stderr_size = stderr_file.tell()
        stderr_file.seek(0)
        stderr_file.read(max_output_bytes + 1)

    return TerminalFaultResult(
        exit_code=exit_code,
        timed_out=timed_out,
        stdout_bytes=stdout_size,
        stderr_bytes=stderr_size,
        stdout_truncated=stdout_size > max_output_bytes,
        stderr_truncated=stderr_size > max_output_bytes,
        termination_strategy=termination_strategy,
    )


def _terminate_process_tree(process: subprocess.Popen[bytes]) -> str:
    if process.poll() is not None:
        return "already_exited"
    if os.name == "nt":
        completed = subprocess.run(
            ["taskkill", "/PID", str(process.pid), "/T", "/F"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if completed.returncode == 0:
            return "windows_taskkill_tree"
        process.kill()
        return "windows_process_kill"
    try:
        os.killpg(process.pid, signal.SIGTERM)
        return "posix_process_group_sigterm"
    except ProcessLookupError:
        return "already_exited"
