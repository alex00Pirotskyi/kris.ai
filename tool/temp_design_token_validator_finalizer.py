#!/usr/bin/env python3
"""Repair and validate the release gate's governed design-token discovery."""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BRANCH = "agent/gpt-gold/gs-003b-design-token-validator"
BASE = "26dcf3eec5c435ce7fcba1044b1aa4110ddcf13a"
BASE_TREE = "f038ddf7a10779057348f089826cc966f61d087a"
WORKFLOW = Path(".github/workflows/temp-design-token-validator-finalizer.yml")
SCRIPT = Path("tool/temp_design_token_validator_finalizer.py")
FINAL_PATHS = {
    "SOURCE_MANIFEST.sha256",
    "test/product/source_contract_test.dart",
    "tool/validate_release.py",
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
    run("git", "merge-base", "--is-ancestor", BASE, trigger)
    if run("git", "rev-parse", f"{BASE}^{{tree}}", capture=True) != BASE_TREE:
        raise RuntimeError("protected-main base tree changed unexpectedly")


def patch_validator() -> None:
    path = ROOT / "tool/validate_release.py"
    text = path.read_text(encoding="utf-8")
    old = '''    ui = read(ROOT / "lib/product/ui.dart")
    chat = read(ROOT / "lib/product/chat_studio.dart")
    ui_advanced = read(ROOT / "lib/product/ui_advanced.dart")
    ui_components = read(ROOT / "lib/product/ui_components.dart")
    all_ui = "\\n".join((ui, chat, ui_advanced, ui_components))
'''
    new = '''    ui = read(ROOT / "lib/product/ui.dart")
    chat = read(ROOT / "lib/product/chat_studio.dart")
    ui_advanced = read(ROOT / "lib/product/ui_advanced.dart")
    ui_components = read(ROOT / "lib/product/ui_components.dart")
    design_token_sources = [
        read(ROOT / relative)
        for relative in sorted(_load_governed_product_library_files())
        if relative.endswith("_design_tokens.dart")
    ]
    all_ui = "\\n".join(
        (ui, chat, ui_advanced, ui_components, *design_token_sources)
    )
'''
    path.write_text(
        replace_once(text, old, new, "governed design-token aggregate"),
        encoding="utf-8",
        newline="\n",
    )


def patch_source_contract() -> None:
    path = ROOT / "test/product/source_contract_test.dart"
    text = path.read_text(encoding="utf-8")
    marker = "    test('stale-source migration consumes governed inventories', () {"
    addition = '''    test('release validator follows governed design-token modules', () {
      final validator = source('tool/validate_release.py');
      expect(
        validator,
        contains('_load_governed_product_library_files()'),
      );
      expect(
        validator,
        contains('relative.endswith("_design_tokens.dart")'),
      );
      expect(validator, contains('*design_token_sources'));
    });

'''
    path.write_text(
        replace_once(text, marker, addition + marker, "validator source regression"),
        encoding="utf-8",
        newline="\n",
    )


def remove_transport_and_refresh_manifest() -> None:
    for path in (ROOT / WORKFLOW, ROOT / SCRIPT):
        if not path.is_file():
            raise RuntimeError(f"missing temporary path: {path.relative_to(ROOT)}")
        path.unlink()
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    first = (ROOT / "SOURCE_MANIFEST.sha256").read_bytes()
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    if (ROOT / "SOURCE_MANIFEST.sha256").read_bytes() != first:
        raise RuntimeError("SOURCE_MANIFEST.sha256 is not byte-stable")
    run("python3", "tool/p1a_text_eof_contract_test.py", "--project", ".")


def restore_validator_reports() -> None:
    for relative in (
        "release/validation_report.json",
        "release/VALIDATION_REPORT.md",
    ):
        result = subprocess.run(
            ["git", "ls-files", "--error-unmatch", relative],
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        path = ROOT / relative
        if result.returncode == 0:
            run("git", "restore", "--source=HEAD", "--", relative)
        elif path.exists():
            path.unlink()


def validate() -> None:
    run("flutter", "pub", "get")
    run("python3", "tool/dart_format_scope.py", "--write")
    run("python3", "tool/dart_format_scope.py", "--check")
    remove_transport_and_refresh_manifest()
    run("python3", "tool/validate_release.py", "--skip-tests")
    restore_validator_reports()
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
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    run("git", "diff", "--exit-code", "--", "SOURCE_MANIFEST.sha256")


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
            f"exact validator scope mismatch: expected {sorted(FINAL_PATHS)}, got {paths}"
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
        "fix(validation): discover governed design-token modules",
        "-m",
        "Make the Flutter compatibility release gate derive design-token "
        "sources from the closed governed product inventory, preserving the "
        "CardThemeData regression after theme extraction without weakening it.",
    )
    run("git", "diff", "--exit-code")
    run("git", "diff", "--cached", "--exit-code")
    if run("git", "status", "--porcelain=v1", capture=True):
        raise RuntimeError("final validator candidate worktree is dirty")
    head = run("git", "rev-parse", "HEAD", capture=True)
    tree = run("git", "rev-parse", "HEAD^{tree}", capture=True)
    run("git", "push", "origin", f"HEAD:refs/heads/{BRANCH}")
    print(f"VALIDATOR_FINAL_COMMIT={head}")
    print(f"VALIDATOR_FINAL_TREE={tree}")
    print("VALIDATOR_FINAL_PATHS=" + ",".join(paths))


def main() -> int:
    trigger = os.environ.get("GITHUB_SHA", "").strip()
    verify_transport(trigger)
    patch_validator()
    patch_source_contract()
    validate()
    publish(prove_scope())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
