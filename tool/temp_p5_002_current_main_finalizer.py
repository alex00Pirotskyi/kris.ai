#!/usr/bin/env python3
# Reconcile P5-002 onto the exact validator-repaired protected main.
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BRANCH = "agent/gpt-gold/gs-016-p5-002-current-main"
BASE = "fb8ebae9ef8845d306c61e355bafc01ea95165f1"
BASE_TREE = "6b5f6fd82e6b0c2c83caf9983b3b921a7192c92f"
WORKFLOW = Path(".github/workflows/temp-p5-002-current-main-finalizer.yml")
SCRIPT = Path("tool/temp_p5_002_current_main_finalizer.py")
FINAL_PATHS = {
    "SOURCE_MANIFEST.sha256",
    "lib/product/p5_design_tokens.dart",
    "lib/product/ui.dart",
    "test/product/p5_design_tokens_test.dart",
    "test/product/source_contract_test.dart",
}
EXPECTED_BLOBS = {
    "lib/product/p5_design_tokens.dart": "81a35a8fddffb5a947ec31536107d66dd353fe80",
    "lib/product/ui.dart": "06b4bd2cd34ae74d19ed698a4864dcf65841f033",
    "test/product/p5_design_tokens_test.dart": "de8da5053ae2732eb35a7990fc5a8e4614c31633",
    "test/product/source_contract_test.dart": "f57f8279692e5cc83dfe1c427090b4221dd0543a",
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
    for relative, expected in EXPECTED_BLOBS.items():
        actual = run("git", "hash-object", relative, capture=True)
        if actual != expected:
            raise RuntimeError(
                f"unexpected source blob for {relative}: {actual} != {expected}"
            )
    validator = (ROOT / "tool/validate_release.py").read_text(encoding="utf-8")
    for marker in (
        "_load_governed_product_library_files()",
        'relative.endswith("_design_tokens.dart")',
        "*design_token_sources",
    ):
        if marker not in validator:
            raise RuntimeError(f"validator repair marker missing: {marker}")


def patch_source_contract() -> None:
    path = ROOT / "test/product/source_contract_test.dart"
    text = path.read_text(encoding="utf-8")

    inventory_anchor = "        'lib/product/p2_terminal_model.dart',\n"
    inventory_addition = (
        inventory_anchor + "        'lib/product/p5_design_tokens.dart',\n"
    )
    text = replace_once(
        text,
        inventory_anchor,
        inventory_addition,
        "governed P5 design-token inventory",
    )

    validator_test = '''    test('release validator follows governed design-token modules', () {
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
    semantic_test = '''    test('application wires semantic accessibility themes', () {
      final ui = source('lib/product/ui.dart');
      expect(ui, contains("import 'p5_design_tokens.dart';"));
      expect(ui, contains('highContrastTheme: _studioTheme('));
      expect(ui, contains('highContrastDarkTheme: _studioTheme('));
      expect(ui, contains('accessibilityFeatures.disableAnimations'));
      expect(ui, contains('P5DesignSystem.themeTransitionDuration'));
      expect(ui, contains('WidgetsBinding.instance.addObserver(this)'));
      expect(ui, contains('WidgetsBinding.instance.removeObserver(this)'));
    });

'''
    text = replace_once(
        text,
        validator_test,
        validator_test + semantic_test,
        "P5 semantic-theme source regression",
    )

    ui_anchor = "        source('lib/product/ui.dart'),\n"
    text = replace_once(
        text,
        ui_anchor,
        ui_anchor + "        source('lib/product/p5_design_tokens.dart'),\n",
        "Flutter compatibility P5 source aggregate",
    )

    path.write_text(text, encoding="utf-8", newline="\n")


def remove_transport() -> None:
    for relative in (WORKFLOW, SCRIPT):
        path = ROOT / relative
        if not path.is_file():
            raise RuntimeError(f"missing temporary path: {relative}")
        path.unlink()


def restore_validator_reports() -> None:
    for relative in (
        "release/validation_report.json",
        "release/VALIDATION_REPORT.md",
    ):
        tracked = subprocess.run(
            ["git", "ls-files", "--error-unmatch", relative],
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        path = ROOT / relative
        if tracked.returncode == 0:
            run("git", "restore", "--source=HEAD", "--", relative)
        elif path.exists():
            path.unlink()


def restore_generated_test_outputs() -> None:
    allowed = FINAL_PATHS | {WORKFLOW.as_posix(), SCRIPT.as_posix()}
    changed = run("git", "diff", "--name-only", capture=True).splitlines()
    for relative in changed:
        if relative and relative not in allowed:
            run("git", "restore", "--source=HEAD", "--", relative)
    untracked = run(
        "git", "ls-files", "--others", "--exclude-standard", capture=True
    ).splitlines()
    for relative in untracked:
        if not relative or relative in allowed:
            continue
        target = ROOT / relative
        if target.is_symlink() or target.is_file():
            target.unlink()
        elif target.is_dir():
            shutil.rmtree(target)


def refresh_manifest_twice() -> None:
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    first = (ROOT / "SOURCE_MANIFEST.sha256").read_bytes()
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    if (ROOT / "SOURCE_MANIFEST.sha256").read_bytes() != first:
        raise RuntimeError("SOURCE_MANIFEST.sha256 is not byte-stable")
    run("python3", "tool/p1a_text_eof_contract_test.py", "--project", ".")


def validate() -> None:
    patch_source_contract()
    run("flutter", "pub", "get")
    run("python3", "tool/dart_format_scope.py", "--write")
    run("python3", "tool/dart_format_scope.py", "--check")
    remove_transport()
    refresh_manifest_twice()
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
    restore_generated_test_outputs()
    refresh_manifest_twice()


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
        "feat(p5-002): reconcile semantic design tokens with current main",
        "-m",
        "Preserve the exact validated P5-002 product blobs while carrying the "
        "separate governed validator repair from protected main. Keep the "
        "effective candidate limited to five product/source-manifest paths.",
    )
    run("git", "diff", "--exit-code")
    run("git", "diff", "--cached", "--exit-code")
    if run("git", "status", "--porcelain=v1", capture=True):
        raise RuntimeError("final P5-002 candidate worktree is dirty")
    head = run("git", "rev-parse", "HEAD", capture=True)
    tree = run("git", "rev-parse", "HEAD^{tree}", capture=True)
    run("git", "push", "origin", f"HEAD:refs/heads/{BRANCH}")
    print(f"P5_FINAL_COMMIT={head}")
    print(f"P5_FINAL_TREE={tree}")
    print("P5_FINAL_PATHS=" + ",".join(paths))


def main() -> int:
    trigger = os.environ.get("GITHUB_SHA", "").strip()
    verify_transport(trigger)
    validate()
    publish(prove_scope())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
