#!/usr/bin/env python3
from __future__ import annotations

import ipaddress
import os
import pathlib
import shutil
import socket
import subprocess
import sys

DEFAULT_PORT = 8090
SERVICE = "kris-qwen-control.service"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def run(argv: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        argv,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        fail(f"{' '.join(argv)} failed: {detail}")
    return result


def current_branch(repo: pathlib.Path) -> str:
    result = run(["git", "-C", str(repo), "branch", "--show-current"])
    branch = result.stdout.strip()
    if not branch:
        fail("the repository is on a detached HEAD; check out the branch Qwen should follow")
    return branch


def active_systemd_controller() -> tuple[bool, bool]:
    """Return (active, durable_always_on_unit) without mutating the service."""
    if shutil.which("systemctl") is None:
        return False, False
    active = run(["systemctl", "is-active", "--quiet", SERVICE], check=False)
    if active.returncode != 0:
        return False, False
    unit = run(["systemctl", "cat", SERVICE], check=False)
    text = unit.stdout if unit.returncode == 0 else ""
    durable = (
        "tool/kris_qwen_control.py.compat.py" in text
        and "Restart=always" in text
        and "StartLimitIntervalSec=0" in text
    )
    return True, durable


def report_existing_durable_service() -> None:
    print()
    print("KRIS Qwen durable systemd controller is already active.")
    print("Leaving it running; a second foreground controller is not started.")
    print(f"  status: systemctl status {SERVICE} --no-pager")
    print(f"  logs:   journalctl -u {SERVICE} -f")
    print("  config: /etc/kris-qwen-control.env")
    print()
    print("For phone access, the service environment must use:")
    print("  KRIS_QWEN_CONTROL_HOST=0.0.0.0")
    print("  KRIS_QWEN_CONTROL_ALLOW_REMOTE_HTTP=1")
    print()


def require_github_auth() -> None:
    if shutil.which("gh") is None:
        fail("GitHub CLI 'gh' is required so Fetch latest + run can authenticate")
    result = run(["gh", "auth", "status", "--hostname", "github.com"], check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        fail(f"GitHub CLI is not authenticated for github.com: {detail}")


def ensure_port_free(port: int) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("0.0.0.0", port))
    except OSError as exc:
        fail(f"port {port} is already in use: {exc}")
    finally:
        sock.close()


def discover_ip() -> str | None:
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.connect(("1.1.1.1", 80))
            return sock.getsockname()[0]
        finally:
            sock.close()
    except OSError:
        return None


def main() -> int:
    repo = pathlib.Path(__file__).resolve().parent
    controller = repo / "tool" / "kris_qwen_control.py"
    controller_entry = repo / "tool" / "kris_qwen_control.py.compat.py"
    worker = repo / "tool" / "kris_qwen_worker.py"
    worker_policy = repo / "tool" / "kris_qwen_v53_policy.py"
    worker_recovery = repo / "tool" / "kris_qwen_v53_recovery.py"
    worker_legacy_entry = repo / "tool" / "kris_qwen_worker.py.compat.py"
    worker_entry = repo / "tool" / "kris_qwen_worker_v53.py"

    if not (repo / ".git").is_dir():
        fail(f"not a Git checkout: {repo}")
    if not (
        controller.is_file()
        and controller_entry.is_file()
        and worker.is_file()
        and worker_policy.is_file()
        and worker_recovery.is_file()
        and worker_legacy_entry.is_file()
        and worker_entry.is_file()
    ):
        fail("Qwen controller/worker always-on compatibility files are missing from tool/")

    branch = os.environ.get("KRIS_QWEN_REPO_BRANCH", "").strip() or current_branch(repo)

    active_service, durable_service = active_systemd_controller()
    if active_service:
        if durable_service:
            report_existing_durable_service()
            return 0
        fail(
            f"legacy {SERVICE} is active. Do not stop a running Qwen supervisor implicitly. "
            "Migrate it in place with 'sudo ./tool/install_kris_qwen_control_systemd.sh'."
        )

    try:
        port = int(os.environ.get("KRIS_QWEN_CONTROL_PORT", str(DEFAULT_PORT)))
    except ValueError:
        fail("KRIS_QWEN_CONTROL_PORT must be an integer")
    if not 1 <= port <= 65535:
        fail("KRIS_QWEN_CONTROL_PORT must be between 1 and 65535")

    require_github_auth()
    ensure_port_free(port)

    env = dict(os.environ)
    env["KRIS_QWEN_REPO_DIR"] = str(repo)
    env["KRIS_QWEN_REPO_BRANCH"] = branch
    env["KRIS_QWEN_WORKER_SCRIPT"] = str(worker_entry)
    env["KRIS_QWEN_CONTROL_HOST"] = "0.0.0.0"
    env["KRIS_QWEN_CONTROL_PORT"] = str(port)
    env["KRIS_QWEN_CONTROL_ALLOW_REMOTE_HTTP"] = "1"
    env.setdefault("KRIS_QWEN_AUTO_UPDATE", "1")
    env.setdefault("KRIS_QWEN_AUTO_UPDATE_SECONDS", "30")
    env.setdefault("KRIS_QWEN_CONTROLLER_SELF_RESTART", "0")

    ip = discover_ip()
    print()
    print("KRIS Qwen phone server")
    print(f"  repo:   {repo}")
    print(f"  branch: {branch}")
    print(f"  port:   {port}")
    print("  mode:   foreground always-on worker + automatic safe updates")
    print("  note:   durable controller crash recovery requires the systemd installer")
    if ip:
        print(f"  open:   http://{ip}:{port}")
    else:
        print(f"  open:   http://<server-ip>:{port}")
    print()
    print("The controller will print the control token below.")
    if ip:
        try:
            public = not ipaddress.ip_address(ip).is_private
        except ValueError:
            public = False
        if public:
            print("WARNING: this server address is public Internet.")
    print("WARNING: this control page uses plain HTTP. Prefer a trusted LAN/VPN")
    print("because the bearer token is otherwise sent without transport encryption.")
    print()

    os.execve(
        sys.executable,
        [sys.executable, str(controller_entry), "--phone", "--port", str(port)],
        env,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
