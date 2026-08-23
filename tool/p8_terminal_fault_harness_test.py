#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path
import sys
import tempfile

import p8_terminal_fault_harness as terminal


def python_case(source: str) -> list[str]:
    return [sys.executable, "-c", source]


def main() -> int:
    binary = terminal.run_fault_case(
        python_case("import sys; sys.stdout.buffer.write(b'\\x00\\xffbinary')"),
        timeout_seconds=2,
        max_output_bytes=1024,
    )
    assert binary.exit_code == 0 and not binary.timed_out
    assert binary.stdout_bytes == len(b"\x00\xffbinary")
    assert not binary.stdout_truncated

    flood = terminal.run_fault_case(
        python_case("import sys; sys.stdout.write('x' * 65536)"),
        timeout_seconds=2,
        max_output_bytes=4096,
    )
    assert flood.exit_code == 0
    assert flood.stdout_bytes == 65536
    assert flood.stdout_truncated

    hung = terminal.run_fault_case(
        python_case("import time; time.sleep(10)"),
        timeout_seconds=0.1,
        max_output_bytes=1024,
    )
    assert hung.timed_out
    assert hung.exit_code is not None
    assert hung.termination_strategy != "natural_exit"

    abrupt = terminal.run_fault_case(
        python_case("import sys; sys.stderr.write('worker died'); raise SystemExit(7)"),
        timeout_seconds=2,
        max_output_bytes=1024,
    )
    assert abrupt.exit_code == 7
    assert abrupt.stderr_bytes == len("worker died")

    try:
        terminal.sanitized_environment({"MY_SECRET_TOKEN": "should-not-enter-child"})
    except ValueError as exc:
        assert "terminal_environment_sensitive_key_rejected" in str(exc)
    else:
        raise AssertionError("expected sensitive environment key rejection")

    with tempfile.TemporaryDirectory(prefix="kristin-terminal-") as raw:
        cwd = Path(raw)
        cwd_case = terminal.run_fault_case(
            python_case("import os; print(os.getcwd())"),
            timeout_seconds=2,
            max_output_bytes=4096,
            cwd=cwd,
            extra_environment={"KRISTIN_TEST_MARKER": "1"},
        )
        assert cwd_case.exit_code == 0

    if os.name != "nt":
        group = terminal.run_fault_case(
            python_case(
                "import subprocess,sys,time; "
                "subprocess.Popen([sys.executable,'-c','import time; time.sleep(10)']); "
                "time.sleep(10)"
            ),
            timeout_seconds=0.1,
            max_output_bytes=1024,
        )
        assert group.timed_out
        assert group.termination_strategy == "posix_process_group_sigterm"

    print("PASS P8 terminal faults: binary, flood, timeout, process-group kill, worker death, env isolation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
