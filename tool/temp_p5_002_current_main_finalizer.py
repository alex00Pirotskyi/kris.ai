#!/usr/bin/env python3
"""Validate and publish the exact current-main P5-002 Product candidate."""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BRANCH = "agent/gpt-gold/gs-016-p5-002-current-main"
BASE = "26dcf3eec5c435ce7fcba1044b1aa4110ddcf13a"
BASE_TREE = "f038ddf7a10779057348f089826cc966f61d087a"
WORKFLOW = Path(".github/workflows/temp-p5-002-current-main-finalizer.yml")
SCRIPT = Path("tool/temp_p5_002_current_main_finalizer.py")
EXPECTED_BLOBS = {
    "lib/product/p5_design_tokens.dart": "81a35a8fddffb5a947ec31536107d66dd353fe80",
    "lib/product/ui.dart": "06b4bd2cd34ae74d19ed698a4864dcf65841f033",
    "test/product/p5_design_tokens_test.dart": "de8da5053ae2732eb35a7990fc5a8e4614c31633",
    "test/product/source_contract_test.dart": "da2e80e8513a2e07d7bf0d22da8672d5ec081fe3",
}
FINAL_PATHS = {
    "SOURCE_MANIFEST.sha256",
    *EXPECTED_BLOBS,
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


def verify_transport(trigger: str) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", trigger):
        raise RuntimeError("GITHUB_SHA is missing or invalid")
    if run("git", "branch", "--show-current", capture=True) != BRANCH:
        raise RuntimeError("unexpected branch")
    if run("git", "rev-parse", "HEAD", capture=True) != trigger:
        raise RuntimeError("checkout does not match exact trigger head")
    run("git", "merge-base", "--is-ancestor", BASE, trigger)
    if run("git", "rev-parse", f"{BASE}^{{tree}}", capture=True) != BASE_TREE:
        raise RuntimeError("protected-main base tree changed unexpectedly")
    for path, expected in EXPECTED_BLOBS.items():
        actual = run("git", "hash-object", path, capture=True)
        if actual != expected:
            raise RuntimeError(
                f"validated P5 source blob drift for {path}: {actual} != {expected}"
            )


def validate() -> None:
    run("flutter", "pub", "get")
    run("python3", "tool/dart_format_scope.py", "--check")
    run(
        "flutter",
        "analyze",
        "--no-pub",
        "--fatal-warnings",
        "--fatal-infos",
    )
    run(
        "flutter",
        "test",
        "--no-pub",
        "--concurrency=1",
        "--reporter=expanded",
        "test/product/p5_design_tokens_test.dart",
        "test/product/source_contract_test.dart",
    )
    run(
        "flutter",
        "test",
        "--no-pub",
        "--concurrency=1",
        "--reporter=expanded",
    )
    run("npm", "ci", "--prefix", "automation_host")
    run("npm", "test", "--prefix", "automation_host")


def finalize_manifest() -> None:
    for path in (ROOT / WORKFLOW, ROOT / SCRIPT):
        if not path.is_file():
            raise RuntimeError(f"missing temporary finalizer path: {path.relative_to(ROOT)}")
        path.unlink()
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    first = (ROOT / "SOURCE_MANIFEST.sha256").read_bytes()
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    if (ROOT / "SOURCE_MANIFEST.sha256").read_bytes() != first:
        raise RuntimeError("SOURCE_MANIFEST.sha256 is not byte-stable")
    run("python3", "tool/p1a_text_eof_contract_test.py", "--project", ".")


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
            f"exact P5-002 scope mismatch: expected {sorted(FINAL_PATHS)}, got {paths}"
        )
    for temporary in (WORKFLOW.as_posix(), SCRIPT.as_posix()):
        if temporary in paths or (ROOT / temporary).exists():
            raise RuntimeError(f"temporary finalizer survived publication scope: {temporary}")
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
        "feat(p5): add accessible semantic design tokens",
        "-m",
        "Rematerialize the validated P5-002 design system on current protected "
        "main with readable typography, high-contrast and reduced-motion "
        "themes, exact source contracts, full tests, and a canonical manifest.",
    )
    run("git", "diff", "--exit-code")
    run("git", "diff", "--cached", "--exit-code")
    if run("git", "status", "--porcelain=v1", capture=True):
        raise RuntimeError("final candidate worktree is dirty")
    head = run("git", "rev-parse", "HEAD", capture=True)
    tree = run("git", "rev-parse", "HEAD^{tree}", capture=True)
    run("git", "push", "origin", f"HEAD:refs/heads/{BRANCH}")
    print(f"P5_002_CURRENT_MAIN_COMMIT={head}")
    print(f"P5_002_CURRENT_MAIN_TREE={tree}")
    print("P5_002_CURRENT_MAIN_PATHS=" + ",".join(paths))


def main() -> int:
    trigger = os.environ.get("GITHUB_SHA", "").strip()
    verify_transport(trigger)
    validate()
    finalize_manifest()
    publish(prove_scope())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
