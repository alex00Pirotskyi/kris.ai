#!/usr/bin/env python3
"""Executable sandbox-worker and secret-broker validation gate."""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import tempfile

import sandbox_worker
import secret_broker


@dataclass
class Result:
    name: str
    status: str
    detail: str


class Gate:
    def __init__(self) -> None:
        self.results: list[Result] = []

    def check(self, name: str, callback) -> None:
        try:
            detail = callback()
        except Exception as exc:  # noqa: BLE001 - release gate must capture failures
            self.results.append(Result(name, "failed", f"{type(exc).__name__}: {exc}"))
        else:
            self.results.append(Result(name, "passed", detail))

    @property
    def passed(self) -> bool:
        return all(item.status == "passed" for item in self.results)


def _assert(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json-output")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    gate = Gate()

    def probe_case() -> str:
        report = sandbox_worker.probe_backend()
        _assert(report["available"] is True, report)
        _assert(report["supports"]["readOnlyWorkspace"] is True, report)
        return f"backend={report['backend']} supports read-only and snapshot-writable namespace execution"

    gate.check("Linux namespace worker probe", probe_case)

    with tempfile.TemporaryDirectory(prefix="kristin-worker-fixture-") as temp_dir:
        project = Path(temp_dir) / "project"
        project.mkdir()
        (project / "input.txt").write_text("fixture\n", encoding="utf-8")

        def host_hidden() -> str:
            result = sandbox_worker.run_finite(
                executable="/usr/bin/python3",
                arguments=[
                    "-c",
                    "import os; print(os.path.exists(\"/mnt/data\")); print(os.path.exists(\"/workspace/input.txt\"))",
                ],
                project_root=project,
                workspace_mode="read_only",
                timeout_seconds=30,
            )
            lines = result["stdout"].strip().splitlines()
            _assert(lines == ["False", "True"], result)
            return "sandboxed process can read the mounted workspace but not the host data root"

        gate.check("Host path isolation", host_hidden)

        def read_only_block() -> str:
            result = sandbox_worker.run_finite(
                executable="/usr/bin/python3",
                arguments=[
                    "-c",
                    "from pathlib import Path\n"
                    "target = Path('/workspace/blocked.txt')\n"
                    "try:\n"
                    "  target.write_text('x')\n"
                    "  print('wrote')\n"
                    "except Exception as exc:\n"
                    "  print(type(exc).__name__)\n",
                ],
                project_root=project,
                workspace_mode="read_only",
                timeout_seconds=30,
            )
            _assert(result["stdout"].strip() == "OSError", result)
            _assert(not (project / "blocked.txt").exists(), "host project was modified")
            return "read-only workspace rejects writes and leaves the host project untouched"

        gate.check("Read-only workspace enforcement", read_only_block)

        def snapshot_writable() -> str:
            before = project.read_bytes() if project.is_file() else None
            result = sandbox_worker.run_finite(
                executable="/usr/bin/python3",
                arguments=[
                    "-c",
                    "from pathlib import Path; Path('/workspace/generated.txt').write_text('ok'); print(Path('/workspace/generated.txt').read_text())",
                ],
                project_root=project,
                workspace_mode="snapshot_writable",
                timeout_seconds=30,
            )
            _assert(result["stdout"].strip() == "ok", result)
            _assert(not (project / "generated.txt").exists(), "snapshot write leaked into the host project")
            _assert(result.get("workspaceSnapshotHash"), result)
            return "snapshot-writable execution permits project writes without mutating the original project tree"

        gate.check("Snapshot-writable workspace", snapshot_writable)

        def network_off() -> str:
            result = sandbox_worker.run_finite(
                executable="/usr/bin/python3",
                arguments=[
                    "-c",
                    "import socket\n"
                    "sock = socket.socket()\n"
                    "sock.settimeout(1)\n"
                    "try:\n"
                    "  sock.connect(('1.1.1.1', 443))\n"
                    "  print('network-open')\n"
                    "except Exception as exc:\n"
                    "  print(type(exc).__name__)\n",
                ],
                project_root=project,
                workspace_mode="read_only",
                timeout_seconds=30,
            )
            _assert(result["stdout"].strip() == "OSError", result)
            return "network namespace leaves only loopback available to worker processes"

        gate.check("Network-off enforcement", network_off)

        def executable_boundary() -> str:
            try:
                sandbox_worker.run_finite(
                    executable=str(Path.home() / ".local" / "bin" / "custom-tool"),
                    arguments=[],
                    project_root=project,
                    workspace_mode="read_only",
                    timeout_seconds=5,
                )
            except sandbox_worker.SandboxPolicyError:
                return "sandbox rejects executables outside the approved project or system runtime mounts"
            raise AssertionError("unsupported executable path was not rejected")

        gate.check("Executable path boundary", executable_boundary)

        def secret_one_use() -> str:
            issued = secret_broker.issue_secret("top-secret", owner="test-suite", ttl_seconds=60)
            first = secret_broker.consume_secret(issued["handle"], owner="test-suite")
            _assert(first == "top-secret", first)
            try:
                secret_broker.consume_secret(issued["handle"], owner="test-suite")
            except secret_broker.SecretHandleMissingError:
                return "secret handles are single-use and disappear after successful consumption"
            raise AssertionError("consumed secret handle remained reusable")

        gate.check("One-use secret handle", secret_one_use)

        def secret_into_worker() -> str:
            result = sandbox_worker.run_finite(
                executable="/usr/bin/python3",
                arguments=["-c", "import os; print(os.environ.get('KRISTIN_SECRET', 'missing'))"],
                project_root=project,
                workspace_mode="read_only",
                timeout_seconds=30,
                secret_environment={"KRISTIN_SECRET": "swordfish"},
            )
            _assert(result["stdout"].strip() == "swordfish", result)
            return "secret values can be injected into the sandbox through one-use handles without entering the ordinary environment contract"

        gate.check("Secret broker sandbox injection", secret_into_worker)

    payload = {
        "version": "1.9.0+190",
        "passed": gate.passed,
        "results": [asdict(item) for item in gate.results],
    }
    if args.json_output:
        Path(args.json_output).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    else:
        print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if gate.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
