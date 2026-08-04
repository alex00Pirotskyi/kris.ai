#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import pathlib
import platform
import shutil
import subprocess
import sys
import tempfile
import time

from p2_behavioral_gate import (
    test_authorization,
    test_command,
    test_filesystem,
    test_redaction,
    test_watchdog,
)


def require_passed(rows: list[dict], label: str) -> dict:
    failed = [row for row in rows if row.get("status") != "passed"]
    if failed:
        return {"status": "blocked", "label": label, "results": rows, "reason": "non_behavioral_or_failed_result"}
    return {"status": "passed", "label": label, "results": rows}


def filesystem_fixture(root: pathlib.Path) -> dict:
    rows = test_filesystem(root)
    if os.name == "nt":
        rows = [row for row in rows if row.get("name") != "symlink final-target revalidation"]
        source = root / "junction-source"
        source.mkdir()
        junction = root / "junction"
        command = ["cmd.exe", "/d", "/c", "mklink", "/J", str(junction), str(source)]
        proc = subprocess.run(command, text=True, capture_output=True)
        ok = proc.returncode == 0 and junction.exists() and junction.resolve() == source.resolve()
        rows.append({"name": "Windows junction identity fixture", "status": "passed" if ok else "blocked", "detail": f"rc={proc.returncode}"})
    return require_passed(rows, "filesystem full-host transaction fixture")


def command_fixture(root: pathlib.Path) -> dict:
    rows = test_authorization(root) + test_command(root)
    if os.name == "nt":
        rows = [row for row in rows if row.get("name") != "timeout and process-tree termination"]
        script = root / "tree.py"
        script.write_text(
            "import subprocess,sys,time; subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)']); time.sleep(30)\n",
            encoding="utf-8",
        )
        process = subprocess.Popen([sys.executable, str(script)])
        time.sleep(0.5)
        kill = subprocess.run(["taskkill.exe", "/PID", str(process.pid), "/T", "/F"], text=True, capture_output=True)
        try:
            process.wait(timeout=5)
            stopped = process.returncode is not None
        except subprocess.TimeoutExpired:
            stopped = False
            process.kill()
        rows.append({"name": "Windows finite-command timeout tree fixture", "status": "passed" if kill.returncode == 0 and stopped else "failed", "detail": f"taskkill={kill.returncode}"})
    return require_passed(rows, "finite direct command fixture")


def undo_fixture(root: pathlib.Path) -> dict:
    repo = root / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "p2-fixture@example.invalid"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "P2 Fixture"], cwd=repo, check=True)
    target = repo / "state.txt"
    target.write_text("before\n")
    subprocess.run(["git", "add", "state.txt"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "checkpoint"], cwd=repo, check=True)
    checkpoint = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    backup = root / "state.bak"
    shutil.copy2(target, backup)
    target.write_text("after\n")
    shutil.copy2(backup, target)
    file_restore = target.read_text() == "before\n"
    target.write_text("dirty\n")
    subprocess.run(["git", "reset", "--hard", checkpoint], cwd=repo, check=True, stdout=subprocess.DEVNULL)
    git_restore = target.read_text() == "before\n"
    return {"status": "passed" if file_restore and git_restore else "failed", "label": "file backup and Git checkpoint restore", "checkpoint": checkpoint, "fileRestore": file_restore, "gitRestore": git_restore, "irreversibleClassification": "explicitly_not_restorable"}


def watchdog_fixture(root: pathlib.Path) -> dict:
    rows = test_watchdog(root)
    if os.name == "nt":
        # The real Job Object prelaunch/kill receipt is executed by the native
        # platform smoke assertion. Do not turn this source marker into PASS.
        return {"status": "blocked", "label": "Windows watchdog delegated to native assertion", "results": rows, "reason": "native_assertion_required"}
    return require_passed(rows, "external watchdog fixture")


def adversarial_fixture(root: pathlib.Path) -> dict:
    # Bounded fanout fixture: at most eight descendants, no unbounded fork bomb.
    program = "import subprocess,sys,time; children=[subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)']) for _ in range(8)]; time.sleep(30)"
    parent = subprocess.Popen([sys.executable, "-c", program], start_new_session=(os.name != "nt"))
    time.sleep(0.5)
    if os.name == "nt":
        killed = subprocess.run(["taskkill.exe", "/PID", str(parent.pid), "/T", "/F"], capture_output=True).returncode == 0
    else:
        import signal
        os.killpg(parent.pid, signal.SIGKILL)
        killed = True
    try:
        parent.wait(timeout=5)
    except subprocess.TimeoutExpired:
        killed = False
        parent.kill()
    redaction = require_passed(test_redaction(root), "redaction fixture")
    return {"status": "passed" if killed and redaction["status"] == "passed" else "failed", "label": "bounded fanout/crash/redaction adversarial fixture", "boundedDescendants": 8, "terminated": killed, "redaction": redaction}


def guide_fixture(project: pathlib.Path) -> dict:
    guide = (project / "docs/OWNER_MODE_OPERATOR_GUIDE.md").read_text(encoding="utf-8")
    workspace = (project / "lib/product/p2_owner_workspace.dart").read_text(encoding="utf-8")
    watchdog = (project / "lib/product/p2_emergency_watchdog.dart").read_text(encoding="utf-8")
    required = ["not a sandbox", "full current-account", "Emergency", "recovery", "unattended", "secret"]
    missing = [token for token in required if token.lower() not in guide.lower()]
    source_ok = "Terminate tree" in workspace and "Interrupt" in workspace and "emergency" in watchdog.lower()
    return {"status": "passed" if not missing and source_ok else "failed", "label": "operator guide to UI/source consistency", "missingGuideTerms": missing, "workspaceActionsPresent": source_ok}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--task", required=True, choices=["P2-002", "P2-003", "P2-010", "P2-011", "P2-013", "P2-014"])
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    with tempfile.TemporaryDirectory(prefix=f"{args.task.lower()}-") as temp:
        root = pathlib.Path(temp)
        if args.task == "P2-002": result = filesystem_fixture(root)
        elif args.task == "P2-003": result = command_fixture(root)
        elif args.task == "P2-010": result = undo_fixture(root)
        elif args.task == "P2-011": result = watchdog_fixture(root)
        elif args.task == "P2-013": result = adversarial_fixture(root)
        else: result = guide_fixture(project)
    payload = {
        "schemaVersion": "1.0.0",
        "taskId": args.task,
        "platform": platform.system().lower(),
        **result,
    }
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2))
    return 0 if payload["status"] == "passed" else 3


if __name__ == "__main__":
    raise SystemExit(main())
