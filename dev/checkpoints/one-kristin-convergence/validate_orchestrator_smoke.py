#!/usr/bin/env python3
"""Run the real 20-slice orchestrator on a modeled recovered-head worktree.

The temporary Git repository exists only so the production checkout guards can
run. No user checkout or remote repository is touched.
"""
from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ORCHESTRATOR = ROOT / "apply_all_development_slices.py"


def load_composition():
    path = ROOT / "validate_anchor_composition.py"
    spec = importlib.util.spec_from_file_location("_orchestrator_composition", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot import composition validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    composition = load_composition()
    operations = composition._operations_by_file()
    with tempfile.TemporaryDirectory(prefix="one-kristin-orchestrator-") as temp:
        repo = Path(temp) / "repo"
        repo.mkdir()
        created_paths = {
            "lib/product/task_kernel/task_family_execution.dart",
            "lib/product/task_kernel/research_task_family_executor.dart",
            "lib/product/run_steering_record.dart",
            "test/product/semantic_durable_steering_test.dart",
            "lib/product/agent_delegation_record.dart",
            "lib/product/task_kernel/command_planning_context.dart",
        }
        for relative, file_operations in operations.items():
            path = repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            # New whole-file artifacts must remain absent until the owning
            # slice creates them. A wholesale replacement of an existing
            # recovered-head file (run_steering.dart) still needs a seed.
            if relative in created_paths:
                continue
            content = composition._synthetic_head(relative, file_operations)
            if file_operations and file_operations[0][0] == "set" and not content:
                content = "// synthetic recovered-head existing file\n"
            path.write_text(content, encoding="utf-8")
        # Some slices create tests/files that are not later transformed and
        # therefore do not appear in the composition map. Parent directories
        # are enough for those guarded creators.
        for directory in [
            "lib/product/task_kernel",
            "test/product/task_kernel",
            "test/product",
        ]:
            (repo / directory).mkdir(parents=True, exist_ok=True)

        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@example.invalid"], check=True)
        subprocess.run(["git", "-C", str(repo), "config", "user.name", "Orchestrator Smoke"], check=True)
        subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
        subprocess.run(["git", "-C", str(repo), "commit", "-qm", "synthetic recovered head"], check=True)

        completed = subprocess.run(
            [
                sys.executable,
                str(ORCHESTRATOR),
                str(repo),
                "--apply",
                "--allow-head-mismatch",
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        if completed.returncode != 0:
            print(completed.stdout)
            raise SystemExit(
                f"real orchestrator synthetic smoke failed with {completed.returncode}"
            )
        if "[20/20] human-readable failure projection" not in completed.stdout:
            print(completed.stdout)
            raise SystemExit("orchestrator did not reach slice 20/20")
        if "All guarded development slices applied" not in completed.stdout:
            raise SystemExit("orchestrator did not report successful completion")
        print("OK actual 20-slice orchestrator on synthetic recovered-head worktree")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
