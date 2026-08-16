#!/usr/bin/env python3
"""Make the owner-risk promotion workflow exact-head and PR-bound."""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BRANCH = "agent/gpt-gold/gs-003c-p2-promotion-current-main"
BASE = "e4f66ce5a95870cad342bbf9aaf89f94dc768f58"
CLEAN_PARENT = "78abfc812f1d7db572420876b081d4ffdec61e41"
CLEAN_PARENT_TREE = "dc1aec1bd8df788631410bf41c5973495d35fd4d"
WORKFLOW = Path(".github/workflows/temp-gs003-owner-risk-pr-trigger-finalizer.yml")
SCRIPT = Path("tool/temp_gs003_owner_risk_pr_trigger_finalizer.py")
OWNER_WORKFLOW = Path(".github/workflows/p1-p2-owner-risk-promotion-v71r12.yml")
FINAL_PATHS = {
    "SOURCE_MANIFEST.sha256",
    OWNER_WORKFLOW.as_posix(),
    "tool/p2_promotion_state_test.py",
    "tool/v71r12_exact_source_gate.py",
}


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(
        list(args),
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(args)}\n"
            f"{result.stdout or ''}"
        )
    return (result.stdout or "").strip()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def verify_transport(trigger: str) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", trigger):
        raise RuntimeError("GITHUB_SHA is missing or invalid")
    if run("git", "branch", "--show-current", capture=True) != BRANCH:
        raise RuntimeError("unexpected branch")
    if run("git", "rev-parse", "HEAD", capture=True) != trigger:
        raise RuntimeError("checkout does not match exact trigger head")
    run("git", "merge-base", "--is-ancestor", CLEAN_PARENT, trigger)
    if run("git", "rev-parse", f"{CLEAN_PARENT}^{{tree}}", capture=True) != CLEAN_PARENT_TREE:
        raise RuntimeError("clean promotion-repair parent tree changed unexpectedly")


def patch_workflow() -> None:
    path = ROOT / OWNER_WORKFLOW
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "on:\n  workflow_dispatch:\n  push:\n",
        "on:\n  workflow_dispatch:\n  pull_request:\n    branches:\n      - main\n  push:\n",
        "pull-request trigger",
    )
    text = replace_once(
        text,
        'env:\n  P1A_PYTHON_VERSION: "3.13.5"\n',
        'env:\n  OWNER_RISK_CANDIDATE_SHA: ${{ github.event.pull_request.head.sha || github.sha }}\n  P1A_PYTHON_VERSION: "3.13.5"\n',
        "candidate identity environment",
    )
    text = replace_once(
        text,
        "      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1\n        with:\n          persist-credentials: false\n",
        "      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1\n        with:\n          ref: ${{ env.OWNER_RISK_CANDIDATE_SHA }}\n          fetch-depth: 0\n          persist-credentials: false\n\n      - name: Assert exact candidate checkout\n        shell: bash\n        run: |\n          set -euo pipefail\n          test \"$(git rev-parse HEAD)\" = \"$OWNER_RISK_CANDIDATE_SHA\"\n",
        "exact candidate checkout",
    )
    old_source = '--source-commit "${{ github.sha }}"'
    new_source = '--source-commit "${{ env.OWNER_RISK_CANDIDATE_SHA }}"'
    if text.count(old_source) != 2:
        raise RuntimeError(
            f"candidate source identity: expected two matches, found {text.count(old_source)}"
        )
    text = text.replace(old_source, new_source)
    path.write_text(text, encoding="utf-8", newline="\n")


def remove_transport() -> None:
    for relative in (WORKFLOW, SCRIPT):
        path = ROOT / relative
        if not path.is_file():
            raise RuntimeError(f"missing temporary path: {relative}")
        path.unlink()


def refresh_manifest_twice() -> None:
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    first = (ROOT / "SOURCE_MANIFEST.sha256").read_bytes()
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    if (ROOT / "SOURCE_MANIFEST.sha256").read_bytes() != first:
        raise RuntimeError("SOURCE_MANIFEST.sha256 is not byte-stable")
    run("python3", "tool/p1a_text_eof_contract_test.py", "--project", ".")


def validate() -> None:
    patch_workflow()
    remove_transport()
    refresh_manifest_twice()
    run("python3", "-m", "py_compile", "tool/v71r12_exact_source_gate.py", "tool/p2_promotion_state_test.py")
    run("python3", "tool/p2_evidence_state.py", "--project", ".")
    run("python3", "tool/p2_evidence_state_test.py")
    run("python3", "tool/p2_promotion_state_test.py")
    run("ruby", "tool/workflow_integrity_test.rb", ".")
    run("git", "diff", "--check")


def prove_scope() -> list[str]:
    run("git", "add", "-A")
    run("git", "diff", "--cached", "--check")
    paths = run(
        "git",
        "diff",
        "--cached",
        "--name-only",
        BASE,
        "--",
        capture=True,
    ).splitlines()
    if set(paths) != FINAL_PATHS:
        raise RuntimeError(
            f"exact promotion candidate scope mismatch: expected {sorted(FINAL_PATHS)}, got {paths}"
        )
    for temporary in (WORKFLOW.as_posix(), SCRIPT.as_posix()):
        if temporary in paths or (ROOT / temporary).exists():
            raise RuntimeError(f"temporary finalizer survived: {temporary}")
    return paths


def publish(paths: list[str]) -> None:
    run("git", "config", "user.name", "github-actions[bot]")
    run(
        "git",
        "config",
        "user.email",
        "41898282+github-actions[bot]@users.noreply.github.com",
    )
    run(
        "git",
        "commit",
        "-m",
        "ci(p2): require exact-head owner-risk promotion on pull requests",
        "-m",
        "Run the full tri-platform owner-risk workflow before main landing, "
        "check out the immutable PR head rather than the merge ref, and bind "
        "packaging receipts to that exact candidate identity.",
    )
    run("git", "diff", "--exit-code")
    run("git", "diff", "--cached", "--exit-code")
    if run("git", "status", "--porcelain=v1", capture=True):
        raise RuntimeError("final owner-risk promotion candidate worktree is dirty")
    head = run("git", "rev-parse", "HEAD", capture=True)
    tree = run("git", "rev-parse", "HEAD^{tree}", capture=True)
    run("git", "push", "origin", f"HEAD:refs/heads/{BRANCH}")
    print(f"OWNER_RISK_PR_FINAL_COMMIT={head}")
    print(f"OWNER_RISK_PR_FINAL_TREE={tree}")
    print("OWNER_RISK_PR_FINAL_PATHS=" + ",".join(paths))


def main() -> int:
    trigger = os.environ.get("GITHUB_SHA", "").strip()
    verify_transport(trigger)
    validate()
    publish(prove_scope())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
