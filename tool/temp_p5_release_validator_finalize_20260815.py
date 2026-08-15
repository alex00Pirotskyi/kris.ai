#!/usr/bin/env python3
"""Publish a clean P5 candidate with the release validator aligned to the shipped shell."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BRANCH = "agent/f/P5-001-information-architecture"
CLEAN_P5_BASE = "96f653e5f025a0cf6b82a9c5281b457f610fc5dd"
EXPECTED_MAIN = "67e6e0314877d4ff3233d3e11e0743dd7562de55"


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


def reset_to_clean_candidate(transport_head: str) -> None:
    if run("git", "branch", "--show-current", capture=True) != BRANCH:
        raise RuntimeError("unexpected branch")
    if run("git", "rev-parse", "HEAD", capture=True) != transport_head:
        raise RuntimeError("checkout is not bound to GITHUB_SHA")
    run("git", "merge-base", "--is-ancestor", CLEAN_P5_BASE, transport_head)
    run(
        "git",
        "fetch",
        "--no-tags",
        "origin",
        "+refs/heads/main:refs/remotes/origin/main",
    )
    if run("git", "rev-parse", "refs/remotes/origin/main", capture=True) != EXPECTED_MAIN:
        raise RuntimeError("protected main moved; recompute instead of landing stale source")
    run("git", "read-tree", "--reset", "-u", CLEAN_P5_BASE)


def patch_release_validator() -> None:
    path = ROOT / "tool/validate_release.py"
    text = path.read_text(encoding="utf-8")
    old = '''    if "home: ChatStudio(" not in ui:
        shell = read(ROOT / "lib/product/p2_app_shell.dart")
        shell_is_chat_first = (
            "home: P2KristinShell(" in ui
            and "chat: ChatStudio(" in ui
            and "var _index = 0;" in shell
            and source_contains(
                shell,
                "final pages = <Widget>[ widget.chat, "
                "widget.ownerMode.buildWorkspace(",
            )
        )
        if not shell_is_chat_first:
            failures.append(
                "the application does not open in ChatStudio or the "
                "governed chat-first P2 shell"
            )
'''
    new = '''    if "home: ChatStudio(" not in ui:
        shell = read(ROOT / "lib/product/p2_app_shell.dart")
        p2_shell_is_chat_first = (
            "home: P2KristinShell(" in ui
            and "chat: ChatStudio(" in ui
            and "var _index = 0;" in shell
            and source_contains(
                shell,
                "final pages = <Widget>[ widget.chat, "
                "widget.ownerMode.buildWorkspace(",
            )
        )
        integrated_shell_is_chat_first = (
            "home: KristinMainShell(" in ui
            and "chat: ChatStudio(" in ui
            and "var _index = 0;" in ui
            and source_contains(
                ui,
                "final pages = <Widget>[ widget.chat, "
                "P5InformationArchitecturePrototype( "
                "controller: _experienceController, ), "
                "widget.ownerMode.buildWorkspace(",
            )
        )
        if not (p2_shell_is_chat_first or integrated_shell_is_chat_first):
            failures.append(
                "the application does not open in ChatStudio, the governed "
                "chat-first P2 shell, or the governed chat-first integrated shell"
            )
'''
    text = replace_once(text, old, new, "chat-first release validator")
    path.write_text(text, encoding="utf-8", newline="\n")


def validate() -> None:
    run("flutter", "pub", "get")
    run("python3", "tool/dart_format_scope.py", "--check")
    run("flutter", "analyze", "--no-pub", "--fatal-warnings", "--fatal-infos")
    run(
        "flutter",
        "test",
        "--no-pub",
        "--concurrency=1",
        "--reporter",
        "expanded",
    )
    run("npm", "ci", "--prefix", "automation_host")
    run("npm", "test", "--prefix", "automation_host")

    sys.path.insert(0, str(ROOT / "tool"))
    spec = importlib.util.spec_from_file_location(
        "p5_validate_release", ROOT / "tool/validate_release.py"
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load release validator")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    module.checks.clear()
    module.check_chat_workspace_ux()
    failures = [
        check.detail
        for check in module.checks
        if check.blocking and check.status != "passed"
    ]
    if failures:
        raise RuntimeError(f"chat workspace release validation failed: {failures}")

    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    first = (ROOT / "SOURCE_MANIFEST.sha256").read_bytes()
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    if (ROOT / "SOURCE_MANIFEST.sha256").read_bytes() != first:
        raise RuntimeError("SOURCE_MANIFEST.sha256 is not byte-stable")
    run("python3", "tool/p1a_text_eof_contract_test.py", "--project", ".")


def prove_scope() -> None:
    run("git", "add", "-A")
    run("git", "diff", "--cached", "--check")
    paths = run(
        "git",
        "diff",
        "--cached",
        "--name-only",
        EXPECTED_MAIN,
        "--",
        capture=True,
    ).splitlines()
    exact = {
        "SOURCE_MANIFEST.sha256",
        "config/p2_source_inventory.v1.json",
        "lib/product/ui.dart",
        "lib/product/p2_product_runtime_bootstrap.dart",
        "test/product/source_contract_test.dart",
        "test/product/p5_main_shell_integration_test.dart",
        "test/product/p2_owner_mode_failure_presentation_test.dart",
        "tool/validate_release.py",
    }
    prefixes = (
        "lib/product/p5_information_architecture/",
        "test/product/p5_information_architecture/",
    )
    unauthorized = [
        path for path in paths if path not in exact and not path.startswith(prefixes)
    ]
    if unauthorized:
        raise RuntimeError(f"unauthorized Product paths: {unauthorized}")
    if "tool/validate_release.py" not in paths:
        raise RuntimeError("release-validator compatibility repair is missing")
    for forbidden in (
        ".github/workflows/temp-p5-main-delivery-20260815.yml",
        "tool/temp_p5_main_delivery_20260815.py",
        "tool/temp_p5_patch_materializer_20260815.py",
        "tool/temp_p5_release_validator_finalize_20260815.py",
        "lib/p5_ia_preview.dart",
    ):
        if forbidden in paths:
            raise RuntimeError(f"temporary or stale path leaked into candidate: {forbidden}")
    print("Exact current-main Product diff:")
    print("\n".join(paths))


def publish(transport_head: str) -> tuple[str, str]:
    run("git", "config", "user.name", "github-actions[bot]")
    run(
        "git",
        "config",
        "user.email",
        "41898282+github-actions[bot]@users.noreply.github.com",
    )
    tree = run("git", "write-tree", capture=True)
    message = (
        "feat(p5): finalize runnable integrated experience shell\n\n"
        "Preserve the exact validated P5 Product tree, align the release "
        "validator with the governed chat-first integrated shell, and "
        "regenerate the canonical source manifest.\n"
    )
    commit = subprocess.run(
        [
            "git",
            "commit-tree",
            tree,
            "-p",
            transport_head,
            "-p",
            EXPECTED_MAIN,
        ],
        cwd=ROOT,
        input=message,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout.strip()
    run("git", "reset", "--hard", commit)
    if run("git", "rev-parse", "HEAD^{tree}", capture=True) != tree:
        raise RuntimeError("published candidate tree changed")
    if run("git", "status", "--porcelain=v1", capture=True):
        raise RuntimeError("candidate worktree is not clean")
    run("git", "push", "origin", f"{commit}:refs/heads/{BRANCH}")
    return commit, tree


def main() -> int:
    transport_head = os.environ.get("GITHUB_SHA", "").strip()
    if not re.fullmatch(r"[0-9a-f]{40}", transport_head):
        raise RuntimeError("GITHUB_SHA is missing or invalid")
    reset_to_clean_candidate(transport_head)
    patch_release_validator()
    validate()
    prove_scope()
    commit, tree = publish(transport_head)
    print(f"P5_FINAL_COMMIT={commit}")
    print(f"P5_FINAL_TREE={tree}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
