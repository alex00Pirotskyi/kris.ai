#!/usr/bin/env python3
"""Apply the recovered One-Kristin development slices in a guarded order.

This orchestrator intentionally performs SOURCE-WORKTREE mutations only.
It never stages, commits, branches, pushes, opens PRs, or edits GitHub.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

EXPECTED_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"

SLICES = [
    ("One-Kristin remaining state ownership", "apply_one_kristin_state_convergence.py"),
    ("Advanced projects the same Kristin conversation", "apply_advanced_same_conversation.py"),
    ("semantic slash-command Understanding", "apply_semantic_slash_understanding.py"),
    ("blocking clarification loop", "apply_blocking_clarification_loop.py"),
    ("collision-safe target resolution", "apply_collision_safe_target_resolution.py"),
    ("truthful ordinary-conversation streaming", "apply_truthful_conversation_streaming.py"),
    ("deterministic utility.time", "apply_deterministic_utility_time.py"),
    ("project-free Research execution", "apply_project_free_research_execution.py"),
    ("semantic durable steering", "apply_semantic_durable_steering.py"),
    ("protocol-v3 durable timestamp wait", "apply_protocol_v3_timestamp_wait.py"),
    ("bounded protocol-v3 delegate", "apply_bounded_protocol_v3_delegate.py"),
    ("scope-changing steering continuation", "apply_scope_changing_steering_continuation.py"),
    ("awaiting-approval steering continuation", "apply_idle_steering_continuation.py"),
    ("Research restart reconciliation", "apply_research_restart_reconciliation.py"),
    ("Research optional archive guard", "apply_research_optional_archive_guard.py"),
    ("Research archive degradation", "apply_research_archive_degradation.py"),
    ("delegate recovery qualification", "apply_delegate_recovery_qualification.py"),
    ("continuation handoff and activity projection", "apply_continuation_handoff_activity_projection.py"),
    ("authority convergence qualification", "apply_authority_convergence_qualification.py"),
    ("human-readable failure projection", "apply_human_readable_failure_projection.py"),
]

FOCUSED_TESTS = [
    "test/product/kristin_conversation_session_test.dart",
    "test/product/advanced_same_conversation_contract_test.dart",
    "test/product/task_kernel/semantic_slash_understanding_test.dart",
    "test/product/blocking_clarification_contract_test.dart",
    "test/product/chat_target_collision_test.dart",
    "test/product/truthful_conversation_streaming_test.dart",
    "test/product/utility_time_test.dart",
    "test/product/task_kernel/research_task_family_execution_test.dart",
    "test/product/semantic_durable_steering_test.dart",
    "test/product/runner_deferred_timestamp_wait_contract_test.dart",
    "test/product/runner_bounded_delegate_contract_test.dart",
    "test/product/steering_scope_continuation_contract_test.dart",
    "test/product/steering_idle_continuation_contract_test.dart",
    "test/product/task_kernel/research_restart_reconciliation_test.dart",
    "test/product/research_optional_archive_contract_test.dart",
    "test/product/research_archive_degradation_contract_test.dart",
    "test/product/runner_delegate_recovery_contract_test.dart",
    "test/product/chat_continuation_activity_contract_test.dart",
    "test/product/authority_convergence_contract_test.dart",
    "test/product/chat_failure_projection_contract_test.dart",
]


def run(cmd: list[str], *, cwd: Path | None = None) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, check=True)


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(root), *args],
        text=True,
        stderr=subprocess.STDOUT,
    ).strip()


def verify_base(root: Path, *, allow_head_mismatch: bool, allow_dirty: bool) -> None:
    if not (root / ".git").exists():
        raise SystemExit(f"{root} is not a Git checkout")
    head = git(root, "rev-parse", "HEAD")
    if head != EXPECTED_HEAD and not allow_head_mismatch:
        raise SystemExit(
            f"refusing HEAD {head}; expected recovered head {EXPECTED_HEAD}. "
            "Use --allow-head-mismatch only after reviewing source drift."
        )
    dirty = git(root, "status", "--porcelain")
    if dirty and not allow_dirty:
        raise SystemExit(
            "checkout is already dirty; refusing to mix the development bundle "
            "with unknown work. Use --allow-dirty only intentionally."
        )


def _changed_dart(root: Path) -> list[str]:
    status = git(root, "status", "--porcelain=v1", "--untracked-files=all")
    selected: set[str] = set()
    for line in status.splitlines():
        if len(line) < 4:
            continue
        relative = line[3:].split(" -> ")[-1].replace("\\", "/")
        if relative.endswith(".dart") and (root / relative).is_file():
            selected.add(relative)
    return sorted(selected)


def optional_verify(root: Path) -> None:
    """Run bounded local checks when the checkout has the required tools.

    For full repository qualification use qualify_real_checkout.py. This helper
    intentionally does not regenerate SOURCE_MANIFEST.sha256.
    """
    dart = shutil.which("dart")
    flutter = shutil.which("flutter")
    if dart:
        changed = _changed_dart(root)
        if changed:
            run([dart, "format", *changed], cwd=root)
        else:
            print("SKIP: no changed Dart files to format.")
    else:
        print("SKIP: dart not found; formatting was not run.")
    if flutter:
        run([flutter, "analyze", "--no-pub", "--fatal-infos", "--fatal-warnings"], cwd=root)
        existing = [path for path in FOCUSED_TESTS if (root / path).exists()]
        if existing:
            run([flutter, "test", "--no-pub", "--concurrency=1", *existing], cwd=root)
    else:
        print("SKIP: flutter not found; analyzer/tests were not run.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", type=Path, help="path to the recovered kris.ai checkout")
    parser.add_argument("--apply", action="store_true", help="apply all guarded source slices")
    parser.add_argument(
        "--verify",
        action="store_true",
        help="after applying, run bounded formatter/analyzer/focused tests when tools exist",
    )
    parser.add_argument("--allow-head-mismatch", action="store_true")
    parser.add_argument("--allow-dirty", action="store_true")
    args = parser.parse_args()

    if not args.apply:
        parser.error("--apply is required; inspect individual scripts with --diff first")

    root = args.repo.resolve()
    bundle = Path(__file__).resolve().parent
    verify_base(
        root,
        allow_head_mismatch=args.allow_head_mismatch,
        allow_dirty=args.allow_dirty,
    )

    for index, (label, script_name) in enumerate(SLICES, start=1):
        script = bundle / script_name
        if not script.exists():
            raise SystemExit(f"missing bundle script: {script_name}")
        print(f"\n[{index}/{len(SLICES)}] {label}")
        cmd = [sys.executable, str(script), str(root), "--apply"]
        if script_name == "apply_one_kristin_state_convergence.py":
            if args.allow_head_mismatch:
                cmd.append("--allow-head-mismatch")
            if args.allow_dirty:
                cmd.append("--allow-dirty")
        elif args.allow_head_mismatch:
            cmd.append("--allow-head-drift")
        run(cmd)

    print("\nAll guarded development slices applied to the local worktree.")
    print("No Git metadata or remote repository state was changed.")
    print("SOURCE_MANIFEST.sha256 was NOT regenerated.")
    if args.verify:
        optional_verify(root)
    else:
        print("Use qualify_real_checkout.py for the governed real-checkout qualification sequence.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
